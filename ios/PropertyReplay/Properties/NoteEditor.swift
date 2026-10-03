import PropertyModel
import SwiftData
import SwiftUI

/// A note written away from the home: a fact or a judgment the camera cannot catch, such as the school zone, the
/// commute, or how the price sits (Lee, 2026-10-03). It is the buyer's own record, Observed · noted, and Compare
/// counts it like a note said on site. It hangs off the property, so writing one is not a visit.
struct NoteEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let property: Property
    @State private var text = ""
    @State private var category: ObservationCategory
    @State private var sentiment: Sentiment = .neutral
    @State private var saveError: String?
    @FocusState private var writing: Bool

    init(property: Property, category: ObservationCategory?) {
        self.property = property
        _category = State(initialValue: category ?? .other)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("What do you want to remember?", text: $text, axis: .vertical)
                        .lineLimit(3...12)
                        .focused($writing)
                        .padding(12)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Your note")
                    TagControls(rooms: [], room: nil, category: category, sentiment: sentiment,
                                setRoom: { _ in }, setCategory: { category = $0 }, setSentiment: { sentiment = $0 })
                    if let saveError {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Color.problemText)
                    }
                    Text("Kept with \(property.shortAddress) as your own note, and counted in Compare under \(category.displayName).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add a note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmed.isEmpty || !StoreHealth.shared.isPersistent)
                        .keyboardShortcut(.return, modifiers: .command)   // Return alone makes a new line
                }
            }
            .task { writing = true }   // the one thing this sheet is for
        }
    }

    private func save() {
        let note = InspectionObservation(kind: .note, category: category, sentiment: sentiment, source: .userText, text: trimmed)
        do {
            try PropertyStore.addNote(note, to: property, in: context)
            dismiss()
        } catch {
            saveError = String(localized: "Couldn't save: \(error.localizedDescription). Your note is still here.")
        }
    }
}
