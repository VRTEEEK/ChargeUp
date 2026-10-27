import Foundation
import Testing
@testable import ChargeUpCore

/// Creates and tears down a host and a mirror over real loopback many times.
/// A crash anywhere in teardown kills the test process, which is the failure.
@Suite(.serialized) struct TeardownStressTests {
    static let iterations = 50

    @MainActor
    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @Test @MainActor func fiftyConnectAndTearDownCycles() async throws {
        try #require(ProcessInfo.processInfo.environment["CHARGEUP_SKIP_LOOPBACK"] != "1")
        let sequence = try ChargeSequence.shipped()
        var connected = 0
        for i in 0..<Self.iterations {
            let service = "cu-td-\(String(UInt16.random(in: 0...0xFFFF), radix: 16))"
            // Each iteration varies the teardown order and timing so pending
            // asyncAfter blocks on the peer queue are still in flight.
            let host = SessionHost(sequence: sequence,
                                   channel: PeerChannel(role: .vision, serviceType: service, displayName: "v\(i)"))
            let nurse = SessionMirror(sequence: sequence,
                                      channel: PeerChannel(role: .nurse, serviceType: service, displayName: "n\(i)"))
            host.start()
            nurse.channel.start()
            let linked = await waitUntil(i % 5 == 0 ? 0.05 : 8) { host.channel.isConnected && nurse.channel.isConnected }
            if linked {
                connected += 1
                nurse.tapButton()
                _ = await waitUntil(2) { nurse.currentStepId == StepID.cream }
            }
            switch i % 4 {
            case 0: host.stop(); nurse.channel.stop()
            case 1: nurse.channel.stop(); host.stop()
            case 2: host.stop()           // nurse channel dropped without stop
            default: nurse.channel.stop() // host dropped without stop
            }
            // Drop the objects now; anything still queued must not touch them.
            if i % 3 == 0 { try? await Task.sleep(for: .milliseconds(30)) }
        }
        #expect(connected >= Self.iterations / 2, "most iterations should link: \(connected)/\(Self.iterations)")
        // Give any late blocks their chance to fire before the process exits.
        try? await Task.sleep(for: .seconds(2))
    }
}
