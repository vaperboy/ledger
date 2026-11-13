import SwiftUI
import Simulation
import GameCore

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
        let ink: Color = containerInk ?? (tint ?? palette.accent).inPalette(palette)
        LedgerIcon(svg: glyph)
            .stroke(ink, style: style)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

enum Glyph {
    static let edit = "M15 5 L19 9 L8 20 L4 20 L4 16 Z M13 7 L17 11"
    static let home = "M4 11 L12 4 L20 11 V20 H4 Z M10 20 V14 H14 V20"
    static let team = "M3 20 C3 15 15 15 15 20 M15 15 C19 14.5 21.5 16.5 21.5 20 M9 5 A3 3 0 1 0 9 11 A3 3 0 1 0 9 5"
    static let group = "M12 3 L21 8 L12 13 L3 8 Z M3 12 L12 17 L21 12 M3 16 L12 21 L21 16"
    static let projects = "M14 4 L20 10 L17 13 L11 7 Z M12 9 L4 18 L6 20 L15 12"
    static let phone = "M9.5 2.5 H14.5 A2.5 2.5 0 0 1 17 5 V19 A2.5 2.5 0 0 1 14.5 21.5 H9.5 A2.5 2.5 0 0 1 7 19 V5 A2.5 2.5 0 0 1 9.5 2.5 M10.5 18.5 H13.5"
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
        let n: Int = min(8, max(1, Int(saturating: (abs(delta) / (Double.pi / 2)).rounded(.up))))
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

struct IconCircle: View {
    var glyph: String
    var size: CGFloat = 40
    var tint: Color? = nil
    @Environment(\.outsidePalette) private var palette

    var body: some View {
        LedgerGlyph(glyph: glyph, size: IconCircle.glyphSize(size), tint: tint ?? palette.accent)
            .frame(width: size, height: size)
    }

    static func glyphSize(_ holder: CGFloat) -> CGFloat {
        if holder < 36 { return Theme.Icon.small }
        if holder > 48 { return Theme.Icon.large }
        return Theme.Icon.medium
    }
}

struct AppIconTile: View {
    var glyph: String
    var size: CGFloat = 62
    var tint: Color? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.appIcon * size / 62, style: .continuous)
        GlyphView(glyph: glyph, size: size * 0.45, weight: 1.5, tint: tint ?? Theme.gold)
            .frame(width: size, height: size)
            .background(shape.fill(Color(hex: 0x17181A)))
            .background(shape.fill((tint ?? Color.clear).opacity(0.07)))
            .overlay(shape.strokeBorder(Color(hex: 0x303134), lineWidth: 1))
    }
}

struct RoundBackButton: View {
    var label = "Back"
    var action: () -> Void
    @Environment(\.outsidePalette) private var palette

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            LedgerGlyph(glyph: Glyph.back, size: Theme.Icon.medium, tint: palette.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier("back-button")
    }
}

