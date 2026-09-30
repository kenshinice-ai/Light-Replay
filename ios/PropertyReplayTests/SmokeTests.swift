import XCTest
@testable import PropertyReplay

final class SmokeTests: XCTestCase {
    func testBundleIdentifier() {
        XCTAssertEqual(Bundle(for: SmokeTests.self).bundleIdentifier?.hasPrefix("com.pwegroup.propertyreplay"), true)
    }
}
