import Foundation
import Testing
@testable import ChargeUpCore

@Suite struct SessionReducerTests {
    let seq = try! ChargeSequence.shipped()

    private func reduce(_ s: SessionState, _ e: SessionEvent) -> SessionState {
        SessionReducer.reduce(s, e, sequence: seq)
    }

    private func stepId(_ s: SessionState) -> String? { s.currentStep(in: seq)?.id }

    @Test func happyPath() {
        var s = SessionState()
        #expect(s.phase == .idle)
        s = reduce(s, .start(at: 0))
        #expect(stepId(s) == StepID.cream)
        s = reduce(s, .nurseTap(at: 1))
        #expect(stepId(s) == StepID.clean)
        s = reduce(s, .nurseTap(at: 2))
        #expect(stepId(s) == StepID.countdown)
        s = reduce(s, .connect(nurseTimestamp: 2.9, at: 3))
        #expect(stepId(s) == StepID.connect)
        #expect(s.connectNurseTimestamp == 2.9)
        s = reduce(s, .tick(at: 3.4))
        #expect(stepId(s) == StepID.flush)
        s = reduce(s, .nurseTap(at: 5))
        #expect(stepId(s) == StepID.charge)
        s = reduce(s, .nurseTap(at: 8))
        #expect(stepId(s) == StepID.release)
        s = reduce(s, .nurseTap(at: 10))
        #expect(s.phase == .complete)
        #expect(seq.steps.count == 7)
        // Nothing moves after complete except reset.
        #expect(reduce(s, .nurseTap(at: 11)).phase == .complete)
        #expect(reduce(s, .tick(at: 11)).phase == .complete)
        #expect(reduce(s, .reset).phase == .idle)
    }

    @Test func eachNurseTapAdvancesExactlyOne() {
        var s = reduce(SessionState(), .start(at: 0))
        for (index, step) in seq.steps.enumerated() {
            guard step.advance.isNurseTap, step.id != StepID.countdown else { continue }
            s.phase = .step(index)
            let next = reduce(s, .nurseTap(at: 1))
            if index + 1 < seq.steps.count {
                #expect(next.phase == .step(index + 1), "tap on \(step.id)")
            } else {
                #expect(next.phase == .complete, "tap on \(step.id)")
            }
        }
    }

    @Test func nurseTapIgnoredOnCountdownAndAutoSteps() {
        var s = SessionState()
        s.phase = .step(seq.index(of: StepID.countdown)!)
        #expect(reduce(s, .nurseTap(at: 1)) == s)
        s.phase = .step(seq.index(of: StepID.connect)!)
        #expect(reduce(s, .nurseTap(at: 1)) == s)
    }

    @Test func connectIgnoredUnlessCountdown() {
        for index in seq.steps.indices where seq.steps[index].id != StepID.countdown {
            var s = SessionState()
            s.phase = .step(index)
            let next = reduce(s, .connect(nurseTimestamp: 1, at: 1))
            #expect(next == s, "connect on \(seq.steps[index].id) should be ignored")
        }
        #expect(reduce(SessionState(), .connect(nurseTimestamp: 1, at: 1)) == SessionState())
        var complete = SessionState()
        complete.phase = .complete
        #expect(reduce(complete, .connect(nurseTimestamp: 1, at: 1)) == complete)
    }

    @Test func startOnlyFromIdle() {
        var s = SessionState()
        s.phase = .step(3)
        #expect(reduce(s, .start(at: 5)) == s)
    }

    @Test func autoAdvanceTiming() {
        var s = SessionState()
        s = reduce(s, .start(at: 0))
        s.phase = .step(seq.index(of: StepID.countdown)!)
        s = reduce(s, .connect(nurseTimestamp: 10, at: 10))
        #expect(stepId(s) == StepID.connect)
        #expect(s.enteredAt == 10)
        s = reduce(s, .tick(at: 10.2))
        #expect(stepId(s) == StepID.connect)
        s = reduce(s, .tick(at: 10.399))
        #expect(stepId(s) == StepID.connect)
        s = reduce(s, .tick(at: 10.4))
        #expect(stepId(s) == StepID.flush)
        #expect(s.enteredAt == 10.4)
    }

    @Test func resetFromEveryState() {
        var states: [SessionState] = [SessionState()]
        var s = reduce(SessionState(), .start(at: 0))
        s = reduce(s, .presence(armStill: true, headOnPort: true))
        for index in seq.steps.indices {
            s.phase = .step(index)
            s.charge = 0.5
            states.append(s)
        }
        s.phase = .complete
        states.append(s)
        for state in states {
            #expect(reduce(state, .reset) == SessionState())
        }
    }

    @Test func chargeAccruesOnlyWhileCooperating() {
        var s = reduce(SessionState(), .start(at: 0))
        s.phase = .step(seq.index(of: StepID.charge)!)
        s.enteredAt = 0
        s.lastTickAt = 0
        s = reduce(s, .tick(at: 1))
        #expect(s.charge == 0)
        s = reduce(s, .presence(armStill: true, headOnPort: false))
        s = reduce(s, .tick(at: 2))
        #expect(s.charge == 0)
        s = reduce(s, .presence(armStill: true, headOnPort: true))
        s = reduce(s, .tick(at: 3))
        #expect(abs(s.charge - seq.config.chargeRatePerSecond) < 1e-9)
        s = reduce(s, .presence(armStill: false, headOnPort: true))
        s = reduce(s, .tick(at: 4))
        #expect(abs(s.charge - seq.config.chargeRatePerSecond) < 1e-9)
        s = reduce(s, .presence(armStill: true, headOnPort: true))
        s = reduce(s, .tick(at: 100))
        #expect(s.charge == 1)
        #expect(stepId(s) == StepID.charge, "charge step waits for the nurse")
    }

    @Test func chargeDoesNotAccrueOutsideChargeStep() {
        var s = reduce(SessionState(), .start(at: 0))
        s = reduce(s, .presence(armStill: true, headOnPort: true))
        s = reduce(s, .tick(at: 5))
        #expect(s.charge == 0)
    }

    @Test func isChargingReflectsStepAndPresence() {
        var s = reduce(SessionState(), .start(at: 0))
        s.phase = .step(seq.index(of: StepID.charge)!)
        #expect(!s.isCharging(in: seq))
        s = reduce(s, .presence(armStill: true, headOnPort: true))
        #expect(s.isCharging(in: seq))
    }
}
