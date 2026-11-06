import SwiftUI

// The shared pieces of the new look. Every screen is built from these, so a
// colour, radius or icon changes in one place. Values are the mockups' own; tokens live in Theme.swift.
//
//   Icons ......... LedgerIcon / Glyph      the mockups' 24x24 SVG paths, drawn as strokes (never SF Symbols for the house icons)
//   Headers ....... AppHeader, RoundBackButton, HomeHeader, .appScreen(title:subtitle:)
//   Containers .... Card (in Components.swift), StatStrip, SharpTable (TableHeader / TableRow)
//   Controls ...... ActionTile, ChoiceCard, SegmentedPill, QuietButton, SmallOutlineButton, CardRow
//   Badges ........ RedBubble, IconCircle, AppIconTile
//   Navigation .... PillTabBar (floating tab bar with highlighted pill and bubbles)
//
// House rules these encode: cards and icons are the style; the back button is round; title and "Hello, name"
// only on Home; every other screen has its own AppHeader; only Next Day is a filled button.

// MARK: Icons

/// An icon drawn from SVG path data on a 24 x 24 grid (the mockups' own icons). Supports M L H V C A Z, absolute and relative.
struct LedgerIcon: Shape {
    var svg: String

    func path(in rect: CGRect) -> Path {
        let raw: Path = SVGPathData.parse(svg)
        let side: CGFloat = min(rect.width, rect.height)
        let scale: CGFloat = side / 24
        let dx: CGFloat = rect.minX + (rect.width - side) / 2
        let dy: CGFloat = rect.minY + (rect.height - side) / 2
        let move = CGAffineTransform(translationX: dx, y: dy)
        let t: CGAffineTransform = CGAffineTransform(scaleX: scale, y: scale).concatenating(move)
        return raw.applying(t)
    }
}

/// A stroked house icon at a size. `weight` is the SVG stroke width (1.4 to 1.7 in the mockups) and scales with the size.
struct GlyphView: View {
    var glyph: String
    var size: CGFloat = 22
    var weight: CGFloat = 1.5
    var tint: Color? = nil
    @Environment(\.outsidePalette) private var palette
    @Environment(\.containerInk) private var containerInk

