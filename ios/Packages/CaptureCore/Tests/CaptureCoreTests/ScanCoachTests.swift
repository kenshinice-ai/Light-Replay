import Foundation
import simd
import XCTest
@testable import CaptureCore

final class ScanCoachTests: XCTestCase {
    private func scanning() -> ScanStatus {
        var s = ScanStatus()
        s.isRecording = true
        s.trackingState = "normal"
        s.anchorLocked = true
        s.driftM = 0.02
        s.directionKnown = true
        s.coverage = 0.4
        s.gap = SIMD2(-40, 5)
        return s
    }

    func testOneInstructionInPriorityOrder() {
        var s = scanning()
        XCTAssertEqual(ScanCoach.prompt(for: s).text, "Turn left. The winter sun passes there.")
        s.gap = SIMD2(30, 2)
        XCTAssertEqual(ScanCoach.prompt(for: s).symbol, "arrow.right")
        s.gap = SIMD2(3, 25)
        XCTAssertEqual(ScanCoach.prompt(for: s).symbol, "arrow.up")
        s.gap = SIMD2(2, 4)
        XCTAssertEqual(ScanCoach.prompt(for: s).text, "Sweep slowly along the sun path.", "gap already on screen")

        s.directionKnown = false
        XCTAssertEqual(ScanCoach.prompt(for: s).symbol, "location.north.line")
        s.pathReady = false
        XCTAssertEqual(ScanCoach.prompt(for: s).text, "Working out the sun path…")
        s.locationKnown = false
        XCTAssertEqual(ScanCoach.prompt(for: s).symbol, "location", "no place, no sun path")
        s.locationKnown = true
        s.pathReady = true
        s.turnRateDegPerSec = 90
        XCTAssertEqual(ScanCoach.prompt(for: s).text, "Slower. Let the camera see the sky.")
        s.driftM = 0.3
        XCTAssertEqual(ScanCoach.prompt(for: s).symbol, "arrow.uturn.backward")
        s.anchorLocked = false
        XCTAssertEqual(ScanCoach.prompt(for: s).text, "Hold still for a moment.")
        s.trackingState = "limited:excessive_motion"
        XCTAssertEqual(ScanCoach.prompt(for: s).text, "Slow down.")
        s.isRecording = false
        XCTAssertEqual(ScanCoach.prompt(for: s).symbol, "figure.stand")
    }

    func testDoneOnlyWhenTheTargetIsReachedAndNothingIsWrong() {
        var s = scanning()
        s.coverage = 0.93
        XCTAssertEqual(ScanCoach.prompt(for: s).tone, .done)
        XCTAssertEqual(ScanCoach.prompt(for: s).text, "Sun path covered. Tap Save.", "covered, not a claim about sky or sunlight")
        s.pathReady = false
        XCTAssertNotEqual(ScanCoach.prompt(for: s).tone, .done, "no done while the path is being worked out")
        s.pathReady = true
        s.driftM = 0.5
        XCTAssertNotEqual(ScanCoach.prompt(for: s).tone, .done, "a viewpoint problem outranks done")
    }

    func testLiveYawAveragesAcrossNorthAndIgnoresBadReadings() throws {
        var yaw = LiveYaw()
        let now = Date()
        // Camera at AR azimuth 10°, compass 8°/12° → Δ ≈ 358°/2°, i.e. around 0 across the wrap.
        for (i, h) in [8.0, 12.0, 8.0, 12.0].enumerated() {
            yaw.add(HeadingSample(trueHeading: h, magneticHeading: h, headingAccuracy: 10, sampledAt: now + Double(i)),
                    cameraAzimuthARDeg: 10, cameraPitchDeg: 5)
        }
        let e = try XCTUnwrap(yaw.estimate)
        XCTAssertEqual(SIMD2(cos(e.deltaDeg * .pi / 180), sin(e.deltaDeg * .pi / 180)).x, 1, accuracy: 1e-3)
        XCTAssertEqual(e.sigmaDeg, 10, accuracy: 0.5, "reported accuracy dominates a 2° spread")
        XCTAssertEqual(e.samples, 4)

        yaw.add(HeadingSample(trueHeading: -1, magneticHeading: -1, headingAccuracy: -1, sampledAt: now), cameraAzimuthARDeg: 10, cameraPitchDeg: 0)
        yaw.add(HeadingSample(trueHeading: 200, magneticHeading: 200, headingAccuracy: 5, sampledAt: now), cameraAzimuthARDeg: 10, cameraPitchDeg: 80)
        XCTAssertEqual(yaw.estimate?.samples, 4, "invalid and steep readings are ignored")
        XCTAssertNil(LiveYaw().estimate)
    }

    /// What the scans of 2026-10-05 did: level readings first, then the camera goes up to the summer sun and the
    /// compass answers for the phone's top edge, about 180° round.
    func testLookingUpDoesNotTurnTheSunPathRound() throws {
        var yaw = LiveYaw()
        let now = Date()
        func add(_ delta: Double, pitch: Double, at i: Int) {
            yaw.add(HeadingSample(trueHeading: delta + 40, magneticHeading: delta + 28, headingAccuracy: 10, sampledAt: now + Double(i) / 10),
                    cameraAzimuthARDeg: 40, cameraPitchDeg: pitch)
        }
        for i in 0..<40 { add(100 + Double(i % 5) - 2, pitch: 10, at: i) }
        for i in 40..<140 { add(280, pitch: 31 + Double(i % 50), at: i) }
        let e = try XCTUnwrap(yaw.estimate)
        XCTAssertEqual(e.deltaDeg, 100, accuracy: 1)
        XCTAssertEqual(e.samples, 40)
        XCTAssertEqual(e.sigmaDeg, 10, accuracy: 0.5, "the flipped readings do not widen it either")
    }

    /// A window of recent readings follows the compass wherever it wanders; the whole session does not.
    func testTheWholeSessionOutweighsTheLastFewSeconds() throws {
        var yaw = LiveYaw()
        let now = Date()
        func add(_ delta: Double, at i: Int) {
            yaw.add(HeadingSample(trueHeading: delta, magneticHeading: delta, headingAccuracy: 10, sampledAt: now + Double(i) / 10),
                    cameraAzimuthARDeg: 0, cameraPitchDeg: 0)
        }
        for i in 0..<200 { add(100, at: i) }
        for i in 200..<270 { add(130, at: i) }   // seven seconds of a compass that has drifted
        XCTAssertEqual(try XCTUnwrap(yaw.estimate).deltaDeg, 100, accuracy: 0.001)

        for i in 270..<(LiveYaw.capacity + 400) { add(100, at: i) }
        let e = try XCTUnwrap(yaw.estimate)
        XCTAssertLessThanOrEqual(e.samples, LiveYaw.capacity)
        XCTAssertEqual(e.deltaDeg, 100, accuracy: 0.001, "thinning a long session keeps its answer")
    }
}
