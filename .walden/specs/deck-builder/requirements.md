---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-20T09:09:40Z
last_modified: 2026-09-20T09:09:40Z
approved_fingerprint: sha256:801af3e91ff433fa491f1de8bd881dbea0ecd0e536bd4574d67890af90fe7bf7
---

# Requirements Document

## Introduction

The deck builder is where the catalog becomes useful. It lets a duelist assemble decks from the stored card pool, tells them whether a deck is legal in the format they actually play, and exchanges decks with the tools the rest of the community uses.

This feature covers deck creation and editing, composition and copy limits, per-format legality, import and export in the `.ydk` and YDKe interchange formats, organisation into folders and tags, and version history. It does not cover which cards the user physically owns, deck statistics, or prices; those are separate specifications that read the decks this one produces.

Facts established against the live catalog and against the user's own deck files on 2026-09-20, which shape several requirements below:

- **The user's existing decks are GOAT-format decks.** Both `Lockdown Burn.ydk` and `LR-Chaos Turbo.ydk` are legal in GOAT and carry four and six banlist violations respectively in TCG. A builder that validates against one fixed format would declare both of them broken.
- **Alternate artwork identifiers appear in real deck files.** `Lockdown Burn.ydk` references passcode `83555667`, an alternate artwork of *Ring of Destruction*, which resolves only through the catalog's artwork alias table.
- **142 cards carry a `treated_as` name, and 13 of those differ from the card's own name.** `Harpie Lady 1`, `2` and `3` all count as *Harpie Lady*; `A Legendary Ocean` counts as *Umi*; `Fusion Substitute` counts as *Polymerization*. Counting copies by printed name alone permits illegal decks.
- **A `.ydk` file carries no format, no deck name and no card names** — only section markers and passcodes. Everything else has to come from the catalog or from the user.
- **YDKe is `ydke://<main>!<extra>!<side>!`**, each section base64 of little-endian 32-bit passcodes. Verified by decoding the published example into real cards and by round-tripping both of the user's decks.

## Requirements

### R1 Deck creation and editing

**User Story:** As a duelist, I want to build and change decks inside the application, so that my lists live next to the card pool I build them from.

#### Acceptance Criteria

1. `R1.AC1` WHEN the user creates a deck, the system SHALL store it with a name, a chosen format and empty main, extra and side sections.
   - Acceptance check: a newly created deck is retrievable afterwards, reports zero cards in each section, and carries the name and format that were chosen.
2. `R1.AC2` WHEN the user adds a card to a section, the system SHALL increase that card's count in that section by one.
   - Acceptance check: adding the same card three times yields a count of three in that section and leaves the other two sections unchanged.
3. `R1.AC3` WHEN the user removes a card from a section, the system SHALL decrease that card's count in that section by one and remove the entry once the count reaches zero.
   - Acceptance check: removing a card held once leaves no entry for it, and removing from a section that does not hold it changes nothing.
4. `R1.AC4` WHEN the user renames a deck or changes its format, the system SHALL store the change and re-evaluate the deck's legality.
   - Acceptance check: changing a deck's format from TCG to GOAT changes the reported violations without altering which cards the deck holds.
5. `R1.AC5` WHEN a deck is modified, the system SHALL record the time of the change.
   - Acceptance check: a deck's recorded modification time after an edit is later than the one it replaced.
6. `R1.AC6` WHEN the user deletes a deck, the system SHALL require a confirmation before removing it.
   - Acceptance check: deletion without a confirmation leaves the deck retrievable; after confirmation it is gone and its cards are untouched in the catalog.
7. `R1.AC7` WHEN the user duplicates a deck, the system SHALL store an independent copy whose later edits do not affect the original.
   - Acceptance check: editing the copy leaves the original's card counts unchanged.

### R2 Composition limits

**User Story:** As a duelist, I want the application to hold me to the deck construction rules, so that I do not discover an illegal list at a tournament table.

#### Acceptance Criteria

