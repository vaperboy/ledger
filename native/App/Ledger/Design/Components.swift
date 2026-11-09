import SwiftUI
import Countries
import enum Events.ConfirmRule

/// The surface primitive: a group or tile on the surface tone, no border. Inside another card or a section's group it draws flat
/// (just its content), and in a popup it is a flat group under a hairline, so a box never sits inside a box. An explicit `fill` or
/// `stroke` (a selected or warning state) is always drawn. `rule` is kept so older call sites compile. `padding: 0` for content that pads itself.
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    var rule = true
    var radius: CGFloat = Theme.Radius.card
    var fill: Color? = nil
    var stroke: Color? = nil
    @ViewBuilder var content: () -> Content
    @Environment(\.outsidePalette) private var palette
    @Environment(\.insidePopup) private var insidePopup
    @Environment(\.insideCard) private var insideCard
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        // The game's cards are translucent over the backdrop; outside apps and Reduce Transparency keep the solid fill.
        let cardFill: Color = palette == .game && !reduceTransparency ? palette.card.opacity(0.65) : palette.card
        let plain: Bool = fill == nil && stroke == nil
        if plain && insideCard {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if plain && insidePopup {
            content()
                .environment(\.insideCard, true)
                .padding(.vertical, padding * 0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Hairline() }
        } else {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            content()
                .environment(\.insideCard, true)
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    ZStack {
                        shape.fill(fill ?? cardFill)
                        shape.fill(LinearGradient(
                            colors: [Color.white.opacity(palette.isLight ? 0.10 : 0.05), .clear],
                            startPoint: .top, endPoint: .bottom
                        ))
                    }
                }
                .overlay {
                    if rule {
                        shape.strokeBorder(stroke ?? palette.line.opacity(0.9), lineWidth: 0.8)
                    } else if let stroke {
                        shape.strokeBorder(stroke, lineWidth: 1)
                    }
                }
        }
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

/// A list row with an SF symbol in front: `LedgerRow` in its compact density.
struct ListRow: View {
    var symbol: String
    var tint: Color = Theme.accent
    var title: String
    var subtitle: String = ""
    var trailing: String = ""
    var trailingSub: String = ""
    var trailingTint: Color = Theme.ink
    var chevron = false
    var body: some View {
        LedgerRow(leading: .symbol(symbol), leadingTint: tint, title: title, subtitle: subtitle, value: trailing, valueTint: trailingTint,
                  valueNote: trailingSub, chevron: chevron, density: .compact)
    }
}

/// Next Day: the primary button at full width.
struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonStyle(fullWidth: true).makeBody(configuration: configuration)
    }
}

/// A secondary action: the secondary button; `tint` colours the text.
struct QuietButtonStyle: ButtonStyle {
    var tint: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonStyle(tint: tint).makeBody(configuration: configuration)
    }
}

/// A line chart without axes, for real history. Draws nothing misleading for fewer than two points.
struct Sparkline: View {
    var values: [Double]
    var tint: Color = Theme.gold
    var filled = true
    var body: some View {
        GeometryReader { geo in
            if values.count >= 2, values.allSatisfy({ $0.isFinite }), geo.size.width.isFinite, geo.size.height.isFinite, let lo = values.min(), let hi = values.max() {
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
                        }.fill(tint.opacity(ChartPalette.areaOpacity))
                    }
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }.stroke(tint, style: StrokeStyle(lineWidth: ChartPalette.lineWidth, lineCap: .round, lineJoin: .round))
                }
            } else {
                Hairline().frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

/// A small status: a dot and a word. No capsule, no border.
struct Chip: View {
    @Environment(\.outsidePalette) private var P
    var text: String
    var tint: Color = Theme.ivoryMuted
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            if let symbol { Image(systemName: symbol).font(TextStep.label.fixedFont) } else { Circle().fill(tint.inPalette(P)).frame(width: 6, height: 6) }
            Text(text.tidyText).textStyle(.caption, tint: tint, weight: .medium)
        }
        .foregroundStyle(tint.inPalette(P))
    }
}

