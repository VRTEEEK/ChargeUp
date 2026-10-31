import Foundation
import Testing
@testable import ChargeUpCore

@Suite struct SessionStoreTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("chargeup-sky-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func emptyDirectoryIsAnEmptySky() throws {
        let store = try SessionStore(directory: try tempDir())
        #expect(store.count == 0)
        #expect(store.records.isEmpty)
    }

    @Test func appendPersistsAndReloads() throws {
        let dir = try tempDir()
        var store = try SessionStore(directory: dir)
        let a = SessionRecord(date: Date(timeIntervalSince1970: 1_700_000_000), variant: "lantern", fill: 0.9)
        let b = SessionRecord(date: Date(timeIntervalSince1970: 1_690_000_000), variant: "lantern", fill: 1.0)
        try store.append(a)
        try store.append(b)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(SessionStore.fileName).path))
        let reloaded = try SessionStore(directory: dir)
        #expect(reloaded.records == [a, b])
        #expect(reloaded.sorted == [b, a], "oldest first")
    }

    @Test func seedWritesTheConfiguredNumberOfPastSessions() throws {
        let config = try ChargeSequence.shipped().config.sky
        #expect(config.seededSessions == 6)
        var store = try SessionStore(directory: try tempDir())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try store.seed(count: config.seededSessions, variant: "lantern", now: now)
        #expect(store.count == 6)
        #expect(store.records.allSatisfy { $0.seeded && $0.variant == "lantern" && (0.7...1.0).contains($0.fill) })
        #expect(store.records.allSatisfy { $0.date < now })
        #expect(store.sorted == store.records, "seeded oldest first")
        #expect(store.records.last!.date.timeIntervalSince(now) == -3 * 7 * 24 * 3600, "latest seed is three weeks ago")
    }

    @Test func seedIfEmptyNeverGrowsASavedSky() throws {
        let dir = try tempDir()
        var store = try SessionStore(directory: dir)
        #expect(try store.seedIfEmpty(count: 6, variant: "lantern"))
        try store.append(SessionRecord(date: Date(), variant: "lantern", fill: 0.9))
        // A relaunch: the saved sky has lanterns, so nothing is added.
        var relaunched = try SessionStore(directory: dir)
        #expect(try !relaunched.seedIfEmpty(count: 6, variant: "lantern"))
        #expect(try SessionStore(directory: dir).count == 7)
    }

    @Test func resetClearsThenReseeds() throws {
        let dir = try tempDir()
        var store = try SessionStore(directory: dir)
        try store.append(SessionRecord(date: Date(), variant: "lantern", fill: 1))
        try store.reset(seeding: 0, variant: "lantern")
        #expect(try SessionStore(directory: dir).count == 0)
        try store.reset(seeding: 3, variant: "lantern")
        #expect(try SessionStore(directory: dir).count == 3)
    }

    @Test func corruptFileThrows() throws {
        let dir = try tempDir()
        try Data("not json".utf8).write(to: dir.appendingPathComponent(SessionStore.fileName))
        #expect(throws: (any Error).self) { try SessionStore(directory: dir) }
    }
}
