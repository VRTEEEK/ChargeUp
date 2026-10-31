// Upscales one texture for a large model whose atlas is too coarse for the
// headset: Lanczos resampling, an optional light unsharp mask, written as
// JPEG (quality 0.95) or PNG by the output extension. It adds no new
// detail; it keeps the GPU's 4x4 compression blocks and the source's JPEG
// blocks small enough on screen that the surface stops looking blocky.
//
//   swiftc -O upscale_texture.swift -o upscale_texture
//   ./upscale_texture <in> <out.jpg|out.png> <scale> <sharpen 0...1> <color|raw>
//
// `raw` keeps values untouched (normal, roughness, metallic maps): no colour
// management, no sharpening of the data beyond what is asked.
import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
let input = URL(fileURLWithPath: a[1]), output = URL(fileURLWithPath: a[2])
let scale = Double(a[3])!, sharpen = Double(a[4])!, raw = a[5] == "raw"

let options: [CIContextOption: Any] = raw
    ? [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()]
    : [:]
let context = CIContext(options: options)
guard var image = CIImage(contentsOf: input, options: raw ? [.colorSpace: NSNull()] : [:]) else {
    fatalError("cannot read \(input.path)")
}
let lanczos = CIFilter(name: "CILanczosScaleTransform")!
lanczos.setValue(image, forKey: kCIInputImageKey)
lanczos.setValue(scale, forKey: kCIInputScaleKey)
lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
image = lanczos.outputImage!
if sharpen > 0 {
    let unsharp = CIFilter(name: "CIUnsharpMask")!
    unsharp.setValue(image, forKey: kCIInputImageKey)
    unsharp.setValue(1.6 * scale, forKey: kCIInputRadiusKey)
    unsharp.setValue(sharpen, forKey: kCIInputIntensityKey)
    image = unsharp.outputImage!
}
let extent = CGRect(x: 0, y: 0, width: (image.extent.width).rounded(), height: (image.extent.height).rounded())
let space = raw ? CGColorSpace(name: CGColorSpace.linearSRGB)! : CGColorSpace(name: CGColorSpace.sRGB)!
guard let cg = context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: raw ? nil : space) else {
    fatalError("render failed")
}
let type = output.pathExtension.lowercased() == "png" ? UTType.png : UTType.jpeg
let dest = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, cg, type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary : nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
print("wrote \(output.lastPathComponent) \(cg.width)x\(cg.height)")
