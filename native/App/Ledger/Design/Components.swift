import SwiftUI
import Countries

/// The house container (new look): a bordered card on the #151617 surface. Radius per mockup: `Theme.Radius.hero` (16) for the big
/// summary boxes, `.card` (14, the default) for standard cards, `.row` (12) for compact row cards, `.table` (8) for sharp boxes.
/// `rule` is kept so older call sites compile; it no longer draws anything. `padding: 0` for content that pads itself.
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    var rule = true
    var radius: CGFloat = Theme.Radius.card
    var fill: Color? = nil
    var stroke: Color? = nil
    @ViewBuilder var content: () -> Content
    @Environment(\.outsidePalette) private var palette
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(fill ?? palette.card))
            .overlay(shape.strokeBorder(stroke ?? palette.line, lineWidth: 1))
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
                Text(title.tidyText).font(.system(size: 14.5)).foregroundStyle(Theme.ivory).lineLimit(2)
                if !subtitle.isEmpty { Text(subtitle.tidyText).font(.caption).foregroundStyle(Theme.ivoryFaint).lineLimit(2) }
            }
            Spacer(minLength: 8)
            if !trailing.isEmpty || !trailingSub.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    if !trailing.isEmpty { Text(trailing.tidyText).font(.system(size: 14.5).monospacedDigit()).foregroundStyle(trailingTint) }
                    if !trailingSub.isEmpty { Text(trailingSub.tidyText).font(.caption2).foregroundStyle(Theme.ivoryFaint) }
                }
            }
            if chevron { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.ivoryFaint) }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

/// The one filled control: a champagne pill with dark text. House rule: ONLY Next Day uses it; every other action is `QuietButton` /
/// `QuietButtonStyle` (outline) or `SmallOutlineButton`.
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

/// A quiet text button with a champagne outline (8 pt corners) for secondary actions. `QuietButton` in NewLook.swift is the same as a view.
struct QuietButtonStyle: ButtonStyle {
    var tint: Color? = nil
    @Environment(\.outsidePalette) private var palette
    func makeBody(configuration: Configuration) -> some View {
        let tint: Color = self.tint ?? palette.accent
        return configuration.label
            .font(.system(.subheadline).weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(tint.opacity(0.7), lineWidth: 1))
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

/// A small status: a dot and a word. No capsule, no border.
struct Chip: View {
    var text: String
    var tint: Color = Theme.ivoryMuted
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) } else { Circle().fill(tint).frame(width: 5, height: 5) }
            Text(text.tidyText).font(.system(size: 11.5, weight: .medium))
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
    @Environment(\.outsidePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10.5)).foregroundStyle(palette.inkFaint).lineLimit(1)
            Text(value.tidyText).font(.figure(15.5, weight: .semibold)).foregroundStyle(tint).minimumScaleFactor(0.7).lineLimit(1)
            if !sub.isEmpty { Text(sub.tidyText).font(.system(size: 10)).foregroundStyle(palette.inkFaint).lineLimit(1) }
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
    @Environment(\.outsidePalette) private var palette
    func body(content: Content) -> some View {
        content
            .ledgerScreen()
            .background(palette.ground.ignoresSafeArea())
            .foregroundStyle(palette.ink)
    }
}

private struct TabBarClearanceKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues {
    var tabBarClearance: CGFloat {
        get { self[TabBarClearanceKey.self] }
        set { self[TabBarClearanceKey.self] = newValue }
    }
}

/// Keeps scrolled content from ever drawing over the status bar, the Back button or the title. It does not depend on the global
/// `UINavigationBar` appearance: the navigation bar gets the page colour as an always-visible background (the bar then clips the
/// scroll content under it), and a page-coloured strip the height of the top safe area is pinned above the scroll container as a
/// second guard for screens without a navigation bar. Applied by `ledgerBackground()`, so every screen gets it.
struct LedgerScreen: ViewModifier {
    /// Height of the floating tab bar plus margin (0 where there is none); set by `PhoneShell`.
    @Environment(\.tabBarClearance) private var tabBarClearance
    @Environment(\.outsidePalette) private var palette

