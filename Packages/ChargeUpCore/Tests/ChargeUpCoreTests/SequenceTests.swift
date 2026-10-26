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

    @Test func sleeveGlowIsDefaultAndCableIsAmber() throws {
        let seq = try ChargeSequence.shipped()
        #expect(seq.config.sleeve.style == .glow)
        #expect(seq.config.sleeve.glow.extentMinMm == 40 && seq.config.sleeve.glow.extentMaxMm == 140)
        #expect(seq.config.visuals.cableColor == "#FFB347")
        let rgb = seq.config.visuals.cableRGB
        #expect(abs(rgb.x - 1) < 1e-6 && abs(rgb.y - 179.0 / 255) < 1e-6 && abs(rgb.z - 71.0 / 255) < 1e-6)
        #expect(seq.config.visuals.cableCoreMm == 6)
    }

    @Test func companionCuesPerStepAndOffByDefault() throws {
        let seq = try ChargeSequence.shipped()
        #expect(!seq.config.companion.enabled)
        #expect(seq.config.companion.heightM == 0.22)
        #expect(seq.step(id: StepID.cream)?.companion == .appear)
        #expect(seq.step(id: StepID.countdown)?.companion == .agreeHold)
        #expect(seq.step(id: StepID.connect)?.companion == .hold)
        #expect(seq.step(id: StepID.charge)?.companion == .charging)
        #expect(seq.step(id: StepID.release)?.companion == .cheerHeart)
        #expect(seq.step(id: StepID.clean)?.companion == .idle)
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
