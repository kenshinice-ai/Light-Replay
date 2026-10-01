import PropertyModel
import SwiftData
import SwiftUI

/// Inspect mode (ADR-0015): camera-style, three actions, no mode picker. Every capture becomes an InspectionObservation on
/// the property's open inspection; a sheet over the viewfinder lets the buyer tag it without leaving the screen.
struct InspectView: View {
    static let defaultRooms = ["Entry", "Living", "Kitchen", "Dining", "Bedroom 1", "Bedroom 2", "Bedroom 3", "Bathroom", "Study", "Balcony", "Backyard", "Garage"]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \UserPreferences.createdAt) private var preferencesRows: [UserPreferences]
    @Bindable var property: Property

    @StateObject private var camera = CameraService()
    @StateObject private var sensors = InspectSensors()
    @StateObject private var recorder = NoteRecorder()
    @State private var room = "Living"
    @State private var draft: ObservationDraft?
    @State private var blink = false
    @State private var busy = false
    @State private var message: String?
    @State private var scanningLight = false
    /// Done was tapped while a note was being dictated: finish the inspection once that note is saved or discarded.
    @State private var finishAfterDraft = false
    @State private var captureCount = 0
    @State private var savedCount = 0

    var body: some View {
        ZStack {
            viewfinder
                .overlay { if blink { Color.black.opacity(0.65) } }   // shutter feedback stays inside the viewfinder (review U19)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                // Text that sits on the live picture stops growing at accessibility2 so the viewfinder stays
                // visible; the editor sheet scales all the way.
                header.dynamicTypeSize(...DynamicTypeSize.accessibility2)
                Spacer(minLength: 0)
                if draft == nil && recorder.state != .idle {
                    transcriptBubble.dynamicTypeSize(...DynamicTypeSize.accessibility2)
                }
                controls
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)   // camera-style: the three actions are the only controls (docs/14 §1)
        .navigationBarBackButtonHidden(recorder.isRecording)   // while dictating, leaving goes through Done
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { Task { await requestFinish() } }
            }
        }
        // The editor can only be left through Save or Discard, so nothing unsaved is dropped by leaving (R04).
        .sheet(item: $draft, onDismiss: draftDismissed) { current in
            DraftEditor(draft: draftBinding(current), rooms: Self.defaultRooms, errorMessage: message,
                        onSave: saveDraft, onDiscard: { message = nil; draft = nil })
                .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.fraction(0.62), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.thickMaterial)
                .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: $scanningLight, onDismiss: { Task { await camera.start() } }) {
            LightScanView(property: property, roomLabel: room)
        }
        .onChange(of: scenePhase) { _, phase in
            // Never keep the microphone open in the background; what was said becomes a draft (R05).
            if phase == .background, recorder.isRecording { Task { await endNote() } }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: captureCount)
        .sensoryFeedback(.success, trigger: savedCount)
        .sensoryFeedback(trigger: recorder.state) { old, new in
            if new == .recording { return .start }
            if old == .recording { return .stop }
            return nil
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
                CameraPreview(service: camera)
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
                        }
                        #endif
                    }
                    .padding()
                }
            }
        }
    }

    /// Address and room over the live picture, on material so they read against a bright window or a dark room
    /// (review U17). Side by side when they fit, stacked at large text sizes (review U01).
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                titleBlock
                Spacer(minLength: 0)
                roomMenu
            }
            VStack(alignment: .leading, spacing: 8) {
                titleBlock
                roomMenu
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(property.shortAddress).font(.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text("\(property.allObservations.count) recorded").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var roomMenu: some View {
        Menu {
            ForEach(Self.defaultRooms, id: \.self) { name in
                Button(name) { room = name }
            }
        } label: {
            Label(room, systemImage: "door.left.hand.open")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(.regularMaterial, in: Capsule())
        }
        .accessibilityLabel("Room")
        .accessibilityValue(room)
    }

    private var transcriptBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: recorder.state == .recording ? "waveform" : "text.quote")
                .foregroundStyle(recorder.state == .recording ? .red : .secondary)
            Text(bubbleText).font(.callout).lineLimit(6).truncationMode(.head)   // the newest words stay visible
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var bubbleText: String {
        let language = recorder.activeLocaleName.map { " (\($0))" } ?? ""
        switch recorder.state {
        case .unavailable(let why): return why
        case .preparing: return "Getting ready to listen\(language)… The microphone is not on yet."
        case .recording: return recorder.transcript.isEmpty ? "Listening\(language)…" : recorder.transcript
        case .finishing: return recorder.transcript.isEmpty ? "Finishing…" : recorder.transcript
        case .idle: return ""
        }
    }

    /// The three actions share the width equally. Like a tab bar, their captions stop growing at xxxLarge and offer
    /// the Large Content Viewer instead (press and hold shows them big); everything else on screen scales fully.
    private var controls: some View {
        VStack(spacing: 6) {
            if let message, draft == nil {
                Text(message).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center).padding(.horizontal)
            }
            HStack(alignment: .center, spacing: 0) {
                noteButton.frame(maxWidth: .infinity)
                shutter.frame(maxWidth: .infinity)
                lightButton.frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .background(.bar)
    }

    /// Push-to-talk (ADR-0015). Touch: hold to speak, release to finish. VoiceOver, Switch Control and the keyboard
    /// (⌘D) cannot hold, so for them one activation starts and the next finishes (review U05). `.startsMediaSession`
    /// keeps VoiceOver from speaking into the note.
    private var noteButton: some View {
        VStack(spacing: 4) {
            Image(systemName: recorder.state == .recording ? "mic.fill" : "mic").font(.title2)
                .foregroundStyle(recorder.state == .recording ? Color.red : (recorder.state == .preparing ? Color.secondary : Color.primary))
            Text(noteCaption).font(.caption2).multilineTextAlignment(.center).lineLimit(2)
        }
        .frame(minWidth: 72, minHeight: 56)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginNote() }
                .onEnded { _ in Task { await endNote() } }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dictate note")
        .accessibilityValue(noteCaption)
        .accessibilityHint("Hold to speak and release to finish. With VoiceOver, double tap to start and double tap again to finish.")
        .accessibilityAddTraits([.isButton, .startsMediaSession])
        .accessibilityAction { toggleNote() }
        .background {
            Button("Dictate note", action: toggleNote).keyboardShortcut("d", modifiers: .command).opacity(0).accessibilityHidden(true)
        }
    }

    private var noteCaption: String {
        switch recorder.state {
        case .preparing: "Getting ready"
        case .recording: "Release to finish"
        case .finishing: "Finishing"
        default: "Hold to note"
        }
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
        .buttonStyle(PressScaleStyle(scale: 0.94))
        .disabled(!camera.isAvailable || busy || recorder.isRecording)
        .accessibilityLabel("Capture")
        .accessibilityShowsLargeContentViewer { Label("Capture", systemImage: "camera") }
        .keyboardShortcut(.return, modifiers: .command)
    }

    private var lightButton: some View {
        Button {
            camera.stop()   // ARKit needs the camera to itself
            scanningLight = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "sun.max.fill").font(.title2).foregroundStyle(SunPathOverlay.sun)
                Text("Light").font(.caption2)
            }
            .frame(minWidth: 72, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(recorder.isRecording)
        .accessibilityLabel("Light")
        .accessibilityHint("Scan the sky to see where the sun passes")
        .accessibilityShowsLargeContentViewer { Label("Light", systemImage: "sun.max.fill") }
    }

    // MARK: - Actions

    private func capture() async {
        busy = true
        defer { busy = false }
        do {
            guard let data = try await camera.capturePhoto() else { message = "No photo captured."; return }
            captureCount += 1
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.05)) { blink = true }
                try? await Task.sleep(for: .milliseconds(90))
                withAnimation(.easeOut(duration: 0.12)) { blink = false }
            }
            message = nil
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
        captureCount += 1
        draft = ObservationDraft(kind: .photo, room: room, photoData: image.jpegData(compressionQuality: 0.8), sensors: sensors.snapshot)
    }
    #endif

    /// Binds the editor to the draft without force-unwrapping: SwiftUI reads the binding once more while the editor is
    /// removed, after Save or Discard has set `draft` to nil (device crash 2026-09-30 21:24). Writes only land on the
    /// same draft.
    private func draftBinding(_ current: ObservationDraft) -> Binding<ObservationDraft> {
        Binding(get: { draft ?? current },
                set: { newValue in if draft?.id == newValue.id { draft = newValue } })
    }

    private func beginNote() {
        guard !recorder.isRecording, recorder.state != .finishing, draft == nil else { return }
        recorder.preferredLanguage = preferencesRows.first?.noteLanguage
        Task { await recorder.start() }
    }

    /// The accessible and keyboard path: one activation starts, the next finishes.
    private func toggleNote() {
        if recorder.isRecording { Task { await endNote() } } else { beginNote() }
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
        message = nil
        draft = newDraft
        // The suggestion arrives later and merges only into this same draft, never into a newer one (R03).
        let id = newDraft.id
        Task {
            guard let suggestion = await NoteStructurer.structure(transcript: text, rooms: Self.defaultRooms),
                  draft?.id == id else { return }
            draft?.apply(suggestion)
        }
    }

    private func saveDraft() {
        if save() { savedCount += 1 }
    }

    /// Saves the draft on screen. Returns false and keeps the draft when anything fails.
    private func save() -> Bool {
        guard let draft else { return true }
        guard StoreHealth.shared.isPersistent else { message = "Storage problem: this can't be saved right now."; return false }
        let words = draft.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (words?.isEmpty ?? true) ? draft.transcript : words   // a note is never saved empty
        let observation = InspectionObservation(kind: draft.kind, category: draft.category, sentiment: draft.sentiment,
                                                source: draft.kind == .photo ? .userPhoto : .userVoice,
                                                text: text, roomLabel: draft.room)
        if let transcript = draft.transcript, text != transcript { observation.originalText = transcript }
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

    /// Runs after the editor has gone, whichever way it was left.
    private func draftDismissed() {
        guard finishAfterDraft else { return }
        finishAfterDraft = false
        finish()
    }

    /// Done: a note being dictated is finished first and gets its editor; the inspection closes after that.
    private func requestFinish() async {
        guard recorder.isRecording else { finish(); return }
        await endNote()
        if draft == nil { finish() } else { finishAfterDraft = true }
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

/// What the editor edits before an InspectionObservation exists. One value, owned by InspectView and bound into the
/// editor, so what is on screen is what gets saved (R03). The buyer's choices always win over a late model suggestion.
struct ObservationDraft: Identifiable {
    enum Field: Hashable { case room, category, sentiment }

    let id = UUID()
    var kind: ObservationKind
    /// The buyer's words, editable in the editor.
    var text: String?
    /// The raw transcript of a voice note, kept as `originalText` when the buyer corrects it.
    let transcript: String?
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
        self.transcript = kind == .voice ? text : nil
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
