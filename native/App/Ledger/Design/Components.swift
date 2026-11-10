import SwiftUI
import Countries
import enum Events.ConfirmRule

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

struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonStyle(fullWidth: true).makeBody(configuration: configuration)
    }
}

struct QuietButtonStyle: ButtonStyle {
    var tint: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonStyle(tint: tint).makeBody(configuration: configuration)
    }
}

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

struct Stat: View {
    var label: String
    var value: String
    var tint: Color = Theme.ink
    var sub: String = ""
    var body: some View {
        Figure(label: label, value: value, note: sub, tint: tint, size: .inline)
    }
}

struct KeyFigures: View {
    struct Item: Identifiable {
        var id = UUID()
        var label: String
        var value: String
        var tint: Color = Theme.ink
        var sub: String = ""
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

struct LedgerBackdrop: View {
    var palette: OutsidePalette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if palette == .game {
                LinearGradient(colors: [Theme.page, Theme.pageLift], startPoint: .top, endPoint: .bottom)
                if !reduceTransparency { photo }
                if !reduceTransparency {
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

    private var photo: some View {
        Color.clear
            .overlay {
                Image("HomeBackdrop")
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.12)
                    .blur(radius: 18)
            }
            .overlay { Color.black.opacity(0.26) }
            .overlay {
                LinearGradient(stops: [.init(color: Theme.page.opacity(0.8), location: 0), .init(color: Theme.page.opacity(0.35), location: 0.14),
                                       .init(color: Theme.page.opacity(0), location: 0.3),
                                       .init(color: Theme.page.opacity(0), location: 0.55), .init(color: Theme.page.opacity(0.78), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .clipped()
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

struct GlassSurface: ViewModifier {
    var radius: CGFloat
    var raised: Bool

    func body(content: Content) -> some View {
        content.modifier(LiquidGlass(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), tint: raised ? Theme.surfaceRaised : nil))
    }
}

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

struct LedgerScreen: ViewModifier {
    @Environment(\.tabBarClearance) private var tabBarClearance
    @Environment(\.outsidePalette) private var palette

    func body(content: Content) -> some View {
        content
            .environment(\.tabBarClearance, 0)
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: tabBarClearance) }
            .modifier(TopBarBackground(palette: palette))
            .toolbarColorScheme(palette.isLight ? .light : .dark, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: 0).background(TopStrip(palette: palette))
            }
    }
}

private struct TopBarBackground: ViewModifier {
    var palette: OutsidePalette
    @ViewBuilder func body(content: Content) -> some View {
        if palette == .game {
            content.toolbarBackground(.hidden, for: .navigationBar)
        } else {
            content.toolbarBackground(palette.ground, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

private struct TopStrip: View {
    var palette: OutsidePalette
    var body: some View {
        if palette == .game {
            LinearGradient(colors: [Theme.page.opacity(0.55), Theme.page.opacity(0)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top).allowsHitTesting(false)
        } else {
            palette.ground.ignoresSafeArea(edges: .top)
        }
    }
}
extension View {
    func ledgerScreen() -> some View { modifier(LedgerScreen()) }
    func ledgerBackground() -> some View { modifier(LedgerBackground()) }
}

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

struct AmountField: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var currency: Currency
    @Binding var amount: Double
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

struct SectionTabs<T: Hashable>: View {
    var items: [T]
    var primary: [T]? = nil
    var title: (T) -> String
    @Binding var selection: T
    var badge: (T) -> Int = { _ in 0 }
    var dots: ((T) -> Bool)? = nil
    var urgent: Bool = false
    var sub: Bool = false
    var itemIdentifier: ((T) -> String)? = nil
    var scrolls: Bool = false
    @Environment(\.outsidePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

struct SmallOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonStyle(fullWidth: true).makeBody(configuration: configuration)
    }
}

struct PendingAction: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var button: String
    var destructive = false
    var alwaysAsk = false
    var amount: Double? = nil
    var currency: Currency? = nil
    var risk = ""
    var tone: PopupTone? = nil
    var icon: String? = nil
    var run: () -> Void
}

enum ConfirmThreshold {
    static let sizes: [Double] = [0, 500, 2_000, 10_000, 50_000, 250_000]
    static let defaultStep = 2
    static let key = "askBelowStep"
    static var delegated: (() -> (limit: Double, rate: Double))?
    static var step: Int {
        get {
            guard UserDefaults.standard.object(forKey: key) != nil else { return defaultStep }
            return min(max(UserDefaults.standard.integer(forKey: key), 0), sizes.count - 1)
        }
        set { UserDefaults.standard.set(min(max(newValue, 0), sizes.count - 1), forKey: key) }
    }

    static func skips(_ p: PendingAction, step: Int) -> Bool {
        var size: Double? = nil
        if let currency = p.currency {
            size = limit(step: step, currency: currency)
            if let d = delegated?(), d.limit > 0, abs(d.rate - currency.rate) < 1e-9 { size = max(size ?? 0, d.limit) }
        }
        return !ConfirmRule.asks(irreversible: p.destructive || p.alwaysAsk, amount: p.amount, limit: size)
    }
    static func skips(_ p: PendingAction) -> Bool { skips(p, step: step) }

    static func limit(step: Int, currency: Currency) -> Double {
        let i = min(max(step, 0), sizes.count - 1)
        return sizes[i] == 0 ? 0 : currency.scaledPrice(sizes[i])
    }
}

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
        if go { DispatchQueue.main.async { run(p) } }
    }

    private func run(_ p: PendingAction) {
        if let s = outcomeStore { s.runConfirmed(p) } else { p.run() }
    }
}

extension View {
    func confirmAction(_ pending: Binding<PendingAction?>) -> some View {
        modifier(ConfirmActionModifier(pending: pending))
    }
}

struct SegmentedChoice<T: Hashable>: View {
    var items: [T]
    var title: (T) -> String
    @Binding var selection: T
    var badges: ((T) -> Bool)? = nil

    var body: some View {
        SegmentTrack(items: items, title: title, selection: $selection, identifier: { (_: T) -> String in "" }, badges: badges)
    }
}

struct KeyboardDismiss: ViewModifier {
    static func hide() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func body(content: Content) -> some View {
        content
            .background(Color.clear.contentShape(Rectangle()).onTapGesture { Self.hide() })
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { Self.hide() }.accessibilityIdentifier("keyboard-done")
                }
            }
    }
}

extension View {
    func keyboardDismissable() -> some View { modifier(KeyboardDismiss()) }
}
