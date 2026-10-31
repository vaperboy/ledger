import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

// The tabs of the Group screen, built to the approved mockups (GroupA Overview, GroupB Structure, GroupC Board; Deals and More follow
// the same pattern). Every figure and every action comes from the engine; the views only choose, format and report.

/// The five underline tabs under the Group header. Four are fixed; More is a menu of the other Group pages.
enum GroupTab: String, CaseIterable, Hashable {
    case overview = "Overview", structure = "Structure", board = "Board", deals = "Deals", more = "More"
}

/// The pages behind the More menu. Everything that used to sit on the long Group page, plus the pages it linked to.
enum GroupMorePage: String, CaseIterable, Hashable, Identifiable {
    case holdings = "Holdings", chains = "Chains", franchises = "Franchises", standAlone = "Stand-alone companies"
    case office = "Group office", posts = "Executive posts", boards = "Boards", dividends = "Dividends and group tax"
    case rivals = "Rival groups and market", giving = "Giving back"
    var id: String { rawValue }
    /// Holdings, chains, franchises and boards are reached from Structure and Board; the More menu keeps the group's own services.
    var inMore: Bool {
        switch self {
        case .holdings, .chains, .franchises, .boards: return false
        default: return true
        }
    }
    var sub: String {
        switch self {
        case .holdings: return "Holding companies and what they own"
        case .chains: return "Chains, their stores and loose store groups"
        case .franchises: return "Franchises you run and units you hold"
        case .standAlone: return "Companies with no group link"
        case .office: return "Main office, reviews, meetings and suppliers"
        case .posts: return "Group managing director and chain posts"
        case .boards: return "Every board and its history"
        case .dividends: return "Last quarter's decisions and tax between companies"
        case .rivals: return "Rival groups and how your trades compare"
        case .giving: return "Gifts, sponsorships and your foundation"
        }
    }
    var glyph: String {
        switch self {
        case .holdings: return Glyph.bank
        case .chains, .franchises: return Glyph.group
        case .standAlone: return Glyph.home
        case .office: return Glyph.team
        case .posts: return Glyph.person
        case .boards: return Glyph.achievements
        case .dividends: return Glyph.reports
        case .rivals: return Glyph.market
        case .giving: return Glyph.richList
        }
    }
}

/// Text tabs with a champagne underline on the chosen one and a "More" menu at the right (never scrolls sideways).
struct GroupTabBar: View {
    @Binding var tab: GroupTab
    @Binding var more: GroupMorePage
    var badges: [GroupTab: Int] = [:]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(GroupTab.allCases.filter { $0 != .more }, id: \.self) { t in
                Button { tab = t; Haptics.choose() } label: { cell(t.rawValue, on: tab == t, badge: badges[t] ?? 0, menu: false) }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tab == t ? [.isButton, .isSelected] : [.isButton])
                    .accessibilityIdentifier("group-tab-\(t.rawValue)")
            }
            Menu {
                ForEach(GroupMorePage.allCases.filter { $0.inMore }) { p in
                    Button { more = p; tab = .more; Haptics.choose() } label: {
                        if tab == .more && more == p { Label(p.rawValue, systemImage: "checkmark") } else { Text(p.rawValue) }
                    }
                }
            } label: { cell("More", on: tab == .more, badge: 0, menu: true) }
                .accessibilityIdentifier("group-tab-More")
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func cell(_ text: String, on: Bool, badge: Int, menu: Bool) -> some View {
        HStack(spacing: 3) {
            Text(text).font(.system(size: 13.5)).lineLimit(1)
            if menu { Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)) }
            RedBubble(count: badge, size: .small)
        }
        .foregroundStyle(on ? Theme.ivory : Theme.ivoryFaint)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
        .overlay(alignment: .bottom) { if on { Rectangle().fill(Theme.gold).frame(height: 2) } }
        .contentShape(Rectangle())
    }
}

// MARK: - Small shared pieces

/// A card with the house outline.
private struct GroupCard<Content: View>: View {
    var strong = false
    var padding = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(strong ? Theme.gold : Theme.border, lineWidth: 1))
    }
}