    var body: some View {
        let line: CGFloat = size / 24 * weight
        let style = StrokeStyle(lineWidth: line, lineCap: .butt, lineJoin: .round)
        // Same ink rules as `.textStyle`: a filled container's ink first, and game colours mapped into an outside app's palette.
        let ink: Color = containerInk ?? (tint ?? palette.accent).inPalette(palette)
        LedgerIcon(svg: glyph)
            .stroke(ink, style: style)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The house icon set: SVG path data. Add new icons here, in the same 24 x 24 style.
enum Glyph {
    // Tabs
    static let home = "M4 11 L12 4 L20 11 V20 H4 Z M10 20 V14 H14 V20"
    static let team = "M3 20 C3 15 15 15 15 20 M15 15 C19 14.5 21.5 16.5 21.5 20 M9 5 A3 3 0 1 0 9 11 A3 3 0 1 0 9 5"
    static let group = "M12 3 L21 8 L12 13 L3 8 Z M3 12 L12 17 L21 12 M3 16 L12 21 L21 16"
    static let projects = "M14 4 L20 10 L17 13 L11 7 Z M12 9 L4 18 L6 20 L15 12"
    static let phone = "M9.5 2.5 H14.5 A2.5 2.5 0 0 1 17 5 V19 A2.5 2.5 0 0 1 14.5 21.5 H9.5 A2.5 2.5 0 0 1 7 19 V5 A2.5 2.5 0 0 1 9.5 2.5 M10.5 18.5 H13.5"
    // Phone apps
    static let bank = "M3 10 L12 4 L21 10 M5 10 V18 M9 10 V18 M15 10 V18 M19 10 V18 M3 20 H21"
    static let inbox = "M3 13 L6 5 H18 L21 13 V19 H3 Z M3 13 H9 L10.5 15 H13.5 L15 13 H21"
    static let news = "M4 5 H17 V19 H6 C5 19 4 18 4 17 Z M17 8 H20 V17 C20 18 19 19 18 19 M7 9 H14 M7 12 H14 M7 15 H11"
    static let stats = "M5 20 V12 M10 20 V6 M15 20 V10 M20 20 V4"
    static let goals = "M12 3 V21 M12 4 H19 L16 8 L19 12 H12"
    static let world = "M12 3 A9 9 0 1 0 12 21 A9 9 0 1 0 12 3 M3 12 H21 M12 3 C8 8 8 16 12 21 M12 3 C16 8 16 16 12 21"
    static let luxury = "M12 4 L19 10 L12 20 L5 10 Z M5 10 H19"
    static let ventures = "M12 3 C16 6 17 11 14 16 L12 20 L10 16 C7 11 8 6 12 3 M9 17 L6 20 M15 17 L18 20"
    static let richList = "M4 18 L6 8 L10 12 L12 6 L14 12 L18 8 L20 18 Z"
    static let reports = "M6 3 H15 L19 7 V21 H6 Z M9 13 H16 M9 17 H16"
    static let achievements = "M8 4 H16 V10 C16 13 14 14 12 14 C10 14 8 13 8 10 Z M12 14 V18 M9 20 H15"
    static let settings = "M12 8 A4 4 0 1 0 12 16 A4 4 0 1 0 12 8 M12 2 V5 M12 19 V22 M2 12 H5 M19 12 H22"
    // Actions and marks
    static let hire = "M12 5 V19 M5 12 H19"
    static let market = "M4 18 L9 12 L13 15 L20 6"
    static let invest = "M4 18 L9 12 L13 15 L20 6 M15 6 H20 V11"
    static let person = "M12 4.5 A3.5 3.5 0 1 0 12 11.5 A3.5 3.5 0 1 0 12 4.5 M5 20 C5 14 19 14 19 20"
    static let warning = "M12 3 L22 20 H2 Z M12 10 V14 M12 16.5 V17"
    static let back = "M15 5 L8 12 L15 19"
    static let chevron = "M9 5 L16 12 L9 19"
    static let gym = "M4 10 H20 M7 7 V13 M17 7 V13 M2 10 H4 M20 10 H22 M9 10 V17 M15 10 V17"
    static let cafe = "M5 9 H17 V15 C17 18 15 19 12 19 H10 C7 19 5 18 5 15 Z M17 10 H19 C21 10 21 14 18 14"
}

/// Parses SVG path data into a SwiftUI `Path`. Arcs assume no axis rotation (every mockup arc is a circle).
enum SVGPathData {
    static func parse(_ d: String) -> Path {
        let toks: [String] = tokens(d)
        var path = Path()
        var i = 0
        var cmd = ""
        var cur = CGPoint.zero
        var start = CGPoint.zero

        func num() -> CGFloat {
            guard i < toks.count else { return 0 }
            let v = Double(toks[i]) ?? 0
            i += 1
            return CGFloat(v)
        }

        while i < toks.count {
            if let f = toks[i].first, f.isLetter {
                cmd = toks[i]
                i += 1
                if cmd == "Z" || cmd == "z" {
                    path.closeSubpath()
                    cur = start
                    continue
                }
            }
            switch cmd {
            case "M", "m":
                let x = num(), y = num()
                let p = cmd == "M" ? CGPoint(x: x, y: y) : CGPoint(x: cur.x + x, y: cur.y + y)
                path.move(to: p); cur = p; start = p
                cmd = cmd == "M" ? "L" : "l"
            case "L", "l":
                let x = num(), y = num()
                let p = cmd == "L" ? CGPoint(x: x, y: y) : CGPoint(x: cur.x + x, y: cur.y + y)
                path.addLine(to: p); cur = p
            case "H", "h":
                let x = num()
                let p = CGPoint(x: cmd == "H" ? x : cur.x + x, y: cur.y)
                path.addLine(to: p); cur = p
            case "V", "v":
                let y = num()
                let p = CGPoint(x: cur.x, y: cmd == "V" ? y : cur.y + y)
                path.addLine(to: p); cur = p
            case "C", "c":
                let rel = cmd == "c"
                let ox: CGFloat = rel ? cur.x : 0
                let oy: CGFloat = rel ? cur.y : 0
                let x1 = num(), y1 = num(), x2 = num(), y2 = num(), x = num(), y = num()
                let c1 = CGPoint(x: ox + x1, y: oy + y1)
                let c2 = CGPoint(x: ox + x2, y: oy + y2)
                let p = CGPoint(x: ox + x, y: oy + y)
                path.addCurve(to: p, control1: c1, control2: c2); cur = p
            case "A", "a":
                let rel = cmd == "a"
                let rx = num(), ry = num()
                _ = num()
                let large = num() != 0
                let sweep = num() != 0
                let x = num(), y = num()
                let p = CGPoint(x: rel ? cur.x + x : x, y: rel ? cur.y + y : y)
                addArc(&path, from: cur, rx: rx, ry: ry, large: large, sweep: sweep, to: p)
                cur = p
            default:
                i += 1
            }
        }
        return path
    }

    private static func tokens(_ d: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for ch in d {
            if ch.isLetter {
                if !cur.isEmpty { out.append(cur); cur = "" }
                out.append(String(ch))
            } else if ch == " " || ch == "," {
                if !cur.isEmpty { out.append(cur); cur = "" }
            } else if ch == "-" {
                if !cur.isEmpty { out.append(cur) }
                cur = "-"
            } else {
                cur.append(ch)
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// SVG endpoint arc to cubic curves (spec F.6.5 with no rotation).
    private static func addArc(_ path: inout Path, from p0: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat, large: Bool, sweep: Bool, to p1: CGPoint) {
        if p0 == p1 { return }
        var rx: Double = Double(abs(rx0)), ry: Double = Double(abs(ry0))
        if rx == 0 || ry == 0 { path.addLine(to: p1); return }
        let x0 = Double(p0.x), y0 = Double(p0.y), x1 = Double(p1.x), y1 = Double(p1.y)
        let dx2: Double = (x0 - x1) / 2
        let dy2: Double = (y0 - y1) / 2
        let lambda: Double = (dx2 * dx2) / (rx * rx) + (dy2 * dy2) / (ry * ry)
        if lambda > 1 { let s = lambda.squareRoot(); rx *= s; ry *= s }
        let rx2: Double = rx * rx, ry2: Double = ry * ry
        let num: Double = rx2 * ry2 - rx2 * dy2 * dy2 - ry2 * dx2 * dx2
        let den: Double = rx2 * dy2 * dy2 + ry2 * dx2 * dx2
        let sign: Double = large == sweep ? -1 : 1
        let coef: Double = den == 0 ? 0 : sign * max(0, num / den).squareRoot()
        let cxp: Double = coef * rx * dy2 / ry
        let cyp: Double = -coef * ry * dx2 / rx
        let cx: Double = cxp + (x0 + x1) / 2
        let cy: Double = cyp + (y0 + y1) / 2
        let theta1: Double = atan2((dy2 - cyp) / ry, (dx2 - cxp) / rx)
        let theta2: Double = atan2((-dy2 - cyp) / ry, (-dx2 - cxp) / rx)
        var delta: Double = theta2 - theta1
        if !sweep && delta > 0 { delta -= 2 * Double.pi }
        if sweep && delta < 0 { delta += 2 * Double.pi }
        let n: Int = max(1, Int((abs(delta) / (Double.pi / 2)).rounded(.up)))
        let step: Double = delta / Double(n)
        let k: Double = 4.0 / 3.0 * tan(step / 4)
        for j in 0..<n {
            let a1: Double = theta1 + Double(j) * step
            let a2: Double = a1 + step
            let c1 = CGPoint(x: cx + rx * (cos(a1) - k * sin(a1)), y: cy + ry * (sin(a1) + k * cos(a1)))
            let c2 = CGPoint(x: cx + rx * (cos(a2) + k * sin(a2)), y: cy + ry * (sin(a2) - k * cos(a2)))
            let end = CGPoint(x: cx + rx * cos(a2), y: cy + ry * sin(a2))
            path.addCurve(to: end, control1: c1, control2: c2)
        }
    }
}

// MARK: Badges and icon holders

/// The red notification bubble: a count on an app icon or a tab. Draws nothing for zero. Large (20 pt) on app icons, small (16 pt) on tabs.
struct RedBubble: View {
    enum Size { case regular, small }
    var count: Int
    var size: Size = .regular
    @State private var bounced = false

    var body: some View {
        if count > 0 {
            let big = size == .regular
            let h: CGFloat = big ? 20 : 16
            let text: String = count > 9 ? "9+" : "\(count)"
            Text(text)
                .font(.system(size: big ? 11.5 : 10, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 5)
                .frame(minWidth: h, minHeight: h)
                .background(Capsule().fill(Theme.alert))
                .overlay(Capsule().strokeBorder(Theme.page, lineWidth: big ? 2 : 0))
                .accessibilityLabel("\(count) waiting")
                .scaleEffect(bounced ? 1.1 : 1)
                .onChange(of: count) { old, new in
                    guard new > old else { return }
                    Motion.animate(Motion.quickAnimation) { bounced = true }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(Motion.quickSeconds * 1_000_000_000))
                        Motion.animate(Motion.quickAnimation) { bounced = false }
                    }
                }
        }
    }
}

/// The icon holder of rows and options: an unoutlined glyph at one of the three icon sizes, centred in a `size` square so layouts
/// keep their measure. Champagne by default.
struct IconCircle: View {
    var glyph: String
    var size: CGFloat = 40
    var tint: Color? = nil
    @Environment(\.outsidePalette) private var palette

    var body: some View {
        LedgerGlyph(glyph: glyph, size: IconCircle.glyphSize(size), tint: tint ?? palette.accent)
            .frame(width: size, height: size)
    }

    /// The icon size for a holder: small under 36 pt, large over 48 pt, medium between.
    static func glyphSize(_ holder: CGFloat) -> CGFloat {
        if holder < 36 { return Theme.Icon.small }
        if holder > 48 { return Theme.Icon.large }
        return Theme.Icon.medium
    }
}

/// The app icon of the Phone grid: a 62 pt rounded square with a soft vertical gradient and a border.
struct AppIconTile: View {
    var glyph: String
    var size: CGFloat = 62
    /// A muted colour for inside the icon (Phone apps). Nil keeps the plain champagne icon.
    var tint: Color? = nil

    /// The icon mood board (1 Nov 2026): a flat dark squircle with a thin outline, and a flat, desaturated outline glyph in the app's own tint.
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.appIcon * size / 62, style: .continuous)
        GlyphView(glyph: glyph, size: size * 0.45, weight: 1.5, tint: tint ?? Theme.gold)
            .frame(width: size, height: size)
            .background(shape.fill(Color(hex: 0x17181A)))
            .background(shape.fill((tint ?? Color.clear).opacity(0.07)))
            .overlay(shape.strokeBorder(Color(hex: 0x303134), lineWidth: 1))
    }
}

// MARK: Headers

/// The back button: a chevron on a small round inset fill (36 pt drawn, 44 pt target). Every screen outside Home has one. It pops the current screen.
struct RoundBackButton: View {
    var label = "Back"
    var action: () -> Void
    @Environment(\.outsidePalette) private var palette

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            LedgerGlyph(glyph: Glyph.back, size: Theme.Icon.small + 2, tint: palette.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(palette.ink.opacity(palette.isLight ? 0.07 : 0.09)))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier("back-button")
    }
}

/// A screen header. With `onBack` (a pushed screen) it is the calm inline bar: round back at the left, the serif title and its grey
/// subtitle centred, the trailing control at the right. Without it (a tab root) it is the large serif title at the left with the
/// subtitle under it and the trailing control beside it. Use it as the first element of a screen, or through `.appScreen(title:subtitle:)`.
struct AppHeader<Trailing: View>: View {
    var title: String
    var subtitle: String = ""
    var onBack: (() -> Void)? = nil
    var backLabel = "Back"
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.outsidePalette) private var palette

