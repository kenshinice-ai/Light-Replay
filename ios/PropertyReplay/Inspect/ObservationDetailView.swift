import PropertyModel
import SwiftData
import SwiftUI

/// One recorded thing, read properly at home (review U04): the photo large and zoomable, the words in full and
/// correctable with the first version kept, tags editable, and where it came from. Nothing here raises its evidence
/// level; a corrected transcript is still the buyer's own note (ADR-0013).
struct ObservationDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var observation: InspectionObservation

    @State private var words = ""
    @State private var showingPhoto = false
    @State private var showingOriginal = false
    @State private var confirmingDelete = false
    @State private var saveError: String?
    /// Set just before deleting: the page stops reading the model, which must not be touched once it is gone.
    @State private var deleted = false
    @FocusState private var editingWords: Bool

    private var image: UIImage? { observation.photoData.flatMap(UIImage.init(data:)) }

    var body: some View {
        if deleted {
            Color.clear
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let image { photo(image) }
                if observation.kind != .light || observation.text != nil { wordsSection }
                if observation.kind != .light { tagsSection }
                detailsSection
                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red)
                }
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label("Delete", systemImage: "trash").frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if editingWords {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { commitWords() } }
            }
        }
        .onAppear { words = observation.text ?? "" }
        .onDisappear { commitWords() }
        .fullScreenCover(isPresented: $showingPhoto) {
            if let image { PhotoViewer(image: image) }
        }
        .confirmationDialog("Delete this from the inspection?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                editingWords = false
                deleted = true
                do { try PropertyStore.delete(observation, in: context) } catch {
                    StoreHealth.shared.note("Deleting didn't finish saving (\(error.localizedDescription)); it completes with the next save.")
                }
                dismiss()
            }
        }
    }

    private var title: String {
        switch observation.kind {
        case .photo: "Photo"
        case .voice: "Note"
        case .tag: observation.sentiment.displayName
        case .light: "Light scan"
        }
    }

    private func photo(_ image: UIImage) -> some View {
        Button { showingPhoto = true } label: {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 460)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityLabel("Photo\(observation.roomLabel.map { ", \($0)" } ?? "")")
        .accessibilityHint("Opens the photo full screen to zoom")
    }

    /// The buyer's words. Light scans show their status line read-only.
    private var wordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(observation.kind == .photo ? "Caption" : (observation.kind == .light ? "Status" : "What you said"))
                .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            if observation.kind == .light {
                Text(observation.text ?? "").font(.body).textSelection(.enabled)
            } else {
                TextField(observation.kind == .photo ? "Add a caption" : "Your note", text: $words, axis: .vertical)
                    .lineLimit(1...40)
                    .focused($editingWords)
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(observation.kind == .photo ? "Caption" : "Your note")
            }
            if let original = observation.originalText {
                DisclosureGroup(isExpanded: $showingOriginal) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(original).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Use the original again") {
                            words = original
                            commitWords()
                        }
                        .font(.footnote.weight(.semibold))
                    }
                    .padding(.top, 4)
                } label: {
                    Text("You corrected this. The first version is kept.").font(.footnote).foregroundStyle(Color(.secondaryLabel))
                }
                .tint(Color(.secondaryLabel))
            }
            if let summary = observation.summary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Summary by the on-device model · Indicative").font(.caption).foregroundStyle(.secondary)
                    Text(summary).font(.callout)
                }
                .padding(.top, 2)
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            TagControls(rooms: InspectView.defaultRooms, room: observation.roomLabel, category: observation.category,
                        sentiment: observation.sentiment,
                        setRoom: { observation.roomLabel = $0; tagsReviewed() },
                        setCategory: { observation.category = $0; tagsReviewed() },
                        setSentiment: { observation.sentiment = $0; tagsReviewed() })
            if observation.modelSuggested {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("These tags were suggested by the on-device model.").font(.footnote).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button("They're right") { tagsReviewed() }.font(.footnote.weight(.semibold))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("These tags were suggested by the on-device model.").font(.footnote).foregroundStyle(.secondary)
                        Button("They're right") { tagsReviewed() }.font(.footnote.weight(.semibold))
                    }
                }
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Details").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            VStack(spacing: 10) {
                AdaptiveRow(title: "Recorded", value: observation.capturedAt.formatted(date: .abbreviated, time: .shortened))
                if let property = observation.inspection?.property {
                    AdaptiveRow(title: "Property", value: property.shortAddress)
                }
                AdaptiveRow(title: "How we know", value: evidenceText)
                if let heading = observation.headingDeg {
                    AdaptiveRow(title: "Facing", value: Self.compassText(heading, accuracy: observation.headingAccuracyDeg))
                }
            }
            .font(.callout)
        }
    }

    /// Plain words for the evidence level and source (ADR-0013 levels; consumer wording per review U24).
    private var evidenceText: String {
        switch (observation.kind, observation.level) {
        case (.photo, _): "You photographed this on site"
        case (.voice, _): observation.originalText == nil ? "You said this on site" : "You said this on site, then corrected the words"
        case (.tag, _): "You marked this on site"
        case (.light, .observedMeasured): "Measured on site, passed the quality checks"
        case (.light, _): "Recorded on site. Sunlight not calculated yet"
        }
    }

    static func compassText(_ degrees: Double, accuracy: Double?) -> String {
        let names = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
        let name = names[Int((degrees + 22.5).truncatingRemainder(dividingBy: 360) / 45) % 8]
        guard let accuracy, accuracy >= 0 else { return name.capitalized }
        return "\(name.capitalized), compass within about \(Int(accuracy.rounded()))°"
    }

    // MARK: - Edits

    private func commitWords() {
        guard !deleted else { return }
        editingWords = false
        guard observation.kind != .light else { return }
        observation.correctText(to: words)
        words = observation.text ?? ""
        save()
    }

    /// The buyer has looked at the tags (changed one or said they are right), so they are no longer the model's.
    private func tagsReviewed() {
        observation.modelSuggested = false
        save()
    }

    private func save() {
        guard context.hasChanges else { return }
        do {
            try PropertyStore.commit(context)
            saveError = nil
        } catch {
            saveError = "Couldn't save this change yet: \(error.localizedDescription)"
        }
    }
}
