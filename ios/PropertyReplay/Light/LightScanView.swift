import CaptureCore
import PropertyModel
import SunEngine
import SwiftData
import SwiftUI

/// The Light scan screen (docs/04 OneTake, apple-design review 2026-09-30): full-screen camera, the sun path for the
/// chosen question drawn into it, one instruction at a time, a coverage ring and one primary button.
struct LightScanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \UserPreferences.createdAt) private var preferencesRows: [UserPreferences]
    @AppStorage("lightScanQuestion") private var questionRaw = LightQuestion.winter.rawValue
    @State private var model: LightScanModel
    @State private var confirmingDiscard = false
    @State private var confirmingLowCoverage = false

    init(property: Property?, roomLabel: String?) {
        _model = State(initialValue: LightScanModel(property: property, roomLabel: roomLabel))
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                ZStack {
                    camera
                    SunPathOverlay(state: model.overlay)
                }
                .onAppear { model.viewSize = geo.size }
                .onChange(of: geo.size) { _, size in model.viewSize = size }
            }
            .ignoresSafeArea()

            if case .unsupported(let reason) = model.phase {
                unsupported(reason)
            } else {
                if model.phase == .ready || model.phase == .scanning { reticle }
                VStack(spacing: 14) {
                    topBar
                    Spacer()
                    if model.phase == .ready || model.phase == .scanning {
                        promptView
                        bottomBar
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            if case .saved(let result) = model.phase {
                resultCard(result)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1), value: model.phase)
        .background(Color.black)
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
        .sensoryFeedback(.impact(weight: .light), trigger: model.anchorLocked) { _, locked in locked }
        .sensoryFeedback(.success, trigger: model.reachedTarget) { _, reached in reached }
        .sensoryFeedback(trigger: model.phase) { _, phase in
            guard case .saved(let result) = phase else { return nil }
            return result.failure == nil ? .success : .error
        }
        .confirmationDialog("Discard this scan?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                model.discard()
                dismiss()
            }
            Button("Keep scanning", role: .cancel) {}
        }
        .alert("Only \(Int((model.coverage * 100).rounded()))% of the \(model.question.title.lowercased()) path was seen",
               isPresented: $confirmingLowCoverage) {
            Button("Save anyway") { model.save(in: context) }
            Button("Keep scanning", role: .cancel) {}
        } message: {
            Text("Parts of the path the camera didn't see stay unknown in the result.")
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

    private var topBar: some View {
        HStack {
            Button(action: close) {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Close")
            Spacer()
            Menu {
                Picker("Question", selection: Bindable(model).question) {
                    ForEach(LightQuestion.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(model.question.title).font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(in: Capsule())
            }
            .disabled(model.phase == .saving)
            Spacer()
            Label(model.directionText, systemImage: "location.north.line")
                .font(.caption.weight(.medium))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .glassEffect(in: Capsule())
                .accessibilityLabel("Direction: \(model.directionText)")
        }
        .padding(.top, 4)
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

    private var bottomBar: some View {
        HStack {
            CoverageRing(coverage: model.coverage, reached: model.reachedTarget, animate: !reduceMotion)
                .frame(width: 58, height: 58)
                .opacity(model.phase == .scanning ? 1 : 0.4)
            Spacer()
            primaryButton
            Spacer()
            Color.clear.frame(width: 58, height: 58)
        }
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

    private func resultCard(_ result: LightScanResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let failure = result.failure {
                Label("Scan not saved", systemImage: "exclamationmark.triangle.fill")
                    .font(.title3.weight(.bold)).foregroundStyle(.orange)
                Text(failure).font(.callout)
            } else {
                Label {
                    Text("Scan saved")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .font(.title3.weight(.bold))
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow { Text(result.pathTitle).foregroundStyle(.secondary); Text("\(result.coveragePct)% seen") }
                    GridRow { Text("Direction").foregroundStyle(.secondary); Text("\(result.direction), approximate") }
                    GridRow { Text("Place").foregroundStyle(.secondary); Text(result.place) }
                }
                .font(.callout)
                Text("Sunlight hours come from the sky analysis, which isn't ready yet. This scan is kept with the property and will be analysed then.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let pending = result.pendingNote {
                    Text(pending).font(.footnote).foregroundStyle(.orange)
                    Button("Try again") { model.retryAttach(in: context) }.font(.footnote.weight(.semibold))
                }
            }
            HStack {
                Button("Scan again") { model.scanAgain() }
                    .buttonStyle(.glass)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("lightScanDone")
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(maxWidth: 520)
        .glassEffect(in: RoundedRectangle(cornerRadius: 30))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .bottom)
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
        if model.coverage >= LightScanModel.targetCoverage { model.save(in: context) } else { confirmingLowCoverage = true }
    }
}

/// How much of the question's sun path the camera has looked at. Turns green at the target.
struct CoverageRing: View {
    let coverage: Double
    let reached: Bool
    let animate: Bool

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.001, coverage))
                .stroke(reached ? Color.green : SunPathOverlay.sun, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((coverage * 100).rounded()))%")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(5)
        .glassEffect(in: Circle())
        .animation(animate ? .spring(response: 0.35, dampingFraction: 1) : nil, value: coverage)
        .accessibilityElement()
        .accessibilityLabel("Sun path seen")
        .accessibilityValue("\(Int((coverage * 100).rounded())) percent")
    }
}
