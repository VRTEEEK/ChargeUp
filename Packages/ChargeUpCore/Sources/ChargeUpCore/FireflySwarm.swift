import Foundation
import simd

/// The fireflies of the energy stream: a fixed set that flows from the port
/// to the lantern along the EnergyPath and is reused, never created or
/// destroyed. Each has its own speed, size and wander, drawn again every
/// time it sets off, so the stream never repeats visibly; its colour belongs
/// to its entity. Seeded, so a run is reproducible.
public struct FireflySwarm: Equatable, Sendable {
    public struct Firefly: Equatable, Sendable {
        /// Position along the path. Below 0 it is waiting at the port to set
        /// off; at or past 1 it has gone into the lantern.
        public var u: Float
        public var speed: Float
        public var size: Float
        /// Phase of its sideways wander.
        public var phase: Float
        public var isVisible: Bool { u >= 0 && u < 1 }
    }

    public private(set) var flies: [Firefly] = []
    private var state: UInt64

    public init(visuals: VisualsConfig, seed: UInt64 = 0x5EED) {
        state = seed
        let n = max(1, visuals.fireflyCount)
        for i in 0..<n {
            // Staggered: evenly spaced waits so they set off one after another.
            var f = Firefly(u: -Float(i) / Float(n), speed: 1, size: 1, phase: 0)
            draw(&f, visuals: visuals)
            flies.append(f)
        }
    }

    /// Moves every firefly on by `dt`. While `flowing`, one that reaches the
    /// lantern sets off again from the port with fresh traits; otherwise it
    /// finishes its run and waits.
    public mutating func advance(dt: Float, flowing: Bool, visuals: VisualsConfig) {
        let rate = Float(visuals.flowCableFractionPerSecond)
        for i in flies.indices {
            if flies[i].u < 0 && !flowing { continue }
            flies[i].u += rate * flies[i].speed * max(0, dt)
            if flies[i].u >= 1 && flowing {
                var f = flies[i]
                f.u -= 1
                draw(&f, visuals: visuals)
                flies[i] = f
            }
        }
    }

    /// Sideways offset from the path, in the plane across it: wanders up to
    /// `fireflyWanderMm`, gathered to nothing at the port and the lantern so
    /// each firefly leaves from the glass and goes into the glass.
    public static func wander(_ f: Firefly, time: Double, visuals: VisualsConfig) -> SIMD2<Float> {
        let gather = sin(.pi * max(0, min(1, f.u)))
        let a = Float(visuals.fireflyWanderMm / 1000) * gather
        let w = Float(time) * 2.1 + f.phase
        return SIMD2(a * sin(w), a * cos(w * 0.77 + f.phase * 1.3))
    }

    private mutating func draw(_ f: inout Firefly, visuals: VisualsConfig) {
        f.speed = 1 + Float(visuals.fireflySpeedJitter) * (next() * 2 - 1)
        f.size = 1 + Float(visuals.fireflySizeJitter) * (next() * 2 - 1)
        f.phase = next() * 2 * .pi
    }

    /// SplitMix64, 0..<1.
    private mutating func next() -> Float {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Float(z >> 40) / Float(1 << 24)
    }
}
