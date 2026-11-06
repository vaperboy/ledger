import SwiftUI
import GameCore
import Businesses
import Simulation

enum CompanyRoute: Hashable {
    /// The company screen: its Overview with the fixed section bar Overview | Team | Manage | Sales | Stats.
    case company(Int)
    case newCompany, market
    /// One screen of a company (a section of the hub, or a trade's own page), opened from the hub, Team, Projects, the Inbox or a deep link.
    case companyAt(Int, CompanySection)
    /// The same screen opened on one of its parts (the Finances page on Ownership, Operations on Premises): `part` is the part's title.
    case companyPart(Int, CompanySection, String)
    /// The Applicants page: company id (0 = all companies) and role id ("" = all roles).
    case applicants(Int, String)

    /// What makes two routes "the same record" for the navigation stack: the company, and for the trade pages that are their own screen
    /// (Marketing, Customers, Market, Plant, Fish, Club, Chain, Book, Setup) the page too. The five sections of the company screen
    /// (Overview, Team, Manage, Sales, Stats) are one record: a link to another of them changes the section shown, it never stacks a copy.
    var key: String {
        switch self {
        case .company(let id): return "company.\(id)"
        case .companyAt(let id, let s), .companyPart(let id, let s, _): return CompanyDetailView.isLeaf(s) ? "company.\(id).\(s.rawValue)" : "company.\(id)"
        case .newCompany: return "newCompany"
        case .applicants: return "applicants"
        case .market: return "market"
        }
    }

    /// The route for `openCompany(id, section:, part:)`. A link without a section opens the hub. Premises are a part of Operations.
    static func make(_ id: Int, _ section: CompanySection?, _ part: String?) -> CompanyRoute {
        guard let section else { return .company(id) }
        if section == .properties { return .companyPart(id, .operations, OpsPart.premises.rawValue) }
        if let part, !part.isEmpty { return .companyPart(id, section, part) }
        return .companyAt(id, section)
    }
}

/// The Home tab: one scrolling page with net worth, what needs the owner, every company in one comparable list (a table on iPad),
/// then rank and shortcuts. The Next day bar stays pinned at the bottom.
struct CompaniesView: View {
    enum Sort: String, CaseIterable, Hashable { case attention = "Needs attention", profit = "Profit", revenue = "Revenue", cash = "Cash", name = "Name" }
    @EnvironmentObject var store: GameStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sort: Sort = .attention
    /// The phone list shows the first `previewCount` companies (worst first) until the owner asks for all of them.
    @State private var showAll = false
    static let previewCount = 6

    var body: some View {
        NavigationStack(path: Binding(get: { store.path(for: .company) }, set: { store.setPath($0, for: .company) })) {
            Group {
                if let e = store.engine {
                    let cos = e.state.companies.filter { $0.type != "hold" && $0.status != .sold }
                    let rows = cos.map { (co: $0, h: e.companyHealth($0)) }.sorted(by: order)
                    homeScreen(e, rows: rows)
                    .id(store.rootToken(.company))
                    .safeAreaInset(edge: .bottom, spacing: 0) { AdvanceBar(engine: e) }
                }
            }
            .ledgerBackground()
            .onAppear { store.refreshPending() }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .companyRouteDestinations()
            .returnBar(for: .company)
        }
    }

    // MARK: The Home page

