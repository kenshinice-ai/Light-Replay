import Compression
import CoreImage
import CoreVideo
import CryptoKit
import Foundation
import simd

/// How a stored picture relates to the sensor image its intrinsics describe (docs/03 §11, `SunEngine.ImageTransform`):
/// the whole sensor image, scaled, then turned clockwise by `rotationDeg`.
public struct StoredImage: Codable, Sendable, Equatable {
    /// File name inside the spool folder. Nil for the hero, whose bytes travel with the row.
    public var file: String?
    public var nativeWidth: Int
    public var nativeHeight: Int
    public var encodedWidth: Int
    public var encodedHeight: Int
    public var scale: Double
    public var rotationDeg: Int
    public var byteCount: Int
    public var sha256: String
}

/// The picture a scan is remembered by: the frame that locked the viewpoint, stored upright.
public struct HeroImage: Sendable, Equatable {
    public var data: Data
    public var image: StoredImage
    public var frameID: String

    public init(data: Data, image: StoredImage, frameID: String) {
        self.data = data
        self.image = image
        self.frameID = frameID
    }
}

/// LiDAR depth of one spool frame: `width × height` Float16 metres (little-endian, row-major) followed by
/// `width × height` confidence bytes (ARConfidenceLevel: 0 low, 1 medium, 2 high), the whole compressed with LZFSE.
/// The depth map covers the same field of view as the colour image; a depth pixel (i, j) is the colour pixel
/// ((i + 0.5) · nativeWidth / width, (j + 0.5) · nativeHeight / height).
public struct SpoolDepth: Codable, Sendable, Equatable {
    public var file: String
    public var width: Int
    public var height: Int
    public var byteCount: Int
    public var sha256: String
}

/// One frame kept for analysis, with everything that was true of it at the same instant (docs/04 §12, review R01):
/// the picture, its pose, the intrinsics of the sensor image it was scaled from, and its depth when there is LiDAR.
public struct SpoolFrame: Codable, Sendable, Equatable {
    public var frameID: String
    /// ARFrame.timestamp, seconds, monotonic.
    public var timestamp: Double
    /// Seconds since the first frame of the record, as in the pose log.
    public var t: Double
    /// Column-major 4x4 camera-to-world transform.
    public var cameraTransform: [Double]
    /// Column-major 3x3 intrinsics of the sensor image (not of the stored picture).
    public var intrinsics: [Double]
    public var image: StoredImage
    public var depth: SpoolDepth?
    public var exposureOffset: Double?
    public var lensOffsetM: Double?
    public var turnRateDegPerSec: Double
    /// "visibility" for the scan itself; "calibration" for frames taken while confirming the direction.
    public var role: String
}

/// What a spool folder holds. Written once, when the scan ends; a folder without it is an unfinished scan.
public struct SpoolManifest: Codable, Sendable, Equatable {
    public var version = 1
    /// The capture session, which is also the identity of the row the scan becomes.
    public var sessionID: String
    public var createdAt: Date
    /// False when frames were dropped because the limit was reached.
    public var truncated: Bool
    public var frames: [SpoolFrame]
    public var hero: StoredImage?
    public var heroFrameID: String?
    /// After this the frames are deleted, analysed or not (docs/04 §12; 14 days, a candidate).
    public var expiresAt: Date

