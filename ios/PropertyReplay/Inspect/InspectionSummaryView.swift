import PropertyModel
import SwiftData
import SwiftUI

/// After: memory, not report (docs/01 §5). Grouped by what the buyer tagged; everything else under Notes.
struct InspectionSummaryView: View {
    @Environment(\.modelContext) private var context
    let property: Property

    private var observations: [InspectionObservation] { property.allObservations }

    var body: some View {
        List {
            group("You liked", .like, "hand.thumbsup")
            group("You were unsure about", .concern, "exclamationmark.triangle")
            group("Ask next", .ask, "questionmark.circle")
            group("Notes", .neutral, "note.text")
            if observations.isEmpty {
                ContentUnavailableView("Nothing recorded yet", systemImage: "camera", description: Text("Use Inspect when you are at the property."))
            }
        }
        .navigationTitle("Your inspection")
    }

    @ViewBuilder
    private func group(_ title: String, _ sentiment: Sentiment, _ symbol: String) -> some View {
        let items = observations.filter { $0.sentiment == sentiment }
        if !items.isEmpty {
            Section {
                ForEach(items) { ObservationRow(observation: $0) }
                    .onDelete { offsets in
                        for index in offsets { try? PropertyStore.delete(items[index], in: context) }
                    }
            } header: {
                Label(title, systemImage: symbol)
            }
        }
    }
}

struct ObservationRow: View {
    let observation: InspectionObservation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let path = observation.mediaPath, let image = UIImage(contentsOfFile: MediaStore.url(for: path).path) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: observation.kind == .voice ? "waveform" : observation.category.systemImage)
                    .frame(width: 56, height: 56).background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(observation.headline).font(.body).lineLimit(3)
                HStack(spacing: 6) {
                    if let room = observation.roomLabel { Text(room) }
                    Text("· \(observation.category.displayName)")
                    Text("· \(observation.level.displayName)")
                    if observation.modelSuggested { Text("· model-suggested") }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(observation.capturedAt, format: .dateTime.weekday(.abbreviated).hour().minute()).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
