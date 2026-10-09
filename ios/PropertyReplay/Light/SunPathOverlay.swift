import SwiftUI

/// The question's sun paths over the camera. Seen parts turn sun-yellow; unseen parts stay dashed white, so the gaps
/// read as "point here" without a word. Every stroke has a faint dark halo so it holds up against a bright sky.
struct SunPathOverlay: View {
    let state: SunPathOverlayState
    /// Bottom edge of the controls at the top of the screen, in this view's space. A path's name is not put under them.
    var topClear: CGFloat = 0

    static let sun = Color(red: 1, green: 0.82, blue: 0.24)
    /// Words keep this far from the screen edges and from the dot they belong to.
    private static let edge: CGFloat = 12
    private static let gap: CGFloat = 7

    var body: some View {
        Canvas { context, size in
            let limit = max(size.width, size.height) * 1.5
            for line in state.lines { Self.draw(line, in: &context, limit: limit) }
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.55), radius: 2))
                for mark in state.marks {
                    let dot = Path(ellipseIn: CGRect(x: mark.screen.x - 4, y: mark.screen.y - 4, width: 8, height: 8))
                    layer.fill(dot, with: .color(mark.lit ? Self.sun : .white))
                    // The time sits above its dot and the path's name below the path, each by its own height, so
                    // they stay apart at any text size (review LS03).
                    let time = layer.resolve(Text(mark.text).font(.caption2.weight(.semibold)).foregroundStyle(.white))
                    let height = time.measure(in: size).height
                    // Half a time showing from under the legend reads as a fault; there the dot stands alone.
                    guard mark.screen.y - Self.gap - height >= topClear else { continue }
                    layer.draw(time, at: CGPoint(x: mark.screen.x, y: mark.screen.y - Self.gap), anchor: .bottom)
                }
                for line in state.lines where line.emphasis == .primary {
                    guard let anchor = Self.labelPoint(line, width: size.width, below: topClear) else { continue }
                    let text = layer.resolve(Text(line.label).font(.caption.weight(.bold)).foregroundStyle(.white))
                    // Measured, so a long name wraps inside the screen instead of running off both sides.
                    let room = max(1, size.width - 2 * Self.edge)
                    let box = text.measure(in: CGSize(width: room, height: .infinity))
                    let x = min(max(anchor.x - box.width / 2, Self.edge), size.width - Self.edge - box.width)
                    layer.draw(text, in: CGRect(x: x, y: anchor.y + Self.gap, width: box.width, height: box.height))
                }
                if let sun = state.sunNow {
                    let disk = Path(ellipseIn: CGRect(x: sun.x - 9, y: sun.y - 9, width: 18, height: 18))
                    layer.fill(disk, with: .color(Self.sun))
                    layer.stroke(disk, with: .color(.white), lineWidth: 2)
                    layer.draw(Text("Now").font(.caption2.weight(.bold)).foregroundStyle(.white),
                               at: CGPoint(x: sun.x, y: sun.y + 9 + Self.gap), anchor: .top)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Consecutive visible points become segments; runs with the same lit state share one path.
    private static func draw(_ line: SunPathOverlayState.Line, in context: inout GraphicsContext, limit: CGFloat) {
        var lit = Path(), unlit = Path()
        for (a, b) in zip(line.points, line.points.dropFirst()) {
            guard let p = a.screen, let q = b.screen, hypot(q.x - p.x, q.y - p.y) < limit else { continue }
            if a.lit && b.lit {
                lit.move(to: p); lit.addLine(to: q)
            } else {
                unlit.move(to: p); unlit.addLine(to: q)
            }
        }
        let primary = line.emphasis == .primary
        let litWidth: CGFloat = primary ? 4 : 2
        let unlitStyle = StrokeStyle(lineWidth: primary ? 2.5 : 1.5, lineCap: .round, dash: primary ? [7, 6] : [4, 6])
        context.stroke(lit, with: .color(.black.opacity(0.25)), style: StrokeStyle(lineWidth: litWidth + 2, lineCap: .round))
        context.stroke(unlit, with: .color(.black.opacity(0.2)), style: StrokeStyle(lineWidth: unlitStyle.lineWidth + 2, lineCap: .round))
        context.stroke(lit, with: .color(sun.opacity(primary ? 1 : 0.6)), style: StrokeStyle(lineWidth: litWidth, lineCap: .round))
        context.stroke(unlit, with: .color(.white.opacity(primary ? 0.85 : 0.45)), style: unlitStyle)
    }

    /// The visible point nearest the middle of the screen, where a label reads best, and clear of the top controls.
    private static func labelPoint(_ line: SunPathOverlayState.Line, width: CGFloat, below top: CGFloat) -> CGPoint? {
        line.points.compactMap(\.screen).filter { $0.x > 40 && $0.x < width - 40 && $0.y + gap >= top }
            .min { abs($0.x - width / 2) < abs($1.x - width / 2) }
    }
}

#if DEBUG
/// The simulator's painted sky and ground, drawn from the same pretend camera as the overlay.
struct SimulatedSky: View {
    let state: SunPathOverlayState

    var body: some View {
        Canvas { context, size in
            let sky = Gradient(colors: [Color(red: 0.22, green: 0.45, blue: 0.78), Color(red: 0.62, green: 0.78, blue: 0.93)])
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(sky, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            let horizon = state.horizon.compactMap { $0 }.filter { $0.x > -size.width && $0.x < size.width * 2 }.sorted { $0.x < $1.x }
            guard let first = horizon.first, let last = horizon.last else { return }
            var ground = Path()
            ground.move(to: CGPoint(x: first.x, y: size.height + 20))
            for p in horizon { ground.addLine(to: p) }
            ground.addLine(to: CGPoint(x: last.x, y: size.height + 20))
            ground.closeSubpath()
            context.fill(ground, with: .color(Color(red: 0.24, green: 0.27, blue: 0.22)))
        }
        .overlay(alignment: .center) {
            Text("Simulator · pretend camera").font(.caption2).foregroundStyle(.white.opacity(0.7)).offset(y: 60)
        }
    }
}
#endif
