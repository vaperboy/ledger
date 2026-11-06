import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

// The Group tab works like Banking: pressing it opens the picker of companies, holdings and chains; everything else is managed per
// entity on its own page (GroupEntityPage.swift and the GroupEntity*.swift files). Every figure comes from the engine.

/// The tabs of an entity page. `key` is the name other screens use to ask for one (`GroupRouteBox.Request.section`).
enum GroupSection: String, CaseIterable, Hashable {
    case overview = "Overview", management = "Management", board = "Boardroom", money = "Money", expansion = "Expansion", deals = "Ownership"
    var key: String { rawValue.lowercased() }
}

/// Text tabs with a champagne underline. When all six titles fit at their natural size they share the width equally; on a narrow
/// phone or with larger text the row scrolls sideways and keeps the chosen tab in view, so a title is never shrunk or clipped.
struct GroupSectionBar: View {
    @Binding var tab: GroupSection
    var badges: [GroupSection: Int] = [:]
    /// The tabs shown (all six: the Boardroom always exists, advisory until a co-owner joins).
    var sections: [GroupSection] = GroupSection.allCases
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
                .onAppear { reader.scrollTo(tab, anchor: .center) }
                .onChange(of: tab) { _, now in Motion.animate(Motion.quickAnimation) { reader.scrollTo(now, anchor: .center) } }
            }
        }
        .background(alignment: .bottom) { Hairline() }
    }

    private func cells(equal: Bool) -> some View {
        ForEach(sections, id: \.self) { (t: GroupSection) in
            Button { tab = t; Haptics.choose() } label: { cell(t.rawValue, on: tab == t, badge: badges[t] ?? 0, equal: equal) }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(tab == t ? [.isButton, .isSelected] : [.isButton])
                .accessibilityIdentifier("group-tab-\(t.rawValue)")
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

// MARK: - Landing

/// The Group landing, a holding company's private dashboard: the group's value with its 30-day change and trend, what waits for you,
/// then one row per company (value and this month's profit), who runs what, and the supplier directory.
struct GroupLanding: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var onPick: (GroupEntity, GroupSection) -> Void
    var onSuppliers: () -> Void
    @Environment(\.outsidePalette) private var P

    var body: some View {
        let list: [GroupEntity] = GroupEntities.cached(store) ?? GroupEntities.build(engine)
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            hero
            needsYou(list)
            companies(list)
            GroupWhoRunsWhat(engine: engine)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Network").textStyle(.label, tint: P.inkFaint)
                LedgerRow(leading: .glyph(Glyph.bank), title: "Suppliers", subtitle: "Every supplier your companies use",
                          identifier: "group-suppliers", action: onSuppliers)
            }
        }
    }

    // MARK: Hero

    /// The group's value is the one big number; its 30-day change, the cash inside the companies and the trend line sit under it.
    private var hero: some View {
        let value: Double = (store.netWorthNow ?? engine.netWorth).companies
        let hist: DayHistory = store.dayHistoryNow ?? engine.dayHistory
        let vc = DayHistory.change(hist.companies, days: 30)
        let vt = GroupFmt.change(vc?.amount ?? 0, vc?.share, has: vc != nil, store)
        var amount: String = ""
        if let c = vc { amount = (c.amount >= 0 ? "+" : "\u{2212}") + store.short(abs(c.amount)) }
        let trend: [Double] = Array(hist.companies.suffix(90))
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Group value").textStyle(.label, tint: P.inkFaint)
            LiveFigure(value: value, text: store.short(value)).textStyle(.display)
                .lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityLabel("Group value " + store.short(value))
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(vc == nil ? vt.text : vt.text + "  " + amount).textStyle(.caption, tint: vt.tint, numeric: true).lineLimit(1)
                Text("in 30 days").textStyle(.caption, tint: P.inkFaint).lineLimit(1)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            if trend.count >= 2 {
                Sparkline(values: trend, tint: (trend.last ?? 0) >= (trend.first ?? 0) ? Theme.accent : Theme.loss)
                    .frame(height: 44)
                    .padding(.top, Theme.Space.xs)
                    .accessibilityHidden(true)
            }
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text("Cash in the companies").textStyle(.caption, tint: P.inkFaint).lineLimit(1)
                LiveFigure(value: engine.groupCash, text: store.short(engine.groupCash)).textStyle(.caption, tint: P.ink, numeric: true).lineLimit(1)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .padding(.top, Theme.Space.xs)
            GroupBrandLine(engine: engine)
        }
    }

    // MARK: Needs you

    /// Board decisions that wait for you, one tappable tile per entity; nothing when the boards are quiet.
    @ViewBuilder private func needsYou(_ list: [GroupEntity]) -> some View {
        let waiting: [Waiting] = list.compactMap { (g: GroupEntity) -> Waiting? in
            let n: Int = boardWaiting(g)
            return n > 0 ? Waiting(entity: g, count: n) : nil
        }
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Needs you").textStyle(.label, tint: P.inkFaint)
                ForEach(waiting) { (w: Waiting) in
                    let g: GroupEntity = w.entity
                    let n: Int = w.count
                    Button { Haptics.tap(); onPick(g, .board) } label: {
                        HStack(spacing: Theme.Space.m) {
                            LedgerGlyph(glyph: Glyph.achievements, size: Theme.Icon.large, tint: P.accent)
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text("\(n) board \(n == 1 ? "decision" : "decisions") waiting").textStyle(.headline).lineLimit(2)
                                Text(g.name).textStyle(.caption).lineLimit(1)
                            }
                            Spacer(minLength: Theme.Space.s)
                            LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint)
                        }
                        .padding(Theme.Space.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(P.card))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("group-needs-\(g.id)")
                }
            }
        }
    }

    private struct Waiting: Identifiable {
        var entity: GroupEntity
        var count: Int
        var id: String { entity.id }
    }

    private func boardWaiting(_ g: GroupEntity) -> Int {
        guard !g.indent, let key = engine.boardKey(companyID: g.companyID), engine.boardIsActive(key: key) else { return 0 }
        return engine.boardOpenDecisions(key: key)
    }

    // MARK: Companies

    @ViewBuilder private func companies(_ list: [GroupEntity]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Companies").textStyle(.label, tint: P.inkFaint)
                Spacer(minLength: Theme.Space.s)
                if !list.isEmpty { Text("Value \u{00B7} profit this month").textStyle(.caption, tint: P.inkFaint).lineLimit(1) }
            }
            if list.isEmpty {
                EmptyState(glyph: Glyph.group, title: "No companies yet", message: "Start one with the plus above.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { (n: Int, g: GroupEntity) in
                        if n > 0 { Hairline().padding(.leading, (g.indent ? Theme.Space.xl : 0) + Theme.Icon.medium + Theme.Space.m) }
                        row(g)
                    }
                }
            }
        }
    }

    private func glyph(_ g: GroupEntity) -> String { g.isHolding ? Glyph.bank : (g.isChain ? Glyph.group : Glyph.home) }

    /// One company: name over its kind, value over this month's profit (gain or loss colour).
    private func row(_ g: GroupEntity) -> some View {
        let sign: String = g.profit > 0.5 ? "+" : (g.profit < -0.5 ? "\u{2212}" : "")
        return LedgerRow(leading: .glyph(glyph(g)), leadingTint: g.indent ? P.inkFaint : nil, title: g.name, subtitle: g.kind,
                         value: store.short(g.value), valueTint: g.value < 0 ? Theme.loss : nil,
                         valueNote: sign + store.short(abs(g.profit)), valueNoteTint: Theme.change(g.profit), badge: boardWaiting(g),
                         lineLimit: 1, identifier: "group-entity-\(g.id)", action: { onPick(g, .overview) })
            .padding(.leading, g.indent ? Theme.Space.xl : 0)
            .frame(minHeight: 60)
    }
}
