import Foundation
import Testing
@testable import ChargeUpCore

@Suite struct SequenceTests {
    @Test func shippedJSONDecodes() throws {
        let seq = try ChargeSequence.shipped()
        #expect(seq.version == 1)
        #expect(seq.object == "lantern")
        #expect(seq.steps.map(\.id) == [
            StepID.hold, StepID.swab, StepID.countdown, StepID.connect,
            StepID.charge, StepID.release, StepID.seal,
        ])
        #expect(seq.step(id: StepID.countdown)?.advance == .nurseTap(label: "CONNECT"))
        #expect(seq.step(id: StepID.connect)?.advance == .auto(durationMs: 400))
        #expect(seq.step(id: StepID.hold)?.advance.buttonLabel == Advance.defaultLabel)
        #expect(seq.step(id: StepID.charge)?.haptic == .ramp)
        #expect(seq.step(id: StepID.connect)?.haptic == .pulse)
        #expect(seq.config.rampStartIntensity == 0.2)
        #expect(seq.config.rampEndIntensity == 1.0)
        #expect(seq.config.headOnPortDegrees == 25)
    }

    @Test func visualsConfigMatchesPerceivedText() throws {
        let v = try ChargeSequence.shipped().config.visuals
        #expect(v.countdownPulseCount == 3)
        #expect(v.countdownPulseMs == 800, "three pulses of light, 800 ms apart")
        #expect(v.cableSnap < v.cableRetract)
    }

    @Test func audioConfigAndIds() throws {
        let seq = try ChargeSequence.shipped()
        #expect(seq.audioIds == ["port_place", "frost", "pulse", "click", "flow_loop", "complete", "seal"])
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
        config.removeValue(forKey: "chargeRatePerSecond")
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
        #expect(throws: SequenceError.duplicateStepId(StepID.hold)) { try load(json) }
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
