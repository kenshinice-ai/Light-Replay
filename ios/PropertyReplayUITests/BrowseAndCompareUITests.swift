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

/// UI/UX review U15, U16, U21: settings that mean something today, a sync line that claims nothing it has not seen,
/// and an address sheet that is ready to type into.
final class SettingsAndInputUITests: UITestCase {
    func testAddingAHomeStartsInTheAddressField() {
        launch()
        tap(app.buttons["Properties"].firstMatch)
        tap(app.buttons["Add"].firstMatch)
        let field = app.textFields["Start typing an address"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        // No tap: the sheet puts the cursor in the field, so typing lands there.
        app.typeText("12 Exa")
        XCTAssertEqual(field.value as? String, "12 Exa")
        snapshot("add-typing")
        tap(app.buttons["Cancel"])
    }

    /// The suggestions are the rig's stand-ins for Apple Maps (two made-up homes), so this runs without the network.
    func testChoosingASuggestionKeepsItsPin() {
        launch()
        tap(app.buttons["Properties"].firstMatch)
        tap(app.buttons["Add"].firstMatch)
        let field = app.textFields["Start typing an address"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        app.typeText("5 Sam")
        let other = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sample Close'")).firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 5), "both matches are offered")
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sample Court'")).firstMatch)
        // Choosing rewrites the field. The pin has to survive that (it used to be cleared by the rewrite itself).
        XCTAssertTrue(element(containing: "Pin placed in Carlton").waitForExistence(timeout: 5), "the choice is confirmed where it was made")
        XCTAssertEqual(field.value as? String, "5 Sample Court, Carlton VIC 3053")
        XCTAssertFalse(other.exists, "the suggestions go once one is chosen")
        snapshot("add-chosen")
        tap(app.buttons["Save"])
        XCTAssertTrue(app.staticTexts["5 Sample Court"].waitForExistence(timeout: 8), "the home is in the list")
        XCTAssertTrue(app.staticTexts["Carlton"].exists, "with the suburb that came with its pin")
    }

    func testAnAddressTheMapCannotFindIsSavedAsTypedAfterAsking() {
        launch()
        tap(app.buttons["Properties"].firstMatch)
        tap(app.buttons["Add"].firstMatch)
        let field = app.textFields["Start typing an address"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        app.typeText("77 Nowhere Lane")
        let typed = (field.value as? String) ?? ""   // the simulator can drop a key; whatever arrived is "as typed"
        XCTAssertGreaterThanOrEqual(typed.count, 3)
        XCTAssertTrue(element(containing: "No Australian matches yet").waitForExistence(timeout: 5), "an empty list is explained")
        tap(app.buttons["Save"])
        let withoutPin = app.buttons["Save without pin"]
        XCTAssertTrue(withoutPin.waitForExistence(timeout: 8), "it stays and asks, rather than saving without a pin unasked")
        XCTAssertTrue(element(containing: "Couldn't find this address on the map").isHittable, "the reason is on screen, not behind the keyboard")
        snapshot("add-no-pin")
        withoutPin.tap()
        XCTAssertTrue(app.staticTexts[typed].waitForExistence(timeout: 8), "saved exactly as typed")
    }

    func testYouSaysWhereTheRecordsAreAndHidesNothingBehindJargon() {
        launch()
        tap(app.buttons["You"].firstMatch)
        XCTAssertTrue(app.switches["Haptics"].waitForExistence(timeout: 8), "one haptics switch, not 'on the timeline'")
        XCTAssertFalse(element(containing: "Phase 3").exists, "no roadmap talk in settings")
        XCTAssertFalse(element(containing: "spike").exists)
        let line = element(containing: "Kept on this device only")
        for _ in 0..<5 where !line.exists { app.swipeUp() }
        XCTAssertTrue(line.exists, "the test library is in memory on this device, and the page says so")
        snapshot("you")
    }
}
