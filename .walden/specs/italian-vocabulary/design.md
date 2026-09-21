---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T14:41:01Z
last_modified: 2026-09-21T14:41:01Z
approved_fingerprint: sha256:e5d0205e7358148d9b55de44699cb621620272aeac4dc569c48362f48089494a
source_requirements_approved_at: 2026-09-21T14:41:01Z
source_requirements_fingerprint: sha256:afd132cb84ad26ed6102499cf612fb09600acbb663b5da1935ce67f05249697f
---

# Feature Design

## Architecture

One table, read by everything that shows a card. No new module and nothing stored: a translation is a lookup on a constant.

```
YGOCore ── Vocabulary ──▶ read by every feature that shows a card
```

The vocabulary lives in `YGOCore` beside the types whose values it translates, because that is where a `CardFrame` and an attribute already are, and because putting it in the design system would make a word list a rendering concern.

### Most of the "vocabulary" is proper names

The catalog reports 101 distinct card kinds and 87 monster types, which sounds like a large table. It is not:

- **54 of the 101 kinds are `Skill - <character>`** — Duel Links skill cards, whose kind carries the character's name. Upstream truncates it to thirteen characters: `Skill - Bastion Misaw`, `Skill - Chazz Princet`.
- **53 of the 87 monster types are those same character names**, because a skill card's type column holds the character rather than a monster type. One more value is the empty string.

`R2.AC3` says proper names stay as published, so those are not translated. A `Skill - X` kind translates its prefix and keeps the name: **`Abilità - Joey Wheeler`**. The truncation is the upstream's and is left alone — inventing the missing letters would be inventing data.

That leaves 47 real card kinds and 33 real types, plus 7 attributes and the rarities the Italian market renames.

<!-- assumed: Skill kinds translate their prefix and keep the character name (source: R2.AC3, which keeps proper names as published) -->

### Curated entries, not composed ones

The kinds compose — `Fusion Pendulum Effect Monster` is four words — so a token dictionary applied word by word is tempting. It is also wrong in Italian, where the noun leads: *Mostro Fusione Pendulum Effetto*, not *Fusione Pendulum Effetto Mostro*.

So the table holds whole terms. It is finite, it was generated from the catalog's own distinct values, and a test walks every value the catalog holds and asserts each one resolves. Composition would be shorter to write and impossible to check.

### An unknown term is shown, not hidden

`R1.AC5` is the rule the table needs most. Link arrived in 2017 and Pendulum in 2014; the next one will arrive too. A lookup that misses returns the upstream term unchanged, so a new card kind reads in English rather than as an empty label.

The same function therefore serves both cases, and no caller has to decide what to do about a miss.

### The type column holds three different things

`race` carries a monster's type for a monster, a spell's kind for a spell (`Normal`, `Continuous`, `Quick-Play`, `Equip`, `Field`, `Ritual`), a trap's kind for a trap (`Normal`, `Continuous`, `Counter`), and a character's name for a skill.

`Normal` therefore means *Normale* for a monster and for a spell alike, which is convenient, but the table is one map rather than three because the upstream's own column is one.

## Data Model

Nothing stored. A constant in `YGOCore`:

```swift
public enum Vocabulary {
    /// "Effect Monster" → "Mostro Effetto". An unknown kind is returned as
    /// published (R1.AC5).
    public static func cardKind(_ upstream: String) -> String

    /// DARK → "OSCURITÀ". Seven values, all known.
    public static func attribute(_ upstream: String) -> String

    /// "Spellcaster" → "Incantatore"; a character's name is returned as
    /// published.
    public static func monsterType(_ upstream: String) -> String

    /// "Common" → "Comune"; "Secret Rare" stays, because that is what the
    /// Italian market calls it (C6).
    public static func rarity(_ upstream: String) -> String

    /// Which of a set of terms the table does not hold, for R3.AC4.
    public static func untranslated(kinds: [String], types: [String]) -> [String]
}
```

Five functions with the same shape, each a dictionary lookup with the argument as its default.

### Where the terms appear

`Card.humanReadableType` is shown in four places — the grid tile's subtitle, the detail panel's header, a deck row and a collection row — and each currently prints it raw. Each becomes `Vocabulary.cardKind(...)`. The filter panel's monster type field shows and matches translated values, which `R2.AC4` requires and which is one line either side of the existing completion.

## Options Considered

