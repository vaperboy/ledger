import SwiftUI

// The shared pieces of the new look (approved 27 Oct 2026, native/design/new-look-2026-10). Every screen is built from these, so a
// colour, radius or icon changes in one place. Values are the mockups' own; tokens live in Theme.swift.
//
//   Icons ......... LedgerIcon / Glyph      the mockups' 24x24 SVG paths, drawn as strokes (never SF Symbols for the house icons)
//   Headers ....... AppHeader, RoundBackButton, HomeHeader, .appScreen(title:subtitle:)
//   Containers .... Card (in Components.swift), StatStrip, SharpTable (TableHeader / TableRow)
//   Controls ...... ActionTile, ChoiceCard, SegmentedPill, QuietButton, SmallOutlineButton, CardRow
//   Badges ........ RedBubble, IconCircle, AppIconTile
//   Navigation .... PillTabBar (floating tab bar with highlighted pill and bubbles)
//
// House rules these encode (docs/DESIGN_RULES.md): cards and icons are the style; the back button is round; title and "Hello, name"
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
    var tint: Color = Theme.gold

    var body: some View {
        let line: CGFloat = size / 24 * weight
        let style = StrokeStyle(lineWidth: line, lineCap: .butt, lineJoin: .round)
        LedgerIcon(svg: glyph)
            .stroke(tint, style: style)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The house icon set: the SVG path data copied from the approved mockups. Add new icons here, in the same 24 x 24 style.
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

    var body: some View {
        if count > 0 {
            let big = size == .regular
            let h: CGFloat = big ? 20 : 16
            let text: String = count > 99 ? "99+" : "\(count)"
            Text(text)
                .font(.system(size: big ? 11.5 : 10, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 5)
                .frame(minWidth: h, minHeight: h)
                .background(Capsule().fill(Theme.alert))
                .overlay(Capsule().strokeBorder(Theme.page, lineWidth: big ? 2 : 0))
                .accessibilityLabel("\(count) waiting")
        }
    }
}

/// A round outlined icon holder (accounts, rows, hire options). 40 pt by default, the glyph in champagne.
struct IconCircle: View {
    var glyph: String
    var size: CGFloat = 40
    var tint: Color = Theme.gold

    var body: some View {
        GlyphView(glyph: glyph, size: size * 0.5, weight: 1.5, tint: tint)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Theme.borderStrong, lineWidth: 1))
    }
}

/// The app icon of the Phone grid: a 62 pt rounded square with a soft vertical gradient and a border.
struct AppIconTile: View {
    var glyph: String
    var size: CGFloat = 62

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.appIcon, style: .continuous)
        let top = Color(hex: 0x232427)
        let bottom = Color(hex: 0x181A1C)
        GlyphView(glyph: glyph, size: size * 0.45, weight: 1.4)
            .frame(width: size, height: size)
            .background(shape.fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(Color(hex: 0x333437), lineWidth: 1))
    }
}

// MARK: Headers

/// The round bordered back button (40 pt). Every screen outside Home has one. It pops the current screen.
struct RoundBackButton: View {
    var label = "Back"
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            GlyphView(glyph: Glyph.back, size: 16, weight: 2, tint: Theme.ivory)
                .frame(width: 40, height: 40)
                .overlay(Circle().strokeBorder(Theme.borderStrong, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("back-button")
    }
}

/// A screen header: optional round back button, serif title (26 pt) and a grey subtitle (12.5 pt), with room for a trailing control.
/// Use it as the first element of every screen except Home, or through `.appScreen(title:subtitle:)`.
struct AppHeader<Trailing: View>: View {
    var title: String
    var subtitle: String = ""
    var onBack: (() -> Void)? = nil
    var backLabel = "Back"
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let onBack { RoundBackButton(label: backLabel, action: onBack) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.serifTitle(26)).foregroundStyle(Theme.ivory).lineLimit(1).minimumScaleFactor(0.7)
                if !subtitle.isEmpty {
                    Text(subtitle.tidyText).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).lineLimit(2)
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
    var onNewCompany: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ledger").font(.serifTitle(14)).foregroundStyle(Theme.gold)
                Text("Hello, \(name)").font(.serifTitle(25)).foregroundStyle(Theme.ivory).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(dateText).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                SmallOutlineButton(title: "New company", action: onNewCompany)
            }
        }
    }
}

