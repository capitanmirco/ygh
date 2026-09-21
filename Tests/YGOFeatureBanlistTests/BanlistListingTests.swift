import Foundation
import Testing
import YGOCore
@testable import YGOFeatureBanlist

@Suite("Banlist listing")
struct BanlistListingTests {
    /// The GOAT-defining list's measured shape: 18 forbidden (6 monsters, 10
    /// spells, 2 traps), 44 limited (22, 12, 10), 15 semi-limited (6, 6, 3).
    static func goatList() -> [BanlistListEntry] {
        var entries: [BanlistListEntry] = []
        var id = 1

        func add(_ status: BanlistStatus, _ frame: CardFrame, _ count: Int) {
            for index in 0..<count {
                entries.append(BanlistListEntry(
                    konamiID: id, cardID: id,
                    name: String(format: "%@ %02d", frame.rawValue, count - index),
                    italianName: nil, status: status, frame: frame))
                id += 1
            }
        }

        add(.forbidden, .effect, 6)
        add(.forbidden, .spell, 10)
        add(.forbidden, .trap, 2)
        add(.limited, .effect, 22)
        add(.limited, .spell, 12)
        add(.limited, .trap, 10)
        add(.semiLimited, .effect, 6)
        add(.semiLimited, .spell, 6)
        add(.semiLimited, .trap, 3)
        return entries.shuffled()
    }

    /// Evidence for R1.AC1: a list is read in three blocks, and those are the
    /// three the source stores. There is no fourth, because a card absent
    /// from a list is unrestricted on it.
    @Test func theGoatListYieldsGroupsOfEighteenFortyFourAndFifteen() {
        let groups = BanlistListing.groups(from: Self.goatList())

        #expect(groups.count == 3)
        #expect(groups.map(\.count) == [18, 44, 15])
        #expect(groups.map(\.count).reduce(0, +) == 77)

        // Each group holds only its own status.
        for group in groups {
            #expect(group.cards.allSatisfy { $0.status == group.status })
        }
    }

    /// Evidence for R1.AC2: most restrictive first, which is how every
    /// published list is laid out.
    @Test func forbiddenPrecedesLimitedPrecedesSemiLimited() {
        let groups = BanlistListing.groups(from: Self.goatList())

        #expect(groups.map(\.status) == [.forbidden, .limited, .semiLimited])
        #expect(groups[0].italianName == "Proibite")
        #expect(groups[1].italianName == "Limitate")
        #expect(groups[2].italianName == "Semi-limitate")

        // The order is the constant, not an accident of the input.
        #expect(BanlistListing.statusOrder == [.forbidden, .limited, .semiLimited])
    }

    /// Evidence for R1.AC3, and the reason ordering by kind is not cosmetic:
    /// among the forbidden, spells outnumber monsters ten to six, while among
    /// the limited the monsters lead twenty-two to twelve. What you see first
    /// in a block depends on this.
    @Test func monstersPrecedeSpellsPrecedeTrapsWithinAGroup() {
        let groups = BanlistListing.groups(from: Self.goatList())

        func kinds(_ group: BanlistGroup) -> [CardType] {
            group.cards.compactMap { $0.frame?.cardType }
        }

        let forbidden = kinds(groups[0])
        #expect(forbidden.prefix(6).allSatisfy { $0 == .monster })
        #expect(forbidden.dropFirst(6).prefix(10).allSatisfy { $0 == .spell })
        #expect(forbidden.suffix(2).allSatisfy { $0 == .trap })

        let limited = kinds(groups[1])
        #expect(limited.prefix(22).allSatisfy { $0 == .monster })
        #expect(limited.dropFirst(22).prefix(12).allSatisfy { $0 == .spell })
        #expect(limited.suffix(10).allSatisfy { $0 == .trap })

        // Every group is ordered by the same rank, never re-sorted by name
        // across kinds.
        for group in groups {
            let ranks = group.cards.map { BanlistListing.rank($0.frame) }
            #expect(ranks == ranks.sorted(), "\(group.italianName) is out of order")
        }
    }

