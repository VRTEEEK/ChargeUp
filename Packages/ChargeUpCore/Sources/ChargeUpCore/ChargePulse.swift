import Foundation

/// The lantern's charging pulse: its light breathes around the charging
/// glow, one beat every `chargePulseStartMs` while empty, quickening to
/// `chargePulseEndMs` when full, so it feels like it is filling up. The
/// phase accumulates, so the beat never jumps as the period shortens.
public struct ChargePulse: Equatable, Sendable {
    public private(set) var phase: Double = 0

    public init() {}

    /// The beat's period in seconds at charge `level` (0...1).
    public static func period(level: Double, visuals: VisualsConfig) -> Double {
        let l = min(1, max(0, level))
        let start = Double(visuals.chargePulseStartMs), end = Double(visuals.chargePulseEndMs)
        return (start + (end - start) * l) / 1000
    }

    /// Moves the beat on by `dt` seconds at charge `level` and returns the
    /// brightness multiplier, between 1 - depth and 1 + depth.
    public mutating func advance(dt: Double, level: Double, visuals: VisualsConfig) -> Double {
        phase = (phase + max(0, dt) / Self.period(level: level, visuals: visuals)).truncatingRemainder(dividingBy: 1)
        return 1 + visuals.chargePulseDepth * sin(2 * .pi * phase)
    }
}
