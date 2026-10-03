import PropertyModel
import SwiftUI

/// The tag-and-save panel shown right after a Capture or a Note, as a system sheet over the viewfinder. A sheet
/// scrolls at any text size, avoids the keyboard, and becomes a centred panel on iPad (review U01, U20). It can only
/// be left through Save or Discard, so an unsaved draft is never dropped by accident (reaudit R04).
struct DraftEditor: View {
    @Binding var draft: ObservationDraft
    let rooms: [String]
    let errorMessage: String?
    let onSave: () -> Void
    let onDiscard: () -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// iPhone on its side: the sheet is about 300 pt tall, so a photo stacked above the tags pushed them off screen
    /// (Lee, 2026-10-03). Photo beside the tags there; stacked everywhere else and at accessibility text sizes.
    private var sideBySide: Bool { verticalSizeClass == .compact && !dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if sideBySide, let image = photo {
                        HStack(alignment: .top, spacing: 20) {
                            photoView(image).frame(maxWidth: 240, maxHeight: 180)
                            fields
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            if let image = photo { photoView(image).frame(maxHeight: 220).frame(maxWidth: .infinity) }
                            fields
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: sideBySide ? .infinity : 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(draft.kind == .photo ? String(localized: "Photo") : String(localized: "Note"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { actions }
        }
    }

    private var photo: UIImage? { draft.photoData.flatMap(UIImage.init(data:)) }

    private func photoView(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityLabel("The photo you just took")
    }

    /// Everything that is not the photo: the words, the tags, and a save error when there is one.
    private var fields: some View {
        VStack(alignment: .leading, spacing: 18) {
            if draft.kind == .voice { words }
            TagControls(rooms: rooms, room: draft.room, category: draft.category, sentiment: draft.sentiment,
                        setRoom: { draft.setRoom($0) }, setCategory: { draft.setCategory($0) },
                        setSentiment: { draft.setSentiment($0) })
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(Color.problemText)
            }
        }
    }

    /// The transcript, editable in place; the first version is kept when it is saved.
    private var words: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What you said").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            TextField("Your note", text: Binding(get: { draft.text ?? "" }, set: { draft.text = $0 }), axis: .vertical)
                .lineLimit(1...12)
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Your note")
            if let summary = draft.summary {
                Text(summary).font(.footnote).foregroundStyle(.secondary)
            }
            if let note = draft.modelNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                discardButton
                saveButton
            }
            VStack(spacing: 10) {
                saveButton
                discardButton
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var saveButton: some View {
        Button(action: onSave) {
            Text("Save").font(.headline).frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var discardButton: some View {
        Button(role: .destructive, action: onDiscard) {
            Text("Discard").frame(minHeight: 28)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}
