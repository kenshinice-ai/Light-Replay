import Foundation
import simd

/// How a stored image relates to the sensor image its intrinsics describe (docs/03 §11, review R01).
///
/// The sensor image ("native") has its origin top-left, x to the right, y down, in pixels: the frame ARKit hands
/// over, the one the camera intrinsics belong to. A stored image is that picture cropped, then scaled, then turned
/// clockwise by a quarter-turn multiple. Directions are always projected in native pixels (`PinholeCamera`); this
/// type only moves points between the two pictures, so a hero photo stored upright and a spool frame stored small
/// both stay tied to the same camera. Mirrors `engine/lightreplay/imagetransform.py`.
public struct ImageTransform: Sendable, Equatable, Codable {
    public var nativeWidth: Double
    public var nativeHeight: Double
    /// The part of the native image that was kept: x, y, width, height in native pixels.
    public var cropX: Double
    public var cropY: Double
    public var cropWidth: Double
    public var cropHeight: Double
    public var scale: Double
    /// Clockwise turn applied after scaling: 0, 90, 180 or 270.
    public var rotationDeg: Int

    public init(nativeWidth: Double, nativeHeight: Double, cropX: Double = 0, cropY: Double = 0, cropWidth: Double? = nil,
                cropHeight: Double? = nil, scale: Double, rotationDeg: Int = 0) {
        self.nativeWidth = nativeWidth
        self.nativeHeight = nativeHeight
        self.cropX = cropX
        self.cropY = cropY
        self.cropWidth = cropWidth ?? nativeWidth - cropX
        self.cropHeight = cropHeight ?? nativeHeight - cropY
        self.scale = scale
        self.rotationDeg = ((rotationDeg % 360) + 360) % 360
    }

    private var quarterTurned: Bool { rotationDeg == 90 || rotationDeg == 270 }

    /// Size of the stored image before rounding to whole pixels.
    public var encodedSize: SIMD2<Double> {
        let a = cropWidth * scale, b = cropHeight * scale
        return quarterTurned ? SIMD2(b, a) : SIMD2(a, b)
    }

    /// A native pixel position in the stored image.
    public func encoded(_ native: SIMD2<Double>) -> SIMD2<Double> {
        let a = cropWidth * scale, b = cropHeight * scale
        let x = (native.x - cropX) * scale, y = (native.y - cropY) * scale
        switch rotationDeg {
        case 90: return SIMD2(b - y, x)
        case 180: return SIMD2(a - x, b - y)
        case 270: return SIMD2(y, a - x)
        default: return SIMD2(x, y)
        }
    }

    /// A stored-image position back in native pixels.
    public func native(_ encoded: SIMD2<Double>) -> SIMD2<Double> {
        let a = cropWidth * scale, b = cropHeight * scale
        let p: SIMD2<Double>
        switch rotationDeg {
        case 90: p = SIMD2(encoded.y, b - encoded.x)
        case 180: p = SIMD2(a - encoded.x, b - encoded.y)
        case 270: p = SIMD2(a - encoded.y, encoded.x)
        default: p = encoded
        }
        return SIMD2(p.x / scale + cropX, p.y / scale + cropY)
    }

    /// The camera of a stored image that was only cropped and scaled, as spool frames are. Nil for a turned image:
    /// project in native pixels and carry the point over with `encoded(_:)` instead.
    public func camera(_ native: PinholeCamera) -> PinholeCamera? {
        guard rotationDeg == 0 else { return nil }
        return PinholeCamera(rotation: native.rotation, fx: native.fx * scale, fy: native.fy * scale,
                             cx: (native.cx - cropX) * scale, cy: (native.cy - cropY) * scale,
                             imageWidth: cropWidth * scale, imageHeight: cropHeight * scale)
    }
}