/// A label with a figure beneath it: `Figure` at the inline size.
struct Stat: View {
    var label: String
    var value: String
    var tint: Color = Theme.ink
    var sub: String = ""
    var body: some View {
        Figure(label: label, value: value, note: sub, tint: tint, size: .inline)
    }
}

/// Key figures in a joined row under a hairline: `FigureRow`. `columns` per row; a second row follows the first.
struct KeyFigures: View {
    struct Item: Identifiable {
        var id = UUID()
        var label: String
        var value: String
        var tint: Color = Theme.ink
        var sub: String = ""
        /// The number behind `value`: when set, the figure rolls and flashes as it changes.
        var live: Double? = nil
    }
    var items: [Item]
    var columns = 3
    var body: some View {
        FigureRow(items: items, columns: columns)
            .padding(.vertical, Theme.Space.m)
            .overlay(alignment: .top) { Hairline() }
    }
}

/// The page behind every screen: in the game palette a very soft vertical gradient from the page colour to a warmer, lifted tone and a faint
/// large champagne glow in the top right corner, drawn once and never animated. Outside apps keep their flat ground. Reduce Transparency
/// drops the glow.
struct LedgerBackdrop: View {
    var palette: OutsidePalette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if palette == .game {
                LinearGradient(colors: [Theme.page, Theme.pageLift], startPoint: .top, endPoint: .bottom)
                photo
                if !reduceTransparency {
                    // Faded out over the top inset so the status-bar guard strip (flat page colour) shows no edge.
                    RadialGradient(colors: [Theme.accent.opacity(0.07), Theme.accent.opacity(0)], center: .topTrailing, startRadius: 0, endRadius: 440)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0.07), .init(color: .black, location: 0.28)], startPoint: .top, endPoint: .bottom))
                }
            } else {
                palette.ground
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// The game's photo: blurred, darkened, with a dark scrim along the top and bottom so text stays readable. Slightly oversized so the blur has no soft edge.
    private var photo: some View {
        Color.clear
            .overlay {
                Image("HomeBackdrop")
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.12)
                    .blur(radius: 18)
            }
            .overlay { Color.black.opacity(0.10) }
            .overlay {
                LinearGradient(stops: [.init(color: Theme.page.opacity(0.6), location: 0), .init(color: Theme.page.opacity(0), location: 0.25),
                                       .init(color: Theme.page.opacity(0), location: 0.6), .init(color: Theme.page.opacity(0.7), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .clipped()
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// A card or tile floating on the backdrop: Liquid Glass in a rounded rectangle (raised cards carry the raised surface tint).
struct GlassSurface: ViewModifier {
    var radius: CGFloat
    var raised: Bool

    func body(content: Content) -> some View {
        content.modifier(LiquidGlass(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), tint: raised ? Theme.surfaceRaised : nil))
    }
}

/// The floating capsule (tab bar, Next day): Liquid Glass in a capsule.
struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View { content.modifier(LiquidGlass(shape: Capsule())) }
}

extension View {
    func glassSurface(radius: CGFloat = Theme.Radius.medium, raised: Bool = false) -> some View { modifier(GlassSurface(radius: radius, raised: raised)) }
    func glassCapsule() -> some View { modifier(GlassCapsule()) }
}

struct LedgerBackground: ViewModifier {
    @Environment(\.outsidePalette) private var palette
    func body(content: Content) -> some View {
        content
            .ledgerScreen()
            .background(LedgerBackdrop(palette: palette))
            .foregroundStyle(palette.ink)
            .environment(\.colorScheme, palette.isLight ? .light : .dark)
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
            .toolbarColorScheme(palette.isLight ? .light : .dark, for: .navigationBar)
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
    @Environment(\.outsidePalette) private var P
    var label: String
    var value: String
    var tint: Color = Theme.ivory
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(label).textStyle(.body, tint: P.inkSoft)
            Spacer(minLength: Theme.Space.s)
            Text(value).textStyle(.body, tint: tint, numeric: true)
        }
    }
}

/// A money input in the currency being shown. Converts what the player types into the game's accounting units.
struct AmountField: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var currency: Currency
    @Binding var amount: Double          // accounting units
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(currency.country.currencyCode).textStyle(.caption, tint: P.inkFaint, weight: .medium)
            TextField(title, text: $text)
                .keyboardType(.decimalPad)
                .focused($focused)
                .textStyle(.headline, numeric: true)
                .multilineTextAlignment(.trailing)
                .onChange(of: text) { _, new in
                    let cleaned = new.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
                    amount = (Double(cleaned) ?? 0) * currency.rate
                }
            // The decimal pad has no return key and a keyboard toolbar does not show inside a popup overlay: Done sits beside the field.
            if focused {
                Button("Done") { Haptics.play(.tap); focused = false }
                    .textStyle(.body, tint: P.accent, weight: .semibold)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("amount-done")
            }
        }
        .padding(.vertical, Theme.Space.s)
        .overlay(alignment: .bottom) { Rectangle().fill(focused ? P.focus : P.hairline).frame(height: focused ? 1 : 0.5) }
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
    /// Tabs that hold something new or important get a small marker in the app's colour (a dot; red-filled when `urgent`).
    var dots: ((T) -> Bool)? = nil
    var urgent: Bool = false
    /// Second-level row (sub-navigation under another tab row): small capitals, no underline bar, a faint track.
    var sub: Bool = false
    /// An accessibility identifier per item (nil: none). It takes precedence over an identifier set on the whole row.
    var itemIdentifier: ((T) -> String)? = nil
    /// Every item in one sideways-scrolling row (the chosen one scrolled into view) instead of a fixed row plus "More".
    var scrolls: Bool = false
    @Environment(\.outsidePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        RedBubble(count: n, size: .small)
    }

    var body: some View {
        if scrolls {
            scrollRow
                .background(alignment: .bottom) { if !sub { Hairline() } }
        } else {
            ViewThatFits(in: .horizontal) {
                tabRow(fixed(condensed: false), tight: false)
                tabRow(fixed(condensed: true), tight: true)
            }
            .padding(.horizontal, Theme.Space.margin)
            .background(alignment: .bottom) { if !sub { Hairline() } }
        }
    }

    /// The `scrolls` variant: all items at their natural width, the page margin as content inset, the selection kept in view.
    private var scrollRow: some View {
        ScrollViewReader { (proxy: ScrollViewProxy) in
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Space.xs) {
                    ForEach(items, id: \.self) { (item: T) in
                        tabButton(item, tight: false).id(item)
                    }
                }
                .padding(.horizontal, Theme.Space.margin)
            }
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { (_: T, new: T) in
                Motion.animate(Motion.quick(reduceMotion)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }

    private func tabButton(_ item: T, tight: Bool) -> some View {
        let on: Bool = selection == item
        return Button { selection = item; Haptics.choose() } label: {
            cell(title(item), count: badge(item), on: on, more: false, tight: tight)
                .flagMarker(!on && (dots?(item) ?? false), important: urgent, alignment: .topTrailing)
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
        .modifier(OptionalIdentifier(identifier: itemIdentifier?(item) ?? ""))
    }

    /// The row of tabs: the fixed items, then a "More" menu for the rest. The width is shared equally, so a row never needs to scroll.
    private func tabRow(_ fixed: [T], tight: Bool) -> some View {
        let rest: [T] = items.filter { !fixed.contains($0) }
        return HStack(spacing: Theme.Space.xs) {
            ForEach(fixed, id: \.self) { (item: T) in
                tabButton(item, tight: tight)
            }
            if !rest.isEmpty { moreMenu(rest, tight: tight) }
        }
    }

    private func moreMenu(_ rest: [T], tight: Bool) -> some View {
        let inRest = rest.contains(selection)
        return Menu {
            ForEach(rest, id: \.self) { item in
                Button { selection = item; Haptics.choose() } label: {
                    let n = badge(item)
                    let t = n > 0 ? "\(title(item)) (\(n))" : title(item)
                    if selection == item { Label(t, systemImage: "checkmark") } else { Text(t) }
                }
                .modifier(OptionalIdentifier(identifier: itemIdentifier?(item) ?? ""))
            }
        } label: {
            cell(inRest ? title(selection) : "More", count: rest.reduce(0) { $0 + badge($1) }, on: inRest, more: true, tight: tight)
        }
    }

    private func cell(_ text: String, count: Int, on: Bool, more: Bool, tight: Bool) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Text(sub ? text.uppercased() : text)
                .textStyle(sub ? .label : .body, tint: on ? palette.accent : palette.inkFaint, weight: on || sub ? .semibold : .regular)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: !tight, vertical: false)
            if more { Image(systemName: "chevron.down").font(TextStep.label.fixedFont) }
            if count > 0 { countView(count) }
        }
        .foregroundStyle(on ? palette.accent : palette.inkFaint)
        .padding(.horizontal, tight ? Theme.Space.xxs : Theme.Space.s)
        .frame(maxWidth: .infinity, minHeight: sub ? 34 : 44)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(sub && on ? palette.inset : Color.clear))
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { if on && !sub { Rectangle().fill(palette.accent).frame(height: 1.5) } }
    }
}