1. `R2.AC1` The system SHALL report a deck whose main section holds fewer than forty or more than sixty cards as violating its size limits.
   - Acceptance check: decks of thirty-nine, forty, sixty and sixty-one main cards report violation, legal, legal and violation respectively.
2. `R2.AC2` The system SHALL report a deck whose extra section holds more than fifteen cards as violating its size limits.
   - Acceptance check: fifteen extra cards reports legal and sixteen reports a violation; an empty extra section is legal.
3. `R2.AC3` The system SHALL report a deck whose side section holds more than fifteen cards as violating its size limits.
   - Acceptance check: fifteen side cards reports legal and sixteen reports a violation; an empty side section is legal.
4. `R2.AC4` IF a card belonging to the Extra Deck is placed in the main or side section, THEN the system SHALL report that placement as a violation naming the card.
   - Acceptance check: a Fusion, Synchro, Xyz or Link card placed in the main section is reported by name; the same card in the extra section is not.
5. `R2.AC5` IF a card not belonging to the Extra Deck is placed in the extra section, THEN the system SHALL report that placement as a violation naming the card.
   - Acceptance check: a Spell card placed in the extra section is reported by name.
6. `R2.AC6` WHEN the user adds a card, the system SHALL place it in the section its card type belongs to unless the user chose a section explicitly.
   - Acceptance check: adding a Fusion monster with no section chosen puts it in the extra section, and adding a Spell puts it in the main section.

### R3 Copy limits

**User Story:** As a duelist, I want copies counted the way the rules count them, so that a deck the application calls legal really is.

#### Acceptance Criteria

1. `R3.AC1` The system SHALL count a card's copies across the main, extra and side sections together.
   - Acceptance check: two copies in the main section and two in the side section report four copies, not two.
2. `R3.AC2` The system SHALL count every artwork of a card as the same card.
   - Acceptance check: a deck holding a card twice under its own passcode and twice under an alternate artwork passcode reports four copies of one card, not two of each.
3. `R3.AC3` WHERE a card is treated as another card's name, the system SHALL count its copies against that other name.
   - Acceptance check: a deck holding two `Harpie Lady 1` and two `Harpie Lady 2` reports four copies of *Harpie Lady* and is over its limit, while a deck holding one of each reports two and is not.
4. `R3.AC4` IF a card's copies exceed the allowance its ban status permits in the deck's format, THEN the system SHALL report a violation naming the card, the count held and the count permitted.
   - Acceptance check: three copies of a Limited card report a violation stating three held against one permitted; one copy reports none.
5. `R3.AC5` The system SHALL report more than three copies of any card as a violation regardless of format or ban status.
   - Acceptance check: four copies of an unrestricted card report a violation even in a format with no ban list at all.

### R4 Format legality

**User Story:** As a duelist who plays more than one format, I want each deck judged against its own format, so that a GOAT deck is not reported as broken because it would be illegal in TCG.

#### Acceptance Criteria

1. `R4.AC1` WHEN a deck's legality is evaluated, the system SHALL judge every card against the ban status of the deck's own format.
   - Acceptance check: a deck holding cards forbidden in TCG but unrestricted in GOAT reports no ban violations when its format is GOAT and reports them when its format is TCG.
2. `R4.AC2` IF a deck holds a card that is not part of its format's card pool, THEN the system SHALL report a violation naming the card.
   - Acceptance check: a card released after a retro format's cutoff is reported when the deck's format is that retro format.
3. `R4.AC3` WHEN a deck has no violations of any kind, the system SHALL report it as legal in its format.
   - Acceptance check: both of the user's existing deck files report legal once their format is set to GOAT.
4. `R4.AC4` WHEN a deck's legality is evaluated, the system SHALL report every violation it holds rather than stopping at the first.
   - Acceptance check: a deck with an undersized main section and two over-copy cards reports three violations, not one.
5. `R4.AC5` WHERE a deck's format has no upstream ban list, the system SHALL judge its ban violations against the restrictions the user recorded for that format.
   - Acceptance check: a card the user marked Limited in Edison reports a violation at two copies in an Edison deck, and reports none once the user clears that entry.
