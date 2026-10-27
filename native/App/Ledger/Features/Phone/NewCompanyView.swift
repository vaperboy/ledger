import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Simulation

/// New company, step 1 of 3: choose the trade. A sharp table (trade, start-up, demand, staff) under sector tabs; the engine's
/// `tradePickerRows` supply every figure and the reason a trade cannot be started. Other ways in (holding, franchise, abroad, club)
/// stay below the table.
struct NewCompanyView: View {
    @EnvironmentObject var store: GameStore
    @State private var sector = "All"
    @State private var cityID = ""
    @State private var selectedID: String?
    @State private var rows: [TradePickerRow] = []
    @State private var goNext = false

    private let columns: [TableColumn] = [
        TableColumn(title: "Trade"), TableColumn(title: "Start-up", width: 74),
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
                    otherWays(e)
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
            Text(rows.isEmpty ? "No trades are on offer here." : "No trade in this group.")
                .font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint).frame(maxWidth: .infinity, alignment: .leading)
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
        let tap: (() -> Void)? = choosable ? { selectedID = r.tradeID } : nil
        let opacity: Double = choosable ? 1 : 0.55
        TableRow(columns: columns, title: r.name, note: note, values: [cost, r.demand.rawValue, staff], valueTints: tints,
                 selected: r.tradeID == selectedID, action: tap)
            .opacity(opacity)
    }

    /// Why a trade cannot be picked: the engine's own refusal, or how much more money it needs.
    private func reason(_ e: GameEngine, _ r: TradePickerRow) -> String? {
        if let b = r.blocked { return b }
        guard let c = r.startUpCost else { return "Cannot be priced here." }
        if !r.isFunded {
            let short: Double = max(0, c - Payments.liquid(e.state))
            return "Needs \(store.money(short)) more than you have"
        }
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

    @ViewBuilder private func otherWays(_ e: GameEngine) -> some View {
        let hasOpen: Bool = e.state.companies.contains(where: { $0.status == .open && $0.type != "hold" })
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Other ways in").capsLabel().padding(.top, Theme.Space.s)
            NavigationLink { NewHoldingView() } label: {
                CardRow(glyph: Glyph.richList, title: "Holding company", subtitle: "Owns your other companies; dividends into it are taxed far lower")
            }.buttonStyle(.plain)
            NavigationLink { FranchisesView() } label: {
                CardRow(glyph: Glyph.market, title: "Join a franchise", subtitle: "A known brand, their rules and a fee")
            }.buttonStyle(.plain)
            if hasOpen {
                NavigationLink { ExpandAbroadView() } label: {
                    CardRow(glyph: Glyph.world, title: "Expand abroad", subtitle: "A subsidiary of one of your companies in another country")
                }.buttonStyle(.plain)
            }
            NavigationLink { ClubMarketView() } label: {
                CardRow(glyph: Glyph.group, title: "Football club", subtitle: "Buy a club in a top league, or found one")
            }.buttonStyle(.plain)
        }
    }

    private func bottomBar(_ picked: TradePickerRow?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Selected").font(.system(size: 10.5)).tracking(1).textCase(.uppercase).foregroundStyle(Theme.ivoryFaint)
                if let p = picked {
                    let from: String = p.startUpCost.map { store.money($0) } ?? ""
                    Text("\(p.name) · from \(from)").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                } else {
                    Text("Pick a trade above").font(.system(size: 14)).foregroundStyle(Theme.ivoryMuted)
                }
            }
            Spacer(minLength: 8)
            QuietButton(title: "Continue ›") { if picked != nil { goNext = true } }
                .opacity(picked == nil ? 0.4 : 1).disabled(picked == nil)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(Theme.page)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}
