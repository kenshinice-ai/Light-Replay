import XCTest

/// Walks the Inspect draft paths the way a buyer does: capture, tag, save, discard, correct a note, read it back.
/// Added after the 2026-09-30 21:24 device crash on Save/Discard, which no unit test could reach.
final class InspectFlowUITests: UITestCase {
    func testPhotoAndNoteSaveDiscardAndDone() {
        launch()
        openInspect()

        // Photo → Save.
        tap(app.buttons["Add test photo (simulator)"])
        tap(app.buttons["Save"])
        XCTAssertTrue(app.staticTexts["1 recorded"].waitForExistence(timeout: 5))

        // Note → Discard, then Note → tag → Save (the model suggestion may land while the editor is up).
        tap(app.buttons["Add test note (simulator)"])
        tap(app.buttons["Discard"])
        XCTAssertTrue(app.staticTexts["1 recorded"].waitForExistence(timeout: 5))
        tap(app.buttons["Add test note (simulator)"])
        tap(app.buttons["Like"])
        tap(app.buttons["Save"])
        XCTAssertTrue(app.staticTexts["2 recorded"].waitForExistence(timeout: 5))

        // Done closes the inspection and returns to the property.
        tap(app.buttons["Done"])
        XCTAssertTrue(app.buttons["Inspect now"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "All 2 recorded").waitForExistence(timeout: 5))
    }

    /// Review U04: the words can be corrected and the first version is kept; the photo opens large.
    func testCorrectedNoteKeepsItsOriginalAndThePhotoOpensLarge() {
        launch()
        openInspect()
        tap(app.buttons["Add test note (simulator)"])
        let note = app.textViews["Your note"].exists ? app.textViews["Your note"] : app.textFields["Your note"]
        tap(note)
        note.typeText(" Checked twice.")
        tap(app.buttons["Save"])
        XCTAssertTrue(app.staticTexts["1 recorded"].waitForExistence(timeout: 5))
        tap(app.buttons["Add test photo (simulator)"])
        tap(app.buttons["Save"])
        XCTAssertTrue(app.staticTexts["2 recorded"].waitForExistence(timeout: 5))
        tap(app.buttons["Done"])

        tap(element(containing: "All 2 recorded"))
        tap(element(containing: "Checked twice."))
        XCTAssertTrue(element(containing: "You corrected this").waitForExistence(timeout: 5), "the first version is kept and said so")
        XCTAssertTrue(element(containing: "You said this on site, then corrected the words").exists)
        snapshot("note-detail")
        goBack()

        tap(app.staticTexts["Photo"].firstMatch)
        tap(element(containing: "Photo, Living"))
        XCTAssertTrue(app.buttons["Close photo"].waitForExistence(timeout: 5), "the photo opens full screen")
        snapshot("photo-viewer")
        app.buttons["Close photo"].tap()
        XCTAssertTrue(element(containing: "You photographed this on site").waitForExistence(timeout: 5))
    }

    /// Review U12: booking details live behind Edit; the page says plainly when there is no inspection time.
    func testEditingAPropertyChangesTheInspectionTimeNotTheAddress() {
        launch()
        openProperty("8 Sample Avenue")
        XCTAssertTrue(element(containing: "Inspection ").waitForExistence(timeout: 5))
        tap(app.buttons["Edit"])
        let booked = app.switches["Inspection booked"]
        XCTAssertTrue(booked.waitForExistence(timeout: 5))
        booked.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        tap(app.buttons["Save"])
        XCTAssertTrue(app.staticTexts["No inspection time set"].waitForExistence(timeout: 8))
        XCTAssertTrue(element(containing: "8 Sample Avenue, Box Hill").exists, "the address is untouched")
    }
}
