import XCTest

/// Walks the Inspect draft paths the way a buyer does: capture, tag, save, discard, leave with something unsaved.
/// Runs on the simulator with the DEBUG stand-ins for camera and microphone and an in-memory library (`-uitest`).
/// Added after the 2026-09-30 21:24 device crash on Save/Discard, which no unit test could reach.
final class InspectFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()
    }

    /// Location and similar prompts belong to SpringBoard; accept them so they do not cover the controls.
    private func allowSystemPrompts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Allow", "OK"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 1) { button.tap() }
        }
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "missing \(element)", file: file, line: line)
        element.tap()
    }

    private func openInspect() {
        tap(app.buttons["Properties"].firstMatch)
        tap(app.staticTexts["12 Example Street"].firstMatch)
        let inspect = app.buttons["Inspect now"].firstMatch
        for _ in 0..<4 where !inspect.isHittable { app.swipeUp() }
        tap(inspect)
        allowSystemPrompts()
    }

    func testPhotoAndNoteSaveDiscardAndDone() {
        openInspect()

        // Photo → Save.
        tap(app.buttons["Add test photo (simulator)"])
        tap(app.buttons["Save"])
        XCTAssertTrue(app.staticTexts["1 recorded"].waitForExistence(timeout: 5))

        // Note → Discard, then Note → tag → Save (the model suggestion may land while the card is up).
        tap(app.buttons["Add test note (simulator)"])
        tap(app.buttons["Discard"])
        XCTAssertTrue(app.staticTexts["1 recorded"].exists)
        tap(app.buttons["Add test note (simulator)"])
        tap(app.buttons["Like"])
        tap(app.buttons["Save"])
        XCTAssertTrue(app.staticTexts["2 recorded"].waitForExistence(timeout: 5))

        // Something unsaved, then Done: asked, discarded, back on the property.
        tap(app.buttons["Add test photo (simulator)"])
        tap(app.buttons["Done"])
        tap(app.buttons["Discard and finish"])
        XCTAssertTrue(app.buttons["Inspect now"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["All 2 recorded"].exists || app.staticTexts["All 2 recorded"].exists)
    }

    func testSaveAndFinishFromTheDoneDialog() {
        openInspect()
        tap(app.buttons["Add test note (simulator)"])
        tap(app.buttons["Done"])
        tap(app.buttons["Save and finish"])
        XCTAssertTrue(app.buttons["Inspect now"].waitForExistence(timeout: 5))
    }
}
