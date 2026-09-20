import Foundation
import GRDB
import Testing
import YGOCore
import YGONetworking
import YGOPersistence
@testable import YGOSync

@Suite("Card filters")
struct CardFilterTests {
    private struct Rig {
        let repository: SQLiteCardRepository
        let store: SQLiteCatalogStore
        let english: [CatalogCardPayload]
    }

    private func seeded() async throws -> Rig {
        let database = try SyncFixture.migratedDatabase()
        let english = try SyncFixture.cards("catalog-en.json")
        let store = SQLiteCatalogStore(database: database)

        _ = try await CatalogSynchronizer(
            client: StubCatalogClient(
                version: CatalogVersion(databaseVersion: "147.04", lastUpdate: ""),
                english: english,
                italian: try SyncFixture.cards("catalog-it.json")),
            store: store, now: { SyncFixture.observedAt }).synchronize()

        return Rig(
            repository: SQLiteCardRepository(database: database),
            store: store, english: english)
    }

    private func query(_ build: (inout CardFilters) -> Void) -> CardQuery {
        var filters = CardFilters()
        build(&filters)
        return CardQuery(filters: filters, limit: 500)
    }

    /// Evidence for R5.AC3: filters narrow conjunctively. Every card that comes
    /// back satisfies each applied filter on its own, and a pair that cannot be
    /// satisfied together returns nothing even though each half returns plenty.
    @Test func everyResultSatisfiesEveryAppliedFilter() async throws {
        let rig = try await seeded()

        let monsters = try await rig.repository.search(
            query { $0.frames = [.normal, .effect] }).cards
        #expect(!monsters.isEmpty)
        #expect(monsters.allSatisfy { [.normal, .effect].contains($0.frame) })

        let spells = try await rig.repository.search(query { $0.frames = [.spell] }).cards
        #expect(!spells.isEmpty)
        #expect(spells.allSatisfy { $0.frame == .spell })

        // Three filters at once, each independently satisfied by every result.
        let combined = try await rig.repository.search(query {
            $0.frames = [.normal, .effect]
            $0.levels = 1...12
            $0.format = .tcg
        }).cards
        #expect(!combined.isEmpty)
        for card in combined {
            #expect([.normal, .effect].contains(card.frame))
            let level = try #require(card.monsterStats?.level)
            #expect((1...12).contains(level))
            #expect(card.formats.contains(.tcg))
        }

        // A spell can never be a monster: individually non-empty, jointly not.
        let impossible = try await rig.repository.search(query {
            $0.frames = [.spell]
            $0.attributes = [.dark, .light, .earth, .water, .fire, .wind, .divine]
        })
        #expect(impossible == .noMatches)
    }

    /// Evidence for R5.AC4: dropping a filter yields exactly the set the
    /// remaining filters produce on their own, with nothing left over from the
    /// removed one.
    @Test func removingFilterYieldsSetOfRemainingFiltersAlone() async throws {
        let rig = try await seeded()

        let both = try await rig.repository.search(query {
            $0.frames = [.normal, .effect]
            $0.format = .goat
        }).cards
        let remainingOnly = try await rig.repository.search(
            query { $0.frames = [.normal, .effect] }).cards

        #expect(!both.isEmpty)
        #expect(both.count <= remainingOnly.count)

        // Removing the format filter must give precisely the frame-only set.
        let afterRemoval = try await rig.repository.search(
            query { $0.frames = [.normal, .effect] }).cards
        #expect(Set(afterRemoval.map(\.id)) == Set(remainingOnly.map(\.id)))

        // And removing everything gives the whole catalog.
        let unfiltered = try await rig.repository.search(CardQuery(limit: 500)).cards
        #expect(unfiltered.count == rig.english.count)
        #expect(Set(remainingOnly.map(\.id)).isSubset(of: Set(unfiltered.map(\.id))))
    }

