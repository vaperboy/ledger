import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

// The Group tab works like Banking: pressing it opens the picker of companies, holdings and chains; everything else is managed per
// entity on its own page (GroupEntityPage.swift and the GroupEntity*.swift files). Every figure comes from the engine.

/// The tabs of an entity page. `key` is the name other screens use to ask for one (`GroupRouteBox.Request.section`).
enum GroupSection: String, CaseIterable, Hashable {
    case overview = "Overview", board = "Board", dividends = "Dividends", expansion = "Expansion", money = "Money", deals = "Deals"
    var key: String { rawValue.lowercased() }
}

/// Text tabs with a champagne underline, equal widths, never scrolling sideways (six short titles fit 375 pt).
struct GroupSectionBar: View {
    @Binding var tab: GroupSection
    var badges: [GroupSection: Int] = [:]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(GroupSection.allCases, id: \.self) { (t: GroupSection) in
                Button { tab = t; Haptics.choose() } label: { cell(t.rawValue, on: tab == t, badge: badges[t] ?? 0) }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(tab == t ? [.isButton, .isSelected] : [.isButton])
                    .accessibilityIdentifier("group-tab-\(t.rawValue)")
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func cell(_ text: String, on: Bool, badge: Int) -> some View {
        HStack(spacing: 2) {
            Text(text).font(.system(size: 12.5, weight: on ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.8)
            RedBubble(count: badge, size: .small)
        }
        .foregroundStyle(on ? Theme.ivory : Theme.ivoryFaint)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
        .overlay(alignment: .bottom) { if on { Rectangle().fill(Theme.gold).frame(height: 2) } }
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
    var isChain: Bool { chainID != nil }
}

enum GroupEntities {
    /// The change of a sum of companies over `days`: the amounts add up, the share is against what they were worth before.
    static func change(_ e: GameEngine, ids: [Int], values: [Int: Double], days: Int) -> (amount: Double, share: Double?)? {
        var amount: Double = 0
        var earlier: Double = 0
        var any = false
        for id in ids {
            guard let c = e.companyValueChange(companyID: id, days: days) else { continue }
            any = true
            amount += c.amount
            earlier += (values[id] ?? 0) - c.amount
        }
        if !any { return nil }
        return (amount, earlier > 1 ? amount / earlier : nil)
    }

    private static func make(_ e: GameEngine, id: String, companyID: Int, chainID: Int?, name: String, kind: String, isHolding: Bool, indent: Bool, ids: [Int], members: [Int], values: [Int: Double], days: Int) -> GroupEntity {
        var total: Double = 0
        for i in ids { total += values[i] ?? 0 }
        let ch = change(e, ids: ids, values: values, days: days)
        return GroupEntity(id: id, companyID: companyID, chainID: chainID, name: name, kind: kind, isHolding: isHolding, indent: indent, value: total,
                           hasChange: ch != nil, changeAmount: ch?.amount ?? 0, changeShare: ch?.share, members: members)
    }

    /// Everything the picker lists, biggest first; a holding is followed by its companies, indented.
    static func build(_ e: GameEngine, days: Int = 30) -> [GroupEntity] {
        let st: GameState = e.state
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
            top.append(make(e, id: "ch\(ch.id)", companyID: first, chainID: ch.id, name: ch.name, kind: kind, isHolding: false, indent: false, ids: ids, members: ids, values: values, days: days))
        }
        for c in live where c.type != "hold" && !inChain.contains(c.id) {
            let franchisee: Bool = !c.value("franchise").isNull
            let kind: String = (franchisee ? "Franchise \u{00B7} " : "") + "\(e.tradeName(c)) \u{00B7} \(e.cityName(c))"
            let ent = make(e, id: "co\(c.id)", companyID: c.id, chainID: nil, name: c.name, kind: kind, isHolding: false, indent: false, ids: [c.id], members: [c.id], values: values, days: days)
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
            var ent = make(e, id: "co\(h.id)", companyID: h.id, chainID: nil, name: h.name, kind: kind, isHolding: true, indent: false, ids: [h.id], members: members, values: values, days: days)
            var sum: Double = ent.value
            for s in subs { sum += s.value }
            ent.value = sum
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

/// The Group landing: an Overview of the whole group, then one compact row per entity, then Suppliers.
struct GroupLanding: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var onPick: (GroupEntity) -> Void
    var onSuppliers: () -> Void
    var onNewHolding: () -> Void

    var body: some View {
        let list: [GroupEntity] = GroupEntities.build(engine)
        VStack(alignment: .leading, spacing: 14) {
            overview
            VStack(alignment: .leading, spacing: 8) {
                Text("COMPANIES AND CHAINS").capsLabel()
                if list.isEmpty {
                    Text("Start a company from Home to build a group.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                } else {
                    Card(padding: 4, radius: Theme.Radius.hero) {
                        VStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { (n: Int, g: GroupEntity) in
                                row(g, first: n == 0)
                            }
                        }
                    }
                }
            }
            Button { Haptics.tap(); onSuppliers() } label: {
                CardRow(glyph: Glyph.bank, title: "Suppliers", subtitle: "Every supplier your companies use, with profiles")
            }.buttonStyle(PressableStyle()).accessibilityIdentifier("group-suppliers")
            Button { Haptics.tap(); onNewHolding() } label: {
                HStack {
                    Text("Set up a holding company").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                    Spacer()
                    Text("Set one up \u{203A}").font(.system(size: 12.5)).foregroundStyle(Theme.gold)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .contentShape(Rectangle())
            }.buttonStyle(PressableStyle()).accessibilityIdentifier("group-new-holding")
        }
    }

    // MARK: Overview header

    private var overview: some View {
        let value: Double = engine.netWorth.companies
        let vc = DayHistory.change(engine.dayHistory.companies, days: 30)
        let cc = engine.groupCashChange(days: 30)
        let vt = GroupFmt.change(vc?.amount ?? 0, vc?.share, has: vc != nil, store)
        let ct = GroupFmt.change(cc?.amount ?? 0, cc?.share, has: cc != nil, store)
        return Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                Text("OVERVIEW").capsLabel()
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Group value").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                        LiveFigure(value: value, text: store.short(value)).font(.serifTitle(30)).foregroundStyle(Theme.ivory).lineLimit(1).minimumScaleFactor(0.6)
                        Text(vt.text + " in 30 days").font(.system(size: 11.5)).foregroundStyle(vt.tint).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Group cash").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                        LiveFigure(value: engine.groupCash, text: store.short(engine.groupCash)).font(.system(size: 20, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1).minimumScaleFactor(0.7)
                        Text(ct.text).font(.system(size: 11.5)).foregroundStyle(ct.tint).lineLimit(1)
                    }
                }
                NetWorthChart(engine: engine, days: 90, height: 44)
                GroupBrandLine(engine: engine)
            }
        }
    }

    // MARK: Picker rows

    private func glyph(_ g: GroupEntity) -> String { g.isHolding ? Glyph.bank : (g.isChain ? Glyph.group : Glyph.home) }

    private func row(_ g: GroupEntity, first: Bool) -> some View {
        let ch = GroupFmt.change(g, store)
        let key: String = engine.boardKey(companyID: g.companyID) ?? ""
        let waiting: Int = (!key.isEmpty && engine.boardIsActive(key: key)) ? engine.boardOpenDecisions(key: key) : 0
        return Button { Haptics.tap(); onPick(g) } label: {
            HStack(spacing: 10) {
                IconCircle(glyph: glyph(g), size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(g.name).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                    Text(g.kind).font(.system(size: 11.5)).foregroundStyle(g.isChain ? Theme.gold : Theme.ivoryFaint).lineLimit(1)
                }
                Spacer(minLength: 6)
                RedBubble(count: waiting, size: .small)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(store.short(g.value)).font(.system(size: 14.5, weight: .medium).monospacedDigit()).foregroundStyle(g.value < 0 ? Theme.loss : Theme.ivory).lineLimit(1)
                    Text(ch.text).font(.system(size: 11.5)).foregroundStyle(ch.tint).lineLimit(1)
                }
                GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim)
            }
            .padding(.leading, g.indent ? 26 : 10).padding(.trailing, 10).padding(.vertical, 9)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { if !first { Rectangle().fill(Theme.divider).frame(height: 1) } }
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("group-entity-\(g.id)")
    }
}
