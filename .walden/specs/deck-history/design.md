---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-22T10:38:14Z
last_modified: 2026-09-22T10:38:14Z
approved_fingerprint: sha256:429b63cb3ffdbe0f18f90b9f3e07e943e4abd8c8b9b2092ec647430260a14f4a
source_requirements_approved_at: 2026-09-22T10:34:40Z
source_requirements_fingerprint: sha256:b166c06692c45636804d4576b0314a0394f0d4c36d3e55cc6004a3676cae577e
---

# Feature Design

## Architecture

A port, a panel, and two methods that guard what the storage already does.

```
YGOFeatureDeckBuilder ──▶ YGOCore (DeckHistorying, DeckVersion)
   DeckEditorViewModel            ▲
   DeckHistoryPanel               │
                        SQLiteDeckRepository
                        (SQLiteDeckOrganisation.swift, already written)
```

No table, no column, no migration. `saveVersion`, `versions(of:)` and `restore(versionID:)` are written, certified by `deck-builder`'s version-history requirement and reachable from the object the editor already holds. What is missing is a name a feature module can call them by, two guards, and somewhere to see them.

### The port

`DeckVersion` moves from `YGOPersistence` to `YGOCore`, because a feature module cannot name a type declared in a module it must not import. It gains one field:

```swift
public struct DeckVersion: Hashable, Sendable, Identifiable {
    public let id: Int64
    public let deckID: Int64
    public let label: String?
    public let createdAt: Date
    public let slots: [DeckSlot]
    /// False when the stored snapshot could not be read. The slots are then
    /// empty, which is not the same thing as a version of an empty deck.
    public let isReadable: Bool
}
```

`isReadable` defaults to `true` in the initialiser, so `deck-builder`'s certified tests keep compiling and passing unchanged. Making `slots` optional instead would have broken four of them, and a version that cannot be read is not a version with no cards — which is the whole of `R2.AC5`.

```swift
public protocol DeckHistorying: Sendable {
    @discardableResult
    func saveVersion(of deckID: Int64, label: String?) async throws -> Int64
    func versions(of deckID: Int64) async throws -> [DeckVersion]
    /// Restores a version into the deck it belongs to, and refuses otherwise.
    func restoreVersion(_ versionID: Int64, of deckID: Int64) async throws
}
```

### Two guards over storage that already works

**`restoreVersion(_:of:)` is new, and `restore(versionID:)` stays.** The existing method reads the version's own `deck_id` and restores into it, so handing it a version from another deck silently rewrites *that other deck*. Nothing in the application could do that today because nothing calls it at all; a screen that lists versions makes it one wrong identifier away. `R3.AC6` is that guard: the new method checks the version belongs to the deck named, throws if it does not, and otherwise delegates to the existing path so there is one restore and not two.

**`versions(of:)` stops degrading.** It currently turns an unreadable snapshot into `slots: []`, which reads as a version of an empty deck. It now returns `isReadable: false` with empty slots, and the panel refuses to restore such a version. `restore` already throws on one, so the two finally agree.

### The panel is the preview's neighbour, not a sheet

The editor already has a panel beside the deck, which `deck-card-preview` put there. The history goes in the same place and the two take turns: one panel, two things it can show.

A sheet was the alternative and is rejected under Options Considered — this project has already learned that presentations compete, and the editor is holding a confirmation dialog for deck deletion.

For the same reason the restore confirmation sits on its own level:

```swift
.background { Color.clear.alert("Ripristinare questa versione?", ...) }
```

Stacked on the same view as the deletion dialog, SwiftUI would show one and silently drop the other — which is how a deck could be renamed and not deleted.

### The confirmation carries what was confirmed

```swift
public private(set) var pendingRestore: Int64?
public func askRestore(_ versionID: Int64)
public func confirmRestore(_ versionID: Int64) async   // takes it, never reads it
public func cancelRestore()
```

`confirmRestore` takes the identifier rather than reading `pendingRestore`, because the alert's dismissal clears the armed value before the button's action runs. That is not a hypothesis: it is the defect found in the collection screen and in the settings window on 2026-09-22, and before that in deck deletion and deck renaming. The view captures while the alert is built and hands it over.

