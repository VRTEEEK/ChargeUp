import Foundation
import simd

/// The lantern tree: where every finished session's lantern hangs. It takes
/// the place of the floating sky cluster (config.sky stays the fallback when
/// the tree is off or its model is missing). The tree stands on the floor in
/// front of the child, behind the current lantern, door toward the child.
public struct TreeConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Height of the whole model once placed.
    public var heightM: Double
    /// From the head to the trunk axis, horizontally, along the lantern's forward.
    public var forwardM: Double
    /// Sideways from that point; positive is to the child's right.
    public var sideM: Double
    /// Extra turn about the vertical, after facing the child.
    public var yawDeg: Double
    /// Used instead of forwardM while the simulated forearm is active, so
    /// the tree sits inside the simulator's fixed camera frame.
    public var simulatedForwardM: Double
    /// The tree fades in over this long when the space opens.
    public var appearSeconds: Double
    /// Scale of a hung lantern relative to the current one.
    public var lanternScale: Double
    /// The chain each lantern hangs on: thickness, colour, and how long it
    /// takes to grow down from the hook after the lantern lands.
    public var chainMm: Double
    public var chainColor: String
    public var chainGrowSeconds: Double
    /// When every hook holds a lantern, the next hangs below the lowest one
    /// on the same chain, this far under it.
    public var stackGapMm: Double
    /// Hung lanterns swing gently: amplitude, period, and the time a newly
    /// landed one takes to reach full swing.
    public var swayDeg: Double
    public var swayPeriodS: Double
    public var swayRampSeconds: Double
    /// The flight from the current lantern to its hook bows up by this much at mid-flight.
    public var flightArcM: Double
    public var glow: TreeGlowConfig
    public var light: TreeLightConfig
    /// Where the companion stands when the tree is there: on the floor
    /// under the canopy, `forwardM` in front of the trunk axis toward the
    /// child and `sideM` to the side away from the held arm, `heightM` tall.
    public var companion: TreeCompanionConfig
    public var motes: TreeMotesConfig
    public var trail: TreeTrailConfig
    public var landingBurst: TreeBurstConfig
    public var touch: TreeTouchConfig
    /// Hooks in the model's own frame (metres before scaling, base centre at
    /// the origin, +Z the door side), in fill order, as [x, y, z, chainM].
    /// chainM is the chain length once placed, in metres. Made offline by
    /// Tools/AssetPrep/tree_hooks.swift for the model in the lantern_tree slot.
    public var hooks: [[Double]]

    public var chainColorRGB: SIMD3<Float> { hexRGB(chainColor) ?? SIMD3(0.85, 0.64, 0.26) }
}

/// The tree's own glow (the emissive map: the heart, the door, the small
/// baked lanterns) breathes slowly and flares when a lantern lands.
public struct TreeGlowConfig: Codable, Equatable, Sendable {
    public var base: Double
    public var breathe: Double
    public var periodS: Double
    public var landingBoost: Double
    public var landingDecaySeconds: Double
}

/// A warm light inside the tree, just in front of the trunk under the
/// canopy, so the trunk and the underside of the leaves glow from within.
/// It breathes and flares with the glow above (scaled by the same factor).
public struct TreeLightConfig: Codable, Equatable, Sendable {
    public var color: String
    /// RealityKit point light intensity at glow 1.
    public var intensity: Double
    public var attenuationRadiusM: Double
    /// Height as a fraction of the tree's height, and distance in front of the trunk axis.
    public var height: Double
    public var forwardM: Double

    public var rgb: SIMD3<Float> { hexRGB(color) ?? SIMD3(1, 0.7, 0.35) }
}

public struct TreeCompanionConfig: Codable, Equatable, Sendable {
    public var heightM: Double
    public var forwardM: Double
    public var sideM: Double
    /// It turns to face the child's head, at most this fast, so it looks at
    /// the child from beside the trunk and follows them if they shift.
    public var turnDegPerSecond: Double
}

/// Golden motes drifting up through the canopy.
public struct TreeMotesConfig: Codable, Equatable, Sendable {
    public var birthRate: Double
    public var lifeSpanS: Double
    public var sizeMm: Double
    public var speedMps: Double
    public var color: String
    /// Emitter box as fractions of the tree's width, height and depth,
    /// centred at `centreHeight` (a fraction of the height).
    public var box: [Double]
    public var centreHeight: Double

    public var rgb: SIMD3<Float> { hexRGB(color) ?? SIMD3(1, 0.82, 0.48) }
}

/// Sparks shed by the lantern while it flies to the tree.
public struct TreeTrailConfig: Codable, Equatable, Sendable {
    public var birthRate: Double
    public var lifeSpanS: Double
    public var sizeMm: Double
}

