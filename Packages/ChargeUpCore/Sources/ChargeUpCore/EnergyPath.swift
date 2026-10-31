import simd

/// The energy stream's path: a cubic Bezier from the port to the lantern's
/// glass. It leaves the port straight out of its glass (along the port's
/// up), arcs over, and enters the glass level from the port's side, through
/// the open cage, so the energy looks as if it flows out of one jewel into
/// the other. Built from the current endpoints every frame; anything that
/// rides it follows the arm and the lantern without lag.
public struct EnergyPath: Equatable, Sendable {
    public let p0: SIMD3<Float>, p1: SIMD3<Float>, p2: SIMD3<Float>, p3: SIMD3<Float>

    /// `bend` is each control arm's length as a fraction of the span.
    public init(port: SIMD3<Float>, portUp: SIMD3<Float>, target: SIMD3<Float>, bend: Float) {
        let span = simd_length(target - port)
        let up = simd_length(portUp) > 1e-6 ? simd_normalize(portUp) : SIMD3<Float>(0, 1, 0)
        var toPort = port - target
        toPort.y = 0
        let entry = simd_length(toPort) > 1e-6 ? simd_normalize(toPort) : -up
        p0 = port
        p1 = port + up * bend * span
        p2 = target + entry * bend * span
        p3 = target
    }

    /// Point at u in 0...1 (clamped): 0 the port, 1 the lantern's glass.
    public func point(at u: Float) -> SIMD3<Float> {
        let t = max(0, min(1, u)), s = 1 - t
        return s * s * s * p0 + 3 * s * s * t * p1 + 3 * s * t * t * p2 + t * t * t * p3
    }

    /// Unit tangent at u, pointing toward the lantern.
    public func tangent(at u: Float) -> SIMD3<Float> {
        let t = max(0, min(1, u)), s = 1 - t
        let d = 3 * s * s * (p1 - p0) + 6 * s * t * (p2 - p1) + 3 * t * t * (p3 - p2)
        let l = simd_length(d)
        return l > 1e-7 ? d / l : simd_normalize(p3 - p0 + SIMD3(0, 1e-6, 0))
    }

    /// `segments + 1` samples by parameter, ends included.
    public func samples(segments: Int) -> [SIMD3<Float>] {
        let n = max(1, segments)
        return (0...n).map { point(at: Float($0) / Float(n)) }
    }

    /// Opacity of something riding the path at u: ramps 0 to 1 over the
    /// first `fade` and 1 to 0 over the last `fade`, so nothing pops in at
    /// the port or out at the lantern. `fade` 0 means none.
    public static func fade(at u: Float, fade: Float) -> Float {
        let t = max(0, min(1, u))
        guard fade > 0 else { return 1 }
        return max(0, min(1, min(t / fade, (1 - t) / fade)))
    }
}

/// Rotation-minimising frames (parallel transport) along a polyline: each
/// sample gets a tangent and a normal; the normal is carried from one
/// sample to the next by the smallest rotation that takes the old tangent
/// onto the new one. Unlike a fixed up vector, this never flips when the
/// line runs vertical, so a tube built on it cannot twist.
public enum TransportFrames {
    public struct Frame: Equatable, Sendable {
        public var tangent: SIMD3<Float>
        public var normal: SIMD3<Float>
        public var binormal: SIMD3<Float> { simd_cross(tangent, normal) }
    }

    public static func frames(along points: [SIMD3<Float>]) -> [Frame] {
        let n = points.count
        guard n >= 2 else { return [] }
        var tangents: [SIMD3<Float>] = []
        tangents.reserveCapacity(n)
        for i in 0..<n {
            let d: SIMD3<Float>
            if i == 0 { d = points[1] - points[0] }
            else if i == n - 1 { d = points[n - 1] - points[n - 2] }
            else { d = points[i + 1] - points[i - 1] }
            let l = simd_length(d)
            tangents.append(l > 1e-7 ? d / l : (tangents.last ?? SIMD3(0, 1, 0)))
        }
        // First normal: any perpendicular, built from the world axis least
        // aligned with the first tangent. Only the start is chosen; the rest
        // is transported.
        let t0 = tangents[0]
        let axes: [SIMD3<Float>] = [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]
        let seed = axes.min { abs(simd_dot($0, t0)) < abs(simd_dot($1, t0)) }!
        var normal = simd_normalize(seed - t0 * simd_dot(seed, t0))
        var result = [Frame(tangent: t0, normal: normal)]
        result.reserveCapacity(n)
        for i in 1..<n {
            let a = tangents[i - 1], b = tangents[i]
            let c = simd_dot(a, b)
            if c < 0.999999 {
                let axis = simd_cross(a, b)
                let s = simd_length(axis)
                if s > 1e-7 {
                    normal = simd_act(simd_quatf(angle: atan2(s, c), axis: axis / s), normal)
                }
            }
            // Re-orthogonalise against drift.
            normal -= b * simd_dot(normal, b)
            let l = simd_length(normal)
            normal = l > 1e-7 ? normal / l : result[i - 1].normal
            result.append(Frame(tangent: b, normal: normal))
        }
        return result
    }
}
