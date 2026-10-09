import XCTest

/// Review U01, U02: at the largest accessibility text size nothing a buyer needs may leave the window or collapse
/// into a column of letters. Frames come from the accessibility tree; screenshots are attached for the eye.
final class AdaptiveLayoutUITests: UITestCase {
    func testInspectAndItsEditorAtTheLargestText() {
        launch(Self.largestText)
        openInspect()
        assertInsideWindow(app.staticTexts["12 Example Street"].firstMatch, "address")
        assertInsideWindow(app.buttons["Room"], "room menu")
        assertInsideWindow(app.buttons["Capture"], "shutter")
        assertInsideWindow(app.buttons["Light"], "Light")
        snapshot("large-inspect")

        tap(app.buttons["Add test photo (simulator)"])
        for name in ["Save", "Discard", "Like", "Concern", "Ask"] { assertInsideWindow(app.buttons[name], name) }
        XCTAssertTrue(app.buttons["Save"].isHittable)
        XCTAssertTrue(app.buttons["Discard"].isHittable)
        snapshot("large-editor")
        tap(app.buttons["Save"])
        XCTAssertTrue(app.staticTexts["1 recorded"].waitForExistence(timeout: 5))
    }

    func testLightScanAndItsResultAtTheLargestText() {
        launch(Self.largestText + ["-syntheticSweepSpeed", "0"])
        openInspect()
        tap(app.buttons["Light"])
        let question = app.buttons["Question"]
        assertInsideWindow(question, "question menu")
        XCTAssertGreaterThan(question.frame.width, 200, "the question reads as words, not a column of letters")
        XCTAssertLessThan(question.frame.height, 220)
        assertInsideWindow(app.buttons["Close"], "Close")
        assertInsideWindow(app.buttons["Start"], "Start")
        snapshot("large-light-ready")
        // The paths' names are drawn, not accessible elements: these two pictures are looked at by a person
        // (review LS03 found "Shortest day · 21 Jun" running off both sides here).
        tap(app.buttons["Question"])
        tap(app.buttons["All-year sun"])
        assertInsideWindow(app.buttons["Start"], "Start")
        snapshot("large-light-ready-allyear")
        tap(app.buttons["Question"])
        tap(app.buttons["Winter sun"])

        tap(app.buttons["Start"])
        assertInsideWindow(app.buttons["Save"], "Save")
        snapshot("large-light-scanning")
        tap(app.buttons["Save"])
        tap(app.buttons["Save anyway"])
        assertInsideWindow(app.staticTexts["Scan saved"], "result title")
        assertInsideWindow(app.staticTexts["Sunlight not calculated yet"], "what is missing")
        let done = app.buttons["lightScanDone"]
        assertInsideWindow(done, "Done")
        XCTAssertTrue(done.isHittable)
        XCTAssertGreaterThan(done.frame.width, 200, "Done is a full button, not a clipped stub")
        snapshot("large-light-result")
        done.tap()
        XCTAssertTrue(app.staticTexts["1 recorded"].waitForExistence(timeout: 8))
    }

    /// The same screen in Chinese, where the names of the paths are other words of other widths.
    func testLightAtTheLargestTextInChinese() {
        launch(Self.largestText + ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-syntheticSweepSpeed", "0"])
        tap(app.buttons["房产"].firstMatch)
        tap(app.staticTexts["12 Example Street"].firstMatch)
        let inspect = app.buttons["开始看房"].firstMatch
        XCTAssertTrue(inspect.waitForExistence(timeout: 8))
        for _ in 0..<4 where !inspect.isHittable { app.swipeUp() }
        inspect.tap()
        allowSystemPrompts()
        tap(app.buttons["光线"])
        assertInsideWindow(app.buttons["开始"], "Start")
        snapshot("large-zh-light-ready")
        tap(app.buttons["问题"])
        tap(app.buttons["全年阳光"])
        assertInsideWindow(app.buttons["开始"], "Start")
        snapshot("large-zh-light-ready-allyear")
    }

    /// Lee, 2026-10-03: the phone may turn, people shoot landscape. Inspect's three actions, the editor's Save and
    /// Discard and the Light controls must stay inside the turned window and tappable. The camera picture and the
    /// saved photo follow the rotation coordinator (U03), which the simulator cannot show.
    func testInspectAndLightInLandscape() {
        launch(["-syntheticSweepSpeed", "0"])
        XCUIDevice.shared.orientation = .landscapeLeft
        openInspect()
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, window.height, "the window really turned")
        for name in ["Capture", "Light", "Dictate note"] {
            assertInsideWindow(app.buttons[name], name)
            XCTAssertTrue(app.buttons[name].isHittable, name)
        }
        assertInsideWindow(app.staticTexts["12 Example Street"].firstMatch, "address")
        snapshot("landscape-inspect")
        tap(app.buttons["Add test photo (simulator)"])
        for name in ["Save", "Discard"] {
            assertInsideWindow(app.buttons[name], name)
            XCTAssertTrue(app.buttons[name].isHittable, name)
        }
        // The photo sits beside the tags on a phone on its side; nothing has to be dragged into view (Lee, 2026-10-03).
        for name in ["Like", "Concern", "Ask"] {
            let frame = app.buttons[name].frame
            XCTAssertTrue(frame.minY >= window.minY && frame.maxY <= window.maxY, "\(name) is below the fold in landscape (y \(Int(frame.minY))…\(Int(frame.maxY)) of \(Int(window.height)))")
            XCTAssertTrue(app.buttons[name].isHittable, name)
        }
        snapshot("landscape-editor")
        tap(app.buttons["Discard"])
        tap(app.buttons["Light"])
        assertInsideWindow(app.buttons["Start"], "Start")
        assertInsideWindow(app.buttons["Question"], "question menu")
        snapshot("landscape-light")
        tap(app.buttons["Start"])
        assertInsideWindow(app.buttons["Save"], "Save")
        snapshot("landscape-light-scanning")
        tap(app.buttons["Close"])
        tap(confirmButton("Discard"))
        XCTAssertTrue(app.buttons["Capture"].waitForExistence(timeout: 8), "back on Inspect, still in landscape")
    }