struct AppHeader<Trailing: View>: View {
    var title: String
    var subtitle: String = ""
    var onBack: (() -> Void)? = nil
    var backLabel = "Back"
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.outsidePalette) private var palette
    var titleAction: (() -> Void)? = nil

    @ViewBuilder private var titleText: some View {
        if let titleAction {
            Button { Haptics.tap(); titleAction() } label: {
                HStack(spacing: Theme.Space.xs) {
                    Text(title).textStyle(.title).lineLimit(1).minimumScaleFactor(0.7)
                    LedgerGlyph(glyph: Glyph.edit, size: 14, tint: Theme.inkSoft)
                }
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(title + ", rename")
            .accessibilityIdentifier("header-title-rename")
        } else {
            Text(title).textStyle(.title).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if let onBack { RoundBackButton(label: backLabel, action: onBack).padding(.leading, -Theme.Space.m) }
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                titleText
                if !subtitle.isEmpty {
                    Text(subtitle.tidyText).textStyle(.caption).lineLimit(2)
                }
            }
            .accessibilityElement(children: titleAction == nil ? .combine : .contain)
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
    var backdrop: SeasonReward? = nil
    var titleAction: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .swipeBackEnabled()
            .toolbar(.hidden, for: .navigationBar)
            .ledgerBackground()
            .safeAreaInset(edge: .top, spacing: 0) {
                AppHeader(title: title, subtitle: subtitle, onBack: (showsBack && !hidesRootBack) ? { dismiss() } : nil, trailing: trailing, titleAction: titleAction)
                    .environment(\.outsidePalette, palette == OutsidePalette.bank ? OutsidePalette.forest : palette)
                    .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.xs).padding(.bottom, Theme.Space.s)
                    .frame(maxWidth: .infinity)
                    .background {
                        ZStack {
                            if palette == .game {
                                LinearGradient(colors: [Theme.page.opacity(0.6), Theme.page.opacity(0.25)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: [.top, .horizontal])
                            } else {
                                (palette == OutsidePalette.bank ? FinanceColor.forest : palette.ground).ignoresSafeArea(edges: [.top, .horizontal])
                            }
                            if let backdrop { HeaderBackdropFill(reward: backdrop).ignoresSafeArea(edges: [.top, .horizontal]) }
                        }
                    }
            }
    }
}

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
                    LedgerGlyph(glyph: Glyph.back, size: 12, tint: Theme.accent)
                    Text("Back to \(r.from.title)").textStyle(.body, tint: Theme.accent, weight: .medium)
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
    func appScreen(title: String, subtitle: String = "", tab: AppTab = .company, showsBack: Bool = true, backdrop: SeasonReward? = nil, onTitleTap: (() -> Void)? = nil) -> some View {
        modifier(AppScreen(title: title, subtitle: subtitle, tab: tab, showsBack: showsBack, backdrop: backdrop, titleAction: onTitleTap, trailing: { EmptyView() }))
    }
    func appScreen<T: View>(title: String, subtitle: String = "", tab: AppTab = .company, showsBack: Bool = true, backdrop: SeasonReward? = nil, onTitleTap: (() -> Void)? = nil, @ViewBuilder trailing: @escaping () -> T) -> some View {
        modifier(AppScreen(title: title, subtitle: subtitle, tab: tab, showsBack: showsBack, backdrop: backdrop, titleAction: onTitleTap, trailing: trailing))
    }
}

struct StatStrip: View {
    struct Cell: Identifiable {
        var id: String { label }
        var label: String
        var value: String
        var tint: Color = Theme.ink
        var live: Double? = nil
        var glow: Bool = false
    }
    var cells: [Cell]
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

struct CardRow: View {
    @Environment(\.insideCard) private var insideCard
    var glyph: String
    var title: String
    var subtitle: String = ""
    var value: String = ""
    var valueTint: Color = Theme.ink
    var badge: Int = 0
    var chevron = true
    var thumb: ThumbSpec? = nil

    var body: some View {
        let lead: LedgerRow.Leading = thumb.map { LedgerRow.Leading.thumb($0) } ?? LedgerRow.Leading.glyph(glyph)
        Card(padding: 0) {
            LedgerRow(leading: lead, title: title, subtitle: subtitle, value: value, valueTint: valueTint, badge: badge,
                      chevron: chevron, inset: insideCard ? 0 : 14)
        }
    }
}

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

struct ChoiceCard: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var subtitle: String = ""
    var trailing: String = ""
    var selected: Bool
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

struct SegmentedPill<T: Hashable>: View {
    var items: [T]
    var title: (T) -> String
    @Binding var selection: T
    var identifier: ((T) -> String)? = nil
    var badges: ((T) -> Bool)? = nil

    var body: some View {
        let title: (T) -> String = self.title
        let ids: (T) -> String = identifier ?? { (item: T) -> String in "segment-\(title(item))" }
        SegmentTrack(items: items, title: title, selection: $selection, identifier: ids, badges: badges)
    }
}

struct TableColumn: Identifiable {
    var id: String { title }
    var title: String
    var width: CGFloat? = nil
}

struct SharpTable<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    @Environment(\.insideCard) private var insideCard
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        VStack(spacing: 0, content: content)
            .environment(\.insideCard, true)
            .background(insideCard ? Color.clear : P.card)
            .clipShape(shape)
    }
}

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