6. `R4.AC6` WHERE a deck's format has no upstream ban list, the system SHALL indicate that its restrictions are user-maintained.
   - Acceptance check: a legality report for an Edison deck is distinguishable from one for a TCG deck without inspecting the stored ban rows.

### R5 Deck import

**User Story:** As a duelist with decks built in other tools, I want to bring them in as they are, so that I do not retype forty cards.

#### Acceptance Criteria

1. `R5.AC1` WHEN the user imports a `.ydk` file, the system SHALL create a deck holding every passcode it lists in the section it lists them under.
   - Acceptance check: importing `LR-Chaos Turbo.ydk` yields a deck of forty main, fifteen extra and fifteen side cards.
2. `R5.AC2` WHEN an imported passcode identifies an alternate artwork, the system SHALL resolve it to the card that artwork depicts.
   - Acceptance check: importing `Lockdown Burn.ydk` yields forty main cards including *Ring of Destruction*, whose passcode in that file is an alternate artwork.
3. `R5.AC3` IF an imported passcode matches no card in the catalog, THEN the system SHALL import the rest of the deck and report that passcode as unresolved.
   - Acceptance check: a file holding one unknown passcode among known ones yields a deck of the known cards plus a report naming the unknown passcode, rather than a failed import or a silently shorter deck.
4. `R5.AC4` WHEN a deck is imported, the system SHALL name it after the file it came from.
   - Acceptance check: importing `Lockdown Burn.ydk` yields a deck named "Lockdown Burn".
5. `R5.AC5` WHEN a deck is imported, the system SHALL propose the format in which it holds the fewest violations.
   - Acceptance check: importing either of the user's deck files proposes GOAT rather than TCG.
6. `R5.AC6` WHEN the user imports a YDKe link, the system SHALL create a deck holding the passcodes it encodes in their encoded sections.
   - Acceptance check: a link generated from a known deck imports back to that same deck.
7. `R5.AC7` IF an imported file or link is malformed, THEN the system SHALL report it as unreadable and create no deck.
   - Acceptance check: a truncated link and a file with a corrupt section marker each leave the stored deck count unchanged.

### R6 Deck export

**User Story:** As a duelist, I want to take my decks to a simulator or share them, so that the application is not a place my lists get stuck in.

#### Acceptance Criteria

1. `R6.AC1` WHEN the user exports a deck as `.ydk`, the system SHALL write its sections under the markers the format uses, one passcode per line.
   - Acceptance check: exporting an imported deck produces a file that imports back to an identical deck.
2. `R6.AC2` WHEN the user exports a deck as a YDKe link, the system SHALL encode each section as base64 of its passcodes in little-endian order.
   - Acceptance check: a link exported from a deck decodes to that deck's passcodes, section by section, and round-trips through import unchanged.
3. `R6.AC3` WHEN a deck is exported, the system SHALL write the passcode the user's copy holds rather than substituting a different artwork.
   - Acceptance check: a deck holding an alternate artwork exports that artwork's passcode, not the card's primary one.
4. `R6.AC4` The system SHALL export a deck regardless of whether it is legal.
   - Acceptance check: an unfinished thirty-card deck exports and re-imports intact.

### R7 Organisation

**User Story:** As a duelist with many decks, I want them sorted, so that I can find the one I want.

#### Acceptance Criteria

1. `R7.AC1` WHEN the user places a deck in a folder, the system SHALL list that deck under that folder.
   - Acceptance check: a deck moved into a folder appears under it and no longer at the top level.
2. `R7.AC2` WHEN the user applies a tag to a deck, the system SHALL list that deck under that tag.
   - Acceptance check: a deck carrying two tags appears under each of them.
3. `R7.AC3` IF a folder holding decks is deleted, THEN the system SHALL keep those decks and return them to the top level.
   - Acceptance check: deleting a folder of three decks leaves all three retrievable.
