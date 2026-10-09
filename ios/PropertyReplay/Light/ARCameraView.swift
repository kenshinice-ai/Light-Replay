import ARKit
import RealityKit
import SwiftUI

/// The live camera for the Light scan: RealityKit's ARView showing the recorder's own ARSession, so the record and
/// the picture are the same session. Rendering effects the scan does not need are off.
struct ARCameraView: UIViewRepresentable {
    let session: ARSession
    let onView: (ARView) -> Void

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        let delegate = session.delegate
        view.session = session
        if session.delegate == nil { session.delegate = delegate }   // the recorder must keep receiving frames
        view.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableHDR, .disableCameraGrain,
                              .disableGroundingShadows, .disableAREnvironmentLighting, .disablePersonOcclusion,
                              .disableFaceMesh]
        view.environment.sceneUnderstanding.options = []
        onView(view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
