import PropertyModel
import SwiftData
import SwiftUI

/// Inspect mode (ADR-0015): camera-style, three actions, no mode picker. Every capture becomes an InspectionObservation on
/// the property's open inspection; the card under the viewfinder lets the buyer tag it without leaving the screen.
struct InspectView: View {
    static let defaultRooms = ["Entry", "Living", "Kitchen", "Dining", "Bedroom 1", "Bedroom 2", "Bedroom 3", "Bathroom", "Study", "Balcony", "Backyard", "Garage"]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \UserPreferences.createdAt) private var preferencesRows: [UserPreferences]
    @Bindable var property: Property

    @StateObject private var camera = CameraService()
    @StateObject private var sensors = InspectSensors()
    @StateObject private var recorder = NoteRecorder()
    @State private var room = "Living"
    @State private var draft: ObservationDraft?
    @State private var flash = false
    @State private var busy = false
    @State private var message: String?
    @State private var confirmingExit = false
    @State private var scanningLight = false

    var body: some View {
        ZStack {
            viewfinder.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Spacer()
                if draft == nil && (recorder.state != .idle || !recorder.transcript.isEmpty) {
                    transcriptBubble
                }
                if let current = draft {
                    ObservationCard(draft: draftBinding(current), rooms: Self.defaultRooms, onSave: { _ = save() }, onDiscard: { draft = nil })
                        .id(current.id)
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
        .navigationBarBackButtonHidden(draft != nil || recorder.isRecording)   // leaving goes through Done, which asks (R04)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { Task { await requestFinish() } }
            }
        }
        .confirmationDialog(unsavedTitle, isPresented: $confirmingExit, titleVisibility: .visible) {
            Button("Save and finish") { if save() { finish() } }
            Button("Discard and finish", role: .destructive) { draft = nil; finish() }
            Button("Keep inspecting", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $scanningLight, onDismiss: { Task { await camera.start() } }) {
            LightScanView(property: property, roomLabel: room)
        }
        .onChange(of: scenePhase) { _, phase in
            // Never keep the microphone open in the background; what was said becomes a draft (R05).
            if phase == .background, recorder.isRecording { Task { await endNote() } }
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
                            // Simulator stand-ins for the camera and microphone so the UI tests walk the real draft paths.
                            Button("Add test photo (simulator)") { Task { await captureTestPhoto() } }.font(.footnote)
                            Button("Add test note (simulator)") { makeVoiceDraft("The living room felt darker than the listing photos") }.font(.footnote)
                                .disabled(draft != nil)
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
        case .preparing: return "Preparing on-device transcription\(recorder.activeLocaleName.map { " (\($0))" } ?? "")…"
        case .recording: return "Listening\(recorder.activeLocaleName.map { " (\($0))" } ?? "")…"
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
                Button {
                    camera.stop()   // ARKit needs the camera to itself
                    scanningLight = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "sun.max.fill").font(.title2).foregroundStyle(SunPathOverlay.sun)
                        Text("Light").font(.caption2)
                    }
                    .frame(width: 72)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(recorder.isRecording)
                .accessibilityLabel("Light")
                .accessibilityHint("Scan the sky to see where the sun passes")
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
                        recorder.preferredLanguage = preferencesRows.first?.noteLanguage
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

    /// Binds the card to the draft without force-unwrapping: SwiftUI reads the binding once more while the card is
    /// removed, after Save or Discard has set `draft` to nil (device crash 2026-09-30 21:24). Writes only land on the
    /// same draft.
    private func draftBinding(_ current: ObservationDraft) -> Binding<ObservationDraft> {
        Binding(get: { draft ?? current },
                set: { newValue in if draft?.id == newValue.id { draft = newValue } })
    }

    private func endNote() async {
        let text = await recorder.stop()
        if case .unavailable = recorder.state { return }   // the transcript bubble already shows the reason
        makeVoiceDraft(text)
    }

    private func makeVoiceDraft(_ text: String) {
        guard !text.isEmpty, draft == nil else { return }
        var newDraft = ObservationDraft(kind: .voice, room: room, text: text, sensors: sensors.snapshot)
        newDraft.modelNote = NoteStructurer.availabilityNote
        draft = newDraft
        // The suggestion arrives later and merges only into this same draft, never into a newer one (R03).
        let id = newDraft.id
        Task {
            guard let suggestion = await NoteStructurer.structure(transcript: text, rooms: Self.defaultRooms),
                  draft?.id == id else { return }
            draft?.apply(suggestion)
        }
    }

    /// Saves the draft on screen. Returns false and keeps the draft when anything fails.
    private func save() -> Bool {
        guard let draft else { return true }
        guard StoreHealth.shared.isPersistent else { message = "Storage problem: this note cannot be saved right now."; return false }
        let observation = InspectionObservation(kind: draft.kind, category: draft.category, sentiment: draft.sentiment,
                                                source: draft.kind == .photo ? .userPhoto : .userVoice,
                                                text: draft.text, roomLabel: draft.room)
        observation.summary = draft.summary
        observation.modelSuggested = draft.modelSuggested
        observation.photoData = draft.photoData
        observation.headingDeg = draft.sensors.headingDeg
        observation.headingAccuracyDeg = draft.sensors.headingAccuracyDeg
        observation.latitude = draft.sensors.latitude
        observation.longitude = draft.sensors.longitude
        do {
            try PropertyStore.record(observation, for: property, in: context)
        } catch {
            message = "Couldn't save: \(error.localizedDescription). Your draft is still here."
            return false
        }
        message = nil
        self.draft = nil
        return true
    }

    private var unsavedTitle: String {
        draft?.kind == .photo ? "This photo isn't saved yet." : "This note isn't saved yet."
    }

    /// Done: a note being dictated is finished first; anything unsaved gets an explicit choice (R04).
    private func requestFinish() async {
        if recorder.isRecording { await endNote() }
        if draft != nil { confirmingExit = true } else { finish() }
    }

    private func finish() {
        property.openInspection?.endedAt = Date()
        do {
            try PropertyStore.commit(context)
            dismiss()
        } catch {
            message = "Couldn't close the inspection: \(error.localizedDescription)"
        }
    }
}

/// What the card edits before an InspectionObservation exists. One value, owned by InspectView and bound into the card,
/// so what is on screen is what gets saved (R03). The buyer's choices always win over a late model suggestion.
struct ObservationDraft: Identifiable {
    enum Field: Hashable { case room, category, sentiment }

    let id = UUID()
    var kind: ObservationKind
    var text: String?
    var summary: String?
    var photoData: Data?
    var modelNote: String?
    var sensors: InspectSensors.Snapshot
    private(set) var room: String
    private(set) var category: ObservationCategory = .other
    private(set) var sentiment: Sentiment = .neutral
    /// Fields the buyer set; a suggestion never overwrites them.
    private(set) var setByBuyer: Set<Field> = []
    /// Fields that still hold the model's suggestion.
    private(set) var setByModel: Set<Field> = []

    init(kind: ObservationKind, room: String, text: String? = nil, photoData: Data? = nil, sensors: InspectSensors.Snapshot) {
        self.kind = kind
        self.room = room
        self.text = text
        self.photoData = photoData
        self.sensors = sensors
    }

    /// Stored as InspectionObservation.modelSuggested: some tag is still the model's, not the buyer's.
    var modelSuggested: Bool { !setByModel.isEmpty }

    mutating func setRoom(_ value: String) { room = value; buyerSet(.room) }
    mutating func setCategory(_ value: ObservationCategory) { category = value; buyerSet(.category) }
    mutating func setSentiment(_ value: Sentiment) { sentiment = value; buyerSet(.sentiment) }

    mutating func apply(_ suggestion: NoteStructurer.Suggestion) {
        if let suggested = suggestion.room, !setByBuyer.contains(.room) { room = suggested; setByModel.insert(.room) }
        if !setByBuyer.contains(.category) { category = suggestion.category; setByModel.insert(.category) }
        if !setByBuyer.contains(.sentiment) { sentiment = suggestion.sentiment; setByModel.insert(.sentiment) }
        summary = suggestion.summary
        modelNote = setByModel.isEmpty
            ? "Summary by the on-device model · Indicative"
            : "Suggested by the on-device model · Indicative until you confirm"
    }

    private mutating func buyerSet(_ field: Field) {
        setByBuyer.insert(field)
        setByModel.remove(field)
    }
}