    var body: some View {
        if let onBack { inline(onBack) } else { large }
    }

    /// Pushed screen: the sides share the width equally so the title stays centred whatever the trailing control is.
    private func inline(_ onBack: @escaping () -> Void) -> some View {
        HStack(spacing: Theme.Space.xs) {
            RoundBackButton(label: backLabel, action: onBack)
                .padding(.leading, -Theme.Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 1) {
                Text(title).textStyle(.figure, weight: .semibold).lineLimit(1).minimumScaleFactor(0.75)
                if !subtitle.isEmpty {
                    Text(subtitle.tidyText).textStyle(.caption, tint: palette.inkFaint).lineLimit(1)
                }
            }
            .multilineTextAlignment(.center)
            .layoutPriority(1)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            // The clear spacer keeps this side in the layout when there is no trailing control.
            ZStack(alignment: .trailing) {
                Color.clear.frame(width: 1, height: 1)
                trailing()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: 44)
    }

    /// Tab root: the large title, left-aligned.
    private var large: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title).textStyle(.title, weight: .semibold).lineLimit(1).minimumScaleFactor(0.7)
                if !subtitle.isEmpty {
                    Text(subtitle.tidyText).textStyle(.caption, tint: palette.inkFaint).lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension AppHeader where Trailing == EmptyView {
    init(title: String, subtitle: String = "", onBack: (() -> Void)? = nil, backLabel: String = "Back") {
        self.init(title: title, subtitle: subtitle, onBack: onBack, backLabel: backLabel, trailing: { EmptyView() })
    }
}

/// The Home header, the only one with the app name and "Hello, name": title and greeting at the left, date and New company at the right.
struct HomeHeader: View {
    var name: String
    var dateText: String
    /// Consecutive days played; the flame and number show only from 3 up (the store passes 0 below that).
    var streak: Int = 0
    var onNewCompany: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(dateText).textStyle(.label, tint: Theme.inkFaint)
                Text("Hello, \(name)").textStyle(.title).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: Theme.Space.s)
            Button("New company", action: onNewCompany)
                .buttonStyle(SecondaryButtonStyle(size: .compact))
        }
    }
}

