import Foundation
import Observation
import YGOCore

/// Drives the filter panel beside the grid.
///
/// A panel rather than a popover: `R5.AC2` needs the applied filters visible
/// while the results change, and a popover that stays open to show them covers
/// what it is changing.
@MainActor
@Observable
public final class FilterPanelModel {
    /// The sections the keyboard moves through, in reading order.
    public enum Region: String, CaseIterable, Hashable, Sendable {
        case cardType, attribute, level, monsterType, archetype
        case stats, era, format, publishedList, owned

        public var title: String {
            switch self {
            case .cardType: "Tipo carta"
            case .attribute: "Attributo"
            case .level: "Livello"
            case .monsterType: "Tipo mostro"
            case .archetype: "Archetipo"
            case .stats: "Attacco e difesa"
            case .era: "Anno di uscita"
            case .format: "Formato"
            case .publishedList: "Banlist"
            case .owned: "Collezione"
            }
        }
    }

    public private(set) var focusedRegion: Region = .cardType
    public private(set) var allMonsterTypes: [String] = []
    public private(set) var allArchetypes: [String] = []

    /// What the user has typed into each of the two long fields.
    public var monsterTypeQuery = ""
    public var archetypeQuery = ""

    private let vocabulary: any CardVocabularyReading

    public init(vocabulary: any CardVocabularyReading) {
        self.vocabulary = vocabulary
    }

    public func load() async {
        allMonsterTypes = (try? await vocabulary.monsterTypes()) ?? []
        allArchetypes = (try? await vocabulary.archetypes()) ?? []
    }

    /// 87 values. A menu of them is a wall, so typing narrows it.
    public var monsterTypeSuggestions: [String] {
        Self.narrow(allMonsterTypes, by: monsterTypeQuery)
    }

    /// 662 values, which is the one that makes this necessary rather than
    /// merely nicer.
    public var archetypeSuggestions: [String] {
        Self.narrow(allArchetypes, by: archetypeQuery)
    }

    static func narrow(_ values: [String], by query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return values }
        // Matches anywhere, so "eyes" finds "Blue-Eyes" as well as "Red-Eyes".
        return values.filter { $0.range(of: trimmed, options: .caseInsensitive) != nil }
    }

    // MARK: - Keyboard

    public func focus(_ region: Region) {
        focusedRegion = region
    }

    /// Steps through the sections, stopping at the ends rather than wrapping.
    public func moveFocus(by offset: Int) {
        let regions = Region.allCases
        guard let current = regions.firstIndex(of: focusedRegion) else { return }
        focusedRegion = regions[min(max(current + offset, 0), regions.count - 1)]
    }

    /// Clears one filter without touching the others, which is what a keyboard
    /// path needs in order to be usable rather than merely present.
    public func clear(_ region: Region, in filters: inout CardFilters) {
        switch region {
        case .cardType: filters.cardTypes = []
        case .attribute: filters.attributes = []
        case .level: filters.levels = nil
        case .monsterType: filters.races = []; monsterTypeQuery = ""
        case .archetype: filters.archetypes = []; archetypeQuery = ""
        case .stats: filters.attack = nil; filters.defense = nil; filters.unknownStatsOnly = false
        case .era: filters.releaseYears = nil
        case .format: filters.format = nil; filters.banStatuses = []
        case .publishedList: filters.publishedList = nil
        case .owned: filters.ownedOnly = false
        }
    }
}
