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
}
