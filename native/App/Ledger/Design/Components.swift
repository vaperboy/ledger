import SwiftUI
import Countries

/// A smoked-glass card on the walnut background.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Space.l
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.glass.opacity(0.55), Theme.leather.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }
}

/// The prominent champagne-gold action button (Next day).
struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .serif).weight(.semibold))
            .foregroundStyle(Color(red: 0.16, green: 0.115, blue: 0.05))
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).fill(Theme.goldGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75)
            )
            .shadow(color: Theme.gold.opacity(0.28), radius: 14, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A quiet outlined button for secondary actions.
struct QuietButtonStyle: ButtonStyle {
    var tint: Color = Theme.gold
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline).weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Space.l).padding(.vertical, 10)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.18 : 0.09)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.75))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Small uppercase label above a section.
struct SectionLabel: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.label).tracking(1.2).foregroundStyle(Theme.ivoryFaint)
    }
}

/// A green/red change indicator: arrow, amount and (when meaningful) percent. Never shows a misleading percentage.
struct DeltaPill: View {
    var title: String
    var amount: Double
    var share: Double?
    var format: (Double) -> String

    var body: some View {
        let c = Theme.change(amount)
        HStack(spacing: 5) {
            Image(systemName: amount > 0 ? "arrow.up.right" : amount < 0 ? "arrow.down.right" : "minus").font(.caption2.weight(.bold))
            Text(title).font(.label).foregroundStyle(Theme.ivoryMuted)
            Text(amount == 0 ? format(0) : (amount > 0 ? "+" : "−") + format(abs(amount))).font(.system(.caption, design: .serif).weight(.semibold).monospacedDigit())
            if let share, abs(share) >= 0.001, abs(share) < 10 {
                Text(String(format: "%+.1f%%", share * 100)).font(.caption2.monospacedDigit()).opacity(0.85)
            }
        }
        .foregroundStyle(c)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(c.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}

/// A line chart without axes, for real history. Draws nothing misleading for fewer than two points.
struct Sparkline: View {
    var values: [Double]
    var tint: Color = Theme.gold
    var body: some View {
        GeometryReader { geo in
            if values.count >= 2, let lo = values.min(), let hi = values.max() {
                let span = max(hi - lo, abs(hi) * 0.002, 1)
                let pts: [CGPoint] = values.enumerated().map { i, v in
                    CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(values.count - 1), y: geo.size.height * (1 - CGFloat((v - lo) / span)) * 0.9 + geo.size.height * 0.05)
                }
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        p.closeSubpath()
                    }.fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }.stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            } else {
                Rectangle().fill(Theme.hairline).frame(height: 1).frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

/// Bars for a short series (monthly profit). Gains up in green, losses down in red.
struct MiniBars: View {
    var values: [Double]
    var body: some View {
        GeometryReader { geo in
            let peak = max(values.map { abs($0) }.max() ?? 1, 1)
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0).frame(maxHeight: v >= 0 ? .infinity : 0)
                        RoundedRectangle(cornerRadius: 2).fill(Theme.change(v)).frame(height: max(2, geo.size.height / 2 * CGFloat(abs(v) / peak)))
                        Spacer(minLength: 0).frame(maxHeight: v < 0 ? .infinity : 0)
                    }
                }
            }
        }
    }
}

/// Small status capsule.
struct Chip: View {
    var text: String
    var tint: Color = Theme.ivoryMuted
    var body: some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

/// A label with a figure beneath it.
struct Stat: View {
    var label: String
    var value: String
    var tint: Color = Theme.ivory
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(label)
            Text(value).font(.figure(18)).foregroundStyle(tint).minimumScaleFactor(0.7).lineLimit(1)
        }
    }
}

struct LedgerBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Theme.background.ignoresSafeArea()).foregroundStyle(Theme.ivory)
    }
}
extension View {
    func ledgerBackground() -> some View { modifier(LedgerBackground()) }
}

/// A row of label and value, used in lists.
struct ValueRow: View {
    var label: String
    var value: String
    var tint: Color = Theme.ivory
    var body: some View {
        HStack {
            Text(label).font(.bodyText).foregroundStyle(Theme.ivoryMuted)
            Spacer()
            Text(value).font(.system(.subheadline, design: .serif).monospacedDigit()).foregroundStyle(tint)
        }
    }
}

/// A money input in the currency being shown. Converts what the player types into the game's accounting units.
struct AmountField: View {
    var title: String
    var currency: Currency
    @Binding var amount: Double          // accounting units
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(currency.country.currencyCode).font(.label).foregroundStyle(Theme.ivoryFaint)
            TextField(title, text: $text)
                .keyboardType(.decimalPad)
                .focused($focused)
                .font(.system(.body, design: .serif).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .onChange(of: text) { _, new in
                    let cleaned = new.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
                    amount = (Double(cleaned) ?? 0) * currency.rate
                }
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.walnut.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(focused ? Theme.gold.opacity(0.6) : Theme.hairline, lineWidth: 1))
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } } }
    }
}

/// Horizontal section switcher used on detail screens.
struct SectionTabs<T: Hashable>: View {
    var items: [T]
    var title: (T) -> String
    @Binding var selection: T
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Button { selection = item; Haptics.choose() } label: {
                        Text(title(item)).font(.subheadline.weight(.semibold))
                            .foregroundStyle(selection == item ? Color(red: 0.16, green: 0.115, blue: 0.05) : Theme.ivoryMuted)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(selection == item ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.leather.opacity(0.8))))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Space.l)
        }
    }
}

/// A 0–100 meter such as reputation or quality.
struct Meter: View {
    var label: String
    var value: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(label).font(.caption).foregroundStyle(Theme.ivoryMuted); Spacer(); Text("\(Int(value.rounded()))").font(.caption.monospacedDigit()).foregroundStyle(Theme.ivory) }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule().fill(Theme.goldGradient).frame(width: max(4, g.size.width * CGFloat(min(100, max(0, value)) / 100)))
                }
            }.frame(height: 5)
        }
    }
}