    func body(content: Content) -> some View {
        content
            .environment(\.tabBarClearance, 0)
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: tabBarClearance) }
            .toolbarBackground(palette.ground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: 0).background(palette.ground.ignoresSafeArea(edges: .top))
            }
    }
}
extension View {
    func ledgerScreen() -> some View { modifier(LedgerScreen()) }
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

/// Chips that wrap onto further lines instead of scrolling sideways. Put the chips directly inside (a Group is fine).
struct WrapRow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? 320, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(bounds.width, subviews)
        for (i, f) in r.frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        var frames: [CGRect] = []
        for v in subviews {
            let s = v.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: s))
            x += s.width + spacing; rowH = max(rowH, s.height); maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowH), frames)
    }
}

/// Section switcher. It never scrolls sideways. Up to 5 items in one equal-width row when every title fits; more than 5 items: a fixed
/// row of `primary` (default the first 4) plus a "More" menu listing the rest. When the titles of that row do not fit the width, the
/// row keeps its first three plus "More". The chosen fixed item has a champagne underline; the menu marks the chosen item with a checkmark and "More"
/// turns accent when the choice is inside it. A small red count may sit beside a title (counts of hidden items roll up onto "More").
/// Tap targets are 44 pt tall.
struct SectionTabs<T: Hashable>: View {
    var items: [T]
    var primary: [T]? = nil
    var title: (T) -> String
    @Binding var selection: T
    var badge: (T) -> Int = { _ in 0 }
    /// Second-level row (sub-navigation under another tab row): small capitals, no underline bar, a faint track.
    var sub: Bool = false
    @Environment(\.outsidePalette) private var palette

    /// The items kept in the fixed row. `condensed` is the narrow variant used when the full row does not fit.
    private func fixed(condensed: Bool) -> [T] {
        if let primary {
            let p = primary.filter { items.contains($0) }
            let all = p.count < items.count ? p : items
            return condensed && all.count > 3 ? Array(all.prefix(3)) : all
        }
        if condensed { return items.count <= 3 ? items : Array(items.prefix(3)) }
        return items.count <= 5 ? items : Array(items.prefix(4))
    }

    private func countView(_ n: Int) -> some View {
        Text("\(n)").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.page)
            .padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(Theme.loss))
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tabRow(fixed(condensed: false))
            tabRow(fixed(condensed: true))
        }
        .padding(.horizontal, Theme.Space.margin)
        .background(alignment: .bottom) { if !sub { Hairline() } }
    }

    /// The row of tabs: the fixed items, then a "More" menu for the rest. The width is shared equally, so a row never needs to scroll.
    private func tabRow(_ fixed: [T]) -> some View {
        let rest: [T] = items.filter { !fixed.contains($0) }
        return HStack(spacing: 6) {
            ForEach(fixed, id: \.self) { item in
                let on = selection == item
                Button { selection = item; Haptics.choose() } label: {
                    cell(title(item), count: badge(item), on: on, more: false, spread: true)
                }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
            }
            if !rest.isEmpty { moreMenu(rest) }
        }
    }

    private func moreMenu(_ rest: [T]) -> some View {
        let inRest = rest.contains(selection)
        return Menu {
            ForEach(rest, id: \.self) { item in
                Button { selection = item; Haptics.choose() } label: {
                    let n = badge(item)
                    let t = n > 0 ? "\(title(item)) (\(n))" : title(item)
                    if selection == item { Label(t, systemImage: "checkmark") } else { Text(t) }
                }
            }
        } label: {
            cell(inRest ? title(selection) : "More", count: rest.reduce(0) { $0 + badge($1) }, on: inRest, more: true, spread: true)
        }
    }

    private func cell(_ text: String, count: Int, on: Bool, more: Bool, spread: Bool) -> some View {
        HStack(spacing: 3) {
            Text(sub ? text.uppercased() : text)
                .font(.system(size: sub ? 11 : 14, weight: on ? .semibold : .regular))
                .tracking(sub ? 0.6 : 0)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if more { Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)) }
            if count > 0 { countView(count) }
        }
        .foregroundStyle(on ? palette.accent : palette.inkFaint)
        .padding(.horizontal, spread ? 0 : 12)
        .frame(maxWidth: spread ? .infinity : nil, minHeight: sub ? 34 : 44)
        .background(RoundedRectangle(cornerRadius: 6).fill(sub && on ? palette.hairline : Color.clear))
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { if on && !sub { Rectangle().fill(palette.accent).frame(height: 1.5) } }
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
///
/// `amount` (in `currency`) is the money the action spends. Only a reversible spend that supplies it can skip the question, when the
/// player chose a size under which they do not want to be asked (Settings, "How much I decide"). Anything `destructive` (dismissals,
/// wind-up, sales, closing, anything irreversible) and anything without an amount always asks.
struct PendingAction: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var button: String
    var destructive = false
    var amount: Double? = nil
    var currency: Currency? = nil
    var run: () -> Void
}

