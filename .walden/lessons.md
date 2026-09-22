# Walden Lessons

Review this file before non-trivial work when the current request matches past mistakes, rejections, or validation failures.

## Lessons

<!-- Append entries with: walden lesson log --feature <name> --phase <phase> --trigger "..." --lesson "..." --guardrail "..." -->
### 2026-09-19T18:07:08Z | card-catalog | execute
- Trigger: Task 7's CatalogWriter aborted on the recorded fixture with 'UNIQUE constraint failed: card_format.card_id, card_format.format_code'. The upstream dataset repeats a format name for 8 of its 14,566 cards - Blue-Eyes White Dragon lists 'Speed Duel' twice - which a hand-written fixture would not have contained.
- Lesson: Third-party datasets violate their own implied uniqueness. A field that reads as a set in the documentation can arrive as a list with repeats, and a primary key built on that assumption aborts the whole ingestion transaction on a card most of the way through the file.
- Guardrail: Build ingestion fixtures by sampling the real upstream payload for structural edge cases (repeats, absent optional fields, multi-valued identifiers) rather than hand-writing minimal examples, and deduplicate any upstream collection before it reaches a uniqueness constraint.

### 2026-09-20T08:51:06Z | card-catalog | execute
- Trigger: Task 16's filter tests failed with empty result sets for any query combining a format filter with another filter, while each filter alone worked. The query builder appended bound arguments in the order the clauses were constructed (text, conditions, joins) rather than the order the '?' placeholders appear in the assembled SQL (joins, conditions, ordering, paging), so values were bound to the wrong placeholders.
- Lesson: A SQL builder that assembles clauses out of order must collect each clause's arguments separately and concatenate them in placeholder order. Positional binding fails silently: the statement still executes and returns a plausible-looking empty or wrong result rather than an error, so only a test asserting real result membership catches it.
- Guardrail: In any query builder, keep one argument accumulator per clause and concatenate them in the exact order the clauses appear in the emitted SQL. Test every filter both alone and in combination with a filter that contributes a JOIN, asserting set membership rather than merely a non-zero count.

### 2026-09-22T11:33:03Z | deck-history | execute
- Trigger: Writing Tests/YGOSyncTests/DeckHistoryTests.swift with a shell heredoc silently overwrote a tracked file of the same name holding deck-editing's four certified undo and redo proofs. It surfaced only as 'verification failed for deck-editing: 5' in the final portfolio verify.
- Lesson: A new test file's name can already be taken by another spec's certified proofs, and a heredoc write destroys them without a word. The suite name is also the proof's selector, so the collision breaks the other spec's verification rather than merely duplicating a name.
- Guardrail: Before writing any test file, check that the path is untracked and the suite name is unused: git ls-files --error-unmatch <path> and grep -rn 'struct <SuiteName>' Tests/. Use an editing tool that refuses to clobber, and confirm the file's @Test count rose rather than reset.

