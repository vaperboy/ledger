import SwiftUI
import Countries

/// A section of a screen. Ivory Ledger has no boxes: a section is a hairline above and space around the content, so the old
/// card call sites keep working and simply lose their frame.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Space.l
    var rule = true
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(.vertical, padding == 0 ? 0 : padding * 0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { if rule { Hairline() } }
    }
}

/// A titled section: small-caps label on the left, an optional note or action on the right, then the content.
struct LedgerSection<Content: View, Trailing: View>: View {
    var title: String
    var rule = true
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).capsLabel()
                Spacer(minLength: 8)
                trailing()
            }
            content()
        }
        .padding(.top, Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { if rule { Hairline() } }
    }
}
extension LedgerSection where Trailing == EmptyView {
    init(_ title: String, rule: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, rule: rule, trailing: { EmptyView() }, content: content)
    }
}

/// A small icon at the lead of a row: a plain glyph, no tile.
struct IconBadge: View {
    var symbol: String
    var tint: Color = Theme.gold
    var size: CGFloat = 38
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: max(13, size * 0.38), weight: .regular))
            .foregroundStyle(tint)
            .frame(width: max(20, size * 0.6), height: max(20, size * 0.6))
            .accessibilityHidden(true)
    }
}

/// A list row: glyph, title and subtitle, a figure and a small line under it, optional chevron.
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
                Text(title).font(.system(size: 14.5)).foregroundStyle(Theme.ivory).lineLimit(2)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(Theme.ivoryFaint).lineLimit(2) }
            }
            Spacer(minLength: 8)
            if !trailing.isEmpty || !trailingSub.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    if !trailing.isEmpty { Text(trailing).font(.system(size: 14.5).monospacedDigit()).foregroundStyle(trailingTint) }
                    if !trailingSub.isEmpty { Text(trailingSub).font(.caption2).foregroundStyle(Theme.ivoryFaint) }
                }
            }
            if chevron { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.ivoryFaint) }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

/// The top of a main screen: a small line (date, place), then the title in serif.
struct ScreenHeader<Trailing: View>: View {
    var eyebrow: String
    var title: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                if !eyebrow.isEmpty { Text(eyebrow).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }
                Text(title).font(.serifTitle(28)).foregroundStyle(Theme.ivory)
            }
            Spacer()
            trailing()
        }
    }
}

/// The one filled control: a champagne pill with dark text.
struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color(red: 0.09, green: 0.075, blue: 0.055))
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Capsule().fill(Theme.gold))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A quiet text button with a hairline outline for secondary actions.
struct QuietButtonStyle: ButtonStyle {
    var tint: Color = Theme.gold
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline).weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .overlay(Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 0.75))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The heading of a section ("Upcoming payments"): small caps in champagne.
struct SectionLabel: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).capsLabel() }
}

/// A green/red change line: arrow, amount and (when meaningful) percent. Never shows a misleading percentage.
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
        .accessibilityElement(children: .combine)
    }
}

/// A line chart without axes, for real history. Draws nothing misleading for fewer than two points.
struct Sparkline: View {
    var values: [Double]
    var tint: Color = Theme.gold
    var filled = true
    var body: some View {
        GeometryReader { geo in
            if values.count >= 2, let lo = values.min(), let hi = values.max() {
                let span = max(hi - lo, abs(hi) * 0.002, 1)
                let pts: [CGPoint] = values.enumerated().map { i, v in
                    CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(values.count - 1), y: geo.size.height * (1 - CGFloat((v - lo) / span)) * 0.9 + geo.size.height * 0.05)
                }
                ZStack {
                    if filled {
                        Path { p in
                            p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                            for pt in pts { p.addLine(to: pt) }
                            p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                            p.closeSubpath()
                        }.fill(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                    }
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }.stroke(tint, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
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
                        RoundedRectangle(cornerRadius: 1).fill(Theme.change(v)).frame(height: max(2, geo.size.height / 2 * CGFloat(abs(v) / peak)))
                        Spacer(minLength: 0).frame(maxHeight: v < 0 ? .infinity : 0)
                    }
                }
            }
        }
    }
}

/// A small status: a dot and a word. No capsule, no border.
struct Chip: View {
    var text: String
    var tint: Color = Theme.ivoryMuted
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) } else { Circle().fill(tint).frame(width: 5, height: 5) }
            Text(text).font(.system(size: 11.5, weight: .medium))
        }
        .foregroundStyle(tint)
    }
}

/// A label with a figure beneath it.
struct Stat: View {
    var label: String
    var value: String
    var tint: Color = Theme.ivory
    var sub: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
            Text(value).font(.figure(15.5, weight: .semibold)).foregroundStyle(tint).minimumScaleFactor(0.7).lineLimit(1)
            if !sub.isEmpty { Text(sub).font(.system(size: 10)).foregroundStyle(Theme.ivoryFaint).lineLimit(1) }
        }
    }
}

/// Key figures in a joined row, separated by vertical hairlines. `columns` per row; a second row follows the first.
struct KeyFigures: View {
    struct Item: Identifiable { var id = UUID(); var label: String; var value: String; var tint: Color = Theme.ivory; var sub: String = "" }
    var items: [Item]
    var columns = 3
    var body: some View {
        let rows = stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                if r > 0 { Hairline().padding(.vertical, 9) }
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { i, it in
                        Stat(label: it.label, value: it.value, tint: it.tint, sub: it.sub)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, i == 0 ? 0 : 10)
                            .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(Theme.hairline).frame(width: 0.5) } }
                    }
                    ForEach(0..<(columns - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Hairline() }
    }
}

