import Foundation

/// Step ids that are not rows in the sequence but appear in `stepChanged`
/// messages so companions can mirror the whole session.
public enum SessionMarker {
    public static let idle = "idle"
    public static let complete = "complete"
}

/// The authority. Lives on the visionOS device, owns the reducer, the host
/// clock and the broadcast of every state change. No UI, no RealityKit.
@MainActor
public final class SessionHost: ObservableObject {
    public let sequence: ChargeSequence
    public let channel: PeerChannel
    @Published public private(set) var state = SessionState()

    public var clock: () -> TimeInterval = { Date().timeIntervalSince1970 }
    /// Called after every reduce that changed the phase.
    public var onPhaseChanged: ((SessionState) -> Void)?
    /// Called on every host tick (10 Hz) with the state and the host clock.
    public var onTick: ((SessionState, TimeInterval) -> Void)?

    private var ticker: Task<Void, Never>?
    private static let tickInterval: Duration = .milliseconds(100)

    public init(sequence: ChargeSequence, channel: PeerChannel? = nil) {
        self.sequence = sequence
        self.channel = channel ?? PeerChannel(role: .vision)
        self.channel.onMessage = { [weak self] message, peer in self?.receive(message, from: peer) }
        self.channel.onPeerJoined = { [weak self] peer in self?.sync(peer) }
    }

    public var currentStepId: String {
        switch state.phase {
        case .idle: return SessionMarker.idle
        case .complete: return SessionMarker.complete
        case .step(let i): return sequence.steps[i].id
        }
    }

    public var currentStep: Step? { state.currentStep(in: sequence) }

    /// Open the channel and start ticking. Does not start the sequence.
    public func start() {
        channel.start()
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: SessionHost.tickInterval)
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    public func stop() {
        ticker?.cancel()
        ticker = nil
        channel.stop()
    }

    /// Operator pressed Start.
    public func begin() { apply(.start(at: clock())) }

    /// Operator reset (long pinch) or nurse reset.
    public func reset() { apply(.reset) }

    public func updatePresence(armStill: Bool, headOnPort: Bool) {
        apply(.presence(armStill: armStill, headOnPort: headOnPort))
    }

    public func apply(_ event: SessionEvent) {
        let before = state
        state = SessionReducer.reduce(state, event, sequence: sequence)
        guard state.phase != before.phase else { return }
        broadcastPhase()
        onPhaseChanged?(state)
    }

    // MARK: Private

    private func tick() {
        let now = clock()
        apply(.tick(at: now))
        onTick?(state, now)
        guard channel.isConnected else { return }
        channel.send(.presence(headOnPort: state.headOnPort, armStill: state.armStill, charge: state.charge))
    }

    private func broadcastPhase() {
        if state.phase == .idle {
            channel.send(.reset)
        } else {
            channel.send(.stepChanged(stepId: currentStepId, hostTimestamp: clock()))
        }
    }

    /// A companion just said hello: give it the current state, never a reset.
    private func sync(_ peer: PeerInfo) {
        if state.phase == .idle {
            channel.send(.stepChanged(stepId: SessionMarker.idle, hostTimestamp: clock()), to: peer)
        } else {
            channel.send(.stepChanged(stepId: currentStepId, hostTimestamp: clock()), to: peer)
        }
    }

    private func receive(_ message: Message, from peer: PeerInfo) {
        switch message {
        case .hello, .presence:
            break
        case .reset:
            reset()
        case .connect(let nurseTimestamp):
            apply(.connect(nurseTimestamp: nurseTimestamp, at: clock()))
        case .stepChanged(let target, _):
            // A companion asks to move to `target`. Only the next step is honoured,
            // so a doubled tap or a stale request cannot skip or repeat a step.
            guard target == nextStepId else { return }
            if state.phase == .idle {
                begin()
            } else {
                apply(.nurseTap(at: clock()))
            }
        }
    }

    private var nextStepId: String? {
        switch state.phase {
        case .idle: return sequence.steps.first?.id
        case .complete: return nil
        case .step(let i):
            return i + 1 < sequence.steps.count ? sequence.steps[i + 1].id : SessionMarker.complete
        }
    }
}

/// A companion's view of the session, rebuilt from the host's messages.
/// Nurse, Parent and Haptic all sit on top of this.
@MainActor
public final class SessionMirror: ObservableObject {
    public let sequence: ChargeSequence
    public let channel: PeerChannel

    /// A step id, `SessionMarker.idle`, or `SessionMarker.complete`.
    @Published public private(set) var currentStepId: String = SessionMarker.idle
    @Published public private(set) var headOnPort = false
    @Published public private(set) var armStill = false
    @Published public private(set) var charge: Double = 0
    /// Milliseconds from sending `connect` to receiving the matching `stepChanged`.
    @Published public private(set) var lastConnectRoundTripMs: Double?

    public var clock: () -> TimeInterval = { Date().timeIntervalSince1970 }
    /// Fired on every step change, with the step if it is a real row.
    public var onStepChanged: ((String, Step?) -> Void)?

    private var connectSentAt: TimeInterval?

    public init(sequence: ChargeSequence, channel: PeerChannel) {
        self.sequence = sequence
        self.channel = channel
        self.channel.onMessage = { [weak self] message, _ in self?.receive(message) }
    }

    public var currentStep: Step? { sequence.step(id: currentStepId) }
    public var currentIndex: Int? { sequence.index(of: currentStepId) }
    public var isIdle: Bool { currentStepId == SessionMarker.idle }
    public var isComplete: Bool { currentStepId == SessionMarker.complete }

    public static let startLabel = "START"
    public static let resetLabel = "RESET"

    /// What the nurse's single button should say right now.
    public var buttonLabel: String {
        if isIdle { return SessionMirror.startLabel }
        if isComplete { return SessionMirror.resetLabel }
        return currentStep?.advance.buttonLabel ?? Advance.defaultLabel
    }

    /// Auto steps advance on the host; the button does nothing on them.
    public var isButtonEnabled: Bool {
        channel.isConnected && (isIdle || isComplete || currentStep?.advance.isNurseTap == true)
    }

    /// The nurse's single button. Sends `connect` on the countdown step,
    /// `reset` when complete, otherwise a request for the next step.
    public func tapButton() {
        if isComplete {
            channel.send(.reset)
            return
        }
        if currentStepId == StepID.countdown {
            connectSentAt = clock()
            channel.send(.connect(nurseTimestamp: clock()))
            return
        }
        guard let next = nextStepId else { return }
        channel.send(.stepChanged(stepId: next, hostTimestamp: clock()))
    }

    public func sendReset() { channel.send(.reset) }

    private var nextStepId: String? {
        if isIdle { return sequence.steps.first?.id }
        guard let i = currentIndex else { return nil }
        return i + 1 < sequence.steps.count ? sequence.steps[i + 1].id : SessionMarker.complete
    }

    private func receive(_ message: Message) {
        switch message {
        case .hello, .connect:
            break
        case .reset:
            setStep(SessionMarker.idle)
            charge = 0
        case .presence(let headOnPort, let armStill, let charge):
            self.headOnPort = headOnPort
            self.armStill = armStill
            self.charge = charge
        case .stepChanged(let stepId, _):
            if let sentAt = connectSentAt, stepId == StepID.connect {
                lastConnectRoundTripMs = (clock() - sentAt) * 1000
                connectSentAt = nil
            }
            setStep(stepId)
        }
    }

    private func setStep(_ id: String) {
        guard id != currentStepId else { return }
        currentStepId = id
        onStepChanged?(id, sequence.step(id: id))
    }
}
