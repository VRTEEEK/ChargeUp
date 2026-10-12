import Foundation
import Testing
@testable import ChargeUpCore

@Suite struct MessageCodecTests {
    static let everyCase: [Message] = [
        .hello(role: .nurse),
        .hello(role: .vision),
        .stepChanged(stepId: "charge", hostTimestamp: 1234.5678),
        .connect(nurseTimestamp: 42.25),
        .presence(headOnPort: true, armStill: false, charge: 0.375),
        .reset,
    ]

    @Test(arguments: everyCase) func roundTrips(_ message: Message) throws {
        let envelope = Envelope(seq: 7, message: message)
        let data = try MessageCodec.encode(envelope)
        #expect(try MessageCodec.decode(data) == envelope)
    }

    @Test func wireFormatIsFlatWithTypeDiscriminator() throws {
        let data = try MessageCodec.encode(Envelope(seq: 3, message: .stepChanged(stepId: "swab", hostTimestamp: 1)))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["seq"] as? Int == 3)
        let message = json["message"] as! [String: Any]
        #expect(message["type"] as? String == "stepChanged")
        #expect(message["stepId"] as? String == "swab")
        #expect(message["hostTimestamp"] as? Double == 1)
    }

    @Test func unknownTypeFails() {
        let data = Data(#"{"seq":1,"message":{"type":"teleport"}}"#.utf8)
        #expect(throws: DecodingError.self) { try MessageCodec.decode(data) }
    }

    @Test func counterIsMonotonic() {
        var c = SequenceCounter()
        #expect(c.take() == 1)
        #expect(c.take() == 2)
        #expect(c.take() == 3)
    }

    @Test func gateDropsOutOfOrderAndDuplicates() {
        var gate = SequenceGate()
        let a = "peerA"
        #expect(gate.accept(Envelope(seq: 1, message: .hello(role: .nurse)), from: a) != nil)
        #expect(gate.accept(Envelope(seq: 2, message: .reset), from: a) != nil)
        #expect(gate.accept(Envelope(seq: 2, message: .reset), from: a) == nil, "duplicate")
        #expect(gate.accept(Envelope(seq: 1, message: .reset), from: a) == nil, "stale")
        #expect(gate.accept(Envelope(seq: 5, message: .reset), from: a) != nil, "gaps are fine")
        #expect(gate.accept(Envelope(seq: 4, message: .reset), from: a) == nil, "late arrival")
    }

    @Test func gateIsPerSender() {
        var gate = SequenceGate()
        #expect(gate.accept(Envelope(seq: 10, message: .reset), from: "a") != nil)
        #expect(gate.accept(Envelope(seq: 1, message: .reset), from: "b") != nil)
    }

    @Test func helloResetsGateForRestartedSender() {
        var gate = SequenceGate()
        #expect(gate.accept(Envelope(seq: 50, message: .reset), from: "a") != nil)
        #expect(gate.accept(Envelope(seq: 1, message: .hello(role: .haptic)), from: "a") != nil)
        #expect(gate.accept(Envelope(seq: 2, message: .reset), from: "a") != nil)
    }

    @Test func forgetClearsSender() {
        var gate = SequenceGate()
        #expect(gate.accept(Envelope(seq: 9, message: .reset), from: "a") != nil)
        gate.forget("a")
        #expect(gate.accept(Envelope(seq: 1, message: .reset), from: "a") != nil)
    }
}

@Suite struct MessageLogTests {
    @Test func ringBufferKeepsNewest() {
        var log = MessageLog(capacity: 3)
        for i in 1...5 {
            log.append(LogEntry(localTimestamp: Double(i), direction: .sent, peer: "p", seq: UInt64(i), type: "reset"))
        }
        #expect(log.count == 3)
        #expect(log.entries.map(\.seq) == [3, 4, 5])
        log.clear()
        #expect(log.entries.isEmpty)
    }

    @Test func csvHasHeaderAndRows() {
        var log = MessageLog(capacity: 10)
        log.append(LogEntry(localTimestamp: 1.5, direction: .received, peer: "vision-1", seq: 2,
                            type: "stepChanged", stepId: "hold", hostTimestamp: 1.25))
        let csv = log.csv()
        let lines = csv.split(separator: "\n")
        #expect(lines[0] == Substring(MessageLog.csvHeader))
        #expect(lines[1] == "1.500000,received,vision-1,2,stepChanged,hold,1.250000")
    }
}
