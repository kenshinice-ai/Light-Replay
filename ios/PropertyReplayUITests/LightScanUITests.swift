import XCTest

/// The Light scan in the simulator: a scripted sweep stands in for ARKit (DEBUG), so the overlay, coverage, guidance
/// and save path run for real. Screenshots are attached for review.
final class LightScanUITests: UITestCase {
    private let covered = "Sun path covered. Tap Save."

    func testScanFromInspectSavesAnObservation() {
        launch()
        openInspect()
        tap(app.buttons["Light"])
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 8))
        snapshot("1-ready")
        tap(app.buttons["Start"])
        XCTAssertTrue(app.staticTexts[covered].waitForExistence(timeout: 60))
        snapshot("2-covered")
        tap(app.buttons["Save"])
        XCTAssertTrue(app.staticTexts["Scan saved"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Sunlight not calculated yet"].exists, "a saved scan is not a sunlight result")
        snapshot("3-saved")
        tap(app.buttons["lightScanDone"])
        XCTAssertTrue(app.staticTexts["1 recorded"].waitForExistence(timeout: 8))
    }

    func testLowCoverageAsksAndDiscardAsks() {
        launch(["-syntheticSweepSpeed", "0"])   // the pretend camera stays still
        openInspect()
        tap(app.buttons["Light"])
        tap(app.buttons["Start"])
        tap(app.buttons["Save"])
        XCTAssertTrue(app.buttons["Keep scanning"].waitForExistence(timeout: 5), "saving early asks first")
        app.buttons["Keep scanning"].tap()
        tap(app.buttons["Close"])
        tap(app.buttons["Discard"])
        XCTAssertTrue(app.staticTexts["0 recorded"].waitForExistence(timeout: 8), "discarded scans leave nothing")
    }

    /// Review U23: "covered" belongs to the question on screen. One pass covers the winter path, not the whole year.
    func testSwitchingQuestionTakesCoveredAwayAndGivesItBack() {
        launch(["-syntheticSweepPasses", "1"])
        openInspect()
        tap(app.buttons["Light"])
        tap(app.buttons["Start"])
        XCTAssertTrue(app.staticTexts[covered].waitForExistence(timeout: 40))

        tap(app.buttons["Question"])
        tap(app.buttons["All-year sun"])
        XCTAssertTrue(app.staticTexts[covered].waitForNonExistence(timeout: 10), "the all-year path is not covered by one low pass")
        tap(app.buttons["Save"])
        XCTAssertTrue(app.buttons["Keep scanning"].waitForExistence(timeout: 5), "and saving it asks, like any incomplete scan")
        app.buttons["Keep scanning"].tap()

        tap(app.buttons["Question"])
        tap(app.buttons["Winter sun"])
        XCTAssertTrue(app.staticTexts[covered].waitForExistence(timeout: 10))
        tap(app.buttons["Save"])
        XCTAssertTrue(app.staticTexts["Scan saved"].waitForExistence(timeout: 10))
    }

    /// Review U22: a failed save offers to save the same scan again, not to scan again.
    func testAFailedSaveIsRetriedWithoutRescanning() {
        launch(["-failFirstLightSave"])
        openInspect()
        tap(app.buttons["Light"])
        tap(app.buttons["Start"])
        XCTAssertTrue(app.staticTexts[covered].waitForExistence(timeout: 60))
        tap(app.buttons["Save"])
        XCTAssertTrue(app.staticTexts["Scan not saved"].waitForExistence(timeout: 10))
        snapshot("save-failed")
        tap(app.buttons["Try saving again"])
        XCTAssertTrue(app.staticTexts["Scan saved"].waitForExistence(timeout: 10))
        tap(app.buttons["lightScanDone"])
        XCTAssertTrue(app.staticTexts["1 recorded"].waitForExistence(timeout: 8))
    }
}
