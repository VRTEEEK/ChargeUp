import Foundation

/// Per-session evidence: one row per host tick while a session runs. The
/// Vision app writes the CSV to Documents so it can be pulled over Files.
public struct SessionRecorder: Sendable {
    public struct Row: Equatable, Sendable {
        public var stepId: String
        public var hostTimestamp: TimeInterval
        public var armStill: Bool
        public var headOnPort: Bool
        public var charge: Double
    }

    public static let csvHeader = "step,hostTimestamp,armStill,headOnPort,charge"

    public private(set) var rows: [Row] = []
    public private(set) var startedAt: TimeInterval?

    public init() {}

    public var isRecording: Bool { startedAt != nil }

    public mutating func begin(at now: TimeInterval) {
        rows.removeAll(keepingCapacity: true)
        startedAt = now
    }

    /// Append a row only while recording. Consecutive identical rows are
    /// still written: the timestamp is the point.
    public mutating func record(stepId: String, hostTimestamp: TimeInterval, armStill: Bool, headOnPort: Bool, charge: Double) {
        guard isRecording else { return }
        rows.append(Row(stepId: stepId, hostTimestamp: hostTimestamp, armStill: armStill, headOnPort: headOnPort, charge: charge))
    }

    public func csv() -> String {
        var lines = [SessionRecorder.csvHeader]
        lines.reserveCapacity(rows.count + 1)
        for r in rows {
            lines.append("\(r.stepId),\(String(format: "%.3f", r.hostTimestamp)),\(r.armStill ? 1 : 0),\(r.headOnPort ? 1 : 0),\(String(format: "%.3f", r.charge))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `chargeup-session-20261103-141502.csv`, from the session start.
    public func fileName(timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let date = Date(timeIntervalSince1970: startedAt ?? Date().timeIntervalSince1970)
        return "chargeup-session-\(f.string(from: date)).csv"
    }

    /// Write the CSV into `directory` and stop recording. Returns the file
    /// URL, or nil if there was nothing to write.
    @discardableResult
    public mutating func finish(into directory: URL) throws -> URL? {
        defer { startedAt = nil }
        guard isRecording, !rows.isEmpty else { return nil }
        let url = directory.appendingPathComponent(fileName())
        try csv().write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
