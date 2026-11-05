import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// One entity of the Group picker (a company, a holding or a whole chain): a header with its value, the in-page tabs, and the tab's content,
/// everything scoped to exactly this entity.
struct GroupEntityPage: View {
    @EnvironmentObject var store: GameStore
    var entity: GroupEntity
    @Binding var section: GroupSection
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18).padding(.top, 6)
            if let e = store.engine {
                let shown: [GroupSection] = visibleSections(e)
                GroupSectionBar(tab: $section, badges: badges(e), sections: shown)
                    .padding(.horizontal, 18).padding(.top, 10)
                SegmentPager(items: shown, selection: $section) { (s: GroupSection) in
                    screen(e, s)
                }
                .id(entity.id)
                .onAppear { if !shown.contains(section) { section = .overview } }
                .onChange(of: shown) { _, now in if !now.contains(section) { section = .overview } }
            }
        }
    }

    @ViewBuilder private func screen(_ e: GameEngine, _ s: GroupSection) -> some View {
        if s == .money {
            FixedScreen(top: 12) { content(e, s) }
        } else {
            ScrollScreen(top: 12) { content(e, s) }
        }
    }

    /// Every tab, minus Board while nobody could sit on it. A board that exists always shows.
    private func visibleSections(_ e: GameEngine) -> [GroupSection] {
        let open: Bool = store.isUnlocked("board", companyID: entity.companyID)
        return GroupSection.allCases.filter { (s: GroupSection) -> Bool in s != .board || open }
    }

    private func badges(_ e: GameEngine) -> [GroupSection: Int] {
        guard let key = e.boardKey(companyID: entity.companyID), e.boardIsActive(key: key) else { return [:] }
        let n: Int = e.boardOpenDecisions(key: key)
        return n > 0 ? [.board: n] : [:]
    }

    private var header: some View {
        let ch = GroupFmt.change(entity, store)
        return HStack(spacing: 10) {
            Button { Haptics.tap(); onBack() } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.gold)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Back to Group")
            .accessibilityIdentifier("group-back")
            VStack(alignment: .leading, spacing: 1) {
                Text(entity.name).font(.serifTitle(24)).foregroundStyle(Theme.ivory).lineLimit(1).minimumScaleFactor(0.7)
                Text(entity.kind).font(.system(size: 12)).foregroundStyle(entity.isChain ? Theme.gold : Theme.ivoryMuted).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                LiveFigure(value: entity.value, text: store.short(entity.value)).font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1).minimumScaleFactor(0.7)
                Text(ch.text).font(.system(size: 11.5)).foregroundStyle(ch.tint).lineLimit(1)
            }
        }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ s: GroupSection) -> some View {
        switch s {
        case .overview: GroupEntityOverview(engine: e, entity: entity)
        case .management: GroupEntityManagement(engine: e, entity: entity)
        case .board: GroupEntityBoard(engine: e, entity: entity)
        case .expansion: EntityExpansionView(companyID: entity.companyID)
        case .money: GroupEntityMoney(engine: e, entity: entity)
        case .deals: GroupEntityDeals(engine: e, entity: entity)
        }
    }
}

// MARK: - Overview

