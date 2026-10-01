import XCTest
@testable import PropertyModel

final class SyncStatusTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    func testNothingIsClaimedBeforeSomethingFinishes() {
        var status = SyncStatus()
        XCTAssertEqual(status.summary, .nothingYet)
        status.record(.send, finishedAt: nil, succeeded: false, reason: nil)
        XCTAssertEqual(status.summary, .working, "running is not done")
        status.record(.send, finishedAt: t0, succeeded: true, reason: nil)
        XCTAssertEqual(status.summary, .lastSucceeded(sent: t0, received: nil))
        XCTAssertTrue(status.inProgress.isEmpty)
    }

    func testAFailureShowsUntilTheSameKindSucceedsLater() {
        var status = SyncStatus()
        status.record(.send, finishedAt: t0, succeeded: true, reason: nil)
        status.record(.send, finishedAt: t0 + 60, succeeded: false, reason: "quota exceeded")
        XCTAssertEqual(status.summary, .failed(.init(kind: .send, at: t0 + 60, reason: "quota exceeded")))
        status.record(.receive, finishedAt: t0 + 90, succeeded: true, reason: nil)
        if case .failed(let failure) = status.summary { XCTAssertEqual(failure.kind, .send) } else { XCTFail("receiving fine does not mean sending works") }
        status.record(.send, finishedAt: t0 + 120, succeeded: true, reason: nil)
        XCTAssertEqual(status.summary, .lastSucceeded(sent: t0 + 120, received: t0 + 90))
    }

    func testTwoKindsFailingAreRememberedSeparately() {
        var status = SyncStatus()
        status.record(.send, finishedAt: t0, succeeded: false, reason: "quota exceeded")
        status.record(.receive, finishedAt: t0 + 30, succeeded: false, reason: "network lost")
        if case .failed(let failure) = status.summary { XCTAssertEqual(failure.kind, .receive, "the latest failure is the one shown") } else { XCTFail() }
        status.record(.receive, finishedAt: t0 + 60, succeeded: true, reason: nil)
        XCTAssertEqual(status.summary, .failed(.init(kind: .send, at: t0, reason: "quota exceeded")),
                       "receiving again must not hide that sending still fails")
        status.record(.send, finishedAt: t0 + 90, succeeded: true, reason: nil)
        XCTAssertEqual(status.summary, .lastSucceeded(sent: t0 + 90, received: t0 + 60))
    }

    func testEventsReportedOutOfOrderDoNotRewindTheStatus() {
        var status = SyncStatus()
        status.record(.send, finishedAt: t0 + 60, succeeded: true, reason: nil)
        status.record(.send, finishedAt: t0, succeeded: false, reason: "an older attempt, reported late")
        XCTAssertEqual(status.summary, .failed(.init(kind: .send, at: t0, reason: "an older attempt, reported late")),
                       "a failure is never dropped silently; the next success of its kind clears it")
        status.record(.send, finishedAt: t0 + 30, succeeded: true, reason: nil)
        XCTAssertEqual(status.summary, .lastSucceeded(sent: t0 + 60, received: nil), "an older success does not move the time back")
    }

    func testSetupSuccessIsNotASync() {
        var status = SyncStatus()
        status.record(.setup, finishedAt: t0, succeeded: true, reason: nil)
        XCTAssertEqual(status.summary, .nothingYet, "the mirror starting up has sent and received nothing")
        status.record(.setup, finishedAt: t0 + 5, succeeded: false, reason: "not signed in")
        if case .failed(let failure) = status.summary { XCTAssertEqual(failure.reason, "not signed in") } else { XCTFail() }
    }
}
