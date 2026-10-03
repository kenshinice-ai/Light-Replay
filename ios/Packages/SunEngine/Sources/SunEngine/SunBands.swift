import Foundation

/// NorthResolver's answer: `az_ar = az_true − deltaDeg`, with its one-sigma uncertainty.
public struct YawEstimate: Sendable, Equatable {
    public let deltaDeg: Double
    public let sigmaDeg: Double

    public init(deltaDeg: Double, sigmaDeg: Double) {
        self.deltaDeg = deltaDeg
        self.sigmaDeg = sigmaDeg
    }
}

public struct BandOptions: Sendable, Equatable {
    /// Monte Carlo draws of Δ (docs/06 §6, candidate 64).
    public var samples = 64
    /// Per-draw boundary jitter, uniform in ±this many degrees on both axes.
    public var boundaryJitterDeg = 1.0
    public var stepMinutes = SunSampler.defaultStepMinutes
    /// Fixed so the same inputs give the same bands (`analysis.versions.inputs_hash`).
    public var seed: UInt64 = 0x5EED_2026

    public init() {}
}

public struct BandSegment: Sendable, Equatable {
    public let from: Date
    public let to: Date
    public let state: SunState
    public var minutes: Int { Int((to.timeIntervalSince(from) / 60).rounded()) }
}

public struct DayBands: Sendable, Equatable {
    public let day: LocalDay
    public let segments: [BandSegment]

    public func minutes(_ state: SunState) -> Int { segments.filter { $0.state == state }.reduce(0) { $0 + $1.minutes } }
    /// Minutes with the sun up.
    public var daylightMinutes: Int { segments.reduce(0) { $0 + $1.minutes } }
    /// Stable direct sun only. This is the number a buyer may see as "measured" once the record passes (ADR-0013).
    public var directMinutes: Int { minutes(.direct) }
    /// Everything not stably blocked: unknown counted as sky (docs/06 §6 "上界").
    public var upperBoundMinutes: Int { daylightMinutes - minutes(.blocked) }
}

/// Time bands for one target point (docs/06 §6): every instant is judged under K draws of the direction uncertainty.
/// p ≥ 0.95 direct is direct, p ≤ 0.05 is blocked, anything between is sensitive, and one draw on an unknown or glass
/// cell makes the instant unknown. Nothing unknown is ever reported as direct.
public struct SunBands: Sendable {
    public static let version = "sunbands-0.1"

    public let grid: VisibilityGrid
    public let latitude: Double
    public let longitude: Double
    public let timeZone: TimeZone
    public let yaw: YawEstimate
    public let options: BandOptions
    private let draws: [(dYaw: Double, dAz: Double, dAlt: Double)]

    public init(grid: VisibilityGrid, latitude: Double, longitude: Double, timeZone: TimeZone, yaw: YawEstimate,
                options: BandOptions = BandOptions()) {
        self.grid = grid
        self.latitude = latitude
        self.longitude = longitude
        self.timeZone = timeZone
        self.yaw = yaw
        self.options = options
        if yaw.sigmaDeg == 0 && options.boundaryJitterDeg == 0 {
            draws = [(0, 0, 0)]
        } else {
            var rng = SplitMix64(seed: options.seed)
            let j = options.boundaryJitterDeg
            draws = (0..<max(1, options.samples)).map { _ in
                (rng.nextGaussian() * yaw.sigmaDeg, rng.nextUniform(-j, j), rng.nextUniform(-j, j))
            }
        }
    }

    /// nil while the sun is below the horizon.
    public func state(at date: Date) -> SunState? {
        let p = SolarPosition.compute(at: date, latitude: latitude, longitude: longitude)
        guard p.elevationDeg > 0 else { return nil }
        var direct = 0.0
        for d in draws {
            switch DirectSun.classify(azimuthARDeg: p.azimuthDeg - yaw.deltaDeg - d.dYaw + d.dAz,
                                      altitudeDeg: p.elevationDeg + d.dAlt, in: grid) {
            case .unknown: return .unknown
            case .direct: direct += 1
            case .sensitive: direct += 0.5
            case .blocked: break
            }
        }
        let share = direct / Double(draws.count)
        if share >= 0.95 { return .direct }
        if share <= 0.05 { return .blocked }
        return .sensitive
    }

    /// Segments for one local day at whole minutes. Samples every `stepMinutes`; where two samples differ, every
    /// minute in between is evaluated so entry and exit times are exact to the minute (docs/06 §3).
    public func bands(on day: LocalDay) -> DayBands {
        let interval = day.interval(in: timeZone)
        let step = TimeInterval(options.stepMinutes * 60)
        var segments: [BandSegment] = []
        var openStart = interval.start
        var openState = state(at: interval.start)
        func close(at t: Date, next: SunState?) {
            if let s = openState, t > openStart { segments.append(BandSegment(from: openStart, to: t, state: s)) }
            openStart = t
            openState = next
        }
        var previous = interval.start
        var t = interval.start.addingTimeInterval(step)
        while t <= interval.end {
            let s = t < interval.end ? state(at: t) : nil
            if s != openState || t == interval.end {
                var m = previous.addingTimeInterval(60)
                while m < t {
                    let sm = state(at: m)
                    if sm != openState { close(at: m, next: sm) }
                    m = m.addingTimeInterval(60)
                }
                if s != openState || t == interval.end { close(at: t, next: s) }
            }
            previous = t
            t = t.addingTimeInterval(step)
        }
        return DayBands(day: day, segments: segments)
    }
}

/// Small deterministic generator so bands are reproducible across runs and, later, against the Python reference.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func nextUnit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func nextUniform(_ low: Double, _ high: Double) -> Double { low + (high - low) * nextUnit() }
    /// Box–Muller; the second value is discarded to keep the stream simple.
    mutating func nextGaussian() -> Double {
        let u1 = max(nextUnit(), .leastNonzeroMagnitude)
        let u2 = nextUnit()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}
