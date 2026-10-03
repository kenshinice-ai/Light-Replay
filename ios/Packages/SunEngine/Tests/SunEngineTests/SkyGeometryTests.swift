import Foundation
import simd
import XCTest
@testable import SunEngine

final class SkyGeometryTests: XCTestCase {
    private let tz = TimeZone(identifier: "Australia/Melbourne")!

    func testDirectionRoundTripAndConvention() {
        // −Z is azimuth 0, +X is 90 (clockwise from above), up is altitude 90 (docs/02 §3).
        XCTAssertEqual(SkyDirection.vector(azimuthDeg: 0, altitudeDeg: 0).z, -1, accuracy: 1e-12)
        XCTAssertEqual(SkyDirection.vector(azimuthDeg: 90, altitudeDeg: 0).x, 1, accuracy: 1e-12)
        XCTAssertEqual(SkyDirection.vector(azimuthDeg: 0, altitudeDeg: 90).y, 1, accuracy: 1e-12)
        for (az, alt) in [(0.0, 0.0), (37.5, 12.0), (181.0, -8.0), (359.5, 71.0)] {
            let back = SkyDirection.angles(of: SkyDirection.vector(azimuthDeg: az, altitudeDeg: alt))
            XCTAssertEqual(back.azimuthDeg, az, accuracy: 1e-9)
            XCTAssertEqual(back.altitudeDeg, alt, accuracy: 1e-9)
        }
        XCTAssertEqual(SkyDirection.azimuthDelta(from: 350, to: 10), 20)
        XCTAssertEqual(SkyDirection.azimuthDelta(from: 10, to: 350), -20)
    }

    func testCameraProjectsForwardToTheImageCentreAndUpToTheTop() throws {
        let camera = PinholeCamera.looking(azimuthDeg: 30, altitudeDeg: 10, horizontalFOVDeg: 60, imageWidth: 400, imageHeight: 800)
        let centre = try XCTUnwrap(camera.pixel(of: SkyDirection.vector(azimuthDeg: 30, altitudeDeg: 10)))
        XCTAssertEqual(centre.x, 200, accuracy: 1e-9)
        XCTAssertEqual(centre.y, 400, accuracy: 1e-9)
        let higher = try XCTUnwrap(camera.pixel(of: SkyDirection.vector(azimuthDeg: 30, altitudeDeg: 20)))
        XCTAssertLessThan(higher.y, 400, "higher in the sky is higher on screen")
        let right = try XCTUnwrap(camera.pixel(of: SkyDirection.vector(azimuthDeg: 40, altitudeDeg: 10)))
        XCTAssertGreaterThan(right.x, 200, "clockwise is to the right")
        XCTAssertNil(camera.pixel(of: SkyDirection.vector(azimuthDeg: 210, altitudeDeg: -10)), "behind the camera")
        // Half the horizontal field of view lands on the image edge.
        let edge = try XCTUnwrap(camera.pixel(of: SkyDirection.vector(azimuthDeg: 60, altitudeDeg: 10)))
        XCTAssertEqual(edge.x, 400, accuracy: 25, "30° right is near the right edge (altitude bends it slightly)")
    }

    func testSweepMarksOnlyWhatTheCameraSaw() {
        var sweep = SkySweep()
        let camera = PinholeCamera.looking(azimuthDeg: 0, altitudeDeg: 0, horizontalFOVDeg: 60, imageWidth: 600, imageHeight: 600)
        let added = sweep.add(camera, margin: 0)
        XCTAssertGreaterThan(added, 2_000)
        XCTAssertEqual(sweep.seenCount, added)
        XCTAssertTrue(sweep.isSeen(azimuthDeg: 0, altitudeDeg: 0))
        XCTAssertTrue(sweep.isSeen(azimuthDeg: 355, altitudeDeg: -8))
        XCTAssertFalse(sweep.isSeen(azimuthDeg: 180, altitudeDeg: 0), "behind")
        XCTAssertFalse(sweep.isSeen(azimuthDeg: 0, altitudeDeg: 50), "above a 60° square view")
        XCTAssertEqual(sweep.add(camera, margin: 0), 0, "looking again adds nothing")
    }

    func testCorridorProgressFollowsTheYawAndPointsAtTheGap() throws {
        let lat = -37.8136, lon = 144.9631
        let days = LightQuestion.winter.corridorDays(year: 2026, latitude: lat, timeZone: tz)
        let progress = CorridorProgress(corridor: SunCorridor(days: days, latitude: lat, longitude: lon, timeZone: tz, yawDeg: 0))
        XCTAssertFalse(progress.cells.isEmpty)

        // Winter sun in Melbourne: north-east to north-west, low. Sweep the northern sky low down with Δ = 0.
        var sweep = SkySweep()
        for az in stride(from: -90.0, through: 90.0, by: 10) {
            sweep.add(.looking(azimuthDeg: az, altitudeDeg: 12, horizontalFOVDeg: 60, imageWidth: 600, imageHeight: 800))
        }
        XCTAssertGreaterThan(progress.coverage(of: sweep, yawDeg: 0), 0.95)
        // The same sweep with the session turned round (Δ = 180) looked south: almost none of the corridor.
        XCTAssertLessThan(progress.coverage(of: sweep, yawDeg: 180), 0.1)

        // Having seen only the eastern end (sunrise side), the nearest gap is to the left, towards north.
        var eastOnly = SkySweep()
        eastOnly.add(.looking(azimuthDeg: 70, altitudeDeg: 12, horizontalFOVDeg: 60, imageWidth: 600, imageHeight: 800))
        let gap = try XCTUnwrap(progress.nearestGap(from: 70, altitudeDeg: 12, sweep: eastOnly, yawDeg: 0))
        XCTAssertLessThan(gap.x, -20, "turn left")
        XCTAssertNil(progress.nearestGap(from: 0, altitudeDeg: 12, sweep: sweep, yawDeg: 0).flatMap { abs($0.x) > 90 ? $0 : nil },
                     "after the full sweep any gap left is close by")
    }

    func testWinterFollowsTheHemisphere() {
        XCTAssertEqual(LightQuestion.winterSolstice(year: 2026, latitude: -37.8).month, 6)
        XCTAssertEqual(LightQuestion.winterSolstice(year: 2026, latitude: 51.5).month, 12)
        let winter = LightQuestion.winter.corridorDays(year: 2026, latitude: -37.8, timeZone: tz)
        XCTAssertEqual(winter.first?.description, "2026-05-10")
        XCTAssertEqual(winter.last?.description, "2026-08-02")
        XCTAssertEqual(winter.count, 13)
        XCTAssertGreaterThan(LightQuestion.allYear.corridorDays(year: 2026, latitude: -37.8, timeZone: tz).count, 50)
    }
}