/// A 0–100 meter such as reputation or quality: label, the one progress line, the level word.
struct Meter: View {
    var label: String
    var value: Double
    var scale: Words.Scale = .quality
    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Text(label).textStyle(.caption).frame(minWidth: 90, alignment: .leading)
            ProgressLine(fraction: min(100, max(0, value)) / 100)
            Text(Words.level(value, scale: scale)).textStyle(.caption, tint: Theme.ink).frame(minWidth: 34, alignment: .trailing)
        }
    }
}

/// A labelled share (capacity used, demand met): label, the one progress line, percent. Give `word` for a standing that is not
/// measured in real life (reputation, brand, awareness): the bar then carries a word instead of a percent.
struct RateBar: View {
    var label: String
    var fraction: Double
    var tint: Color = Theme.accent
    var word: String? = nil
    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Text(label).textStyle(.caption).lineLimit(1).minimumScaleFactor(0.85).frame(width: 104, alignment: .leading)
            ProgressLine(fraction: fraction, tint: tint)
            if let word {
                Text(word).textStyle(.caption, tint: Theme.ink).lineLimit(1).minimumScaleFactor(0.8).frame(minWidth: 42, alignment: .trailing)
            } else {
                Text(String(format: "%.0f%%", fraction * 100)).textStyle(.caption, tint: Theme.ink, numeric: true).frame(width: 42, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The other answers beside a primary one: the secondary button at full width.
struct SmallOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonStyle(fullWidth: true).makeBody(configuration: configuration)
    }
}

/// A consequential action waiting for the in-game "Are you sure" popup: what it is, what it costs or changes, and what to run.
/// One shared popup instead of a hand-written dialog per button.
///
/// The popup shows ONLY for a spend at or above the size the player chose (Settings, "Ask before spending") and for an irreversible
/// action. Every other action runs at once when it is set. So a SPEND must give `amount` (in `currency`), or it would run unasked;
/// anything irreversible (dismissals, wind-up, sales, closing, conversions) is `destructive`, which always asks (red button).
struct PendingAction: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var button: String
    var destructive = false
    /// Asks whatever the size, without the red button: a commitment of a size the screen cannot state (a loan, a bulk set-up).
    var alwaysAsk = false
    var amount: Double? = nil
    var currency: Currency? = nil
    /// What can go wrong, shown under the effect. Empty: nothing extra (an irreversible action says it cannot be undone).
    var risk = ""
    /// The event's accent; nil: red when destructive, champagne for a spend, otherwise neutral.
    var tone: PopupTone? = nil
    /// SF Symbol of the popup's icon ring; nil: the tone's own symbol.
    var icon: String? = nil
    var run: () -> Void
}

