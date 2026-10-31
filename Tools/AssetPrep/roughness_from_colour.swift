// Writes a roughness map for a model with one atlas: each texel gets the
// foliage value where the colour map is green-dominant and the bark value
// everywhere else. For Meshy trees, whose own roughness map sits around
// 0.56 everywhere and reads as plastic in RealityKit.
//
//   swiftc -O roughness_from_colour.swift -o roughness_from_colour
//   ./roughness_from_colour <colour.jpg> <out.png> <size> <foliage 0...1> <bark 0...1>
//
// The output is 8-bit grey with no colour profile, for a texture read as raw.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
let size = Int(a[3])!, foliage = Double(a[4])!, bark = Double(a[5])!
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil)!
let colour = CGImageSourceCreateImageAtIndex(src, 0, nil)!
var rgba = [UInt8](repeating: 0, count: size * size * 4)
let ctx = CGContext(data: &rgba, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .medium
ctx.draw(colour, in: CGRect(x: 0, y: 0, width: size, height: size))

let leafValue = UInt8((foliage * 255).rounded()), barkValue = UInt8((bark * 255).rounded())
var grey = [UInt8](repeating: barkValue, count: size * size)
var leaves = 0
for i in 0..<(size * size) {
    let r = Double(rgba[i * 4]), g = Double(rgba[i * 4 + 1]), b = Double(rgba[i * 4 + 2])
    // Green-dominant: leaves, and the moss on the bark, which should be as matte.
    if g > r * 1.05 && g > b * 1.15 { grey[i] = leafValue; leaves += 1 }
}
let provider = CGDataProvider(data: Data(grey) as CFData)!
let out = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: size,
                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, out, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
print(String(format: "wrote %@ %dx%d: foliage %.2f on %.1f%% of texels, bark %.2f on the rest",
             (a[2] as NSString).lastPathComponent, size, size, foliage, 100.0 * Double(leaves) / Double(size * size), bark))