/// The burst of sparks where the lantern lands.
public struct TreeBurstConfig: Codable, Equatable, Sendable {
    public var count: Int
    public var sizeMm: Double
    public var speedMps: Double
    public var lifeSpanS: Double
}

/// A hung lantern swings when a real hand touches it: pushed away from the
/// hand, at its own pendulum rate, dying away on top of the gentle sway.
public struct TreeTouchConfig: Codable, Equatable, Sendable {
    /// The first step at which touch works. It keeps working through the
    /// later steps and after the session, never before: the needle steps
    /// need the child still.
    public var fromStep: String
    /// A fingertip or knuckle closer than this to a lantern's centre touches it.
    public var radiusMm: Double
    /// The hand must then move this much further out before the same
    /// lantern can be pushed again, so a hand resting on it does not keep pushing.
    public var rearmMm: Double
    /// Peak swing, and the time for it to fall to about a third.
    public var swingDeg: Double
    public var decaySeconds: Double
}

func hexRGB(_ hex: String) -> SIMD3<Float>? {
    var h = hex
    if h.hasPrefix("#") { h.removeFirst() }
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
    return SIMD3(Float((v >> 16) & 0xFF), Float((v >> 8) & 0xFF), Float(v & 0xFF)) / 255
}

extension TreeConfig {
    func validate() -> Bool {
        heightM > 0 && forwardM > 0 && simulatedForwardM > 0 && appearSeconds >= 0
            && lanternScale > 0 && chainMm > 0 && hexRGB(chainColor) != nil && chainGrowSeconds >= 0
            && stackGapMm >= 0 && swayDeg >= 0 && swayPeriodS > 0 && swayRampSeconds >= 0 && flightArcM >= 0
            && glow.periodS > 0 && glow.landingDecaySeconds > 0 && glow.base >= 0
            && hexRGB(light.color) != nil && light.intensity >= 0 && light.attenuationRadiusM > 0
            && (0...1).contains(light.height)
            && companion.heightM > 0 && companion.forwardM >= 0 && companion.sideM >= 0 && companion.turnDegPerSecond > 0
            && motes.birthRate >= 0 && motes.lifeSpanS > 0 && motes.sizeMm > 0 && hexRGB(motes.color) != nil
            && motes.box.count == 3 && (0...1).contains(motes.centreHeight)
            && trail.birthRate >= 0 && trail.lifeSpanS > 0 && trail.sizeMm > 0
            && landingBurst.count >= 0 && landingBurst.sizeMm > 0 && landingBurst.lifeSpanS > 0
            && touch.radiusMm > 0 && touch.rearmMm >= 0 && touch.swingDeg > 0 && touch.decaySeconds > 0
            && !hooks.isEmpty && hooks.allSatisfy { $0.count == 4 && $0[3] >= 0 }
    }
}

