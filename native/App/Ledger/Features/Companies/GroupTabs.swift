import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

// The Group tab has four tabs: Overview, Structure, People, Suppliers (GroupHome.swift); each company, holding and chain is managed on its own page (GroupEntityPage.swift and
// the GroupEntity*.swift files). Every figure comes from the engine.

/// The tabs of an entity page. `key` is the name other screens use to ask for one (`GameStore.openGroupEntity(companyID:section:)`).
enum GroupSection: String, CaseIterable, Hashable {
    case overview = "Overview", management = "Management", board = "Boardroom", money = "Money", expansion = "Grow", deals = "Owners and sales"
    /// Stays the same when a tab is retitled, so links that name a tab keep working.
    var key: String {
        switch self {
        case .overview: return "overview"
        case .management: return "management"
        case .board: return "boardroom"
        case .money: return "money"
        case .expansion: return "expansion"
        case .deals: return "ownership"
        }
    }
}

/// Text tabs with a champagne underline, for the Group tab and for an entity page. When all titles fit at their natural size they share
/// the width equally; on a narrow phone or with larger text the row scrolls sideways and keeps the chosen tab in view.
struct GroupSectionBar<Tab: Hashable & RawRepresentable>: View where Tab.RawValue == String {
    @Binding var tab: Tab
    var badges: [Tab: Int] = [:]
    var sections: [Tab]
    /// Each tab's accessibility identifier is this prefix and its title.
    var idPrefix: String = "group-tab-"
    /// Tabs a tour points at.
    var anchors: [Tab: CoachStop] = [:]
    @Environment(\.outsidePalette) private var P

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) { cells(equal: true) }.padding(.horizontal, Theme.Space.page)
            ScrollViewReader { (reader: ScrollViewProxy) in
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Space.xs) { cells(equal: false) }
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, Theme.Space.page, for: .scrollContent)
                // The strip fades out at both edges, so a tab cut by the edge reads as "more this way", not as clipped text.
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                             .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                                     startPoint: .leading, endPoint: .trailing))
                .onAppear { reader.scrollTo(tab, anchor: .center) }
                .onChange(of: tab) { _, now in Motion.animate(Motion.quickAnimation) { reader.scrollTo(now, anchor: .center) } }
            }
        }
        .background(alignment: .bottom) { Hairline() }
    }

    private func cells(equal: Bool) -> some View {
        ForEach(sections, id: \.self) { (t: Tab) in
            Button { tab = t; Haptics.choose() } label: { cell(t.rawValue, on: tab == t, badge: badges[t] ?? 0, equal: equal) }
                .buttonStyle(PressableStyle())
                .coachAnchor(anchors[t] ?? .groupStructure, enabled: anchors[t] != nil)
                .accessibilityAddTraits(tab == t ? [.isButton, .isSelected] : [.isButton])
                .accessibilityIdentifier(idPrefix + t.rawValue)
                .id(t)
        }
    }

    private func cell(_ text: String, on: Bool, badge: Int, equal: Bool) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Text(text).textStyle(.body, tint: on ? P.accent : P.inkFaint, weight: on ? .semibold : .regular)
                .lineLimit(1).fixedSize()
            RedBubble(count: badge, size: .small)
        }
        .padding(.horizontal, equal ? Theme.Space.xs : Theme.Space.m)
        .frame(maxWidth: equal ? .infinity : nil, minHeight: 44)
        .overlay(alignment: .bottom) { if on { Rectangle().fill(P.accent).frame(height: 1.5) } }
        .contentShape(Rectangle())
    }
}

// MARK: - The entities