/// The one money-size rule for confirmations. A device preference, not game state: it is not in the save and never travels with it.
enum ConfirmThreshold {
    /// Reference-economy sizes (scaled to the spend's own currency like every price). Step 0 = always ask a spend.
    static let sizes: [Double] = [0, 500, 2_000, 10_000, 50_000, 250_000]
    /// What a new player gets: small everyday spends are not asked (step 2, 2,000 at the reference level).
    static let defaultStep = 2
    static let key = "askBelowStep"
    /// Set by the game store: what managers may spend without asking (home currency) and that currency's rate.
    static var delegated: (() -> (limit: Double, rate: Double))?
    static var step: Int {
        get {
            guard UserDefaults.standard.object(forKey: key) != nil else { return defaultStep }
            return min(max(UserDefaults.standard.integer(forKey: key), 0), sizes.count - 1)
        }
        set { UserDefaults.standard.set(min(max(newValue, 0), sizes.count - 1), forKey: key) }
    }

    /// True when `p` runs without asking. Pure so it can be tested as a decision table.
    static func skips(_ p: PendingAction, step: Int) -> Bool {
        var size: Double? = nil
        if let currency = p.currency {
            size = limit(step: step, currency: currency)
            // With a manager in charge the limit grows with net worth: a 10k spend is not asked of someone worth 10M.
            if let d = delegated?(), d.limit > 0, abs(d.rate - currency.rate) < 1e-9 { size = max(size ?? 0, d.limit) }
        }
        return !ConfirmRule.asks(irreversible: p.destructive || p.alwaysAsk, amount: p.amount, limit: size)
    }
    static func skips(_ p: PendingAction) -> Bool { skips(p, step: step) }

