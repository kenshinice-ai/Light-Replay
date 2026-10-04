"""How a stored image relates to the sensor image its intrinsics describe (docs/03 §11, review R01). Reference.

The sensor image ("native") has its origin top-left, x to the right, y down, in pixels: the frame ARKit hands over,
the one the camera intrinsics belong to. A stored image is that picture cropped, then scaled, then turned clockwise
by a quarter-turn multiple. Directions are always projected in native pixels; this module only moves points between
the two pictures, so a hero photo stored upright and a spool frame stored small both stay tied to the same camera.
"""


def encoded_size(crop, scale, rotation_deg):
    """Size of the stored image, (width, height), before rounding to whole pixels."""
    width, height = crop[2] * scale, crop[3] * scale
    return (height, width) if rotation_deg in (90, 270) else (width, height)


def to_encoded(point, crop, scale, rotation_deg):
    """A native pixel position in the stored image."""
    a, b = crop[2] * scale, crop[3] * scale
    x, y = (point[0] - crop[0]) * scale, (point[1] - crop[1]) * scale
    if rotation_deg == 0:
        return (x, y)
    if rotation_deg == 90:
        return (b - y, x)
    if rotation_deg == 180:
        return (a - x, b - y)
    if rotation_deg == 270:
        return (y, a - x)
    raise ValueError("rotation must be 0, 90, 180 or 270")


def to_native(point, crop, scale, rotation_deg):
    """A stored-image position back in native pixels."""
    a, b = crop[2] * scale, crop[3] * scale
    if rotation_deg == 0:
        x, y = point
    elif rotation_deg == 90:
        x, y = point[1], b - point[0]
    elif rotation_deg == 180:
        x, y = a - point[0], b - point[1]
    elif rotation_deg == 270:
        x, y = a - point[1], point[0]
    else:
        raise ValueError("rotation must be 0, 90, 180 or 270")
    return (x / scale + crop[0], y / scale + crop[1])


def scaled_intrinsics(fx, fy, cx, cy, crop, scale):
    """Intrinsics of a stored image that was only cropped and scaled (rotation 0), as spool frames are."""
    return (fx * scale, fy * scale, (cx - crop[0]) * scale, (cy - crop[1]) * scale)
