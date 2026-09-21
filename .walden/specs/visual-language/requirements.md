---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T12:41:16Z
last_modified: 2026-09-21T12:41:16Z
approved_fingerprint: sha256:4398957fb18a836e3068a64c58fd7f32184696f7770965d0ddb36040fea5509b
---

# Requirements Document

## Introduction

The interface today is deliberately colourless. The design system says so in as many words: *"Card artwork supplies nearly all the colour in this interface, so the surrounding surfaces stay neutral and let it carry the page."* Every tile, row and panel is a grey rectangle with the artwork doing the work.

That was a defensible choice and the user has asked to reverse it. Colour should carry meaning — the game already codes its own cards by frame, and a duelist reads those colours faster than any label. This feature makes the application use them, across all five screens, without turning minimal into busy.

Facts measured against the user's own database and code on 2026-09-21:

- **Seventeen frame types exist**, and the distribution is very uneven: 5,975 effect monsters, 2,886 spells, 2,085 traps, 685 normal monsters, then 591 Xyz, 568 fusion, 531 synchro, 473 link, 314 pendulum effect monsters, 152 ritual, 124 skill, 106 token, and five pendulum variants in single or double digits.
- **Seven of those seventeen are extra-deck frames**: fusion, synchro, Xyz and link, plus the pendulum variants of the first three. Link has no pendulum variant, because the game has no Link Pendulum monster.
- **Three colours already carry meaning** and have earned it: red for forbidden, orange for limited, yellow for semi-limited.
- **Everything else is system grey**: two surfaces, two text colours, a separator and the system accent.
- **The five screens are Catalogo, Mazzi, Collezione, Statistiche and Valore.** Every one reads tokens from `Theme` rather than writing literals, so a token change reaches all of them.
- **Typography is five sizes between 11 and 13 points**, with no scale above `sectionTitle`.

## Requirements

### R1 Colour that means something

**User Story:** As a duelist, I want a card's colour to tell me what it is, so that I can read a grid or a deck list without reading every label.

#### Acceptance Criteria

1. `R1.AC1` The system SHALL give each card frame a distinct colour.
   - Acceptance check: every frame type resolves to a colour, and no two frames a user must tell apart resolve to the same one.
2. `R1.AC2` WHEN a card is shown anywhere in the application, the system SHALL show its frame colour with it.
   - Acceptance check: the same card carries the same colour in the catalog grid, the card detail, a deck list and a collection row.
3. `R1.AC3` The system SHALL distinguish extra-deck frames from main-deck frames by colour.
   - Acceptance check: the seven extra-deck frames are separable from the rest by colour alone.
4. `R1.AC4` The system SHALL keep the existing restriction colours for restriction only.
   - Acceptance check: red, orange and yellow continue to mean forbidden, limited and semi-limited, and no frame colour is mistakable for one of them.
5. `R1.AC5` IF a card's frame is unknown to the palette, THEN the system SHALL show it in a neutral colour rather than omitting the marker.
   - Acceptance check: a card with an unrecognised frame still renders with a marker, in a colour that claims nothing.

### R2 Still minimal

**User Story:** As someone who looks at this for hours, I want the colour to inform rather than shout, so that the screen stays calm.

#### Acceptance Criteria

1. `R2.AC1` The system SHALL apply frame colour as a marker rather than as a background fill behind text.
   - Acceptance check: no text is drawn on a saturated frame colour.
2. `R2.AC2` The system SHALL keep surfaces and text neutral.
   - Acceptance check: the surfaces and text colours remain system-derived, and colour enters only through markers, accents and states.
3. `R2.AC3` The system SHALL present every text against its background at a contrast ratio of at least 4.5 to 1.
   - Acceptance check: each text-on-surface pair in the palette measures at least 4.5 to 1, in both light and dark appearance.
4. `R2.AC4` The system SHALL follow the system's light and dark appearance.
   - Acceptance check: every colour resolves in both appearances, and none is a fixed value that only works in one.

### R3 A visual scale

**User Story:** As a reader, I want headings, values and captions to be visibly different, so that a screen has a shape instead of being a wall of 13-point text.

#### Acceptance Criteria

1. `R3.AC1` The system SHALL provide a typographic scale with a distinct level for a screen title, a section heading, body text, a numeric figure and a caption.
   - Acceptance check: the five levels differ in size or weight, and the ordering from title to caption is strictly decreasing in prominence.
2. `R3.AC2` The system SHALL present numeric figures in a form whose digits do not shift width.
   - Acceptance check: a changing figure does not move the text beside it.
3. `R3.AC3` The system SHALL provide elevation levels that separate a raised surface from the page behind it.
   - Acceptance check: a raised surface is distinguishable from the page in both appearances without a border being required.

### R4 Everywhere, not somewhere

**User Story:** As the person using this, I want the whole application to look like one thing, so that it does not feel half rebuilt.

#### Acceptance Criteria

1. `R4.AC1` The system SHALL apply the visual language to all five screens.
   - Acceptance check: the catalog, decks, collection, statistics and valuation screens each use the new tokens.
2. `R4.AC2` The system SHALL define every colour, spacing, radius and type style in one place.
   - Acceptance check: no feature module contains a colour, font size, corner radius or spacing literal.
3. `R4.AC3` WHEN a token changes, the system SHALL reflect it on every screen without those screens being edited.
   - Acceptance check: changing a token's value changes what every screen reads, with no other edit.

## Non-Functional Requirements

- `NFR1` Legibility: colour is never the only way a fact is conveyed; every colour-coded fact is also available as text. Bridged by `R1.AC2` and `R1.AC5`.
- `NFR2` Accessibility: contrast holds in both appearances, and figures read as sentences as they already do. Bridged by `R2.AC3` and `R2.AC4`.
- `NFR3` Responsiveness: the catalog grid keeps its measured budget, a keystroke still narrowing results within 150 ms with the new tiles. Bridged by `R4.AC1`.
- `NFR4` Consistency: one definition per token, read by every screen. Bridged by `R4.AC2` and `R4.AC3`.
- `NFR5` Concurrency safety: the design system and every feature build under Swift 6 strict concurrency with no data-race diagnostics suppressed.

## Constraints And Dependencies

- `C1` The seventeen frame types are the catalog's, not this feature's. Their distribution is extremely uneven — four frames account for 11,631 of 14,566 cards — so a palette that gives equal weight to all seventeen would spend most of itself on cards the user rarely sees.
- `C2` Red, orange and yellow are taken. They mean forbidden, limited and semi-limited, and `R1.AC4` keeps them that way.
- `C3` Colours must resolve in both light and dark appearance, so each is defined against the system's dynamic colours rather than as a fixed value.
- `C4` The measured budgets from `card-detail` stand: narrowing within 150 ms and a detail panel within 100 ms. A heavier tile must not spend them.
- `C5` Card artwork is 421 by 614 and supplies the strongest colour on screen. The palette sits beside it, not against it.
- `C6` Target platform is macOS 27 on arm64, built with Swift 6.4 and Swift Package Manager.

## Out Of Scope

- Changing what any screen shows, which is each feature's own specification.
- Rearranging layouts or navigation.
- A user-configurable theme or an accent picker.
- Animation and transitions.
- Icons and illustration beyond the system's own symbols.