    /// A normal vertical scroll, so larger text and small phones push content down instead of clipping it.
    private func homeScreen(_ e: GameEngine, rows: [(co: Company, h: CompanyHealth)]) -> some View {
        ScrollView(.vertical) {
            HomeSummary(engine: e, onNewCompany: { store.push(.newCompany, on: .company) }) {
                companiesBlock(e, rows: rows)
            }
            .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.l)
            .frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder private func companiesBlock(_ e: GameEngine, rows: [(co: Company, h: CompanyHealth)]) -> some View {
        if rows.isEmpty {
            LedgerSection("Companies") {
                EmptyState(glyph: Glyph.group, title: "No companies yet", message: "Pick a trade, see the full start-up cost, then decide.",
                           actionTitle: "Choose a trade", action: { store.push(.newCompany, on: .company) })
            }
        } else {
            let regular: Bool = sizeClass == .regular
            let shown: [(co: Company, h: CompanyHealth)] = (showAll || regular) ? rows : Array(rows.prefix(Self.previewCount))
            LedgerSection(title: "Companies · \(rows.count)", trailing: { sortMenu }) {
                companyRows(e, rows: shown)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("home-companies-box")
                if shown.count < rows.count {
                    Button("Show all \(rows.count) companies") { Haptics.tap(); Motion.animate(Motion.quick(reduceMotion)) { showAll = true } }
                        .buttonStyle(TertiaryButtonStyle(size: .compact))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityIdentifier("show-all-companies")
                }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Text("Sorted by \(sort.rawValue.lowercased())").textStyle(.caption, tint: Theme.inkFaint)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(Theme.inkFaint).accessibilityHidden(true)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
    }

    @ViewBuilder private func companyRows(_ e: GameEngine, rows: [(co: Company, h: CompanyHealth)]) -> some View {
        if sizeClass == .regular {
            CompanyTable(engine: e, rows: rows) { store.push(.company($0), on: .company) }
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.co.id) { (i: Int, r: (co: Company, h: CompanyHealth)) in
                    if i > 0 { Hairline() }
                    NavigationLink(value: CompanyRoute.company(r.co.id)) { CompanyRow(engine: e, company: r.co, health: r.h) }
                        .buttonStyle(PressableStyle())
                        .transition(.opacity)
                }
            }
            .animation(Motion.quick(reduceMotion), value: rows.map { (r: (co: Company, h: CompanyHealth)) -> Int in r.co.id })
        }
    }

    private func order(_ a: (co: Company, h: CompanyHealth), _ b: (co: Company, h: CompanyHealth)) -> Bool {
        switch sort {
        case .attention:
            let ra = Self.urgency(a.co, a.h), rb = Self.urgency(b.co, b.h)
            return ra != rb ? ra < rb : a.h.profitTTM < b.h.profitTTM
        case .profit: return a.h.profitTTM > b.h.profitTTM
        case .revenue: return a.h.revenueTTM > b.h.revenueTTM
        case .cash: return a.co.cash > b.co.cash
        case .name: return a.co.name < b.co.name
        }
    }

    /// 0 is most urgent: out of cash, struggling or short of runway come before healthy companies; closed and setting up sit in between.
    static func urgency(_ co: Company, _ h: CompanyHealth) -> Int {
        if co.status == .setup { return 2 }
        if co.status == .closed { return 3 }
        if co.cash < 0 || h.label == "Struggling" { return 0 }
        if let w = h.runwayWeeks, w < 8 { return 0 }
        if h.label == "Tight" { return 1 }
        return 4
    }

}

/// iPad: every company side by side, one row each.
struct CompanyTable: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var rows: [(co: Company, h: CompanyHealth)]
    var open: (Int) -> Void
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Space.l, verticalSpacing: 0) {
            GridRow {
                ForEach(["Company", "Status", "Revenue 12 mo", "Profit 12 mo", "Margin", "Cash", "Cash lasts", "Run by", "Staff", "Limited by"], id: \.self) { h in
                    Text(h).textStyle(.label, tint: Theme.inkFaint).lineLimit(1)
                }
            }
            .padding(.vertical, Theme.Space.s)
            ForEach(rows, id: \.co.id) { r in
                Hairline().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    Button { Haptics.tap(); open(r.co.id) } label: {
                        HStack(spacing: Theme.Space.s) {
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text(r.co.name).textStyle(.headline, tint: Theme.accent).lineLimit(1)
                                Text("\(engine.tradeName(r.co)) · \(engine.cityName(r.co))").textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
                            }
                            LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(PressableStyle())
                    .accessibilityHint("Opens the company")
                    HealthChip(label: r.h.label)
                    num(store.short(r.h.revenueTTM, in: r.co))
                    num(store.short(r.h.profitTTM, in: r.co), Theme.change(r.h.profitTTM) == Theme.inkSoft ? Theme.ink : Theme.change(r.h.profitTTM))
                    num(r.h.marginTTM.map { String(format: "%.0f%%", $0 * 100) } ?? "–")
                    num(store.short(r.co.cash, in: r.co), r.co.cash < 0 ? Theme.loss : Theme.ink)
                    num(RunwayText.of(r.h), r.h.runwayWeeks.map { $0 < 8 ? Theme.loss : Theme.warn } ?? Theme.inkSoft)
                    Text(RunBy.name(engine, r.co)).textStyle(.caption).lineLimit(1)
                    num("\(r.co.staff.count)")
                    Text(r.h.bottleneck ?? "–").textStyle(.caption).lineLimit(1)
                }
                .padding(.vertical, Theme.Space.xs)
            }
        }
    }
    private func num(_ s: String, _ c: Color = Theme.ink) -> some View {
        Text(s).textStyle(.body, tint: c, numeric: true).lineLimit(1)
    }
}

