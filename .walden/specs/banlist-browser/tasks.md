---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T19:45:54Z
last_modified: 2026-09-21T19:52:53Z
approved_fingerprint: sha256:6a42899b17c84c148d104cad9b0302a3331b65cddab42bfb7a214bb1c2181212
source_design_approved_at: 2026-09-21T19:45:15Z
source_design_fingerprint: sha256:474774205f5ddd37fc4efae00cabf31d4457b905ed93a3a331a2551e495fec92
---

# Implementation Plan

Five executable tasks. The runner marker asserted throughout is `Test <name>() passed`.

Task 1 is the grouping, because it is the whole of this feature's new behaviour and the only part that can be objectively wrong: the ordering is two enumerations and a string, and getting an enumeration's order wrong is silent.

The figures asserted below were measured against the user's own database on 2026-09-21, after a synchronisation: 177 stored lists — 73 TCG, 66 Master Duel, 23 OCG, 15 Rush Duel — holding 28,648 entries. The GOAT-defining list holds 77 cards: 18 forbidden (6 monsters, 10 spells, 2 traps), 44 limited (22, 12, 10) and 15 semi-limited (6, 6, 3).

- [x] 1. Group a list the way a list is read
  - Requirements: `R1.AC1`, `R1.AC2`, `R1.AC3`, `R1.AC4`, `R1.AC5`
  - Design: Architecture, Data Model
  - Notes: Three keys — status, kind, name — of which two are enumerations whose order is a rule about the game rather than about strings. In SQL that is a `CASE` ladder nobody can read and that cannot be proven without a database; in Swift it is a comparator over entries. `CardType` already collapses the seventeen frames into the four this needs, so the second key is a property rather than a new classification.
  - Verification:
    - command: ["swift", "test", "--filter", "BanlistListingTests"]
      expect_output: "Test theGoatListYieldsGroupsOfEighteenFortyFourAndFifteen() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "BanlistListingTests"]
      expect_output: "Test forbiddenPrecedesLimitedPrecedesSemiLimited() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "BanlistListingTests"]
      expect_output: "Test monstersPrecedeSpellsPrecedeTrapsWithinAGroup() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "BanlistListingTests"]
      expect_output: "Test cardsOfOneKindReadAlphabetically() passed"
      covers: ["R1.AC4"]
    - command: ["swift", "test", "--filter", "BanlistListingTests"]
      expect_output: "Test eachGroupStatesItsCountAndTheThreeSumToTheList() passed"
      covers: ["R1.AC5"]

- [x] 2. Account for every entry
  - Requirements: `R1.AC6`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: A list names `konami_id`s, and 203 of the catalog's 14,566 cards carry none. Those entries have no name and no kind, so they are counted rather than shown — a row reading *konami_id 4007* among card names is noise, and dropping them in silence is worse than both. The arithmetic closing is the check that this screen is not quietly losing rows. An entry with no kind sorts last within its group rather than disappearing.
  - Verification:
    - command: ["swift", "test", "--filter", "BanlistListingTests"]
      expect_output: "Test groupedPlusUnmatchedEqualsTheListsSize() passed"
      covers: ["R1.AC6"]
    - command: ["swift", "test", "--filter", "BanlistListingTests"]
      expect_output: "Test anEntryWithNoKindSortsLastRatherThanVanishing() passed"
      covers: ["R1.AC6"]

- [x] 3. Carry the card's kind out of storage
  - Requirements: `R1.AC3`
  - Design: Data Model, Options Considered
  - Notes: `BanlistListEntry` carries the identifier, the names and the status, which is not enough to order a block by kind. The query already joins `card` to fetch those names, so the kind is one more column rather than a second join and a second type. Additive, on a type whose readers are this feature and `banlist-history`'s own tests.
  - Verification:
    - command: ["swift", "test", "--filter", "BanlistEntryKindTests"]
      expect_output: "Test aStoredEntryCarriesItsCardsKind() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "BanlistEntryKindTests"]
      expect_output: "Test anUnmatchedEntryCarriesNoKindJustAsItCarriesNoName() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "BanlistEntryKindTests"]
      expect_output: "Test theGoatListsKindsMatchWhatTheCatalogSays() passed"
      covers: ["R1.AC3"]

