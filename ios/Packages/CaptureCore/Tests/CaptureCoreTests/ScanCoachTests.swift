import Foundation
import simd
import NorthResolver
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
        yaw.add(HeadingSample(trueHeading: 200, magneticHeading: 200, headingAccuracy: 5, sampledAt: now + 9), cameraAzimuthARDeg: 10, cameraPitchDeg: 80)
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

    private func reading(_ delta: Double, at i: Int, from start: Date, accuracy: Double = 10) -> HeadingSample {
        HeadingSample(trueHeading: delta, magneticHeading: delta, headingAccuracy: accuracy, sampledAt: start + Double(i) / 10)
    }

    /// A window of recent readings follows the compass wherever it wanders; the whole session does not.
    func testTheWholeSessionOutweighsTheLastFewSeconds() throws {
        var yaw = LiveYaw()
        let now = Date()
        for i in 0..<200 { yaw.add(reading(100, at: i, from: now), cameraAzimuthARDeg: 0, cameraPitchDeg: 0) }
        for i in 200..<270 { yaw.add(reading(130, at: i, from: now), cameraAzimuthARDeg: 0, cameraPitchDeg: 0) }   // seven seconds adrift
        XCTAssertEqual(try XCTUnwrap(yaw.estimate).deltaDeg, 100, accuracy: 0.001)
    }

    /// Review LS02: 2400 readings one way, then 1201 another. A third of the readings must not carry the answer,
    /// however long the scan runs; thinning the early ones while the late ones kept full weight once made it 130.
    func testALongScanStillCountsEveryReadingOnce() throws {
        var yaw = LiveYaw()
        let now = Date()
        var all: [(yawDeg: Double, sigmaDeg: Double)] = []
        for i in 0..<3601 {
            // Early readings straddle north (355…5), late ones sit 30° on, so the seam is in the test too.
            let delta = i < 2400 ? [355.0, 0, 5][i % 3] : 30
            let accuracy = i < 2400 ? 10.0 : 14
            yaw.add(reading(delta, at: i, from: now, accuracy: accuracy), cameraAzimuthARDeg: 0, cameraPitchDeg: 0)
            all.append((delta, accuracy))
            // Worked out on every reading up to 512, then on every eighth: at those counts it is the full merge.
            guard i + 1 >= 3, i + 1 <= 512 || (i + 1).isMultiple(of: 8) else { continue }
            let e = try XCTUnwrap(yaw.estimate), full = NorthResolver.merge(all)
            XCTAssertEqual(e.samples, i + 1)
            XCTAssertEqual(e.deltaDeg, full.yawDeg, accuracy: 1e-9, "after \(i + 1) readings")
            XCTAssertEqual(e.sigmaDeg, full.sigmaDeg, accuracy: 1e-9, "after \(i + 1) readings")
        }
        let e = try XCTUnwrap(yaw.estimate)
        XCTAssertEqual(e.samples, 3600, "at most seven readings behind")
        // 800 readings each at 355, 0 and 5, then 1200 at 30: the middle one of 3600 is a 5.
        XCTAssertEqual(e.deltaDeg, 5, accuracy: 1e-9, "the early two thirds still decide; thinned, it said 30")
    }

    /// Review LS01: the record starts its list of readings at Start; so does the path on screen.
    func testRecordingStartsFromItsOwnReadings() throws {
        var yaw = LiveYaw()
        let now = Date()
        for i in 0..<400 { yaw.add(reading(115, at: i, from: now), cameraAzimuthARDeg: 0, cameraPitchDeg: 0) }   // a long, biased preview
        XCTAssertEqual(try XCTUnwrap(yaw.estimate).deltaDeg, 115, accuracy: 1e-9)

        let lastOfPreview = reading(115, at: 400, from: now)   // delivered, not yet offered when Start is tapped
        yaw.beginRecording(after: lastOfPreview)
        XCTAssertNil(yaw.estimate, "no reading of this recording yet: nothing is drawn rather than the preview's guess")
        yaw.add(lastOfPreview, cameraAzimuthARDeg: 0, cameraPitchDeg: 0)
        yaw.add(lastOfPreview, cameraAzimuthARDeg: 0, cameraPitchDeg: 0)
        XCTAssertNil(yaw.estimate, "the preview's last reading is not taken after the start")

        var recorded: [(yawDeg: Double, sigmaDeg: Double)] = []
        for i in 401..<601 {
            let sample = reading(100, at: i, from: now)
            yaw.add(sample, cameraAzimuthARDeg: 0, cameraPitchDeg: 0)
            yaw.add(sample, cameraAzimuthARDeg: 0, cameraPitchDeg: 0)   // the same reading on the next frame
            recorded.append((100, 10))
        }
        let e = try XCTUnwrap(yaw.estimate)
        XCTAssertEqual(e.samples, 200, "each reading once")
        XCTAssertEqual(e.deltaDeg, NorthResolver.merge(recorded).yawDeg, accuracy: 1e-9)
        XCTAssertEqual(e.deltaDeg, 100, accuracy: 1e-9)
    }
}
