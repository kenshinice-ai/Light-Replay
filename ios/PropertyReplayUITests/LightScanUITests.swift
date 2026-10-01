import XCTest

/// The Light scan in the simulator: a scripted sweep stands in for ARKit (DEBUG), so the overlay, coverage, guidance
/// and save path run for real. Screenshots are attached for review.
final class LightScanUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()
    }

    private func allowSystemPrompts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Allow", "OK"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 1) { button.tap() }
        }
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), "missing \(element)", file: file, line: line)
        element.tap()
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openInspect() {
        tap(app.buttons["Properties"].firstMatch)
        tap(app.staticTexts["12 Example Street"].firstMatch)
        let inspect = app.buttons["Inspect now"].firstMatch
        for _ in 0..<4 where !inspect.isHittable { app.swipeUp() }
        tap(inspect)
        allowSystemPrompts()
    }

    func testScanFromInspectSavesAnObservation() {
        openInspect()
        tap(app.buttons["Light"])
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 8))
        sleep(2)
        snapshot("1-ready")
        tap(app.buttons["Start"])
        sleep(3)
        snapshot("2-scanning")
        XCTAssertTrue(app.staticTexts["That's enough sky. Tap Save."].waitForExistence(timeout: 40))
        snapshot("3-enough")
        tap(app.buttons["Save"])
        XCTAssertTrue(app.staticTexts["Scan saved"].waitForExistence(timeout: 10))
        snapshot("4-saved")
        tap(app.buttons["lightScanDone"])
        XCTAssertTrue(app.staticTexts["1 recorded"].waitForExistence(timeout: 8))
        snapshot("5-back-in-inspect")
    }

    func testLowCoverageAsksAndDiscardAsks() {
        app.terminate()
        app.launchArguments = ["-uitest", "-syntheticSweepSpeed", "0"]   // the pretend camera stays still
        app.launch()
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
}
