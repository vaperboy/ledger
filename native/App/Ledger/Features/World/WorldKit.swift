import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

extension Glyph {
    static let civicDome = "M4 20 H20 M6 20 V11 M10 20 V11 M14 20 V11 M18 20 V11 M3 11 H21 L12 4 Z"
    static let ballotBox = "M4 12 H20 V20 H4 Z M8 12 L6 5 H18 L16 12 M10 8 H14"
    static let gavel = "M5 20 H13 M9 20 V15 M6 9 L12 3 L16 7 L10 13 Z M14 9 L19 14"
    static let coinStack = "M12 4 A8 8 0 1 0 12 20 A8 8 0 1 0 12 4 M12 7.5 V16.5 M9.5 10 H13.5 M10.5 14 H14.5"
    static let watchEye = "M2 12 C6 6 18 6 22 12 C18 18 6 18 2 12 M12 9 A3 3 0 1 0 12 15 A3 3 0 1 0 12 9"
    static let podium = "M3 20 H21 M8 20 V12 H16 V20 M12 12 V6 M12 6 L16 8 L12 10"
}

extension OutsidePalette {
    static let civic = OutsidePalette(
        ground: Color(hex: 0x0D1424), ground2: Color(hex: 0x080D18), card: Color(hex: 0x141D33), cardDeep: Color(hex: 0x0F172B),
        line: Color(hex: 0x24304D), lineStrong: Color(hex: 0x3B4A70), divider: Color(hex: 0x202B47), hairline: Color(hex: 0x1B253F),
        ink: Color(hex: 0xEDEAE0), inkSoft: Color(hex: 0xADB6CC), inkFaint: Color(hex: 0x8B96B1), inkDim: Color(hex: 0x6E7A97),
        accent: Color(hex: 0xCBAA6B), accent2: Color(hex: 0x86A9DA), onAccent: Color(hex: 0x0D1424),
        gain: Color(hex: 0x7FCBA0), loss: Color(hex: 0xE39583), caution: Color(hex: 0xDDB872))

    static let pledge = OutsidePalette(
        ground: Color(hex: 0xF5EEE0), ground2: Color(hex: 0xEADFC9), card: Color(hex: 0xFBF7EC), cardDeep: Color(hex: 0xEFE5CF),
        line: Color(hex: 0xDACDB1), lineStrong: Color(hex: 0xA8997A), divider: Color(hex: 0xE3D8BF), hairline: Color(hex: 0xE3D8BF),
        ink: Color(hex: 0x2A1B1E), inkSoft: Color(hex: 0x5A4647), inkFaint: Color(hex: 0x76625F), inkDim: Color(hex: 0x8F7D78),
        accent: Color(hex: 0x7A2E3A), accent2: Color(hex: 0xA57C2E), onAccent: Color(hex: 0xFBF7EC),
        gain: Color(hex: 0x2B6B45), loss: Color(hex: 0xA8322B), caution: Color(hex: 0x86601E), isLight: true)

    static let ballot = OutsidePalette(
        ground: Color(hex: 0xF4F4EF), ground2: Color(hex: 0xE8E8E0), card: Color(hex: 0xFFFFFF), cardDeep: Color(hex: 0xECECE4),
        line: Color(hex: 0xCFCFC4), lineStrong: Color(hex: 0x1A1A1A), divider: Color(hex: 0xDDDDD2), hairline: Color(hex: 0xDDDDD2),
        ink: Color(hex: 0x141414), inkSoft: Color(hex: 0x40403B), inkFaint: Color(hex: 0x5E5E57), inkDim: Color(hex: 0x82827A),
        accent: Color(hex: 0x1D3F8A), accent2: Color(hex: 0xB3262E), onAccent: Color(hex: 0xFFFFFF),
        gain: Color(hex: 0x2B6B45), loss: Color(hex: 0xB3262E), caution: Color(hex: 0x86601E), isLight: true)

    static let oval = OutsidePalette(
        ground: Color(hex: 0x1B0F13), ground2: Color(hex: 0x12090C), card: Color(hex: 0x2A1920), cardDeep: Color(hex: 0x22141A),
        line: Color(hex: 0x472A33), lineStrong: Color(hex: 0x6A414D), divider: Color(hex: 0x3A222A), hairline: Color(hex: 0x321D24),
        ink: Color(hex: 0xF3E9DA), inkSoft: Color(hex: 0xCDB9B0), inkFaint: Color(hex: 0xA48F89), inkDim: Color(hex: 0x86726D),
        accent: Color(hex: 0xD6B26B), accent2: Color(hex: 0xE9CF98), onAccent: Color(hex: 0x1B0F13),
        gain: Color(hex: 0x8ED0A6), loss: Color(hex: 0xEE9C8C), caution: Color(hex: 0xE3B766))

