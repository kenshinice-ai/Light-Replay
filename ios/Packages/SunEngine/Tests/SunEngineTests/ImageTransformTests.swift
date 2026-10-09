import XCTest
import simd
@testable import SunEngine

/// The stored-image transform against the Python reference (engine/tests/fixtures/image-transform-cases.json) and
/// against two physical facts that do not come from the specification.
final class ImageTransformTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Point: Decodable { let native: [Double]; let encoded: [Double] }
        struct Case: Decodable {
            let native_size: [Double]; let crop: [Double]; let scale: Double; let rotation_deg: Int
            let encoded_size: [Double]; let points: [Point]
        }
        let cases: [Case]
    }

    private func fixture() throws -> Fixture {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appending(path: "engine/tests/fixtures/image-transform-cases.json")))
    }

    func testEveryCaseMatchesTheReferenceBothWays() throws {
        let cases = try fixture().cases
        XCTAssertEqual(cases.count, 5)
        for c in cases {
            let t = ImageTransform(nativeWidth: c.native_size[0], nativeHeight: c.native_size[1], cropX: c.crop[0], cropY: c.crop[1],
                                   cropWidth: c.crop[2], cropHeight: c.crop[3], scale: c.scale, rotationDeg: c.rotation_deg)
            XCTAssertEqual(t.encodedSize.x, c.encoded_size[0], accuracy: 1e-9)
            XCTAssertEqual(t.encodedSize.y, c.encoded_size[1], accuracy: 1e-9)
            for p in c.points {
                let there = t.encoded(SIMD2(p.native[0], p.native[1]))
                XCTAssertEqual(there.x, p.encoded[0], accuracy: 1e-9)
                XCTAssertEqual(there.y, p.encoded[1], accuracy: 1e-9)
                let back = t.native(there)
                XCTAssertEqual(back.x, p.native[0], accuracy: 1e-9)
                XCTAssertEqual(back.y, p.native[1], accuracy: 1e-9)
            }
        }
    }

    func testAQuarterTurnClockwisePutsTheTopLeftCornerTopRight() {
        let t = ImageTransform(nativeWidth: 400, nativeHeight: 300, scale: 1, rotationDeg: 90)
        XCTAssertEqual(t.encodedSize, SIMD2(300, 400))
        XCTAssertEqual(t.encoded(SIMD2(0, 0)), SIMD2(300, 0))
        XCTAssertEqual(t.encoded(SIMD2(400, 0)), SIMD2(300, 400))
    }

    /// Review R01's acceptance: the same direction lands on the same spot of the scene whatever size the frame was
    /// stored at. A direction projected with the scaled camera is the native projection carried through the transform.
    func testTheSameDirectionAtAnyStoredSize() {
        let native = PinholeCamera.looking(azimuthDeg: 20, altitudeDeg: 25, horizontalFOVDeg: 68, imageWidth: 1920, imageHeight: 1440)
        let direction = SkyDirection.vector(azimuthDeg: 31, altitudeDeg: 33)
        let inNative = native.pixel(of: direction)!
        for scale in [1.0, 0.5, 960.0 / 1920.0, 0.25] {
            let t = ImageTransform(nativeWidth: 1920, nativeHeight: 1440, scale: scale)
            let small = t.camera(native)!.pixel(of: direction)!
            XCTAssertEqual(simd_distance(small, t.encoded(inNative)), 0, accuracy: 1e-9)
            XCTAssertEqual(simd_distance(t.native(small), inNative), 0, accuracy: 1e-9)
        }
        XCTAssertNil(ImageTransform(nativeWidth: 1920, nativeHeight: 1440, scale: 1, rotationDeg: 90).camera(native))
    }

    /// Held upright, the phone's sensor image is on its side: the hero is stored turned a quarter clockwise. A point
    /// straight above the camera's aim in the world must end up above the centre of the upright picture.
    func testUpInTheWorldIsUpInAnUprightHero() {
        // Portrait: the camera's x axis (native "right") points down in the world, so native +x is world down.
        let forward = SkyDirection.vector(azimuthDeg: 0, altitudeDeg: 10)
        let worldUp = SIMD3<Double>(0, 1, 0)
        let right = simd_normalize(simd_cross(forward, worldUp))
        let up = simd_cross(right, forward)
        let camera = PinholeCamera(rotation: simd_double3x3(columns: (-up, right, -forward)), fx: 1450, fy: 1450, cx: 960, cy: 720,
                                   imageWidth: 1920, imageHeight: 1440)
        let hero = ImageTransform(nativeWidth: 1920, nativeHeight: 1440, scale: 1, rotationDeg: 90)
        let centre = hero.encoded(camera.pixel(of: forward)!)
        let above = hero.encoded(camera.pixel(of: SkyDirection.vector(azimuthDeg: 0, altitudeDeg: 20))!)
        XCTAssertEqual(above.x, centre.x, accuracy: 1e-6)
        XCTAssertLessThan(above.y, centre.y, "higher in the sky is nearer the top of the upright picture")
        XCTAssertEqual(hero.encodedSize, SIMD2(1440, 1920))
    }
}
