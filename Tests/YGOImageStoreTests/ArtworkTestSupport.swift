import Foundation
import GRDB
import YGOCore
import YGONetworking
import YGOPersistence

enum ArtworkFixture {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let storedAt = Date(timeIntervalSince1970: 1_758_000_000)

    static func cards() throws -> [CatalogCardPayload] {
        try YGOProDeckCatalogClient.decodeDataset(
            Data(contentsOf: root.appending(path: "fixtures/catalog-en.json")))
    }

    /// A catalog holding the fixture's cards and artworks, with a throwaway
    /// directory for the image files.
    static func seededDatabase() throws -> (DatabaseQueue, URL) {
        var configuration = GRDB.Configuration()
        configuration.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: configuration)
        try CatalogSchema.migrator.migrate(queue)
        try queue.write { db in
            try CatalogWriter().writeEnglishDataset(
                try cards(), observedAt: storedAt, into: db)
        }

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ygo-artwork-\(UUID().uuidString)")
        return (queue, directory)
    }

    /// Stand-in image bytes; the store does not decode them.
    static func imageBytes(_ marker: String) -> Data { Data(marker.utf8) }
}
