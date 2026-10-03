import CaptureCore
import PropertyModel
import SceneRecord
import SwiftData
import SwiftUI

/// W1 capture validator (docs/07 W1). One button, live stats, a shareable SceneRecord. When opened from Inspect it is
/// bound to a property and leaves an `InspectionObservation(kind: .light)` carrying the record; from You › Advanced it is
/// unbound and only shared. A bound record goes to disk as a PendingCapture before the database is touched (R02).
struct CaptureValidatorView: View {
    let property: Property?
    let roomLabel: String?

    @Environment(\.modelContext) private var context
    @Query(sort: \UserPreferences.createdAt) private var preferencesRows: [UserPreferences]
    @StateObject private var recorder = CaptureRecorder()
    @State private var exportURL: URL?
    @State private var lastError: String?
    /// Recorded and safe on disk, but not yet on a row. Retried here, or on the next launch.
    @State private var pending: PendingCapture?
    @State private var attachError: String?
    @State private var stoppedWithoutExport = false

    var body: some View {
        List {
            Section(property?.shortAddress ?? "Unbound debug capture") {
                if let property { Text("\(property.address)\(roomLabel.map { " · \($0)" } ?? "")").font(.footnote).foregroundStyle(.secondary) }
                else { Text("Not attached to a property. The record can be shared but is not remembered.").font(.footnote).foregroundStyle(.secondary) }
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
                    if let reason = recorder.failureReason { Text("ARSession: \(reason)").foregroundStyle(Color.cautionText).font(.footnote) }
                }
                Section {
                    Button(recorder.isRunning ? "Stop and export" : "Start OneTake") {
                        if recorder.isRunning { finish() } else { begin() }
                    }
                    .font(.headline)
                    if stoppedWithoutExport { Text("Stopped when you left the screen; nothing exported.").font(.footnote).foregroundStyle(Color.cautionText) }
                }
            case .unsupported(let reason):
                Section {
                    ContentUnavailableView("Needs a real iPhone", systemImage: "iphone.slash", description: Text(reason))
                }
            }
            if let pending {
                Section("Not added to the property yet") {
                    Text(attachError ?? "Saving…").font(.footnote).foregroundStyle(Color.cautionText)
                    Text("The record \(pending.sceneID) is kept on this phone and is added automatically the next time the app opens.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Try again") { attach() }
                }
            }
            if let exportURL {
                Section("Last record") {
                    Text(exportURL.deletingPathExtension().lastPathComponent).font(.footnote.monospaced())
                    ShareLink(item: exportURL) { Label("Share scene.json", systemImage: "square.and.arrow.up") }
                }
            }
            if let lastError {
                Section("Validation") { Text(lastError).foregroundStyle(Color.problemText).font(.footnote.monospaced()) }
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
            let outcome = try LightCaptureSaver.save(log, property: property, roomLabel: roomLabel, note: nil, in: context)
            exportURL = outcome.shareURL
            lastError = nil
            pending = outcome.pending
            attachError = outcome.attachError.map { "Couldn't add it to the property: \($0)" }
        } catch {
            lastError = String(describing: error)
        }
    }

    /// Puts the pending record on the property's open inspection. Idempotent by scene id.
    private func attach() {
        guard let capture = pending, let property else { return }
        do {
            try LightCaptureSaver.attach(capture, to: property, in: context)
            pending = nil
            attachError = nil
        } catch {
            attachError = "Couldn't add it to the property: \(error.localizedDescription)"
        }
    }
}