    /// The size in this currency under which the player is not asked (0 = a spend is always asked).
    static func limit(step: Int, currency: Currency) -> Double {
        let i = min(max(step, 0), sizes.count - 1)
        return sizes[i] == 0 ? 0 : currency.scaledPrice(sizes[i])
    }
}

/// Holds the popup for a `PendingAction`: setting `pending` either runs it at once (a small or free action) or opens the popup.
/// The question is registered with the app's popup host (highest priority, above any popup or sheet that raised it). Nothing is
/// presented, so no screen underneath changes.
private struct ConfirmActionModifier: ViewModifier {
    @Binding var pending: PendingAction?
    @State private var asked: PendingAction?
    @Environment(\.outcomeStore) private var outcomeStore

    func body(content: Content) -> some View {
        let current: PendingAction? = asked
        return content
            .onChange(of: pending?.id) { _, _ in settle() }
            .modifier(HostedPopupModifier(key: current.map { (p: PendingAction) -> String in "confirm-" + p.id.uuidString } ?? "confirm", priority: .confirm,
                                          active: current != nil, draw: .raw,
                                          onClose: { if let p = current { answer(p, go: false) } }, onDismiss: nil,
                                          card: { () -> AnyView in
                                              guard let p = current else { return AnyView(EmptyView()) }
                                              return AnyView(ConfirmPopup(action: p, onConfirm: { answer(p, go: true) }, onCancel: { answer(p, go: false) }))
                                          }))
    }

    private func settle() {
        guard let p = pending else { asked = nil; return }
        if ConfirmThreshold.skips(p) {
            pending = nil
            run(p)
        } else {
            asked = p
        }
    }

    private func answer(_ p: PendingAction, go: Bool) {
        asked = nil
        pending = nil
        // Once the popup is gone, so the action may open or close screens without clashing with it.
        if go { DispatchQueue.main.async { run(p) } }
    }

    /// Runs the action; the game store then tells its outcome in one popup (or just runs it where no store is in the environment).
    private func run(_ p: PendingAction) {
        if let s = outcomeStore { s.runConfirmed(p) } else { p.run() }
    }
}

/// Runs `show` once a sheet that is closing has gone, so the popup it opens is not lost to the sheet's dismissal.
func presentAfterSheet(_ show: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + Motion.sheetLeaveSeconds, execute: show)
}

extension View {
    /// Shows `pending` as the in-game "Are you sure" popup when it is a spend above the player's size or irreversible; any other
    /// action runs at once. Confirming runs it, cancelling drops it.
    func confirmAction(_ pending: Binding<PendingAction?>) -> some View {
        modifier(ConfirmActionModifier(pending: pending))
    }
}

/// Segmented control for a choice made inside a page (Minimal / Normal / Thorough): the one segment look (`SegmentTrack`), so it never
/// reads as page navigation (the underlined SectionTabs).
struct SegmentedChoice<T: Hashable>: View {
    var items: [T]
    var title: (T) -> String
    @Binding var selection: T
    /// Options that hold something new get a small marker in the app's colour.
    var badges: ((T) -> Bool)? = nil

    var body: some View {
        SegmentTrack(items: items, title: title, selection: $selection, identifier: { (_: T) -> String in "" }, badges: badges)
    }
}
