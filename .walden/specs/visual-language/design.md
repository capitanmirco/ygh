---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T12:41:23Z
last_modified: 2026-09-21T12:41:23Z
approved_fingerprint: sha256:c4396fcba0b83a642b4aba2cc4d80549e797b37da447cae1b9ca4e0fae88c1b6
source_requirements_approved_at: 2026-09-21T12:41:16Z
source_requirements_fingerprint: sha256:4398957fb18a836e3068a64c58fd7f32184696f7770965d0ddb36040fea5509b
---

# Feature Design

## Architecture

One file changes shape and every screen follows it. `Theme` already exists and every feature reads from it rather than writing literals, so the work is to widen the vocabulary and then use the new words.

```
YGODesignSystem (Theme)
  ├── Palette.frame(_:)      ← new: colour per card frame
  ├── Palette.surfaces       ← unchanged, still system-derived
  ├── Typography (5 levels)  ← new: a scale with a real top
  └── Elevation              ← new
        ▲
        │ read by
  Catalogo · Mazzi · Collezione · Statistiche · Valore
```

Nothing about what a screen shows changes. `R4.AC3` is already true of the tokens that exist and stays true of the ones being added.

### The palette is measured, not chosen by eye

Three colours are already spoken for: red, orange and yellow mean forbidden, limited and semi-limited. A frame colour that reads as one of them would make colour mean two things at once, which is worse than it meaning nothing.

So the palette is constrained and the constraints are numbers a test can check:

| Rule | Threshold | Why |
| --- | --- | --- |
| Frame colour against any restriction colour | ΔE ≥ 25 | `R1.AC4`: not mistakable |
| Frame colour against another frame colour | ΔE ≥ 18 | `R1.AC1`: distinct |
| Marker against its surface | ≥ 3:1 | A marker nobody can see is not a marker |
| Text against its surface | ≥ 4.5:1 | `R2.AC3` |

ΔE is CIE76 in Lab, which is crude but sufficient at these distances and needs no dependency.

The values below were measured before any code was written. Game-faithful where the constraints allow, shifted where they do not — the game's own effect-monster orange and normal-monster yellow are exactly the two hues the restriction colours occupy, so those two move:

| Frame | Light | Note |
| --- | --- | --- |
| `normal` | `#D4B36A` | Sand rather than the game's yellow, which is semi-limited's |
| `effect` | `#9C7A5C` | Warm stone rather than the game's orange, which is limited's |
| `ritual` | `#3D6FB8` | Blue, as the game has it |
| `fusion` | `#9B3FB5` | Purple |
| `synchro` | `#9AA3AE` | Silver, darkened so it survives a light surface |
| `xyz` | `#3A3F47` | Near-black, lightened in dark appearance |
| `link` | `#128A8A` | Teal |
| `spell` | `#1E8A5F` | Green |
| `trap` | `#C0397A` | Magenta |
| `token` | `#6E7480` | Grey, and the only frame that should read as "no colour" |
| `skill` | `#5E6B2E` | Olive-green, chosen for distance from everything else |

Two of those deserve saying out loud. **Effect monsters are 5,975 of 14,566 cards** — 41% of the catalog — so the quietest colour in the palette going to the most common frame is not a compromise, it is the thing that keeps a grid calm. **Normal monsters are 685**, and sand is the closest the constraints allow to the game's yellow.

### Seventeen frames, eleven colours

The five pendulum variants are not separate colours. The game draws a pendulum card as its base frame with a second tone across the bottom, and this follows: `effect_pendulum` is `effect` with a pendulum treatment. That is 11 colours and one rule covering 17 frames, and it means the four pendulum variants that hold fewer than forty cards each cost nothing.

<!-- assumed: pendulum variants derive from their base frame rather than receiving their own colours (source: R1.AC1 requires frames a user must tell apart to differ, and the game itself draws them as variants) -->

### Each colour is a pair, not a value

`C3` requires colours that resolve in both appearances, and two frames make that unavoidable: silver synchro disappears on a light surface and near-black Xyz disappears on a dark one.

So every frame colour is defined as a light value and a dark value, and the dark value is the light one lifted or darkened until it holds 3:1 against the dark surface. `R2.AC4` then falls out of the definition rather than needing care at each call site.

### Colour is a marker, never a fill

`R2.AC1` is the line between "colourful" and "loud". The frame colour appears as a bar along the leading edge of a tile or a row, and as a small dot in dense lists. Nothing is written on top of it, so its contrast never has to carry text.

Surfaces and text stay system-derived. A screen's colour comes from card artwork, from the markers, and from the accent — and nowhere else.

## Data Model

No stored data. The additions to `Theme`:

```swift
extension Theme.Palette {
    /// A frame's marker colour, resolving per appearance.
    static func frame(_ frame: CardFrame) -> Color

    /// The measured values, exposed so a test can check them rather than
    /// trusting that they were chosen carefully.
    static func frameComponents(_ frame: CardFrame) -> (light: RGB, dark: RGB)
}

extension Theme.Typography {
    static let screenTitle: Font    // 22 semibold
    static let sectionTitle: Font   // 15 semibold  (was 13)
    static let body: Font           // 13
    static let figure: Font         // 17 medium, monospaced digits
    static let caption: Font        // 11
}

extension Theme {
    enum Elevation {
        static let page: Color      // the window behind everything
        static let raised: Color    // a card, a panel, a row group
        static let overlay: Color   // a popover or a sheet
    }
}
```