/// One line of the picker: a company, a holding or a whole chain (a chain is ONE entry). `companyID` is the company the entity page works
/// on (a chain: its first store); `members` are the companies the entity covers (a holding: itself and everything under it).
struct GroupEntity: Identifiable, Equatable {
    var id: String
    var companyID: Int
    var chainID: Int?
    var name: String
    var kind: String
    var isHolding: Bool
    var indent: Bool
    var value: Double
    var hasChange: Bool
    var changeAmount: Double
    var changeShare: Double?
    var members: [Int]
    /// Profit this month of the companies it covers (a holding: itself and everything under it).
    var profit: Double = 0
    /// Its value per day, oldest first (the sum of its companies' histories, aligned on today), for the trend line.
    var trend: [Double] = []
    var isChain: Bool { chainID != nil }
}

enum GroupEntities {
    /// The change of a sum of companies over `days`: the amounts add up, the share is against what they were worth before.
    /// `hist` is the decoded history when the caller has it (decoding it per company was the slow part of building the list).
    static func change(_ e: GameEngine, ids: [Int], values: [Int: Double], days: Int, hist: DayHistory? = nil) -> (amount: Double, share: Double?)? {
        let h: DayHistory = hist ?? e.dayHistory
        var amount: Double = 0
        var earlier: Double = 0
        var any = false
        for id in ids {
            guard let c = DayHistory.change(h.perCompany[id] ?? [], days: days) else { continue }
            any = true
            amount += c.amount
            earlier += (values[id] ?? 0) - c.amount
        }
        if !any { return nil }
        return (amount, earlier > 1 ? amount / earlier : nil)
    }

    private static func make(_ e: GameEngine, id: String, companyID: Int, chainID: Int?, name: String, kind: String, isHolding: Bool, indent: Bool, ids: [Int], members: [Int], values: [Int: Double], days: Int, hist: DayHistory) -> GroupEntity {
        var total: Double = 0
        for i in ids { total += values[i] ?? 0 }
        let ch = change(e, ids: ids, values: values, days: days, hist: hist)
        var profit: Double = 0
        for i in ids { profit += e.financeOverview(companyID: i).monthProfit }
        return GroupEntity(id: id, companyID: companyID, chainID: chainID, name: name, kind: kind, isHolding: isHolding, indent: indent, value: total,
                           hasChange: ch != nil, changeAmount: ch?.amount ?? 0, changeShare: ch?.share, members: members,
                           profit: profit, trend: series(hist, ids: ids))
    }

    /// The summed daily values of `ids`, aligned on the last day (a company with a shorter history adds from its first day on).
    static func series(_ h: DayHistory, ids: [Int]) -> [Double] {
        let all: [[Double]] = ids.compactMap { (i: Int) -> [Double]? in h.perCompany[i] }
        let n: Int = all.map { (s: [Double]) -> Int in s.count }.max() ?? 0
        guard n >= 2 else { return [] }
        var out: [Double] = Array(repeating: 0, count: n)
        for s in all {
            let off: Int = n - s.count
            for (k, v) in s.enumerated() { out[off + k] += v }
        }
        return out
    }