### What the editor gains

```swift
@MainActor @Observable public final class DeckEditorViewModel {
    // Absent means the editor cannot offer a history, the same way `editing`
    // absent means it cannot rearrange.
    private let history: (any DeckHistorying)?

    public private(set) var versions: [DeckVersion] = []
    public private(set) var isHistoryVisible = false
    public private(set) var selectedVersion: Int64?
    public var canUseHistory: Bool { history != nil && deck != nil }

    public func showHistory() async     // loads, then reveals
    public func hideHistory()
    public func saveVersion(named label: String?) async
    public func moveVersionSelection(by offset: Int)
}
```

A version's display name is `label ??` its moment, formatted — which is `R1.AC2` proven on the model rather than on a window. Its size is `slots.reduce(0) { $0 + $1.quantity }`, the same arithmetic the deck list uses.

Listing is one call to `versions(of:)`, which returns every version in one query. Nothing re-reads the deck per row, which is `NFR4`.

### Loading and ordering

`versions(of:)` orders `created_at, id` ascending, which is oldest first. `R2.AC1` wants the newest at the top, so the view model reverses it rather than changing a query `deck-builder` certified. Ties on `created_at` — two versions saved in the same second — are broken by `id`, so the order is total and a restore-then-save sequence reads in the order it happened.

## Options Considered

**Reopening `deck-builder`'s tasks instead of a new specification.** The version-history requirement lives there and this is its missing half, so adding tasks to it is defensible. It was rejected because a body edit breaks that document's seal, `reconcile` resets the approval chain, and fifteen certified tasks go back through their gates for a screen none of them describes. This project has taken the other route four times — `banlist-browser` over `banlist-history`, `deck-card-preview` and `deck-editing` over `deck-builder` — where the storage is certified in one specification and the screen that makes it reachable is its own. `C1` records that the storage contract remains `deck-builder`'s.

**A sheet or a separate window for the history.** More room, and the deck stays visible behind it. Rejected: the editor already presents a confirmation dialog, and this project's recorded failures are all presentations competing on one view. The panel beside the deck exists, is keyboard reachable, and is where a card already appears.

**Splitting the port into reading and writing, as the collection does.** `CollectionReading`/`CollectionWriting` exist because a read-only collection screen exists. No read-only history screen does, so the split would be a shape with no caller. One protocol, and if a read-only history ever appears it can be split then.

**Letting `versions(of:)` throw on an unreadable snapshot instead of flagging it.** Honest, and one corrupt row would then hide every version of that deck — the opposite of what a history is for. The flag keeps the rest of the list readable and tells the truth about the one that is not.

## Simplicity And Elegance Review

The feature adds one protocol, one field, one method and one panel. Every write it performs was already written and certified; it adds the two guards that only matter once a user can reach them.

The first draft had the view model hold `historyFailure`, `isSavingVersion` and `isRestoring` alongside the existing `lastFailure`. That is three flags describing the same thing the editor already reports one way, so they went: saving and restoring report through `lastFailure` and reload through the same `load(deckID:)` every other edit uses, which is also how `R3.AC3` is satisfied without a second refresh path.

Coupling stays where the constitution puts it: the feature module imports `YGOCore`, the conformance sits on the repository that already implements the behaviour, and the composition root binds one more protocol to an object it already builds.

## Failure Modes And Tradeoffs

**A restore that fails part way.** `restore` runs inside one GRDB write, which is one transaction: the delete and the re-insert either both land or neither does. A throw rolls back, the deck is untouched, and the editor reloads from storage and reports — which is `R3.AC5`.

**A version from another deck.** Refused by `restoreVersion(_:of:)`. The old unguarded method stays for `deck-builder`'s certified proofs, which call it on the deck that owns the version; the feature never uses it.

**An unreadable snapshot.** Listed, marked, and not restorable. The list keeps working.

**Two versions in the same second.** `id` breaks the tie, so the order is total.

