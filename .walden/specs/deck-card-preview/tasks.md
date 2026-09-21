---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T15:35:59Z
last_modified: 2026-09-21T18:15:20Z
approved_fingerprint: sha256:d0951b473db16a2f335d8e08c0dad2a3dde38bdf205469cae9a83b75a9516344
source_design_approved_at: 2026-09-21T15:33:54Z
source_design_fingerprint: sha256:a2adec427667397f9a9cc78318197fe0c5afefb80e9864614967579573712c30
---

# Implementation Plan

Five executable tasks. The runner marker asserted throughout is `Test <name>() passed`.

Task 1 comes first because resolving a selection into a card is the only new behaviour here; everything after it arranges what already exists.

The figures asserted below come from the user's own decks and code: 74 slots across 65 distinct cards, a deck editor that is already two columns, and a card detail panel `card-detail` built and certified.

- [x] 1. Resolve the selected entry into a card
  - Requirements: `R1.AC1`, `R1.AC5`, `R1.AC6`
  - Design: Architecture, Data Model
  - Notes: A `DeckEntryItem` carries an identifier; the panel needs a `Card`. The read lives in the editor rather than in the view, because a view that asks a repository for a card holds policy and could then only be checked by rendering. `previewFailure` is its own property rather than an empty `previewCard`: "nothing selected" invites a selection and "this could not be read" reports a problem, and a screen has to say different things for each.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckPreviewTests"]
      expect_output: "Test selectingAnEntryPreviewsItsCard() passed"
      covers: ["R1.AC1"]
    - command: ["swift", "test", "--filter", "DeckPreviewTests"]
      expect_output: "Test anUnreadableCardIsStatedRatherThanLeftBlank() passed"
      covers: ["R1.AC5"]
    - command: ["swift", "test", "--filter", "DeckPreviewTests"]
      expect_output: "Test aFreshlyLoadedDeckHasNoPreviewAndNoFailure() passed"
      covers: ["R1.AC6"]
    - command: ["swift", "test", "--filter", "DeckPreviewTests"]
      expect_output: "Test aReadAnsweredAfterTheSelectionMovedOnIsDiscarded() passed"
      covers: ["R1.AC1"]

- [x] 2. Preview a search result, and show what the catalog shows
  - Requirements: `R1.AC2`, `R1.AC4`
  - Design: Architecture, Options Considered
  - Notes: `candidates` is already `[Card]`, so previewing a search result is an assignment with no read at all — and it lets a card be read before it is added rather than after. `R1.AC2` is the reason the panel is `card-detail`'s rather than a lighter one written here: a second panel drifts, and the catalog's would gain a section the deck's did not.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckPreviewTests"]
      expect_output: "Test selectingACandidatePreviewsItWithoutACatalogRead() passed"
      covers: ["R1.AC4"]
    - command: ["swift", "test", "--filter", "DeckPreviewSharingTests"]
      expect_output: "Test aCardPreviewedFromADeckCarriesWhatTheCatalogCarries() passed"
      covers: ["R1.AC2"]
    - command: ["swift", "test", "--filter", "DeckPreviewSharingTests"]
      expect_output: "Test theDeckAndTheCatalogUseTheSamePanel() passed"
      covers: ["R1.AC2"]

- [x] 3. Replace it, and put it away
  - Requirements: `R1.AC3`, `R2.AC3`
  - Design: Architecture, Failure Modes And Tradeoffs
  - Notes: The deck list is what the user is working in, so changing the panel must not move it. Dismissing keeps the selected card: a session spent adjusting counts does not need effect text on screen, and reopening should not be a second search for something already found.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckPreviewTests"]
      expect_output: "Test selectingAnotherEntryLeavesTheDeckUndisturbed() passed"
      covers: ["R1.AC3"]
    - command: ["swift", "test", "--filter", "DeckPreviewTests"]
      expect_output: "Test dismissingClearsThePanelAndKeepsTheCardForItsReturn() passed"
      covers: ["R2.AC3"]

- [x] 4. Fit three columns on one screen
  - Requirements: `R2.AC1`, `R2.AC2`, `R2.AC4`
  - Design: Architecture, Options Considered
  - Notes: The editor is already two columns, and the user has already met this: the catalog's filters were unreadable beside a wide detail. A quarter of the window with a readable floor, so a narrow window narrows the deck rather than the panel. The keyboard path matters more here than in the catalog, because a deck list is walked with the arrow keys.
  - Verification:
    - command: ["swift", "test", "--filter", "DeckPreviewLayoutTests"]
      expect_output: "Test theDetailIsNeverWiderThanAQuarterOfTheWindow() passed"
      covers: ["R2.AC1"]
    - command: ["swift", "test", "--filter", "DeckPreviewLayoutTests"]
      expect_output: "Test aNarrowWindowNarrowsTheDeckNotThePanel() passed"
      covers: ["R2.AC2"]
    - command: ["swift", "test", "--filter", "DeckPreviewLayoutTests"]
      expect_output: "Test selectingAndDismissingAreReachableWithoutAPointer() passed"
      covers: ["R2.AC4"]

- [x] 5. Hold the budgets
  - Requirements: `NFR1`, `NFR2`, `NFR3`, `NFR4`, `NFR5`
  - Design: Verification Plan, Requirement Coverage
  - Notes: Measured while walking a full deck with the arrow keys, because that is the motion this feature makes possible and the one a slow read would ruin. The offline check drives the whole panel with every outbound call throwing; only the full artwork is allowed to be missing.
  - Verification:
    - command: ["swift", "build"]
      expect_output: "Build complete!"
      covers: ["NFR5"]
    - command: ["swift", "test", "--filter", "DeckPreviewBudgetTests"]
      expect_output: "Test walkingADeckWithTheArrowKeysStaysUnderOneHundredMilliseconds() passed"
      covers: ["NFR1"]
      timeout: 20m
    - command: ["swift", "test", "--filter", "DeckPreviewBudgetTests"]
      expect_output: "Test thePanelIsTheCatalogsAndNotACopyOfIt() passed"
      covers: ["NFR2"]
    - command: ["swift", "test", "--filter", "DeckPreviewBudgetTests"]
      expect_output: "Test everySectionButTheArtworkResolvesOffline() passed"
      covers: ["NFR3"]
    - command: ["swift", "test", "--filter", "DeckPreviewBudgetTests"]
      expect_output: "Test everyFigureInThePanelStillReadsAsASentence() passed"
      covers: ["NFR4"]
