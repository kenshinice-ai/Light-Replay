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

    func testPropertyPageAtTheLargestText() {
        launch(Self.largestText)
        openProperty()
        assertInsideWindow(app.buttons["Inspect now"], "Inspect now")
        assertInsideWindow(app.buttons["Scan light"], "Scan light")
        assertInsideWindow(app.buttons["Edit"], "Edit")
        snapshot("large-property")
    }
}