**Versions accumulate.** One JSON snapshot each, a deck holds at most ninety distinct cards, and nothing prunes them. Accepted: they cascade with the deck, and pruning is out of scope until somebody has enough of them to care.

**The panel and the preview cannot both be open.** Accepted, and deliberate: one panel means one presentation and one focus target. Closing the history restores the preview, so nothing is lost.

## Verification Plan

New suite `DeckHistoryTests` in `YGOSyncTests`, where the editor's other affordances are proven, plus additions to `YGOPersistenceTests` for the two guards. Everything runs against a temporary database; nothing touches the user's installation.

| What | Where | How it is observed |
| --- | --- | --- |
| Saving stores a version | `DeckHistoryTests` | after `saveVersion`, the deck's version list holds one more entry and carries the given label |
| An unnamed version reads as its moment | `DeckHistoryTests` | a version saved with no label has a display name equal to its formatted date and time, not an empty string |
| No deck, no saving | `DeckHistoryTests` | an editor with no deck loaded reports `canUseHistory == false` and saving changes nothing |
| A failed save leaves the deck alone | `DeckHistoryTests` | with a stub throwing, `lastFailure` is set and the deck's slots are identical |
| Newest first | `DeckHistoryTests` | three versions saved in order are listed in the reverse order, ties broken by identifier |
| Each version reports name, moment, size | `DeckHistoryTests` | a version of a deck holding 43 cards reports 43 and a non-empty display name |
| Only this deck's versions | `DeckHistoryTests` | with two decks each versioned, the list holds only the open deck's |
| A deck with no versions | `DeckHistoryTests` | the list is empty and the model says the deck has never been versioned |
| An unreadable version is marked | `YGOPersistenceTests` | a `deck_version` row holding invalid JSON is listed with `isReadable == false` and empty slots, and the other versions of that deck are still listed |
| Asking does not restore | `DeckHistoryTests` | after `askRestore`, the deck's counts are unchanged and `cancelRestore` leaves them unchanged |
| Confirming restores exactly | `DeckHistoryTests` | each section holds the version's counts after `confirmRestore` |
| The editor shows the restored deck | `DeckHistoryTests` | `items` and `legality` read the restored deck with no second load |
| The replaced state becomes a version | `DeckHistoryTests` | after restoring, the list holds an entry whose slots are the pre-restore ones, and restoring it returns the deck to them |
| A failed restore leaves the deck alone | `DeckHistoryTests` | with a stub throwing, the deck's slots are identical and `lastFailure` is set |
| A foreign version is refused | `YGOPersistenceTests` | `restoreVersion(_:of:)` throws for a version belonging to another deck, and **both** decks' cards are unchanged |
| A confirmed restore survives the dismissal | `DeckHistoryTests` | armed, then cleared as a dismissal clears it, then `confirmRestore(captured)` still restores |
| Keyboard | `DeckHistoryTests` | `showHistory`/`hideHistory` toggle the panel and `moveVersionSelection` walks the list and stops at its ends |

## Requirement Coverage

| Requirement | Covered By |
| --- | --- |
| `R1` | `DeckHistorying.saveVersion` bound to `SQLiteDeckRepository`, `canUseHistory`, display name on `DeckVersion`, failures through `lastFailure` |
| `R2` | `versions(of:)` reversed for newest-first, `isReadable` for the unreadable case, per-version size arithmetic, empty-state on the view model |
| `R3` | `restoreVersion(_:of:)` with its ownership guard, `askRestore`/`confirmRestore(_:)`/`cancelRestore`, reload through `load(deckID:)`, the pre-restore version storage that already exists |
| `R4` | `showHistory`/`hideHistory` and `moveVersionSelection` on the view model, bound to keyboard shortcuts in the panel |
| `NFR1` | The armed-and-captured confirmation, the single-transaction restore, and the pre-restore version |
| `NFR2` | Every call is a local database read or write; no client and no transport is involved |
| `NFR3` | Display name, moment and size on every row, asserted in the feature's tests; the panel's actions are keyboard reachable |
| `NFR4` | One `versions(of:)` call per opening; no per-row deck read |
