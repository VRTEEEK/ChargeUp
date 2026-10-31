// Lifts the subject out of an image whose "transparent" background is a
// painted checkerboard (common in generated UI art): Vision's foreground
// instance mask, applied as alpha, then cropped to the subject. Writes PNG.
//
//   swiftc -O cutout.swift -o cutout
//   ./cutout <in> <out.png>
import Foundation
import Vision
import CoreImage
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
let input = URL(fileURLWithPath: a[1]), output = URL(fileURLWithPath: a[2])
let request = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(url: input)
try handler.perform([request])
guard let result = request.results?.first else { fatalError("no subject found") }
let masked = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
let image = CIImage(cvPixelBuffer: masked)
let context = CIContext()
guard let cg = context.createCGImage(image, from: image.extent, format: .RGBA8,
                                     colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else { fatalError("render failed") }
let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, cg, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
print("wrote \(output.lastPathComponent) \(cg.width)x\(cg.height), \(result.allInstances.count) instance(s)")
