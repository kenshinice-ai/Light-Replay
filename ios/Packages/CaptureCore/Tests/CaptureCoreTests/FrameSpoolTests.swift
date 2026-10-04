import CoreGraphics
import CoreVideo
import ImageIO
import SceneRecord
import XCTest
@testable import CaptureCore

/// The frames a scan keeps for analysis (docs/04 §12, reviews R01 and R05). Synthetic pictures only.
final class FrameSpoolTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL.temporaryDirectory.appending(path: "spool-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    // MARK: - Which frames are kept

    func testAdmissionNeedsNormalTrackingTheViewpointAndASteadyHand() {
        func admits(normal: Bool = true, offset: Double? = 0.05, turn: Double = 10, since: TimeInterval? = nil, angle: Double? = nil) -> Bool {
            SpoolAdmission.admits(trackingNormal: normal, lensOffsetM: offset, toleranceM: 0.15, turnRateDegPerSec: turn, sinceLast: since, angleFromLastDeg: angle)
        }
        XCTAssertTrue(admits(), "the first qualifying frame")
        XCTAssertFalse(admits(normal: false))
        XCTAssertFalse(admits(offset: nil), "before the viewpoint is locked")
        XCTAssertFalse(admits(offset: 0.2), "outside the viewpoint tolerance")
        XCTAssertTrue(admits(offset: 0.15), "three steps of 0.05 count as 0.15")
        XCTAssertFalse(admits(turn: 61), "turning too fast: the frame would be smeared")
        XCTAssertFalse(admits(since: 0.1, angle: 20), "never more than five a second")
        XCTAssertFalse(admits(since: 0.25, angle: 2), "neither long enough nor far enough")
        XCTAssertTrue(admits(since: 0.25, angle: 5), "the view moved")
        XCTAssertTrue(admits(since: 0.3, angle: 0), "enough time passed")
    }

    // MARK: - What is written

    /// A grey picture with a red block in its top-left corner: row 0 of a pixel buffer is the top of the picture.
    private func picture(width: Int = 640, height: Int = 480) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        XCTAssertEqual(CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &buffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        defer { CVPixelBufferUnlockBaseAddress(pixels, []) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)), stride = CVPixelBufferGetBytesPerRow(pixels)
        for row in 0..<height {
            let line = (base + row * stride).assumingMemoryBound(to: UInt8.self)
            for column in 0..<width {
                let red = row < height / 4 && column < width / 4
                line[column * 4 + 0] = red ? 0 : 128      // B
                line[column * 4 + 1] = red ? 0 : 128      // G
                line[column * 4 + 2] = red ? 255 : 128    // R
                line[column * 4 + 3] = 255
            }
        }
        return pixels
    }

    private func depth(width: Int = 8, height: Int = 6) throws -> (depth: CVPixelBuffer, confidence: CVPixelBuffer) {
        var d: CVPixelBuffer?, c: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_DepthFloat32, nil, &d)
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_OneComponent8, nil, &c)
        let depth = try XCTUnwrap(d), confidence = try XCTUnwrap(c)
        CVPixelBufferLockBaseAddress(depth, [])
        CVPixelBufferLockBaseAddress(confidence, [])
        for row in 0..<height {
            let line = (CVPixelBufferGetBaseAddress(depth)! + row * CVPixelBufferGetBytesPerRow(depth)).assumingMemoryBound(to: Float32.self)
            let levels = (CVPixelBufferGetBaseAddress(confidence)! + row * CVPixelBufferGetBytesPerRow(confidence)).assumingMemoryBound(to: UInt8.self)
            for column in 0..<width {
                line[column] = 0.5 + Float(row) + Float(column) * 0.25
                levels[column] = UInt8((row + column) % 3)
            }
        }
        CVPixelBufferUnlockBaseAddress(depth, [])
        CVPixelBufferUnlockBaseAddress(confidence, [])
        return (depth, confidence)
    }

    private func meta(_ id: String, at timestamp: Double) -> FrameSpoolWriter.Meta {
        .init(frameID: id, timestamp: timestamp, t: timestamp - 100, cameraTransform: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
              intrinsics: [500, 0, 0, 0, 500, 0, 320, 240, 1], exposureOffset: 0.1, lensOffsetM: 0.02, turnRateDegPerSec: 12)
    }

    /// RGB of one pixel of a JPEG, origin top-left.
    private func colour(of jpeg: Data, x: Int, y: Int) throws -> (r: Int, g: Int, b: Int, width: Int, height: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let at = (y * image.width + x) * 4   // a CGContext's memory starts with the top row
        return (Int(pixels[at]), Int(pixels[at + 1]), Int(pixels[at + 2]), image.width, image.height)
    }

    func testAFrameIsWrittenWithItsPoseItsScaleAndItsDepth() async throws {
        let writer = try FrameSpoolWriter(sessionID: "SESSION-A", root: root)
        let buffers = try depth()
        XCTAssertTrue(writer.offer(image: try picture(width: 1920, height: 1440), depth: buffers.depth, confidence: buffers.confidence, meta: meta("f00003", at: 100.4)))
        let result = await writer.finish()
        let manifest = try XCTUnwrap(result.manifest)
        XCTAssertEqual(manifest.frames.count, 1)
        let frame = manifest.frames[0]
        XCTAssertEqual(frame.frameID, "f00003")
        XCTAssertEqual(frame.t, 0.4, accuracy: 1e-9)
        XCTAssertEqual(frame.intrinsics[6], 320, "the intrinsics stay those of the sensor image")
        XCTAssertEqual([frame.image.nativeWidth, frame.image.nativeHeight, frame.image.encodedWidth, frame.image.encodedHeight], [1920, 1440, 960, 720])
        XCTAssertEqual(frame.image.scale, 0.5, accuracy: 1e-12)
        XCTAssertEqual(frame.image.rotationDeg, 0)
        let folder = FrameSpool.folder(for: "SESSION-A", root: root)
        let jpeg = try Data(contentsOf: folder.appending(path: try XCTUnwrap(frame.image.file)))
        XCTAssertEqual(jpeg.count, frame.image.byteCount)
        XCTAssertEqual(FrameSpoolWriter.sha256(jpeg), frame.image.sha256)
        let corner = try colour(of: jpeg, x: 40, y: 40)
        XCTAssertEqual([corner.width, corner.height], [960, 720])
        XCTAssertTrue(corner.r > 200 && corner.g < 60, "the top-left of the sensor image is the top-left of the stored frame")
        // Depth comes back as it went in, to half-float precision.
        let stored = try XCTUnwrap(frame.depth)
        let unpacked = try FrameSpoolWriter.unpack(try Data(contentsOf: folder.appending(path: stored.file)), width: stored.width, height: stored.height)
        XCTAssertEqual([stored.width, stored.height], [8, 6])
        XCTAssertEqual(unpacked.metres[0], 0.5, accuracy: 1e-3)
        XCTAssertEqual(unpacked.metres[8 * 5 + 7], 0.5 + 5 + 7 * 0.25, accuracy: 1e-2)
        XCTAssertEqual(unpacked.confidence[8 * 5 + 7], UInt8((5 + 7) % 3))
        XCTAssertTrue(FrameSpool.isIntact(manifest, root: root))
        XCTAssertEqual(FrameSpool.manifest(for: "SESSION-A", root: root), manifest, "what is read back is what was written")
    }

    /// Held upright, the sensor image is on its side. The hero is stored turned a quarter clockwise, and the corner
    /// that was top-left in the sensor image ends up top-right: the same statement `ImageTransform` makes.
    func testTheHeroIsStoredUpright() async throws {
        let writer = try FrameSpoolWriter(sessionID: "SESSION-B", root: root)
        writer.setHero(image: try picture(), rotationDeg: 90, frameID: "f00000")
        _ = writer.offer(image: try picture(), depth: nil, confidence: nil, meta: meta("f00000", at: 100))
        let finished = await writer.finish()
        let hero = try XCTUnwrap(finished.hero)
        XCTAssertEqual([hero.image.encodedWidth, hero.image.encodedHeight], [480, 640])
        XCTAssertEqual(hero.image.rotationDeg, 90)
        XCTAssertEqual(hero.image.scale, 1, "never scaled up")
        let topRight = try colour(of: hero.data, x: 440, y: 40), topLeft = try colour(of: hero.data, x: 40, y: 40)
        XCTAssertEqual([topRight.width, topRight.height], [480, 640])
        XCTAssertTrue(topRight.r > 200 && topRight.g < 60, "the sensor image's top-left corner is at the top-right")
        XCTAssertTrue(abs(topLeft.r - topLeft.g) < 30, "and not where it started")
        // The other two ways of holding the phone.
        for (rotation, x, y) in [(0, 40, 40), (180, 600, 440), (270, 40, 600)] {
            let other = try FrameSpoolWriter(sessionID: "SESSION-B\(rotation)", root: root)
            other.setHero(image: try picture(), rotationDeg: rotation, frameID: "f00000")
            let turned = await other.finish()
            let stored = try XCTUnwrap(turned.hero)
            let marked = try colour(of: stored.data, x: x, y: y)
            XCTAssertTrue(marked.r > 200 && marked.g < 60, "rotation \(rotation)")
        }
    }

    func testAScanThatKeptNothingLeavesNoManifestToAnalyse() async throws {
        let writer = try FrameSpoolWriter(sessionID: "SESSION-C", root: root)
        let result = await writer.finish()
        XCTAssertNil(result.manifest, "no frames: nothing to say is ready")
    }

    func testTheSameScanAlwaysHasTheSameDigestAndAnotherScanAnother() async throws {
        func spool(_ id: String) async throws -> SpoolManifest {
            let writer = try FrameSpoolWriter(sessionID: id, root: root)
            XCTAssertTrue(writer.offer(jpeg: Data("picture-of-\(id)".utf8), width: 4, height: 3, meta: meta("f00000", at: 100)))
            let finished = await writer.finish()
            return try XCTUnwrap(finished.manifest)
        }
        let one = try await spool("SESSION-D"), other = try await spool("SESSION-E")
        XCTAssertEqual(one.digest, try XCTUnwrap(FrameSpool.manifest(for: "SESSION-D", root: root)).digest)
        XCTAssertNotEqual(one.digest, other.digest)
        XCTAssertEqual(one.digest.count, 64)
    }

    // MARK: - What is thrown away

    func testSweepRemovesUnfinishedDeletedAndExpiredScansAndNothingElse() async throws {
        func finished(_ id: String) async throws {
            let writer = try FrameSpoolWriter(sessionID: id, root: root)
            _ = writer.offer(jpeg: Data("x".utf8), width: 1, height: 1, meta: meta("f00000", at: 100))
            _ = await writer.finish()
        }
        try await finished("KEPT")
        try await finished("ROW-DELETED")
        try await finished("EXPIRED")
        _ = try FrameSpoolWriter(sessionID: "UNFINISHED", root: root)   // a scan the app died during
        let now = Date()
        // A moment later nothing is removed: the row of a scan saved just now may not exist yet.
        XCTAssertEqual(FrameSpool.sweep(keeping: ["KEPT", "EXPIRED"], now: now.addingTimeInterval(60), root: root), FrameSpool.Sweep())
        // Two hours later the unfinished scan and the one whose row is gone are removed.
        let later = FrameSpool.sweep(keeping: ["KEPT", "EXPIRED"], now: now.addingTimeInterval(7200), root: root)
        XCTAssertEqual(Set(later.orphans), ["ROW-DELETED", "UNFINISHED"])
        XCTAssertTrue(later.expired.isEmpty)
        XCTAssertNotNil(FrameSpool.manifest(for: "KEPT", root: root))
        // Past the keeping time, a scan's frames go even though its row is still there; the row is told.
        let afterKeeping = FrameSpool.sweep(keeping: ["KEPT", "EXPIRED"], now: now.addingTimeInterval(FrameSpool.retention + 60), root: root)
        XCTAssertEqual(Set(afterKeeping.expired), ["KEPT", "EXPIRED"])
        XCTAssertNil(FrameSpool.manifest(for: "KEPT", root: root))
    }

    func testAManifestWhoseFilesAreMissingIsNotIntact() async throws {
        let writer = try FrameSpoolWriter(sessionID: "SESSION-F", root: root)
        _ = writer.offer(jpeg: Data("picture".utf8), width: 4, height: 3, meta: meta("f00000", at: 100))
        let finished = await writer.finish()
        let manifest = try XCTUnwrap(finished.manifest)
        XCTAssertTrue(FrameSpool.isIntact(manifest, root: root))
        try FileManager.default.removeItem(at: FrameSpool.folder(for: "SESSION-F", root: root).appending(path: "f00000.jpg"))
        XCTAssertFalse(FrameSpool.isIntact(manifest, root: root), "recovery check 1: half an input is not an input")
    }

    func testTheHeroTurnFollowsTheInterface() {
        XCTAssertEqual(CaptureRecorder.heroRotationDeg(for: .portrait), 90)
        XCTAssertEqual(CaptureRecorder.heroRotationDeg(for: .landscapeRight), 0)
        XCTAssertEqual(CaptureRecorder.heroRotationDeg(for: .landscapeLeft), 180)
        XCTAssertEqual(CaptureRecorder.heroRotationDeg(for: .portraitUpsideDown), 270)
    }
}
