import SwiftUI

private enum SeriesStep {
    case grow
    case slide
    case tail
    case still

    static func between(_ old: [Double], _ new: [Double]) -> SeriesStep {
        guard old.count >= 2, new.count >= 2 else { return .still }
        if new.count == old.count + 1, Array(new.dropLast()) == old { return .grow }
        if new.count == old.count, old.count >= 3, Array(new.dropLast()) == Array(old.dropFirst()) { return .slide }
        if new.count == old.count, Array(new.dropLast()) == Array(old.dropLast()) { return .tail }
        return .still
    }
}

private struct SeriesShape: Shape {
    var to: [Double]
    var from: [Double]
    var step: SeriesStep
    var area: Bool
    var phase: Double
    var base: Double
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
        func fin(_ v: Double) -> CGFloat { v.isFinite ? CGFloat(v) : 0 }
        let points: [CGPoint] = pts.map { (q: (x: Double, v: Double)) -> CGPoint in
            CGPoint(x: rect.minX + rect.width * fin(q.x), y: rect.minY + rect.height * (1 - fin((q.v - lo) / span)) * 0.9 + rect.height * 0.05)
        }
        guard rect.width.isFinite, rect.height.isFinite, !points.isEmpty else { return Path() }
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