/// "Self-funding", or how many weeks the cash lasts at the current rate of loss.
enum RunwayText {
    static func of(_ h: CompanyHealth) -> String {
        guard let w = h.runwayWeeks else { return h.profitTTM > 0 || h.label == "New" ? "Self-funding" : "–" }
        return w >= 104 ? "2+ years" : "\(Int(w)) weeks"
    }
}

struct HealthChip: View {
    var label: String
    var body: some View {
        Chip(text: label, tint: HealthChip.tint(label))
    }
    static func tint(_ label: String) -> Color {
        switch label { case "Thriving", "Healthy": return Theme.gain; case "Tight": return Theme.caution; case "Struggling": return Theme.loss; default: return Theme.ivoryMuted }
    }
}

struct StatusChip: View {
    var company: Company
    var body: some View {
        switch company.status {
        case .setup: Chip(text: "Setting up", tint: Theme.caution)
        case .open: Chip(text: company.cash < 0 ? "Out of cash" : "Open", tint: company.cash < 0 ? Theme.loss : Theme.gain)
        case .closed: Chip(text: "Closed", tint: Theme.ivoryMuted)
        case .sold: Chip(text: "Sold", tint: Theme.ivoryMuted)
        case .bust: Chip(text: "Bankrupt", tint: Theme.loss)
        default: Chip(text: company.status.rawValue.capitalized)
        }
    }
}

/// One company in the Home list, unboxed between hairlines: icon, name with trade, city and people, profit a year and cash.
struct CompanyRow: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var health: CompanyHealth
    @Environment(Entitlements.self) private var ent
    @AppStorage(CosmeticKeys.badge) private var badgeID: String = Cosmetics.defaultBadgeID
    @AppStorage(CosmeticKeys.theme) private var themeID: String = Cosmetics.defaultThemeID

    var body: some View {
        let co = company, h = health
        // The player's worn badge marks their own companies, in the theme accent.
        let badge: Cosmetics.Badge = Cosmetics.resolvedBadge(badgeID, earned: engine.careerCosmetics, pro: ent.isPro)
        let accent: Color = Cosmetics.resolvedTheme(themeID, pro: ent.isPro).accent
        let urgent = CompaniesView.urgency(co, h) == 0
        let profitTint: Color = h.profitTTM < -0.5 ? Theme.loss : h.profitTTM > 0.5 ? Theme.gain : Theme.inkSoft
        HStack(spacing: Theme.Space.m) {
            ThumbnailView(kind: .trade, key: co.type, size: 36)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                HStack(spacing: Theme.Space.xs) {
                    if urgent { LedgerGlyph(glyph: Glyph.warning, size: Theme.Icon.small, tint: Theme.loss).accessibilityLabel("Needs attention") }
                    Text(co.name).textStyle(.headline).lineLimit(1)
                    CosmeticBadgeView(badge: badge, tint: accent, size: 16)
                }
                Text(subtitle(co)).textStyle(.caption, tint: Theme.inkFaint).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                Text((h.profitTTM < 0 ? "−" : h.profitTTM > 0.5 ? "+" : "") + store.short(abs(h.profitTTM), in: co) + " / yr")
                    .textStyle(.body, tint: profitTint, numeric: true, weight: .medium)
                Text("cash " + store.short(co.cash, in: co)).textStyle(.caption, tint: co.cash < 0 ? Theme.loss : Theme.inkFaint, numeric: true)
            }
            .lineLimit(1)
            LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
        }
        .padding(.vertical, Theme.Space.m)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "Gym · London · 3 people", with the status in place of the people when the company is not open.
    private func subtitle(_ co: Company) -> String {
        let tail = co.status == .open ? co.staff.count.peopleText : (co.status == .setup ? "Setting up" : co.status.rawValue.capitalized)
        return "\(engine.tradeName(co)) · \(engine.cityName(co)) · \(tail)"
    }
}

/// Who runs a company day to day, in two words for list rows: the manager (or the boss above), "You", or "No one".
enum RunBy {
    static func name(_ e: GameEngine, _ co: Company) -> String {
        guard co.status.isLive, co.type != "hold" else { return "–" }
        if let b = e.decisionChain(companyID: co.id).first { return b.name }
        return OwnerHours.works(co) ? "You" : (co.status == .open ? "No one" : "–")
    }
}