/// The entity's own overview: stores open, franchised out, employees, revenue and profit this month, brand and the rest of its key figures,
/// plus the way into its staff (managers and executives are in the Management tab).
struct GroupEntityOverview: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var entity: GroupEntity

    private struct Stat: Identifiable {
        var id: String { label }
        var label: String
        var value: String
        var tint: Color = Theme.ivory
    }

    var body: some View {
        let cos: [Company] = entity.members.compactMap { (id: Int) -> Company? in engine.state.company(id) }.filter { (c: Company) -> Bool in c.status.isLive }
        VStack(alignment: .leading, spacing: 14) {
            Card(padding: 12, radius: Theme.Radius.hero) {
                VStack(spacing: 0) {
                    let list: [Stat] = stats(cos)
                    ForEach(Array(list.enumerated()), id: \.element.id) { (n: Int, s: Stat) in
                        HStack {
                            Text(s.label).font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted)
                            Spacer(minLength: 8)
                            Text(s.value).font(.system(size: 13.5, weight: .medium).monospacedDigit()).foregroundStyle(s.tint).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .top) { if n > 0 { Rectangle().fill(Theme.divider).frame(height: 1) } }
                    }
                }
            }
            if entity.isHolding { subsidiaries }
            Button { Haptics.tap(); store.openCompany(entity.companyID, section: .staff) } label: {
                CardRow(glyph: Glyph.team, title: "Staff", subtitle: "Workers, hiring, job ads and perks. Managers and executives are in Management")
            }.buttonStyle(PressableStyle()).accessibilityIdentifier("group-entity-team")
            Button { Haptics.tap(); openEntityCompany() } label: {
                CardRow(glyph: Glyph.home, title: entity.isChain ? "Open the flagship store" : "Open the company", subtitle: "Manage, sales, stats and the rest of its screens")
            }.buttonStyle(PressableStyle())
        }
    }

    private func openEntityCompany() {
        if entity.isHolding { store.openCompany(entity.companyID, section: CompanySection.holding) } else { store.openCompany(entity.companyID) }
    }

    private func stats(_ cos: [Company]) -> [Stat] {
        var cash: Double = 0
        var staff: Int = 0
        var open: Int = 0
        var franchised: Int = 0
        var revenue: Double = 0
        var profit: Double = 0
        var franchisors: Int = 0
        for c in cos {
            cash += c.cash
            staff += c.staff.count + (c.managerID != nil ? 1 : 0)
            if c.status == .open { open += 1 }
            if engine.isFranchisor(companyID: c.id) {
                franchisors += 1
                franchised += engine.franchiseSystem(companyID: c.id)["units"].array.count
            }
            let f = engine.financeOverview(companyID: c.id)
            revenue += f.monthRevenue
            profit += f.monthProfit
        }
        var out: [Stat] = []
        if entity.isHolding {
            out.append(Stat(label: "Companies under it", value: "\(max(0, cos.count - 1))"))
        } else {
            out.append(Stat(label: entity.isChain ? "Stores open" : "Open", value: entity.isChain ? "\(open) of \(cos.count)" : (open > 0 ? "Yes" : "Closed")))
            out.append(Stat(label: "Franchised out", value: franchised == 0 ? "None" : "\(franchised) \(franchised == 1 ? "franchisee" : "franchisees")"))
        }
        out.append(Stat(label: "Employees", value: "\(staff)"))
        out.append(Stat(label: "Revenue this month", value: store.short(revenue)))
        out.append(Stat(label: "Profit this month", value: store.short(profit), tint: profit < 0 ? Theme.loss : Theme.gain))
        out.append(Stat(label: "Cash", value: store.short(cash), tint: cash < 0 ? Theme.loss : Theme.ivory))
        let brand: Double = engine.brandValue(companyID: entity.companyID)
        out.append(Stat(label: "Brand", value: BrandWords.label(score: brand), tint: Theme.gold))
        if entity.isChain {
            out.append(Stat(label: "Stores in the chain", value: "\(cos.count)"))
            out.append(Stat(label: "Chain CEO", value: chainCEO()))
            out.append(Stat(label: "Franchise brands", value: franchisors == 0 ? "None" : "\(franchisors)"))
        }
        return out
    }

    private func chainCEO() -> String {
        guard let key = engine.boardKey(companyID: entity.companyID) else { return "None" }
        let v = engine.boardVoters(key: key).first(where: { (x: ManagerModel.Voter) -> Bool in x.type == "ceo" })
        return v?.name ?? "None"
    }

    /// A holding's companies, each opening its own page through the picker rows above; here they are listed with their value.
    @ViewBuilder private var subsidiaries: some View {
        let subs: [Company] = entity.members.dropFirst().compactMap { (id: Int) -> Company? in engine.state.company(id) }
        if !subs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("UNDER THIS HOLDING").capsLabel()
                ForEach(subs) { (c: Company) in
                    Button { Haptics.tap(); store.openCompany(c.id) } label: {
                        CardRow(glyph: Glyph.home, title: c.name, subtitle: "\(engine.tradeName(c)) \u{00B7} \(engine.cityName(c))", value: store.short(Valuation.companyValue(c, state: engine.state, trades: engine.data.catalog), in: c))
                    }.buttonStyle(PressableStyle())
                }
            }
        }
    }
}
