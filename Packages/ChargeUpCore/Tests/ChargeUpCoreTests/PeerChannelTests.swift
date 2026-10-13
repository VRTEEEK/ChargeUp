import Foundation
import Testing
@testable import ChargeUpCore

/// Two in-process channels over real Bonjour loopback. Multipeer discovery
/// takes a few seconds, so this suite is serialized and generous with time.
/// Set CHARGEUP_SKIP_LOOPBACK=1 to skip on machines without local network access.
@Suite(.serialized) struct PeerChannelLoopbackTests {
    static let discoveryTimeout: TimeInterval = 30
    static let messageTimeout: TimeInterval = 5

    private static var skipped: Bool {
        ProcessInfo.processInfo.environment["CHARGEUP_SKIP_LOOPBACK"] == "1"
    }

    @MainActor
    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    @Test @MainActor func helloAndStepChangedCrossTheChannel() async throws {
        try #require(!Self.skipped, "loopback skipped by CHARGEUP_SKIP_LOOPBACK")
        let service = "cu-test-\(String(UInt16.random(in: 0...0xFFFF), radix: 16))"
        let host = PeerChannel(role: .vision, serviceType: service, displayName: "vision-test")
        let nurse = PeerChannel(role: .nurse, serviceType: service, displayName: "nurse-test")
        defer { host.stop(); nurse.stop() }

        var hostGot: [Message] = []
        var nurseGot: [Message] = []
        host.onMessage = { message, _ in hostGot.append(message) }
        nurse.onMessage = { message, _ in nurseGot.append(message) }

        host.start()
        nurse.start()

        let connected = await waitUntil(Self.discoveryTimeout) { host.isConnected && nurse.isConnected }
        try #require(connected, "channels did not connect: host=\(host.lastDiagnostic) nurse=\(nurse.lastDiagnostic)")

        let helloed = await waitUntil(Self.messageTimeout) {
            hostGot.contains(.hello(role: .nurse)) && nurseGot.contains(.hello(role: .vision))
        }
        #expect(helloed)
        #expect(host.peers.first?.role == .nurse)
        #expect(nurse.peers.first?.role == .vision)

        host.send(.stepChanged(stepId: StepID.swab, hostTimestamp: 12.5))
        let stepArrived = await waitUntil(Self.messageTimeout) {
            nurseGot.contains(.stepChanged(stepId: StepID.swab, hostTimestamp: 12.5))
        }
        #expect(stepArrived)

        nurse.send(.connect(nurseTimestamp: 99))
        let connectArrived = await waitUntil(Self.messageTimeout) { hostGot.contains(.connect(nurseTimestamp: 99)) }
        #expect(connectArrived)

        let sent = host.log.entries.filter { $0.direction == .sent && $0.type == "stepChanged" }
        #expect(sent.count == 1)
        #expect(sent.first?.hostTimestamp == 12.5)
        #expect(host.log.entries.contains { $0.direction == .received && $0.type == "connect" })
        #expect(host.log.csv().contains("stepChanged,swab,12.500000"))
    }

