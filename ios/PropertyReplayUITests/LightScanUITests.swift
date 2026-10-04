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
        XCTAssertTrue(element(containing: "frames from this scan are kept on this device for 14 days").exists, "the frames are kept, and for how long is said")
        tap(app.buttons["lightScanDone"])
        XCTAssertTrue(app.staticTexts["1 recorded"].waitForExistence(timeout: 8))
        // Back on the property the scan is a row with its picture; its status is worked out from the scan, and opening
        // it shows the hero the scan is remembered by.
        tap(app.navigationBars.buttons.firstMatch)
        let status = "Light scan · camera covered 100% of the winter sun path · sunlight not calculated"
        let row = element(containing: status)
        XCTAssertTrue(row.waitForExistence(timeout: 8), "the row says what the scan is")
        snapshot("4-row")
        row.tap()
        XCTAssertTrue(app.staticTexts["Status"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.images.firstMatch.exists || app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'photo'")).firstMatch.exists, "the hero is on the scan's page")
        snapshot("5-scan-detail")
    }

    /// In Chinese the sentence reads "…覆盖了冬季阳光路径的 100%": until 2026-10-04 its two arguments were swapped.
    func testTheStatusLineReadsRightInChinese() {
        launch(["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"])
        openTab("房产")
        tap(app.staticTexts["12 Example Street"].firstMatch)
        tap(app.buttons["扫描光线"])
        tap(app.buttons["开始"])
        tap(app.buttons["保存"].firstMatch)
        if app.buttons["仍然保存"].waitForExistence(timeout: 3) { app.buttons["仍然保存"].tap() }
        tap(app.buttons["lightScanDone"])
        XCTAssertTrue(element(containing: "路径的 ").waitForExistence(timeout: 10))
        XCTAssertTrue(element(containing: "光线扫描 · 镜头覆盖了冬季阳光路径的 ").exists, "the question comes before the percentage")
        snapshot("zh-row")
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
