import SwiftUI
import Simulation

struct StockTriangle: Shape {
    var up: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if up {
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}

struct StockArrow: View {
    var up: Bool
    var good: Bool
    var side: CGFloat? = nil
    @Environment(\.outsidePalette) private var P
    @ScaledMetric(relativeTo: .body) private var scaled: CGFloat = 8

    var body: some View {
        let size: CGFloat = side ?? scaled
        StockTriangle(up: up)
            .fill((good ? Theme.gain : Theme.loss).inPalette(P))
            .frame(width: size, height: size * 0.85)
            .accessibilityHidden(true)
    }
}

struct ArrowAmount: View {
    var gain: Double
    var amount: Double? = nil
    var format: (Double) -> String
    var live: Bool = false
    var instant: Bool = false
    var roll: Bool = false
    var step: TextStep = .body
    var weight: Font.Weight? = nil
    var font: Font? = nil
    var arrowSide: CGFloat? = nil
    @Environment(\.outsidePalette) private var P

    private var size: Double { abs(amount ?? gain) }
    private var flat: Bool { abs(gain) < 0.5 || size < 0.5 }

    var body: some View {
        let up: Bool = gain > 0
        let tint: Color = flat ? Theme.inkSoft : (up ? Theme.gain : Theme.loss)
        HStack(spacing: Theme.Space.xs) {
            if !flat { StockArrow(up: up, good: up, side: arrowSide) }
            figure(tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(flat ? format(0) : (up ? "up " : "down ") + format(size))
    }

    @ViewBuilder private func figure(_ tint: Color) -> some View {
        if roll && live {
            RollingMoney(value: size, betterWhenHigher: gain >= 0, format: format).foregroundStyle(tint.inPalette(P))
                .modifier(OptionalFont(font: font, step: step, weight: weight))
        } else if let font {
            if live {
                CountedFigure(value: size, format: format, tint: tint.inPalette(P), instant: instant).font(font)
            } else {
                Text(format(size)).font(font).foregroundStyle(tint.inPalette(P))
            }
        } else if live {
            CountedFigure(value: size, format: format, tint: tint.inPalette(P), instant: instant).textStyle(step, numeric: true, weight: weight)
        } else {
            Text(format(size)).textStyle(step, tint: tint, numeric: true, weight: weight)
        }
    }
}

private struct OptionalFont: ViewModifier {
    var font: Font?
    var step: TextStep
    var weight: Font.Weight?
    func body(content: Content) -> some View {
        if let font { content.font(font) } else { content.textStyle(step, numeric: true, weight: weight) }
    }
}

struct ChangeNote: View {
    var now: Double
    var before: Double?
    var isCost: Bool = false
    var against: String
    var format: (Double) -> String
    var step: TextStep = .caption

    var body: some View {
        if let before {
            let d: Double = now - before
            if abs(d) < 0.5 {
                Text("level on " + against).textStyle(step, tint: Theme.inkFaint)
            } else {
                let good: Bool = isCost ? d < 0 : d > 0
                let size: String = ReportMath.share(now, before).map { (s: Double) -> String in
                    let p: Double = abs(s) * 100
                    return p < 10 ? String(format: "%.1f%%", p) : String(format: "%.0f%%", p)
                } ?? format(abs(d))
                let words: String = (d > 0 ? "up " : "down ") + size + " on " + against
                HStack(spacing: Theme.Space.xxs) {
                    StockArrow(up: d > 0, good: good)
                    Text(words).textStyle(step, tint: good ? Theme.gain : Theme.loss, numeric: true).lineLimit(1).minimumScaleFactor(0.8)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(words)
            }
        }
    }
}
