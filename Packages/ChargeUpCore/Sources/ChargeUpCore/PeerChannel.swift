import Foundation
@preconcurrency import MultipeerConnectivity
import os

/// A connected peer as the rest of the app sees it. `id` is the Multipeer display name.
public struct PeerInfo: Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public var role: Role?

    public init(id: String, role: Role? = nil) {
        self.id = id
        self.role = role
    }
}

/// One line of the send/receive log. `localTimestamp` is this device's clock;
/// `hostTimestamp` is copied from stepChanged messages so the two can be
/// compared across devices.
public struct LogEntry: Equatable, Sendable {
    public enum Direction: String, Sendable { case sent, received, dropped, event }

    public var localTimestamp: TimeInterval
    public var direction: Direction
    public var peer: String
    public var seq: UInt64
    public var type: String
    public var stepId: String
    public var hostTimestamp: TimeInterval?

    public init(localTimestamp: TimeInterval, direction: Direction, peer: String, seq: UInt64,
                type: String, stepId: String = "", hostTimestamp: TimeInterval? = nil) {
        self.localTimestamp = localTimestamp
        self.direction = direction
        self.peer = peer
        self.seq = seq
        self.type = type
        self.stepId = stepId
        self.hostTimestamp = hostTimestamp
    }
}

/// Fixed-capacity ring buffer of log entries. Oldest entries are overwritten.
public struct MessageLog: Equatable, Sendable {
    public let capacity: Int
    private var buffer: [LogEntry] = []
    private var head = 0
    private var filled = false

    public init(capacity: Int = 2000) {
        self.capacity = max(1, capacity)
        buffer.reserveCapacity(self.capacity)
    }

    public mutating func append(_ entry: LogEntry) {
        if buffer.count < capacity {
            buffer.append(entry)
        } else {
            buffer[head] = entry
            head = (head + 1) % capacity
            filled = true
        }
    }

    /// Entries in chronological order.
    public var entries: [LogEntry] {
        guard filled else { return buffer }
        return Array(buffer[head...] + buffer[..<head])
    }

    public var count: Int { buffer.count }

    public mutating func clear() {
        buffer.removeAll(keepingCapacity: true)
        head = 0
        filled = false
    }

    public static let csvHeader = "localTimestamp,direction,peer,seq,type,stepId,hostTimestamp"

