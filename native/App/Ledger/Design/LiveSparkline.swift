import SwiftUI

/// How a series changed from the one drawn before it.
private enum SeriesStep {
    /// A new last point was added: the earlier points stay and the line grows to it.
    case grow
    /// The series is a fixed window: it moved on by one day, so the line slides left by one step and ends at the new point.
    case slide
    /// Only the last point moved.
    case tail
    /// Anything else (another period chosen): shown at once.
    case still

    static func between(_ old: [Double], _ new: [Double]) -> SeriesStep {
        guard old.count >= 2, new.count >= 2 else { return .still }
        if new.count == old.count + 1, Array(new.dropLast()) == old { return .grow }
        if new.count == old.count, old.count >= 3, Array(new.dropLast()) == Array(old.dropFirst()) { return .slide }
        if new.count == old.count, Array(new.dropLast()) == Array(old.dropLast()) { return .tail }
        return .still
    }
}

/// The line of a series (or its filled area) between the series drawn before (`from`) and the one now (`to`). `phase - base`, clamped to 0...1,
/// is how far the move has gone: earlier points stay put (or slide one step left for a window), the last point travels from the old last
/// value to the new one, and the vertical scale eases between the two ranges.
private struct SeriesShape: Shape {
    var to: [Double]
    var from: [Double]
    var step: SeriesStep
    var area: Bool
    var phase: Double
    var base: Double
    /// Maps a series to the low and high of the plot (so a chart can pad its scale).
    var range: ([Double]) -> (Double, Double)

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let n: Int = to.count
        guard n >= 2 else { return Path() }
        let t: Double = step == .still ? 1 : min(max(phase - base, 0), 1)
        var pts: [(x: Double, v: Double)] = []
        let lo: Double, hi: Double
        if t >= 1 {
            for (j, v) in to.enumerated() { pts.append((Double(j) / Double(n - 1), v)) }
            let r = range(to)
            lo = r.0
            hi = r.1
        } else {
            let a = range(from), b = range(to)
            lo = a.0 + (b.0 - a.0) * t
            hi = a.1 + (b.1 - a.1) * t
            let last: Double = (from.last ?? 0) + ((to.last ?? 0) - (from.last ?? 0)) * t
            switch step {
            case .slide:
                pts.append((-t / Double(n - 1), from.first ?? 0))
                for j in 0..<(n - 1) { pts.append(((Double(j) + 1 - t) / Double(n - 1), to[j])) }
            case .grow:
                let d: Double = Double(n - 2) + t
                for j in 0..<(n - 1) { pts.append((Double(j) / d, to[j])) }
            case .tail, .still:
                for j in 0..<(n - 1) { pts.append((Double(j) / Double(n - 1), to[j])) }
            }
            pts.append((1, last))
        }
        let span: Double = max(hi - lo, abs(hi) * 0.002, 1)
        let points: [CGPoint] = pts.map { (q: (x: Double, v: Double)) -> CGPoint in
            CGPoint(x: rect.minX + rect.width * CGFloat(q.x), y: rect.minY + rect.height * (1 - CGFloat((q.v - lo) / span)) * 0.9 + rect.height * 0.05)
        }
        var p = Path()
        if area {
            p.move(to: CGPoint(x: points[0].x, y: rect.maxY))
            for pt in points { p.addLine(to: pt) }
            p.addLine(to: CGPoint(x: points[points.count - 1].x, y: rect.maxY))
            p.closeSubpath()
        } else {
            p.move(to: points[0])
            for pt in points.dropFirst() { p.addLine(to: pt) }
        }
        return p
    }
}

/// A sparkline that is drawn once and then only extended: when a day is appended the earlier line stays and its trailing segment travels to the
/// new point (a fixed window slides left by one step), instead of drawing again. The left-to-right draw is `drawsItself()` and belongs to the
/// first appearance only. Reduce Motion shows the new series at once. `range` can pad the scale (default: the series' own low and high).
struct LiveSparkline: View {
    var values: [Double]
    var tint: Color = Theme.gold
    var filled = true
    var range: (([Double]) -> (Double, Double))? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: [Double]? = nil
    @State private var before: [Double] = []
    @State private var step: SeriesStep = .still
    @State private var phase: Double = 0
    @State private var base: Double = 0

    private func scale(_ v: [Double]) -> (Double, Double) {
        if let range { return range(v) }
        return (v.min() ?? 0, v.max() ?? 0)
    }

    var body: some View {
        let to: [Double] = drawn ?? values
        ZStack {
            if filled {
                SeriesShape(to: to, from: before, step: step, area: true, phase: phase, base: base, range: scale)
                    .fill(tint.opacity(ChartPalette.areaOpacity))
            }
            SeriesShape(to: to, from: before, step: step, area: false, phase: phase, base: base, range: scale)
                .stroke(tint, style: StrokeStyle(lineWidth: ChartPalette.lineWidth, lineCap: .round, lineJoin: .round))
        }
        .clipped()
        .onChange(of: values) { old, new in
            let kind: SeriesStep = reduceMotion ? .still : SeriesStep.between(drawn ?? old, new)
            before = drawn ?? old
            step = kind
            base = phase
            drawn = new
            if kind == .still {
                phase = base + 1
            } else {
                withAnimation(.easeInOut(duration: 0.7)) { phase = base + 1 }
            }
        }
    }
}
