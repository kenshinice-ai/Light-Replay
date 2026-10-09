import Foundation
import SunEngine

/// How a question is named on screen. SunEngine keeps the English raw titles; the words a buyer reads live here so
/// they are in the catalog with everything else.
extension LightQuestion {
    var localizedTitle: String {
        switch self {
        case .winter: String(localized: "Winter sun")
        case .allYear: String(localized: "All-year sun")
        }
    }

    /// Lower-case, for the middle of a sentence ("the winter sun path").
    var localizedName: String {
        switch self {
        case .winter: String(localized: "winter sun")
        case .allYear: String(localized: "all-year sun")
        }
    }
}