/// Pure geometry for the tree: where it stands and where lantern `index` hangs.
public enum TreePlacement {
    /// World transform of the tree's base centre: on the floor (y = 0, the
    /// immersive space origin), `forwardM` ahead of the head along its
    /// floor-plane forward and `sideM` to its right, facing back toward the
    /// head (+Z toward the child), then turned by `yawDeg`.
    public static func transform(head: simd_float4x4?, lantern: LanternConfig, tree: TreeConfig,
                                 simulated: Bool = false) -> simd_float4x4 {
        let headPos: SIMD3<Float>
        var forward: SIMD3<Float>
        if let head {
            headPos = ForearmPoseSolver.translation(of: head)
            let f = head.columns.2
            forward = SIMD3<Float>(-f.x, 0, -f.z)
            if simd_length(forward) < 1e-4 { forward = SIMD3<Float>(0, 0, -1) }
        } else {
            headPos = SIMD3<Float>(0, lantern.fallbackHeadHeight, 0)
            forward = SIMD3<Float>(0, 0, -1)
        }
        forward = simd_normalize(forward)
        let up = SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(forward, up))
        let distance = Float(simulated ? tree.simulatedForwardM : tree.forwardM)
        var position = SIMD3<Float>(headPos.x, 0, headPos.z) + forward * distance + right * Float(tree.sideM)
        position.y = 0
        let facing = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: -forward)
        let turned = simd_quatf(angle: Float(tree.yawDeg) * .pi / 180, axis: up) * facing
        var m = simd_float4x4(turned)
        m.columns.3 = SIMD4(position, 1)
        return m
    }

    /// Where lantern `index` hangs, in the tree's placed frame (metres, base
    /// centre at the origin, unscaled entity): the hook, and how far below
    /// the hook the lantern's ring sits. Past the last hook, lanterns hang
    /// below earlier ones on the same chains, one more lantern-height (plus
    /// the stack gap) down each time round.
    public static func hang(index: Int, tree: TreeConfig, modelScale: Float,
                            hungLanternHeight: Float) -> (hook: SIMD3<Float>, drop: Float) {
        let n = tree.hooks.count
        let h = tree.hooks[index % n]
        let round = Float(index / n)
        let hook = SIMD3<Float>(Float(h[0]), Float(h[1]), Float(h[2])) * modelScale
        let drop = Float(h[3]) + round * (hungLanternHeight + Float(tree.stackGapMm) / 1000)
        return (hook, drop)
    }

    /// The swing angle (radians) of a hung lantern `age` seconds after it
    /// was hung; `phase` staggers lanterns so they do not swing together.
    public static func sway(age: Double, phase: Double, tree: TreeConfig) -> Float {
        let ramp = tree.swayRampSeconds > 0 ? min(1, max(0, age / tree.swayRampSeconds)) : 1
        let eased = ramp * ramp * (3 - 2 * ramp)
        let a = tree.swayDeg * .pi / 180 * eased * sin(2 * .pi * age / tree.swayPeriodS + phase)
        return Float(a)
    }

    /// The yaw (radians about +Y, 0 = facing +Z) that turns something at
    /// `position` toward `target` on the floor plane, moved from `current`
    /// by at most `maxStep` the short way round. Both points in the same
    /// frame. A target straight above or below leaves the yaw as it is.
    public static func faceYaw(current: Float, position: SIMD3<Float>, target: SIMD3<Float>, maxStep: Float) -> Float {
        let d = target - position
        guard d.x * d.x + d.z * d.z > 1e-6 else { return current }
        let want = atan2(d.x, d.z)
        let delta = atan2(sin(want - current), cos(want - current))
        return current + max(-maxStep, min(maxStep, delta))
    }

    /// The flight path from the current lantern (`from`) to its hanging
    /// spot (`to`) at eased progress `u`: straight between them plus an
    /// upward bow of `arc` at mid-flight.
    public static func flight(from: SIMD3<Float>, to: SIMD3<Float>, u: Float, arc: Float) -> SIMD3<Float> {
        let u = max(0, min(1, u))
        return from + (to - from) * u + SIMD3<Float>(0, arc * sin(.pi * u), 0)
    }
}

/// Pure rules for touching a hung lantern; LanternSky applies them per frame.
public enum TreeTouch {
    /// Whether hung lanterns answer a touch at this point of the session.
    public static func isActive(stepId: String, steps: [String], touch: TreeTouchConfig) -> Bool {
        if stepId == SessionMarker.complete { return true }
        guard let from = steps.firstIndex(of: touch.fromStep), let now = steps.firstIndex(of: stepId) else { return false }
        return now >= from
    }

    /// Fires once when a hand comes within the radius, then waits until the
    /// hand is beyond radius + rearm before it can fire again.
    public struct Trigger: Equatable, Sendable {
        public private(set) var armed = true
        public init() {}
        public mutating func update(distance: Float, touch: TreeTouchConfig) -> Bool {
            let radius = Float(touch.radiusMm / 1000)
            if armed, distance < radius {
                armed = false
                return true
            }
            if !armed, distance > radius + Float(touch.rearmMm / 1000) { armed = true }
            return false
        }
    }

    /// A simple pendulum's period for a lantern hanging `length` below its hook.
    public static func period(length: Float) -> Float {
        2 * .pi * sqrt(max(0.01, length) / 9.81)
    }

    /// The axis (in the frame where +Y is up) that swings a hanging lantern
    /// along `push` for a positive angle; nil if the push is nearly vertical.
    public static func swingAxis(push: SIMD3<Float>) -> SIMD3<Float>? {
        let flat = SIMD3<Float>(push.x, 0, push.z)
        guard simd_length(flat) > 1e-4 else { return nil }
        return simd_normalize(simd_cross(simd_normalize(flat), SIMD3<Float>(0, 1, 0)))
    }

    /// True once a swing has died below 0.25 % of its peak (six decay
    /// times), so the per-lantern state can be dropped.
    public static func hasSettled(age: Double, touch: TreeTouchConfig) -> Bool {
        age > touch.decaySeconds * 6
    }

    /// The swing angle `age` seconds after the push: from rest, out along
    /// the push first, decaying.
    public static func angle(age: Double, period: Float, touch: TreeTouchConfig) -> Float {
        guard age >= 0 else { return 0 }
        let amplitude = touch.swingDeg * .pi / 180 * exp(-age / touch.decaySeconds)
        return Float(amplitude * sin(2 * .pi * age / Double(period)))
    }
}
