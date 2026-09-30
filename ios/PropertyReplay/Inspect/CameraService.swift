@preconcurrency import AVFoundation
import Foundation
import UIKit

/// Minimal still-photo camera for Capture (ADR-0015). Session work runs on its own queue; results hop to main.
final class CameraService: NSObject, ObservableObject, @unchecked Sendable {
    @MainActor @Published private(set) var isAvailable = false
    @MainActor @Published private(set) var isRunning = false
    @MainActor @Published private(set) var lastError: String?

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.pwegroup.propertyreplay.camera")
    private let output = AVCapturePhotoOutput()
    private var configured = false
    private var pendingCapture: PhotoCaptureDelegate?

    @MainActor
    func start() async {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
        default: granted = false
        }
        guard granted else { lastError = "Camera access is off. Enable it in Settings to capture photos."; return }
        let configuredOK: Bool = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.configureIfNeeded()) }
        }
        isAvailable = configuredOK
        guard configuredOK else { lastError = "No camera available on this device."; return }
        queue.async { self.session.startRunning() }
        isRunning = true
    }

    @MainActor
    func stop() {
        queue.async { self.session.stopRunning() }
        isRunning = false
    }

    /// JPEG bytes of one photo, or nil when the camera is not available.
    @MainActor
    func capturePhoto() async throws -> Data? {
        guard isAvailable else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                let delegate = PhotoCaptureDelegate { result in
                    self.queue.async { self.pendingCapture = nil }
                    continuation.resume(with: result)
                }
                self.pendingCapture = delegate
                self.output.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    private func configureIfNeeded() -> Bool {
        if configured { return true }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(output) else { session.commitConfiguration(); return false }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        configured = true
        return true
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: @Sendable (Result<Data?, any Error>) -> Void
    init(completion: @escaping @Sendable (Result<Data?, any Error>) -> Void) { self.completion = completion }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        if let error { completion(.failure(error)); return }
        completion(.success(photo.fileDataRepresentation()))
    }
}

/// Downscales a captured JPEG for storage (this is an observation photo, not a measurement frame).
enum PhotoScaler {
    static func jpeg(_ data: Data, maxPixels: CGFloat = 2048, quality: CGFloat = 0.85) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let longest = max(image.size.width, image.size.height) * image.scale
        guard longest > maxPixels else { return data }
        let factor = maxPixels / longest
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let renderer = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let scaled = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return scaled.jpegData(compressionQuality: quality) ?? data
    }
}
