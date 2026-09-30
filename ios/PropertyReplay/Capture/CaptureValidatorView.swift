import CaptureCore
import PropertyModel
import SceneRecord
import SwiftData
import SwiftUI

/// W1 capture validator (docs/07 W1). One button, live stats, export of the SceneRecord. When opened from Inspect it
/// is bound to a property and leaves an `InspectionObservation(kind: .light)` behind; from You › Advanced it is unbound.
struct CaptureValidatorView: View {
    let property: Property?
    let roomLabel: String?

    @Environment(\.modelContext) private var context
    @Query private var preferencesRows: [UserPreferences]
    @StateObject private var recorder = CaptureRecorder()
    @State private var exportURL: URL?
    @State private var lastError: String?
    @State private var stoppedWithoutExport = false

    var body: some View {
        List {
            Section(property?.shortAddress ?? "Unbound debug capture") {
                if let property { Text("\(property.address)\(roomLabel.map { " · \($0)" } ?? "")").font(.footnote).foregroundStyle(.secondary) }
                else { Text("Not attached to a property. The record is exported but not remembered.").font(.footnote).foregroundStyle(.secondary) }
            }
            switch recorder.availability {
            case .supported:
                Section("Session") {
                    LabeledContent("Tracking", value: recorder.trackingState)
                    LabeledContent("Anchor", value: recorder.anchorLocked ? "Locked" : "Waiting for normal tracking")
                    LabeledContent("Pose samples", value: "\(recorder.frameCount)")
                    LabeledContent("Lens drift", value: driftText)
                    LabeledContent("Heading", value: headingText)
                    LabeledContent("Location", value: locationText)
                    if let reason = recorder.failureReason { Text("ARSession: \(reason)").foregroundStyle(.orange).font(.footnote) }
                }
                Section {
                    Button(recorder.isRunning ? "Stop and export" : "Start OneTake") {
                        if recorder.isRunning { finish() } else { begin() }
                    }
                    .font(.headline)
                    if stoppedWithoutExport { Text("Stopped when you left the screen; nothing exported.").font(.footnote).foregroundStyle(.orange) }
                }
            case .unsupported(let reason):
                Section {
                    ContentUnavailableView("Needs a real iPhone", systemImage: "iphone.slash", description: Text(reason))
                }
            }
            if let exportURL {
                Section("Last record") {
                    Text(exportURL.deletingLastPathComponent().lastPathComponent).font(.footnote.monospaced())
                    ShareLink(item: exportURL) { Label("Share scene.json", systemImage: "square.and.arrow.up") }
                }
            }
            if let lastError {
                Section("Validation") { Text(lastError).foregroundStyle(.red).font(.footnote.monospaced()) }
            }
            Section {
                Text("Records every pose, the heading readings and one location fix into a capture-only (R0) SceneRecord. No sky, no north, no sun yet.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Capture validator")
        .onDisappear {
            if recorder.isRunning {
                _ = recorder.stop()
                stoppedWithoutExport = true
            }
        }
    }

    private var driftText: String {
        guard let current = recorder.currentDriftM else { return "— (anchor not locked)" }
        return String(format: "%.2f m (max %.2f m)", current, recorder.maxDriftM ?? current)
    }

    private var headingText: String {
        guard let h = recorder.latestHeading else { return "—" }
        return h.isValid ? String(format: "%.0f° ± %.0f°", h.trueHeading, h.headingAccuracy) : "invalid reading"
    }

    private var locationText: String {
        guard let l = recorder.location else { return "—" }
        return String(format: "±%.0f m", l.horizontalAccuracyM ?? -1)
    }

    private func begin() {
        stoppedWithoutExport = false
        recorder.viewpointToleranceM = preferencesRows.first?.viewpointToleranceM ?? 0.15
        recorder.start()
    }

    private func finish() {
        let height = preferencesRows.first?.targetHeightM
        let label = property.map { "\($0.shortAddress)\(roomLabel.map { " · \($0)" } ?? "")" } ?? "Capture validator target"
        guard let log = recorder.stop(targetLabel: label, targetHeightM: height) else { return }
        do {
            let result = try SceneExporter.export(log, root: SceneStore.root)
            exportURL = result.fileURL
            lastError = nil
            try remember(sceneID: result.sceneID)
        } catch {
            lastError = String(describing: error)
        }
    }

    /// A light observation on the property's open inspection. Its level is Unknown until an analysis passes (ADR-0013).
    private func remember(sceneID: String) throws {
        guard let property else { return }
        let inspection = PropertyStore.openInspection(for: property, in: context)
        let observation = InspectionObservation(kind: .light, category: .naturalLight, source: .sensor, roomLabel: roomLabel)
        observation.sceneId = sceneID
        observation.text = "Light measurement recorded (analysis pending)"
        observation.inspection = inspection
        inspection.observations.append(observation)
        context.insert(observation)
        try context.save()
    }
}