/// Gives a pushed screen the new header: hides the system navigation bar (and its back button), pins an `AppHeader` with the round
/// back button above the content. Back from the first screen a link from another tab pushed returns to that tab (see `GameStore.setPath`).
/// `trailing` is for a screen's own menu (the Inbox options). Apply it to the content of a `navigationDestination`, not to a tab root.
struct AppScreen<Trailing: View>: ViewModifier {
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    @Environment(\.outsidePalette) private var palette
    @Environment(\.hidesRootBack) private var hidesRootBack
    var title: String
    var subtitle: String
    var tab: AppTab
    var showsBack: Bool
    @ViewBuilder var trailing: () -> Trailing

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .swipeBackEnabled()
            .toolbar(.hidden, for: .navigationBar)
            .ledgerBackground()
            .safeAreaInset(edge: .top, spacing: 0) {
                // On the ivory Bank the header is the forest-green band with ivory text; everywhere else it is the page colour.
                let ground: Color = palette == OutsidePalette.bank ? FinanceColor.forest : palette.ground
                AppHeader(title: title, subtitle: subtitle, onBack: (showsBack && !hidesRootBack) ? { dismiss() } : nil, trailing: trailing)
                    .environment(\.outsidePalette, palette == OutsidePalette.bank ? OutsidePalette.forest : palette)
                    .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.xxs).padding(.bottom, Theme.Space.s)
                    .background(ground.ignoresSafeArea(edges: .top))
                    // Content scrolling up fades under the header instead of meeting a hard edge.
                    .background(alignment: .bottom) {
                        LinearGradient(colors: [ground, ground.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: palette == OutsidePalette.bank ? 0 : Theme.Space.m).offset(y: Theme.Space.m).allowsHitTesting(false)
                    }
            }
    }
}