struct LedgerBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.page.ignoresSafeArea())
            .foregroundStyle(Theme.ivory)
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
            Text(label).font(.system(size: 14)).foregroundStyle(Theme.ivoryMuted)
            Spacer()
            Text(value).font(.system(size: 14).monospacedDigit()).foregroundStyle(tint)
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
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(focused ? Theme.gold : Theme.hairline).frame(height: focused ? 1 : 0.5) }
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } } }
    }
}

/// Section switcher: text with a champagne underline under the chosen one and a hairline beneath the row.
/// A small red count may sit beside a title.
struct SectionTabs<T: Hashable>: View {
    var items: [T]
    var title: (T) -> String
    @Binding var selection: T
    var badge: (T) -> Int = { _ in 0 }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(items, id: \.self) { item in
                    let on = selection == item
                    Button { selection = item; Haptics.choose() } label: {
                        HStack(spacing: 5) {
                            Text(title(item)).font(.system(size: 14, weight: on ? .semibold : .regular))
                            if badge(item) > 0 {
                                Text("\(badge(item))").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.page)
                                    .padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(Theme.loss))
                            }
                        }
                        .foregroundStyle(on ? Theme.ivory : Theme.ivoryFaint)
                        .padding(.vertical, 9)
                        .overlay(alignment: .bottom) { if on { Rectangle().fill(Theme.gold).frame(height: 1.5) } }
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Space.margin)
        }
        .background(alignment: .bottom) { Hairline() }
    }
}

/// A 0–100 meter such as reputation or quality: a thin bar.
struct Meter: View {
    var label: String
    var value: Double
    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).frame(minWidth: 90, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule().fill(Theme.gold).frame(width: max(3, g.size.width * CGFloat(min(100, max(0, value)) / 100)))
                }
            }.frame(height: 3)
            Text("\(Int(value.rounded()))").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ivory).frame(width: 34, alignment: .trailing)
        }
    }
}

/// A thin labelled bar for a share (capacity used, demand met): label, bar, percent.
struct RateBar: View {
    var label: String
    var fraction: Double
    var tint: Color = Theme.gold
    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).frame(width: 104, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule().fill(tint).frame(width: max(3, g.size.width * CGFloat(min(1, max(0, fraction)))))
                }
            }.frame(height: 4)
            Text(String(format: "%.0f%%", fraction * 100)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.ivory).frame(width: 42, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A circular gauge with a figure in the middle. Thin stroke; kept for places where a ring reads better than a bar.
struct Ring: View {
    var label: String
    var fraction: Double
    var centre: String
    var tint: Color = Theme.gold
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Theme.hairline, lineWidth: 3)
                Circle().trim(from: 0, to: CGFloat(min(1, max(0.005, fraction))))
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                Text(centre).font(.system(.subheadline, design: .default).weight(.semibold).monospacedDigit()).foregroundStyle(Theme.ivory)
                    .minimumScaleFactor(0.6).lineLimit(1).padding(6)
            }
            .frame(width: 60, height: 60)
            Text(label).font(.caption2).foregroundStyle(Theme.ivoryMuted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Compact champagne button for the main answer on a decision.
struct SmallGoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(red: 0.09, green: 0.075, blue: 0.055))
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(Capsule().fill(Theme.gold))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Compact hairline button for the other answers.
struct SmallOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.ivory)
            .frame(maxWidth: .infinity, minHeight: 34)
            .overlay(Capsule().strokeBorder(Theme.ivory.opacity(configuration.isPressed ? 0.4 : 0.22), lineWidth: 0.75))
    }
}

/// One symbol per kind of business, used wherever a company or trade is listed.
enum TradeSymbol {
    static func of(family: String) -> String {
        switch family {
        case "svc": return "briefcase.fill"
        case "venue": return "fork.knife"
        case "retail": return "bag.fill"
        case "prod": return "gearshape.2.fill"
        case "logi": return "truck.box.fill"
        case "project": return "hammer.fill"
        case "rent": return "house.fill"
        case "fin": return "banknote.fill"
        case "energy": return "bolt.fill"
        case "club": return "sportscourt.fill"
        default: return "building.2.fill"
        }
    }
}

/// A consequential action waiting for confirmation: what it is, what it costs or changes, and what to run.
/// One shared confirmation instead of a hand-written dialog per button.
struct PendingAction: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var button: String
    var destructive = false
    var run: () -> Void
}

extension View {
    /// Shows `pending` as a confirmation dialog; confirming runs it, cancelling drops it.
    func confirmAction(_ pending: Binding<PendingAction?>) -> some View {
        confirmationDialog(pending.wrappedValue?.title ?? "", isPresented: Binding(get: { pending.wrappedValue != nil }, set: { if !$0 { pending.wrappedValue = nil } }),
                           titleVisibility: .visible, presenting: pending.wrappedValue) { p in
            Button(p.button, role: p.destructive ? .destructive : nil) { p.run(); pending.wrappedValue = nil }
        } message: { p in Text(p.message) }
    }
}