    /// Evidence for R1.AC4: within a kind, a list reads alphabetically,
    /// because that is how you find a name you are looking for.
    @Test func cardsOfOneKindReadAlphabetically() {
        let entries = [
            BanlistListEntry(konamiID: 1, cardID: 1, name: "Zombyra",
                             italianName: nil, status: .limited, frame: .effect),
            BanlistListEntry(konamiID: 2, cardID: 2, name: "Airknight",
                             italianName: nil, status: .limited, frame: .effect),
            BanlistListEntry(konamiID: 3, cardID: 3, name: "Morphing Jar",
                             italianName: nil, status: .limited, frame: .effect),
            BanlistListEntry(konamiID: 4, cardID: 4, name: "Delinquent Duo",
                             italianName: nil, status: .limited, frame: .spell),
            BanlistListEntry(konamiID: 5, cardID: 5, name: "Confiscation",
                             italianName: nil, status: .limited, frame: .spell),
        ]

        let group = BanlistListing.groups(from: entries)[1]
        #expect(group.cards.map(\.displayName)
                == ["Airknight", "Morphing Jar", "Zombyra", "Confiscation", "Delinquent Duo"])

        // The Italian name is what sorts when there is one, because that is
        // what the reader sees.
        let translated = [
            BanlistListEntry(konamiID: 6, cardID: 6, name: "Zombyra",
                             italianName: "Anfora", status: .limited, frame: .effect),
            BanlistListEntry(konamiID: 7, cardID: 7, name: "Airknight",
                             italianName: "Zaffiro", status: .limited, frame: .effect),
        ]
        #expect(BanlistListing.groups(from: translated)[1].cards.map(\.displayName)
                == ["Anfora", "Zaffiro"])
    }

    /// Evidence for R1.AC5: a block's size is the first thing read about it.
    @Test func eachGroupStatesItsCountAndTheThreeSumToTheList() {
        let entries = Self.goatList()
        let groups = BanlistListing.groups(from: entries)

        for group in groups {
            #expect(group.count == group.cards.count)
        }
        #expect(groups.map(\.count).reduce(0, +) == entries.count)

        // An empty list yields three empty groups rather than no groups, so
        // the screen has the same shape whatever it is showing.
        let empty = BanlistListing.groups(from: [])
        #expect(empty.count == 3)
        #expect(empty.allSatisfy { $0.count == 0 })
    }

    /// Evidence for R1.AC6: 203 of 14,566 cards carry no Konami identifier,
    /// and a list can name a card released since the last catalog sync. The
    /// arithmetic closing is what proves nothing is quietly lost.
    @Test func groupedPlusUnmatchedEqualsTheListsSize() {
        var entries = Self.goatList()
        // Three entries the catalog cannot name.
        for index in 0..<3 {
            entries.append(BanlistListEntry(
                konamiID: 90_000 + index, cardID: nil, name: nil,
                italianName: nil, status: .forbidden, frame: nil))
        }

        let groups = BanlistListing.groups(from: entries)
        let unmatched = BanlistListing.unmatched(in: entries)

        #expect(unmatched == 3)
        #expect(groups.map(\.count).reduce(0, +) + unmatched == entries.count)

        // The unmatched ones are counted, not shown as bare identifiers.
        #expect(groups.allSatisfy { $0.cards.allSatisfy { $0.cardID != nil } })
        #expect(groups[0].count == 18)

        // A list with nothing unmatched reports zero rather than nothing.
        #expect(BanlistListing.unmatched(in: Self.goatList()) == 0)
    }

    /// Evidence for R1.AC6: a card the catalog holds but whose frame it does
    /// not recognise is still a card on the list.
    @Test func anEntryWithNoKindSortsLastRatherThanVanishing() {
        let entries = [
            BanlistListEntry(konamiID: 1, cardID: 1, name: "Una trappola",
                             italianName: nil, status: .forbidden, frame: .trap),
            BanlistListEntry(konamiID: 2, cardID: 2, name: "Senza tipo",
                             italianName: nil, status: .forbidden, frame: nil),
            BanlistListEntry(konamiID: 3, cardID: 3, name: "Un mostro",
                             italianName: nil, status: .forbidden, frame: .effect),
        ]

        let group = BanlistListing.groups(from: entries)[0]
        #expect(group.count == 3, "the entry without a kind was dropped")
        #expect(group.cards.map(\.displayName) == ["Un mostro", "Una trappola", "Senza tipo"])

        // It is not counted as unmatched: the catalog knows the card, just
        // not its frame.
        #expect(BanlistListing.unmatched(in: entries) == 0)
        #expect(BanlistListing.rank(nil) > BanlistListing.rank(.trap))
    }
}
