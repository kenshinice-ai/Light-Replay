import XCTest
@testable import PropertyReplay

final class SmokeTests: XCTestCase {
    func testBundleIdentifier() {
        XCTAssertEqual(Bundle(for: SmokeTests.self).bundleIdentifier?.hasPrefix("com.pwegroup.propertyreplay"), true)
    }
}

/// Address suggestions stay in Australia even when Maps falls back to the world (found 2026-10-01).
final class AddressScopeTests: XCTestCase {
    func testSuggestionsAreKeptOnlyWhenTheyNameAustralia() {
        XCTAssertTrue(AddressCompleter.looksAustralian(title: "12 Smith St", subtitle: "Collingwood, VIC, Australia"))
        XCTAssertTrue(AddressCompleter.looksAustralian(title: "5 George St", subtitle: "Sydney NSW 2000"))
        XCTAssertTrue(AddressCompleter.looksAustralian(title: "3 Hay St", subtitle: "Perth WA"))
        XCTAssertFalse(AddressCompleter.looksAustralian(title: "EXA 北上尾, 23-1, Harashimmachi", subtitle: "Ageo, Saitama, Japan"))
        XCTAssertFalse(AddressCompleter.looksAustralian(title: "12 Pike St", subtitle: "Seattle, WA, United States"))
        XCTAssertFalse(AddressCompleter.looksAustralian(title: "12 Example Rd", subtitle: "Swansea, Wales"), "letters inside a word are not a state")
    }

    func testAPinAbroadIsNotAccepted() {
        XCTAssertTrue(AddressCompleter.isInAustralia(latitude: -37.8136, longitude: 144.9631))   // Melbourne
        XCTAssertTrue(AddressCompleter.isInAustralia(latitude: -12.4634, longitude: 130.8456))   // Darwin
        XCTAssertTrue(AddressCompleter.isInAustralia(latitude: -42.8821, longitude: 147.3272))   // Hobart
        XCTAssertFalse(AddressCompleter.isInAustralia(latitude: 35.97, longitude: 139.59))       // Saitama
        XCTAssertFalse(AddressCompleter.isInAustralia(latitude: -36.85, longitude: 174.76))      // Auckland
    }
}


/// Warning and error words have to be readable where they sit: 4.5:1 against a list row and a plain page, light and
/// dark. The standard system orange is about 2.2:1 on white.
final class TextColorTests: XCTestCase {
    func testWarningWordsReachFourPointFiveToOneOnTheirSurfaces() {
        let surfaces: [(String, UIColor)] = [("page", .systemBackground), ("row", .secondarySystemGroupedBackground)]
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            for (surfaceName, surface) in surfaces {
                for (name, color) in [("caution", UIColor.cautionText), ("problem", UIColor.problemText)] {
                    let ratio = Self.contrast(color.resolvedColor(with: traits), surface.resolvedColor(with: traits))
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name) words on a \(surfaceName), \(style == .dark ? "dark" : "light"): \(ratio):1")
                }
            }
            XCTAssertGreaterThanOrEqual(Self.contrast(.white, UIColor.problemFill.resolvedColor(with: traits)), 4.5, "white words on the storage banner")
        }
    }

    func testTheStandardOrangeIsWhyTheseExist() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        XCTAssertLessThan(Self.contrast(UIColor.systemOrange.resolvedColor(with: light), UIColor.systemBackground.resolvedColor(with: light)), 3.0)
    }

    /// WCAG 2 contrast ratio from sRGB components.
    static func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        func luminance(_ color: UIColor) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &alpha)
            func linear(_ c: CGFloat) -> Double {
                let v = Double(min(max(c, 0), 1))
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
