import Foundation
import simd

/// One-euro filter (Casiez, Roustan, Vogel 2012) for a single value.
public struct OneEuroFilter: Sendable {
    public var minCutoff: Double
    public var beta: Double
    public var derivativeCutoff: Double
    private var x: Double?
    private var dx: Double = 0

    public init(minCutoff: Double, beta: Double, derivativeCutoff: Double) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    private static func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1 / (2 * .pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    /// `dt` in seconds since the previous sample. The first sample passes through.
    public mutating func filter(_ value: Double, dt: Double) -> Double {
        guard let prev = x, dt > 0 else {
            x = value
            return value
        }
        let rawDx = (value - prev) / dt
        let aD = Self.alpha(cutoff: derivativeCutoff, dt: dt)
        dx = aD * rawDx + (1 - aD) * dx
        let cutoff = minCutoff + beta * abs(dx)
        let a = Self.alpha(cutoff: cutoff, dt: dt)
        let out = a * value + (1 - a) * prev
        x = out
        return out
    }

    public mutating func reset() {
        x = nil
        dx = 0
    }
}

/// One-euro on a position and a rotation together.
public struct OneEuroPose: Sendable {
    private var p: [OneEuroFilter]
    private var q: [OneEuroFilter]
    private var lastQ: simd_quatf?

    public init(minCutoff: Double, beta: Double, derivativeCutoff: Double) {
        let f = OneEuroFilter(minCutoff: minCutoff, beta: beta, derivativeCutoff: derivativeCutoff)
        p = Array(repeating: f, count: 3)
        q = Array(repeating: f, count: 4)
    }

    public mutating func filter(position: SIMD3<Float>, orientation: simd_quatf, dt: Double)
        -> (position: SIMD3<Float>, orientation: simd_quatf) {
        var pos = SIMD3<Float>()
        for i in 0..<3 { pos[i] = Float(p[i].filter(Double(position[i]), dt: dt)) }
        // Keep the quaternion on the same hemisphere as the last one so the
        // component-wise filter never averages across q and -q.
        var qin = orientation
        if let last = lastQ, simd_dot(last.vector, qin.vector) < 0 { qin = simd_quatf(vector: -qin.vector) }
        var v = SIMD4<Float>()
        for i in 0..<4 { v[i] = Float(q[i].filter(Double(qin.vector[i]), dt: dt)) }
        let out = simd_normalize(simd_quatf(vector: v))
        lastQ = out
        return (pos, out)
    }

    public mutating func reset() {
        for i in p.indices { p[i].reset() }
        for i in q.indices { q[i].reset() }
        lastQ = nil
    }
}

/// Where the port sits on the forearm, in world space.
public struct PortPose: Equatable, Sendable {
    public var position: SIMD3<Float>
    public var orientation: simd_quatf
    /// 0...1. Drops to `occludedOpacity` while tracking is lost.
    public var opacity: Float
    public var status: ForearmTracker.Status

    public init(position: SIMD3<Float>, orientation: simd_quatf, opacity: Float, status: ForearmTracker.Status) {
        self.position = position
        self.orientation = orientation
        self.opacity = opacity
        self.status = status
    }
}

/// Pure geometry: two joint transforms in, port pose out. No ARKit types so
/// it runs under `swift test` on macOS.
public enum ForearmPoseSolver {
    /// - Parameters:
    ///   - wrist: world transform of the forearmWrist joint.
    ///   - arm: world transform of the forearmArm joint (toward the elbow).
    /// Returns nil when the two joints coincide and no forearm axis exists.
    public static func solve(wrist: simd_float4x4, arm: simd_float4x4, config: ForearmConfig)
        -> (position: SIMD3<Float>, orientation: simd_quatf)? {
        let wristPos = translation(of: wrist)
        let armPos = translation(of: arm)
        let toElbow = armPos - wristPos
        guard simd_length(toElbow) > 1e-4 else { return nil }
        let proximal = simd_normalize(toElbow)

        // Dorsal: the configured local axis of the wrist joint, made perpendicular to the forearm.
        var dorsal = axis(config.dorsalAxis, of: wrist)
        dorsal -= proximal * simd_dot(dorsal, proximal)
        if simd_length(dorsal) < 1e-4 {
            dorsal = SIMD3<Float>(0, 1, 0)
            dorsal -= proximal * simd_dot(dorsal, proximal)
        }
        dorsal = simd_normalize(dorsal)

        let position = wristPos + proximal * config.portOffsetProximal + dorsal * config.forearmRadius
        // Port frame: +X toward the hand, +Y out of the skin, +Z completes it.
        let x = -proximal
        let y = dorsal
        let z = simd_normalize(simd_cross(x, y))
        let rotation = simd_float3x3(columns: (x, y, z))
        return (position, simd_quatf(rotation))
    }

    public static func translation(of m: simd_float4x4) -> SIMD3<Float> {
        SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
    }

    static func axis(_ a: SignedAxis, of m: simd_float4x4) -> SIMD3<Float> {
        let c: SIMD4<Float>
        switch a.axis {
        case .x: c = m.columns.0
        case .y: c = m.columns.1
        case .z: c = m.columns.2
        }
        return simd_normalize(SIMD3<Float>(c.x, c.y, c.z)) * Float(a.sign)
    }
}

/// Smoothing plus hold-and-fade when tracking drops. Feed it every anchor
/// update with `observe`, and ask it for the pose every rendered frame with
/// `pose(at:)` so the hold timer and fades progress without new samples.
public struct ForearmTracker: Sendable {
    public enum Status: String, Equatable, Sendable {
        /// No pose has ever been seen.
        case searching
        case tracked
        /// Lost within the last `holdLastPoseMs`; pose frozen, fully opaque.
        case holding
        /// Lost for longer; pose frozen, faded to `occludedOpacity`.
        case faded
    }

