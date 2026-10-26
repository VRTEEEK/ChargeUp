import Foundation
import RealityKit

/// A tube along a sagging curve from `start` to `end`, with UV u along the
/// cable (0 at start) and v around it. Rebuilt per frame; small enough.
@MainActor
enum CableMesh {
    static func catenaryPoints(from start: SIMD3<Float>, to end: SIMD3<Float>, sag: Float, segments: Int) -> [SIMD3<Float>] {
        (0...segments).map { i in
            let t = Float(i) / Float(segments)
            var p = start + (end - start) * t
            // Parabolic sag, zero at both ends, `sag` at mid-span, straight down.
            p.y -= sag * 4 * t * (1 - t)
            return p
        }
    }

    static func tube(along points: [SIMD3<Float>], radius: Float, sides: Int = 10) -> MeshResource? {
        guard points.count >= 2 else { return nil }
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        let n = points.count
        for (i, p) in points.enumerated() {
            let tangent: SIMD3<Float> = {
                if i == 0 { return simd_normalize(points[1] - points[0]) }
                if i == n - 1 { return simd_normalize(points[n - 1] - points[n - 2]) }
                return simd_normalize(points[i + 1] - points[i - 1])
            }()
            var up = SIMD3<Float>(0, 1, 0)
            if abs(simd_dot(up, tangent)) > 0.95 { up = SIMD3(1, 0, 0) }
            let side = simd_normalize(simd_cross(tangent, up))
            let out = simd_normalize(simd_cross(side, tangent))
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

    /// Point at parameter t (0...1) along the same curve, for the sparks.
    static func point(on points: [SIMD3<Float>], at t: Float) -> SIMD3<Float> {
        let x = max(0, min(1, t)) * Float(points.count - 1)
        let i = min(points.count - 2, Int(x))
        let f = x - Float(i)
        return points[i] + (points[i + 1] - points[i]) * f
    }
}