/// The small champagne caps label above a block, with an optional link at the right.
private struct GroupCaps: View {
    var text: String
    var link: String = ""
    var action: (() -> Void)? = nil
    var body: some View {
        HStack {
            Text(text.uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(1.4).foregroundStyle(Theme.gold)
            Spacer()
            if let action, !link.isEmpty {
                Button { Haptics.tap(); action() } label: { Text(link).font(.system(size: 12)).foregroundStyle(Theme.gold).frame(minHeight: 28) }.buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Overview (GroupA)

/// Group > Overview, laid out like the table-layout mockup: two figure cards, the companies table (every row opens the company, "View all
/// companies" opens the full list), four count tiles that each open their area, and the latest activity. The money card stays last.
struct GroupOverviewTab: View {
    /// How far back the change figures look (the engine keeps 140 days of history).
    enum Period: Int, CaseIterable, Identifiable {
        case week = 7, month = 30, quarter = 90
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .week: return "7 days"
            case .month: return "30 days"
            case .quarter: return "90 days"
            }
        }
    }

    @EnvironmentObject var store: GameStore
    @State private var period: Period = .month
    var engine: GameEngine
    var goStructure: () -> Void
    var openMore: (GroupMorePage) -> Void

    var body: some View {
        let live = engine.state.companies.filter { $0.status.isLive }
        VStack(alignment: .leading, spacing: 12) {
            GroupAttention(engine: engine)
            figures
            companiesTable(live)
            tiles(live)
            activity(live)
            money
        }
    }

    // MARK: Figures

    /// A change as an arrow with a share (or an amount when the earlier value was too small for a share), coloured by direction.
    private func changeText(_ c: (amount: Double, share: Double?)?, in co: Company? = nil, suffix: String = "") -> (text: String, tint: Color) {
        guard let c else { return ("No history yet", Theme.ivoryMuted) }
        guard abs(c.amount) >= 1 else { return ("No change", Theme.ivoryMuted) }
        let up = c.amount >= 0
        let size: String
        if let share = c.share {
            size = String(format: "%+.0f%%", share * 100)
        } else {
            size = co.map { store.short(abs(c.amount), in: $0) } ?? store.short(abs(c.amount))
        }
        return ("\(up ? "▲" : "▼") \(size)\(suffix)", up ? Theme.gain : Theme.loss)
    }

    private var figures: some View {
        let days = period.rawValue
        let value = changeText(DayHistory.change(engine.dayHistory.companies, days: days), suffix: " in \(period.title)")
        let cash = changeText(engine.groupCashChange(days: days), suffix: " in \(period.title)")
        return HStack(alignment: .top, spacing: 10) {
            OverviewFigureCard(label: "Value of holdings", value: store.short(engine.netWorth.companies), note: value.text, noteTint: value.tint)
            OverviewFigureCard(label: "Group cash", value: store.short(engine.groupCash), note: cash.text, noteTint: cash.tint)
        }
    }

    // MARK: Companies table

    private var periodMenu: some View {
        Menu {
            ForEach(Period.allCases) { p in
                Button(p.title) { Haptics.choose(); period = p }
            }
        } label: {
            HStack(spacing: 3) {
                Text(period.title).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.ivoryMuted)
            }
            .frame(minHeight: 28)
        }
        .accessibilityLabel("Change over \(period.title)")
    }

    private func companyRow(_ c: Company, value: Double) -> OverviewRowData {
        let ch = changeText(engine.companyValueChange(companyID: c.id, days: period.rawValue), in: c)
        let id = c.id
        return OverviewRowData(
            id: "co\(id)", glyph: c.type == "hold" ? Glyph.bank : Glyph.home, title: c.name,
            subtitle: "\(engine.tradeName(c)) · \(engine.cityName(c))",
            value: store.short(value, in: c), valueTint: value < 0 ? Theme.loss : Theme.ivory,
            note: ch.text, noteTint: ch.tint,
            action: { store.openCompany(id) })
    }

    private func companiesTable(_ live: [Company]) -> some View {
        let ranked = live.map { (co: $0, value: engine.companyHealth($0).value) }.sorted { $0.value > $1.value }
        let rows = ranked.prefix(5).map { companyRow($0.co, value: $0.value) }
        return OverviewTable(title: "Companies", rows: Array(rows), emptyText: "No companies yet. Start one from Home.",
                             footer: "View all companies ›", footerAction: { store.jump(to: .company) }) {
            periodMenu
        }
    }

    // MARK: Count tiles

    private func tiles(_ live: [Company]) -> some View {
        let operating = live.filter { $0.type != "hold" }
        let franchisors = operating.filter { engine.isFranchisor(companyID: $0.id) }
        let units = franchisors.reduce(0) { $0 + engine.franchiseSystem(companyID: $1.id)["units"].array.count }
        let list: [CountTileData] = [
            CountTileData(glyph: "M5 21 V4 H15 V21 M15 9 H19 V21 M3 21 H21", count: operating.count, label: "Companies", action: { store.jump(to: .company) }),
            CountTileData(glyph: "M12 5 L5 18 H19 Z M12 5 V12", count: engine.chainSummaries.count, label: "Chains", action: { openMore(.chains) }),
            CountTileData(glyph: "M4 9 L6 4 H18 L20 9 M5 9 V20 H19 V9", count: units, label: "Franchises", action: { openMore(.franchises) }),
            CountTileData(glyph: "M4 8 C4 5 20 5 20 8 C20 11 4 11 4 8 M4 8 V16 C4 19 20 19 20 16 V8", count: engine.holdingCompanies.count, label: "Holdings", action: { openMore(.holdings) }),
        ]
        return CountTiles(title: "Structure", link: "View all ›", linkAction: goStructure, tiles: list)
    }

    /// This year's revenue, profit and what is owed in tax. Read-only: the Bank app is where the group's money is managed.
    private var money: some View {
        let o = engine.financeOverview()
        let growth: Double? = o.lastYearProfit > 1 ? o.yearProfit / o.lastYearProfit - 1 : nil
        let taxDue = o.upcoming.first { $0.title.localizedCaseInsensitiveContains("tax") || $0.title.localizedCaseInsensitiveContains("vat") }
        return GroupCard {
            VStack(alignment: .leading, spacing: 2) {
                GroupCaps(text: "Money, this year", link: "Manage in Bank ›") { store.openApp(.bank) }.padding(.bottom, 4)
                moneyRow("Revenue", store.short(o.yearRevenue), "", Theme.ivoryMuted)
                moneyRow("Profit", store.short(o.yearProfit),
                         growth.map { String(format: "%+.0f%%", $0 * 100) } ?? "",
                         (growth ?? 0) < 0 || o.yearProfit < 0 ? Theme.loss : Theme.gain)
                moneyRow("Tax and VAT owed", store.short(o.taxesOwed), taxDue.map { "due \($0.dateText)" } ?? "", Theme.caution)
            }
        }
    }

    private func moneyRow(_ label: String, _ value: String, _ trend: String, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, alignment: .leading)
            Text(value).monospacedDigit().foregroundStyle(Theme.ivory)
            Text(trend).font(.system(size: 12)).foregroundStyle(tint).frame(minWidth: 52, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.7)
        }
        .font(.system(size: 13.5))
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    /// The latest dividend decision of each company that has one, newest first; each opens the company's Finances.
    private func activity(_ live: [Company]) -> some View {
        let rows = live.compactMap { c in engine.lastDividendDecision(companyID: c.id).map { (co: c, d: $0) } }.sorted { $0.d.week > $1.d.week }
        let items: [ActivityItem] = rows.prefix(5).map { r in
            let id = r.co.id
            return ActivityItem(
                id: "div\(id)", glyph: Glyph.reports, title: "Dividend reviewed: \(r.co.name)",
                subtitle: r.d.paid > 0 ? "Last quarter · paid \(store.short(r.d.paid, in: r.co))" : "Last quarter · skipped",
                action: { store.openCompany(id, section: .finances) })
        }
        return ActivityList(items: items, emptyText: "Dividend decisions and group tax show here once your companies make profit.")
    }
}

// MARK: - Structure (GroupB)

/// The four views of Structure: the ownership tree, chains with their franchises, holdings, and who manages whom.
enum GroupStructurePart: String, CaseIterable, Hashable {
    case ownership = "Ownership", chains = "Chains", holdings = "Holdings", authority = "Authority"
    var sub: String {
        switch self {
        case .ownership: return "Who owns what"
        case .chains: return "Chains, stores and franchises"
        case .holdings: return "Holding companies and what they own"
        case .authority: return "Who manages whom"
        }
    }
}

struct GroupStructureTab: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @Binding var part: GroupStructurePart
    var openMore: (GroupMorePage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SegmentedPill(items: GroupStructurePart.allCases, title: { $0.rawValue }, selection: $part, identifier: { "group-structure-\($0.rawValue)" })
            switch part {
            case .ownership: ownership
            case .chains: GroupStructureOverview(engine: engine, parts: [.chains, .franchises])
            case .holdings:
                GroupStructureOverview(engine: engine, parts: [.holdings])
                if engine.holdingCompanies.isEmpty && engine.companiesForHolding.isEmpty {
                    Text("Holding companies need a limited company to hold.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                }
            case .authority: GroupAuthoritySection(engine: engine, openMore: openMore)
            }
        }
    }

    @ViewBuilder private var ownership: some View {
        let live = engine.state.companies.filter { $0.status.isLive && $0.type != "hold" }
        let holdings = engine.holdingCompanies
        let direct = live.filter { $0.holdingID == 0 }
        let chains = engine.chainSummaries
        let franchisors = live.filter { engine.isFranchisor(companyID: $0.id) }
        let units = franchisors.reduce(0) { $0 + engine.franchiseSystem(companyID: $1.id)["units"].array.count }
        let franchised = live.filter { !$0.value("franchise").isNull }
        VStack(alignment: .leading, spacing: 12) {
            CardRow(glyph: Glyph.person, title: "\(engine.state.player.name) (you)",
                    subtitle: "Owner · directly owns \(direct.count) \(direct.count == 1 ? "company" : "companies")",
                    value: store.short(engine.netWorth.companies), chevron: false)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(holdings) { h in
                    let subs = live.filter { $0.holdingID == h.id }
                    NavigationLink(value: CompanyRoute.companyAt(h.id, .holding)) {
                        node(name: h.name, kind: "Holding company · \(subs.count) \(subs.count == 1 ? "company" : "companies") under it",
                             value: store.short(Valuation.companyValue(h, state: engine.state, trades: engine.data.catalog), in: h), profit: nil, in: h)
                    }.buttonStyle(.plain)
                    ForEach(subs) { c in
                        NavigationLink(value: CompanyRoute.company(c.id)) { companyNode(c) }.buttonStyle(.plain).padding(.leading, 18)
                    }
                }
                ForEach(direct) { c in
                    NavigationLink(value: CompanyRoute.company(c.id)) { companyNode(c) }.buttonStyle(.plain)
                }
                if live.isEmpty {
                    Text("Start a company to build a group.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).padding(.vertical, 6)
                }
                if holdings.isEmpty {
                    NavigationLink { NewHoldingView() } label: {
                        HStack {
                            Text("No holding company yet").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                            Spacer()
                            Text("Set one up ›").font(.system(size: 12.5)).foregroundStyle(Theme.gold)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .padding(.leading, 18)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 1).padding(.leading, 0) }
            .padding(.leading, 20)

            HStack(spacing: 8) {
                countTile("Chains", chains.count, chains.isEmpty ? "Start one ›" : "Open ›") { openMore(.chains) }
                countTile("Franchised out", units, units == 0 ? "Offer ›" : "Open ›") { openMore(.franchises) }
                countTile("Franchise you hold", franchised.count, franchised.isEmpty ? "Join ›" : "Open ›") { openMore(.franchises) }
            }
        }
    }

    private func companyNode(_ c: Company) -> some View {
        let h = engine.companyHealth(c)
        return node(name: c.name, kind: "\(engine.tradeName(c)) · \(engine.cityName(c)) · \(h.label)",
                    value: store.short(h.value, in: c), profit: h.profitTTM, in: c)
    }

    private func node(name: String, kind: String, value: String, profit: Double?, in co: Company) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                Text(kind).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value).font(.system(size: 13.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivory)
                if let profit {
                    Text("\(store.short(profit, in: co)) / yr").font(.system(size: 11.5)).foregroundStyle(profit > 0 ? Theme.gain : (profit < 0 ? Theme.loss : Theme.ivoryMuted))
                }
            }
            GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
    }

    private func countTile(_ label: String, _ n: Int, _ cue: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1).minimumScaleFactor(0.7)
                Text("\(n)").font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.ivory)
                Text(cue).font(.system(size: 11)).foregroundStyle(Theme.gold)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

// MARK: - Board (GroupC)

struct GroupBoardTab: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var openMore: (GroupMorePage) -> Void

