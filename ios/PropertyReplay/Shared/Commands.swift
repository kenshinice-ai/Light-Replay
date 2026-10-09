import SwiftUI

extension FocusedValues {
    /// Starts or finishes dictating a note on the Inspect screen in front; nil when no Inspect screen is in front.
    @Entry var dictateNote: (() -> Void)?
}

/// App-wide keyboard shortcuts as scene commands. They appear in the iPad menu bar and in the list a held Command
/// key shows, and add nothing to the accessibility tree. A shortcut parked on an invisible button stays a button for
/// VoiceOver and for tests (group memory swiftui-keyboard-shortcuts-as-commands); shortcuts that belong to a visible
/// control (⌘↩ on the shutter, ⌘N on Add) stay on that control.
struct InspectCommands: Commands {
    @FocusedValue(\.dictateNote) private var dictateNote

    var body: some Commands {
        CommandMenu("Inspect") {
            Button("Dictate note") { dictateNote?() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(dictateNote == nil)
        }
    }
}
