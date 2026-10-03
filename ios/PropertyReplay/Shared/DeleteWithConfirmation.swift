import SwiftUI

/// Swipe or long-press a row to delete it, with the question attached to that row and naming what goes. Deleting here
/// is physical and reaches iCloud (ADR-0017), and there is no undo, so it asks. Since iOS 26 a confirmationDialog is
/// a bubble anchored to its view, so it belongs on the row, not on the screen (group memory
/// confirmation-dialog-anchors-to-its-view). The swipe button has no destructive role: that role animates the row
/// away before the answer.
struct DeleteWithConfirmation: ViewModifier {
    let question: LocalizedStringKey
    let actionLabel: LocalizedStringKey
    let action: () -> Void
    @State private var asking = false

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button { asking = true } label: { Label(actionLabel, systemImage: "trash") }
                    .tint(.red)
            }
            .contextMenu {
                Button(role: .destructive) { asking = true } label: { Label(actionLabel, systemImage: "trash") }
            }
            .confirmationDialog(question, isPresented: $asking, titleVisibility: .visible) {
                Button(actionLabel, role: .destructive, action: action)
            }
    }
}

extension View {
    func deleteWithConfirmation(_ question: LocalizedStringKey, actionLabel: LocalizedStringKey = "Delete", action: @escaping () -> Void) -> some View {
        modifier(DeleteWithConfirmation(question: question, actionLabel: actionLabel, action: action))
    }
}
