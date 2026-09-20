import Foundation
import Testing
import YGOCore
@testable import YGODeckIO

@Suite("YDK file")
struct YDKFileTests {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func realFile(_ name: String) throws -> DeckList {
        try YDKFile.read(contentsOf: Self.root.appending(path: "fixtures/\(name).ydk"))
    }

    /// Evidence for R5.AC1: a real file read into the three sections it
    /// declares, with the counts the game's rules expect.
    @Test func readsRealDeckFileIntoItsThreeSections() throws {
        let full = try realFile("LR-Chaos Turbo")
        #expect(full.main.count == 40)
        #expect(full.extra.count == 15)
        #expect(full.side.count == 15)
        #expect(full.main.allSatisfy { $0 > 0 })

        // A deck with no extra or side section reads as empty ones, not as
        // missing ones.
        let mainOnly = try realFile("Lockdown Burn")
        #expect(mainOnly.main.count == 40)
        #expect(mainOnly.extra.isEmpty)
        #expect(mainOnly.side.isEmpty)

        // Repeated copies stay repeated: the file is a list, not a set.
        let distinct = Set(mainOnly.main).count
        #expect(distinct < mainOnly.main.count, "il mazzo contiene copie multiple")
    }

    /// Evidence for R6.AC1: what is written reads back unchanged, copies and
    /// ordering included.
    @Test func writtenFileReadsBackAsTheSameDeck() throws {
        for name in ["LR-Chaos Turbo", "Lockdown Burn"] {
            let original = try realFile(name)
            let written = YDKFile.write(original)
            let reread = YDKFile.read(written)

            #expect(reread == original, "\(name) non è sopravvissuto al round trip")
            #expect(reread.main == original.main, "l'ordine delle carte deve restare")
        }

        // The written form carries the markers the rest of the ecosystem reads.
        let text = YDKFile.write(DeckList(main: [1, 1, 2], extra: [3], side: [4]))
        #expect(text.contains("#main"))
        #expect(text.contains("#extra"))
        #expect(text.contains("!side"))
        #expect(text.hasSuffix("\n"))
    }

    /// Real files are not tidy: they carry a creator line, blank lines,
    /// trailing spaces and whichever line ending the tool that wrote them used.
    @Test func toleratesCommentsBlankLinesAndCarriageReturns() {
        let messy = "#created by someone\r\n\r\n#main\r\n  1001  \r\n1002\r\n\r\n#extra\r\n2001\r\n!side\r\n3001\r\n"
        let list = YDKFile.read(messy)

        #expect(list.main == [1001, 1002])
        #expect(list.extra == [2001])
        #expect(list.side == [3001])

        // An unknown marker closes the section rather than swallowing what
        // follows into the wrong one.
        let unknown = YDKFile.read("#main\n1\n#notasection\n999\n!side\n2\n")
        #expect(unknown.main == [1])
        #expect(unknown.side == [2])
        #expect(!unknown.main.contains(999), "999 non appartiene a nessuna sezione nota")
        #expect(!unknown.side.contains(999))

        // Lines before any marker belong nowhere.
        let orphan = YDKFile.read("12345\n#main\n1\n")
        #expect(orphan.main == [1])

        // Nonsense lines are skipped rather than read as zero.
        let garbage = YDKFile.read("#main\nnot-a-number\n0\n-5\n7\n")
        #expect(garbage.main == [7])
    }
}
