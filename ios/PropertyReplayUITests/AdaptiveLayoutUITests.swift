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