4. `R7.AC4` WHEN the user searches their decks by name, the system SHALL return the decks whose name matches.
   - Acceptance check: a search naming one deck returns it and not the others.

### R8 Version history

**User Story:** As a duelist who tunes a list over weeks, I want to see and recover what it looked like before, so that an experiment is never a one-way door.

#### Acceptance Criteria

1. `R8.AC1` WHEN the user saves a named version of a deck, the system SHALL store that deck's card counts as they stand.
   - Acceptance check: a version saved before an edit still reports the pre-edit counts after the edit.
2. `R8.AC2` WHEN the user restores a version, the system SHALL set the deck's sections to that version's card counts.
   - Acceptance check: restoring a version returns the deck to exactly the counts it held when that version was saved.
3. `R8.AC3` WHEN the user restores a version, the system SHALL store the pre-restore state as a version of its own.
   - Acceptance check: after restoring, the state that was replaced is still recoverable.
4. `R8.AC4` The system SHALL retain a deck's versions for as long as the deck exists.
   - Acceptance check: a deck's versions are still listed after unrelated decks are deleted and the application restarts.

## Non-Functional Requirements

- `NFR1` Editing responsiveness: adding or removing a card re-evaluates the deck's legality and updates the reported violations within 50 ms for a sixty-card deck on the target machine. Bridged by `R1.AC2`, `R1.AC3` and `R4.AC4`, whose acceptance checks are measured under this budget.
- `NFR2` Data safety: deck and version data is user-authored and irreplaceable. No edit, import, restore or deletion loses a deck without the confirmation `R1.AC6` requires. Bridged by `R1.AC6`, `R5.AC7` and `R8.AC3`.
- `NFR3` Offline operation: every behaviour in this feature functions with no network connection, since it reads only the stored catalog. Bridged by the stored-catalog acceptance checks on `R4.AC1` and `R5.AC1`.
- `NFR4` Interchange fidelity: a deck exported and re-imported is identical in every section, including which artwork each copy uses. Bridged by `R6.AC1`, `R6.AC2` and `R6.AC3`.
- `NFR5` Accessibility: deck sections, the card list and the violation report are reachable and operable by keyboard alone, and each reported violation is readable by assistive technology as a sentence naming the card and the rule. Bridged by `R3.AC4` and `R4.AC4`, which require violations to name their card and count.
- `NFR6` Concurrency safety: the feature builds and runs under Swift 6 strict concurrency checking with no data-race diagnostics suppressed.

## Constraints And Dependencies

- `C1` This feature reads the catalog produced by the `card-catalog` specification. Artwork alias resolution (`R7` there) is what `R5.AC2` depends on, and per-format ban status (`R6` there) is what `R4.AC1` depends on.
- `C2` The upstream catalog publishes ban lists for TCG, OCG and GOAT only. Edison and Master Duel decks are judged against user-recorded restrictions, which the application cannot guarantee are current.
- `C3` A `.ydk` file carries no format, no deck name and no card names. The format proposed by `R5.AC5` is inferred from violation counts and is a suggestion, not a fact recorded in the file.
- `C4` The `treated_as` field covers 142 cards, of which 13 name a card other than themselves. Cards that share a name limit but are not marked this way upstream cannot be detected by the application.
- `C5` Retro format pools are derived from release dates and the format membership the upstream catalog publishes; the application has no independent record of what was legal on a given date.
- `C6` Target platform is macOS 27 on arm64, built with Swift 6.4 and Swift Package Manager.

## Out Of Scope

- Which cards the user physically owns, and telling them what a deck is missing — covered by the `collection-tracker` specification.
- Draw probability, opening-hand simulation and deck statistics — covered by the `deck-analytics` specification.
- Deck and card valuation — covered by the `pricing` specification.
- Playing or simulating duels.
- Sharing decks to a server, publishing them, or any outbound network traffic. Export writes a local file or puts a link on the clipboard.
- Deck formats other than `.ydk` and YDKe, such as the text lists some tournaments require.
- Automatic deck suggestions or a recommendation engine.
