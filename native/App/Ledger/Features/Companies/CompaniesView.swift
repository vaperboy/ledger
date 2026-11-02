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

    /// What makes two routes "the same record" for the navigation stack: the company, and for the trade pages that are their own screen
    /// (Marketing, Customers, Market, Plant, Fish, Club, Chain, Book, Setup) the page too. The five sections of the company screen
    /// (Overview, Team, Manage, Sales, Stats) are one record: a link to another of them changes the section shown, it never stacks a copy.
    var key: String {
        switch self {
        case .company(let id): return "company.\(id)"
        case .companyAt(let id, let s), .companyPart(let id, let s, _): return CompanyDetailView.isLeaf(s) ? "company.\(id).\(s.rawValue)" : "company.\(id)"
        case .newCompany: return "newCompany"
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

/// The companies and the group as a whole: totals at the top, then every company in one comparable list (a table on iPad).
/// Replaces the former separate Group tab, which listed the same companies again.
struct CompaniesView: View {
    enum Sort: String, CaseIterable, Hashable { case attention = "Needs attention", profit = "Profit", revenue = "Revenue", cash = "Cash", name = "Name" }
    @EnvironmentObject var store: GameStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var sort: Sort = .attention
    /// With many companies: a name search and a filter by chain ("all", "independent" or a chain id).
    @State private var query = ""
    @State private var chainFilter = "all"
    /// The measured height of Home's fixed top block (date, net worth, shortcuts, priorities); the estimate holds until the first pass.
    @State private var topHeight: CGFloat = 330

    var body: some View {
        NavigationStack(path: Binding(get: { store.path(for: .company) }, set: { store.setPath($0, for: .company) })) {
            Group {
                if let e = store.engine {
                    let cos = e.state.companies.filter { $0.type != "hold" && $0.status != .sold }
                    let rows = cos.filter(matches).map { (co: $0, h: e.companyHealth($0)) }.sorted(by: order)
                    homeScreen(e, cos: cos, rows: rows)
                    .id(store.rootToken(.company))
                    .safeAreaInset(edge: .bottom, spacing: 0) { AdvanceBar(engine: e) }
                }
            }
            .ledgerBackground()
            .overlay { celebration }
            .onAppear { store.refreshPending() }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .companyRouteDestinations()
            .returnBar(for: .company)
        }
    }

    // MARK: The locked Home screen

    private static let rowHeight: CGFloat = 46
    private static let moreHeight: CGFloat = 34

    /// How many company rows fit in `avail` points under the "Companies" title (at least 2 when more exist), and whether the
    /// final "All N companies in Group" row is needed; `used` is the height the block takes.
    static func companyFit(avail: CGFloat, count: Int, head: CGFloat, pitch: CGFloat) -> (shown: Int, more: Bool, used: CGFloat) {
        let room: CGFloat = avail - head + 5
        let all: Int = Int((room / pitch).rounded(.down))
        if count <= max(2, all) { return (count, false, head + CGFloat(count) * pitch - 5) }
        let shown: Int = min(count, max(2, Int(((room - moreHeight - 5) / pitch).rounded(.down))))
        return (shown, true, head + CGFloat(shown) * pitch - 5 + 5 + moreHeight)
    }

    /// One locked screen: nothing scrolls. The top block has its natural height; the companies take what they can use of the rest
    /// (most important first, then the Group link), and "Recent" sits at the bottom with only the space that is left.
    @ViewBuilder private func homeScreen(_ e: GameEngine, cos: [Company], rows: [(co: Company, h: CompanyHealth)]) -> some View {
        let regular: Bool = sizeClass == .regular
        GeometryReader { (geo: GeometryProxy) in
            let total: CGFloat = geo.size.height - 12
            let head: CGFloat = regular ? 66 : 27
            let pitch: CGFloat = regular ? 52 : Self.rowHeight + 5
            let minCompanies: CGFloat = cos.isEmpty ? 120 : head + CGFloat(min(2, cos.count)) * pitch - 5
            let priorities: Int = max(1, min(3, Int(((total - 290 - 36 - 32 - 8 - minCompanies - 8) / 38).rounded(.down))))
            let mid: CGFloat = max(0, total - topHeight - 8)
            let fit = Self.companyFit(avail: mid, count: rows.count, head: head, pitch: pitch)
            let used: CGFloat = cos.isEmpty ? 120 : fit.used
            let recent: Int = max(0, min(6, Int(((mid - used - 8 - HomeTimeline.titleHeight) / HomeTimeline.rowHeight).rounded(.down))))
            VStack(alignment: .leading, spacing: 8) {
                HomeSummary(engine: e, onNewCompany: { store.push(.newCompany, on: .company) }, maxPriorities: priorities)
                    .background(GeometryReader { (g: GeometryProxy) in Color.clear.preference(key: HomeTopHeightKey.self, value: g.size.height) })
                companiesBlock(e, cos: cos, rows: rows, shown: fit.shown, more: fit.more)
                Spacer(minLength: 0)
                HomeTimeline(maxRows: recent)
            }
            .onPreferenceChange(HomeTopHeightKey.self) { topHeight = $0 }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 4)
            .frame(maxWidth: 1100).frame(maxWidth: .infinity)
            .frame(height: geo.size.height, alignment: .top)
            .clipped()
        }
    }

    @ViewBuilder private func companiesBlock(_ e: GameEngine, cos: [Company], rows: [(co: Company, h: CompanyHealth)], shown: Int, more: Bool) -> some View {
        if cos.isEmpty {
            Card(padding: 12, radius: Theme.Radius.card) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No companies yet").font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                    Text("Pick a trade, see the full start-up cost, then decide.").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    QuietButton(title: "Choose a trade") { store.push(.newCompany, on: .company) }
                }
            }
        } else {
            let list: [(co: Company, h: CompanyHealth)] = Array(rows.prefix(shown))
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Companies").font(.system(size: 10.5, weight: .semibold)).tracking(1.4).textCase(.uppercase).foregroundStyle(Theme.gold)
                    Spacer()
                    Menu {
                        Picker("Sort by", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    } label: {
                        Text("Sorted by \(sort.rawValue.lowercased())  ⌄").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    }
                }
                .frame(height: 22)
                if sizeClass == .regular {
                    CompanyTable(engine: e, rows: list) { store.push(.company($0), on: .company) }
                } else {
                    ForEach(list, id: \.co.id) { r in
                        NavigationLink(value: CompanyRoute.company(r.co.id)) { CompanyRow(engine: e, company: r.co, health: r.h) }
                            .buttonStyle(PressableStyle())
                            .frame(height: Self.rowHeight)
                    }
                }
                if more {
                    Button { Haptics.tap(); store.selectTab(.group) } label: {
                        HStack {
                            Spacer()
                            Text("All \(rows.count) companies in Group ›").font(.system(size: 11.5)).foregroundStyle(Theme.gold)
                        }
                        .frame(height: Self.moreHeight).contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle()).accessibilityIdentifier("home-open-group")
                }
            }
        }
    }

    /// The reward popup, once the report sheet (if any) has been read.
    @ViewBuilder private var celebration: some View {
        if store.ambitionPrompt {
            AmbitionPrompt().transition(.opacity)
        } else if store.reportSheet == nil, store.dailySheet == nil, let first = store.celebrationQueue.first {
            CelebrationPopup(item: first).id(first.id).transition(.opacity)
        }
    }

    private func matches(_ co: Company) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty && !co.name.lowercased().contains(q) && !(store.engine.map { $0.cityName(co).lowercased().contains(q) || $0.tradeName(co).lowercased().contains(q) } ?? false) { return false }
        switch chainFilter {
        case "all": return true
        case "independent": return co.value("chain").isNull
        default: return !co.value("chain").isNull && String(co.value("chain").int) == chainFilter
        }
    }

    /// Search and chain chips, shown once there are enough companies for a long list to need them.
    @ViewBuilder private func filterBar(_ chains: [Chains.Summary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                TextField("Name, city or trade", text: $query).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).textInputAutocapitalization(.never).autocorrectionDisabled()
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.ivoryFaint) }.buttonStyle(PressableStyle()) }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Color.white.opacity(0.05)))
            if !chains.isEmpty {
                SectionTabs(items: ["all"] + chains.map { String($0.id) } + ["independent"],
                            title: { k in k == "all" ? "All" : k == "independent" ? "Independent" : (chains.first { String($0.id) == k }?.name ?? "Chain") },
                            selection: $chainFilter).padding(.horizontal, -18)
            }
        }.padding(.bottom, 6)
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
        Card(padding: 0, rule: false) {
            Grid(alignment: .leading, horizontalSpacing: Theme.Space.l, verticalSpacing: 0) {
                GridRow {
                    ForEach(["Company", "Status", "Revenue 12 mo", "Profit 12 mo", "Margin", "Cash", "Cash lasts", "Run by", "Staff", "Limited by"], id: \.self) { h in
                        Text(h).font(.system(size: 9.5, weight: .semibold)).tracking(1).textCase(.uppercase).foregroundStyle(Theme.ivoryFaint)
                    }
                }
                .padding(.vertical, Theme.Space.m)
                ForEach(rows, id: \.co.id) { r in
                    Hairline().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        Button { Haptics.tap(); open(r.co.id) } label: {
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.co.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.gold).lineLimit(1)
                                    Text("\(engine.tradeName(r.co)) · \(engine.cityName(r.co))").font(.caption2).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                                }
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.gold)
                            }.contentShape(Rectangle())
                        }.buttonStyle(PressableStyle())
                        .accessibilityHint("Opens the company")
                        HealthChip(label: r.h.label)
                        num(store.short(r.h.revenueTTM, in: r.co))
                        num(store.short(r.h.profitTTM, in: r.co), Theme.change(r.h.profitTTM) == Theme.ivoryMuted ? Theme.ivory : Theme.change(r.h.profitTTM))
                        num(r.h.marginTTM.map { String(format: "%.0f%%", $0 * 100) } ?? "–")
                        num(store.short(r.co.cash, in: r.co), r.co.cash < 0 ? Theme.loss : Theme.ivory)
                        num(RunwayText.of(r.h), r.h.runwayWeeks.map { $0 < 8 ? Theme.loss : Theme.caution } ?? Theme.ivoryMuted)
                        Text(RunBy.name(engine, r.co)).font(.caption).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
                        num("\(r.co.staff.count)")
                        Text(r.h.bottleneck ?? "–").font(.caption).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }
    private func num(_ s: String, _ c: Color = Theme.ivory) -> some View {
        Text(s).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(c).lineLimit(1)
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

/// One company in the list, a slim card as in the Home mockup: icon, name with trade, city and people, value, and profit a year.
struct CompanyRow: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var health: CompanyHealth

    var body: some View {
        let co = company, h = health
        let urgent = CompaniesView.urgency(co, h) == 0
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        HStack(spacing: 10) {
            ThumbnailView(kind: .trade, key: co.type, size: 30)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    if urgent { GlyphView(glyph: Glyph.warning, size: 12, weight: 1.9, tint: Theme.loss).accessibilityLabel("Needs attention") }
                    Text(co.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                }
                Text(subtitle(co)).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                Text((h.profitTTM < 0 ? "−" : h.profitTTM > 0.5 ? "+" : "") + store.short(abs(h.profitTTM), in: co) + " / yr")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(h.profitTTM < -0.5 ? Theme.loss : h.profitTTM > 0.5 ? Theme.gain : Theme.ivoryMuted)
                Text("cash " + store.short(co.cash, in: co)).font(.system(size: 11).monospacedDigit()).foregroundStyle(co.cash < 0 ? Theme.loss : Theme.ivoryFaint)
            }
            .lineLimit(1)
            GlyphView(glyph: Glyph.chevron, size: 11, weight: 2, tint: Theme.ivoryDim)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(shape.fill(Theme.surface))
        .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
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

/// Carries the measured height of Home's fixed top block up to the screen that lays the rest out.
struct HomeTopHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
