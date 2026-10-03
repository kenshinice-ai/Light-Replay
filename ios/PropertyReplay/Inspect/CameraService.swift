@preconcurrency import AVFoundation
import Foundation
import os
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
    /// Set once on the session queue while configuring; read on the main actor only after that has finished.
    private var device: AVCaptureDevice?

    // Rotation (UI/UX review U03). Preview and capture each have their own angle: the preview follows the layer on
    // screen, the capture follows gravity, so a photo taken with the device on its side is saved upright even while
    // the interface stays in portrait. Both come from AVCaptureDevice.RotationCoordinator.
    @MainActor private var rotation: AVCaptureDevice.RotationCoordinator?
    @MainActor private var rotationObservers: [NSKeyValueObservation] = []
    @MainActor private weak var previewLayer: AVCaptureVideoPreviewLayer?
    /// The capture angle, read on the session queue when a photo is taken. 90° is portrait, the value before any reading.
    private let captureAngle = OSAllocatedUnfairLock(initialState: CGFloat(90))

    @MainActor
    func start() async {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
        default: granted = false
        }
        guard granted else { lastError = String(localized: "Camera access is off. Enable it in Settings to capture photos."); return }
        let configuredOK: Bool = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.configureIfNeeded()) }
        }
        isAvailable = configuredOK
        guard configuredOK else { lastError = String(localized: "No camera available on this device."); return }
        queue.async { self.session.startRunning() }
        isRunning = true
        startRotationIfReady()
    }

    /// Called by the preview when its layer exists.
    @MainActor
    func attach(previewLayer: AVCaptureVideoPreviewLayer) {
        if self.previewLayer !== previewLayer {
            self.previewLayer = previewLayer
            rotation = nil
            rotationObservers = []
        }
        startRotationIfReady()
    }

    @MainActor
    private func startRotationIfReady() {
        guard rotation == nil, let device, let layer = previewLayer else { applyRotation(); return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
        rotation = coordinator
        rotationObservers = [
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.applyRotation() }
            },
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.applyRotation() }
            }
        ]
        applyRotation()
    }

    @MainActor
    private func applyRotation() {
        guard let rotation else { return }
        let preview = rotation.videoRotationAngleForHorizonLevelPreview
        if let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(preview) {
            connection.videoRotationAngle = preview
        }
        let capture = rotation.videoRotationAngleForHorizonLevelCapture
        captureAngle.withLock { $0 = capture }
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
                let angle = self.captureAngle.withLock { $0 }
                if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
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
        self.device = device
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