    /// Group memory swiftui-searchable-empty-state-landscape-freeze: a search field over a screen that cannot scroll
    /// froze another family app on its side, main thread at 100%, nothing crashing. Every tab has to come up and
    /// answer in landscape with an empty library, and the map has to take a search with homes in it.
    func testEveryTabAnswersInLandscape() {
        launch(["-uitestEmpty"])
        XCUIDevice.shared.orientation = .landscapeLeft
        let landmarks = [("Properties", "No properties yet"), ("Inspect", "Add a property first"),
                         ("Compare", "Add properties first, in the Properties tab."), ("You", "Priorities"),
                         ("Home", "See beyond the inspection.")]
        for (tab, landmark) in landmarks {
            let started = Date()
            openTab(tab)
            XCTAssertTrue(element(containing: landmark).waitForExistence(timeout: 15), "\(tab) in landscape with an empty library")
            XCTAssertLessThan(Date().timeIntervalSince(started), 30, "\(tab) answered slowly in landscape")
        }
        snapshot("landscape-empty-home")

        launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        openTab("Properties")
        tap(app.buttons["Map"].firstMatch)
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 15), "the map under the search field")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("Box")
        XCTAssertTrue(element(containing: "1 of 3 homes match").waitForExistence(timeout: 15), "the map answers a search on its side")
        tap(app.buttons["List"].firstMatch)
        XCTAssertTrue(app.staticTexts["8 Sample Avenue"].waitForExistence(timeout: 15))
    }

    /// The four list screens at the largest text: titles whole, rows inside the window, search still offered.
    func testTabsAtTheLargestText() {
        launch(Self.largestText)
        XCTAssertTrue(app.staticTexts["Property Replay"].firstMatch.waitForExistence(timeout: 8), "the Home title is whole, not cut to an ellipsis")
        snapshot("large-home")
        tap(app.buttons["Properties"].firstMatch)
        XCTAssertTrue(app.searchFields["Address or suburb"].waitForExistence(timeout: 8), "search is offered without having to find it")
        tap(app.buttons["Inspect"].firstMatch)
        allowSystemPrompts()
        assertInsideWindow(app.staticTexts["Which home are you at?"].firstMatch, "the Inspect question")
        snapshot("large-inspect-tab")
        tap(app.buttons["Compare"].firstMatch)
        assertInsideWindow(app.staticTexts["Choose up to three."].firstMatch, "the Compare hint")
        snapshot("large-compare")
    }

    func testPropertyPageAtTheLargestText() {
        launch(Self.largestText)
        // The list first: in the iPad sidebar the row is narrow, and the badge used to break into "SAM-PLE".
        tap(app.buttons["Properties"].firstMatch)
        let badge = app.staticTexts["Sample property, fictional"].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(badge.frame.width, badge.frame.height * 1.5, "the badge stays on one line")
        assertInsideWindow(app.staticTexts["12 Example Street"].firstMatch, "the address in the list")
        snapshot("large-list")
        openProperty()
        assertInsideWindow(app.buttons["Inspect now"], "Inspect now")
        assertInsideWindow(app.buttons["Scan light"], "Scan light")
        assertInsideWindow(app.buttons["Edit"], "Edit")
        snapshot("large-property")
    }
}
