import Foundation
import YGOCore

/// Undo and redo for the edits made to one open deck.
///
/// It holds edits, not deck states. Every edit's inverse is another edit of the
/// same kind, so undoing reuses the two write operations and there is no third
/// way of putting a deck into a given shape.
///
/// It is not stored: an undo is for the mistake just made, and `C5` scopes it
/// to an open editor.
struct DeckEditHistory {
    private(set) var applied: [DeckEdit] = []
    private(set) var undone: [DeckEdit] = []

    var canUndo: Bool { !applied.isEmpty }
    var canRedo: Bool { !undone.isEmpty }

    mutating func record(_ edit: DeckEdit) {
        applied.append(edit)
        // A redo of something that no longer follows from the current deck
        // would apply a change to a deck it was never about.
        undone.removeAll()
    }

    /// The edit to apply in order to undo the last one, or `nil` when there is
    /// nothing to undo.
    mutating func takeUndo() -> DeckEdit? {
        guard let last = applied.popLast() else { return nil }
        undone.append(last)
        return last.inverse
    }

    mutating func takeRedo() -> DeckEdit? {
        guard let last = undone.popLast() else { return nil }
        applied.append(last)
        return last
    }

    /// Called when another deck is opened. A ⌘Z meant for one deck reaching
    /// another is the worst thing this could do.
    mutating func clear() {
        applied.removeAll()
        undone.removeAll()
    }
}

import CoreTransferable
import UniformTypeIdentifiers

/// Lets a dragged payload cross SwiftUI's drag boundary.
///
/// The conformance lives in the feature module rather than in `YGOCore`, which
/// depends on nothing and should not start depending on a UI framework for one
/// gesture.
extension DeckDragPayload: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .ygoDeckDragPayload)
    }
}

extension UTType {
    static let ygoDeckDragPayload = UTType(
        exportedAs: "app.ygodeckmanager.deck-drag-payload")
}
