import PropertyModel
import SwiftData
import SwiftUI

/// Inspect mode (ADR-0015): camera-style, three actions, no mode picker. Every capture becomes an InspectionObservation on
/// the property's open inspection; the card under the viewfinder lets the buyer tag it without leaving the screen.
struct InspectView: View {
    static let defaultRooms = ["Entry", "Living", "Kitchen", "Dining", "Bedroom 1", "Bedroom 2", "Bedroom 3", "Bathroom", "Study", "Balcony", "Backyard", "Garage"]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var preferencesRows: [UserPreferences]
    @Bindable var property: Property

    @StateObject private var camera = CameraService()
    @StateObject private var sensors = InspectSensors()
    @StateObject private var recorder = NoteRecorder()
    @State private var room = "Living"
    @State private var draft: ObservationDraft?
    @State private var flash = false
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        ZStack {
            viewfinder.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Spacer()
                if draft == nil && (recorder.state != .idle || !recorder.transcript.isEmpty) {
                    transcriptBubble
                }
                if let draft {
                    ObservationCard(draft: draft, rooms: Self.defaultRooms, onSave: save, onDiscard: { self.draft = nil })
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                controls
            }
            if flash { Color.white.ignoresSafeArea().transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.2), value: draft != nil)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)   // camera-style: the three actions are the only controls (docs/14 §1)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { finish() }
            }
        }
        .task {
            sensors.start()
            await camera.start()
        }
        .onDisappear {
            camera.stop()
            sensors.stop()
            Task { _ = await recorder.stop() }
        }
    }

    // MARK: - Pieces

    private var viewfinder: some View {
        Group {
            if camera.isRunning {
                CameraPreview(session: camera.session)
            } else {
                ZStack {
                    Color(.systemGray6)
                    VStack(spacing: 8) {
                        Image(systemName: "camera").font(.largeTitle).foregroundStyle(.secondary)
                        Text(camera.lastError ?? "Starting camera…").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        #if DEBUG
                        if !camera.isAvailable {
                            Button("Add test photo (simulator)") { Task { await captureTestPhoto() } }.font(.footnote)
                        }
                        #endif
                    }
                    .padding()
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(property.shortAddress).font(.headline)
                Text("\(property.allObservations.count) recorded").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(Self.defaultRooms, id: \.self) { name in
                    Button(name) { room = name }
                }
            } label: {
                Label(room, systemImage: "door.left.hand.open").font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var transcriptBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: recorder.isRecording ? "waveform" : "text.quote").foregroundStyle(recorder.isRecording ? .red : .secondary)
            Text(bubbleText).font(.callout)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var bubbleText: String {
        if !recorder.transcript.isEmpty { return recorder.transcript }
        switch recorder.state {
        case .preparing: return "Preparing on-device transcription…"
        case .recording: return "Listening…"
        case .finishing: return "Finishing…"
        case .unavailable(let why): return why
        case .idle: return ""
        }
    }

    private var controls: some View {
        VStack(spacing: 6) {
            if let message {
                Text(message).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center).padding(.horizontal)
            }
            HStack(alignment: .center) {
                noteButton
                Spacer()
                shutter
                Spacer()
                NavigationLink { CaptureValidatorView(property: property, roomLabel: room) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "sun.max.fill").font(.title2)
                        Text("Measure").font(.caption2)
                    }
                    .frame(width: 72)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
        }
        .background(.bar)
    }

    private var noteButton: some View {
        VStack(spacing: 4) {
            Image(systemName: recorder.isRecording ? "mic.fill" : "mic").font(.title2)
                .foregroundStyle(recorder.isRecording ? .red : .primary)
            Text(recorder.isRecording ? "Release" : "Hold to note").font(.caption2)
        }
        .frame(width: 72)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !recorder.isRecording && draft == nil {
                        recorder.locale = preferencesRows.first?.noteLocale ?? .current
                        Task { await recorder.start() }
                    }
                }
                .onEnded { _ in Task { await endNote() } }
        )
        .disabled(draft != nil)
    }

    private var shutter: some View {
        Button {
            Task { await capture() }
        } label: {
            ZStack {
                Circle().strokeBorder(.primary, lineWidth: 4).frame(width: 74, height: 74)
                Circle().fill(.primary).frame(width: 60, height: 60)
            }
        }
        .buttonStyle(.plain)
        .disabled(!camera.isAvailable || busy || draft != nil)
        .accessibilityLabel("Capture")
    }

    // MARK: - Actions

    private func capture() async {
        busy = true
        defer { busy = false }
        do {
            guard let data = try await camera.capturePhoto() else { message = "No photo captured."; return }
            withAnimation(.easeOut(duration: 0.08)) { flash = true }
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation { flash = false }
            draft = ObservationDraft(kind: .photo, room: room, photoData: PhotoScaler.jpeg(data), sensors: sensors.snapshot)
        } catch {
            message = "Capture failed: \(error.localizedDescription)"
        }
    }

    #if DEBUG
    private func captureTestPhoto() async {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1000))
        let image = renderer.image { ctx in
            UIColor.systemTeal.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 1000))
            let text = "Test photo (simulator)" as NSString
            text.draw(at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 40), .foregroundColor: UIColor.white])
        }
        draft = ObservationDraft(kind: .photo, room: room, photoData: image.jpegData(compressionQuality: 0.8), sensors: sensors.snapshot)
    }
    #endif

    private func endNote() async {
        let text = await recorder.stop()
        if case .unavailable = recorder.state { return }   // the transcript bubble already shows the reason
        guard !text.isEmpty else { return }
        var newDraft = ObservationDraft(kind: .voice, room: room, text: text, sensors: sensors.snapshot)
        newDraft.modelNote = NoteStructurer.availabilityNote
        draft = newDraft
        if let suggestion = await NoteStructurer.structure(transcript: text, rooms: Self.defaultRooms) {
            draft?.apply(suggestion)
        }
    }

    private func save(_ draft: ObservationDraft) {
        guard StoreHealth.shared.isPersistent else { message = "Storage problem: this note cannot be saved right now."; return }
        let inspection = PropertyStore.openInspection(for: property, in: context)
        let observation = InspectionObservation(kind: draft.kind, category: draft.category, sentiment: draft.sentiment,
                                      source: draft.kind == .photo ? .userPhoto : .userVoice,
                                      text: draft.text, roomLabel: draft.room)
        observation.summary = draft.summary
        observation.modelSuggested = draft.modelSuggested
        observation.headingDeg = draft.sensors.headingDeg
        observation.headingAccuracyDeg = draft.sensors.headingAccuracyDeg
        observation.latitude = draft.sensors.latitude
        observation.longitude = draft.sensors.longitude
        do {
            if let data = draft.photoData {
                observation.mediaPath = try MediaStore.saveJPEG(data, for: observation.uuid)
            }
            observation.inspection = inspection
            inspection.observations.append(observation)
            context.insert(observation)
            if property.status == .toInspect { property.status = .inspected }
            try context.save()
        } catch {
            MediaStore.delete(observation.mediaPath)
            context.rollback()
            message = "Couldn't save: \(error.localizedDescription). Your draft is still here."
            return
        }
        message = nil
        self.draft = nil
    }

    private func finish() {
        property.openInspection?.endedAt = Date()
        do {
            try context.save()
            dismiss()
        } catch {
            message = "Couldn't close the inspection: \(error.localizedDescription)"
        }
    }
}

/// What the card edits before an InspectionObservation exists.
struct ObservationDraft {
    var kind: ObservationKind
    var room: String
    var text: String?
    var summary: String?
    var photoData: Data?
    var category: ObservationCategory = .other
    var sentiment: Sentiment = .neutral
    var modelSuggested = false
    var modelNote: String?
    var sensors: InspectSensors.Snapshot

    init(kind: ObservationKind, room: String, text: String? = nil, photoData: Data? = nil, sensors: InspectSensors.Snapshot) {
        self.kind = kind
        self.room = room
        self.text = text
        self.photoData = photoData
        self.sensors = sensors
    }

    mutating func apply(_ suggestion: NoteStructurer.Suggestion) {
        if let room = suggestion.room { self.room = room }
        category = suggestion.category
        sentiment = suggestion.sentiment
        summary = suggestion.summary
        modelSuggested = true
        modelNote = "Suggested by the on-device model · Indicative until you confirm"
    }
}