/// "Back to <tab>" at the root of a tab that a link from another tab landed on. It shows only while nothing is pushed on that tab: a
/// pushed screen has its round back button, which returns to the origin by itself, so a screen never has two Back controls.
struct ReturnLine: View {
    @EnvironmentObject var store: GameStore
    var tab: AppTab

    var body: some View {
        if store.tab == tab, let r = store.returnInfo, r.dest == tab, store.depth(tab) == 0 {
            Button {
                Haptics.tap()
                store.returnToOrigin()
            } label: {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: "chevron.left").textStyle(.caption, tint: Theme.accent, weight: .semibold)
                    Text("Back to \(store.title(for: r.from))").textStyle(.body, tint: Theme.accent, weight: .medium)
                    Spacer()
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, Theme.Space.page).padding(.vertical, Theme.Space.s)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("return-bar")
        }
    }
}

extension View {
    /// The new-look screen header (round back, serif title, grey subtitle) for a pushed screen. See `AppScreen`.
    func appScreen(title: String, subtitle: String = "", tab: AppTab = .phone, showsBack: Bool = true) -> some View {
        modifier(AppScreen(title: title, subtitle: subtitle, tab: tab, showsBack: showsBack, trailing: { EmptyView() }))
    }
    /// The same with a trailing control (a menu) in the header.
    func appScreen<T: View>(title: String, subtitle: String = "", tab: AppTab = .phone, showsBack: Bool = true, @ViewBuilder trailing: @escaping () -> T) -> some View {
        modifier(AppScreen(title: title, subtitle: subtitle, tab: tab, showsBack: showsBack, trailing: trailing))
    }
}

