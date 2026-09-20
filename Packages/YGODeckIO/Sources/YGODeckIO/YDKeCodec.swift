import Foundation

/// The `ydke://` link format, used to pass a deck through a chat message.
///
/// `ydke://<main>!<extra>!<side>!` where each section is standard base64, with
/// padding, over 32-bit passcodes in little-endian order. Verified against the
/// published example, which decodes to real cards.
public enum YDKeCodec {
    public static let scheme = "ydke://"

    public static func decode(_ link: String) throws -> DeckList {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(scheme) else { throw DeckInterchangeError.notAYDKeLink }

        // The trailing separator leaves an empty fourth component.
        let components = trimmed.dropFirst(scheme.count).components(separatedBy: "!")
        guard components.count == 4, components[3].isEmpty else {
            throw DeckInterchangeError.malformedSectionCount(components.count)
        }

        return DeckList(
            main: try passcodes(components[0], section: "main"),
            extra: try passcodes(components[1], section: "extra"),
            side: try passcodes(components[2], section: "side"))
    }

    public static func encode(_ list: DeckList) -> String {
        let sections = [list.main, list.extra, list.side].map(base64)
        return scheme + sections.joined(separator: "!") + "!"
    }

    // MARK: - Sections

    private static func passcodes(_ encoded: String, section: String) throws -> [Int] {
        guard !encoded.isEmpty else { return [] }
        guard let data = Data(base64Encoded: encoded) else {
            throw DeckInterchangeError.notBase64(section: section)
        }
        // A passcode is four bytes; anything else means the link was cut short.
        guard data.count % 4 == 0 else {
            throw DeckInterchangeError.truncatedSection(section: section, byteCount: data.count)
        }

        return stride(from: 0, to: data.count, by: 4).map { offset in
            var value: UInt32 = 0
            for byte in (0..<4).reversed() {
                value = value << 8 | UInt32(data[data.startIndex + offset + byte])
            }
            return Int(value)
        }
    }

    private static func base64(_ passcodes: [Int]) -> String {
        var bytes = [UInt8]()
        bytes.reserveCapacity(passcodes.count * 4)
        for passcode in passcodes {
            let value = UInt32(truncatingIfNeeded: passcode)
            for shift in stride(from: 0, to: 32, by: 8) {
                bytes.append(UInt8truncating(value >> UInt32(shift)))
            }
        }
        return Data(bytes).base64EncodedString()
    }

    private static func UInt8truncating(_ value: UInt32) -> UInt8 {
        UInt8(value & 0xFF)
    }
}