    /// A board with points waiting for a decision: how many, and the first one in words.
    private struct Waiting: Identifiable {
        var id: String { key }
        var key: String
        var count: Int
        var headline: String
    }

    private var waiting: [Waiting] {
        engine.boardKeys.filter { engine.boardIsActive(key: $0) }.compactMap { k in
            let n = engine.boardOpenDecisions(key: k)
            guard n > 0 else { return nil }
            let open = engine.boardMeetings(key: k).filter { $0.isOpen }
            let first: String = open.compactMap { m in m.isEmergency ? m.title : m.items.first(where: { $0.status.isEmpty && !$0.action.isEmpty })?.text }.first ?? ""
            return Waiting(key: k, count: n, headline: first)
        }
    }

    var body: some View {
        let keys = engine.boardKeys.filter { engine.boardIsActive(key: $0) }
        let live = engine.state.companies.filter { $0.status.isLive && $0.type != "hold" }
        let list = waiting
        VStack(alignment: .leading, spacing: 12) {
            if !list.isEmpty {
                ForEach(list.prefix(3)) { w in decision(w) }
                if list.count > 3 {
                    Text("\(list.count - 3) more \(list.count - 3 == 1 ? "board has" : "boards have") points waiting. Open them below.").font(.system(size: 12)).foregroundStyle(Theme.caution)
                }
            } else {
                GroupCard {
                    VStack(alignment: .leading, spacing: 4) {
                        GroupCaps(text: "Decisions")
                        Text(keys.isEmpty ? "A board forms once you register a chain or somebody else owns part of a company."
                                          : "Nothing waits for a board. A board meets when a seat brings a proposal or a concern.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                GroupCaps(text: "Boards and seats")
                ForEach(keys, id: \.self) { key in
                    let voters = engine.boardVoters(key: key)
                    let seats = engine.boardSeats(key: key)
                    NavigationLink { BoardView(key: key) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(engine.boardName(key: key)).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint).padding(.leading, 2)
                            ForEach(voters.prefix(5)) { v in
                                let fee = seats.first { $0.id == v.personID }?.monthlyFee
                                seatRow(initials: initials(v.name), name: v.name, role: v.title + (v.votes ? " · votes" : " · advises"),
                                        fee: fee.map { store.short($0) + " / month" } ?? "no fee")
                            }
                        }
                    }.buttonStyle(.plain)
                }
                if let key = keys.first {
                    NavigationLink { BoardView(key: key) } label: {
                        Text(keys.count > 1 ? "Open a board to seat someone ›" : "Seat someone ›").font(.system(size: 13)).foregroundStyle(Theme.gold)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }

            owners(live)
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return String(parts).uppercased()
    }

    private func seatRow(initials: String, name: String, role: String, fee: String) -> some View {
        HStack(spacing: 12) {
            Text(initials).font(.system(size: 13)).foregroundStyle(Theme.gold)
                .frame(width: 36, height: 36).background(Circle().fill(Color(hex: 0x1E1F21)))
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                Text(role).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(fee).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
    }

    /// A board with points waiting. Decisions are made on the board page, where each point shows its effect, cost and risk before it is confirmed.
    private func decision(_ w: Waiting) -> some View {
        NavigationLink { BoardView(key: w.key) } label: {
            GroupCard(strong: true) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("DECISION NEEDED").font(.system(size: 10.5, weight: .medium)).tracking(1.4).foregroundStyle(Theme.gold)
                        Spacer()
                        Text("\(w.count) to decide").font(.system(size: 12)).foregroundStyle(Theme.caution)
                    }
                    Text(engine.boardName(key: w.key)).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory)
                    if !w.headline.isEmpty { Text(w.headline.tidyMoney).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading) }
                    Text("Open the board ›").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gold)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.gold, lineWidth: 1))
                        .padding(.top, 2)
                }
            }
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    /// Who owns each company with other owners (or the first few): bars of the shares. "Details" opens the company's Finances.
    @ViewBuilder private func owners(_ live: [Company]) -> some View {
        let withHolders = live.filter { !engine.owners(companyID: $0.id).isEmpty }
        let shown = withHolders.isEmpty ? Array(live.prefix(1)) : Array(withHolders.prefix(4))
        if !shown.isEmpty {
            GroupCard {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(shown) { c in
                        let others = engine.owners(companyID: c.id)
                        let mine = max(0, 100 - others.reduce(0) { $0 + $1.pct })
                        HStack {
                            GroupCaps(text: shown.count > 1 ? "Owners · \(c.name)" : "Owners and stakes")
                            NavigationLink(value: CompanyRoute.companyAt(c.id, .finances)) {
                                Text("Details ›").font(.system(size: 12)).foregroundStyle(Theme.gold).frame(minHeight: 28)
                            }.buttonStyle(.plain)
                        }.padding(.top, c.id == shown.first?.id ? 0 : 8)
                        stakeRow("\(engine.state.player.name) (you)", mine, you: true)
                        ForEach(others) { h in stakeRow(h.name, h.pct, you: false) }
                        if others.isEmpty { stakeRow("Outside investors", 0, you: false) }
                    }
                }
            }
        }
    }

    private func stakeRow(_ name: String, _ pct: Double, you: Bool) -> some View {
        HStack(spacing: 10) {
            Text(name).foregroundStyle(you ? Theme.ivory : Theme.ivoryMuted).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(Color(hex: 0x26272A)).frame(width: 90, height: 4)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.gold).frame(width: 90 * CGFloat(min(100, max(0, pct)) / 100), height: 4) }
            Text("\(Int(pct.rounded()))%").monospacedDigit().foregroundStyle(you ? Theme.ivory : Theme.ivoryMuted).frame(width: 44, alignment: .trailing)
        }
        .font(.system(size: 13.5))
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}

