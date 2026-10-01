import Foundation
import simd

/// Directions in the AR world frame (docs/02 §3): y up, azimuth measured clockwise from the session's −Z axis seen
/// from above, `az_ar = atan2(d_x, −d_z)`, `alt = asin(d_y)`. True azimuth is `az_ar + Δ` (docs/05 §4).
public enum SkyDirection {
    public static func vector(azimuthDeg az: Double, altitudeDeg alt: Double) -> SIMD3<Double> {
        let a = radians(az), e = radians(alt)
        return SIMD3(cos(e) * sin(a), sin(e), -cos(e) * cos(a))
    }

    public static func angles(of v: SIMD3<Double>) -> (azimuthDeg: Double, altitudeDeg: Double) {
        let d = simd_normalize(v)
        return (wrap360(degrees(atan2(d.x, -d.z))), degrees(asin(max(-1, min(1, d.y)))))
    }

    /// Signed smallest difference `to − from` in degrees, in (−180, 180].
    public static func azimuthDelta(from: Double, to: Double) -> Double {
        let d = pyMod(to - from + 180, 360) - 180
        return d == -180 ? 180 : d
    }
}

/// A pinhole camera as ARKit reports it (docs/02 §3): `rotation` maps camera axes to world axes (columns are the camera
/// x, y and z axes; the camera looks along −z, y up), intrinsics belong to the captured image in its native orientation.
public struct PinholeCamera: Sendable, Equatable {
    public var rotation: simd_double3x3
    public var fx: Double
    public var fy: Double
    public var cx: Double
    public var cy: Double
    public var imageWidth: Double
    public var imageHeight: Double

    public init(rotation: simd_double3x3, fx: Double, fy: Double, cx: Double, cy: Double, imageWidth: Double, imageHeight: Double) {
        self.rotation = rotation
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }

    /// Looking along a world direction with the image's y axis kept as close to world up as possible.
    public static func looking(azimuthDeg az: Double, altitudeDeg alt: Double, horizontalFOVDeg: Double,
                               imageWidth: Double, imageHeight: Double) -> PinholeCamera {
        let forward = SkyDirection.vector(azimuthDeg: az, altitudeDeg: alt)
        let worldUp = SIMD3<Double>(0, 1, 0)
        let right = simd_normalize(simd_cross(forward, abs(alt) > 89.9 ? SIMD3(0, 0, -1) : worldUp))
        let up = simd_cross(right, forward)
        let f = (imageWidth / 2) / tan(radians(horizontalFOVDeg) / 2)
        return PinholeCamera(rotation: simd_double3x3(columns: (right, up, -forward)), fx: f, fy: f,
                             cx: imageWidth / 2, cy: imageHeight / 2, imageWidth: imageWidth, imageHeight: imageHeight)
    }

    public var forward: SIMD3<Double> { -rotation.columns.2 }

    /// Pixel of a world direction (docs/02 §3 inverted: `u = cx + fx·x/s`, `v = cy − fy·y/s`, `s = −z`); nil behind.
    public func pixel(of direction: SIMD3<Double>) -> SIMD2<Double>? {
        let c = rotation.transpose * direction
        guard c.z < -1e-9 else { return nil }
        let s = -c.z
        return SIMD2(cx + fx * c.x / s, cy - fy * c.y / s)
    }

    /// True when the direction lands inside the image, `margin` (a fraction of each side) away from the edges.
    public func sees(_ direction: SIMD3<Double>, margin: Double = 0) -> Bool {
        guard let p = pixel(of: direction) else { return false }
        let mx = imageWidth * margin, my = imageHeight * margin
        return p.x >= mx && p.x <= imageWidth - mx && p.y >= my && p.y <= imageHeight - my
    }
}

/// Which sky cells the camera has looked at during a scan (AR frame, `VisibilityGrid` layout). Looking at a cell is not
/// knowing whether it is sky: this only drives coverage guidance; states come from segmentation (docs/04 §6).
public struct SkySweep: Sendable, Equatable {
    public private(set) var seen: [Bool]
    public private(set) var seenCount = 0

    public init() {
        seen = Array(repeating: false, count: VisibilityGrid.azimuthCells * VisibilityGrid.altitudeCells)
    }

    /// Marks every cell whose centre the camera sees, keeping `margin` of each image side out (edges segment worst).
    /// Returns how many cells were new.
    @discardableResult
    public mutating func add(_ camera: PinholeCamera, margin: Double = 0.08) -> Int {
        var added = 0
        let directions = Self.cellDirections
        for index in directions.indices where !seen[index] {
            if camera.sees(directions[index], margin: margin) {
                seen[index] = true
                added += 1
            }
        }
        seenCount += added
        return added
    }

    public func isSeen(azimuthDeg: Double, altitudeDeg: Double) -> Bool {
        guard let c = VisibilityGrid.cell(azimuthDeg: azimuthDeg, altitudeDeg: altitudeDeg) else { return false }
        return seen[c.alt * VisibilityGrid.azimuthCells + c.az]
    }

