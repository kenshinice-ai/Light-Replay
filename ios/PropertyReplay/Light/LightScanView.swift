import CaptureCore
import PropertyModel
import SunEngine
import SwiftData
import SwiftUI

/// The Light scan screen (docs/04 §11): full-screen camera, the sun path for the chosen question drawn into it, one
/// instruction at a time, a coverage ring and one primary button. Every part re-flows at large text sizes instead of
/// truncating (review U02), and the wording keeps "the camera covered this" apart from "sunlight" (review U06).
struct LightScanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Where the top bar and legend end on screen; the overlay keeps the paths' names out from under them.
    @State private var topControlsBottom: CGFloat = 0
    @Query(sort: \UserPreferences.createdAt) private var preferencesRows: [UserPreferences]
    @AppStorage("lightScanQuestion") private var questionRaw = LightQuestion.winter.rawValue
    @State private var model: LightScanModel
    @State private var confirmingDiscard = false
    @State private var confirmingLowCoverage = false

    init(property: Property?, roomLabel: String?) {
        _model = State(initialValue: LightScanModel(property: property, roomLabel: roomLabel))
    }

    private var isLive: Bool { model.phase == .ready || model.phase == .scanning }
    /// You › Preferences › Haptics. Every haptic here has a visible twin (the dot, the ring, the result sheet).
    private var haptics: Bool { preferencesRows.first?.hapticsEnabled ?? true }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                ZStack {
                    camera
                    SunPathOverlay(state: model.overlay, topClear: topControlsBottom)
                }
                // Words drawn over the live picture stop growing where the controls over it do (review LS03).
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .onAppear { model.viewSize = geo.size }
                .onChange(of: geo.size) { _, size in model.viewSize = size }
            }
            .ignoresSafeArea()

            if case .unsupported(let reason) = model.phase {
                unsupported(reason)
            } else {
                if isLive { reticle }
                VStack(spacing: 12) {
                    VStack(spacing: 12) {
                        topBar
                        if model.phase == .ready { legend }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { topControlsBottom = $0 }
                    Spacer(minLength: 0)
                    if isLive { promptView }
                    if isLive || model.phase == .saving { bottomBar }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                // Controls that sit on the live picture stop growing at accessibility2 so the camera stays visible,
                // as the system Camera's do; the result sheet and every editor scale all the way (review U02).
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1), value: model.phase)
        .background(Color.black)
        .background(InterfaceOrientationReader { model.interfaceOrientation = $0 })   // the compass follows the screen
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task {
            model.toleranceM = preferencesRows.first?.viewpointToleranceM ?? 0.15
            model.targetHeightM = preferencesRows.first?.targetHeightM
            model.question = LightQuestion(rawValue: questionRaw) ?? .winter
            UIApplication.shared.isIdleTimerDisabled = true
            model.appear()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            model.disappear()
        }
        .onChange(of: model.question) { _, question in questionRaw = question.rawValue }
        .sensoryFeedback(.impact(weight: .light), trigger: model.anchorLocked) { _, locked in locked && haptics }
        .sensoryFeedback(.success, trigger: model.reachedTarget) { _, reached in reached && haptics }
        .sensoryFeedback(trigger: model.phase) { _, phase in
            guard haptics, case .saved(let result) = phase else { return nil }
            return result.failure == nil ? .success : .error
        }
        // The result is a system sheet: it scrolls at any text size and reads on a steady surface (review U02, U17).
        .sheet(item: Binding(get: { if case .saved(let result) = model.phase { result } else { nil } }, set: { _ in })) { result in
            LightResultSheet(result: result,
                             onRetrySave: { model.retrySave(in: context) },
                             onRetryAttach: { model.retryAttach(in: context) },
                             onScanAgain: { model.scanAgain() },
                             onDone: { dismiss() })
                .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.thickMaterial)   // long text reads on a steady surface, not on the camera (review U17)
                .interactiveDismissDisabled()
        }
        .alert("The camera covered only \(Int((model.coverage * 100).rounded()))% of the \(model.question.localizedName) path",
               isPresented: $confirmingLowCoverage) {
            Button("Save anyway") { model.save(in: context) }
            Button("Keep scanning", role: .cancel) {}
        } message: {
            Text("The parts the camera didn't cover will stay unknown.")
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var camera: some View {
        if let session = model.arSession {
            ARCameraView(session: session) { model.arView = $0 }
        } else {
            #if DEBUG
            if model.isSimulated { SimulatedSky(state: model.overlay) } else { Color.black }
            #else
            Color.black
            #endif
        }
    }

    /// One row when it fits; at large text sizes the question gets a row of its own.
    private var topBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                closeButton
                Spacer(minLength: 0)
                questionMenu
                Spacer(minLength: 0)
                directionChip
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    closeButton
                    Spacer(minLength: 0)
                    directionChip
                }
                questionMenu
            }
        }
        .padding(.top, 4)
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Close")
        // Attached to the button that asks.
        .confirmationDialog("Discard this scan?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                model.discard()
                dismiss()
            }
            Button("Keep scanning", role: .cancel) {}
        }
    }

    private var questionMenu: some View {
        Menu {
            Picker("Question", selection: Bindable(model).question) {
                ForEach(LightQuestion.allCases) { Text($0.localizedTitle).tag($0) }
            }
        } label: {
            HStack(spacing: 5) {
                Text(model.question.localizedTitle).font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .glassEffect(in: RoundedRectangle(cornerRadius: 22))
        }
        .disabled(model.phase == .saving)
        .accessibilityLabel("Question")
        .accessibilityValue(model.question.localizedTitle)
    }

    private var directionChip: some View {
        Label(model.directionText, systemImage: "location.north.line")
            .font(.caption.weight(.medium))
            .labelStyle(.titleAndIcon)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 36)
            .glassEffect(in: RoundedRectangle(cornerRadius: 18))
            .accessibilityLabel("Direction: \(model.directionText)")
    }

    /// What the two line styles mean, before the scan starts (review U06). Shape differs as well as colour.
    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { legendCovered; legendNotYet }
            VStack(alignment: .leading, spacing: 6) { legendCovered; legendNotYet }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("On the sun path, a solid line is where the camera has looked, a dashed line is where it hasn't yet.")
    }

    private var legendCovered: some View {
        HStack(spacing: 6) {
            Capsule().fill(SunPathOverlay.sun).frame(width: 22, height: 4)
            Text("Camera has looked here").fixedSize(horizontal: false, vertical: true)
        }
    }

    private var legendNotYet: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Capsule().fill(.primary.opacity(0.8)).frame(width: 5, height: 3) } }
                .frame(width: 22)
            Text("Not yet")
        }
    }

    /// The viewpoint circle: the dot is the lens relative to where the scan started (docs/04 §8).
    private var reticle: some View {
        let x = max(-1.4, min(1.4, model.driftDot.x)), y = max(-1.4, min(1.4, model.driftDot.y))
        return ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: model.anchorLocked ? [] : [4, 4]))
                .frame(width: 64, height: 64)
            Circle()
                .fill(model.driftExceeded ? Color.orange : Color.green)
                .frame(width: 12, height: 12)
                .offset(x: x * 32, y: y * 32)
        }
        .shadow(color: .black.opacity(0.35), radius: 3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var promptView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: model.prompt.symbol).foregroundStyle(promptTint)
            Text(model.prompt.text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(in: RoundedRectangle(cornerRadius: 22))
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: model.prompt)
        .accessibilityElement(children: .combine)
    }

    private var promptTint: Color {
        switch model.prompt.tone {
        case .guide: .primary
        case .caution: .orange
        case .done: .green
        }
    }

    /// Ring, primary button, and a spacer that keeps the button centred. When the text is too large for one row the
    /// button takes the full width and the ring sits under it.
    private var bottomBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                coverage
                Spacer(minLength: 8)
                primaryButton
                Spacer(minLength: 8)
                coverage.hidden().accessibilityHidden(true)
            }
            VStack(spacing: 10) {
                primaryButton
                coverage
            }
        }
    }

    /// The ring is a graphic; the number moves beside it when the text is too large to sit inside (review U02).
    private var coverage: some View {
        let percent = "\(Int((model.coverage * 100).rounded()))%"
        return HStack(spacing: 8) {
            CoverageRing(coverage: model.coverage, reached: model.reachedTarget, label: typeSize.isAccessibilitySize ? nil : percent,
                         animate: !reduceMotion)
                .frame(width: 58, height: 58)
            if typeSize.isAccessibilitySize {
                Text(percent).font(.headline.monospacedDigit()).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .glassEffect(in: Capsule())
            }
        }
        .opacity(model.phase == .scanning ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sun path the camera has covered")
        .accessibilityValue("\(Int((model.coverage * 100).rounded())) percent")
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch model.phase {
        case .ready:
            Button("Start") { model.start() }
                .font(.headline)
                .frame(minWidth: 96)
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
        case .scanning:
            if model.reachedTarget {
                Button("Save", action: requestSave)
                    .font(.headline)
                    .frame(minWidth: 96)
                    .buttonStyle(.glassProminent)
                    .controlSize(.extraLarge)
            } else {
                Button("Save", action: requestSave)
                    .font(.headline)
                    .frame(minWidth: 96)
                    .buttonStyle(.glass)
                    .controlSize(.extraLarge)
            }
        case .saving:
            ProgressView().controlSize(.large).frame(minWidth: 96, minHeight: 52)
        case .saved, .unsupported:
            EmptyView()
        }
    }

    private func unsupported(_ reason: String) -> some View {
        VStack(spacing: 20) {
            ContentUnavailableView("Light scan needs a camera", systemImage: "camera.metering.unknown", description: Text(reason))
                .foregroundStyle(.white)
            Button("Close") { dismiss() }.buttonStyle(.glass)
        }
    }

    // MARK: - Actions

    private func close() {
        if model.phase == .scanning { confirmingDiscard = true } else { dismiss() }
    }

    private func requestSave() {
        if model.reachedTarget { model.save(in: context) } else { confirmingLowCoverage = true }
    }
}

