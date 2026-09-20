import YGOCore

/// A deck as the interchange formats carry it: three lists of passcodes and
/// nothing else.
///
/// Both `.ydk` and YDKe decode to this, so resolving passcodes into cards,
/// handling alternate artworks and reporting what could not be resolved are
/// written once rather than once per format.
public struct DeckList: Hashable, Sendable {
    public var main: [Int]
    public var extra: [Int]
    public var side: [Int]

    public init(main: [Int] = [], extra: [Int] = [], side: [Int] = []) {
        self.main = main
        self.extra = extra
        self.side = side
    }

    public subscript(section: DeckSection) -> [Int] {
        get {
            switch section {
            case .main: main
            case .extra: extra
            case .side: side
            }
        }
        set {
            switch section {
            case .main: main = newValue
            case .extra: extra = newValue
            case .side: side = newValue
            }
        }
    }

    public var totalCount: Int { main.count + extra.count + side.count }
    public var isEmpty: Bool { totalCount == 0 }
}

/// Why a deck file or link could not be read.
public enum DeckInterchangeError: Error, Equatable {
    case notAYDKeLink
    case malformedSectionCount(Int)
    case notBase64(section: String)
    /// A section's byte count is not a whole number of passcodes.
    case truncatedSection(section: String, byteCount: Int)
    case unreadableText
}