    /// Unit vector through each cell centre, row-major like `VisibilityGrid.states`.
    static let cellDirections: [SIMD3<Double>] = (0..<VisibilityGrid.altitudeCells).flatMap { alt in
        (0..<VisibilityGrid.azimuthCells).map { az in
            SkyDirection.vector(azimuthDeg: Double(az) + 0.5, altitudeDeg: VisibilityGrid.minimumAltitudeDeg + Double(alt) + 0.5)
        }
    }
}

/// How much of a question's sun corridor a sweep has looked at. The corridor is kept in the true-north frame so that
/// a better Δ later (compass settling, a light-patch tap) simply re-maps it; nothing already seen is lost.
public struct CorridorProgress: Sendable {
    /// Corridor cells in the true frame as (azimuth cell, altitude cell).
    public let cells: [(az: Int, alt: Int)]

    public init(corridor: SunCorridor) {
        cells = corridor.cells.enumerated().compactMap { index, inside in
            inside ? (index % VisibilityGrid.azimuthCells, index / VisibilityGrid.azimuthCells) : nil
        }
    }

    /// The AR-frame cell index of a true-frame cell for a given Δ.
    private func arIndex(_ cell: (az: Int, alt: Int), yawDeg: Double) -> Int {
        let az = VisibilityGrid.wrap(Int(wrap360(Double(cell.az) + 0.5 - yawDeg).rounded(.down)))
        return cell.alt * VisibilityGrid.azimuthCells + az
    }

    /// Fraction of corridor cells the camera has looked at, 0…1.
    public func coverage(of sweep: SkySweep, yawDeg: Double) -> Double {
        guard !cells.isEmpty else { return 0 }
        let seen = cells.reduce(0) { $0 + (sweep.seen[arIndex($1, yawDeg: yawDeg)] ? 1 : 0) }
        return Double(seen) / Double(cells.count)
    }

    /// The unseen corridor cell nearest to where the camera points, as (Δazimuth, Δaltitude) in degrees from the camera
    /// direction; nil when everything has been seen.
    public func nearestGap(from cameraAzimuthARDeg: Double, altitudeDeg: Double, sweep: SkySweep, yawDeg: Double) -> SIMD2<Double>? {
        var best: SIMD2<Double>?
        var bestDistance = Double.infinity
        let here = SkyDirection.vector(azimuthDeg: cameraAzimuthARDeg, altitudeDeg: altitudeDeg)
        for cell in cells where !sweep.seen[arIndex(cell, yawDeg: yawDeg)] {
            let azAR = wrap360(Double(cell.az) + 0.5 - yawDeg)
            let alt = VisibilityGrid.minimumAltitudeDeg + Double(cell.alt) + 0.5
            let distance = acos(max(-1, min(1, simd_dot(here, SkyDirection.vector(azimuthDeg: azAR, altitudeDeg: alt)))))
            if distance < bestDistance {
                bestDistance = distance
                best = SIMD2(SkyDirection.azimuthDelta(from: cameraAzimuthARDeg, to: azAR), alt - altitudeDeg)
            }
        }
        return best
    }
}

/// The question a scan answers (docs/04 §3). It decides the corridor the coverage gate counts and the arcs drawn.
public enum LightQuestion: String, CaseIterable, Sendable, Identifiable, Codable {
    /// The winter solstice ± 6 weeks, sunrise to sunset.
    case winter
    /// Every day of the year.
    case allYear

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .winter: "Winter sun"
        case .allYear: "All-year sun"
        }
    }

    /// Winter solstice for the hemisphere: June in the south, December in the north.
    public static func winterSolstice(year: Int, latitude: Double) -> LocalDay {
        latitude < 0 ? LocalDay(year: year, month: 6, day: 21) : LocalDay(year: year, month: 12, day: 21)
    }

    public static func summerSolstice(year: Int, latitude: Double) -> LocalDay {
        latitude < 0 ? LocalDay(year: year, month: 12, day: 21) : LocalDay(year: year, month: 6, day: 21)
    }

    /// Days whose sun paths make up the corridor, weekly; with the 3° margin consecutive weeks overlap.
    public func corridorDays(year: Int, latitude: Double, timeZone: TimeZone) -> [LocalDay] {
        switch self {
        case .winter:
            let solstice = Self.winterSolstice(year: year, latitude: latitude)
            return stride(from: -42, through: 42, by: 7).map { solstice.adding(days: $0, in: timeZone) }
        case .allYear:
            let first = LocalDay(year: year, month: 1, day: 1)
            var days = stride(from: 0, to: 365, by: 7).map { first.adding(days: $0, in: timeZone) }
            days += [Self.winterSolstice(year: year, latitude: latitude), Self.summerSolstice(year: year, latitude: latitude)]
            return days
        }
    }
}
