import Foundation
import Combine
import ChargeUpCore

/// The headset's side of the session: owns the SessionHost (reducer, clock,
/// channel) and exposes what the operator window and the scene need.
@MainActor
final class SessionController: ObservableObject {
    let sequence: ChargeSequence
    let host: SessionHost

    @Published private(set) var isRunning = false
    private var bag = Set<AnyCancellable>()

    init() {
        do {
            sequence = try ChargeSequence.shipped()
        } catch {
            fatalError("sequence.json failed to load: \(error)")
        }
        host = SessionHost(sequence: sequence)
        host.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        host.channel.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
    }

    var currentStepId: String { host.currentStepId }
    var currentStep: Step? { host.currentStep }
    var state: SessionState { host.state }
    var peers: [PeerInfo] { host.channel.peers }

    /// Operator pressed Start: advertise and tick. The nurse's START begins the sequence.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        host.start()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        host.stop()
    }

    func reset() { host.reset() }
}