    static let shadow = OutsidePalette(
        ground: Color(hex: 0x0A0A0B), ground2: Color(hex: 0x060607), card: Color(hex: 0x161516), cardDeep: Color(hex: 0x101011),
        line: Color(hex: 0x2A2829), lineStrong: Color(hex: 0x4B4647), divider: Color(hex: 0x222021), hairline: Color(hex: 0x1D1B1C),
        ink: Color(hex: 0xEFEBE4), inkSoft: Color(hex: 0xB5AFA6), inkFaint: Color(hex: 0x948E86), inkDim: Color(hex: 0x76716A),
        accent: Color(hex: 0xE2A53A), accent2: Color(hex: 0xE2A53A), onAccent: Color(hex: 0x0A0A0B),
        gain: Color(hex: 0x86CFA0), loss: Color(hex: 0xEF6A5C), caution: Color(hex: 0xE2A53A))

    static let docket = OutsidePalette(
        ground: Color(hex: 0xE8EAED), ground2: Color(hex: 0xDADDE2), card: Color(hex: 0xF7F8FA), cardDeep: Color(hex: 0xE0E3E8),
        line: Color(hex: 0xC5CAD3), lineStrong: Color(hex: 0x4A5A73), divider: Color(hex: 0xD3D7DE), hairline: Color(hex: 0xD3D7DE),
        ink: Color(hex: 0x18212D), inkSoft: Color(hex: 0x445165), inkFaint: Color(hex: 0x5D6A7E), inkDim: Color(hex: 0x838EA0),
        accent: Color(hex: 0xA8322B), accent2: Color(hex: 0x4A5A73), onAccent: Color(hex: 0xFFFFFF),
        gain: Color(hex: 0x2B6B45), loss: Color(hex: 0xA8322B), caution: Color(hex: 0x86601E), isLight: true)
}

struct CountryRead {
    var code: String
    var name: String
    var gov: Government
    var world: GovernmentWorld
    var week: Int
    var cur: Currency

    var account: String { world.account }
    var playerName: String { world.name }
    var isPresident: Bool { gov.isPresident(world.account, week: week) }
    var isAdmin: Bool { gov.isAdmin(world.account) }

    func isMe(_ acct: String) -> Bool { acct == world.account }
    func shown(_ name: String, account acct: String) -> String { isMe(acct) ? "You" : name }
}

extension GameEngine {
    func countryRead() -> CountryRead? {
        let w: GovernmentWorld = GovernmentBridge.world(state)
        let cc: String = state.homeCountryCode
        guard let g = w.countries[cc] else { return nil }
        return CountryRead(code: cc, name: homeCountry.name, gov: g, world: w, week: state.week, cur: homeCurrency)
    }

    func supportTrades() -> [Trade] {
        data.catalog.order.compactMap { (id: String) -> Trade? in id == "hold" ? nil : data.catalog.trades[id] }
    }
}

extension GameStore {
    @discardableResult
    func govRun(_ body: (inout GameState, GameData, FinanceContext) throws -> Void) -> Bool {
        var failure: String? = nil
        act { (e: inout GameEngine) -> Void in
            e.update { (s: inout GameState, d: GameData, c: FinanceContext) -> Void in
                do { try body(&s, d, c) } catch { failure = error.localizedDescription }
            }
        }
        if let f = failure {
            Haptics.warning()
            tell("", f, tone: "warn")
            return false
        }
        return true
    }

    func ensureCountry() {
        guard let e = engine, GovernmentBridge.world(e.state).countries[e.state.homeCountryCode] == nil else { return }
        govRun { (s: inout GameState, _: GameData, c: FinanceContext) -> Void in
            let cc: String = s.homeCountryCode
            let supply: Double = max(1, c.currency(cc, s).scaledPrice(1_000_000_000))
            GovernmentBridge.ensure(&s, country: cc, admins: [], startingSupply: supply)
        }
    }
}

enum CivicWords {
    static func weeks(_ n: Int) -> String { n == 1 ? "1 week" : "\(n) weeks" }
    static func pct(_ x: Double) -> String { String(format: "%.0f%%", x * 100) }
    static func pct1(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }
    static func date(_ week: Int) -> String { GameCalendar.dateString(week: week) }

    static func treasuryKind(_ k: String) -> String {
        switch k {
        case "donation": return "Donation"
        case "mint": return "New money printed"
        case "candidacy_fee": return "Candidacy fee"
        case "conviction_fine": return "Fine after a conviction"
        case "audit_fine": return "Audit settlement"
        case "price_support": return "Price support paid out"
        case "conviction_refund": return "Fine returned"
        case "tax": return "Tax"
        default: return k.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func offence(_ k: PlayerConviction.Kind) -> String {
        switch k {
        case .taxEvasion: return "Tax evasion"
        case .fraud: return "Fraud"
        case .unsafeGoods: return "Unsafe goods"
        case .smuggling: return "Smuggling"
        case .bribery: return "Bribery"
        case .counterfeiting: return "Counterfeiting"
        case .harassment: return "Harassment"
        case .sabotage: return "Sabotage"
        }
    }

    static func promise(_ p: CampaignPromise, trades: (String) -> String) -> String {
        switch p.kind {
        case .transferTax: return "Transfer tax to \(pct1(p.value))"
        case .gainsTax: return "Gains tax to \(pct1(p.value))"
        case .priceSupport: return "Price support of \(pct1(p.value)) for \(trades(p.tradeID ?? ""))"
        }
    }

    static func severity(_ r: IllegalRoute) -> String {
        switch r.severity { case 1: return "Minor"; case 2: return "Serious"; default: return "Grave" }
    }

    static func number(_ text: String) -> Double? {
        let t: String = text.filter { "0123456789.".contains($0) }
        guard !t.isEmpty, let v = Double(t), v.isFinite else { return nil }
        return v
    }
}

struct CivicHeader: View {
    var title: String
    var subtitle: String = ""
    var onBack: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            if let onBack { RoundBackButton { onBack() } } else { OutsideBack() }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).textStyle(.title).lineLimit(1).minimumScaleFactor(0.7).accessibilityAddTraits(.isHeader)
                if !subtitle.isEmpty { Text(subtitle).textStyle(.caption).lineLimit(2) }
            }
            Spacer(minLength: 0)
        }
    }
}

