import Foundation
import Testing
import simd
@testable import ChargeUpCore

@Suite struct WaveTests {
    private func config() throws -> CompanionWaveConfig { try ChargeSequence.shipped().config.companion.wave }

    /// Feeds a side-to-side motion sampled at 90 Hz; returns the times it fired.
    private func run(amplitudeM: Float, hz: Double, seconds: Double, raised: Bool = true,
                     config: CompanionWaveConfig) -> [Double] {
        var d = WaveDetector()
        var fired: [Double] = []
        let dt = 1.0 / 90
        for i in 0..<Int(seconds / dt) {
            let t = Double(i) * dt
            let x = amplitudeM * Float(sin(2 * .pi * hz * t))
            if d.observe(lateral: x, raised: raised, time: t, config: config) { fired.append(t) }
        }
        return fired
    }

    @Test func aRaisedHandWavingIsAWave() throws {
        let c = try config()
        // A child's wave: about 8 cm each way, two to three times a second.
        let fired = run(amplitudeM: 0.08, hz: 2.5, seconds: 1.2, config: c)
        #expect(fired.first.map { $0 < 1.0 } == true, "recognised within a second")
        // Waving on keeps firing; the responder answers once per cooldown.
        let long = run(amplitudeM: 0.08, hz: 2.5, seconds: 6, config: c)
        var r = CompanionResponder()
        let answers = long.compactMap { r.respond(at: $0, config: c) }
        #expect(long.count > answers.count)
        #expect(answers.count == Int(6 / c.cooldown) || answers.count == Int(6 / c.cooldown) + 1)
    }

    @Test func tremorDriftAndTheLapAreNeverAWave() throws {
        let c = try config()
        #expect(run(amplitudeM: 0.012, hz: 4, seconds: 5, config: c).isEmpty, "tremor and tracking jitter")
        #expect(run(amplitudeM: 0.08, hz: 2.5, seconds: 5, raised: false, config: c).isEmpty, "waving in the lap")
        // A slow sway: strokes further apart than the window allows.
        #expect(run(amplitudeM: 0.1, hz: 0.25, seconds: 10, config: c).isEmpty, "a slow sway is not a wave")
    }

    @Test func lateralIsAcrossTheHeadWhicheverWayTheChildFaces() throws {
        let c = try config()
        // Head at 1.2 m facing -X (turned 90 degrees left): its right is -Z.
        var head = simd_float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3(0, 1, 0)))
        head.columns.3 = SIMD4(0.3, 1.2, 0.1, 1)
        let m = WaveDetector.measure(hand: SIMD3(0.3, 1.0, -0.05), head: head, config: c)
        #expect(abs(m.lateral - 0.15) < 1e-5, "15 cm to the right of the head")
        #expect(m.raised, "20 cm below the head is raised")
        #expect(!WaveDetector.measure(hand: SIMD3(0.3, 0.7, 0.1), head: head, config: c).raised, "the lap is not")
    }

    @Test func aWaveIsAlwaysWavedBackAfterTheCooldown() throws {
        let c = try config()
        #expect(c.responses == ["wave"], "waving gets a wave, nothing else")
        var r = CompanionResponder()
        #expect(r.respond(at: 0, config: c) == "wave")
        #expect(r.respond(at: c.cooldown / 2, config: c) == nil, "not again so soon")
        #expect(r.respond(at: c.cooldown + 0.1, config: c) == "wave")
    }

    @Test func touchingTheMonkeyPlaysACuteClipOnceUntilTheHandMovesAway() throws {
        let t = try ChargeSequence.shipped().config.companion.touch
        let base = SIMD3<Float>(0.5, 0, -1.2), height: Float = 0.55, radius = height * Float(t.bodyRadius)
        // A fingertip on its tummy is inside; one a hand's width away is not.
        #expect(CompanionTouchConfig.distanceToBody(SIMD3(0.5, 0.25, -1.2 + radius * 0.5), base: base, height: height, radius: radius) < 0)
        let away = CompanionTouchConfig.distanceToBody(SIMD3(0.5, 0.25, -1.2 + radius + 0.1), base: base, height: height, radius: radius)
        #expect(abs(away - 0.1) < 1e-5)
        #expect(CompanionTouchConfig.distanceToBody(SIMD3(0.5, height + 0.05, -1.2), base: base, height: height, radius: radius) > 0.04,
                "above its head is not touching it")
        // Trigger and answers.
        var trigger = TreeTouch.Trigger()
        let margin = Float(t.marginMm / 1000), rearm = Float(t.rearmMm / 1000)
        let fired = [0.2, 0.01, -0.02, margin + rearm / 2, 0.0, margin + rearm + 0.01, 0.0].map {
            trigger.update(distance: Float($0), radius: margin, rearm: rearm)
        }
        #expect(fired == [false, true, false, false, false, false, true])
        for id in [StepID.countdown, StepID.connect, SessionMarker.idle] { #expect(!t.isActive(stepId: id)) }
        #expect(t.isActive(stepId: StepID.charge) && t.isActive(stepId: StepID.cream))
    }

    @Test func touchingOrPinchingTheMonkeyPlaysARandomClipNeverTheSameTwiceRunning() throws {
        let t = try ChargeSequence.shipped().config.companion.touch
        #expect(t.pinch && t.responses.count >= 5)
        var rng = SystemRandomNumberGenerator()
        var last: String?
        var seen = Set<String>()
        for _ in 0..<300 {
            let clip = try #require(t.randomResponse(after: last, using: &rng))
            #expect(clip != last, "never the same twice running")
            #expect(t.responses.contains(clip))
            seen.insert(clip)
            last = clip
        }
        #expect(seen == Set(t.responses), "all of them come up")
    }

    @Test func musicPlaysQuietlyAndDipsForTheNeedle() throws {
        let seq = try ChargeSequence.shipped()
        let m = seq.config.audio.music
        #expect(m.enabled && m.file.hasSuffix(".m4a"))
        #expect(m.gainDb <= -12, "background, under the step sounds")
        #expect(m.level(stepId: StepID.countdown) < m.level(stepId: StepID.cream) - 6)
        #expect(m.level(stepId: StepID.connect) == m.level(stepId: StepID.countdown))
        #expect(m.level(stepId: StepID.charge) == m.gainDb)
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Apps/ChargeUpVision/Audio/Music/\(m.file)")
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func quietWhileTheNeedleNeedsStillness() throws {
        let seq = try ChargeSequence.shipped()
        let c = seq.config.companion.wave
        for id in [StepID.countdown, StepID.connect, SessionMarker.idle] { #expect(!c.isActive(stepId: id), "\(id)") }
        for id in [StepID.cream, StepID.clean, StepID.flush, StepID.charge, StepID.release, SessionMarker.complete] {
            #expect(c.isActive(stepId: id), "\(id)")
        }
    }
}