    public let config: ForearmConfig
    private var filter: OneEuroPose
    private var last: (position: SIMD3<Float>, orientation: simd_quatf)?
    private var lastSampleAt: TimeInterval?
    private var lastTrackedAt: TimeInterval?
    private var opacity: Float = 1
    private var opacityAt: TimeInterval?

    public init(config: ForearmConfig) {
        self.config = config
        filter = OneEuroPose(minCutoff: config.filterMinCutoffHz, beta: config.filterBeta,
                             derivativeCutoff: config.filterDerivativeCutoffHz)
    }

    /// A raw pose from the solver, or nil when the held hand is not tracked.
    public mutating func observe(_ raw: (position: SIMD3<Float>, orientation: simd_quatf)?, at now: TimeInterval) {
        guard let raw else { return }
        let dt = lastSampleAt.map { min(now - $0, config.filterMaxStep) } ?? 0
        last = filter.filter(position: raw.position, orientation: raw.orientation, dt: max(dt, 1e-3))
        lastSampleAt = now
        lastTrackedAt = now
    }

    public mutating func pose(at now: TimeInterval) -> PortPose? {
        guard let last, let lastTrackedAt else { return nil }
        let lost = now - lastTrackedAt
        let status: Status
        // Treat anything older than one filter step as a drop; anchors arrive far faster than that.
        if lost <= config.filterMaxStep {
            status = .tracked
        } else if lost <= config.holdLastPose + config.filterMaxStep {
            status = .holding
        } else {
            status = .faded
        }
        let target: Float = status == .faded ? Float(config.occludedOpacity) : 1
        opacity = step(opacity, toward: target, at: now)
        return PortPose(position: last.position, orientation: last.orientation, opacity: opacity, status: status)
    }

    public mutating func reset() {
        filter.reset()
        last = nil
        lastSampleAt = nil
        lastTrackedAt = nil
        opacity = 1
        opacityAt = nil
    }

    private mutating func step(_ current: Float, toward target: Float, at now: TimeInterval) -> Float {
        defer { opacityAt = now }
        guard let opacityAt, current != target else { return current }
        let dt = Float(min(now - opacityAt, config.filterMaxStep))
        let rate = Float(1 - config.occludedOpacity) / Float(config.fade)
        let delta = rate * dt
        return current < target ? min(target, current + delta) : max(target, current - delta)
    }
}

/// Port pose on the simulated forearm: a horizontal circle of `radius` about
/// `centre`, one lap per `periodS`, with the port facing `normal`.
public enum SimulatedForearmPath {
    public static func pose(at t: TimeInterval, config: SimulatedPathConfig) -> PortPose {
        let phase = Float(2 * Double.pi * (t / config.periodS).truncatingRemainder(dividingBy: 1))
        let offset = SIMD3<Float>(cos(phase), 0, sin(phase)) * config.radius
        let position = config.centre + offset
        let y = simd_normalize(config.normalVector)
        // +X of the port frame points toward the (imaginary) hand: along the world -X here.
        var x = SIMD3<Float>(-1, 0, 0)
        x -= y * simd_dot(x, y)
        x = simd_normalize(x)
        let z = simd_normalize(simd_cross(x, y))
        let rotation = simd_float3x3(columns: (x, y, z))
        return PortPose(position: position, orientation: simd_quatf(rotation), opacity: 1, status: .tracked)
    }
}

/// Where to put the lantern, from the head pose at session start.
public enum LanternPlacement {
    /// `head` is the device transform (origin from device), or nil to use the fallback height
    /// facing -Z from the space origin. The lantern is dropped to chest height and
    /// turned to face the head, yaw only.
    public static func transform(head: simd_float4x4?, config: LanternConfig, simulated: Bool = false) -> simd_float4x4 {
        let forwardDistance = Float(simulated ? config.simulatedForwardM : config.forwardM)
        let drop = Float(simulated ? config.simulatedBelowHeadM : config.belowHeadM)
        let headPos: SIMD3<Float>
        var forward: SIMD3<Float>
        if let head {
            headPos = ForearmPoseSolver.translation(of: head)
            // The device looks down its local -Z.
            let f = head.columns.2
            forward = SIMD3<Float>(-f.x, 0, -f.z)
            if simd_length(forward) < 1e-4 { forward = SIMD3<Float>(0, 0, -1) }
        } else {
            headPos = SIMD3<Float>(0, config.fallbackHeadHeight, 0)
            forward = SIMD3<Float>(0, 0, -1)
        }
        forward = simd_normalize(forward)
        let position = SIMD3<Float>(headPos.x, headPos.y - drop, headPos.z) + forward * forwardDistance
        // Lantern +Z faces back toward the head.
        let z = -forward
        let y = SIMD3<Float>(0, 1, 0)
        let x = simd_normalize(simd_cross(y, z))
        var m = matrix_identity_float4x4
        m.columns.0 = SIMD4(x, 0)
        m.columns.1 = SIMD4(y, 0)
        m.columns.2 = SIMD4(z, 0)
        m.columns.3 = SIMD4(position, 1)
        return m
    }
}
