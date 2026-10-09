import XCTest
@testable import CaptureCore

/// ADR-0020: the record keeps poses at most 10 Hz, plus the frames that matter whatever the clock says.
final class PoseLogRateTests: XCTestCase {
    func testOneFrameInTenAtSixtyFps() {
        var kept = 0, last: TimeInterval?
        for i in 0..<600 {   // ten seconds at 60 fps
            let t = Double(i) / 60
            if CaptureRecorder.keepsFrame(at: t, lastKept: last, stateChanged: false, locksAnchor: false) { kept += 1; last = t }
        }
        XCTAssertEqual(kept, 100, "ten seconds at 10 Hz")
    }

    func testTheFirstTheAnchorAndEveryStateChangeAreKept() {
        XCTAssertTrue(CaptureRecorder.keepsFrame(at: 0, lastKept: nil, stateChanged: false, locksAnchor: false), "first frame")
        XCTAssertFalse(CaptureRecorder.keepsFrame(at: 0.016, lastKept: 0, stateChanged: false, locksAnchor: false), "16 ms later")
        XCTAssertTrue(CaptureRecorder.keepsFrame(at: 0.016, lastKept: 0, stateChanged: false, locksAnchor: true), "anchor frame")
        XCTAssertTrue(CaptureRecorder.keepsFrame(at: 0.016, lastKept: 0, stateChanged: true, locksAnchor: false), "tracking changed")
        XCTAssertTrue(CaptureRecorder.keepsFrame(at: 0.1, lastKept: 0, stateChanged: false, locksAnchor: false), "exactly 100 ms")
    }

    /// With the heading filter off the compass reports many times a second whether or not the phone turns; the
    /// record and the screen take ten of them a second.
    func testCompassReadingsAreKeptAtTenASecond() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var kept = 0, last: Date?
        for i in 0..<300 {   // five seconds at 60 a second
            let at = start + Double(i) / 60
            if CaptureRecorder.keepsHeading(at: at, lastKept: last) { kept += 1; last = at }
        }
        XCTAssertEqual(kept, 50)
        XCTAssertTrue(CaptureRecorder.keepsHeading(at: start, lastKept: nil), "the first reading")
        XCTAssertFalse(CaptureRecorder.keepsHeading(at: start + 0.05, lastKept: start))
        XCTAssertTrue(CaptureRecorder.keepsHeading(at: start + 0.1, lastKept: start))
        XCTAssertTrue(CaptureRecorder.keepsHeading(at: start - 5, lastKept: start), "a clock stepped back")
    }
}
