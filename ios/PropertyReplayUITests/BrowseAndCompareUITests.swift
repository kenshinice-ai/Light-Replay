import XCTest

/// UI/UX review U07, U09, U14: the same homes in List and Map, the detail beside them when the window is wide, and
/// a Compare table that names every kind of "nothing". Runs on iPhone and iPad; the wide-window checks apply to iPad.
final class BrowseAndCompareUITests: UITestCase {
    private var isWide: Bool { app.windows.firstMatch.frame.width >= 900 }

    func testAHomeOpensBesideTheListOnAWideWindow() {
        launch()
        openProperty("8 Sample Avenue")
        XCTAssertTrue(app.buttons["Inspect now"].waitForExistence(timeout: 8))
        XCTAssertTrue(element(containing: "8 Sample Avenue, Box Hill").exists, "the full address leads the page")
        assertShowsItsWords(app.buttons["Inspect now"], "Inspect now")
        assertShowsItsWords(app.buttons["Scan light"], "Scan light")
        if isWide {
            XCTAssertTrue(app.staticTexts["12 Example Street"].isHittable, "the list stays beside the detail")
            tap(app.staticTexts["12 Example Street"].firstMatch)
            XCTAssertTrue(element(containing: "12 Example Street, Brunswick").waitForExistence(timeout: 5), "choosing another home swaps the detail in place")
        }
        snapshot("home-detail")
    }

    func testSearchNarrowsListAndMapTogether() {
        launch()
        tap(app.buttons["Properties"].firstMatch)
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 3) { app.swipeDown() }
        tap(field)
        field.typeText("Box")
        XCTAssertTrue(app.staticTexts["8 Sample Avenue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["12 Example Street"].exists, "search hides the others")
        XCTAssertTrue(element(containing: "Showing 1 of 3").exists)
        snapshot("search-list")
        tap(app.buttons["Map"].firstMatch)
        XCTAssertTrue(element(containing: "1 of 3 homes match").waitForExistence(timeout: 8), "the map shows the same filtered set")
        snapshot("search-map")
    }

    func testCompareNamesEveryNothingAndOpensWhatWasRecorded() {
        launch(["-syntheticSweepSpeed", "0"])
        // One light scan at the first home, so one cell has something behind it.
        openInspect()
        tap(app.buttons["Light"])
        tap(app.buttons["Start"])
        tap(app.buttons["Save"])
        tap(app.buttons["Save anyway"])
        tap(app.buttons["lightScanDone"])
        tap(app.buttons["Done"])

        tap(app.buttons["Compare"].firstMatch)
        tap(app.staticTexts["12 Example Street"].firstMatch)
        tap(app.staticTexts["8 Sample Avenue"].firstMatch)
        XCTAssertTrue(element(containing: "Scanned, sunlight not calculated").waitForExistence(timeout: 8))
        XCTAssertTrue(element(containing: "Not recorded").exists)
        tap(app.staticTexts["3/21 Placeholder Road"].firstMatch)
        XCTAssertTrue(app.staticTexts["Three chosen. Remove one to add another."].waitForExistence(timeout: 5), "the limit is said, not silent")
        snapshot("compare-three")

        tap(element(containing: "Natural light: Scanned, sunlight not calculated"))
        XCTAssertTrue(element(containing: "Light scan").waitForExistence(timeout: 5), "a cell opens the records behind it")
        snapshot("compare-evidence")
    }
}
