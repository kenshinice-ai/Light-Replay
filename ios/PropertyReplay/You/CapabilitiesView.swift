import ARKit
import AVFoundation
import CoreLocation
import FoundationModels
import Speech
import SwiftUI

/// What this device can do for us, checked at runtime (ADR-0010 degradation, ADR-0011). Used on field days.
struct CapabilitiesView: View {
    @State private var rows: [(String, String)] = []
    @State private var loading = true

    var body: some View {
        List {
            Section {
                ForEach(rows, id: \.0) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.0).font(.subheadline.weight(.medium))
                        Text(row.1).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if loading { ProgressView() }
            } footer: {
                Text("Runtime checks only. Nothing here is a promise about accuracy; it says which paths can run on this phone.")
            }
        }
        .navigationTitle("Device capabilities")
        .task { await load() }
    }

    private func load() async {
        var r: [(String, String)] = []
        r.append(("ARKit world tracking", ARWorldTrackingConfiguration.isSupported ? "Supported" : "Not supported"))
        r.append(("Scene depth (LiDAR)", ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) ? "Yes" : "No"))
        r.append(("Geo tracking (device)", ARGeoTrackingConfiguration.isSupported ? "Device supports it" : "No"))
        r.append(("Back camera", AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil ? "Wide-angle available" : "None"))
        switch SystemLanguageModel.default.availability {
        case .available: r.append(("Foundation Models (on-device)", "Available"))
        case .unavailable(let reason): r.append(("Foundation Models (on-device)", "Unavailable: \(String(describing: reason))"))
        }
        let pcc = PrivateCloudComputeLanguageModel()
        r.append(("Private Cloud Compute", pcc.isAvailable ? "Available" : "Unavailable (entitlement or eligibility)"))
        let supported = await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }
        let installed = await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }
        let interesting = supported.filter { $0.hasPrefix("en") || $0.hasPrefix("zh") }
        r.append(("Speech transcription supported", supported.isEmpty ? "None" : "\(supported.count) locales; \(interesting.joined(separator: ", "))"))
        r.append(("Speech models installed", installed.isEmpty ? "None yet (downloads on first Note)" : installed.joined(separator: ", ")))
        r.append(("Current locale", Locale.current.identifier))
        rows = r
        // docs/05 §2: Apple documents geo tracking for "several Australian metropolitan areas" without naming cities.
        let melbourne = CLLocationCoordinate2D(latitude: -37.8136, longitude: 144.9631)
        let geo: String = await withCheckedContinuation { continuation in
            ARGeoTrackingConfiguration.checkAvailability(at: melbourne) { @Sendable available, error in
                continuation.resume(returning: available ? "Available at Melbourne CBD" : "Not available at Melbourne CBD\(error.map { " (\($0.localizedDescription))" } ?? "")")
            }
        }
        rows.append(("Geo tracking coverage", geo))
        loading = false
    }
}
