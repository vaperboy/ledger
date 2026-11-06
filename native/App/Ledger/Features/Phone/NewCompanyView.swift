import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Simulation

/// New company, step 1 of 3: choose the trade (step 2 is the company, step 3 the review and payment). A sharp table (trade, start-up, demand, staff) under sector tabs; the engine's
/// `tradePickerRows` supply every figure and the reason a trade cannot be started. Holding, franchise, abroad and club moved to
/// Group (Add to group, and Expansion on a company's page).
struct NewCompanyView: View {
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @State private var sector = "All"
    @State private var cityID = ""
    @State private var selectedID: String?
    @State private var rows: [TradePickerRow] = []
    @State private var goNext = false

    private let columns: [TableColumn] = [
        TableColumn(title: "Trade"), TableColumn(title: "Advised", width: 74),
        TableColumn(title: "Demand", width: 58), TableColumn(title: "Staff", width: 38)
    ]

    var body: some View {
        if let e = store.engine {
            let city: String = cityID.isEmpty ? e.state.player.cityID : cityID
            let sectors: [String] = ["All"] + orderedSectors(rows)
            let shown: [TradePickerRow] = sector == "All" ? rows : rows.filter { $0.sector == sector }
            let picked: TradePickerRow? = rows.first { $0.tradeID == selectedID }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    cityLine(e, city)
                    SectionTabs(items: sectors, primary: Array(sectors.prefix(5)), title: { $0 }, selection: $sector)
                        .padding(.horizontal, -Theme.Space.margin)
                    table(e, shown)
                    Text("Demand is for this city; staff is the usual team size. Start-up costs are exact; the rest is an estimate and your result depends on price, location and management.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 20)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(picked) }
            .appScreen(title: "New company", subtitle: "Step 1 of 3 · choose the trade", tab: .company)
            .navigationDestination(isPresented: $goNext) {
                if let id = selectedID { NewCompanySetupView(tradeID: id, cityID: city) }
            }
            .task(id: city + "|\(Int(Payments.liquid(e.state)))") {
                rows = e.tradePickerRows(cityID: city)
                if let s = selectedID, !(rows.first { $0.tradeID == s }.map(isChoosable) ?? false) { selectedID = nil }
            }
        }
    }

    private func isChoosable(_ r: TradePickerRow) -> Bool { r.blocked == nil && r.isFunded && r.startUpCost != nil }

    private func orderedSectors(_ rows: [TradePickerRow]) -> [String] {
        var seen: [String] = []
        for r in rows where !seen.contains(r.sector) { seen.append(r.sector) }
        return seen
    }

    // MARK: Pieces

    @ViewBuilder private func cityLine(_ e: GameEngine, _ city: String) -> some View {
        let cities: [Country.City] = e.homeCountry.cities
        let name: String = cities.first { $0.id == city }?.name ?? "Home city"
        HStack {
            Text("Priced for").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
            Menu {
                ForEach(cities) { c in Button(c.name) { cityID = c.id; selectedID = nil } }
            } label: {
                HStack(spacing: 4) {
                    Text(name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.gold)
                }
            }
            Spacer()
            Text("You have \(store.money(Payments.liquid(e.state)))").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
        }
    }

    @ViewBuilder private func table(_ e: GameEngine, _ shown: [TradePickerRow]) -> some View {
        if shown.isEmpty {
            EmptyState(glyph: Glyph.market, title: rows.isEmpty ? "No trades are on offer here." : "No trade in this group.",
                       message: rows.isEmpty ? "Try another city." : "Pick another sector above.")
        } else {
            SharpTable {
                TableHeader(columns: columns)
                ForEach(shown) { r in row(e, r) }
            }
        }
    }

    @ViewBuilder private func row(_ e: GameEngine, _ r: TradePickerRow) -> some View {
        let choosable: Bool = isChoosable(r)
        let blurb: String = e.data.catalog[r.tradeID]?.blurb ?? ""
        let note: String = reason(e, r) ?? blurb
        let cost: String = r.startUpCost.map { store.money($0) } ?? "n/a"
        let staff: String = r.staffMin == r.staffMax ? "\(r.staffMax)" : "\(r.staffMin)-\(r.staffMax)"
        let costTint: Color = choosable ? Theme.ivory : Theme.ivoryFaint
        let tints: [Color] = [costTint, demandTint(r.demand, choosable), Theme.ivoryMuted]
        let trade: String = r.tradeID, tradeName: String = r.name
        let open: Bool = TradeAccess.isUnlocked(tradeID: trade, startUpCost: r.startUpCost, medianWage: e.homeCountry.medianMonthlyWage, entitlements: ent.effective, now: Date())
        let tap: (() -> Void)? = choosable ? { if open { selectedID = trade } else { ent.run(.tradeAboveCostLine, "Open a " + tradeName.lowercased()) {} } } : nil
        let opacity: Double = choosable ? 1 : 0.55
        TableRow(columns: columns, title: r.name, note: note, values: [cost, r.demand.rawValue, staff], valueTints: tints,
                 selected: r.tradeID == selectedID, action: tap)
            .opacity(opacity)
            .overlay(alignment: .topTrailing) { if !open && choosable { ProMark(feature: .tradeAboveCostLine).padding(.trailing, 4).padding(.top, 2) } }
    }

    /// Why a trade cannot be picked: the engine's own refusal, or how much more money it needs.
    private func reason(_ e: GameEngine, _ r: TradePickerRow) -> String? {
        if let b = r.blocked { return b }
        guard let c = r.startUpCost else { return "Cannot be priced here." }
        if !r.isFunded {
            let short: Double = max(0, (r.minimumCost ?? c) - Payments.liquid(e.state))
            return "Needs \(store.money(short)) more than you have to start"
        }
        if Payments.liquid(e.state) < c { return "Recommended \(store.money(c)); you can start with less" }
        return nil
    }

    private func demandTint(_ d: DemandLevel, _ on: Bool) -> Color {
        if !on { return Theme.ivoryFaint }
        switch d {
        case .high: return Theme.gain
        case .medium: return Theme.caution
        case .low: return Theme.loss
        }
    }

    /// Step 1's one action; it says why it waits until a trade is picked.
    private func bottomBar(_ picked: TradePickerRow?) -> some View {
        NewCompanyStepBar(title: picked.map { "Continue · \($0.name)" } ?? "Continue", blockedReason: picked == nil ? "Pick a trade above." : nil) { goNext = true }
    }
}
