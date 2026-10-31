// Finds hooks on a tree model for hanging lanterns, offline.
//
//   swiftc -O tree_hooks.swift -o tree_hooks
//   ./tree_hooks lantern_tree.usdz <heightM> <viewerForwardM> <viewerEyeM> <count> [preview.png]
//
// The model must be Y-up, metres, base centre at the origin, front facing +Z
// (decimate_tree.py writes it that way). Prints JSON hooks in model units for
// config.tree.hooks: [x, y, z, chainM]. Rays go up from below to find the
// underside of a branch or the canopy, inside a height band, away from the
// trunk, with room below for a lantern and a clear line to the child's eye.
// Picks are ordered by farthest-point sampling so any first N spread out.
import SceneKit
import AppKit

let args = CommandLine.arguments
let url = URL(fileURLWithPath: args[1])
let heightM = Float(args[2])!, viewerForward = Float(args[3])!, viewerEye = Float(args[4])!
let count = Int(args[5])!
let preview = args.count > 6 ? args[6] : nil

let scene = try! SCNScene(url: url, options: nil)
let root = scene.rootNode
let (mn, mx) = root.boundingBox
let modelHeight = Float(mx.y - mn.y)
let scale = heightM / modelHeight
// Everything below is in model units.
let eye = SCNVector3(0, CGFloat(viewerEye / scale), CGFloat(viewerForward / scale))
let lanternH: Float = 0.25 * 0.45 / scale     // hero lantern 25 cm at the hung scale
let lanternR: Float = 0.07 * 0.45 / scale
let band: ClosedRange<Float> = (0.50 * modelHeight)...(0.74 * modelHeight)
let trunkClear: Float = 0.20 * Float(mx.x - mn.x)

func hits(_ a: SCNVector3, _ b: SCNVector3) -> [SCNHitTestResult] {
    root.hitTestWithSegment(from: a, to: b, options: [SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.all.rawValue,
                                                      SCNHitTestOption.backFaceCulling.rawValue: false])
}
func v(_ x: Float, _ y: Float, _ z: Float) -> SCNVector3 { SCNVector3(CGFloat(x), CGFloat(y), CGFloat(z)) }

struct Hook { var p: SIMD3<Float>; var chain: Float; var visible: Bool }
var candidates: [Hook] = []
let step: Float = 0.03
var x = Float(mn.x) + step
while x < Float(mx.x) {
    var z = Float(mn.z) + step
    while z < Float(mx.z) {
        defer { z += step }
        if (x * x + z * z).squareRoot() < trunkClear { continue }
        // First surface above, from well below the band.
        let up = hits(v(x, band.lowerBound - 0.3, z), v(x, Float(mx.y) + 0.1, z))
            .map { Float($0.worldCoordinates.y) }.filter { $0 > band.lowerBound - 0.3 + 0.001 }.sorted()
        guard let hookY = up.first, band.contains(hookY) else { continue }
        // Room below: nothing within chain + lantern, on the axis and around it.
        let need = lanternH + 0.02 / scale
        var free: Float = .infinity
        for (dx, dz) in [(0, 0), (lanternR, 0), (-lanternR, 0), (0, lanternR), (0, -lanternR)] as [(Float, Float)] {
            let below = hits(v(x + dx, hookY - 0.005, z + dz), v(x + dx, 0, z + dz)).map { hookY - Float($0.worldCoordinates.y) }
            free = min(free, below.min() ?? hookY)
        }
        guard free > need + 0.05 / scale else { continue }
        let chain = min(free - need - 0.02 / scale, (0.06 + 0.16 * Float(abs(sin(x * 37 + z * 19)))) / scale)
        let centre = v(x, hookY - chain - lanternH / 2, z)
        let blocked = !hits(centre, eye).isEmpty
        candidates.append(Hook(p: SIMD3(x, hookY, z), chain: chain * scale, visible: !blocked))
    }
    x += step
}
let visible = candidates.filter(\.visible)
let pool = visible.count >= count ? visible : candidates
FileHandle.standardError.write("candidates \(candidates.count), visible \(visible.count), scale \(scale)\n".data(using: .utf8)!)
// Farthest-point order: the child-facing half first (the first hooks hold
// the seeded lanterns and the first real sessions), then the rest, seeded
// with the visible hook closest to the front centre.
var chosen: [Hook] = []
let minSpacing: Float = 0.18 / scale
func fill(from pool: [Hook], upTo n: Int) {
    if chosen.isEmpty, let first = pool.min(by: { abs($0.p.x) - $0.p.z < abs($1.p.x) - $1.p.z }) { chosen.append(first) }
    while chosen.count < n {
        let open = pool.filter { h in !chosen.contains { $0.p == h.p } }
        guard let next = open.max(by: { a, b in
            chosen.map { simd_distance($0.p, a.p) }.min()! < chosen.map { simd_distance($0.p, b.p) }.min()!
        }) else { break }
        if chosen.map({ simd_distance($0.p, next.p) }).min()! < minSpacing { break }
        chosen.append(next)
    }
}
fill(from: pool.filter { $0.p.z > 0 }, upTo: count)
fill(from: pool, upTo: count)
let rows = chosen.map { String(format: "[%.3f, %.3f, %.3f, %.3f]", $0.p.x, $0.p.y, $0.p.z, $0.chain) }
print("[\n  " + rows.joined(separator: ",\n  ") + "\n]")

if let preview {
    for (i, h) in chosen.enumerated() {
        let chainNode = SCNNode(geometry: SCNCylinder(radius: 0.003, height: CGFloat(h.chain / scale)))
        chainNode.geometry!.firstMaterial!.diffuse.contents = NSColor.systemYellow
        chainNode.position = v(h.p.x, h.p.y - h.chain / scale / 2, h.p.z)
        root.addChildNode(chainNode)
        let lamp = SCNNode(geometry: SCNCapsule(capRadius: CGFloat(lanternR), height: CGFloat(lanternH)))
        lamp.geometry!.firstMaterial!.emission.contents = i < 6 ? NSColor.orange : NSColor.cyan
        lamp.position = v(h.p.x, h.p.y - h.chain / scale - lanternH / 2, h.p.z)
        root.addChildNode(lamp)
    }
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    scene.background.contents = NSColor(white: 0.2, alpha: 1)
    let amb = SCNNode(); amb.light = SCNLight(); amb.light!.type = .ambient; amb.light!.intensity = 700; root.addChildNode(amb)
    renderer.scene = scene
    let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera!.fieldOfView = 75; cam.camera!.zNear = 0.01
    cam.position = eye; cam.look(at: v(0, Float(mx.y) * 0.55, 0)); root.addChildNode(cam)
    renderer.pointOfView = cam
    let img = renderer.snapshot(atTime: 0, with: CGSize(width: 1100, height: 900), antialiasingMode: .multisampling4X)
    try! NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: preview))
}
