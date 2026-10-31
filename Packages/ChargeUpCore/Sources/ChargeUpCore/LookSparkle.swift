import Foundation
import simd

/// Sparkles on what the child looks at: a hung lantern or the monkey sheds
/// soft golden sparkles while the child's head points at it. visionOS does
/// not tell apps where the eyes look (only its own hover highlight follows
/// them, and that changes the material), so this follows the head, as the
/// brief's attention proxy does: turning the head toward something is
/// looking at it. Nothing changes the object itself.
public struct LookSparkleConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// The head must point within this of an object's edge.
    public var coneDeg: Double
    /// It must stay the nearest for this long to be picked (no flicker
    /// between neighbouring lanterns), and is let go this long after the
    /// head turns away.
    public var dwellMs: Int
    public var holdMs: Int
    /// The sparkles: how many a second, how long each lives, size, how fast
    /// they drift out, colour.
    public var perSecond: Double
    public var lifeMs: Int
    public var sizeMm: Double
    public var speedMmPerS: Double
    public var color: String

    public var rgb: SIMD3<Float> { hexRGB(color) ?? SIMD3(1, 0.82, 0.48) }
    public var life: TimeInterval { Double(lifeMs) / 1000 }

    func validate() -> Bool {
        coneDeg > 0 && dwellMs >= 0 && holdMs >= 0 && perSecond > 0 && lifeMs > 0 && sizeMm > 0
            && speedMmPerS >= 0 && hexRGB(color) != nil
    }

    /// How far off the head's ray an object is, in radians, measured to its
    /// edge (a sphere of `radius` at `centre`): 0 when the ray passes
    /// through it.
    public static func offAxis(head: SIMD3<Float>, forward: SIMD3<Float>, centre: SIMD3<Float>, radius: Float) -> Float {
        let to = centre - head
        let distance = simd_length(to)
        guard distance > 1e-4 else { return 0 }
        let angle = acos(max(-1, min(1, simd_dot(simd_normalize(forward), to / distance))))
        return max(0, angle - atan(radius / distance))
    }
}

/// Picks the looked-at object from each frame's off-axis angles (keyed by a
/// stable name; only eligible objects appear), with dwell and hold.
public struct LookPicker: Equatable, Sendable {
    public private(set) var selected: String?
    private var candidate: String?
    private var candidateSince: Double = 0
    private var selectedSeenAt: Double = 0

    public init() {}

    public mutating func update(offAxis: [String: Float], time: Double, config: LookSparkleConfig) -> String? {
        let cone = Float(config.coneDeg * .pi / 180)
        let best = offAxis.filter { $0.value <= cone }.min { $0.value < $1.value }?.key
        if let best, best == selected {
            selectedSeenAt = time
            candidate = nil
            return selected
        }
        if best != candidate {
            candidate = best
            candidateSince = time
        }
        if let candidate, time - candidateSince >= Double(config.dwellMs) / 1000 {
            selected = candidate
            selectedSeenAt = time
            self.candidate = nil
        } else if selected != nil, time - selectedSeenAt > Double(config.holdMs) / 1000 {
            selected = nil
        }
        return selected
    }
}

