import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Sales & Market of one company, on ONE page: a table with one row per decision. Pricing opens the one Pricing screen; How you sell is a
/// popup (its choices and what they cost); Marketing opens its campaigns; "New menu item" (named for the trade) only for trades that
/// have development written for them. Customers are in Stats, the Market is a Phone app, and Projects are a part of this section only
/// for project businesses (`CompanyDetailView`).
struct CompanySales: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Binding var part: OpsPart
    @State private var showSell = false

    var body: some View {
        OverviewSettingsCard(heading: "Sales and market") {
            pricingRow
            sellRow
            marketingRow
            developRow
        }
        .sheet(isPresented: $showSell) { HowYouSellSheet(companyID: company.id) }
        .navigationDestination(isPresented: Binding(get: { part != .setup }, set: { if !$0 { part = .setup } })) {
            OpsPageDestination(part: part, companyID: company.id)
        }
    }

    // MARK: Pricing

    private var pricingRow: some View {
        let moves: PriceMovesInfo? = engine.priceMoves(company)
        let against: Double = moves?.againstMarket ?? 0
        let value: String = moves == nil ? "Not selling yet" : (abs(against) < 0.005 ? "At the market" : Currency.percent(against, decimals: 0) + (against > 0 ? " above" : " below"))
        return SettingsTableRow(title: "Pricing", value: value, glyph: Glyph.opsPrice) {
            store.openCompany(company.id, section: .pricing)
        }
    }

    // MARK: How you sell (a popup)

    @ViewBuilder private var sellRow: some View {
        let trade: Trade? = engine.tradeInfo(companyID: company.id)
        let hasKnobs: Bool = !(trade?.knobs.isEmpty ?? true)
        let hasWays: Bool = engine.waysToSell(companyID: company.id).contains { $0.canSwitch }
        if hasKnobs || hasWays {
            SettingsTableRow(title: "How you sell", value: sellSummary(trade), opens: .sheet, glyph: Glyph.opsRoute) { showSell = true }
                .accessibilityIdentifier("sales-how-you-sell")
        }
    }

    /// The company's current choice for each of its "how you sell" knobs, in one line.
    private func sellSummary(_ trade: Trade?) -> String {
        guard let trade else { return "Set" }
        let names: [String] = trade.knobs.compactMap { (knob: Knob) -> String? in
            let v: JSONValue = company.value("knob")[knob.id]
            let i: Int = v.isNull ? knob.defaultIndex : v.int
            return knob.options.indices.contains(i) ? knob.options[i].name : nil
        }
        return names.isEmpty ? "Set" : names.joined(separator: ", ")
    }

    // MARK: Marketing

    private var marketingRow: some View {
        let cur: Currency = engine.currency(for: company)
        let spend: Double = company.value("mkt").object.values.reduce(0) { $0 + $1["b"].double }
        return SettingsTableRow(title: "Marketing", value: spend > 0 ? cur.tidyShort(spend) + " a week" : "No campaigns", glyph: Glyph.opsMega) { part = .marketing }
    }

    // MARK: Development, named for the trade

    @ViewBuilder private var developRow: some View {
        if CompanyDevelopment.isAvailable(company, engine) {
            let run = Development.running(company)
            let left: Int = max(0, (run?.weeksLeft ?? 0) - engine.state.week)
            SettingsTableRow(title: CompanyDevelopment.title(company, engine), value: run == nil ? "Start one" : "\(left.weeksText) to go",
                             valueTint: run == nil ? Theme.ivory : Theme.caution, glyph: Glyph.opsBox) { part = .develop }
        }
    }
}
