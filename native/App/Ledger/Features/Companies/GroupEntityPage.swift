import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct GroupEntityPage: View {
    @EnvironmentObject var store: GameStore
    var entity: GroupEntity
    @Binding var section: GroupSection
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.xs)
            if let e = store.engine {
                let shown: [GroupSection] = visibleSections(e)
                GroupSectionBar(tab: $section, badges: badges(e), sections: shown)
                    .padding(.top, Theme.Space.s)
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
        ScrollScreen(spacing: Theme.Space.xl, top: Theme.Space.l) { content(e, s) }
            .environment(\.insideCard, true)
    }

    private func visibleSections(_ e: GameEngine) -> [GroupSection] { GroupSection.allCases }

    private func badges(_ e: GameEngine) -> [GroupSection: Int] {
        guard let key = e.boardKey(companyID: entity.companyID) else { return [:] }
        let n: Int = e.boardOpenDecisions(key: key)
        return n > 0 ? [.board: n] : [:]
    }

    private var header: some View {
        let ch = GroupFmt.change(entity, store)
        let trend: [Double] = Array(entity.trend.suffix(90))
        var amount: String = ""
        if entity.hasChange && abs(entity.changeAmount) >= 1 { amount = (entity.changeAmount >= 0 ? "+" : "\u{2212}") + store.short(abs(entity.changeAmount)) }
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .center, spacing: Theme.Space.xs) {
                Button { Haptics.tap(); onBack() } label: {
                    LedgerGlyph(glyph: Glyph.back, size: Theme.Icon.medium, tint: Theme.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .padding(.leading, -Theme.Space.m)
                .accessibilityLabel("Back to Group")
                .accessibilityIdentifier("group-back")
                VStack(alignment: .leading, spacing: 0) {
                    Text(entity.name).textStyle(.headline).lineLimit(1)
                    Text(entity.kind).textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            HStack(alignment: .bottom, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    LiveFigure(value: entity.value, text: store.short(entity.value)).textStyle(.display, numeric: true)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text(amount.isEmpty ? ch.text : ch.text + "  " + amount).textStyle(.caption, tint: ch.tint, numeric: true).lineLimit(1)
                        if entity.hasChange { Text("in 30 days").textStyle(.caption, tint: Theme.inkFaint).lineLimit(1) }
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: Theme.Space.s)
                if trend.count >= 2 {
                    Sparkline(values: trend, tint: (trend.last ?? 0) >= (trend.first ?? 0) ? Theme.accent : Theme.loss, filled: false)
                        .frame(width: 96, height: 36)
                        .padding(.bottom, Theme.Space.xs)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ s: GroupSection) -> some View {
        switch s {
        case .overview: GroupEntityOverview(engine: e, entity: entity)
        case .management: GroupEntityManagement(engine: e, entity: entity)
        case .board: GroupBoardroom(engine: e, entity: entity)
        case .expansion:
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                EntityExpansionView(companyID: entity.companyID)
                GroupBuyRows(engine: e, entity: entity)
                TradeAssociationRows(engine: e, entity: entity)
            }
        case .money: GroupEntityMoney(engine: e, entity: entity)
        case .deals: GroupEntityOwnership(engine: e, entity: entity)
        }
    }
}

struct GroupEntityOverview: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var entity: GroupEntity

    private struct Stat: Identifiable {
        var id: String { label }
        var label: String
        var value: String
        var tint: Color = Theme.ivory
        static let moneyLabels: Set<String> = ["Profit", "Revenue", "Cash"]
    }

    var body: some View {
        let cos: [Company] = entity.members.compactMap { (id: Int) -> Company? in engine.state.company(id) }.filter { (c: Company) -> Bool in c.status.isLive }
        let list: [Stat] = stats(cos)
        let money: [Stat] = list.filter { (s: Stat) -> Bool in Stat.moneyLabels.contains(s.label) }
        let facts: [Stat] = list.filter { (s: Stat) -> Bool in !Stat.moneyLabels.contains(s.label) }
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            FigureRow(items: money.map { (s: Stat) -> KeyFigures.Item in KeyFigures.Item(label: s.label, value: s.value, tint: s.tint, sub: s.label == "Cash" ? "today" : "this month") }, columns: 3, size: .figure, combineCells: true)
            VStack(spacing: Theme.Space.s) {
                ForEach(Array(facts.enumerated()), id: \.element.id) { (n: Int, s: Stat) in
                    if n > 0 { Hairline() }
                    ValueRow(label: s.label, value: s.value, tint: s.tint)
                        .accessibilityElement(children: .combine)
                }
            }
            if entity.isHolding { subsidiaries }
        }
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
        out.append(Stat(label: "Profit", value: store.short(profit), tint: Theme.change(profit)))
        out.append(Stat(label: "Revenue", value: store.short(revenue)))
        out.append(Stat(label: "Cash", value: store.short(cash), tint: cash < 0 ? Theme.loss : Theme.ivory))
        let brand: Double = engine.brandValue(companyID: entity.companyID)
        out.append(Stat(label: "Brand", value: BrandWords.label(score: brand)))
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

    @ViewBuilder private var subsidiaries: some View {
        let subs: [Company] = entity.members.dropFirst().compactMap { (id: Int) -> Company? in engine.state.company(id) }
        if !subs.isEmpty {
            LedgerSection("Under this holding") {
                VStack(spacing: 0) {
                    ForEach(Array(subs.enumerated()), id: \.element.id) { (n: Int, c: Company) in
                        if n > 0 { Hairline() }
                        LedgerRow(leading: .glyph(Glyph.home), title: c.name, subtitle: "\(engine.tradeName(c)) \u{00B7} \(engine.cityName(c))",
                                  value: store.short(Valuation.companyValue(c, state: engine.state, trades: engine.data.catalog), in: c))
                    }
                }
            }
        }
    }
}
