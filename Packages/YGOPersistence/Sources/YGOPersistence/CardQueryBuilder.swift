import Foundation
import GRDB
import YGOCore

/// Turns a `CardQuery` into one SQL statement.
///
/// Text matching and property filters compose into a single statement rather
/// than a match followed by an in-memory narrowing, so a search costs one
/// indexed query no matter how many filters are applied.
struct CardQueryBuilder {
    let query: CardQuery

    /// Column weights for `bm25`, in the order the virtual table declares them:
    /// `name_en`, `desc_en`, `name_it`, `desc_it`.
    ///
    /// Weighting the name columns far above the description columns is what
    /// puts cards matched on their name ahead of cards that merely mention the
    /// words in their effect text, inside the query that already had to run.
    /// Ranking in a second pass would cost a second scan of the same rows.
    static let nameWeight = 10.0
    static let descriptionWeight = 1.0

    /// Escapes user text into an FTS5 match expression.
    ///
    /// Raw input cannot be passed through: a stray quote, asterisk or colon is
    /// FTS syntax and would either throw or mean something the user did not
    /// type. Each word becomes a quoted prefix term, so "dark mag" still finds
    /// "Dark Magician".
    ///
    /// Returns `nil` when the text holds nothing matchable, such as punctuation
    /// alone.
    static func matchExpression(for text: String) -> String? {
        let terms = text
            .split(whereSeparator: \.isWhitespace)
            .map { term in
                String(term.filter { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "-" })
            }
            .filter { !$0.isEmpty }
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }

        guard !terms.isEmpty else { return nil }
        return terms.joined(separator: " ")
    }

    /// The statement, or `nil` when the query can match nothing at all.
    ///
    /// Arguments are collected per clause and concatenated in the order the
    /// placeholders appear in the finished SQL - joins, then conditions, then
    /// ordering, then the page. SQLite binds `?` positionally, so appending
    /// them in construction order instead silently pairs each value with the
    /// wrong placeholder.
    func makeStatement() -> (sql: String, arguments: StatementArguments)? {
        var joins: [String] = []
        var joinArguments = StatementArguments()
        var conditions: [String] = []
        var conditionArguments = StatementArguments()
        var ordering: [String] = []
        var orderingArguments = StatementArguments()

        // MARK: Text

        if let text = query.normalizedText {
            guard let expression = Self.matchExpression(for: text) else { return nil }
            joins.append("JOIN card_fts ON card_fts.rowid = card.id")
            conditions.append("card_fts MATCH ?")
            conditionArguments += [expression]

            // An exact name match leads, whichever language it was typed in.
            ordering.append("""
                CASE WHEN card.name_en = ? COLLATE NOCASE
                       OR card.name_it = ? COLLATE NOCASE THEN 0 ELSE 1 END
                """)
            orderingArguments += [text, text]

            ordering.append(
                "bm25(card_fts, \(Self.nameWeight), \(Self.descriptionWeight), "
                + "\(Self.nameWeight), \(Self.descriptionWeight))")
        } else {
            ordering.append("card.name_en COLLATE NOCASE")
        }

        // MARK: Joins

        let filters = query.filters

        if let format = filters.format {
            joins.append("""
                JOIN card_format ON card_format.card_id = card.id
                    AND card_format.format_code = ?
                """)
            joinArguments += [format.rawValue]

            if !filters.banStatuses.isEmpty {
                joins.append("""
                    LEFT JOIN ban_status ON ban_status.card_id = card.id
                        AND ban_status.format_code = ?
                    """)
                joinArguments += [format.rawValue]
            }
        }

        // MARK: Conditions

        appendSetCondition(filters.frames.map(\.rawValue), column: "card.frame_type",
                           to: &conditions, arguments: &conditionArguments)
        appendSetCondition(filters.attributes.map(\.rawValue), column: "card.attribute",
                           to: &conditions, arguments: &conditionArguments)
        appendSetCondition(Array(filters.races), column: "card.race",
                           to: &conditions, arguments: &conditionArguments)
        appendSetCondition(Array(filters.archetypes), column: "card.archetype",
                           to: &conditions, arguments: &conditionArguments)

        appendRangeCondition(filters.levels, column: "card.level",
                             to: &conditions, arguments: &conditionArguments)
        appendRangeCondition(filters.attack, column: "card.atk",
                             to: &conditions, arguments: &conditionArguments)
        appendRangeCondition(filters.defense, column: "card.def",
                             to: &conditions, arguments: &conditionArguments)
        appendRangeCondition(filters.linkRatings, column: "card.link_value",
                             to: &conditions, arguments: &conditionArguments)
        appendRangeCondition(filters.pendulumScales, column: "card.pendulum_scale",
                             to: &conditions, arguments: &conditionArguments)

        if filters.format != nil, !filters.banStatuses.isEmpty {
            appendBanCondition(filters.banStatuses,
                               to: &conditions, arguments: &conditionArguments)
        }

        // MARK: Assembly

        let sql = """
            SELECT card.* FROM card
            \(joins.joined(separator: "\n"))
            \(conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: "\n  AND "))
            ORDER BY \(ordering.joined(separator: ", "))
            LIMIT ? OFFSET ?
            """

        var arguments = joinArguments
        arguments += conditionArguments
        arguments += orderingArguments
        arguments += [query.limit, query.offset]

        return (sql, arguments)
    }

    // MARK: - Condition helpers

    private func appendSetCondition(
        _ values: [String],
        column: String,
        to conditions: inout [String],
        arguments: inout StatementArguments
    ) {
        guard !values.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: values.count).joined(separator: ", ")
        conditions.append("\(column) IN (\(placeholders))")
        arguments += StatementArguments(values)
    }

    private func appendRangeCondition(
        _ range: ClosedRange<Int>?,
        column: String,
        to conditions: inout [String],
        arguments: inout StatementArguments
    ) {
        guard let range else { return }
        // A card with no value for the column is excluded rather than treated
        // as zero: two thirds of the pool has no ATK at all.
        conditions.append("\(column) IS NOT NULL AND \(column) BETWEEN ? AND ?")
        arguments += [range.lowerBound, range.upperBound]
    }

    /// Unrestricted is stored as the absence of a row, so asking for it means
    /// asking for a null join rather than for a fourth status value.
    private func appendBanCondition(
        _ statuses: Set<BanStatus>,
        to conditions: inout [String],
        arguments: inout StatementArguments
    ) {
        let stored = statuses.compactMap(\.storedValue)
        let wantsUnrestricted = statuses.contains(.unlimited)

        switch (stored.isEmpty, wantsUnrestricted) {
        case (true, true):
            conditions.append("ban_status.status IS NULL")
        case (false, true):
            let placeholders = Array(repeating: "?", count: stored.count).joined(separator: ", ")
            conditions.append("(ban_status.status IS NULL OR ban_status.status IN (\(placeholders)))")
            arguments += StatementArguments(stored)
        case (false, false):
            let placeholders = Array(repeating: "?", count: stored.count).joined(separator: ", ")
            conditions.append("ban_status.status IN (\(placeholders))")
            arguments += StatementArguments(stored)
        case (true, false):
            break
        }
    }
}
