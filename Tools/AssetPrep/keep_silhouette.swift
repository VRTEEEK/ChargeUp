// After cutout.swift: keeps only a badge's solid silhouette and drops the
// soft painted glow around it, which on generated art still carries the
// grey of the checkerboard it was painted over and reads as a pale haze.
// Solid means strongly coloured (gold, blue) or dark (navy); small gaps
// are closed and everything enclosed is filled, so pale details inside the
// badge (a night sky, glass highlights) are kept whole. The app adds its
// own glow. Swirls that merely touch the badge are cut free and dropped.
//
//   swiftc -O keep_silhouette.swift -o keep_silhouette
//   ./keep_silhouette <in.png> <out.png> <minSaturation 0...1> <darkBelow 0...1> <closeRadiusPx> [openRadiusPx]
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
let minSat = Float(a[3])!, dark = Float(a[4])!, radius = Int(a[5])!
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let w = img.width, h = img.height, n = w * h
var buf = [UInt8](repeating: 0, count: n * 4)
let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

// Solid pixels.
var solid = [UInt8](repeating: 0, count: n)
for i in 0..<n {
    let alpha = Float(buf[i * 4 + 3]) / 255
    guard alpha > 0.5 else { continue }
    let r = Float(buf[i * 4]) / 255 / alpha, g = Float(buf[i * 4 + 1]) / 255 / alpha, b = Float(buf[i * 4 + 2]) / 255 / alpha
    let mx = max(r, g, b), mn = min(r, g, b)
    let sat = mx > 0 ? (mx - mn) / mx : 0
    if sat >= minSat || mx < dark { solid[i] = 1 }
}

// Square max (dilate) or min (erode), separable.
func filter(_ m: [UInt8], _ r: Int, dilate: Bool) -> [UInt8] {
    var tmp = m, out = m
    for y in 0..<h { for x in 0..<w {
        var v: UInt8 = dilate ? 0 : 1
        for dx in -r...r { let xx = min(w - 1, max(0, x + dx)); v = dilate ? max(v, m[y * w + xx]) : min(v, m[y * w + xx]) }
        tmp[y * w + x] = v
    } }
    for y in 0..<h { for x in 0..<w {
        var v: UInt8 = dilate ? 0 : 1
        for dy in -r...r { let yy = min(h - 1, max(0, y + dy)); v = dilate ? max(v, tmp[yy * w + x]) : min(v, tmp[yy * w + x]) }
        out[y * w + x] = v
    } }
    return out
}
let closed = filter(filter(solid, radius, dilate: true), radius, dilate: false)

// Everything not reachable from the border through non-solid pixels is inside.
var outside = [UInt8](repeating: 0, count: n)
var stack: [Int] = []
for x in 0..<w { stack.append(x); stack.append((h - 1) * w + x) }
for y in 0..<h { stack.append(y * w); stack.append(y * w + w - 1) }
while let i = stack.popLast() {
    guard outside[i] == 0, closed[i] == 0 else { continue }
    outside[i] = 1
    let x = i % w, y = i / w
    if x > 0 { stack.append(i - 1) }; if x < w - 1 { stack.append(i + 1) }
    if y > 0 { stack.append(i - w) }; if y < h - 1 { stack.append(i + w) }
}

// Only the badge's main body: find it with everything thinner than
// 2 x openRadius trimmed away (so a swirl that merely touches the badge
// comes loose), take the largest piece, then keep every part of the
// silhouette within a few pixels of it, so thin details on the badge itself
// (ribbon tips, star points) stay whole.
let openRadius = a.count > 6 ? Int(a[6])! : 10
var inside = [UInt8](repeating: 0, count: n)
for i in 0..<n where outside[i] == 0 { inside[i] = 1 }
let opened = filter(filter(inside, openRadius, dilate: false), openRadius, dilate: true)
var label = [Int32](repeating: -1, count: n)
var sizes: [Int] = []
for start in 0..<n where opened[start] == 1 && label[start] < 0 {
    let id = Int32(sizes.count)
    var size = 0
    stack = [start]
    while let i = stack.popLast() {
        guard opened[i] == 1, label[i] < 0 else { continue }
        label[i] = id
        size += 1
        let x = i % w, y = i / w
        if x > 0 { stack.append(i - 1) }; if x < w - 1 { stack.append(i + 1) }
        if y > 0 { stack.append(i - w) }; if y < h - 1 { stack.append(i + w) }
    }
    sizes.append(size)
}
if let largest = sizes.indices.max(by: { sizes[$0] < sizes[$1] }) {
    var body = [UInt8](repeating: 0, count: n)
    for i in 0..<n where label[i] == Int32(largest) { body[i] = 1 }
    let near = filter(body, openRadius + 3, dilate: true)
    for i in 0..<n where near[i] == 0 { outside[i] = 1 }
    print("pieces \(sizes.count) after trimming thin parts; kept the main body and what lies within \(openRadius + 3) px of it")
}

// Keep the silhouette, its edge softened over one pixel.
var kept = 0
for y in 0..<h { for x in 0..<w {
    var inside = 0, count = 0
    for dy in -1...1 { for dx in -1...1 {
        let xx = x + dx, yy = y + dy
        guard xx >= 0, xx < w, yy >= 0, yy < h else { continue }
        count += 1
        if outside[yy * w + xx] == 0 { inside += 1 }
    } }
    let k = Float(inside) / Float(count)
    let i = y * w + x
    if k > 0.5 { kept += 1 }
    for c in 0..<4 { buf[i * 4 + c] = UInt8((Float(buf[i * 4 + c]) * k).rounded()) }
} }
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
print(String(format: "kept the silhouette: %.1f%% of the canvas", 100 * Double(kept) / Double(n)))