    public func csv() -> String {
        var lines = [MessageLog.csvHeader]
        for e in entries {
            let host = e.hostTimestamp.map { String(format: "%.6f", $0) } ?? ""
            lines.append("\(String(format: "%.6f", e.localTimestamp)),\(e.direction.rawValue),\(e.peer),\(e.seq),\(e.type),\(e.stepId),\(host)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// MultipeerConnectivity wrapper. The visionOS app (`role == .vision`)
/// advertises and hosts; every other role browses and joins. Messages are
/// `Envelope`s as JSON, always sent reliably so ordering is preserved.
@MainActor
public final class PeerChannel: ObservableObject {
    /// Bonjour service `_chargeup._tcp` (Multipeer appends the transport).
    public static let defaultServiceType = "chargeup"

    public let role: Role
    public let displayName: String
    public var isHost: Bool { role == .vision }

    @Published public private(set) var peers: [PeerInfo] = []
    @Published public private(set) var isRunning = false
    @Published public private(set) var log = MessageLog()
    /// Last transport-level note, for the operator window only.
    @Published public private(set) var lastDiagnostic = ""

    public var isConnected: Bool { !peers.isEmpty }

    public var onMessage: ((Message, PeerInfo) -> Void)?
    public var onPeerJoined: ((PeerInfo) -> Void)?
    public var onPeerLeft: ((PeerInfo) -> Void)?

    public var clock: @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }

    private let transport: MultipeerTransport
    private var counter = SequenceCounter()
    private var gate = SequenceGate()

    public init(role: Role, serviceType: String = PeerChannel.defaultServiceType,
                displayName: String? = nil) {
        self.role = role
        let name = displayName ?? "\(role.rawValue)-\(String(UInt32.random(in: 0...0xFFFF), radix: 16))"
        self.displayName = String(name.utf8.prefix(63)).flatMap { _ in name } ?? name
        self.transport = MultipeerTransport(mode: role == .vision ? .host : .browser,
                                            serviceType: serviceType, displayName: self.displayName)
        self.transport.channel = self
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        transport.start()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        transport.stop()
        for peer in peers { gate.forget(peer.id) }
        peers = []
    }

    /// Broadcast to every connected peer.
    public func send(_ message: Message) {
        send(message, to: peers.map(\.id))
    }

    public func send(_ message: Message, to peer: PeerInfo) {
        send(message, to: [peer.id])
    }

    private func send(_ message: Message, to names: [String]) {
        guard !names.isEmpty else { return }
        let envelope = Envelope(seq: counter.take(), message: message)
        do {
            let data = try MessageCodec.encode(envelope)
            transport.send(data, to: names)
            for name in names { record(.sent, envelope, peer: name) }
        } catch {
            note("encode failed: \(error)")
        }
    }

    public func clearLog() { log.clear() }

    // MARK: Transport callbacks (always on the main actor)

    func transportPeerConnected(_ name: String) {
        guard !peers.contains(where: { $0.id == name }) else { return }
        gate.forget(name)
        peers.append(PeerInfo(id: name))
        log.append(LogEntry(localTimestamp: clock(), direction: .event, peer: name, seq: 0, type: "connected"))
        send(.hello(role: role), to: [name])
    }

    func transportPeerDisconnected(_ name: String) {
        guard let index = peers.firstIndex(where: { $0.id == name }) else { return }
        let peer = peers.remove(at: index)
        gate.forget(name)
        log.append(LogEntry(localTimestamp: clock(), direction: .event, peer: name, seq: 0, type: "disconnected"))
        onPeerLeft?(peer)
    }

    func transportReceived(_ data: Data, from name: String) {
        let envelope: Envelope
        do {
            envelope = try MessageCodec.decode(data)
        } catch {
            note("decode failed from \(name): \(error)")
            return
        }
        guard let message = gate.accept(envelope, from: name) else {
            record(.dropped, envelope, peer: name)
            return
        }
        record(.received, envelope, peer: name)
        guard let index = peers.firstIndex(where: { $0.id == name }) else { return }
        if case .hello(let role) = message {
            peers[index].role = role
            onPeerJoined?(peers[index])
        }
        onMessage?(message, peers[index])
    }

    func transportNote(_ text: String) { note(text) }

    private func note(_ text: String) {
        lastDiagnostic = text
        log.append(LogEntry(localTimestamp: clock(), direction: .event, peer: "", seq: 0, type: text))
    }

    private func record(_ direction: LogEntry.Direction, _ envelope: Envelope, peer: String) {
        var stepId = ""
        var hostTimestamp: TimeInterval? = nil
        switch envelope.message {
        case .stepChanged(let id, let ts):
            stepId = id
            hostTimestamp = ts
        case .connect(let ts):
            hostTimestamp = ts
        default:
            break
        }
        log.append(LogEntry(localTimestamp: clock(), direction: direction, peer: peer, seq: envelope.seq,
                            type: envelope.message.typeName, stepId: stepId, hostTimestamp: hostTimestamp))
    }
}

/// Owns the MCSession and the advertiser or browser. All state lives on one
/// serial queue; everything the channel needs to know is hopped to the main
/// actor as plain Sendable values.
final class MultipeerTransport: NSObject, @unchecked Sendable {
    enum Mode { case host, browser }

    private static let logger = Logger(subsystem: "com.vrteek.chargeup", category: "peer")
    private static let reconnectDelay: TimeInterval = 1.0
    private static let inviteTimeout: TimeInterval = 15

    private let queue = DispatchQueue(label: "com.vrteek.chargeup.peer")
    private let mode: Mode
    private let serviceType: String
    private let myPeerID: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var connected: [String: MCPeerID] = [:]
    private var running = false

    weak var channel: PeerChannel?

    init(mode: Mode, serviceType: String, displayName: String) {
        self.mode = mode
        self.serviceType = serviceType
        self.myPeerID = MCPeerID(displayName: displayName)
        super.init()
    }

    func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
            session.delegate = self
            self.session = session
            switch mode {
            case .host: startAdvertising()
            case .browser: startBrowsing()
            }
        }
    }

    func stop() {
        queue.async { [self] in
            running = false
            advertiser?.stopAdvertisingPeer()
            advertiser = nil
            browser?.stopBrowsingForPeers()
            browser = nil
            session?.disconnect()
            session = nil
            connected.removeAll()
        }
    }

    func send(_ data: Data, to names: [String]) {
        queue.async { [self] in
            guard let session else { return }
            let targets = names.compactMap { connected[$0] }
            guard !targets.isEmpty else { return }
            do {
                try session.send(data, toPeers: targets, with: .reliable)
            } catch {
                notify("send failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Queue-only helpers

    private func startAdvertising() {
        guard running, let session else { return }
        let advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        self.advertiser = advertiser
        advertiser.startAdvertisingPeer()
        _ = session
        notify("advertising \(serviceType)")
    }

    private func startBrowsing() {
        guard running else { return }
        browser?.stopBrowsingForPeers()
        let browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser.delegate = self
        self.browser = browser
        browser.startBrowsingForPeers()
        notify("browsing \(serviceType)")
    }

    private func scheduleRebrowse() {
        guard mode == .browser else { return }
        queue.asyncAfter(deadline: .now() + Self.reconnectDelay) { [weak self] in
            guard let self, running, connected.isEmpty else { return }
            startBrowsing()
        }
    }

    private func notify(_ text: String) {
        Self.logger.info("\(text, privacy: .public)")
        Task { @MainActor [weak channel] in channel?.transportNote(text) }
    }
}

extension MultipeerTransport: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let name = peerID.displayName
        queue.async { [self] in
            switch state {
            case .connected:
                connected[name] = peerID
                Task { @MainActor [weak channel] in channel?.transportPeerConnected(name) }
            case .notConnected:
                let wasConnected = connected.removeValue(forKey: name) != nil
                Task { @MainActor [weak channel] in channel?.transportPeerDisconnected(name) }
                if wasConnected || mode == .browser { scheduleRebrowse() }
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let name = peerID.displayName
        Task { @MainActor [weak channel] in channel?.transportReceived(data, from: name) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MultipeerTransport: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Accept everyone; roles are declared in the hello message.
        queue.sync { invitationHandler(running, session) }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        notify("advertising failed: \(error.localizedDescription)")
        queue.asyncAfter(deadline: .now() + Self.reconnectDelay) { [weak self] in self?.startAdvertising() }
    }
}

extension MultipeerTransport: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        queue.async { [self] in
            guard running, let session, connected.isEmpty else { return }
            notify("found \(peerID.displayName), inviting")
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: Self.inviteTimeout)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        notify("lost \(peerID.displayName)")
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        notify("browsing failed: \(error.localizedDescription)")
        queue.asyncAfter(deadline: .now() + Self.reconnectDelay) { [weak self] in self?.startBrowsing() }
    }
}
