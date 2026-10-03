"""Solar position reference for SunEngine (docs/06 §1).

`position` is the NOAA solar calculator algorithm (after Meeus) with SPA-style refraction; the Swift SunEngine
implements the same operations in the same order and must match it to 1e-7 degrees. `almanac_position` is an
independent formulation (Michalsky 1988, Astronomical Almanac, stated accuracy 0.01 deg for 1950-2050) used only to
cross-check the algorithm itself. Pure standard library.
"""

from dataclasses import dataclass
import math

JD_UNIX_EPOCH = 2440587.5
J2000 = 2451545.0


@dataclass(frozen=True)
class SunPosition:
    azimuth_deg: float          # true north, clockwise, [0, 360)
    elevation_deg: float        # apparent: geometric plus refraction
    true_elevation_deg: float   # geometric, no refraction
    declination_deg: float
    equation_of_time_min: float


def _wrap360(x):
    return x % 360.0


def refraction_deg(true_elevation_deg, pressure_hpa=1010.0, temperature_c=10.0):
    """SPA (Reda & Andreas 2004, eq. 42) refraction; zero once the sun is well below the horizon."""
    e = true_elevation_deg
    if e < -(0.26667 + 0.5667):
        return 0.0
    return (pressure_hpa / 1010.0) * (283.0 / (273.0 + temperature_c)) * 1.02 / (
        60.0 * math.tan(math.radians(e + 10.3 / (e + 5.11))))


def position(unix_seconds, latitude_deg, longitude_deg, pressure_hpa=1010.0, temperature_c=10.0):
    jd = unix_seconds / 86400.0 + JD_UNIX_EPOCH
    jc = (jd - J2000) / 36525.0
    l0 = _wrap360(280.46646 + jc * (36000.76983 + jc * 0.0003032))
    m = 357.52911 + jc * (35999.05029 - 0.0001537 * jc)
    ecc = 0.016708634 - jc * (0.000042037 + 0.0000001267 * jc)
    mr = math.radians(m)
    c = (math.sin(mr) * (1.914602 - jc * (0.004817 + 0.000014 * jc))
         + math.sin(2.0 * mr) * (0.019993 - 0.000101 * jc)
         + math.sin(3.0 * mr) * 0.000289)
    true_long = l0 + c
    omega = math.radians(125.04 - 1934.136 * jc)
    app_long = true_long - 0.00569 - 0.00478 * math.sin(omega)
    mean_obliq = 23.0 + (26.0 + (21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) / 60.0) / 60.0
    obliq = math.radians(mean_obliq + 0.00256 * math.cos(omega))
    decl = math.asin(math.sin(obliq) * math.sin(math.radians(app_long)))
    y = math.tan(obliq / 2.0) ** 2
    l0r = math.radians(l0)
    eot = 4.0 * math.degrees(
        y * math.sin(2.0 * l0r) - 2.0 * ecc * math.sin(mr) + 4.0 * ecc * y * math.sin(mr) * math.cos(2.0 * l0r)
        - 0.5 * y * y * math.sin(4.0 * l0r) - 1.25 * ecc * ecc * math.sin(2.0 * mr))
    minutes_utc = (jd + 0.5 - math.floor(jd + 0.5)) * 1440.0
    true_solar_min = minutes_utc + eot + 4.0 * longitude_deg
    hour_angle = (true_solar_min / 4.0 - 180.0 + 180.0) % 360.0 - 180.0
    lat = math.radians(latitude_deg)
    ha = math.radians(hour_angle)
    cos_zen = math.sin(lat) * math.sin(decl) + math.cos(lat) * math.cos(decl) * math.cos(ha)
    zen = math.acos(max(-1.0, min(1.0, cos_zen)))
    true_elev = 90.0 - math.degrees(zen)
    az = _wrap360(180.0 + math.degrees(math.atan2(
        math.sin(ha), math.cos(ha) * math.sin(lat) - math.tan(decl) * math.cos(lat))))
    elev = true_elev + refraction_deg(true_elev, pressure_hpa, temperature_c)
    return SunPosition(az, elev, true_elev, math.degrees(decl), eot)


def almanac_position(unix_seconds, latitude_deg, longitude_deg):
    """Independent check only (Michalsky 1988). Geometric: no refraction."""
    jd = unix_seconds / 86400.0 + JD_UNIX_EPOCH
    n = jd - J2000
    lmean = _wrap360(280.460 + 0.9856474 * n)
    g = math.radians(_wrap360(357.528 + 0.9856003 * n))
    lam = math.radians(lmean + 1.915 * math.sin(g) + 0.020 * math.sin(2.0 * g))
    eps = math.radians(23.439 - 0.0000004 * n)
    ra = math.atan2(math.cos(eps) * math.sin(lam), math.cos(lam))
    dec = math.asin(math.sin(eps) * math.sin(lam))
    hours_ut = (jd + 0.5 - math.floor(jd + 0.5)) * 24.0
    gmst = (6.697375 + 0.0657098242 * n + hours_ut) % 24.0   # n carries the day fraction
    lmst = (gmst + longitude_deg / 15.0) % 24.0
    ha = math.radians(((lmst * 15.0 - math.degrees(ra)) + 180.0) % 360.0 - 180.0)
    lat = math.radians(latitude_deg)
    elev = math.asin(math.sin(dec) * math.sin(lat) + math.cos(dec) * math.cos(lat) * math.cos(ha))
    az = _wrap360(180.0 + math.degrees(math.atan2(
        math.sin(ha), math.cos(ha) * math.sin(lat) - math.tan(dec) * math.cos(lat))))
    return az, math.degrees(elev)
