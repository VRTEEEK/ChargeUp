import Foundation

/// Who a peer is. The visionOS app is always `vision`; companions pick on launch.
public enum Role: String, Codable, Equatable, Sendable, CaseIterable {
    case vision, nurse, parent, haptic
}

/// Every message that crosses the peer channel. Wire format is flat JSON with
/// a `type` discriminator so the Quest fallback can speak it without Swift.
public enum Message: Equatable, Sendable {
    case hello(role: Role)
    case stepChanged(stepId: String, hostTimestamp: TimeInterval)
    case connect(nurseTimestamp: TimeInterval)
    case presence(headOnPort: Bool, armStill: Bool, charge: Double)
    case reset

    public var typeName: String {
        switch self {
        case .hello: return "hello"
        case .stepChanged: return "stepChanged"
        case .connect: return "connect"
        case .presence: return "presence"
        case .reset: return "reset"
        }
    }
}

extension Message: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, role, stepId, hostTimestamp, nurseTimestamp, headOnPort, armStill, charge
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "hello":
            self = .hello(role: try c.decode(Role.self, forKey: .role))
        case "stepChanged":
            self = .stepChanged(stepId: try c.decode(String.self, forKey: .stepId),
                                hostTimestamp: try c.decode(TimeInterval.self, forKey: .hostTimestamp))
        case "connect":
            self = .connect(nurseTimestamp: try c.decode(TimeInterval.self, forKey: .nurseTimestamp))
        case "presence":
            self = .presence(headOnPort: try c.decode(Bool.self, forKey: .headOnPort),
                             armStill: try c.decode(Bool.self, forKey: .armStill),
                             charge: try c.decode(Double.self, forKey: .charge))
        case "reset":
            self = .reset
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "unknown message type '\(type)'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(typeName, forKey: .type)
        switch self {
        case .hello(let role):
            try c.encode(role, forKey: .role)
        case .stepChanged(let stepId, let hostTimestamp):
            try c.encode(stepId, forKey: .stepId)
            try c.encode(hostTimestamp, forKey: .hostTimestamp)
        case .connect(let nurseTimestamp):
            try c.encode(nurseTimestamp, forKey: .nurseTimestamp)
        case .presence(let headOnPort, let armStill, let charge):
            try c.encode(headOnPort, forKey: .headOnPort)
            try c.encode(armStill, forKey: .armStill)
            try c.encode(charge, forKey: .charge)
        case .reset:
            break
        }
    }
}

/// What actually goes on the wire: a monotonic sequence number per sender plus
/// the message. Receivers drop anything whose `seq` is not greater than the
/// last one they accepted from that sender.
public struct Envelope: Codable, Equatable, Sendable {
    public var seq: UInt64
    public var message: Message

    public init(seq: UInt64, message: Message) {
        self.seq = seq
        self.message = message
    }
}

public enum MessageCodec {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()
    private static let decoder = JSONDecoder()

    public static func encode(_ envelope: Envelope) throws -> Data {
        try encoder.encode(envelope)
    }

    public static func decode(_ data: Data) throws -> Envelope {
        try decoder.decode(Envelope.self, from: data)
    }
}

/// Assigns outgoing sequence numbers. One per channel instance.
public struct SequenceCounter: Sendable {
    private var next: UInt64 = 1
    public init() {}
    public mutating func take() -> UInt64 {
        defer { next += 1 }
        return next
    }
}

/// Tracks the last accepted sequence number per sender and drops stale or
/// duplicate envelopes. A sender that restarts (seq goes back to 1) is
/// recognised by its `hello`, which always resets the gate for that sender.
public struct SequenceGate: Sendable {
    private var lastAccepted: [String: UInt64] = [:]
    public init() {}

    /// Returns the message if it should be processed, nil if it was dropped.
    public mutating func accept(_ envelope: Envelope, from sender: String) -> Message? {
        if case .hello = envelope.message {
            lastAccepted[sender] = envelope.seq
            return envelope.message
        }
        if let last = lastAccepted[sender], envelope.seq <= last {
            return nil
        }
        lastAccepted[sender] = envelope.seq
        return envelope.message
    }

    public mutating func forget(_ sender: String) {
        lastAccepted[sender] = nil
    }
}
