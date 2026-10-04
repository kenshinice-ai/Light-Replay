import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

// segsmoke: run GenerateIterativeSegmentationRequest on plain photos and write down what came back.
//
//   segsmoke [--seed x,y]... [--exclude x,y]... [--quality accurate|balanced|fast] [--out DIR] IMAGE...
//   segsmoke --selftest [--out DIR]
//
// Seeds are fractions of the image, origin top-left (0.5,0.15 = middle, near the top). Vision's own normalised points
// have their origin bottom-left; the flip happens here, once. For every image the tool prints one CSV row
// (field/templates/segmentation-smoke-log.csv) and writes the mask and an overlay beside each other in DIR.
// "mask" as an outcome only says a mask came back: whether it is the sky is for a person looking at the overlay.

struct Options {
    var seeds: [CGPoint] = []
    var excluded: [CGPoint] = []
    var quality = GenerateIterativeSegmentationRequest.QualityLevel.accurate
    var qualityName = "accurate"
    var out = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    var images: [URL] = []
    var selfTest = false
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("segsmoke: " + message + "\n").utf8))
    exit(2)
}

func point(_ text: String) -> CGPoint {
    let parts = text.split(separator: ",").compactMap { Double($0) }
    guard parts.count == 2, parts.allSatisfy({ (0...1).contains($0) }) else { fail("expected x,y between 0 and 1, got \(text)") }
    return CGPoint(x: parts[0], y: parts[1])
}

func parse() -> Options {
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        let argument = arguments.removeFirst()
        func value() -> String {
            if arguments.isEmpty { fail("\(argument) needs a value") }
            return arguments.removeFirst()
        }
        switch argument {
        case "--seed": options.seeds.append(point(value()))
        case "--exclude": options.excluded.append(point(value()))
        case "--out": options.out = URL(fileURLWithPath: value())
        case "--selftest": options.selfTest = true
        case "--quality":
            options.qualityName = value()
            switch options.qualityName {
            case "accurate": options.quality = .accurate
            case "balanced": options.quality = .balanced
            case "fast": options.quality = .fast
            default: fail("unknown quality \(options.qualityName)")
            }
        case "--help", "-h":
            print("segsmoke [--seed x,y]... [--exclude x,y]... [--quality accurate|balanced|fast] [--out DIR] IMAGE...\nsegsmoke --selftest [--out DIR]")
            exit(0)
        default: options.images.append(URL(fileURLWithPath: argument))
        }
    }
    if options.seeds.isEmpty { options.seeds = [CGPoint(x: 0.5, y: 0.15)] }
    return options
}

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

/// A drawn scene, so the tool can be exercised without anyone's photographs: sky, a building, a window frame.
/// It checks that the pipeline runs; a drawing says nothing about how the model treats real skies.
func drawnScene() -> CGImage {
    let width = 960, height = 720
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let sky = CGGradient(colorsSpace: nil, colors: [CGColor(red: 0.35, green: 0.6, blue: 0.95, alpha: 1), CGColor(red: 0.8, green: 0.9, blue: 1, alpha: 1)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(sky, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 200), options: [.drawsAfterEndLocation])
    context.setFillColor(CGColor(red: 0.35, green: 0.33, blue: 0.3, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: 220))                 // ground and a far roofline
    context.fill(CGRect(x: 560, y: 220, width: 300, height: 260))               // a building
    context.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1))
    for x in [0, 300, 930] { context.fill(CGRect(x: x, y: 0, width: 30, height: height)) }   // window frame
    context.fill(CGRect(x: 0, y: 690, width: width, height: 30))
    return context.makeImage()!
}

/// The share of the mask that is set, and the mask as an 8-bit image the size of the result.
func measure(_ mask: CGImage) -> (fraction: Double, pixels: [UInt8], width: Int, height: Int) {
    let width = mask.width, height = mask.height
    var pixels = [UInt8](repeating: 0, count: width * height)
    pixels.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    let set = pixels.reduce(0) { $0 + ($1 > 127 ? 1 : 0) }
    return (Double(set) / Double(max(pixels.count, 1)), pixels, width, height)
}