// MARK: - Deals

/// Franchise offers and brands, buying a rival, and the deals the group can host or agree. Pages that already exist are reused.
struct GroupDealsTab: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var openMore: (GroupMorePage) -> Void

    var body: some View {
        let live = engine.state.companies.filter { $0.status.isLive && $0.type != "hold" }
        let franchisors = live.filter { engine.isFranchisor(companyID: $0.id) }
        let brands = engine.franchiseBrands()
        let chains = engine.chainSummaries
        let open = live.filter { $0.status == .open }
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                GroupCaps(text: "Franchise offers")
                ForEach(franchisors) { c in
                    let chain = chains.first { $0.stores.contains { $0.id == c.id } }
                    ForEach(engine.franchiseApplicants(companyID: c.id)) { a in
                        let cur = engine.currency(for: c)
                        NavigationLink { FranchiseTalkView(companyID: c.id, applicantID: a.id) } label: {
                            CardRow(glyph: Glyph.person, title: "\(a.name) applies to \(chain?.name ?? c.name)",
                                    subtitle: "\(a.experience) yr experience · own money \(cur.tidyShort(a.capital))", value: "Talk")
                        }.buttonStyle(.plain)
                    }
                }
                NavigationLink { FranchisesView() } label: {
                    CardRow(glyph: Glyph.group, title: "Brands that take franchisees",
                            subtitle: brands.isEmpty ? "No brand is looking for franchisees right now." : "\(brands.count) \(brands.count == 1 ? "brand" : "brands") · apply, meet them, agree terms",
                            value: brands.isEmpty ? "" : "\(brands.count)")
                }.buttonStyle(.plain)
                if !franchisors.isEmpty {
                    Button { Haptics.tap(); openMore(.franchises) } label: {
                        CardRow(glyph: Glyph.chevron, title: "Your franchise system", subtitle: "Units, fees and royalties of what you franchise out")
                    }.buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                GroupCaps(text: "Acquisitions")
                if open.isEmpty {
                    Text("Open a company to look at rivals you could buy.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                } else {
                    NavigationLink(value: CompanyRoute.market) {
                        CardRow(glyph: Glyph.market, title: "Rivals you could buy", subtitle: "Pick a rival in the market; the price and what it becomes are agreed there.")
                    }.buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                GroupCaps(text: "Group deals")
                HostingSection(engine: engine)
                if !engine.knownSuppliers.isEmpty {
                    Button { Haptics.tap(); openMore(.office) } label: {
                        CardRow(glyph: Glyph.bank, title: "Supplier deals for the whole group", subtitle: "\(engine.knownSuppliers.count) known \(engine.knownSuppliers.count == 1 ? "supplier" : "suppliers") · under Group office")
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - More

/// The page chosen in the More menu. Sections that were part of the old long Group page are drawn as they were; the rest are links.
struct GroupMoreTab: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var page: GroupMorePage
    var pick: (GroupMorePage) -> Void
    var showGiving: () -> Void

    var body: some View {
        let live = engine.state.companies.filter { $0.type != "hold" && $0.status.isLive }
        VStack(alignment: .leading, spacing: 12) {
            switch page {
            case .holdings:
                GroupStructureOverview(engine: engine, parts: [.holdings])
                if engine.holdingCompanies.isEmpty && engine.companiesForHolding.isEmpty {
                    Text("Holding companies need a limited company to hold.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                }
            case .chains: GroupStructureOverview(engine: engine, parts: [.chains])
            case .franchises: GroupStructureOverview(engine: engine, parts: [.franchises])
            case .standAlone: GroupStructureOverview(engine: engine, parts: [.standAlone])
            case .dividends: GroupStructureOverview(engine: engine, parts: [.dividends])
            case .office:
                if !live.isEmpty { HeadOfficeSection(engine: engine) } else { Text("Start a company first.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted) }
            case .posts:
                if engine.groupOfficeEstablished && live.count >= 2 {
                    ExecutivePosts(engine: engine, chainID: nil)
                } else {
                    Text("Group posts exist once you set up a group office and run two companies.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                    Button { pick(.office) } label: { Text("Open Group office ›").font(.system(size: 13)).foregroundStyle(Theme.gold).frame(minHeight: 36) }.buttonStyle(.plain)
                }
            case .boards:
                BoardsGroupSection(engine: engine) { store.openApp(.bank) }
            case .rivals:
                if live.contains(where: { $0.status == .open }) {
                    NavigationLink(value: CompanyRoute.market) {
                        CardRow(glyph: Glyph.market, title: "Market, reviews and rivals", subtitle: "Rival groups and how your trades compare.")
                    }.buttonStyle(.plain)
                } else {
                    Text("Open a company to see the market and rival groups.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                }
            case .giving:
                Button { Haptics.tap(); showGiving() } label: {
                    CardRow(glyph: Glyph.richList, title: "Gifts, sponsorships and your foundation",
                            subtitle: "\(engine.givingMarks.count) \(engine.givingMarks.count == 1 ? "mark" : "marks")" + (engine.foundation != nil ? " · foundation running" : "") + " · paid from your own cash")
                }.buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                GroupCaps(text: "Other pages")
                ForEach(GroupMorePage.allCases.filter { $0 != page && $0.inMore }) { p in
                    Button { Haptics.tap(); pick(p) } label: { CardRow(glyph: p.glyph, title: p.rawValue, subtitle: p.sub) }.buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        }
    }
}
