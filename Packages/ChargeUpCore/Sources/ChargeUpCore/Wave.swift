import Foundation
import simd

/// The companion waves back: when the child raises a hand and waves, the
/// monkey answers with a clip. Quiet on the steps that need the child still
/// and looking at the port (`quietSteps`: the countdown and the needle).
public struct CompanionWaveConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var quietSteps: [String]
    /// A hand counts as raised when it is no more than this below the head:
    /// about shoulder height, so arm movement in the lap is never a wave.
    public var raisedBelowHeadM: Double
    /// A stroke counts once the hand has come back this far across.
    public var minSwingMm: Double
    /// This many changes of direction (three strokes for two) within the
    /// window make a wave.
    public var reversals: Int
    public var windowMs: Int
    /// After answering, the monkey waits this long before answering again.
    public var cooldownMs: Int
    /// The clips it answers a wave with, in turn (just "wave": it waves back).
    public var responses: [String]

    public var window: TimeInterval { Double(windowMs) / 1000 }
    public var cooldown: TimeInterval { Double(cooldownMs) / 1000 }

    func validate() -> Bool {
        raisedBelowHeadM >= 0 && minSwingMm > 0 && reversals >= 1 && windowMs > 0 && cooldownMs >= 0 && !responses.isEmpty
    }

    /// Whether a wave can be answered on this step.
    public func isActive(stepId: String) -> Bool {
        enabled && stepId != SessionMarker.idle && !quietSteps.contains(stepId)
    }
}

/// One hand's wave detector, fed every frame with the hand's position across
/// the child's head (metres along the head's right, so it is the same wave
/// whichever way they face) and whether the hand is raised. Counts strokes
/// with hysteresis: a change of direction only counts once the hand has
/// come back `minSwingMm` from its furthest point, so tremor and tracking
/// jitter never add up to a wave.
public struct WaveDetector: Equatable, Sendable {
    private var extreme: Float?
    private var direction: Float = 0
    private var reversalTimes: [Double] = []

    public init() {}

    /// Returns true on the sample that completes a wave, then starts afresh.
    public mutating func observe(lateral: Float, raised: Bool, time: Double, config: CompanionWaveConfig) -> Bool {
        guard raised else {
            self = WaveDetector()
            return false
        }
        let swing = Float(config.minSwingMm / 1000)
        guard let far = extreme else {
            extreme = lateral
            return false
        }
        let moved = lateral - far
        if direction == 0 {
            // The first stroke: set off in whichever direction it goes.
            if abs(moved) >= swing {
                direction = moved > 0 ? 1 : -1
                extreme = lateral
            }
        } else if moved * direction > 0 {
            extreme = lateral          // still going the same way: a new furthest point
        } else if -moved * direction >= swing {
            direction = -direction     // came back far enough: a stroke the other way
            extreme = lateral
            reversalTimes.append(time)
        }
        reversalTimes.removeAll { time - $0 > config.window }
        if reversalTimes.count >= config.reversals {
            self = WaveDetector()
            return true
        }
        return false
    }

    /// The hand's position across the head and whether it is raised, from
    /// world positions and the head's transform.
    public static func measure(hand: SIMD3<Float>, head: simd_float4x4, config: CompanionWaveConfig) -> (lateral: Float, raised: Bool) {
        let headPos = SIMD3<Float>(head.columns.3.x, head.columns.3.y, head.columns.3.z)
        var right = SIMD3<Float>(head.columns.0.x, 0, head.columns.0.z)
        right = simd_length(right) > 1e-4 ? simd_normalize(right) : SIMD3(1, 0, 0)
        let raised = hand.y >= headPos.y - Float(config.raisedBelowHeadM)
        return (simd_dot(hand - headPos, right), raised)
    }
}

/// Chooses the companion's answer to a wave or a touch: none during the
/// cooldown, otherwise the responses in turn, starting with the first.
public struct CompanionResponder: Equatable, Sendable {
    private var next = 0
    private var lastAt: Double?

    public init() {}

    public mutating func respond(at time: Double, cooldown: TimeInterval, responses: [String]) -> String? {
        guard !responses.isEmpty else { return nil }
        if let lastAt, time - lastAt < cooldown { return nil }
        lastAt = time
        let clip = responses[next % responses.count]
        next += 1
        return clip
    }

    public mutating func respond(at time: Double, config: CompanionWaveConfig) -> String? {
        respond(at: time, cooldown: config.cooldown, responses: config.responses)
    }

}

/// Touching or pinching the companion plays a random cute clip from
/// `responses`, never the same twice running, at most once per `cooldownMs`
/// across both. Touch: a fingertip or knuckle of either hand reaching its
/// body (a standing capsule `bodyRadius` of its height wide, from its feet
/// to the top of its head) within `marginMm`; the hand must move `rearmMm`
/// further away before the next touch counts. Pinch (`pinch`): look and
/// pinch, the system's own targeting, on the same capsule. Quiet on
/// `quietSteps` (the countdown and the needle).
public struct CompanionTouchConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var quietSteps: [String]
    public var bodyRadius: Double
    public var marginMm: Double
    public var rearmMm: Double
    public var cooldownMs: Int
    public var pinch: Bool
    public var responses: [String]

    public var cooldown: TimeInterval { Double(cooldownMs) / 1000 }

    func validate() -> Bool {
        bodyRadius > 0 && marginMm >= 0 && rearmMm >= 0 && cooldownMs >= 0 && responses.count >= 2
    }

    /// A random clip from `responses`, never `last` again.
    public func randomResponse(after last: String?, using rng: inout some RandomNumberGenerator) -> String? {
        let pool = responses.count > 1 ? responses.filter { $0 != last } : responses
        return pool.randomElement(using: &rng)
    }

    public func isActive(stepId: String) -> Bool {
        enabled && stepId != SessionMarker.idle && !quietSteps.contains(stepId)
    }

    /// Distance from `point` to the surface of a vertical capsule standing
    /// at `base`, `height` tall, `radius` wide; negative inside.
    public static func distanceToBody(_ point: SIMD3<Float>, base: SIMD3<Float>, height: Float, radius: Float) -> Float {
        let bottom = base.y + radius, top = base.y + max(radius, height - radius)
        let y = min(max(point.y, bottom), top)
        return simd_distance(point, SIMD3(base.x, y, base.z)) - radius
    }
}