/// Gives a pushed screen the new header: hides the system navigation bar (and its back button), pins an `AppHeader` with the round
/// back button above the content, and shows "Back to <tab>" when the player was sent here by a link from another tab.
/// `trailing` is for a screen's own menu (the Inbox options). Apply it to the content of a `navigationDestination`, not to a tab root.
struct AppScreen<Trailing: View>: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var subtitle: String
    var tab: AppTab
    var showsBack: Bool
    @ViewBuilder var trailing: () -> Trailing

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .ledgerBackground()
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    ReturnLine(tab: tab)
                    AppHeader(title: title, subtitle: subtitle, onBack: showsBack ? { dismiss() } : nil, trailing: trailing)
                        .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 10)
                }
                .background(Theme.page)
            }
    }
}

/// "Back to <tab>" for a screen reached by a link from another tab (the same bar the tab roots show).
struct ReturnLine: View {
    @EnvironmentObject var store: GameStore
    var tab: AppTab

    var body: some View {
        if store.tab == tab, let back = store.returnTab {
            Button {
                Haptics.tap()
                store.returnToOrigin()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                    Text("Back to \(back.title)").font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(Theme.gold)
                .padding(.horizontal, 18).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
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

/// Cells separated by hairline dividers, like the Private / Companies / Owed strip of the Home net-worth card.
struct StatStrip: View {
    struct Cell: Identifiable {
        var id: String { label }
        var label: String
        var value: String
        var tint: Color = Theme.ivory
    }
    var cells: [Cell]
    /// A hairline above the strip, for use as the footer of a card.
    var ruled = true

    var body: some View {
        VStack(spacing: 0) {
            if ruled { Rectangle().fill(Theme.divider).frame(height: 1).padding(.bottom, 7) }
            HStack(spacing: 0) {
                ForEach(Array(cells.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { Rectangle().fill(Theme.divider).frame(width: 1) }
                    VStack(spacing: 2) {
                        Text(c.label).font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
                        Text(c.value).font(.system(size: 13.5, weight: .medium).monospacedDigit()).foregroundStyle(c.tint)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A tappable row card: round icon, title and a grey line, a figure, a chevron, and an optional red bubble (the Bank account rows).
struct CardRow: View {
    var glyph: String
    var title: String
    var subtitle: String = ""
    var value: String = ""
    var valueTint: Color = Theme.ivory
    var badge: Int = 0
    var chevron = true

    var body: some View {
        HStack(spacing: 12) {
            IconCircle(glyph: glyph)
            VStack(alignment: .leading, spacing: 1) {
                Text(title.tidyText).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(2)
                if !subtitle.isEmpty { Text(subtitle.tidyText).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).lineLimit(2) }
            }
            Spacer(minLength: 8)
            RedBubble(count: badge)
            if !value.isEmpty { Text(value.tidyText).font(.system(size: 15, weight: .medium).monospacedDigit()).foregroundStyle(valueTint) }
            if chevron { GlyphView(glyph: Glyph.chevron, size: 13, weight: 2, tint: Theme.ivoryDim) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One of the quick-action tiles of Home (Bank, Hire, Reports, Market): icon over a label in a small card. Put four in a row.
struct ActionTile: View {
    var glyph: String
    var title: String
    var badge: Int = 0
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 4) {
                GlyphView(glyph: glyph, size: 17, weight: 1.7)
                Text(title).font(.system(size: 11)).foregroundStyle(Theme.ivory).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .overlay(alignment: .topTrailing) { RedBubble(count: badge, size: .small).offset(x: 4, y: -5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// A selectable option as a card with a radio mark: the chosen one is outlined in champagne. For exclusive choices that need a sentence
/// (hiring options, loan terms, the way to pay); for short labels use `SegmentedPill`.
struct ChoiceCard: View {
    var title: String
    var subtitle: String = ""
    var trailing: String = ""
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.choose()
            action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().strokeBorder(selected ? Theme.gold : Theme.borderStrong, lineWidth: 1.5).frame(width: 20, height: 20)
                    if selected { Circle().fill(Theme.gold).frame(width: 10, height: 10) }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title.tidyText).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory).multilineTextAlignment(.leading)
                    if !subtitle.isEmpty { Text(subtitle.tidyText).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).multilineTextAlignment(.leading) }
                }
                Spacer(minLength: 8)
                if !trailing.isEmpty { Text(trailing.tidyText).font(.system(size: 13.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivory) }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(selected ? Theme.goldSelected : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(selected ? Theme.gold : Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The switch between a few short options (Rent / Buy / Home): a sharp bordered track, the chosen segment washed and outlined in champagne.
struct SegmentedPill<T: Hashable>: View {
    var items: [T]
    var title: (T) -> String
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                let on = selection == item
                Button {
                    selection = item
                    Haptics.choose()
                } label: {
                    Text(title(item))
                        .font(.system(size: 12.5, weight: on ? .medium : .regular))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(on ? Theme.ivory : Theme.ivoryMuted)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Theme.goldSelected : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(on ? Theme.gold : Color.clear, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).fill(Theme.surfaceTable))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
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
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0, content: content)
            .background(Theme.surfaceTable)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// The caps header line of a table. The first column is the flexible name column; the others are right-aligned.
struct TableHeader: View {
    var columns: [TableColumn]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(columns.enumerated()), id: \.element.id) { i, c in
                let fixed: CGFloat? = c.width
                let grow: CGFloat? = fixed == nil ? CGFloat.infinity : nil
                let align: Alignment = i == 0 ? .leading : .trailing
                Text(c.title)
                    .font(.system(size: 10, weight: .regular)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(Theme.ivoryFaint)
                    .lineLimit(1)
                    .frame(width: fixed, alignment: align)
                    .frame(maxWidth: grow, alignment: align)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

/// A table row: a name with a grey note under it, then one value per remaining column. A selected row is washed in champagne.
/// Money in `values` must already come through the store formatter.
struct TableRow: View {
    var columns: [TableColumn]
    var title: String
    var note: String = ""
    var values: [String]
    var valueTints: [Color] = []
    var selected = false
    var action: (() -> Void)? = nil

    var body: some View {
        let row = HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title.tidyText).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(2)
                if !note.isEmpty { Text(note.tidyText).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                let colIndex: Int = i + 1
                let w: CGFloat? = colIndex < columns.count ? columns[colIndex].width : nil
                let tint: Color = i < valueTints.count ? valueTints[i] : (i == 0 ? Theme.ivory : Theme.ivoryMuted)
                Text(v.tidyText).font(.system(size: 13).monospacedDigit()).foregroundStyle(tint)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: w, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(selected ? Theme.goldSelected : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.tableLine).frame(height: 1) }
        .contentShape(Rectangle())
        if let action {
            Button { Haptics.tap(); action() } label: { row }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            row
        }
    }
}

// MARK: Buttons

/// The outlined secondary button (Continue, Register ...): champagne outline, 8 pt corners, ivory text. Never filled: only Next Day is.
struct QuietButton: View {
    var title: String
    var tint: Color = Theme.gold
    var fullWidth = false
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ivory)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 28)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(tint, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The small outlined button next to a title (New company): 12 pt text, 12 pt corners, a grey outline.
struct SmallOutlineButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.gold)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: 1))
                .frame(minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
}

/// The floating tab bar: a 66 pt bordered capsule over the page, the selected tab washed in a champagne pill, red bubbles for counts.
/// Overlay it at the bottom of the shell and set `tabBarClearance` so every `ledgerBackground()` screen keeps its content clear of it. Each item is a button with the identifier `tab-<title>`.
struct PillTabBar: View {
    var items: [PillTabItem]
    @Binding var selection: String
    /// Bar height plus its bottom padding; screens keep this much (plus a margin) clear at the bottom.
    static let height: CGFloat = 66 + 8

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let on = item.id == selection
                let traits: AccessibilityTraits = on ? [.isButton, .isSelected] : [.isButton]
                Button {
                    if !on { selection = item.id }
                } label: {
                    VStack(spacing: 3) {
                        GlyphView(glyph: item.glyph, size: 22, weight: 1.5, tint: on ? Theme.gold : Theme.ivoryMuted)
                        Text(item.title).font(.system(size: 10.5)).foregroundStyle(on ? Theme.gold : Theme.ivoryMuted).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(on ? Theme.goldWash : Color.clear))
                    .overlay(alignment: .topTrailing) { RedBubble(count: item.badge, size: .small).padding(.trailing, 14).offset(y: -4) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityValue(item.badge > 0 ? "\(item.badge) waiting" : "")
                .accessibilityIdentifier("tab-\(item.title)")
                .accessibilityAddTraits(traits)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: PillTabBar.height - 8)
        .background(Capsule().fill(Theme.surfaceTable))
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.35), radius: 10, y: 4)
        .padding(.horizontal, 14).padding(.bottom, 8)
    }
}
