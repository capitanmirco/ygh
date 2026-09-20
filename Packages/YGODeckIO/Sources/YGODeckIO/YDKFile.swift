import Foundation
import YGOCore

/// The `.ydk` format used by EDOPro and by the community's deck sites.
///
/// A file is section markers and passcodes, one per line. It carries no deck
/// name, no format and no card names, so everything else has to come from the
/// catalog or from the user.
public enum YDKFile {
    static let mainMarker = "#main"
    static let extraMarker = "#extra"
    static let sideMarker = "!side"

    /// Reads a file's contents.
    ///
    /// Tolerant by necessity: real files carry a `#created by` line, blank
    /// lines, trailing whitespace and either line ending.
    public static func read(_ text: String) -> DeckList {
        var list = DeckList()
        var section: DeckSection?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            switch line {
            case mainMarker: section = .main
            case extraMarker: section = .extra
            case sideMarker: section = .side
            default:
                // Any other marker line closes the current section rather than
                // quietly adding its contents to it.
                if line.hasPrefix("#") || line.hasPrefix("!") {
                    section = nil
                } else if let passcode = Int(line), let section, passcode > 0 {
                    list[section].append(passcode)
                }
            }
        }

        return list
    }

    public static func read(contentsOf url: URL) throws -> DeckList {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw DeckInterchangeError.unreadableText
        }
        return read(text)
    }

    /// Writes a deck in the shape the rest of the ecosystem expects.
    public static func write(_ list: DeckList, createdBy creator: String = "YGODeckManager") -> String {
        var lines = ["#created by \(creator)", mainMarker]
        lines += list.main.map(String.init)
        lines.append(extraMarker)
        lines += list.extra.map(String.init)
        lines.append(sideMarker)
        lines += list.side.map(String.init)
        return lines.joined(separator: "\n") + "\n"
    }
}