struct TableRow: View {
    @Environment(\.outsidePalette) private var P
    var columns: [TableColumn]
    var title: String
    var note: String = ""
    var values: [String]
    var valueTints: [Color] = []
    var selected = false
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

struct PillTabItem: Identifiable, Equatable {
    var id: String
    var title: String
    var glyph: String
    var accent: Color = Theme.accent
    var badge: Int = 0
    var changeable: Bool = false
    var locked: Bool = false
}

struct PillTabBar: View {
    var items: [PillTabItem]
    @Binding var selection: String
    var onReselect: (String) -> Void = { _ in }
    var onLongPress: (String) -> Void = { _ in }
    @State private var longPressed: String?
    @State private var flashing: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var pillSpace
    static let height: CGFloat = 66 + 8

    var body: some View {
        GlassGroup { bar }
    }

    private var bar: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let on = item.id == selection
                let traits: AccessibilityTraits = on ? [.isButton, .isSelected] : [.isButton]
                Button {
                    if longPressed == item.id { longPressed = nil; return }
                    if on { onReselect(item.id); flash(item.id) } else { selection = item.id }
                } label: {
                    VStack(spacing: 3) {
                        LedgerGlyph(glyph: item.locked ? Glyph.lock : item.glyph, size: Theme.Icon.medium, tint: on ? item.accent : Theme.inkSoft)
                        Text(item.title).font(.system(size: 11, weight: on ? .medium : .regular)).foregroundStyle(on ? item.accent : Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .id(item.glyph + item.title)
                    .transition(.opacity)
                    .animation(Motion.quickAnimation, value: item.title)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedPill(on, accent: item.accent))
                    .overlay(Capsule().fill(item.accent.opacity(flashing == item.id ? 0.28 : 0)))
                    .overlay(alignment: .topTrailing) { RedBubble(count: item.badge, size: .small).padding(.trailing, 14).offset(y: -4) }
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
                .animation(reduceMotion ? nil : Motion.moveAnimation, value: on)
                .coachAnchor(item.id == AppTab.custom.rawValue ? CoachStop.customTab : CoachStop.tabItem(item.id))
                .accessibilityLabel(item.title)
                .accessibilityActions { if item.changeable { Button("Change destination") { onLongPress(item.id) } } }
                .accessibilityValue(item.locked ? "Locked" : (item.badge > 0 ? "\(item.badge) waiting" : ""))
                .accessibilityIdentifier("tab-\(item.title)")
                .accessibilityAddTraits(traits)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: PillTabBar.height - 8)
        .glassCapsule()
        .elevation(.raised)
        .padding(.horizontal, Theme.Space.l).padding(.bottom, Theme.Space.s)
    }

    @ViewBuilder private func selectedPill(_ on: Bool, accent: Color) -> some View {
        if on {
            Group {
                #if compiler(>=6.2)
                if #available(iOS 26.0, *), !reduceTransparency {
                    Capsule().fill(Color.clear).liquidGlassCapsule(tint: accent, interactive: true)
                } else {
                    Capsule().fill(accent.opacity(0.14)).overlay(Capsule().strokeBorder(accent.opacity(reduceTransparency ? 0.7 : 0.35), lineWidth: 1))
                }
                #else
                Capsule().fill(accent.opacity(0.14)).overlay(Capsule().strokeBorder(accent.opacity(reduceTransparency ? 0.7 : 0.35), lineWidth: 1))
                #endif
            }
            .matchedGeometryEffect(id: "tab-pill", in: pillSpace)
        } else {
            Color.clear
        }
    }

    private func flash(_ id: String) {
        withAnimation(Motion.quick(reduceMotion)) { flashing = id }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            withAnimation(Motion.quick(reduceMotion)) { flashing = nil }
        }
    }
}