// MARK: Containers

/// Cells separated by hairlines, like the Private / Companies / Owed strip of the Home net-worth card: `FigureRow`, centred.
struct StatStrip: View {
    struct Cell: Identifiable {
        var id: String { label }
        var label: String
        var value: String
        var tint: Color = Theme.ink
        /// The number behind `value`: the figure rolls and flashes as it changes.
        var live: Double? = nil
        /// Kept so older call sites compile; the profit glow is retired.
        var glow: Bool = false
    }
    var cells: [Cell]
    /// A hairline above the strip, for use as the footer of a card.
    var ruled = true

    var body: some View {
        let items: [KeyFigures.Item] = cells.map { (c: Cell) -> KeyFigures.Item in
            KeyFigures.Item(label: c.label, value: c.value, tint: c.tint, live: c.live)
        }
        VStack(spacing: 0) {
            if ruled { Hairline().padding(.bottom, Theme.Space.s) }
            FigureRow(items: items, columns: max(1, items.count), alignment: .center, combineCells: true)
        }
    }
}

/// A row on its own surface tile (flat inside a group): `LedgerRow` with a glyph or picture, a value, a chevron and an optional red count.
struct CardRow: View {
    @Environment(\.insideCard) private var insideCard
    var glyph: String
    var title: String
    var subtitle: String = ""
    var value: String = ""
    var valueTint: Color = Theme.ink
    var badge: Int = 0
    var chevron = true
    /// A picture slot in place of the icon (company rows and the like).
    var thumb: ThumbSpec? = nil

    var body: some View {
        let lead: LedgerRow.Leading = thumb.map { LedgerRow.Leading.thumb($0) } ?? LedgerRow.Leading.glyph(glyph)
        Card(padding: 0) {
            LedgerRow(leading: lead, title: title, subtitle: subtitle, value: value, valueTint: valueTint, badge: badge,
                      chevron: chevron, inset: insideCard ? 0 : 14)
        }
    }
}

/// One of the quick-action tiles of Home (Bank, Hire, Reports, Market): icon over a label in a small card. Put four in a row.
struct ActionTile: View {
    @Environment(\.outsidePalette) private var P
    var glyph: String
    var title: String
    var badge: Int = 0
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: Theme.Space.xs) {
                LedgerGlyph(glyph: glyph, size: Theme.Icon.medium, tint: P.accent)
                Text(title).textStyle(.caption, tint: P.ink).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Space.s)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(P.card))
            .overlay(alignment: .topTrailing) { RedBubble(count: badge, size: .small).offset(x: 4, y: -5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }
}

