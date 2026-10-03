import Foundation

/// Where the sun is, seen from a point on the ground. Azimuth is from true north, clockwise.
public struct SunPosition: Sendable, Equatable {
    public let azimuthDeg: Double
    /// Apparent elevation: geometric plus atmospheric refraction. This is what decides whether the sun is up.
    public let elevationDeg: Double
    public let trueElevationDeg: Double
    public let declinationDeg: Double
    public let equationOfTimeMin: Double
}

/// NOAA solar calculator algorithm (after Meeus) with SPA refraction (docs/06 §1). Mirrors `engine/lightreplay/sun.py`
/// operation for operation; `SolarPositionTests` holds the two to 1e-7 degrees and the algorithm to the NREL SPA example.
public enum SolarPosition {
    public static let version = "sun-noaa-0.1"

    public static func compute(at date: Date, latitude: Double, longitude: Double,
                               pressureHPa: Double = 1010, temperatureC: Double = 10) -> SunPosition {
        let jd = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let jc = (jd - 2_451_545) / 36_525
        let l0 = wrap360(280.46646 + jc * (36_000.76983 + jc * 0.0003032))
        let m = 357.52911 + jc * (35_999.05029 - 0.0001537 * jc)
        let ecc = 0.016708634 - jc * (0.000042037 + 0.0000001267 * jc)
        let mr = radians(m)
        let c = sin(mr) * (1.914602 - jc * (0.004817 + 0.000014 * jc))
            + sin(2 * mr) * (0.019993 - 0.000101 * jc)
            + sin(3 * mr) * 0.000289
        let trueLong = l0 + c
        let omega = radians(125.04 - 1934.136 * jc)
        let appLong = trueLong - 0.00569 - 0.00478 * sin(omega)
        let meanObliq = 23 + (26 + (21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) / 60) / 60
        let obliq = radians(meanObliq + 0.00256 * cos(omega))
        let decl = asin(sin(obliq) * sin(radians(appLong)))
        let y = pow(tan(obliq / 2), 2)
        let l0r = radians(l0)
        let eot = 4 * degrees(
            y * sin(2 * l0r) - 2 * ecc * sin(mr) + 4 * ecc * y * sin(mr) * cos(2 * l0r)
            - 0.5 * y * y * sin(4 * l0r) - 1.25 * ecc * ecc * sin(2 * mr))
        let minutesUTC = (jd + 0.5 - (jd + 0.5).rounded(.down)) * 1440
        let trueSolarMin = minutesUTC + eot + 4 * longitude
        let hourAngle = pyMod(trueSolarMin / 4 - 180 + 180, 360) - 180
        let lat = radians(latitude)
        let ha = radians(hourAngle)
        let cosZen = sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(ha)
        let zen = acos(max(-1, min(1, cosZen)))
        let trueElev = 90 - degrees(zen)
        let az = wrap360(180 + degrees(atan2(sin(ha), cos(ha) * sin(lat) - tan(decl) * cos(lat))))
        let elev = trueElev + refractionDeg(trueElevation: trueElev, pressureHPa: pressureHPa, temperatureC: temperatureC)
        return SunPosition(azimuthDeg: az, elevationDeg: elev, trueElevationDeg: trueElev,
                           declinationDeg: degrees(decl), equationOfTimeMin: eot)
    }

    /// SPA (Reda & Andreas 2004, eq. 42). Zero once the sun is clearly below the horizon.
    public static func refractionDeg(trueElevation e: Double, pressureHPa: Double = 1010, temperatureC: Double = 10) -> Double {
        guard e >= -(0.26667 + 0.5667) else { return 0 }
        return (pressureHPa / 1010) * (283 / (273 + temperatureC)) * 1.02 / (60 * tan(radians(e + 10.3 / (e + 5.11))))
    }
}

@inline(__always) func radians(_ d: Double) -> Double { d * .pi / 180 }
@inline(__always) func degrees(_ r: Double) -> Double { r * 180 / .pi }
/// Python's `%`: the result takes the sign of the divisor. Used so Swift and the reference agree bit for bit.
@inline(__always) func pyMod(_ a: Double, _ b: Double) -> Double {
    let r = a.truncatingRemainder(dividingBy: b)
    return r != 0 && (r < 0) != (b < 0) ? r + b : r
}
@inline(__always) func wrap360(_ x: Double) -> Double { pyMod(x, 360) }
