import Foundation
import GRDB
import Testing
import YGOBanlistHistory
import YGOCore
import YGOFeatureBrowser
import YGOPersistence
@testable import YGOFeatureCardDetail

@MainActor
@Suite("Card detail budgets")
struct CardDetailBudgetTests {
    /// A catalog the size of the real one, so the budgets are measured against
    /// what the application actually holds rather than a handful of rows.
    private static let catalogSize = 14_566

    private func seededDatabase() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try CatalogSchema.migrator.migrate(queue)

        try queue.write { db in
            for index in 1...Self.catalogSize {
                try db.execute(sql: """
                    INSERT INTO card (id, name_en, desc_en, name_it, desc_it,
                                      type, frame_type, human_readable_type,
                                      tcg_date, ocg_date, konami_id)
                    VALUES (?, ?, 'effect text', ?, 'testo effetto',
                            'Spell Card', 'spell', 'Spell Card',
                            '2002-03-08', '1999-01-21', ?)
                    """, arguments: [
                        index,
                        String(format: "Card %05d", index),
                        index % 5 == 0 ? nil : String(format: "Carta %05d", index),
                        index,
                    ])
            }
            // One card printed many times over, like Blue-Eyes with its 78.
            for index in 1...78 {
                try db.execute(sql: """
                    INSERT INTO card_print
                        (card_id, set_code, set_name, rarity, rarity_code, set_price)
                    VALUES (1, ?, ?, 'Common', '(C)', 1.0)
                    """, arguments: [String(format: "SET-%03d", index),
                                     String(format: "Set %03d", index)])
            }
            for source in ["cardmarket", "tcgplayer", "ebay", "amazon", "coolstuffinc"] {
                try db.execute(sql: """
                    INSERT INTO card_price (card_id, source, value, observed_at)
                    VALUES (1, ?, 2.89, '2026-09-21T09:00:00Z')
                    """, arguments: [source])
            }
        }

