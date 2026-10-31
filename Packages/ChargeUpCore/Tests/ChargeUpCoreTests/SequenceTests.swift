import Foundation
import Testing
@testable import ChargeUpCore

@Suite struct SequenceTests {
    @Test func shippedJSONDecodes() throws {
        let seq = try ChargeSequence.shipped()
        #expect(seq.version == 1)
        #expect(seq.object == "lantern")
        #expect(seq.steps.map(\.id) == [
            StepID.cream, StepID.clean, StepID.countdown, StepID.connect,
            StepID.flush, StepID.charge, StepID.release,
        ])
        #expect(seq.step(id: StepID.countdown)?.advance == .nurseTap(label: "CONNECT"))
        #expect(seq.step(id: StepID.connect)?.advance == .auto(durationMs: 400))
        #expect(seq.step(id: StepID.charge)?.advance == .nurseTap(label: "NEEDLE OUT"))
        #expect(seq.step(id: StepID.release)?.advance == .nurseTap(label: "DONE"))
        #expect(seq.step(id: StepID.cream)?.advance.buttonLabel == Advance.defaultLabel)
        #expect(seq.step(id: StepID.connect)?.haptic == .ramp, "the ramp runs from the needle moment")
        #expect(seq.step(id: StepID.charge)?.haptic == Haptic.none, "the infusion has no haptic")
        #expect(seq.steps.filter { $0.haptic == .ramp }.count == 1)
        #expect(seq.config.rampStartIntensity == 0.2)
        #expect(seq.config.rampEndIntensity == 1.0)
        #expect(seq.config.headOnPortDegrees == 25)
    }

    @Test func everyStepHasAPromptInEveryLanguage() throws {
        let seq = try ChargeSequence.shipped()
        for step in seq.steps {
            for language in PromptLanguage.allCases {
                #expect(!seq.prompt(for: step.id, in: language).isEmpty, Comment(rawValue: "\(step.id) \(language)"))
            }
        }
        #expect(!seq.prompt(for: SessionMarker.idle, in: .ar).isEmpty)
        #expect(!seq.prompt(for: SessionMarker.complete, in: .ar).isEmpty)
        #expect(seq.prompt(for: StepID.charge).contains("filling"))
        #expect(seq.prompt(for: StepID.charge, in: .ar).contains("يمتلئ"))
        #expect(seq.prompt(for: "nope").isEmpty)
        #expect(PromptLanguage.ar.isRightToLeft && !PromptLanguage.en.isRightToLeft)
    }

    @Test func missingPromptFails() throws {
        var json = try shippedJSON()
        var prompts = json["prompts"] as! [String: Any]
        prompts.removeValue(forKey: "charge")
        json["prompts"] = prompts
        #expect(throws: SequenceError.missingPrompt(StepID.charge)) { try load(json) }
    }

    @Test func missingLanguageFails() throws {
        var json = try shippedJSON()
        var prompts = json["prompts"] as! [String: Any]
        prompts["flush"] = ["en": "Here comes the first spark."]
        json["prompts"] = prompts
        #expect(throws: DecodingError.self) { try load(json) }
        prompts["flush"] = ["en": "Here comes the first spark.", "ar": " "]
        json["prompts"] = prompts
        #expect(throws: SequenceError.missingPrompt(StepID.flush)) { try load(json) }
    }

    @Test func noSleeveByDefaultAndCableIsAmber() throws {
        let seq = try ChargeSequence.shipped()
        #expect(seq.config.sleeve.style == .none, "the port alone on the arm, no glow patch")
        #expect(seq.config.sleeve.glow.extentMinMm == 40 && seq.config.sleeve.glow.extentMaxMm == 140)
        #expect(seq.config.visuals.cableColor == "#FFB347")
        let rgb = seq.config.visuals.cableRGB
        #expect(abs(rgb.x - 1) < 1e-6 && abs(rgb.y - 179.0 / 255) < 1e-6 && abs(rgb.z - 71.0 / 255) < 1e-6)
        #expect(seq.config.cable.rebuildHz == 30)
        #expect(abs(seq.config.cable.minInterval - 1.0 / 30) < 1e-9)
        #expect(seq.config.cable.moveThreshold == 0.002)
    }

    @Test func energyStreamIsAGentleFlowOfFireflies() throws {
        let seq = try ChargeSequence.shipped()
        let v = seq.config.visuals
        #expect((3...6).contains(v.streamCoreMm), "a very thin core, 3 to 6 mm")
        #expect(v.streamCoreOpacity <= 0.3, "faint, not an opaque beam")
        #expect(v.fireflyCount <= 24 && v.fireflySizeMm <= 3, "modest density, small lights")
        #expect(v.fireflyColors.count >= 2, "amber and pale gold")
        for i in v.fireflyColors.indices {
            let c = v.fireflyRGB(i)
            #expect(c.x >= c.y && c.y > c.z, "warm, not white or blue")
        }
        #expect(v.flowCableFractionPerSecond < 1, "gentle: more than a second from port to lantern")
        #expect(seq.step(id: StepID.charge)?.perceived.contains("fireflies") == true)
        #expect(seq.step(id: StepID.connect)?.perceived.contains("stream") == true)
    }

    @Test func companionCuesPerStepAndOnForTheDemo() throws {
        let seq = try ChargeSequence.shipped()
        #expect(seq.config.companion.enabled)
        #expect(seq.config.companion.heightM == 0.22)
        #expect(seq.step(id: StepID.cream)?.companion == .waveIn)
        #expect(seq.step(id: StepID.countdown)?.companion == .listen)
        #expect(seq.step(id: StepID.connect)?.companion == .listen)
        #expect(seq.step(id: StepID.flush)?.companion == .lookOnce)
        #expect(seq.step(id: StepID.charge)?.companion == .charging)
        #expect(seq.step(id: StepID.release)?.companion == .heartCheer)
        #expect(seq.step(id: StepID.clean)?.companion == .idle)
        #expect(seq.config.companion.speed == 0.7)
        #expect(seq.config.companion.speed(for: "wave") == 0.8)
        #expect(seq.config.companion.speed(for: "listen") == 0.7)
        #expect(seq.config.companion.crossfadeS == 0.3)
        #expect(seq.config.companion.chargeVariety == ["look", "sway", "idleAlt"])
        #expect(seq.config.companion.fidgetMaxPerSession == 1)
    }

    @Test func unknownCompanionCueFails() throws {
        var json = try shippedJSON()
        var steps = json["steps"] as! [[String: Any]]
        steps[0]["companion"] = "dance"
        json["steps"] = steps
        #expect(throws: DecodingError.self) { try load(json) }
    }

    @Test func visualsConfigMatchesPerceivedText() throws {
        let v = try ChargeSequence.shipped().config.visuals
        #expect(v.countdownPulseCount == 3)
        #expect(v.countdownPulseMs == 800, "three pulses of light, 800 ms apart")
        #expect(v.cableSnap < v.cableRetract)
        #expect(v.flushSpark > 0)
    }

    @Test func lanternLightIsOrangeToYellow() throws {
        let l = try ChargeSequence.shipped().config.lantern
        #expect(l.lightBottomRGB.x == 1 && l.lightTopRGB.x == 1)
        #expect(l.lightBottomRGB.y < l.lightTopRGB.y, "orange at the base, yellow at the top")
        #expect(l.lightBottomRGB.z < 0.2 && l.lightTopRGB.z < 0.2, "warm, not white")
    }

    @Test func badLanternColourFails() throws {
        var json = try shippedJSON()
        var config = json["config"] as! [String: Any]
        var lantern = config["lantern"] as! [String: Any]
        lantern["lightColorTop"] = "yellow"
        config["lantern"] = lantern
        json["config"] = config
        #expect(throws: DecodingError.self) { try load(json) }
    }

    @Test func chargingLanternPulsesQuickerAsItFills() throws {
        let seq = try ChargeSequence.shipped()
        let v = seq.config.visuals
        #expect(seq.step(id: StepID.charge)?.perceived.contains("pulsing") == true, "the row names the pulse")
        #expect(abs(ChargePulse.period(level: 0, visuals: v) - Double(v.chargePulseStartMs) / 1000) < 1e-9)
        #expect(abs(ChargePulse.period(level: 1, visuals: v) - Double(v.chargePulseEndMs) / 1000) < 1e-9)
        #expect(ChargePulse.period(level: 1, visuals: v) < ChargePulse.period(level: 0, visuals: v), "quicker when full")

        // Over one empty-lantern period it rises above 1, falls below, and stays within depth.
        var pulse = ChargePulse()
        let dt = 1.0 / 90, steps = Int(ChargePulse.period(level: 0, visuals: v) / dt)
        var values: [Double] = []
        for _ in 0..<steps { values.append(pulse.advance(dt: dt, level: 0, visuals: v)) }
        #expect(values.max()! > 1 + v.chargePulseDepth * 0.95 && values.min()! < 1 - v.chargePulseDepth * 0.95)
        #expect(values.allSatisfy { abs($0 - 1) <= v.chargePulseDepth + 1e-9 })

        // Changing the level mid-beat never jumps the brightness.
        var a = ChargePulse()
        let before = a.advance(dt: 0.3, level: 0.2, visuals: v)
        let after = a.advance(dt: dt, level: 0.9, visuals: v)
        #expect(abs(after - before) < 0.05)
    }

    @Test func skinCleanSparklesAreManyColoursAndTheRowSaysSo() throws {
        let seq = try ChargeSequence.shipped()
        let v = seq.config.visuals
        #expect(seq.step(id: StepID.clean)?.perceived.contains("many colours") == true)
        #expect(Set(v.frostSparkleColors).count >= 3, "a ring of several colours, not one")
        let ring = (0..<v.frostSparkleCount).map { v.frostSparkleRGB($0) }
        #expect(ring[0] != ring[1], "neighbours differ")
        #expect(v.frostSparkleRGB(v.frostSparkleColors.count) == v.frostSparkleRGB(0), "the palette cycles round the ring")
    }

    @Test func badSparkleColourFails() throws {
        var json = try shippedJSON()
        var config = json["config"] as! [String: Any]
        var visuals = config["visuals"] as! [String: Any]
        visuals["frostSparkleColors"] = ["#5CE1FF", "pink"]
        config["visuals"] = visuals
        json["config"] = config
        #expect(throws: DecodingError.self) { try load(json) }
    }

    @Test func portIsAGentleAmberJewel() throws {
        let seq = try ChargeSequence.shipped()
        let port = seq.config.port
        // The step visuals ask for 0.2 (cream start), 2 (rest), 2-4 (frost) and up to 10 (countdown peak).
        #expect(port.glow(for: 10) <= Float(port.glowMax) + 1e-6, "the countdown peak never passes the cap")
        #expect(abs(port.glow(for: 10) - Float(port.glowMax)) < 0.01, "and reaches it, so the pulses keep their shape")
        #expect(port.glow(for: 2) < port.glow(for: 10) / 3, "the three pulses stand well clear of the resting glow")
        #expect(port.glow(for: 0.2) < port.glow(for: 2), "the cream warms it from almost nothing")
        #expect(port.glow(for: -1) == 0)
        #expect(port.glowMax <= 1.5, "subtle: no overexposure in room light")
        let amber = port.glowRGB
        #expect(amber.x > amber.y && amber.y > amber.z, "amber, not white or blue")
        #expect(port.glassOpacity >= 0.8, "a jewel, not a see-through coin")
        #expect(port.sinkMm >= 0 && port.sinkMm <= 3)
        #expect(port.motes.perSecond <= 8 && port.motes.sizeMm <= 2.5, "a few small motes, not a glow")
        #expect(seq.step(id: StepID.cream)?.perceived.contains("amber glass") == true)
    }

    @Test func theBadgeGlowsAndBreathesGently() throws {
        let seq = try ChargeSequence.shipped()
        let v = seq.config.visuals
        let samples = stride(from: 0.0, to: Double(v.markGlowPeriodMs) / 1000, by: 0.01).map { v.markGlow(at: $0) }
        #expect(samples.min()! > 0.5, "always glowing")
        #expect(samples.max()! - samples.min()! > 0.2, "visibly breathing")
        #expect(samples.max()! <= 1, "never brighter than the image itself, so never white")
        #expect((40...100).contains(v.markLengthMm), "badge-sized on a forearm")
        #expect(seq.step(id: StepID.release)?.perceived.contains("glowing badge") == true)
    }

    @Test func theMonkeySpeaksOnlyOnItsFriendlyMomentsAndEveryVoiceHasAFile() throws {
        let c = try ChargeSequence.shipped().config.companion
        #expect(Set(c.voices.keys) == ["wave", "cheer", "heart"])
        for quiet in c.chargeVariety + ["look", "listen", "fidget"] {
            #expect(c.voices[quiet] == nil, "\(quiet) plays while the child may rest: silent")
        }
        #expect((c.voices["wave"]?.count ?? 0) >= 2, "greetings take turns")
        let sounds = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Apps/ChargeUpVision/Audio/Sounds")
        for id in c.voiceIds {
            #expect(FileManager.default.fileExists(atPath: sounds.appendingPathComponent("\(id).wav").path), "\(id).wav")
        }
    }

    @Test func audioConfigAndIds() throws {
        let seq = try ChargeSequence.shipped()
        #expect(seq.audioIds == ["port_place", "frost", "pulse", "click", "spark", "flow_loop", "complete"])
        #expect(seq.config.audio.playsAtLantern("flow_loop"))
        #expect(!seq.config.audio.playsAtLantern("click"))
        #expect(seq.config.audio.loops("flow_loop"))
        #expect(seq.config.audio.lanternGainDb == -6)
    }

    @Test func missingFieldFails() throws {
        var json = try shippedJSON()
        var step = (json["steps"] as! [[String: Any]])[0]
        step.removeValue(forKey: "clinicalCue")
        var steps = json["steps"] as! [[String: Any]]
        steps[0] = step
        json["steps"] = steps
        #expect(throws: DecodingError.self) { try load(json) }
    }

    @Test func missingConfigKeyFails() throws {
        var json = try shippedJSON()
        var config = json["config"] as! [String: Any]
        config.removeValue(forKey: "headOnPortDegrees")
        json["config"] = config
        #expect(throws: DecodingError.self) { try load(json) }
    }

    @Test func badRampIntensityFails() throws {
        var json = try shippedJSON()
        var config = json["config"] as! [String: Any]
        config["rampIntensity"] = [0.2]
        json["config"] = config
        #expect(throws: DecodingError.self) { try load(json) }
    }

    @Test func unknownAdvanceKindFails() throws {
        var json = try shippedJSON()
        var steps = json["steps"] as! [[String: Any]]
        steps[0]["advance"] = ["kind": "timer"]
        json["steps"] = steps
        #expect(throws: DecodingError.self) { try load(json) }
    }

    @Test func autoWithoutDurationFails() throws {
        var json = try shippedJSON()
        var steps = json["steps"] as! [[String: Any]]
        steps[3]["advance"] = ["kind": "auto"]
        json["steps"] = steps
        #expect(throws: DecodingError.self) { try load(json) }
    }

    @Test func duplicateIdFails() throws {
        var json = try shippedJSON()
        var steps = json["steps"] as! [[String: Any]]
        steps[1]["id"] = steps[0]["id"]
        json["steps"] = steps
        #expect(throws: SequenceError.duplicateStepId(StepID.cream)) { try load(json) }
    }

    @Test func missingCountdownStepFails() throws {
        var json = try shippedJSON()
        var steps = json["steps"] as! [[String: Any]]
        steps.remove(at: 2)
        json["steps"] = steps
        #expect(throws: SequenceError.missingStep(StepID.countdown)) { try load(json) }
    }

    @Test func emptyStepsFails() throws {
        var json = try shippedJSON()
        json["steps"] = []
        #expect(throws: SequenceError.noSteps) { try load(json) }
    }

    @Test func roundTripsThroughEncoder() throws {
        let seq = try ChargeSequence.shipped()
        let data = try JSONEncoder().encode(seq)
        #expect(try ChargeSequence.load(from: data) == seq)
    }

    // MARK: Helpers

    private func shippedJSON() throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: "sequence", withExtension: "json"))
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    private func load(_ json: [String: Any]) throws -> ChargeSequence {
        try ChargeSequence.load(from: JSONSerialization.data(withJSONObject: json))
    }
}
