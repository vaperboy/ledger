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
        if s == .overview {
            FixedScreen(spacing: Theme.Space.l, top: Theme.Space.l, minScale: 0.7) { content(e, s) }
                .environment(\.insideCard, true)
        } else {
            ScrollScreen(spacing: Theme.Space.xl, top: Theme.Space.l) { content(e, s) }
                .environment(\.insideCard, true)
        }
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
                    Text(entity.kind + " \u{00B7} Group view").textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                CompanyCustomiseButton(companyID: entity.companyID)
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
        case .overview:
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                GroupEntityOverview(engine: e, entity: entity)
                Text("Group view: ownership, people, board and money. Day-to-day running is in the company itself.")
                    .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                GroupEntityActions(entity: entity)
            }
        case .management: GroupEntityManagement(engine: e, entity: entity)
        case .board: GroupBoardroom(engine: e, entity: entity)
        case .money:
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                GroupEntityMoney(engine: e, entity: entity)
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("Owners and sales").textStyle(.label, tint: Theme.inkFaint)
                    GroupEntityOwnership(engine: e, entity: entity)
                }
            }
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
        static let moneyLabels: Set<String> = ["Profit", "Revenue"]
    }

    var body: some View {
        let cos: [Company] = entity.members.compactMap { (id: Int) -> Company? in engine.state.company(id) }.filter { (c: Company) -> Bool in c.status.isLive }
        let list: [Stat] = stats(cos)
        let money: [Stat] = list.filter { (s: Stat) -> Bool in Stat.moneyLabels.contains(s.label) }
        let facts: [Stat] = list.filter { (s: Stat) -> Bool in !Stat.moneyLabels.contains(s.label) }
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            FigureRow(items: money.map { (s: Stat) -> KeyFigures.Item in KeyFigures.Item(label: s.label, value: s.value, tint: s.tint, sub: "this month") }, columns: 3, size: .figure, combineCells: true)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.m), GridItem(.flexible(), spacing: Theme.Space.m)], alignment: .leading, spacing: Theme.Space.m) {
                ForEach(facts) { (s: Stat) in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.label).textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
                        Text(s.value).textStyle(.body, tint: s.tint, weight: .medium).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func stats(_ cos: [Company]) -> [Stat] {
        var staff: Int = 0
        var open: Int = 0
        var franchised: Int = 0
        var revenue: Double = 0
        var profit: Double = 0
        var franchisors: Int = 0
        for c in cos {
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
        out.append(Stat(label: entity.isChain ? "Stores open" : "Open", value: entity.isChain ? "\(open) of \(cos.count)" : (open > 0 ? "Yes" : "Closed")))
        out.append(Stat(label: "Franchised out", value: franchised == 0 ? "None" : "\(franchised) \(franchised == 1 ? "franchisee" : "franchisees")"))
        out.append(Stat(label: "Employees", value: "\(staff)"))
        out.append(Stat(label: "Profit", value: store.short(profit), tint: Theme.change(profit)))
        out.append(Stat(label: "Revenue", value: store.short(revenue)))
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
}

struct GroupEntityActions: View {
    @EnvironmentObject var store: GameStore
    var entity: GroupEntity
    @State private var grow = false

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Button { Haptics.tap(); grow = true } label: { Text("Grow") }
                .buttonStyle(SecondaryButtonStyle(size: .compact, tint: Theme.accent))
                .accessibilityIdentifier("group-grow")
            Button { Haptics.tap(); store.openCompany(entity.companyID) } label: { Text("Open company") }
                .buttonStyle(SecondaryButtonStyle(size: .compact))
                .accessibilityIdentifier("group-open-company")
            Spacer(minLength: 0)
        }
        .navigationDestination(isPresented: $grow) { GroupGrowScreen(entity: entity) }
    }
}

struct GroupGrowScreen: View {
    @EnvironmentObject var store: GameStore
    var entity: GroupEntity

    var body: some View {
        SettingsPage(title: "Grow", subtitle: entity.name) {
            if let e = store.engine {
                EntityExpansionView(companyID: entity.companyID)
                TradeAssociationRows(engine: e, entity: entity)
            }
        }
    }
}
