import Foundation
import GRDB
import Testing
import YGOCore
import YGOPersistence
@testable import YGOComposition

/// Measured against a catalog the size of the real one, in a temporary
/// directory. These run in a debug build, so a pass here is a conservative
/// reading: the shipped build is optimised.
@Suite(.serialized)
struct CatalogPerformanceTests {
    private static let observedAt = Date(timeIntervalSince1970: 1_758_000_000)

    /// A seeded full-size database. Building it is the expensive part, so both
    /// measurements in this suite are driven from one.
    private func seededDatabase() throws -> (DatabasePool, URL) {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "ygo-perf-\(UUID().uuidString)")
        let database = try DatabaseBootstrapper(
            configuration: .init(containerURL: container)).open()

        let english = try SyntheticCatalog.payload()
        let italian = try SyntheticCatalog.italianPayload(from: english)
        #expect(english.count == SyntheticCatalog.cardCount)

        try database.write { db in
            let writer = CatalogWriter()
            try writer.writeEnglishDataset(english, observedAt: Self.observedAt, into: db)
            try writer.mergeItalianDataset(italian, into: db)
        }

        return (database, container)
    }

    /// Evidence for NFR1: a search over the whole pool returns its first page
    /// within the budget. The FTS index and the filter-column indexes are what
    /// make this hold; the assertion is on the 95th percentile so one slow
    /// sample cannot hide a systematic problem, and one cannot fail it either.
    @Test func searchLatencyP95StaysUnderOneHundredMilliseconds() async throws {
        let (database, container) = try seededDatabase()
        defer {
            try? database.close()
            try? FileManager.default.removeItem(at: container)
        }
        let repository = SQLiteCardRepository(database: database)

        let queries: [CardQuery] = [
            CardQuery(text: "synthetic", limit: 100),
            CardQuery(text: "eternal vanguard", limit: 100),
            CardQuery(text: "carta sintetica", limit: 100),
            CardQuery(text: "banish", limit: 100),
            CardQuery(text: "guardia", limit: 100),
            CardQuery(filters: {
                var f = CardFilters(); f.frames = [.effect]; f.levels = 4...8; return f
            }(), limit: 100),
            CardQuery(filters: {
                var f = CardFilters(); f.format = .tcg; f.attack = 1000...3000; return f
            }(), limit: 100),
            CardQuery(text: "vanguard", filters: {
                var f = CardFilters(); f.format = .tcg
                f.banStatuses = [.forbidden, .limited, .semiLimited]
                return f
            }(), limit: 100),
        ]

        // One untimed pass so the measurement is not dominated by first-use
        // costs such as statement preparation.
        for query in queries { _ = try await repository.search(query) }

        var samples: [Double] = []
        for _ in 0..<6 {
            for query in queries {
                let started = ContinuousClock.now
                let outcome = try await repository.search(query)
                samples.append(
                    Double(started.duration(to: .now).components.attoseconds) / 1e15)
                // A query returning nothing would make the timing meaningless.
                #expect(!outcome.cards.isEmpty, "query senza risultati: \(query.text ?? "filtri")")
            }
        }

        samples.sort()
        let p95 = samples[Int(Double(samples.count) * 0.95)]
        let worst = samples.last ?? 0
        #expect(p95 < 100, "p95 \(String(format: "%.1f", p95)) ms, peggiore \(String(format: "%.1f", worst)) ms")
    }

    /// Evidence for NFR2: reads run beside a synchronisation write rather than
    /// behind it. A write-ahead log is what allows that; a plain queue would
    /// serialise the two and freeze the grid for the length of an update.
    ///
    /// The writer publishes how far it has got, so a read only counts when the
    /// write was demonstrably still open both before and after it. Timing the
    /// reads against a task that had already finished would prove nothing.
    @Test func readsProceedConcurrentlyWithOpenSyncWrite() async throws {
        let (database, container) = try seededDatabase()
        defer {
            try? database.close()
            try? FileManager.default.removeItem(at: container)
        }
        let repository = SQLiteCardRepository(database: database)
        let progress = WriteProgress()

        let writing = Task.detached {
            try await database.write { db in
                let statement = try db.makeStatement(sql:
                    "UPDATE card SET md_rarity = ? WHERE id = ?")
                for index in 0..<SyntheticCatalog.cardCount {
                    try statement.execute(arguments: ["Rare \(index)", 10_000_000 + index])
                    if index % 100 == 0 { progress.advance(to: index) }
                }
                progress.finish()
            }
        }

        var readsDuringWrite = 0
        var readLatencies: [Double] = []

        while !progress.isFinished, readsDuringWrite < 40 {
            let before = progress.rowsWritten
            let started = ContinuousClock.now
            let outcome = try await repository.search(CardQuery(text: "synthetic", limit: 50))
            let elapsed = Double(started.duration(to: .now).components.attoseconds) / 1e15
            let after = progress.rowsWritten

            #expect(!outcome.cards.isEmpty)

            // Count it only if the writer was mid-flight throughout.
            if !progress.isFinished, after > before {
                readsDuringWrite += 1
                readLatencies.append(elapsed)
            }
        }

        try await writing.value

        #expect(readsDuringWrite > 0,
                "nessuna lettura è stata completata mentre la scrittura era ancora aperta")
        #expect(progress.rowsWritten > 0)

        let slowest = readLatencies.max() ?? 0
        #expect(slowest < 500,
                "lettura più lenta \(String(format: "%.1f", slowest)) ms: sembra bloccata dalla scrittura")
    }
}

/// How far the background write has got, readable from another task.
private final class WriteProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var written = 0
    private var finished = false

    var rowsWritten: Int {
        lock.lock(); defer { lock.unlock() }
        return written
    }

    var isFinished: Bool {
        lock.lock(); defer { lock.unlock() }
        return finished
    }

    func advance(to count: Int) {
        lock.lock(); defer { lock.unlock() }
        written = count
    }

    func finish() {
        lock.lock(); defer { lock.unlock() }
        finished = true
    }
}
