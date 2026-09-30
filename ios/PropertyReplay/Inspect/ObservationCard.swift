import PropertyModel
import SwiftUI

/// The tag-and-save card shown under the viewfinder right after a Capture or Note.
struct ObservationCard: View {
    @State var draft: ObservationDraft
    let rooms: [String]
    let onSave: (ObservationDraft) -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if let data = draft.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let text = draft.text {
                        Text(text).font(.callout).lineLimit(3)
                    } else {
                        Text("Photo · \(draft.room)").font(.callout)
                    }
                    if let summary = draft.summary { Text(summary).font(.footnote).foregroundStyle(.secondary) }
                    if let note = draft.modelNote { Text(note).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            HStack {
                Menu {
                    ForEach(rooms, id: \.self) { name in Button(name) { draft.room = name } }
                } label: { chip(draft.room, "door.left.hand.open") }
                Menu {
                    ForEach(ObservationCategory.allCases) { c in Button(c.displayName, systemImage: c.systemImage) { draft.category = c } }
                } label: { chip(draft.category.displayName, draft.category.systemImage) }
            }
            HStack(spacing: 8) {
                ForEach([Sentiment.like, .concern, .ask]) { s in
                    Button {
                        draft.sentiment = draft.sentiment == s ? .neutral : s
                    } label: {
                        Label(s.displayName, systemImage: s.systemImage)
                            .font(.footnote.weight(.medium))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(draft.sentiment == s ? Color.accentColor.opacity(0.2) : Color.clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(draft.sentiment == s ? Color.accentColor : .secondary.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Button("Discard", role: .destructive, action: onDiscard).font(.footnote)
                Spacer()
                Button("Save") { onSave(draft) }.buttonStyle(.borderedProminent).font(.footnote.weight(.semibold))
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func chip(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.footnote)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
    }
}
