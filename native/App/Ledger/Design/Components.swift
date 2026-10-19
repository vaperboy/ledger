import SwiftUI
import Countries

/// A dark glass card with a fine light edge.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Space.l
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.glass.opacity(0.92), Theme.leather.opacity(0.96)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
    }
}

/// An icon in a small rounded square, the lead of every list row.
struct IconBadge: View {
    var symbol: String
    var tint: Color = Theme.gold
    var size: CGFloat = 38
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(tint.opacity(0.13)))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(tint.opacity(0.28), lineWidth: 0.75))
            .accessibilityHidden(true)
    }
}

/// A list row: icon, title and subtitle, a figure and a small line under it, optional chevron.
struct ListRow: View {
    var symbol: String
    var tint: Color = Theme.gold
    var title: String
    var subtitle: String = ""
    var trailing: String = ""
    var trailingSub: String = ""
    var trailingTint: Color = Theme.ivory
    var chevron = false
    var body: some View {
        HStack(spacing: Theme.Space.m) {
            IconBadge(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.bodyText.weight(.medium)).foregroundStyle(Theme.ivory).lineLimit(2)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(Theme.ivoryFaint).lineLimit(2) }
            }
            Spacer(minLength: 8)
            if !trailing.isEmpty || !trailingSub.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    if !trailing.isEmpty { Text(trailing).font(.system(.subheadline).weight(.semibold).monospacedDigit()).foregroundStyle(trailingTint) }
                    if !trailingSub.isEmpty { Text(trailingSub).font(.caption2).foregroundStyle(Theme.ivoryFaint) }
                }
            }
            if chevron { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.ivoryFaint) }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// The top of a main screen: a small line (date, place), then the big title.
struct ScreenHeader<Trailing: View>: View {
    var eyebrow: String
    var title: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                if !eyebrow.isEmpty { Text(eyebrow).font(.subheadline).foregroundStyle(Theme.ivoryMuted) }
                Text(title).font(.system(size: 32, weight: .bold)).foregroundStyle(Theme.cream)
            }
            Spacer()
            trailing()
        }
    }
}

/// The prominent champagne-gold action button (Next day).
struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .default).weight(.semibold))
            .foregroundStyle(Color(red: 0.06, green: 0.05, blue: 0.04))
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).fill(Theme.goldGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75)
            )
            .shadow(color: Theme.gold.opacity(0.18), radius: 12, y: 4)
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

/// The heading of a card ("Upcoming payments").
struct SectionLabel: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.bodyText.weight(.semibold)).foregroundStyle(Theme.ivory)
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
            Text(amount == 0 ? format(0) : (amount > 0 ? "+" : "−") + format(abs(amount))).font(.system(.caption, design: .default).weight(.semibold).monospacedDigit())
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

/// Small status capsule, optionally with an icon.
struct Chip: View {
    var text: String
    var tint: Color = Theme.ivoryMuted
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.14)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.3), lineWidth: 0.5))
    }
}

/// A label with a figure beneath it.
struct Stat: View {
    var label: String
    var value: String
    var tint: Color = Theme.ivory
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
            Text(value).font(.figure(18, weight: .bold)).foregroundStyle(tint).minimumScaleFactor(0.7).lineLimit(1)
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
            Text(value).font(.system(.subheadline, design: .default).monospacedDigit()).foregroundStyle(tint)
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
                .font(.system(.body, design: .default).monospacedDigit())
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

/// Horizontal section switcher: dark pills, the chosen one lit with a light edge. A small red count may sit on a pill.
struct SectionTabs<T: Hashable>: View {
    var items: [T]
    var title: (T) -> String
    @Binding var selection: T
    var badge: (T) -> Int = { _ in 0 }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    let on = selection == item
                    Button { selection = item; Haptics.choose() } label: {
                        HStack(spacing: 5) {
                            Text(title(item)).font(.subheadline.weight(.medium))
                            if badge(item) > 0 {
                                Text("\(badge(item))").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(Theme.loss))
                            }
                        }
                        .foregroundStyle(on ? Theme.ivory : Theme.ivoryMuted)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(on ? Theme.pillOn : Theme.pill))
                        .overlay(Capsule().strokeBorder(on ? Theme.gold.opacity(0.45) : Theme.hairline, lineWidth: 0.75))
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

/// A circular gauge with a figure in the middle (capacity use, demand coverage, rating).
struct Ring: View {
    var label: String
    var fraction: Double
    var centre: String
    var tint: Color = Theme.gold
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Theme.hairline, lineWidth: 6)
                Circle().trim(from: 0, to: CGFloat(min(1, max(0.005, fraction))))
                    .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                Text(centre).font(.system(.subheadline, design: .default).weight(.semibold).monospacedDigit()).foregroundStyle(Theme.ivory)
                    .minimumScaleFactor(0.6).lineLimit(1).padding(6)
            }
            .frame(width: 66, height: 66)
            Text(label).font(.caption2).foregroundStyle(Theme.ivoryMuted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Compact bronze button for the main answer on a card.
struct SmallGoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(red: 0.06, green: 0.05, blue: 0.04))
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous).fill(Theme.goldGradient))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Compact outlined button for the other answers.
struct SmallOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.ivory)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous).fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75))
    }
}
