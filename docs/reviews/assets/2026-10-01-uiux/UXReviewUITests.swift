import XCTest
import UIKit
final class UXReviewUITests: XCTestCase {
 var app: XCUIApplication!
 override func setUpWithError() throws {
  continueAfterFailure = false
  XCUIDevice.shared.orientation = .portrait
  app = XCUIApplication(); app.launchArguments = ["-uitest", "-syntheticSweepSpeed", "0"]
 }
 override func tearDownWithError() throws { app.terminate(); XCUIDevice.shared.orientation = .portrait }
 func launch(large: Bool = false) {
  if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue] }
  app.launch()
 }
 func shot(_ name: String) {
  let s = XCTAttachment(screenshot: app.screenshot()); s.name = name; s.lifetime = .keepAlways; add(s)
  let a = XCTAttachment(string: "window=\(app.windows.firstMatch.frame)\n" + app.debugDescription); a.name=name+"-AX"; a.lifetime = .keepAlways; add(a)
 }
 func tap(_ e: XCUIElement) { XCTAssertTrue(e.waitForExistence(timeout: 8), "Missing \(e)"); e.tap() }
 func prompts() {
  let sb=XCUIApplication(bundleIdentifier:"com.apple.springboard")
  for t in ["Allow While Using App","Allow Once","Allow","OK"] { let b=sb.buttons[t]; if b.waitForExistence(timeout:0.5) { b.tap() } }
 }
 func openInspect() {
  tap(app.buttons["Properties"].firstMatch); tap(app.staticTexts["12 Example Street"].firstMatch)
  let b=app.buttons["Inspect now"].firstMatch
  for _ in 0..<6 where !b.isHittable { app.swipeUp() }
  tap(b); prompts()
 }
 func testPagesAndMap() {
  launch(); shot("01-home-portrait")
  tap(app.buttons["Properties"].firstMatch); shot("02-properties-list")
  tap(app.buttons["Map"].firstMatch); shot("03-properties-map")
  tap(app.buttons["Compare"].firstMatch); shot("04-compare-empty")
  tap(app.staticTexts["12 Example Street"].firstMatch); tap(app.staticTexts["8 Sample Avenue"].firstMatch)
  app.swipeUp(); shot("05-compare-two")
  tap(app.buttons["You"].firstMatch); shot("06-you")
  XCUIDevice.shared.orientation = .landscapeLeft; shot("07-you-landscape-left")
  tap(app.buttons["Properties"].firstMatch); shot("08-map-landscape-left")
  XCUIDevice.shared.orientation = .landscapeRight; shot("09-map-landscape-right")
 }
 func testInspectCardAndLight() {
  launch(); openInspect(); shot("10-inspect-portrait")
  tap(app.buttons["Add test photo (simulator)"]); shot("11-photo-card-portrait")
  XCUIDevice.shared.orientation = .landscapeLeft; shot("12-photo-card-landscape-left")
  XCUIDevice.shared.orientation = .landscapeRight; shot("13-photo-card-landscape-right")
  tap(app.buttons["Discard"]); tap(app.buttons["Light"]); tap(app.buttons["Start"]); shot("14-light-scanning")
  XCUIDevice.shared.orientation = .portrait; shot("15-light-scanning-portrait")
  tap(app.buttons["Save"]); shot("16-light-low-coverage-alert"); tap(app.buttons["Save anyway"])
  XCTAssertTrue(app.staticTexts["Scan saved"].waitForExistence(timeout:10)); shot("17-light-result")
 }
 func testLargeTextPages() {
  launch(large:true); shot("18-large-home")
  tap(app.buttons["Properties"].firstMatch); shot("19-large-list")
  tap(app.buttons["Map"].firstMatch); shot("20-large-map")
  tap(app.buttons["Compare"].firstMatch); shot("21-large-compare")
  tap(app.buttons["You"].firstMatch); shot("22-large-you")
 }
 func testLargeTextInspectAndLight() {
  launch(large:true); openInspect(); shot("23-large-inspect")
  tap(app.buttons["Add test photo (simulator)"]); shot("24-large-photo-card")
  tap(app.buttons["Discard"]); tap(app.buttons["Light"]); tap(app.buttons["Start"]); shot("25-large-light")
  XCUIDevice.shared.orientation = .landscapeLeft; shot("26-large-light-landscape")
  tap(app.buttons["Save"]); shot("27-large-light-alert"); tap(app.buttons["Save anyway"])
  XCTAssertTrue(app.staticTexts["Scan saved"].waitForExistence(timeout:10)); shot("28-large-light-result")
 }
 func settleLandscape() {
  XCUIDevice.shared.orientation = .landscapeRight
  let landscape=NSPredicate { _, _ in self.app.windows.firstMatch.frame.width > self.app.windows.firstMatch.frame.height }
  _ = XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:landscape,object:nil)],timeout:8)
  sleep(2) // UIKit rotation snapshots in the first pass were taken mid-transition.
 }
 func testStableLandscape() {
  launch(); tap(app.buttons["Properties"].firstMatch); settleLandscape(); shot("29-stable-landscape-list")
  tap(app.buttons["Map"].firstMatch); sleep(1); shot("30-stable-landscape-map")
  tap(app.buttons["List"].firstMatch); tap(app.staticTexts["12 Example Street"].firstMatch)
  let b=app.buttons["Inspect now"].firstMatch; for _ in 0..<6 where !b.isHittable { app.swipeUp() };tap(b);prompts()
  tap(app.buttons["Add test photo (simulator)"]);sleep(1);shot("31-stable-landscape-photo-card")
  tap(app.buttons["Discard"]);tap(app.buttons["Light"]);tap(app.buttons["Start"]);sleep(1);shot("32-stable-landscape-light")
 }
 func testDarkPagesAndKeyboard() {
  app.launchArguments += ["-ux-dark"]; launch();shot("33-dark-home")
  tap(app.buttons["Properties"].firstMatch);tap(app.buttons["Add"].firstMatch)
  tap(app.textFields.firstMatch);app.textFields.firstMatch.typeText("12 Example Street");shot("34-dark-add-keyboard")
  tap(app.buttons["Cancel"]);openInspect();tap(app.buttons["Add test photo (simulator)"]);shot("35-dark-photo-card")
  tap(app.buttons["Discard"]);tap(app.buttons["Light"]);tap(app.buttons["Start"]);shot("36-dark-light")
 }

}
