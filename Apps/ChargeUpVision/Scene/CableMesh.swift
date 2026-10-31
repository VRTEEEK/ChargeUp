import Foundation
import RealityKit
import ChargeUpCore

/// A tube along a sampled `CableCurve`, with UV u along the cable (0 at
/// the port) and v around it. The rings sit on rotation-minimising frames
/// (`TransportFrames`), so the tube cannot twist where the cable runs
/// vertical. Rebuilt on the cable throttle, not every frame.
@MainActor
enum CableMesh {
    static func tube(along points: [SIMD3<Float>], radius: Float, sides: Int = 10) -> MeshResource? {
        let frames = TransportFrames.frames(along: points)
        guard frames.count >= 2 else { return nil }
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        let n = points.count
        positions.reserveCapacity(n * (sides + 1))
        for (i, p) in points.enumerated() {
            let f = frames[i]
            let side = f.normal
            let out = f.binormal
            let u = Float(i) / Float(n - 1)
            for s in 0...sides {
                let a = Float(s) / Float(sides) * 2 * .pi
                let normal = cos(a) * side + sin(a) * out
                positions.append(p + normal * radius)
                normals.append(normal)
                uvs.append(SIMD2(u, Float(s) / Float(sides)))
            }
        }
        let ring = UInt32(sides + 1)
        for i in 0..<(n - 1) {
            for s in 0..<sides {
                let a = UInt32(i) * ring + UInt32(s)
                let b = a + 1
                let c = a + ring
                let d = c + 1
                indices += [a, c, b, b, c, d]
            }
        }
        var d = MeshDescriptor(name: "cable")
        d.positions = MeshBuffer(positions)
        d.normals = MeshBuffer(normals)
        d.textureCoordinates = MeshBuffer(uvs)
        d.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [d])
    }
}
