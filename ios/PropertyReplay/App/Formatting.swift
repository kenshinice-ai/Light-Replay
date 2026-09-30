import Foundation

enum Formatting {
    static let inspectionDate: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
        return f
    }()

    static func distance(_ metres: Double) -> String {
        metres < 1000 ? String(format: "%.0f m", metres) : String(format: "%.1f km", metres / 1000)
    }
}
