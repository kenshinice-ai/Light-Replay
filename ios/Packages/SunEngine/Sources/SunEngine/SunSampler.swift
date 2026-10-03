import Foundation

/// A calendar day in the scene's own time zone (docs/06 §1: replay abroad still uses the property's zone).
public struct LocalDay: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public static func < (a: LocalDay, b: LocalDay) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }

    /// Midnight to midnight in `timeZone`: 23 or 25 hours on daylight-saving changes.
    public func interval(in timeZone: TimeZone) -> DateInterval {
        let calendar = Self.calendar(timeZone)
        let start = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return DateInterval(start: start, end: end)
    }

    public func adding(days: Int, in timeZone: TimeZone) -> LocalDay {
        let calendar = Self.calendar(timeZone)
        let date = calendar.date(byAdding: .day, value: days, to: interval(in: timeZone).start)!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return LocalDay(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Every day from `self` through `last`, inclusive.
    public func through(_ last: LocalDay, in timeZone: TimeZone) -> [LocalDay] {
        var days: [LocalDay] = []
        var d = self
        while d <= last {
            days.append(d)
            d = d.adding(days: 1, in: timeZone)
        }
        return days
    }

    static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

public struct SunSample: Sendable, Equatable {
    public let date: Date
    public let position: SunPosition
}

/// Sampling (docs/06 §3): a fixed step from local midnight; only instants with the sun above the horizon count.
public enum SunSampler {
    public static let defaultStepMinutes = 5

    public static func samples(on day: LocalDay, latitude: Double, longitude: Double, timeZone: TimeZone,
                               stepMinutes: Int = defaultStepMinutes) -> [SunSample] {
        let interval = day.interval(in: timeZone)
        return stride(from: interval.start, to: interval.end, by: TimeInterval(stepMinutes * 60)).compactMap { date in
            let p = SolarPosition.compute(at: date, latitude: latitude, longitude: longitude)
            return p.elevationDeg > 0 ? SunSample(date: date, position: p) : nil
        }
    }

    /// "HH:mm" in the scene's zone; outputs are whole minutes (docs/06 §8).
    public static func clock(_ date: Date, in timeZone: TimeZone) -> String {
        let c = LocalDay.calendar(timeZone).dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }
}
