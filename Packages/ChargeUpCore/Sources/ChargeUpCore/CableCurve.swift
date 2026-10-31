import simd

/// The cable from the port to the lantern socket: a straight span with a
/// parabolic sag straight down, zero at both ends and `sag` at mid-span.
/// Evaluated analytically, so anything riding the cable (sparks, the plug)
/// can follow the current endpoints every frame while the tube mesh is
/// rebuilt on its own throttle.
public struct CableCurve: Equatable, Sendable {
    public var start: SIMD3<Float>
    public var end: SIMD3<Float>
    public var sag: Float

    public init(from start: SIMD3<Float>, to end: SIMD3<Float>, sag: Float) {
        self.start = start
        self.end = end
        self.sag = sag
    }

    /// Point at t in 0...1 (clamped). 0 is the port, 1 the lantern socket.
    public func point(at t: Float) -> SIMD3<Float> {
        let t = max(0, min(1, t))
        var p = start + (end - start) * t
        p.y -= sag * 4 * t * (1 - t)
        return p
    }

    /// Unit tangent at t, pointing from the port toward the socket.
    public func tangent(at t: Float) -> SIMD3<Float> {
        let t = max(0, min(1, t))
        var d = end - start
        d.y -= sag * 4 * (1 - 2 * t)
        let l = simd_length(d)
        return l > 1e-6 ? d / l : SIMD3(0, 1, 0)
    }

    /// `segments + 1` evenly spaced samples, ends included.
    public func samples(segments: Int) -> [SIMD3<Float>] {
        let n = max(1, segments)
        return (0...n).map { point(at: Float($0) / Float(n)) }
    }

    /// Opacity of a spark at t: ramps 0 to 1 over the first `fade` of the
    /// cable and 1 to 0 over the last `fade`, 1 between. `fade` 0 means none.
    public static func sparkOpacity(at t: Float, fade: Float) -> Float {
        let t = max(0, min(1, t))
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
