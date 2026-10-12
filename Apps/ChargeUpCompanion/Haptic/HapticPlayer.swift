import Foundation
import CoreHaptics
import os

/// Core Haptics wrapper for the phone in the child's free hand. One transient
/// pulse for the needle, one continuous event with a rising intensity curve
/// for the injection. Everything numeric comes from `SequenceConfig`.
@MainActor
final class HapticPlayer: ObservableObject {
    private static let logger = Logger(subsystem: "com.vrteek.chargeup", category: "haptic")
    /// The ramp holds at full intensity until the nurse taps NEEDLE OUT; this
    /// caps how long it can run if that message never comes.
    private static let maxRampSeconds: TimeInterval = 30

    @Published private(set) var isAvailable = false
    @Published private(set) var isRamping = false

    private var engine: CHHapticEngine?
    private var rampPlayer: CHHapticAdvancedPatternPlayer?

    init() {
        isAvailable = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        guard isAvailable else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.resetHandler = { [weak self] in
                Task { @MainActor in self?.restart() }
            }
            engine.stoppedHandler = { reason in
                HapticPlayer.logger.info("engine stopped: \(reason.rawValue)")
            }
            try engine.start()
            self.engine = engine
        } catch {
            HapticPlayer.logger.error("engine failed: \(error.localizedDescription, privacy: .public)")
            isAvailable = false
        }
    }

    /// One sharp tap, as the cable clicks in.
    func pulse() {
        guard let engine else { return }
        do {
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8),
            ], relativeTime: 0)
            let player = try engine.makePlayer(with: CHHapticPattern(events: [event], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            HapticPlayer.logger.error("pulse failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Continuous buzz rising from rampIntensity[0] to rampIntensity[1] over
    /// rampDurationMs, then holding until `stop()`.
    func startRamp(_ config: SequenceConfigValues) {
        guard let engine else { return }
        stop()
        do {
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(config.sharpness)),
            ], relativeTime: 0, duration: HapticPlayer.maxRampSeconds)
            let curve = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                .init(relativeTime: 0, value: Float(config.startIntensity)),
                .init(relativeTime: config.durationSeconds, value: Float(config.endIntensity)),
                .init(relativeTime: HapticPlayer.maxRampSeconds, value: Float(config.endIntensity)),
            ], relativeTime: 0)
            let pattern = try CHHapticPattern(events: [event], parameterCurves: [curve])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.completionHandler = { [weak self] _ in
                Task { @MainActor in self?.isRamping = false }
            }
            try player.start(atTime: CHHapticTimeImmediate)
            rampPlayer = player
            isRamping = true
        } catch {
            HapticPlayer.logger.error("ramp failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        guard let rampPlayer else { return }
        try? rampPlayer.stop(atTime: CHHapticTimeImmediate)
        self.rampPlayer = nil
        isRamping = false
    }

    private func restart() {
        try? engine?.start()
        isRamping = false
        rampPlayer = nil
    }
}

/// The subset of config the haptic role needs, as plain numbers.
struct SequenceConfigValues {
    let startIntensity: Double
    let endIntensity: Double
    let sharpness: Double
    let durationSeconds: Double
}