    /// What this capture's input was, for the record's `result.capture_digest`: the frames in order with the hashes
    /// of their pictures and depth, and the hero. Two scans never share it; one scan always gives the same.
    public var digest: String {
        var hash = SHA256()
        hash.update(data: Data(sessionID.utf8))
        for frame in frames {
            hash.update(data: Data("|\(frame.frameID):\(frame.image.sha256):\(frame.depth?.sha256 ?? "-")".utf8))
        }
        hash.update(data: Data("|hero:\(hero?.sha256 ?? "-")".utf8))
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Which frames of a scan are kept for analysis (docs/04 §12). A frame qualifies when tracking is normal, the lens is
/// within the viewpoint tolerance and the phone is not turning fast; of those, one is kept when enough time has
/// passed or the view has moved enough since the last one kept. This is support from repeated looks, not
/// statistical independence.
public enum SpoolAdmission {
    /// Never more often than this, whatever the phone does: 5 frames a second.
    public static let hardMinIntervalS = 0.2
    /// Kept by time alone after this long.
    public static let intervalS = 0.3
    /// Kept sooner than `intervalS` only when the view direction moved this far.
    public static let angleDeg = 5.0
    public static let maxTurnRateDegPerSec = 60.0
    /// About 80 seconds of scanning at the fastest rate; beyond it the spool is marked truncated.
    public static let maxFrames = 400

    public static func admits(trackingNormal: Bool, lensOffsetM: Double?, toleranceM: Double, turnRateDegPerSec: Double,
                              sinceLast: TimeInterval?, angleFromLastDeg: Double?) -> Bool {
        guard trackingNormal, let lensOffsetM, lensOffsetM <= toleranceM + 1e-9, turnRateDegPerSec <= maxTurnRateDegPerSec else { return false }
        guard let sinceLast else { return true }
        if sinceLast < hardMinIntervalS - 1e-9 { return false }
        return sinceLast >= intervalS - 1e-9 || (angleFromLastDeg ?? 0) >= angleDeg
    }
}

/// Where spools live and when they go (docs/04 §12). They are the one input that cannot be fetched again: not in
/// Caches, where the system may clear them; not in iCloud or backups, where a house's interior has no business.
public enum FrameSpool {
    public static var root: URL { URL.applicationSupportDirectory.appending(path: "LightSpool", directoryHint: .isDirectory) }
    public static let retention: TimeInterval = 14 * 86_400
    static let manifestName = "manifest.json"

    public static func folder(for sessionID: String, root: URL = root) -> URL {
        root.appending(path: sessionID, directoryHint: .isDirectory)
    }

    /// The manifest of a finished spool, or nil when the folder is missing or the scan never finished.
    public static func manifest(for sessionID: String, root: URL = root) -> SpoolManifest? {
        guard let data = try? Data(contentsOf: folder(for: sessionID, root: root).appending(path: manifestName)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SpoolManifest.self, from: data)
    }

    public static func remove(sessionID: String, root: URL = root) {
        try? FileManager.default.removeItem(at: folder(for: sessionID, root: root))
    }

    /// Whether every file the manifest names is there with the length it states. Cheap: no hashing.
    public static func isIntact(_ manifest: SpoolManifest, root: URL = root) -> Bool {
        let folder = folder(for: manifest.sessionID, root: root)
        func length(_ name: String) -> Int? {
            (try? folder.appending(path: name).resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        }
        return manifest.frames.allSatisfy { frame in
            guard let file = frame.image.file, length(file) == frame.image.byteCount else { return false }
            return frame.depth.map { length($0.file) == $0.byteCount } ?? true
        }
    }

    public struct Sweep: Sendable, Equatable {
        /// Scans that never finished, or whose row no longer exists.
        public var orphans: [String] = []
        /// Finished scans whose frames reached the end of their keeping time.
        public var expired: [String] = []
    }

    /// Removes what should not be kept: unfinished scans older than an hour, scans whose row is gone, and scans past
    /// their keeping time. `live` is every row identity and pending capture that may still need its frames.
    @discardableResult
    public static func sweep(keeping live: Set<String>, now: Date = Date(), root: URL = root) -> Sweep {
        var result = Sweep()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for name in names where !name.hasPrefix(".") {
            let folder = folder(for: name, root: root)
            guard let manifest = manifest(for: name, root: root) else {
                let created = (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                if now.timeIntervalSince(created) > 3600 {
                    remove(sessionID: name, root: root)
                    result.orphans.append(name)
                }
                continue
            }
            if !live.contains(name.lowercased()) && !live.contains(name.uppercased()) && !live.contains(name) {
                if now.timeIntervalSince(manifest.createdAt) > 3600 {   // a scan saved a moment ago may not have its row yet
                    remove(sessionID: name, root: root)
                    result.orphans.append(name)
                }
            } else if now > manifest.expiresAt {
                remove(sessionID: name, root: root)
                result.expired.append(name)
            }
        }
        return result
    }
}

/// Writes a scan's frames to its spool folder while the scan runs. Encoding happens off the main thread; when it
/// falls behind, frames are refused rather than queued, so camera buffers are never held for long.
public final class FrameSpoolWriter: @unchecked Sendable {
    public struct Meta: Sendable {
        public var frameID: String
        public var timestamp: Double
        public var t: Double
        public var cameraTransform: [Double]
        public var intrinsics: [Double]
        public var exposureOffset: Double?
        public var lensOffsetM: Double?
        public var turnRateDegPerSec: Double
        public var role: String

        public init(frameID: String, timestamp: Double, t: Double, cameraTransform: [Double], intrinsics: [Double],
                    exposureOffset: Double?, lensOffsetM: Double?, turnRateDegPerSec: Double, role: String = "visibility") {
            self.frameID = frameID
            self.timestamp = timestamp
            self.t = t
            self.cameraTransform = cameraTransform
            self.intrinsics = intrinsics
            self.exposureOffset = exposureOffset
            self.lensOffsetM = lensOffsetM
            self.turnRateDegPerSec = turnRateDegPerSec
            self.role = role
        }
    }

    public static let frameLongSide = 960.0
    public static let heroLongSide = 2048.0
    static let maxInFlight = 2

    public let sessionID: String
    public let folder: URL
    private let queue = DispatchQueue(label: "com.pwegroup.propertyreplay.spool", qos: .userInitiated)
    private let lock = NSLock()
    private let context = CIContext()
    private var inFlight = 0
    private var accepted = 0
    private var truncated = false
    private var frames: [SpoolFrame] = []          // on `queue`
    private var hero: HeroImage?                   // on `queue`
    /// To the second: the manifest stores dates as ISO 8601, and what is read back must equal what was written.
    private let createdAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))

    public init(sessionID: String, root: URL = FrameSpool.root) throws {
        self.sessionID = sessionID
        folder = FrameSpool.folder(for: sessionID, root: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var parent = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? parent.setResourceValues(values)
    }

    /// Takes a frame for encoding. False when the encoder is busy or the spool is full: the frame is not kept.
    public func offer(image: CVPixelBuffer, depth: CVPixelBuffer?, confidence: CVPixelBuffer?, meta: Meta) -> Bool {
        guard reserve() else { return false }
        let box = Buffers(image: image, depth: depth, confidence: confidence)
        queue.async { [self] in
            defer { release() }
            let picture = CIImage(cvPixelBuffer: box.image)
            guard let stored = try? encode(picture, longSide: Self.frameLongSide, rotationDeg: 0, quality: 0.8, name: meta.frameID + ".jpg") else { return }
            let packed = box.depth.flatMap { depth in try? Self.pack(depth: depth, confidence: box.confidence) }
            append(meta, image: stored.image, depth: packed, depthName: meta.frameID + ".depth")
        }
        return true
    }

    /// Takes a picture that is already a JPEG (the simulator's drawn frames). `native` is the size of the image the
    /// intrinsics in `meta` describe; nil when the JPEG is that image.
    public func offer(jpeg: Data, width: Int, height: Int, native: (width: Int, height: Int)? = nil, meta: Meta) -> Bool {
        guard reserve() else { return false }
        queue.async { [self] in
            defer { release() }
            let name = meta.frameID + ".jpg"
            guard (try? jpeg.write(to: folder.appending(path: name), options: .atomic)) != nil else { return }
            append(meta, image: Self.described(jpeg, name: name, width: width, height: height, native: native), depth: nil, depthName: "")
        }
        return true
    }

    private static func described(_ jpeg: Data, name: String?, width: Int, height: Int, native: (width: Int, height: Int)?) -> StoredImage {
        let nativeWidth = native?.width ?? width, nativeHeight = native?.height ?? height
        return StoredImage(file: name, nativeWidth: nativeWidth, nativeHeight: nativeHeight, encodedWidth: width, encodedHeight: height,
                           scale: Double(width) / Double(nativeWidth), rotationDeg: 0, byteCount: jpeg.count, sha256: sha256(jpeg))
    }

    /// Encodes the hero, upright: `rotationDeg` is the clockwise turn that puts the sensor image the way it was seen.
    public func setHero(image: CVPixelBuffer, rotationDeg: Int, frameID: String) {
        let box = Buffers(image: image, depth: nil, confidence: nil)
        queue.async { [self] in
            guard let stored = try? encode(CIImage(cvPixelBuffer: box.image), longSide: Self.heroLongSide, rotationDeg: rotationDeg, quality: 0.85, name: nil) else { return }
            hero = HeroImage(data: stored.data, image: stored.image, frameID: frameID)
        }
    }

    public func setHero(jpeg: Data, width: Int, height: Int, native: (width: Int, height: Int)? = nil, frameID: String) {
        queue.async { [self] in
            hero = HeroImage(data: jpeg, image: Self.described(jpeg, name: nil, width: width, height: height, native: native), frameID: frameID)
        }
    }

    /// Waits for the encoder to drain, writes the manifest and returns it with the hero. After this the folder is a
    /// finished spool: "saved, ready to analyse" may only be said once this has returned a manifest.
    public func finish() async -> (manifest: SpoolManifest?, hero: HeroImage?) {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let manifest = SpoolManifest(sessionID: sessionID, createdAt: createdAt, truncated: truncated,
                                             frames: frames.sorted { $0.timestamp < $1.timestamp }, hero: hero?.image,
                                             heroFrameID: hero?.frameID, expiresAt: createdAt.addingTimeInterval(FrameSpool.retention))
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.sortedKeys]
                let written = (try? encoder.encode(manifest).write(to: folder.appending(path: FrameSpool.manifestName), options: .atomic)) != nil
                continuation.resume(returning: (written && !manifest.frames.isEmpty ? manifest : nil, hero))
            }
        }
    }