    /// Everything the picker lists, biggest first; a holding is followed by its companies, indented.
    static func build(_ e: GameEngine, days: Int = 30) -> [GroupEntity] {
        let st: GameState = e.state
        let hist: DayHistory = e.dayHistory
        let live: [Company] = st.companies.filter { (c: Company) -> Bool in c.status.isLive }
        var values: [Int: Double] = [:]
        for c in live { values[c.id] = Valuation.companyValue(c, state: st, trades: e.data.catalog) }
        let chains: [Chains.Summary] = e.chainSummaries
        var inChain = Set<Int>()
        for ch in chains { for s in ch.stores { inChain.insert(s.id) } }
        let holdings: [Company] = live.filter { (c: Company) -> Bool in c.type == "hold" }
        let holdingIDs: Set<Int> = Set(holdings.map { (h: Company) -> Int in h.id })
        var top: [GroupEntity] = []
        var subsOf: [Int: [GroupEntity]] = [:]
        for ch in chains {
            let ids: [Int] = ch.stores.filter { (s: Chains.StoreLine) -> Bool in s.status.isLive }.map { (s: Chains.StoreLine) -> Int in s.id }
            guard let first = ids.first else { continue }
            let kind: String = "Chain \u{00B7} \(ids.count) \(ids.count == 1 ? "store" : "stores")"
            top.append(make(e, id: "ch\(ch.id)", companyID: first, chainID: ch.id, name: ch.name, kind: kind, isHolding: false, indent: false, ids: ids, members: ids, values: values, days: days, hist: hist))
        }
        for c in live where c.type != "hold" && !inChain.contains(c.id) {
            let franchisee: Bool = !c.value("franchise").isNull
            let kind: String = (franchisee ? "Franchise \u{00B7} " : "") + "\(e.tradeName(c)) \u{00B7} \(e.cityName(c))"
            let ent = make(e, id: "co\(c.id)", companyID: c.id, chainID: nil, name: c.name, kind: kind, isHolding: false, indent: false, ids: [c.id], members: [c.id], values: values, days: days, hist: hist)
            if c.holdingID != 0 && holdingIDs.contains(c.holdingID) {
                var one = ent
                one.indent = true
                subsOf[c.holdingID, default: []].append(one)
            } else {
                top.append(ent)
            }
        }
        for h in holdings {
            let subs: [GroupEntity] = subsOf[h.id] ?? []
            let kind: String = "Holding company \u{00B7} \(subs.count) \(subs.count == 1 ? "company" : "companies")"
            var members: [Int] = [h.id]
            for s in subs { members.append(s.companyID) }
            var ent = make(e, id: "co\(h.id)", companyID: h.id, chainID: nil, name: h.name, kind: kind, isHolding: true, indent: false, ids: [h.id], members: members, values: values, days: days, hist: hist)
            var sum: Double = ent.value
            var profit: Double = ent.profit
            for s in subs { sum += s.value; profit += s.profit }
            ent.value = sum
            ent.profit = profit
            ent.trend = series(hist, ids: members)
            top.append(ent)
        }
        top.sort { (a: GroupEntity, b: GroupEntity) -> Bool in a.value > b.value }
        var out: [GroupEntity] = []
        for t in top {
            out.append(t)
            if t.isHolding {
                let subs: [GroupEntity] = (subsOf[t.companyID] ?? []).sorted { (a: GroupEntity, b: GroupEntity) -> Bool in a.value > b.value }
                out.append(contentsOf: subs)
            }
        }
        return out
    }

    /// `build` for the store's engine, once per engine change (the Group landing and page both read it on every render).
    @MainActor static func cached(_ store: GameStore) -> [GroupEntity]? { store.memo("groupEntities") { build($0) } }

    /// The entity a request for a company lands on: its own entry, else the chain or holding it belongs to.
    static func find(_ list: [GroupEntity], companyID: Int) -> GroupEntity? {
        if let own = list.first(where: { (g: GroupEntity) -> Bool in g.companyID == companyID }) { return own }
        return list.first(where: { (g: GroupEntity) -> Bool in g.members.contains(companyID) })
    }
}

/// A change as an arrow with a share (or an amount when the earlier value was too small for a share), coloured by direction.
@MainActor
enum GroupFmt {
    static func change(_ amount: Double, _ share: Double?, has: Bool, _ store: GameStore) -> (text: String, tint: Color) {
        guard has else { return ("No history yet", Theme.ivoryMuted) }
        guard abs(amount) >= 1 else { return ("No change", Theme.ivoryMuted) }
        let up: Bool = amount >= 0
        let size: String
        if let share {
            size = String(format: "%.0f%%", abs(share) * 100)
        } else {
            size = store.short(abs(amount))
        }
        return ("\(up ? "\u{25B2}" : "\u{25BC}") \(size)", up ? Theme.gain : Theme.loss)
    }

    static func change(_ g: GroupEntity, _ store: GameStore) -> (text: String, tint: Color) {
        change(g.changeAmount, g.changeShare, has: g.hasChange, store)
    }
}
