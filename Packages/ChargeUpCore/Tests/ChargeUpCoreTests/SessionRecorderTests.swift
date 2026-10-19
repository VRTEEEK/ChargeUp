import Foundation
import Testing
@testable import ChargeUpCore

@Suite struct SessionRecorderTests {
    @Test func recordsOnlyWhileRecordingAndWritesCSV() throws {
        var r = SessionRecorder()
        r.record(stepId: "cream", hostTimestamp: 1, armStill: true, headOnPort: true, charge: 0)
        #expect(r.rows.isEmpty, "nothing before begin")
        r.begin(at: 1_700_000_000)
        r.record(stepId: "cream", hostTimestamp: 1_700_000_000.1, armStill: false, headOnPort: true, charge: 0)
        r.record(stepId: "charge", hostTimestamp: 1_700_000_003.25, armStill: true, headOnPort: true, charge: 0.5)
        #expect(r.rows.count == 2)
        let csv = r.csv()
        let lines = csv.split(separator: "\n")
        #expect(lines[0] == Substring(SessionRecorder.csvHeader))
        #expect(lines[1] == "cream,1700000000.100,0,1,0.000")
        #expect(lines[2] == "charge,1700000003.250,1,1,0.500")
        #expect(r.fileName(timeZone: TimeZone(identifier: "UTC")!) == "chargeup-session-20231114-221320.csv")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("chargeup-rec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = try #require(try r.finish(into: dir))
        #expect(try String(contentsOf: url, encoding: .utf8) == csv)
        #expect(!r.isRecording)
        #expect(try r.finish(into: dir) == nil, "finish twice writes nothing")
    }

    @Test func beginClearsPreviousRows() {
        var r = SessionRecorder()
        r.begin(at: 1)
        r.record(stepId: "cream", hostTimestamp: 1, armStill: true, headOnPort: true, charge: 0)
        r.begin(at: 2)
        #expect(r.rows.isEmpty)
    }

    @Test @MainActor func hostTickFeedsTheRecorder() async throws {
        let sequence = try ChargeSequence.shipped()
        let host = SessionHost(sequence: sequence, channel: PeerChannel(role: .vision, serviceType: "cu-rec", displayName: "v"))
        var recorder = SessionRecorder()
        var ticks = 0
        host.onTick = { state, now in
            ticks += 1
            recorder.record(stepId: host.currentStepId, hostTimestamp: now,
                            armStill: state.armStill, headOnPort: state.headOnPort, charge: state.charge)
        }
        recorder.begin(at: host.clock())
        host.start()
        host.begin()
        host.updatePresence(armStill: true, headOnPort: true)
        try? await Task.sleep(for: .milliseconds(450))
        host.stop()
        #expect(ticks >= 3)
        #expect(recorder.rows.count == ticks)
        #expect(recorder.rows.allSatisfy { $0.stepId == StepID.cream && $0.armStill && $0.headOnPort })
    }
}
