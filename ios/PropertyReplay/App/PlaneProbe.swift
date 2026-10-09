#if DEBUG
import ARKit
import CaptureCore
import Foundation

/// What ARKit says about the surfaces in front of this device: whether it can label them at all, and what it found
/// in a few seconds. `devicectl device process launch --console … com.pwegroup.propertyreplay -- -probePlanes`, with
/// the device unlocked. A phone lying on a desk sees nothing; the first line still answers "can this device label
/// planes". The scan itself is what shows whether a window is called a window.
@MainActor
final class PlaneProbe {
    static let shared = PlaneProbe()
    private var recorder: CaptureRecorder?

    func run(seconds: Double = 8) {
        print("[planes] classification supported: \(ARPlaneAnchor.isClassificationSupported); world tracking: \(ARWorldTrackingConfiguration.isSupported)")
        let recorder = CaptureRecorder()
        recorder.keepsSpool = false
        self.recorder = recorder
        recorder.startPreview()
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            print("[planes] tracking \(recorder.trackingState); surfaces after \(Int(seconds)) s: \(recorder.planeSummary)")
            recorder.endPreview()
        }
    }
}
#endif
