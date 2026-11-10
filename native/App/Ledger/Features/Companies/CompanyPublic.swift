import SwiftUI
import GameCore
import Countries
import Businesses
import Events
import Simulation

struct PublicCompanyCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var policyOpen = false

    var body: some View {
        let cur: Currency = engine.currency(for: company)
        let row: ExchangeRow? = engine.exchangeMarket.first { (r: ExchangeRow) -> Bool in r.id == PublicExchange.id(of: company.id) }
        let chosen: String = engine.dividendPolicy(companyID: company.id)
        let outside: Double = Shareholders.outside(company)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("On the stock exchange \u{00B7} \(company.name)").textStyle(.label, tint: Theme.inkFaint)
            if let row {
                FigureRow(items: [
                    KeyFigures.Item(label: "Share price", value: cur.tidyDisplay(row.close), tint: Theme.change(row.change), sub: change(row.change)),
                    KeyFigures.Item(label: "You own", value: "\(Int(saturating: company.ownership.rounded()))%", sub: company.ownership > PublicRules.controlAbove ? "you keep control" : "control is shared"),
                    KeyFigures.Item(label: "Public owns", value: "\(Int(saturating: outside.rounded()))%", sub: "anyone can buy"),
                ], columns: 3, size: .figure, combineCells: true)
                Text(row.note).textStyle(.caption, tint: Theme.inkSoft)
            }
            Text("Every quarter the company publishes its results. A good quarter lifts the price, a bad one pushes it down.").textStyle(.caption, tint: Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            SharpTable {
                SettingsTableRow(title: "Dividend", value: Shareholders.policyNames[chosen] ?? chosen, opens: .sheet) { policyOpen = true }
            }
            Text("The board decides on the dividend once a quarter, right after the results, and pays it to every shareholder by the share they own. You cannot take money out at other times.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            Text("While the shares are public, closing the company, selling its equipment or property, and taking a very large loan need a vote of all shareholders, so they are not possible.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
        .centerSheet(isPresented: $policyOpen) { DividendPolicySheet(companyID: company.id).environmentObject(store) }
    }

    private func change(_ c: Double) -> String {
        let pct: Double = (c * 1000).rounded() / 10
        return (pct >= 0 ? "+" : "\u{2212}") + String(format: "%.1f", abs(pct)) + "% today"
    }
}
