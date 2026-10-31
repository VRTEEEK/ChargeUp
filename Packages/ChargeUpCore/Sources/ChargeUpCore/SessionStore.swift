import Foundation

/// One completed session: the lantern that went up to the sky.
public struct SessionRecord: Codable, Equatable, Sendable, Identifiable {
    public var date: Date
    /// The charge object variant from sequence.json ("lantern").
    public var variant: String
    /// Fill reached when the needle came out, 0...1.
    public var fill: Double
    /// True for the fake sessions written so the demo sky is not empty.
    public var seeded: Bool

    public var id: Date { date }

    public init(date: Date, variant: String, fill: Double, seeded: Bool = false) {
        self.date = date
        self.variant = variant
        self.fill = fill
        self.seeded = seeded
    }
}

/// sessions.json in the headset's Documents: the only store for the sky.
public struct SessionStore: Sendable {
    public static let fileName = "sessions.json"

    public let directory: URL
    public private(set) var records: [SessionRecord] = []

    private var fileURL: URL { directory.appendingPathComponent(SessionStore.fileName) }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Loads whatever is on disk; a missing file is an empty sky, a corrupt
    /// file throws so the operator sees it rather than losing lanterns quietly.
    public init(directory: URL) throws {
        self.directory = directory
        if FileManager.default.fileExists(atPath: fileURL.path) {
            records = try SessionStore.decoder.decode([SessionRecord].self, from: Data(contentsOf: fileURL))
        }
    }

    public var count: Int { records.count }

    /// Oldest first.
    public var sorted: [SessionRecord] { records.sorted { $0.date < $1.date } }

    public mutating func append(_ record: SessionRecord) throws {
        records.append(record)
        try save()
    }

    /// Seeds `count` fake sessions only when the saved sky is empty, so a
    /// headset used for testing does not grow by a seed set on every launch.
    /// Returns true if it seeded.
    @discardableResult
    public mutating func seedIfEmpty(count: Int, variant: String, now: Date = Date()) throws -> Bool {
        guard records.isEmpty, count > 0 else { return false }
        try seed(count: count, variant: variant, now: now)
        return true
    }

    /// Clears the sky, then writes `seed` fake sessions if asked.
    public mutating func reset(seeding seed: Int = 0, variant: String, now: Date = Date()) throws {
        records = []
        if seed > 0 { try self.seed(count: seed, variant: variant, now: now) }
        try save()
    }

    /// Fake past sessions, one every three weeks going back from `now`,
    /// with fills between 0.7 and 1.0 so the cluster looks lived in.
    public mutating func seed(count: Int, variant: String, now: Date = Date()) throws {
        guard count > 0 else { return }
        for i in 0..<count {
            let weeksBack = Double(count - i) * 3
            let date = now.addingTimeInterval(-weeksBack * 7 * 24 * 3600)
            let fill = 0.7 + 0.3 * Double((i * 7) % 10) / 9
            records.append(SessionRecord(date: date, variant: variant, fill: fill, seeded: true))
        }
        try save()
    }

    private func save() throws {
        let data = try SessionStore.encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}