/// The one money-size rule for confirmations. A device preference, not game state: it is not in the save and never travels with it.
enum ConfirmThreshold {
    /// Reference-economy sizes (scaled to the spend's own currency like every price). Step 0 = always ask.
    static let sizes: [Double] = [0, 500, 2_000, 10_000, 50_000, 250_000]
    static let key = "askBelowStep"
    static var step: Int {
        get { min(max(UserDefaults.standard.integer(forKey: key), 0), sizes.count - 1) }
        set { UserDefaults.standard.set(min(max(newValue, 0), sizes.count - 1), forKey: key) }
    }

    /// True when `p` may run without asking. Pure so it can be tested as a decision table.
    static func skips(_ p: PendingAction, step: Int) -> Bool {
        decide(destructive: p.destructive, amount: p.amount, limit: p.currency.map { limit(step: step, currency: $0) })
    }
    static func skips(_ p: PendingAction) -> Bool { skips(p, step: step) }

    static func decide(destructive: Bool, amount: Double?, limit: Double?) -> Bool {
        guard !destructive, let amount, let limit, limit > 0 else { return false }
        return amount < limit
    }
    /// The size in this currency under which the player is not asked (0 = always asked).
    static func limit(step: Int, currency: Currency) -> Double {
        let i = min(max(step, 0), sizes.count - 1)
        return sizes[i] == 0 ? 0 : currency.scaledPrice(sizes[i])
    }
}

extension View {
    /// Shows `pending` as a confirmation dialog; confirming runs it, cancelling drops it. A reversible spend under the player's chosen
    /// size runs at once instead (its own result message says what was spent); destructive and irreversible actions always ask.
    func confirmAction(_ pending: Binding<PendingAction?>) -> some View {
        confirmationDialog(pending.wrappedValue?.title ?? "",
                           isPresented: Binding(get: { pending.wrappedValue.map { !ConfirmThreshold.skips($0) } ?? false },
                                                set: { if !$0 { pending.wrappedValue = nil } }),
                           titleVisibility: .visible, presenting: pending.wrappedValue) { p in
            Button(p.button, role: p.destructive ? .destructive : nil) { p.run(); pending.wrappedValue = nil }
        } message: { p in Text(p.message.tidyMoney) }
        .onChange(of: pending.wrappedValue?.id) { _, _ in
            if let p = pending.wrappedValue, ConfirmThreshold.skips(p) { pending.wrappedValue = nil; p.run() }
        }
    }
}

/// Compact segmented control for a choice made inside a page (Minimal / Normal / Thorough, Shares / Crypto / Funds). A filled
/// track with the chosen option raised, so it never reads as page navigation (the underlined SectionTabs).
struct SegmentedChoice<T: Hashable>: View {
    var items: [T]
    var title: (T) -> String
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let on = selection == item
                Button { selection = item; Haptics.choose() } label: {
                    Text(title(item))
                        .font(.system(size: 13, weight: on ? .semibold : .regular))
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .foregroundStyle(on ? Theme.ivory : Theme.ivoryMuted)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(RoundedRectangle(cornerRadius: 7).fill(on ? Theme.hairline : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? Theme.gold.opacity(0.7) : Color.clear, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.ivory.opacity(0.05)))
    }
}