struct CivicPage<Content: View>: View {
    var spacing: CGFloat = 18
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: spacing) { content() }
                .padding(.horizontal, Theme.Space.page).padding(.top, 6).padding(.bottom, 40)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
}

struct CivicDial: View {
    var fraction: Double
    var center: String
    var label: String
    var note: String = ""
    var tint: Color
    var track: Color
    var ink: Color
    var soft: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().trim(from: 0, to: 0.75).rotation(.degrees(135))
                    .stroke(track, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                Circle().trim(from: 0, to: 0.75 * min(1, max(0.02, fraction))).rotation(.degrees(135))
                    .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                Text(center).font(.system(size: 20, weight: .medium, design: .serif).monospacedDigit()).foregroundStyle(ink)
            }
            .frame(width: 92, height: 92)
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
            if !note.isEmpty { Text(note).font(.system(size: 11)).foregroundStyle(soft).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct CivicSpark: View {
    var values: [Double]
    var tint: Color

    var body: some View {
        GeometryReader { (g: GeometryProxy) in
            let lo: Double = values.min() ?? 0
            let hi: Double = values.max() ?? 1
            let span: Double = max(hi - lo, 0.0001)
            Path { (p: inout Path) in
                for (i, v) in values.enumerated() {
                    let x: CGFloat = values.count > 1 ? g.size.width * CGFloat(i) / CGFloat(values.count - 1) : 0
                    let y: CGFloat = g.size.height * (1 - CGFloat((v - lo) / span))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

struct CivicStepper: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var format: (Double) -> String
    var tint: Color
    var ink: Color
    var fill: Color

    private func snap(_ x: Double) -> Double { (x * 10_000).rounded() / 10_000 }

    var body: some View {
        HStack(spacing: 0) {
            Button { value = snap(max(range.lowerBound, value - step)); Haptics.choose() } label: {
                Text("\u{2212}").font(.system(size: 22, weight: .medium)).foregroundStyle(tint).frame(width: 44, height: 44)
            }
            .disabled(value <= range.lowerBound + 1e-9).accessibilityLabel("Lower")
            Text(format(value)).font(.system(size: 17, weight: .semibold, design: .serif).monospacedDigit()).foregroundStyle(ink)
                .frame(minWidth: 64)
            Button { value = snap(min(range.upperBound, value + step)); Haptics.choose() } label: {
                Text("+").font(.system(size: 22, weight: .medium)).foregroundStyle(tint).frame(width: 44, height: 44)
            }
            .disabled(value >= range.upperBound - 1e-9).accessibilityLabel("Raise")
        }
        .buttonStyle(PressableStyle())
        .background(Capsule().fill(fill))
    }
}

struct CivicTag: View {
    var text: String
    var tint: Color
    var filled: Bool = false
    var onFill: Color = .white

    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold)).tracking(0.6).textCase(.uppercase)
            .foregroundStyle(filled ? onFill : tint)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(filled ? tint : tint.opacity(0.14)))
    }
}

struct CivicAmountField: View {
    @Binding var text: String
    var symbol: String
    var placeholder: String = "0"
    var ink: Color
    var soft: Color
    var fill: Color
    var edge: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(symbol).font(.system(size: 20, weight: .medium, design: .serif)).foregroundStyle(soft)
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .font(.system(size: 26, weight: .medium, design: .serif).monospacedDigit())
                .foregroundStyle(ink)
                .tint(ink)
        }
        .padding(.horizontal, 14).frame(minHeight: 56)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(edge, lineWidth: 1))
    }
}

struct CivicTile: View {
    var glyph: String
    var title: String
    var line: String
    var fill: Color
    var edge: Color
    var tint: Color
    var ink: Color
    var soft: Color
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                GlyphView(glyph: glyph, size: 26, weight: 1.6, tint: tint)
                Text(title).font(.system(size: 16, weight: .semibold, design: .serif)).foregroundStyle(ink)
                Text(line).font(.system(size: 12)).foregroundStyle(soft).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(edge, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
        .accessibilityHint(line)
    }
}
