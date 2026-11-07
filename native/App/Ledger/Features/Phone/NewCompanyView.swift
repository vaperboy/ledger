import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Simulation

/// New company, step 1 of 3: choose the trade (step 2 is the company, step 3 the review and payment). What you can spend leads, then one row
/// per trade (name, why or what, start-up cost, demand and team) under sector tabs; the engine's
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

    var body: some View {
        if let e = store.engine {
            let city: String = cityID.isEmpty ? e.state.player.cityID : cityID
            let sectors: [String] = ["All"] + orderedSectors(rows)
            let shown: [TradePickerRow] = sector == "All" ? rows : rows.filter { $0.sector == sector }
            let picked: TradePickerRow? = rows.first { $0.tradeID == selectedID }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    cityLine(e, city)
                    SectionTabs(items: sectors, primary: Array(sectors.prefix(5)), title: { $0 }, selection: $sector)
                        .padding(.horizontal, -Theme.Space.margin)
                    table(e, shown)
                    Text("Start-up costs are exact. Demand is for this city; results depend on price, place and management.")
                        .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.l).padding(.bottom, 20)
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

    /// What the player can spend leads; the city the trades are priced for sits under it as a menu.
    @ViewBuilder private func cityLine(_ e: GameEngine, _ city: String) -> some View {
        let cities: [Country.City] = e.homeCountry.cities
        let name: String = cities.first { $0.id == city }?.name ?? "Home city"
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            MoneyHero(label: "You can spend", value: store.money(Payments.liquid(e.state)))
            Menu {
                ForEach(cities) { c in Button(c.name) { cityID = c.id; selectedID = nil } }
            } label: {
                HStack(spacing: 4) {
                    Text("Priced for").textStyle(.caption)
                    Text(name).textStyle(.caption, tint: Theme.accent, weight: .medium)
                    Image(systemName: "chevron.down").textStyle(.caption, tint: Theme.accent, weight: .semibold)
                }
                .frame(minHeight: 32).contentShape(Rectangle())
            }
            .accessibilityLabel("Priced for \(name)")
        }
    }

    @ViewBuilder private func table(_ e: GameEngine, _ shown: [TradePickerRow]) -> some View {
        if shown.isEmpty {
            EmptyState(glyph: Glyph.market, title: rows.isEmpty ? "No trades are on offer here." : "No trade in this group.",
                       message: rows.isEmpty ? "Try another city." : "Pick another sector above.")
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { (n: Int, r: TradePickerRow) in
                    if n > 0 { Hairline() }
                    row(e, r)
                }
            }
        }
    }

    /// One trade: name and why (or what it is), the start-up cost and the city's demand with the usual team. The chosen one is washed in accent.
    @ViewBuilder private func row(_ e: GameEngine, _ r: TradePickerRow) -> some View {
        let choosable: Bool = isChoosable(r)
        let blurb: String = e.data.catalog[r.tradeID]?.blurb ?? ""
        let note: String = reason(e, r) ?? blurb
        let cost: String = r.startUpCost.map { store.money($0) } ?? "n/a"
        let staff: String = r.staffMin == r.staffMax ? "\(r.staffMax)" : "\(r.staffMin)-\(r.staffMax)"
        let trade: String = r.tradeID, tradeName: String = r.name
        let open: Bool = TradeAccess.isUnlocked(tradeID: trade, startUpCost: r.startUpCost, medianWage: e.homeCountry.medianMonthlyWage, entitlements: ent.effective, now: Date())
        let selected: Bool = r.tradeID == selectedID
        Button {
            Haptics.choose()
            if open { selectedID = trade } else { ent.run(.tradeAboveCostLine, "Open a " + tradeName.lowercased()) {} }
        } label: {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(selected ? Theme.accent : Theme.lineStrong)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(r.name.tidyText).textStyle(.headline).lineLimit(1)
                    Text(note.tidyText).textStyle(.caption, tint: choosable ? Theme.inkSoft : Theme.warn).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: Theme.Space.s)
                VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                    Text(cost.tidyText).textStyle(.headline, tint: choosable ? Theme.ink : Theme.inkFaint, numeric: true).lineLimit(1).minimumScaleFactor(0.7)
                    Text("\(r.demand.rawValue) demand \u{00B7} \(staff) staff").textStyle(.caption, tint: demandTint(r.demand, choosable)).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .padding(.vertical, Theme.Space.m).padding(.horizontal, Theme.Space.s)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(selected ? Theme.accentWash : Color.clear))
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(AcctPressStyle())
        .disabled(!choosable)
        .opacity(choosable ? 1 : 0.6)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