- [x] 4. Choose which list to read
  - Requirements: `R2.AC1`, `R2.AC2`, `R2.AC3`, `R2.AC4`, `R2.AC5`
  - Design: Architecture, Options Considered
  - Notes: Newest first, unlike the catalog's chooser: that one is a history to look back through, this one opens on the rules as they are now. A format frozen at a list names it, because GOAT's list is remembered as April 2005 and the source dates it 2005-03-01. With nothing stored the screen says so and links to the synchronisation rather than showing three empty groups.
  - Verification:
    - command: ["swift", "test", "--filter", "BanlistBrowserTests"]
      expect_output: "Test theTcgListsAreOfferedNewestFirst() passed"
      covers: ["R2.AC1"]
    - command: ["swift", "test", "--filter", "BanlistBrowserTests"]
      expect_output: "Test choosingAnotherDateReplacesTheGroups() passed"
      covers: ["R2.AC2"]
    - command: ["swift", "test", "--filter", "BanlistBrowserTests"]
      expect_output: "Test theGoatDefiningListIsLabelledAsSuch() passed"
      covers: ["R2.AC3"]
    - command: ["swift", "test", "--filter", "BanlistBrowserTests"]
      expect_output: "Test withNothingStoredTheScreenSaysSo() passed"
      covers: ["R2.AC4"]
    - command: ["swift", "test", "--filter", "BanlistBrowserTests"]
      expect_output: "Test theScreenNamesTheFormatAndDateItIsShowing() passed"
      covers: ["R2.AC5"]

- [x] 5. Read a card, and hold the budgets
  - Requirements: `R3.AC1`, `R3.AC2`, `R3.AC3`, `NFR1`, `NFR2`, `NFR3`, `NFR4`, `NFR5`
  - Design: Architecture, Verification Plan
  - Notes: The third reuse of `card-detail`'s panel, with the deck editor's supersession rule, because a list is walked with the arrow keys too. The latency budget is measured on the largest stored list rather than on the GOAT one, since grouping cost grows with entries and the point is that it does not grow enough to notice.
  - Verification:
    - command: ["swift", "build"]
      expect_output: "Build complete!"
      covers: ["NFR5"]
    - command: ["swift", "test", "--filter", "BanlistBrowserTests"]
      expect_output: "Test selectingACardShowsItsDetailBesideTheList() passed"
      covers: ["R3.AC1"]
    - command: ["swift", "test", "--filter", "BanlistBrowserTests"]
      expect_output: "Test theDetailIsTheOneTheCatalogGives() passed"
      covers: ["R3.AC2"]
    - command: ["swift", "test", "--filter", "BanlistBrowserTests"]
      expect_output: "Test anUnopenableCardIsStatedRatherThanBlank() passed"
      covers: ["R3.AC3"]
    - command: ["swift", "test", "--filter", "BanlistBrowserBudgetTests"]
      expect_output: "Test anyStoredListIsGroupedAndShownWithinOneHundredFiftyMilliseconds() passed"
      covers: ["NFR1"]
      timeout: 20m
    - command: ["swift", "test", "--filter", "BanlistBrowserBudgetTests"]
      expect_output: "Test theArithmeticClosesOnEveryStoredList() passed"
      covers: ["NFR2"]
    - command: ["swift", "test", "--filter", "BanlistBrowserBudgetTests"]
      expect_output: "Test aStoredListReadsWithNoNetwork() passed"
      covers: ["NFR3"]
    - command: ["swift", "test", "--filter", "BanlistBrowserBudgetTests"]
      expect_output: "Test eachCardReadsAsASentenceNamingItsKindAndStatus() passed"
      covers: ["NFR4"]
