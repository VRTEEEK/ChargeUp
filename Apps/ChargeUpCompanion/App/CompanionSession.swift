import Foundation
import Combine
import ChargeUpCore

/// One companion device: its role, the channel to the headset and the
/// mirrored session. Shared by the Nurse, Parent and Haptic views.
@MainActor
final class CompanionSession: ObservableObject {
    let role: Role
    let sequence: ChargeSequence
    let channel: PeerChannel
    let mirror: SessionMirror

    @Published private(set) var isConnected = false
    private var bag = Set<AnyCancellable>()

    init(role: Role) {
        self.role = role
        self.sequence = CompanionSession.loadSequence()
        self.channel = PeerChannel(role: role)
        self.mirror = SessionMirror(sequence: sequence, channel: channel)
        channel.$peers
            .map { !$0.isEmpty }
            .removeDuplicates()
            .assign(to: &$isConnected)
        // Re-publish mirror and channel changes so views observing the session update.
        mirror.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        channel.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
    }

    func start() { channel.start() }
    func stop() { channel.stop() }

    /// The shipped sequence.json is the source of truth; a bad file stops the app at launch.
    static func loadSequence() -> ChargeSequence {
        do {
            return try ChargeSequence.shipped()
        } catch {
            fatalError("sequence.json failed to load: \(error)")
        }
    }
}