        // 73 lists, the number the TCG actually has.
        let history = SQLiteBanlistHistory(database: queue)
        for year in 1954...2026 {
            try history.store(
                PublishedBanlist(effectiveDate: "\(year)-03-01",
                                 statuses: [1: .limited]),
                format: .tcg, source: "yaml-yugi-limit-regulation", fetchedAt: .now)
        }
        return queue
    }

    private func loader(_ queue: DatabaseQueue) -> CardDetailLoader {
        CardDetailLoader(
            catalog: SQLiteCardRepository(database: queue),
            details: SQLiteCardDetailReader(database: queue),
            usage: SQLiteCardUsageReader(database: queue),
            priceLookup: SQLitePriceRepository(database: queue),
            history: SQLiteBanlistHistory(database: queue),
            provenance: SQLiteBanlistHistory(database: queue))
    }

    private func firstCard(_ queue: DatabaseQueue) async throws -> Card {
        let repository = SQLiteCardRepository(database: queue)
        return try #require(try await repository.card(with: CardIdentifier(1)))
    }

    /// Evidence for NFR1: narrowing has to feel like filtering. Measured end
    /// to end against a full-sized catalog, not against a stub.
    @Test func narrowingFollowsAKeystrokeWithinOneHundredFiftyMilliseconds() async throws {
        let queue = try seededDatabase()
        let repository = SQLiteCardRepository(database: queue)
        let browser = BrowserViewModel(
            repository: repository,
            counter: repository,
            artwork: StubArtworkStore(),
            banStatusProvider: repository,
            language: .italian)

        await browser.start()
        #expect(browser.matchCount == Self.catalogSize)

        var worst: Double = 0
        for text in ["c", "ca", "car", "cart", "carta"] {
            browser.queryText = text
            let started = DispatchTime.now().uptimeNanoseconds
            await browser.queryChanged()
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            worst = max(worst, elapsed)
        }

        #expect(worst < 150, "worst keystroke \(worst) ms")
        #expect(browser.items.count > 0)
    }

    /// Evidence for NFR2: the panel is read the moment it opens, so every
    /// section that comes from stored data has to be there by then.
    @Test func everyStoredSectionIsReadyWithinOneHundredMilliseconds() async throws {
        let queue = try seededDatabase()
        let card = try await firstCard(queue)
        let detailLoader = loader(queue)

        // Warm the statement cache: the budget is a panel opening in a running
        // application, not the first query after a cold start.
        _ = await detailLoader.load(card, language: .italian, format: .tcg)

        var worst: Double = 0
        for _ in 0..<10 {
            let started = DispatchTime.now().uptimeNanoseconds
            let detail = await detailLoader.load(card, language: .italian, format: .tcg)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            worst = max(worst, elapsed)

            #expect(detail.printings.value?.count == 78)
            #expect(detail.prices.count == 5)
            #expect(detail.history.timelineValue != nil)
        }

        #expect(worst < 100, "worst open \(worst) ms")
    }

    /// Evidence for NFR3: everything but the full artwork is already on disk.
    /// Proven by loading the panel with no artwork stored at all and with
    /// nothing that could reach a network in the graph.
    @Test func everySectionButTheArtworkIsProducedOffline() async throws {
        let queue = try seededDatabase()
        let card = try await firstCard(queue)

        let panel = CardDetailViewModel(
            loader: loader(queue),
            artwork: StubArtworkStore())   // nothing stored, nothing fetchable
        await panel.select(card, language: .italian)

        let detail = try #require(panel.detail)
        #expect(detail.text.name == "Carta 00001")
        #expect(detail.printings.value?.count == 78)
        #expect(detail.prices.filter { !$0.isUnpriced }.count == 5)
        #expect(detail.history.timelineValue?.entries.isEmpty == false)
        #expect(detail.release.isKnown)
        #expect(detail.holdings.isEmpty)
        #expect(detail.deckUses.isEmpty)

        // The artwork is the one thing that needed the network, and its
        // absence degrades to a named placeholder rather than a blank.
        #expect(panel.artwork == .placeholder(cardName: "Carta 00001"))
    }

    /// Evidence for NFR4: six ways a piece can be missing, and none of them
    /// may reach the reader as a zero, a blank, or a confident default.
    @Test func noAbsentPieceIsRenderedAsZeroOrBlank() async throws {
        var details = StubDetailReader()
        details.releases = [DetailCards.untranslated.id: .unknown]
        // No konami id, no printings, no prices, no copies, no decks.

        var history = StubBanlistHistory()
        history.revisionDates = [.tcg: ["2026-05-18"]]

        let detail = await CardDetailLoader(
            catalog: StubCardRepository(cards: [DetailCards.untranslated]),
            details: details,
            usage: StubUsageReader(),
            priceLookup: StubPriceLookup(),
            history: history,
            provenance: history
        ).load(DetailCards.untranslated, language: .italian, format: .tcg)

        // 1. Untranslated: English text, and said so.
        #expect(detail.isUntranslated)
        #expect(!detail.text.name.isEmpty)

        // 2. No release date: stated, not an empty string.
        #expect(detail.release == .unknown)
        #expect(CardDetailNarration.release(.unknown) == "Data di uscita sconosciuta")

        // 3. No printing: a reason, not an empty table.
        #expect(detail.printings.isEmpty)
        #expect(detail.printings.message?.isEmpty == false)

        // 4. No price: five lines, all unpriced, none of them zero.
        #expect(detail.prices.count == 5)
        #expect(detail.prices.allSatisfy { $0.money == nil })
        #expect(detail.prices.allSatisfy {
            !CardDetailNarration.price($0).contains("0,00")
        })

        // 5. Nothing owned and nothing built: both stated.
        #expect(detail.holdings.message?.contains("Non possiedi") == true)
        #expect(detail.deckUses.message?.contains("Nessun mazzo") == true)

        // 6. No konami id: unavailable, which is not "never restricted".
        if case let .unavailable(reason) = detail.history {
            #expect(!reason.isEmpty)
        } else {
            Issue.record("expected unavailable, got \(detail.history)")
        }
        #expect(detail.history != .neverRestricted(format: .tcg))

        // None of the six is silently empty: each carries something to read.
        let messages = [detail.printings.message, detail.holdings.message,
                        detail.deckUses.message]
        #expect(messages.allSatisfy { ($0?.count ?? 0) > 10 })
    }
}