    @Test @MainActor func hostAndMirrorRunTheSequenceTogether() async throws {
        try #require(!Self.skipped, "loopback skipped by CHARGEUP_SKIP_LOOPBACK")
        let sequence = try ChargeSequence.shipped()
        let service = "cu-test-\(String(UInt16.random(in: 0...0xFFFF), radix: 16))"
        let host = SessionHost(sequence: sequence,
                               channel: PeerChannel(role: .vision, serviceType: service, displayName: "vision-host"))
        let nurse = SessionMirror(sequence: sequence,
                                  channel: PeerChannel(role: .nurse, serviceType: service, displayName: "nurse-mirror"))
        defer { host.stop(); nurse.channel.stop() }

        host.start()
        nurse.channel.start()
        let connected = await waitUntil(Self.discoveryTimeout) { host.channel.isConnected && nurse.channel.isConnected }
        try #require(connected, "channels did not connect")

        // Companion joins while idle and is told so.
        #expect(await waitUntil(Self.messageTimeout) { nurse.channel.peers.first?.role == .vision })
        #expect(nurse.isIdle)
        #expect(nurse.buttonLabel == SessionMirror.startLabel)

        // Nurse starts the session.
        nurse.tapButton()
        #expect(await waitUntil(Self.messageTimeout) { nurse.currentStepId == StepID.hold })
        #expect(host.currentStepId == StepID.hold)

        // Double tap only advances once: the second request names a stale target.
        nurse.tapButton()
        #expect(await waitUntil(Self.messageTimeout) { nurse.currentStepId == StepID.swab })
        nurse.tapButton()
        #expect(await waitUntil(Self.messageTimeout) { nurse.currentStepId == StepID.countdown })
        #expect(nurse.buttonLabel == "CONNECT")

        // Connect, then the auto step hands over to charge on the host's clock.
        nurse.tapButton()
        #expect(await waitUntil(Self.messageTimeout) { nurse.currentStepId == StepID.charge })
        #expect(nurse.lastConnectRoundTripMs != nil)
        #expect(nurse.buttonLabel == "NEEDLE OUT")

        // Presence flows host -> nurse at tick rate.
        host.updatePresence(armStill: true, headOnPort: true)
        #expect(await waitUntil(Self.messageTimeout) { nurse.armStill && nurse.headOnPort && nurse.charge > 0 })

        nurse.tapButton()
        #expect(await waitUntil(Self.messageTimeout) { nurse.currentStepId == StepID.release })
        nurse.tapButton()
        #expect(await waitUntil(Self.messageTimeout) { nurse.currentStepId == StepID.seal })
        #expect(nurse.buttonLabel == "DONE")
        nurse.tapButton()
        #expect(await waitUntil(Self.messageTimeout) { nurse.isComplete })
        #expect(nurse.buttonLabel == SessionMirror.resetLabel)
        nurse.tapButton()
        #expect(await waitUntil(Self.messageTimeout) { nurse.isIdle })
        #expect(host.state.phase == .idle)
    }
}

@Suite(.serialized) struct RehearsalLoopbackTests {
    @MainActor
    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    @Test @MainActor func rehearsalRunsTheWholeSequenceAgainstTheHostAndCycles() async throws {
        try #require(ProcessInfo.processInfo.environment["CHARGEUP_SKIP_LOOPBACK"] != "1")
        let sequence = try ChargeSequence.shipped()
        let service = "cu-test-\(String(UInt16.random(in: 0...0xFFFF), radix: 16))"
        let host = SessionHost(sequence: sequence,
                               channel: PeerChannel(role: .vision, serviceType: service, displayName: "vision-rh"))
        let nurse = SessionMirror(sequence: sequence,
                                  channel: PeerChannel(role: .nurse, serviceType: service, displayName: "nurse-rh"))
        let driver = RehearsalDriver(mirror: nurse, interval: 0.15)
        defer { driver.set(false); host.stop(); nurse.channel.stop() }

        host.start()
        nurse.channel.start()
        try #require(await waitUntil(30) { host.channel.isConnected && nurse.channel.isConnected })
        #expect(await waitUntil(5) { nurse.channel.peers.first?.role == .vision })

        var seen: [String] = []
        nurse.onStepChanged = { id, _ in seen.append(id) }
        driver.set(true)
        #expect(driver.isOn)

        // Whole sequence, including the auto step, then complete, then back to idle and round again.
        #expect(await waitUntil(10) { seen.contains(SessionMarker.complete) })
        let expected = sequence.steps.map(\.id) + [SessionMarker.complete]
        #expect(Array(seen.prefix(expected.count)) == expected, "\(seen)")
        #expect(await waitUntil(5) { seen.filter { $0 == StepID.hold }.count >= 2 }, "cycles after complete: \(seen)")
        #expect(host.state.phase != .idle || seen.last == SessionMarker.idle)

        driver.set(false)
        #expect(!driver.isOn)
        let tapsAtStop = driver.taps
        try? await Task.sleep(for: .milliseconds(400))
        #expect(driver.taps == tapsAtStop, "no taps after switching off")
    }
}