/// A selectable option as a card with a radio mark: the chosen one is outlined in champagne. For exclusive choices that need a sentence
/// (hiring options, loan terms, the way to pay); for short labels use `SegmentedPill`.
struct ChoiceCard: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var subtitle: String = ""
    var trailing: String = ""
    var selected: Bool
    /// An optional picture slot after the radio (premises options); nil keeps the plain card.
    var thumb: ThumbSpec? = nil
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.choose()
            action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().strokeBorder(selected ? P.accent : P.lineStrong, lineWidth: 1.5).frame(width: 20, height: 20)
                    if selected { Circle().fill(P.accent).frame(width: 10, height: 10) }
                }
                if let thumb { ThumbnailView(thumb, size: 36) }
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title.tidyText).textStyle(.headline).multilineTextAlignment(.leading)
                    if !subtitle.isEmpty { Text(subtitle.tidyText).textStyle(.caption).multilineTextAlignment(.leading) }
                }
                Spacer(minLength: Theme.Space.s)
                if !trailing.isEmpty { Text(trailing.tidyText).textStyle(.headline, numeric: true) }
            }
            .padding(.horizontal, 14).padding(.vertical, Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(selected ? P.accentWash : P.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The switch between a few short options (Rent / Buy / Home): the one segment look (`SegmentTrack`).
struct SegmentedPill<T: Hashable>: View {
    var items: [T]
    var title: (T) -> String
    @Binding var selection: T
    /// Accessibility identifier of each segment (default `segment-<title>`).
    var identifier: ((T) -> String)? = nil
    /// Segments that hold something new or important get a small marker in the app's colour (nil = none).
    var badges: ((T) -> Bool)? = nil

    var body: some View {
        let title: (T) -> String = self.title
        let ids: (T) -> String = identifier ?? { (item: T) -> String in "segment-\(title(item))" }
        SegmentTrack(items: items, title: title, selection: $selection, identifier: ids, badges: badges)
    }
}

// MARK: Sharp table

/// One column of a `SharpTable`. `width` nil = takes the rest of the row (the first, name column).
struct TableColumn: Identifiable {
    var id: String { title }
    var title: String
    var width: CGFloat? = nil
}

/// The sharp trade table: a bordered 8 pt box holding a `TableHeader` and `TableRow`s (the trade picker; any comparison list).
struct SharpTable<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    @Environment(\.insideCard) private var insideCard
    @ViewBuilder var content: () -> Content

    /// On its own the table sits on a surface tile; inside a group it is flat. No outline either way.
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        VStack(spacing: 0, content: content)
            .environment(\.insideCard, true)
            .background(insideCard ? Color.clear : P.card)
            .clipShape(shape)
    }
}

/// The caps header line of a table. The first column is the flexible name column; the others are right-aligned.
struct TableHeader: View {
    @Environment(\.outsidePalette) private var P
    var columns: [TableColumn]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(columns.enumerated()), id: \.element.id) { i, c in
                let fixed: CGFloat? = c.width
                let grow: CGFloat? = fixed == nil ? CGFloat.infinity : nil
                let align: Alignment = i == 0 ? .leading : .trailing
                Text(c.title)
                    .textStyle(.label, tint: P.inkFaint)
                    .lineLimit(1)
                    .frame(width: fixed, alignment: align)
                    .frame(maxWidth: grow, alignment: align)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, Theme.Space.s)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// A table row: a name with a grey note under it, then one value per remaining column. A selected row is washed in champagne.
/// Money in `values` must already come through the store formatter.
struct TableRow: View {
    @Environment(\.outsidePalette) private var P
    var columns: [TableColumn]
    var title: String
    var note: String = ""
    var values: [String]
    var valueTints: [Color] = []
    var selected = false
    /// A picture slot before the name (a rival's logo and the like); nil keeps the plain row.
    var thumb: ThumbSpec? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        let row = HStack(spacing: 6) {
            if let thumb { ThumbnailView(thumb, size: 30).padding(.trailing, 4) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title.tidyText).textStyle(.body, weight: .medium).lineLimit(2)
                if !note.isEmpty { Text(note.tidyText).textStyle(.caption, tint: P.inkFaint).lineLimit(2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                let colIndex: Int = i + 1
                let w: CGFloat? = colIndex < columns.count ? columns[colIndex].width : nil
                let tint: Color = (i < valueTints.count ? valueTints[i] : (i == 0 ? P.ink : P.inkSoft)).inPalette(P)
                Text(v.tidyText).textStyle(.body, tint: tint, numeric: true)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: w, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(selected ? P.accentWash : Color.clear)
        .overlay(alignment: .bottom) { Hairline() }
        .contentShape(Rectangle())
        if let action {
            Button { Haptics.tap(); action() } label: { row }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            row
        }
    }
}

// MARK: Buttons

/// The secondary button as a view (Continue, Register ...); `tint` colours the text.
struct QuietButton: View {
    var title: String
    var tint: Color? = nil
    var fullWidth = false
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
        }
        .buttonStyle(SecondaryButtonStyle(fullWidth: fullWidth, tint: tint))
    }
}