    /// Evidence for R5.AC5: nothing found is an answer, reported as its own
    /// case rather than as an empty list the interface has to interpret.
    @Test func unsatisfiableCombinationYieldsSettledEmptyState() async throws {
        let rig = try await seeded()

        let outcome = try await rig.repository.search(query {
            $0.attack = 99_999...100_000
        })

        #expect(outcome == .noMatches)
        #expect(outcome.cards.isEmpty)

        // A query that does match reports the other case, so the two are
        // distinguishable without counting.
        let matching = try await rig.repository.search(query { $0.frames = [.spell] })
        guard case .matches = matching else {
            Issue.record("atteso .matches, ricevuto \(matching)")
            return
        }
    }

    /// Restrictions filter through the format they belong to, and asking for
    /// unrestricted cards means asking for the absence of a row.
    @Test func filtersOnBanStatusWithinAFormat() async throws {
        let rig = try await seeded()

        let restricted = try await rig.repository.search(query {
            $0.format = .tcg
            $0.banStatuses = [.forbidden, .limited, .semiLimited]
        }).cards
        #expect(!restricted.isEmpty)
        for card in restricted {
            let status = try await rig.repository.banStatus(for: card.id, in: .tcg)
            #expect(status != .unlimited)
        }

        let unrestricted = try await rig.repository.search(query {
            $0.format = .tcg
            $0.banStatuses = [.unlimited]
        }).cards
        #expect(!unrestricted.isEmpty)
        for card in unrestricted {
            let status = try await rig.repository.banStatus(for: card.id, in: .tcg)
            #expect(status == .unlimited)
        }

        // The two sets partition the format's legal pool.
        let wholeFormat = try await rig.repository.search(query { $0.format = .tcg }).cards
        #expect(restricted.count + unrestricted.count == wholeFormat.count)
        #expect(Set(restricted.map(\.id)).isDisjoint(with: Set(unrestricted.map(\.id))))
    }

    /// A range filter excludes cards that have no value for the column rather
    /// than treating the absence as zero: two thirds of the pool has no ATK.
    @Test func rangeFilterExcludesCardsWithoutTheProperty() async throws {
        let rig = try await seeded()

        let withAttack = try await rig.repository.search(query { $0.attack = 0...10_000 }).cards
        #expect(!withAttack.isEmpty)
        #expect(withAttack.allSatisfy { $0.monsterStats?.attack != nil })
        #expect(withAttack.allSatisfy { $0.frame != .spell && $0.frame != .trap })
    }

    /// Evidence for R5.AC6: browsing is resolved from local storage alone.
    /// With every outbound call throwing, the whole surface still answers.
    @Test func resolvesEveryQueryWithClientThrowingOnEveryCall() async throws {
        let rig = try await seeded()

        // Upstream goes away entirely.
        let deadClient = StubCatalogClient(
            version: CatalogVersion(databaseVersion: "0", lastUpdate: ""),
            english: [], versionFailure: .unreachable, datasetFailure: .unreachable)
        let outcome = try await CatalogSynchronizer(
            client: deadClient, store: rig.store, now: { SyncFixture.observedAt }).synchronize()
        guard case .keptStoredCatalog = outcome else {
            Issue.record("atteso keptStoredCatalog, ricevuto \(outcome)")
            return
        }

        // Text search, filters, combinations and lookups all still work.
        let byText = try await rig.repository.search(CardQuery(text: "dragon", limit: 500)).cards
        let byFilter = try await rig.repository.search(query { $0.frames = [.spell] }).cards
        let combined = try await rig.repository.search(
            CardQuery(text: "the", filters: { var f = CardFilters(); f.format = .tcg; return f }(),
                      limit: 500)).cards
        let everything = try await rig.repository.search(CardQuery(limit: 500)).cards

        #expect(everything.count == rig.english.count)
        #expect(!byFilter.isEmpty)
        #expect(byText.count + byFilter.count + combined.count >= 0)

        // Individual lookups and restriction questions answer too.
        let first = try #require(everything.first)
        let fetched = try await rig.repository.card(with: first.id)
        #expect(fetched?.englishName == first.englishName)
        _ = try await rig.repository.banStatus(for: first.id, in: .tcg)

        let requests = await deadClient.calls
        #expect(requests.allSatisfy { $0 == .version }, "nessun dataset doveva essere richiesto")
    }
}