1. **A curated table over composition.** Composition is shorter and produces Italian in the wrong order. The table is finite and checkable.
2. **Translating the prefix of a skill kind over translating the whole thing.** The whole thing contains a character's name, which `R2.AC3` keeps.
3. **Leaving the upstream truncation alone over completing the names.** `Bastion Misaw` is what the source publishes; the missing letters would be ours.
4. **One map for the type column over three.** The upstream column holds monster types, spell kinds, trap kinds and character names. Splitting it would need a card's frame at every call site to know which map to use.
5. **The vocabulary in `YGOCore` over the design system.** A word list is not a rendering concern, and the types it translates are already here.
6. **Returning the upstream term on a miss over a placeholder.** A placeholder would hide that something new has arrived; the English term at least names it.

## Simplicity And Elegance Review

What keeps this small:

- No storage, no migration, no fetch. A constant and five lookups.
- The miss case and the hit case are the same call, so no caller branches.
- The table was generated from the catalog rather than imagined, so it covers what exists rather than what seemed likely.
- `R3.AC4` is a function over the same table, not a second inventory.

Challenged once: this could have been a localisation file with the terms as keys. Rejected because the keys would be English strings from a third party, which is what a `Localizable.strings` file is worst at, and because a test that walks the catalog's distinct values is a stronger guarantee than a translator's checklist.

## Failure Modes And Tradeoffs

| Failure | Containment |
| --- | --- |
| A new card kind arrives from upstream | Shown in English, and `R3.AC4` counts it |
| A skill's character name is translated by accident | Only the prefix is mapped; the remainder is copied |
| The same term reads differently on two screens | One function, one table (`R2.AC1`, `R2.AC2`) |
| A filter shows Italian and matches English | The filter matches on what is displayed (`R2.AC4`) |
| A rarity is translated into a term nobody uses | Only the rarities the Italian market renames are mapped (`C6`) |
| The upstream truncation looks like our bug | Left as published, and said so here |

Accepted tradeoffs:

- **The table is ours and can age.** There is no upstream source for these translations, so a new term is a code change. `R3.AC4` makes that visible instead of silent.
- **Truncated character names stay truncated.** `Bastion Misaw` reads badly and is what the source says.
- **Attributes in capitals.** `OSCURITÀ`, `LUCE`: the game writes them that way in Italian too.
- **Nothing for the 2,981 untranslated cards.** Their names and text stay English because the upstream has no Italian for them; only their vocabulary becomes Italian, which is a half-translated card by upstream's choice rather than ours.

## Verification Plan

The vocabulary is tested against the catalog's own distinct values, read from the live database's shape rather than from a list someone typed. A term that exists is required to resolve; a term that does not is required to survive.

| Check | Observation that decides it |
| --- | --- |
| Kinds translated | "Effect Monster" reads "Mostro Effetto", "Quick-Play Spell" reads "Magia Rapida" |
| Attributes translated | All seven resolve; DARK is "OSCURITÀ" and LIGHT is "LUCE" |
| Types translated | "Spellcaster" is "Incantatore", "Winged Beast" is "Bestia Alata" |
| Rarities | "Common" is "Comune"; "Secret Rare" is unchanged |
| Unknown terms survive | An invented kind is returned unchanged rather than blanked |
| Skill kinds | "Skill - Joey Wheeler" reads "Abilità - Joey Wheeler" |
| Character names untouched | A skill's character type is returned as published, truncation included |
| Consistent everywhere | The same card's kind is identical in grid, detail, deck row and collection row |
| One definition | No feature module contains a translation of an upstream term |
| Proper names kept | An archetype, a set name and a format name are unchanged |
| Filters match what is shown | Typing "incantatore" finds Spellcaster |
| Every attribute covered | All seven the catalog holds resolve to Italian |
| Every kind covered | All 101 resolve, the 54 skill kinds through their prefix |
| Every type covered | All 87 resolve, the character names as themselves |
| Untranslated reported | The count is available and is zero for the catalog as it stands |
| Cost | Translating a grid of 200 tiles is a lookup per tile and measurable as such |
| Concurrency | The feature builds under Swift 6 strict concurrency with no diagnostics |

## Requirement Coverage

| Requirement | Covered By |
| --- | --- |
| `R1` | `Vocabulary.cardKind`, `.attribute`, `.monsterType` and `.rarity`, each defaulting to its argument; the first seven checks |
| `R2` | One table in `YGOCore` read by every screen, and the filter matching on displayed values; the four consistency checks |
| `R3` | Tables generated from the catalog's distinct values, and `untranslated(kinds:types:)`; the four coverage checks |
| `NFR1` | A dictionary lookup per term; the cost check |
| `NFR2` | The argument as the default on every lookup; the unknown-term check |
| `NFR3` | The translated term is the one shown and therefore the one read aloud |
| `NFR4` | A constant and pure functions; the strict-concurrency build check |
