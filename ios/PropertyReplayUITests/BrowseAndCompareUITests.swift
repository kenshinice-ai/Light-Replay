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

/// Lee, 2026-10-03: the interface is bilingual. Launched in Simplified Chinese, the tabs, the list, a property page,
/// Inspect and the Light coach speak Chinese; the main path falls back to English nowhere. The system's own prompts
/// stay in the simulator's language, which is English.
final class ChineseInterfaceUITests: UITestCase {
    func testMainScreensSpeakChinese() {
        launch(["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-syntheticSweepSpeed", "0"])
        for tab in ["首页", "房产", "看房", "比较", "我"] {
            XCTAssertTrue(app.buttons[tab].firstMatch.waitForExistence(timeout: 8), tab)
        }
        XCTAssertTrue(app.staticTexts["下一次看房"].firstMatch.waitForExistence(timeout: 5))
        snapshot("zh-home")
        tap(app.buttons["房产"].firstMatch)
        XCTAssertTrue(app.staticTexts["待看"].firstMatch.waitForExistence(timeout: 8), "status groups are Chinese (PropertyModel catalog)")
        XCTAssertTrue(app.staticTexts["示例房产，虚构"].firstMatch.exists, "the sample badge reads Chinese to VoiceOver")
        snapshot("zh-properties")
        tap(app.staticTexts["12 Example Street"].firstMatch)
        XCTAssertTrue(app.buttons["开始看房"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["扫描光线"].exists)
        XCTAssertTrue(app.buttons["写笔记"].exists)
        snapshot("zh-property")
        tap(app.buttons["开始看房"])
        allowSystemPrompts()
        XCTAssertTrue(app.buttons["拍照"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["光线"].exists)
        XCTAssertTrue(app.buttons["口述笔记"].exists)
        XCTAssertTrue(app.buttons["房间"].waitForExistence(timeout: 3) || element(containing: "客厅").exists, "the default room is named in Chinese")
        snapshot("zh-inspect")
        tap(app.buttons["光线"])
        XCTAssertTrue(element(containing: "站在你会坐的位置").waitForExistence(timeout: 8), "the coach speaks Chinese (CaptureCore catalog)")
        XCTAssertTrue(app.buttons["开始"].exists)
        XCTAssertTrue(element(containing: "冬季阳光").exists, "the question is named in Chinese")
        snapshot("zh-light")
        tap(app.buttons["关闭"])
        let discard = app.buttons["丢弃"]
        if discard.waitForExistence(timeout: 2) { discard.tap() }
        tap(app.buttons["完成"])
        tap(app.buttons["我"].firstMatch)
        XCTAssertTrue(app.switches["触感"].waitForExistence(timeout: 8))
        let kept = element(containing: "只保存在这台设备上")
        for _ in 0..<5 where !kept.exists { app.swipeUp() }
        XCTAssertTrue(kept.exists)
        snapshot("zh-you")
    }
}

/// Lee, 2026-10-03: School, Commute and Price comfort need a way in. An empty Compare cell opens the place to write
/// the first note, and the note counts in the cell.
final class NotesUITests: UITestCase {
    func testANoteWrittenFromAnEmptyCompareCellFillsIt() {
        launch()
        tap(app.buttons["You"].firstMatch)
        tap(app.staticTexts["What you care about"].firstMatch)
        tap(app.staticTexts["School"].firstMatch)
        tap(app.buttons["Compare"].firstMatch)
        tap(app.staticTexts["12 Example Street"].firstMatch)
        tap(app.staticTexts["8 Sample Avenue"].firstMatch)
        let empty = element(containing: "12 Example Street, School: Not recorded")
        XCTAssertTrue(empty.waitForExistence(timeout: 8), "the School row is there and honestly empty")
        empty.tap()
        tap(app.buttons["Add a note"])
        XCTAssertTrue(app.textViews["Your note"].waitForExistence(timeout: 8) || app.textFields["Your note"].waitForExistence(timeout: 2))
        app.typeText("Zoned for the primary we wanted")
        XCTAssertFalse(app.buttons["Room"].exists, "a note from the desk has no room")
        tap(app.buttons["Like"])
        tap(app.buttons["Save"])
        XCTAssertTrue(element(containing: "Zoned for the primary").waitForExistence(timeout: 8), "the note is listed behind the cell")
        snapshot("note-behind-cell")
        goBack()
        XCTAssertTrue(element(containing: "12 Example Street, School: 1 like").waitForExistence(timeout: 8), "the cell now counts the note")
        snapshot("compare-with-note")
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