`RGB` is a plain triple of doubles so the test can compute ΔE and contrast without going through `NSColor`, which is not available in a test running without a display.

## Options Considered

1. **Colour carrying meaning over one accent colour.** Chosen by the user. A duelist already reads frame colour faster than a label, and the alternative would have been decorative — prettier to arrive at, useless to read.
2. **Eleven colours over seventeen.** Seventeen would give `ritual_pendulum`'s six cards a hue of their own and would leave no room between the ones that matter.
3. **Markers over tinted rows.** A tinted row is the obvious way to show a frame and would put text on colour on every line, which is where "colourful but minimal" fails.
4. **Measured constraints over chosen values.** Picking colours by eye is faster and cannot be checked. The thresholds above turn `R1.AC1` and `R1.AC4` into arithmetic.
5. **Colour pairs over a single value with opacity.** Adjusting opacity per appearance is less code and does not fix near-black on black.
6. **Widening `Theme` over a parallel theme type.** A second type would let the two drift; `R4.AC2` exists to prevent exactly that.

## Simplicity And Elegance Review

What keeps this small:

- One file holds every value. The screens change by reading new names, not by learning new rules.
- Pendulum is a modifier, not five more colours.
- The frame colour is one function of one argument, so a tile, a row and a panel all ask the same question.
- The thresholds make the palette checkable, so nobody has to defend a hue in review.

Challenged once: the whole feature could have been "change some colours in `Theme`" with no specification at all. Rejected because `R1.AC4` is a real constraint that a casual change would break — the game's own effect-monster orange is limited's orange, and only measuring catches it.

## Failure Modes And Tradeoffs

| Failure | Containment |
| --- | --- |
| A frame colour drifts toward a restriction colour | The ΔE test fails before it ships (`R1.AC4`) |
| Two frames become hard to tell apart | The pairwise ΔE test fails (`R1.AC1`) |
| A marker vanishes on one appearance | Each colour is a pair, checked at 3:1 against its own surface |
| An unknown frame arrives from upstream | Falls back to the token grey, which claims nothing (`R1.AC5`) |
| Colour is the only clue | Every marker sits beside the text it encodes; `NFR1` requires it |
| A literal creeps into a feature | The token test scans the feature sources for colour and size literals (`R4.AC2`) |
| Heavier tiles cost the grid its budget | The narrowing budget from `card-detail` is re-measured (`C4`, `NFR3`) |

Accepted tradeoffs:

- **Two frames are not the game's colours.** Effect monsters are stone rather than orange and normal monsters are sand rather than yellow, because those two hues mean "limited" and "semi-limited" here. A duelist may find that odd for a day.
- **CIE76 is a crude distance.** It overstates differences in some blues. At thresholds of 18 and 25 that does not matter, and anything better needs a dependency for one test.
- **Eleven colours cannot make seventeen frames unique.** The five pendulum variants share their base colour, which is what the game does too.
- **This touches every screen.** Five screens' worth of edits to change no behaviour, which is the price of not leaving half the application looking like the other half.

## Verification Plan

The palette is tested as arithmetic over its own values: no rendering, no display, no snapshots. The screens are tested for the absence of literals rather than for how they look, because how they look is not something a proof can hold.

| Check | Observation that decides it |
| --- | --- |
| Every frame has a colour | All 17 frames resolve, including the five pendulum variants |
| Frames are distinct | Every pair of base frame colours measures ΔE ≥ 18 |
| Not mistakable for restriction | Every frame colour measures ΔE ≥ 25 from forbidden, limited and semi-limited |
| Extra deck separable | The seven extra-deck frames are separable from the rest by colour alone |
| Restriction colours unchanged | Forbidden, limited and semi-limited hold their current values |
| Unknown frame | A frame outside the palette resolves to the neutral, not to nothing |
| Markers visible | Every frame colour holds ≥ 3:1 against its own appearance's surface |
| Text contrast | Every text-on-surface pair holds ≥ 4.5:1 in both appearances |
| Both appearances | Every colour resolves to a different value per appearance where it needs to |
| A scale exists | The five type levels are strictly ordered in prominence |
| Figures do not shift | The figure style uses monospaced digits |
| Elevation | The three elevation levels differ in both appearances |
| One definition each | No feature source contains a colour, font-size, radius or spacing literal |
| Every screen | Each of the five screens reads the new tokens |
| Colour is not alone | Every colour-coded fact has a text form beside it |
| Grid budget | Narrowing still follows a keystroke within 150 ms with the new tiles |
| Concurrency | The design system and every feature build under Swift 6 with no diagnostics |

## Requirement Coverage

| Requirement | Covered By |
| --- | --- |
| `R1` | `Palette.frame(_:)` over the measured table, with pendulum deriving from its base and an unknown frame falling back to the neutral; the first six checks |
| `R2` | Markers rather than fills, system-derived surfaces, and the contrast and appearance checks |
| `R3` | The five-level `Typography` scale, the monospaced figure style and `Elevation`; the three scale checks |
| `R4` | Every value in `Theme`, the literal scan across feature sources, and the five screens reading them |
| `NFR1` | Text beside every marker; the colour-is-not-alone check |
| `NFR2` | The contrast and appearance checks |
| `NFR3` | The re-measured narrowing budget |
| `NFR4` | One definition per token; the literal scan |
| `NFR5` | Value types throughout; the strict-concurrency build check |
