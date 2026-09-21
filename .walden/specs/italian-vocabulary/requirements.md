---
walden_schema_version: v1alpha1
status: approved
approved_at: 2026-09-21T14:41:01Z
last_modified: 2026-09-21T14:41:01Z
approved_fingerprint: sha256:afd132cb84ad26ed6102499cf612fb09600acbb663b5da1935ce67f05249697f
---

# Requirements Document

## Introduction

Every label the application writes is already Italian. What is not Italian is the catalog's own vocabulary, and the upstream does not translate it: asking for the Italian dataset returns an Italian `name` and `desc` and leaves everything else in English. A card reads *Un Oceano Leggendario*, and under it, *Field Spell*.

This feature translates the catalog's vocabulary — what kind of card it is, what attribute it carries, what kind of monster it is, and at what rarity it was printed — so that an Italian card is described in Italian.

Facts measured against the user's own database on 2026-09-21:

- **The Italian dataset localises two fields.** `name` and `desc` come back in Italian; `type`, `humanReadableCardType`, `race` and `attribute` come back in English.
- **101 distinct human-readable types**, because they compose: Effect Monster 5,130, Normal Trap 1,339, Normal Spell 1,084, Normal Monster 671, Xyz Effect Monster 589, Quick-Play Spell 575, and ninety-five more.
- **87 monster types**, led by Warrior, Machine, Fiend, Dragon, Spellcaster and Fairy — and by *Normal* and *Continuous*, which are spell and trap kinds sharing the same column.
- **7 attributes**: DARK, DIVINE, EARTH, FIRE, LIGHT, WATER, WIND.
- **29 card types** and **48 printing rarities**.
- **The upstream grows.** New card kinds have arrived repeatedly — Link in 2017, Pendulum in 2014 — so any table of translations will one day meet a term it does not hold.

## Requirements

### R1 Describing a card in Italian

**User Story:** As an Italian player, I want a card described in the language its name is in, so that a card does not read half translated.

#### Acceptance Criteria

1. `R1.AC1` WHEN a card's kind is shown, the system SHALL present it in Italian.
   - Acceptance check: a card whose upstream kind is "Effect Monster" is described as "Mostro Effetto".
2. `R1.AC2` WHEN a monster's attribute is shown, the system SHALL present it in Italian.
   - Acceptance check: DARK reads as "OSCURITÀ" and LIGHT as "LUCE".
3. `R1.AC3` WHEN a monster's type is shown, the system SHALL present it in Italian.
   - Acceptance check: "Spellcaster" reads as "Incantatore" and "Winged Beast" as "Bestia Alata".
4. `R1.AC4` WHEN a printing's rarity is shown, the system SHALL present it in Italian where the Italian market uses a different name.
   - Acceptance check: "Common" reads as "Comune"; a rarity the Italian market names in English, such as "Secret Rare", keeps that name.
5. `R1.AC5` IF a term is not in the vocabulary, THEN the system SHALL present the upstream term unchanged rather than nothing.
   - Acceptance check: a card kind invented after this table was written is displayed in English rather than as an empty label.

### R2 Translating consistently

**User Story:** As someone reading several screens, I want the same term translated the same way everywhere, so that I do not have to learn two names for one thing.

#### Acceptance Criteria

1. `R2.AC1` The system SHALL translate a given term identically wherever it appears.
   - Acceptance check: the same card's kind reads the same in the catalog grid, the detail panel, a deck list and a collection row.
2. `R2.AC2` The system SHALL define each translation in one place.
   - Acceptance check: no feature module contains a translation of an upstream term.
3. `R2.AC3` The system SHALL keep proper names untranslated.
   - Acceptance check: an archetype, a set name and a format name are shown as published.
4. `R2.AC4` WHERE a filter offers upstream terms as choices, the system SHALL show them translated and match on what the user sees.
   - Acceptance check: typing "incantatore" in the monster type field finds Spellcaster.

### R3 Covering what the catalog holds

**User Story:** As the person using this, I want the translation to cover the cards I actually have, so that "mostly translated" does not mean the half I never look at.

#### Acceptance Criteria

1. `R3.AC1` The system SHALL translate every attribute the catalog holds.
   - Acceptance check: all seven attributes resolve to an Italian term.
2. `R3.AC2` The system SHALL translate every card kind the catalog holds.
   - Acceptance check: all 101 human-readable kinds resolve to an Italian term.
3. `R3.AC3` The system SHALL translate every monster type the catalog holds.
   - Acceptance check: all 87 types resolve to an Italian term.
4. `R3.AC4` The system SHALL report which upstream terms it does not translate.
   - Acceptance check: a count of untranslated terms is available, and it is zero for the catalog as it stands.

## Non-Functional Requirements

- `NFR1` Cost: translating a term is a lookup, not a computation, so it adds nothing measurable to a grid of 200 tiles. Bridged by `R2.AC1`.
- `NFR2` Honesty: a term the vocabulary does not hold is shown as published rather than blanked or guessed at. Bridged by `R1.AC5`.
- `NFR3` Accessibility: the translated term is what is read aloud, not the English one beside it. Bridged by `R2.AC1`.
- `NFR4` Concurrency safety: the feature builds and runs under Swift 6 strict concurrency checking with no data-race diagnostics suppressed.

## Constraints And Dependencies

- `C1` The upstream translates `name` and `desc` only. Everything else is English regardless of the language asked for.
- `C2` The vocabulary is fixed in the application, not fetched. There is no upstream source for these translations.
- `C3` 101 kinds, 87 types, 7 attributes and 48 rarities, measured against the catalog as it stands on 2026-09-21.
- `C4` The upstream adds terms as the game does, so the table will meet unknown ones. `R1.AC5` is the rule for that, not an edge case.
- `C5` Card names and effect text are already translated upstream and are not touched here.
- `C6` Some rarities are known in Italy by their English names. Translating "Secret Rare" would be inventing a term nobody uses.
- `C7` Target platform is macOS 27 on arm64, built with Swift 6.4 and Swift Package Manager.

## Out Of Scope

- Translating card names or effect text, which the upstream already does.
- Translating archetype names, set names or format names, which are proper names.
- A second interface language, or letting the user choose the vocabulary's language.
- Translating the 2,981 cards the upstream has no Italian text for.
