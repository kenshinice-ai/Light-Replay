import AVFoundation
import SwiftUI
import UIKit

/// The live viewfinder. The service's rotation coordinator keeps the picture upright in it, whichever way the device
/// and the interface are turned (UI/UX review U03).
struct CameraPreview: UIViewRepresentable {
    let service: CameraService

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = service.session
        view.previewLayer.videoGravity = .resizeAspectFill
        service.attach(previewLayer: view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