/// The photo with the mask tinted over it and the seeds marked: what a person looks at to say "sky" or "not sky".
func overlay(_ image: CGImage, mask: CGImage, seeds: [CGPoint], excluded: [CGPoint]) -> CGImage? {
    let width = image.width, height = image.height
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let full = CGRect(x: 0, y: 0, width: width, height: height)
    context.draw(image, in: full)
    context.saveGState()
    context.clip(to: full, mask: mask)
    context.setFillColor(CGColor(red: 1, green: 0.2, blue: 0.6, alpha: 0.45))
    context.fill(full)
    context.restoreGState()
    let radius = CGFloat(max(width, height)) / 120
    for (points, color) in [(seeds, CGColor(red: 0, green: 1, blue: 0, alpha: 1)), (excluded, CGColor(red: 1, green: 0, blue: 0, alpha: 1))] {
        context.setFillColor(color)
        for p in points {
            context.fillEllipse(in: CGRect(x: p.x * CGFloat(width) - radius, y: (1 - p.y) * CGFloat(height) - radius, width: radius * 2, height: radius * 2))
        }
    }
    return context.makeImage()
}

func describe(_ status: DownloadableAssetsRequestStatus) -> String {
    switch status {
    case .ready: "ready"
    case .notReady: "not_ready"
    case .downloading: "downloading"
    case .error(let error): "error(\(error.localizedDescription))"
    @unknown default: "unknown"
    }
}

func run(_ image: CGImage, name: String, source: String, options: Options) async {
    func visionPoint(_ p: CGPoint) -> NormalizedPoint { NormalizedPoint(x: p.x, y: 1 - p.y) }   // top-left → bottom-left origin
    let request = GenerateIterativeSegmentationRequest(seedPoint: visionPoint(options.seeds[0]))
    request.qualityLevel = options.quality
    var assets = describe(await request.assetStatus)
    if assets != "ready" {
        do { try await request.downloadAssets(); assets = describe(await request.assetStatus) } catch { assets = "download_failed(\(error.localizedDescription))" }
    }
    let strategy = "\(options.seeds.count)_included_\(options.excluded.count)_excluded"
    var outcome = "error", fraction = 0.0, note = ""
    let started = Date()
    do {
        // The request is iterative: the seed gives a first mask, and each further point refines the mask before it.
        // Adding points before the first pass fails ("getBestMask failed with status 14", macOS 27.0.1).
        var observation = try await request.perform(on: image)
        var steps: [String] = [String(format: "%.3f", try observation.map { measure(try $0.cgImage).fraction } ?? 0)]
        for (seed, included) in options.seeds.dropFirst().map({ ($0, true) }) + options.excluded.map({ ($0, false) }) {
            if included { try request.addIncludedPoint(visionPoint(seed)) } else { try request.addExcludedPoint(visionPoint(seed)) }
            observation = try await request.perform(on: image)
            steps.append((included ? "+" : "-") + String(format: "%.3f", try observation.map { measure(try $0.cgImage).fraction } ?? 0))
        }
        if let observation {
            let mask = try observation.cgImage
            let measured = measure(mask)
            fraction = measured.fraction
            outcome = fraction == 0 ? "empty" : "mask"
            note = "mask \(measured.width)x\(measured.height) confidence \(observation.confidence) steps \(steps.joined(separator: " "))"
            write(mask, to: options.out.appendingPathComponent(name + ".mask.png"))
            if let composed = overlay(image, mask: mask, seeds: options.seeds, excluded: options.excluded) {
                write(composed, to: options.out.appendingPathComponent(name + ".overlay.png"))
            }
        } else {
            outcome = "empty"
            note = "the request returned no observation"
        }
    } catch {
        note = String(describing: error).replacingOccurrences(of: ",", with: ";").replacingOccurrences(of: "\n", with: " ")
    }
    let seconds = Date().timeIntervalSince(started)
    print("\(name),\(source),,\(strategy),\(options.qualityName),\(outcome),\(String(format: "%.3f", fraction)),\(String(format: "%.2f", seconds)),\(assets),\(note)")
}

let options = parse()
try? FileManager.default.createDirectory(at: options.out, withIntermediateDirectories: true)
print("image_id,source,scene_class,seed_strategy,quality_level,outcome,mask_fraction,seconds,assets_status,notes")
if options.selfTest {
    let scene = drawnScene()
    write(scene, to: options.out.appendingPathComponent("selftest.png"))
    await run(scene, name: "selftest", source: "drawn_scene", options: options)
}
for url in options.images {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        print("\(url.deletingPathExtension().lastPathComponent),plain_photo,,,\(options.qualityName),error,0.000,0.00,,could not read the image")
        continue
    }
    // Apply the EXIF orientation so that "top" in a seed is the top a person sees.
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32).flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up
    let upright = orientation == .up ? image : (CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: max(image.width, image.height)] as CFDictionary) ?? image)
    await run(upright, name: url.deletingPathExtension().lastPathComponent, source: "plain_photo", options: options)
}
