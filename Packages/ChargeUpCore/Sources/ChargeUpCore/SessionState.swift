import Foundation

/// Where the session is. `step` holds an index into `ChargeSequence.steps`.
public enum SessionPhase: Equatable, Sendable, Codable {
    case idle
    case step(Int)
    case complete
}

/// The whole session as a value. The reducer is the only thing that changes it.
public struct SessionState: Equatable, Sendable, Codable {
    public var phase: SessionPhase = .idle
    /// Host clock when `phase` was last entered.
    public var enteredAt: TimeInterval = 0
    /// Host clock at the last tick; used to integrate charge.
    public var lastTickAt: TimeInterval = 0
    /// 0...1, fills during the charge step while the child cooperates.
    public var charge: Double = 0
    public var armStill: Bool = false
    public var headOnPort: Bool = false
    /// The nurse's clock when she tapped Connect. Nil until she does.
    public var connectNurseTimestamp: TimeInterval?

    public init() {}

    public func currentStepIndex() -> Int? {
        if case .step(let i) = phase { return i }
        return nil
    }

    public func currentStep(in sequence: ChargeSequence) -> Step? {
        guard let i = currentStepIndex(), sequence.steps.indices.contains(i) else { return nil }
        return sequence.steps[i]
    }

    /// True while the charge step is active and the child is doing their part.
    public func isCharging(in sequence: ChargeSequence) -> Bool {
        currentStep(in: sequence)?.id == StepID.charge && armStill && headOnPort
    }
}

/// Everything that can happen to a session. `at` is the host clock in seconds.
public enum SessionEvent: Equatable, Sendable {
    /// Operator pressed Start.
    case start(at: TimeInterval)
    /// Nurse pressed the button on a plain nurseTap step.
    case nurseTap(at: TimeInterval)
    /// Nurse pressed CONNECT. Only honoured on the countdown step.
    case connect(nurseTimestamp: TimeInterval, at: TimeInterval)
    /// Host clock advanced. Drives auto steps and charge accrual.
    case tick(at: TimeInterval)
    /// Tracking reported the child's cooperation state.
    case presence(armStill: Bool, headOnPort: Bool)
    /// Back to idle from anywhere.
    case reset
}

public enum SessionReducer {
    /// Pure. Same inputs, same output, no clocks, no frameworks.
    public static func reduce(_ state: SessionState, _ event: SessionEvent,
                              sequence: ChargeSequence) -> SessionState {
        var s = state
        switch event {
        case .reset:
            return SessionState()

        case .start(let now):
            guard s.phase == .idle else { return s }
            s = SessionState()
            return enter(step: 0, into: s, at: now, sequence: sequence)

        case .presence(let armStill, let headOnPort):
            s.armStill = armStill
            s.headOnPort = headOnPort
            return s

        case .nurseTap(let now):
            guard let step = s.currentStep(in: sequence), let i = s.currentStepIndex() else { return s }
            // Auto steps advance on their own; the countdown step advances only by connect.
            guard step.advance.isNurseTap, step.id != StepID.countdown else { return s }
            return enter(step: i + 1, into: s, at: now, sequence: sequence)

        case .connect(let nurseTimestamp, let now):
            guard let step = s.currentStep(in: sequence), let i = s.currentStepIndex(),
                  step.id == StepID.countdown else { return s }
            s.connectNurseTimestamp = nurseTimestamp
            return enter(step: i + 1, into: s, at: now, sequence: sequence)

        case .tick(let now):
            guard let step = s.currentStep(in: sequence), let i = s.currentStepIndex() else { return s }
            let dt = max(0, now - s.lastTickAt)
            s.lastTickAt = now
            if step.id == StepID.charge, s.armStill, s.headOnPort {
                s.charge = min(1, s.charge + sequence.config.chargeRatePerSecond * dt)
            }
            if let ms = step.advance.autoDurationMs, elapsedMs(from: s.enteredAt, to: now) >= ms {
                return enter(step: i + 1, into: s, at: now, sequence: sequence)
            }
            return s
        }
    }

    /// Whole milliseconds, rounded, so a tick landing exactly on the boundary
    /// is not lost to floating-point noise.
    static func elapsedMs(from start: TimeInterval, to now: TimeInterval) -> Int {
        Int(((now - start) * 1000).rounded())
    }

    private static func enter(step index: Int, into state: SessionState, at now: TimeInterval,
                              sequence: ChargeSequence) -> SessionState {
        var s = state
        s.phase = index < sequence.steps.count ? .step(index) : .complete
        s.enteredAt = now
        s.lastTickAt = now
        return s
    }
}
