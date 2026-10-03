import XCTest

/// Shared rig for the simulator UI tests. The app runs with `-uitest`: an in-memory library with the fictional
/// samples, DEBUG stand-ins for camera and microphone, and a scripted pretend camera for the Light scan.
class UITestCase: XCTestCase {
    var app: XCUIApplication!

    /// The largest accessibility text size, the way the system passes it to an app.
    static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// A landscape test must not tilt the next one: the simulator keeps its orientation between tests.
    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    func launch(_ extra: [String] = []) {
        app.launchArguments = ["-uitest"] + extra
        app.launch()
    }

    /// Location and similar prompts belong to SpringBoard; accept them so they do not cover the controls.
    func allowSystemPrompts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Allow", "OK"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 1) { button.tap() }
        }
    }

    func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), "missing \(element)", file: file, line: line)
        element.tap()
    }

    func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A tab is a button in the tab bar; on an iPad turned to landscape the adaptable tab view shows the same tabs
    /// as rows of a sidebar, where the name is a static text.
    func openTab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[name].firstMatch
        if button.waitForExistence(timeout: 3) { button.tap(); return }
        tap(app.staticTexts[name].firstMatch, file: file, line: line)
    }

    func openProperty(_ shortAddress: String = "12 Example Street") {
        openTab("Properties")
        tap(app.staticTexts[shortAddress].firstMatch)
    }

    func openInspect() {
        openProperty()
        let inspect = app.buttons["Inspect now"].firstMatch
        XCTAssertTrue(inspect.waitForExistence(timeout: 8))
        for _ in 0..<4 where !inspect.isHittable { app.swipeUp() }
        inspect.tap()
        allowSystemPrompts()
    }

    /// Back out of the screen on top. On a wide window there are two navigation bars, so "the first button of the
    /// first bar" is not the back button; ask for it by what it is.
    func goBack() {
        let back = app.navigationBars.buttons.matching(NSPredicate(format: "label == 'Back' OR identifier == 'BackButton'")).firstMatch
        if back.waitForExistence(timeout: 3) { back.tap() } else { app.navigationBars.buttons.firstMatch.tap() }
    }

    /// The button inside a confirmation dialog. Since iOS 26 the dialog is a popover anchored to its trigger, which
    /// usually carries the same label, so "the button called Delete" is ambiguous: prefer the one in the popover.
    func confirmButton(_ label: String) -> XCUIElement {
        for container in [app.popovers, app.sheets, app.alerts] {
            let button = container.buttons[label].firstMatch
            if button.waitForExistence(timeout: 2) { return button }
        }
        return app.buttons[label].firstMatch
    }

    /// A button whose words were dropped is only as wide as its icon. Accessibility still finds it by label, so the
    /// width is what shows the words are really drawn (the unlabelled action buttons of 2026-10-01).
    func assertShowsItsWords(_ button: XCUIElement, _ name: String, minimumWidth: CGFloat = 110, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(button.waitForExistence(timeout: 8), "missing \(name)", file: file, line: line)
        XCTAssertGreaterThan(button.staticTexts.count, 0, "\(name) draws no text", file: file, line: line)
        XCTAssertGreaterThan(button.frame.width, minimumWidth, "\(name) is only \(Int(button.frame.width)) pt wide", file: file, line: line)
    }

    /// Existing is not enough: the whole element has to sit inside the window's width (review U01, U02).
    func assertInsideWindow(_ element: XCUIElement, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), "missing \(name)", file: file, line: line)
        let window = app.windows.firstMatch.frame, frame = element.frame
        XCTAssertTrue(frame.minX >= window.minX - 1 && frame.maxX <= window.maxX + 1,
                      "\(name) spans x \(Int(frame.minX))…\(Int(frame.maxX)), outside the \(Int(window.width)) pt window", file: file, line: line)
    }
}