/// The compact secondary button next to a title (New company): accent text, 44 pt hit area.
struct SmallOutlineButton: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
        }
        .buttonStyle(SecondaryButtonStyle(size: .compact, tint: P.accent))
        .accessibilityLabel(title)
    }
}

// MARK: Floating pill tab bar

/// One destination of the floating tab bar.
struct PillTabItem: Identifiable, Equatable {
    var id: String
    var title: String
    var glyph: String
    var badge: Int = 0
    /// True for the tab the player can re-point with a long press (the Custom tab).
    var changeable: Bool = false
}

/// The floating tab bar: a glass capsule over the page, the selected tab in champagne on a soft lens that slides between tabs.
/// Overlay it at the bottom of the shell and set `tabBarClearance` so every `ledgerBackground()` screen keeps its content clear of it. Each item is a button with the identifier `tab-<title>`.
struct PillTabBar: View {
    var items: [PillTabItem]
    @Binding var selection: String
    /// Called with the item's id when the tab that is already selected is tapped again (the tab goes back to its root).
    var onReselect: (String) -> Void = { _ in }
    /// Called with the item's id when a `changeable` item is long-pressed.
    var onLongPress: (String) -> Void = { _ in }
    @State private var longPressed: String?
    @Namespace private var lens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bar height plus its bottom padding; screens keep this much (plus a margin) clear at the bottom.
    static let height: CGFloat = 66 + 8

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { (item: PillTabItem) in
                tab(item)
            }
        }
        .padding(.horizontal, 5)
        .frame(height: PillTabBar.height - 8)
        .liquidGlassCapsule()
        .padding(.horizontal, Theme.Space.m).padding(.bottom, Theme.Space.s)
        .animation(Motion.move(reduceMotion), value: selection)
    }

    private func tab(_ item: PillTabItem) -> some View {
        let on: Bool = item.id == selection
        let ink: Color = on ? Theme.accent : Theme.inkSoft
        let traits: AccessibilityTraits = on ? [.isButton, .isSelected] : [.isButton]
        return Button {
            if longPressed == item.id { longPressed = nil; return }
            if on { onReselect(item.id) } else { selection = item.id }
        } label: {
            VStack(spacing: 3) {
                LedgerGlyph(glyph: item.glyph, size: 22, tint: ink)
                    .overlay(alignment: .topTrailing) { RedBubble(count: item.badge, size: .small).offset(x: 11, y: -7) }
                Text(item.title).font(.system(size: 10.5, weight: on ? .semibold : .medium)).foregroundStyle(ink)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .id(item.glyph + item.title)
            .transition(.opacity)
            .animation(Motion.quickAnimation, value: item.title)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if on {
                    Capsule().fill(Theme.ink.opacity(0.09))
                        .matchedGeometryEffect(id: "lens", in: lens)
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            longPressed = item.id
            Haptics.tap()
            onLongPress(item.id)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                longPressed = nil
            }
        }, including: item.changeable ? .all : .subviews)
        .accessibilityLabel(item.title)
        .accessibilityActions { if item.changeable { Button("Change destination") { onLongPress(item.id) } } }
        .accessibilityValue(item.badge > 0 ? "\(item.badge) waiting" : "")
        .accessibilityIdentifier("tab-\(item.title)")
        .accessibilityAddTraits(traits)
    }
}
