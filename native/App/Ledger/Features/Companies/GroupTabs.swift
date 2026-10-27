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
                ForEach(GroupMorePage.allCases) { p in
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

struct GroupOverviewTab: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var goStructure: () -> Void

    var body: some View {
        let live = engine.state.companies.filter { $0.type != "hold" && $0.status.isLive }
        let health = live.map { engine.companyHealth($0) }
        let value = engine.netWorth.companies
        let change = DayHistory.change(engine.dayHistory.companies, days: 30)
        let profit = health.reduce(0) { $0 + $1.profitTTM }
        let profitable = health.filter { $0.profitTTM > 0 }.count
        let chains = engine.chainSummaries
        let franchisors = live.filter { engine.isFranchisor(companyID: $0.id) }
        let units = franchisors.reduce(0) { $0 + engine.franchiseSystem(companyID: $1.id)["units"].array.count }
        VStack(alignment: .leading, spacing: 12) {
            GroupAttention(engine: engine)

            GroupCard(padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Value of holdings").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                        Text(store.short(value)).font(.serifTitle(30)).foregroundStyle(Theme.ivory).lineLimit(1).minimumScaleFactor(0.6)
                        if let c = change, abs(c.amount) >= 1 {
                            Text("\(c.amount >= 0 ? "▲" : "▼") \(store.short(abs(c.amount))) 30 days").font(.system(size: 12)).foregroundStyle(c.amount >= 0 ? Theme.gain : Theme.loss)
                        } else {
                            Text("No change yet").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(Theme.divider).frame(width: 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Profit, 12 months").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                        Text(store.short(profit)).font(.serifTitle(30)).foregroundStyle(profit < 0 ? Theme.loss : Theme.ivory).lineLimit(1).minimumScaleFactor(0.6)
                        Text(live.isEmpty ? "No companies yet" : "\(profitable) of \(live.count) profitable").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    }
                    .padding(.leading, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                GroupCaps(text: "Structure", link: "View all ›", action: goStructure)
                HStack(spacing: 8) {
                    tile("Companies", live.count, "M5 21 V4 H15 V21 M15 9 H19 V21 M3 21 H21")
                    tile("Chains", chains.count, "M12 5 L5 18 H19 Z M12 5 V12")
                    tile("Franchises", units, "M4 9 L6 4 H18 L20 9 M5 9 V20 H19 V9")
                    tile("Holdings", engine.holdingCompanies.count, "M4 8 C4 5 20 5 20 8 C20 11 4 11 4 8 M4 8 V16 C4 19 20 19 20 16 V8")
                }
            }

            money

            activity(live)
        }
    }

    private func tile(_ label: String, _ n: Int, _ icon: String) -> some View {
        Button { Haptics.tap(); goStructure() } label: {
            VStack(spacing: 3) {
                GlyphView(glyph: icon, size: 18, weight: 1.5)
                Text("\(n)").font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.ivory)
                Text(label).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(n)")
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
    @ViewBuilder private func activity(_ live: [Company]) -> some View {
        let rows = live.compactMap { c in engine.lastDividendDecision(companyID: c.id).map { (co: c, d: $0) } }.sorted { $0.d.week > $1.d.week }
        VStack(alignment: .leading, spacing: 6) {
            GroupCaps(text: "Latest activity")
            if rows.isEmpty {
                Text("Dividend decisions and group tax show here once your companies make profit.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
            }
            ForEach(rows.prefix(3), id: \.co.id) { r in
                NavigationLink(value: CompanyRoute.companyAt(r.co.id, .finances)) {
                    CardRow(glyph: Glyph.reports, title: "Dividend reviewed: \(r.co.name)",
                            subtitle: r.d.paid > 0 ? "Last quarter · paid \(store.short(r.d.paid, in: r.co))" : "Last quarter · skipped",
                            value: "")
                }.buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Structure (GroupB)

struct GroupStructureTab: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var openMore: (GroupMorePage) -> Void

    var body: some View {
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

    private struct Waiting: Identifiable {
        var id: String { key + "#\(meeting.id)" }
        var key: String
        var meeting: ManagerModel.BoardMeeting
    }

    private var waiting: [Waiting] {
        engine.boardKeys.filter { engine.boardIsActive(key: $0) }.flatMap { k in
            engine.boardMeetings(key: k).filter { $0.status.isEmpty }.map { Waiting(key: k, meeting: $0) }
        }
    }

    var body: some View {
        let keys = engine.boardKeys.filter { engine.boardIsActive(key: $0) }
        let live = engine.state.companies.filter { $0.status.isLive && $0.type != "hold" }
        let list = waiting
        VStack(alignment: .leading, spacing: 12) {
            if let first = list.first {
                decision(first, more: list.count - 1)
            } else {
                GroupCard {
                    VStack(alignment: .leading, spacing: 4) {
                        GroupCaps(text: "Decisions")
                        Text(keys.isEmpty ? "A board forms once you register a chain or somebody else owns part of a company."
                                          : "Nothing waits for a board.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                GroupCaps(text: "Board seats", link: keys.count > 1 ? "All boards ›" : "", action: { openMore(.boards) })
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
                        Text("Seat someone ›").font(.system(size: 13)).foregroundStyle(Theme.gold)
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

    /// The first decision that waits. Emergencies and anything with several parts open the board; a single item can be decided here.
    private func decision(_ w: Waiting, more: Int) -> some View {
        let m = w.meeting
        let open = m.items.filter { $0.status.isEmpty }
        return GroupCard(strong: true) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("DECISION NEEDED").font(.system(size: 10.5, weight: .medium)).tracking(1.4).foregroundStyle(Theme.gold)
                    Spacer()
                    if more > 0 { Text("+\(more) more").font(.system(size: 12)).foregroundStyle(Theme.caution) }
                }
                Text("\(m.title) · \(engine.boardName(key: w.key))".tidyMoney).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory)
                if !m.why.isEmpty { Text(m.why.tidyMoney).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) }
                if !m.isEmergency, open.count == 1, let it = open.first {
                    Text(it.text.tidyMoney).font(.system(size: 12.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        decideButton("Decline", filled: false) {
                            let r = store.act { $0.decideMeetingItem(key: w.key, meetingID: m.id, item: it.id, approve: false) }
                            if case .gone? = r { store.show("That item is no longer on the agenda.", tone: "warn") } else { store.show("Declined.") }
                        }
                        decideButton("Approve ›", filled: true) {
                            let r = store.act { $0.decideMeetingItem(key: w.key, meetingID: m.id, item: it.id, approve: true) }
                            switch r {
                            case .followUp(let what)?: Haptics.success(); store.show("Approved. Follow up on it (\(what)) in the company.", tone: "good")
                            case .done(let what)?: Haptics.success(); store.show(what.isEmpty ? "Approved." : what, tone: "good")
                            case .gone?: store.show("That item is no longer on the agenda.", tone: "warn")
                            default: store.show("Approved.", tone: "good")
                            }
                        }
                    }.padding(.top, 2)
                } else {
                    NavigationLink { BoardView(key: w.key) } label: {
                        Text("Open the board ›").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gold)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.gold, lineWidth: 1))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).padding(.top, 2)
                }
            }
        }
    }

    private func decideButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Text(title).font(.system(size: 13, weight: filled ? .medium : .regular)).foregroundStyle(filled ? Theme.gold : Theme.ivory)
                .frame(maxWidth: .infinity, minHeight: 40)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(filled ? Theme.gold : Theme.borderStrong, lineWidth: 1))
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
                ForEach(GroupMorePage.allCases.filter { $0 != page }) { p in
                    Button { Haptics.tap(); pick(p) } label: { CardRow(glyph: p.glyph, title: p.rawValue, subtitle: p.sub) }.buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        }
    }
}
