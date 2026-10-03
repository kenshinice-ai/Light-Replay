import PropertyModel
import SwiftData
import SwiftUI

/// After: memory, not report (docs/01 §5). Grouped by what the buyer tagged; everything else under Notes.
struct InspectionSummaryView: View {
    @Environment(\.modelContext) private var context
    let property: Property
    @State private var deleteError: String?

    private var observations: [InspectionObservation] { property.allObservations }

    var body: some View {
        List {
            group("You liked", .like, "hand.thumbsup")
            group("You were unsure about", .concern, "exclamationmark.triangle")
            group("You want to confirm", .ask, "questionmark.circle")
            group("Notes", .neutral, "note.text")
            if observations.isEmpty {
                ContentUnavailableView("Nothing recorded yet", systemImage: "camera", description: Text("Use Inspect when you are at the property."))
            }
        }
        .navigationTitle("Your inspection")
        .alert("Couldn't delete", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(deleteError ?? "") }
    }

    @ViewBuilder
    private func group(_ title: LocalizedStringKey, _ sentiment: Sentiment, _ symbol: String) -> some View {
        let items = observations.filter { $0.sentiment == sentiment }
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    NavigationLink { ObservationDetailView(observation: item) } label: { ObservationRow(observation: item) }
                        .deleteWithConfirmation("Delete this \(Self.name(item.kind))?") {
                            do { try PropertyStore.delete(item, in: context) } catch {
                                deleteError = String(localized: "\(error.localizedDescription) It is hidden now and will be removed the next time the library saves.")
                            }
                        }
                }
            } header: {
                Label(title, systemImage: symbol)
            }
        }
    }
}

extension InspectionSummaryView {
    static func name(_ kind: ObservationKind) -> String {
        switch kind {
        case .photo: String(localized: "photo")
        case .voice, .note: String(localized: "note")
        case .tag: String(localized: "tag")
        case .light: String(localized: "light scan")
        }
    }
}

struct ObservationRow: View {
    let observation: InspectionObservation

    private var thumbnail: UIImage? {
        observation.photoData.flatMap(UIImage.init(data:))?.preparingThumbnail(of: CGSize(width: 168, height: 168))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let image = thumbnail {
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