    /// Drops the folder and everything queued for it.
    public func discard() {
        queue.async { [self] in try? FileManager.default.removeItem(at: folder) }
    }

    // MARK: - Encoding

    private struct Buffers: @unchecked Sendable {
        let image: CVPixelBuffer
        let depth: CVPixelBuffer?
        let confidence: CVPixelBuffer?
    }

    private func reserve() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if accepted >= SpoolAdmission.maxFrames {
            truncated = true
            return false
        }
        guard inFlight < Self.maxInFlight else { return false }
        inFlight += 1
        accepted += 1
        return true
    }

    private func release() {
        lock.lock()
        inFlight -= 1
        lock.unlock()
    }

    private func append(_ meta: Meta, image: StoredImage, depth: (data: Data, width: Int, height: Int)?, depthName: String) {
        var stored: SpoolDepth?
        if let depth, (try? depth.data.write(to: folder.appending(path: depthName), options: .atomic)) != nil {
            stored = SpoolDepth(file: depthName, width: depth.width, height: depth.height, byteCount: depth.data.count, sha256: Self.sha256(depth.data))
        }
        frames.append(SpoolFrame(frameID: meta.frameID, timestamp: meta.timestamp, t: meta.t, cameraTransform: meta.cameraTransform,
                                 intrinsics: meta.intrinsics, image: image, depth: stored, exposureOffset: meta.exposureOffset,
                                 lensOffsetM: meta.lensOffsetM, turnRateDegPerSec: meta.turnRateDegPerSec, role: meta.role))
    }

    /// Scales so the longer side is `longSide` (never up), turns clockwise, encodes as JPEG, and writes it when named.
    private func encode(_ picture: CIImage, longSide: Double, rotationDeg: Int, quality: Double, name: String?) throws -> (data: Data, image: StoredImage) {
        let nativeWidth = picture.extent.width, nativeHeight = picture.extent.height
        let scale = min(1, longSide / max(nativeWidth, nativeHeight))
        var output = picture.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let orientation: CGImagePropertyOrientation = switch ((rotationDeg % 360) + 360) % 360 {
        case 90: .right
        case 180: .down
        case 270: .left
        default: .up
        }
        output = output.oriented(orientation)
        output = output.transformed(by: CGAffineTransform(translationX: -output.extent.minX, y: -output.extent.minY))
        guard let colour = CGColorSpace(name: CGColorSpace.sRGB),
              let data = context.jpegRepresentation(of: output, colorSpace: colour,
                                                    options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        if let name { try data.write(to: folder.appending(path: name), options: .atomic) }
        // The stored size as the JPEG has it, and the scale that really maps the sensor image onto it.
        let encodedWidth = Int(output.extent.width.rounded()), encodedHeight = Int(output.extent.height.rounded())
        return (data, StoredImage(file: name, nativeWidth: Int(nativeWidth), nativeHeight: Int(nativeHeight), encodedWidth: encodedWidth,
                                  encodedHeight: encodedHeight, scale: scale, rotationDeg: ((rotationDeg % 360) + 360) % 360,
                                  byteCount: data.count, sha256: Self.sha256(data)))
    }

    static func pack(depth: CVPixelBuffer, confidence: CVPixelBuffer?) throws -> (data: Data, width: Int, height: Int) {
        guard CVPixelBufferGetPixelFormatType(depth) == kCVPixelFormatType_DepthFloat32 else { throw CocoaError(.fileWriteUnknown) }
        let width = CVPixelBufferGetWidth(depth), height = CVPixelBufferGetHeight(depth)
        var raw = Data(capacity: width * height * 3)
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(depth) else { throw CocoaError(.fileWriteUnknown) }
        let stride = CVPixelBufferGetBytesPerRow(depth)
        var metres = [Float16](repeating: 0, count: width * height)
        for row in 0..<height {
            let line = (base + row * stride).assumingMemoryBound(to: Float32.self)
            for column in 0..<width { metres[row * width + column] = Float16(line[column]) }
        }
        metres.withUnsafeBytes { raw.append(contentsOf: $0) }
        var levels = [UInt8](repeating: 0, count: width * height)
        if let confidence, CVPixelBufferGetWidth(confidence) == width, CVPixelBufferGetHeight(confidence) == height {
            CVPixelBufferLockBaseAddress(confidence, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
            if let cbase = CVPixelBufferGetBaseAddress(confidence) {
                let cstride = CVPixelBufferGetBytesPerRow(confidence)
                for row in 0..<height {
                    let line = (cbase + row * cstride).assumingMemoryBound(to: UInt8.self)
                    for column in 0..<width { levels[row * width + column] = line[column] }
                }
            }
        }
        raw.append(contentsOf: levels)
        return (try (raw as NSData).compressed(using: .lzfse) as Data, width, height)
    }

    /// The inverse of `pack`, for tests and for the analysis job.
    public static func unpack(_ data: Data, width: Int, height: Int) throws -> (metres: [Float], confidence: [UInt8]) {
        let raw = try (data as NSData).decompressed(using: .lzfse) as Data
        guard raw.count == width * height * 3 else { throw CocoaError(.fileReadCorruptFile) }
        let metres = raw.prefix(width * height * 2).withUnsafeBytes { Array($0.bindMemory(to: Float16.self)).map(Float.init) }
        return (metres, Array(raw.suffix(width * height)))
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
