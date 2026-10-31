// Rewrites a model's metallic and roughness maps so its gold reads as
// polished brass: every warm, saturated texel of the colour map (gold, brass,
// amber) gets the brass values, everything else (enamel, paint) keeps its
// own. Meshy's port came with gold at about metallic 0.62 and roughness 0.46,
// which looks like plastic.
//
//   swiftc -O brass_from_colour.swift -o brass_from_colour
//   ./brass_from_colour <colour.jpg> <metallic.png> <roughness.png> <metallic 0...1> <roughness 0...1>
//
// The two PNGs are rewritten in place at their own size, 8-bit grey with no
// colour profile, for textures read as raw.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
let colourURL = URL(fileURLWithPath: a[1]), metalURL = URL(fileURLWithPath: a[2]), roughURL = URL(fileURLWithPath: a[3])
let brassMetal = UInt8((Double(a[4])! * 255).rounded()), brassRough = UInt8((Double(a[5])! * 255).rounded())

func image(_ url: URL) -> CGImage {
    CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil)!
}
func pixels(_ img: CGImage, size: Int, grey: Bool) -> [UInt8] {
    var buf = [UInt8](repeating: 0, count: size * size * (grey ? 1 : 4))
    let ctx = CGContext(data: &buf, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * (grey ? 1 : 4),
                        space: grey ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: grey ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .medium
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: size, height: size))
    return buf
}
func write(_ grey: [UInt8], size: Int, to url: URL) {
    let provider = CGDataProvider(data: Data(grey) as CFData)!
    let out = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: size,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, out, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write failed \(url.path)") }
}

let metalImage = image(metalURL)
let size = metalImage.width
let colour = pixels(image(colourURL), size: size, grey: false)
var metal = pixels(metalImage, size: size, grey: true), rough = pixels(image(roughURL), size: size, grey: true)
var brass = 0
for i in 0..<(size * size) {
    let r = Float(colour[i * 4]), g = Float(colour[i * 4 + 1]), b = Float(colour[i * 4 + 2])
    let mx = max(r, g, b)
    // Warm and saturated: red >= green >= blue, well away from grey.
    guard mx > 20, r >= g, g >= b, (mx - b) / mx > 0.25 else { continue }
    metal[i] = brassMetal
    rough[i] = brassRough
    brass += 1
}
write(metal, size: size, to: metalURL)
write(rough, size: size, to: roughURL)
print(String(format: "brass on %.1f%% of texels (metallic %.2f, roughness %.2f); the rest kept", 100 * Double(brass) / Double(size * size),
             Double(brassMetal) / 255, Double(brassRough) / 255))