/// How much of the question's sun path the camera has pointed at. Turns green at the target.
struct CoverageRing: View {
    let coverage: Double
    let reached: Bool
    /// The percentage inside the ring, or nil when it is shown beside it.
    let label: String?
    let animate: Bool

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.001, coverage))
                .stroke(reached ? Color.green : SunPathOverlay.sun, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let label {
                Text(label).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.white)
            } else if reached {
                Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(.green)
            }
        }
        .padding(5)
        .glassEffect(in: Circle())
        .animation(animate ? .spring(response: 0.35, dampingFraction: 1) : nil, value: coverage)
    }
}

/// What was saved, and plainly what was not worked out (review U06): a saved scan is not a sunlight result.
struct LightResultSheet: View {
    let result: LightScanResult
    let onRetrySave: () -> Void
    let onRetryAttach: () -> Void
    let onScanAgain: () -> Void
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let failure = result.failure { failed(failure) } else { saved }
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) { buttons }
    }

    @ViewBuilder
    private var saved: some View {
        Label {
            Text("Scan saved")
        } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
        .font(.title2.weight(.bold))
        VStack(spacing: 10) {
            AdaptiveRow(title: String(localized: "Camera covered"), value: String(localized: "\(result.coveragePct)% of the \(result.questionName) path"))
            AdaptiveRow(title: String(localized: "Direction"), value: String(localized: "\(result.direction), approximate"))
            AdaptiveRow(title: String(localized: "Place"), value: result.place)
        }
        .font(.callout)
        VStack(alignment: .leading, spacing: 6) {
            Label("Sunlight not calculated yet", systemImage: "hourglass").font(.headline)
            Text("This scan recorded where the camera pointed and which way the phone faced. It can't yet tell sky from buildings or trees, so there are no sunlight hours.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // Said only of frames that are all on disk; what happens to them is said with it (docs/04 §12).
            Text(result.spoolFrames.map { String(localized: "\($0) frames from this scan are kept on this device for 14 days, for that analysis. After that, this spot needs a new scan.") }
                 ?? String(localized: "No frames were kept for that analysis, so this spot will need a new scan."))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        if let pending = result.pendingNote {
            VStack(alignment: .leading, spacing: 8) {
                Text(pending).font(.footnote).foregroundStyle(Color.cautionText).fixedSize(horizontal: false, vertical: true)
                Button("Try adding it again", action: onRetryAttach).font(.footnote.weight(.semibold))
            }
        }
    }

    @ViewBuilder
    private func failed(_ failure: String) -> some View {
        Label("Scan not saved", systemImage: "exclamationmark.triangle.fill")
            .font(.title2.weight(.bold)).foregroundStyle(Color.cautionText)
        Text(failure).font(.callout).fixedSize(horizontal: false, vertical: true)
        if result.canRetrySave {
            Text("The scan itself is still here. You can try saving it again; you don't need to scan again.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                secondaryButton
                primaryButton
            }
            VStack(spacing: 10) {
                primaryButton
                secondaryButton
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder
    private var primaryButton: some View {
        if result.failure != nil && result.canRetrySave {
            Button(action: onRetrySave) { Text("Try saving again").font(.headline).frame(maxWidth: .infinity, minHeight: 28) }
                .buttonStyle(.borderedProminent)
        } else {
            Button(action: onDone) { Text("Done").font(.headline).frame(maxWidth: .infinity, minHeight: 28) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("lightScanDone")
        }
    }

    @ViewBuilder
    private var secondaryButton: some View {
        if result.failure != nil && result.canRetrySave {
            Button(action: onDone) { Text("Close without saving").frame(minHeight: 28) }
                .buttonStyle(.bordered)
        } else {
            Button(action: onScanAgain) { Text("Scan again").frame(minHeight: 28) }
                .buttonStyle(.bordered)
        }
    }
}
