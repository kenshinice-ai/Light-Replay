import CaptureCore
import SceneRecord
import SwiftUI

/// W1 capture validator UI (docs/07 W1, ios/README "Week 1"). One button, live stats, export of the SceneRecord.
struct CaptureValidatorView: View {
    @StateObject private var recorder = CaptureRecorder()
    @State private var exportURL: URL?
    @State private var lastError: String?
    @State private var sequence = 1

    var body: some View {
        List {
            switch recorder.availability {
            case .supported:
                Section("Session") {
                    LabeledContent("Tracking", value: recorder.trackingState)
                    LabeledContent("Pose samples", value: "\(recorder.frameCount)")
                    LabeledContent("Lens drift", value: String(format: "%.2f m (max %.2f m)", recorder.currentDriftM, recorder.maxDriftM))
                    LabeledContent("Heading", value: headingText)
                    LabeledContent("Location", value: locationText)
                }
                Section {
                    Button(recorder.isRunning ? "Stop and export" : "Start OneTake") {
                        if recorder.isRunning { finish() } else { recorder.start() }
                    }
                    .font(.headline)
                }
            case .unsupported(let reason):
                Section {
                    ContentUnavailableView("Needs a real iPhone", systemImage: "iphone.slash", description: Text(reason))
                }
            }
            if let exportURL {
                Section("Last record") {
                    Text(exportURL.lastPathComponent).font(.footnote.monospaced())
                    ShareLink(item: exportURL) { Label("Share scene.json", systemImage: "square.and.arrow.up") }
                }
            }
            if let lastError {
                Section("Validation") { Text(lastError).foregroundStyle(.red).font(.footnote.monospaced()) }
            }
            Section {
                Text("Records poses, one magnetometer reading and one location fix into a capture-only (R0) SceneRecord. No sky, no north, no sun yet.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Capture validator")
    }

    private var headingText: String {
        guard let h = recorder.heading else { return "—" }
        return h.headingAccuracy >= 0 ? String(format: "%.0f° ± %.0f°", h.trueHeading, h.headingAccuracy) : "invalid"
    }

    private var locationText: String {
        guard let l = recorder.location else { return "—" }
        return String(format: "±%.0f m", l.horizontalAccuracyM ?? -1)
    }

    private func finish() {
        guard let log = recorder.stop() else { return }
        do {
            let sceneID = SceneRecordBuilder.sceneID(date: log.endedAt, sequence: sequence, timezone: log.timezone)
            let document = try SceneRecordBuilder.build(log, sceneID: sceneID)
            let folder = URL.documentsDirectory.appending(path: sceneID, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: "scene.json")
            try document.encoded().write(to: file, options: .atomic)
            exportURL = file
            lastError = nil
            sequence += 1
        } catch {
            lastError = String(describing: error)
        }
    }
}
