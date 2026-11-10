import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct CompanyInventorySection: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    var tradeID: String
    @State private var pending: PendingAction? = nil

    private var isDealer: Bool { tradeID == UsedCarDealer.tradeID }

    var body: some View {
        if let e = store.engine {
            let rows: [InventoryItem] = e.inventoryItems.filter { (i: InventoryItem) -> Bool in
                guard i.isFree else { return false }
                if isDealer { return e.inventoryStockProblem(itemID: i.id, companyID: companyID) == nil }
                return e.inventoryRepairOffers(itemID: i.id).contains { (o: InventoryRepairOffer) -> Bool in o.shopID == companyID }
            }
            if !rows.isEmpty {
                PageGroup(isDealer ? "From your inventory" : "Your inventory to repair") {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { (n: Int, i: InventoryItem) in
                        if n > 0 { RowRule(inset: 0) }
                        row(e, i)
                    }
                }
                .confirmAction($pending)
            }
        }
    }

    private func row(_ e: GameEngine, _ i: InventoryItem) -> some View {
        let offer: InventoryRepairOffer? = isDealer ? nil : e.inventoryRepairOffers(itemID: i.id).first { (o: InventoryRepairOffer) -> Bool in o.shopID == companyID }
        return HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(i.title.tidyText).textStyle(.headline).lineLimit(2)
                Text(MarketFormat.condition(i.cond) + " \u{00B7} worth " + store.short(i.value)).textStyle(.caption)
            }
            Spacer(minLength: Theme.Space.s)
            if isDealer {
                Button("Stock it") {
                    pending = PendingAction(title: "Stock in the dealership", message: "The company buys \(i.title) from you for \(store.short(i.paid)) and sells it to customers.", button: "Stock it", amount: i.paid) {
                        let r: SettingResult? = store.act { (g: inout GameEngine) -> SettingResult in g.stockInventoryItem(itemID: i.id, companyID: companyID) }
                        if let why = r?.reason { store.show(why, tone: "warn") } else { store.show("In the showroom.", tone: "good") }
                    }
                }
                .buttonStyle(SecondaryButtonStyle(size: .compact))
            } else if let o = offer {
                Button("Repair \(store.short(o.price))") {
                    pending = PendingAction(title: "Repair here", message: "Ready in \(o.weeks) weeks. It should be worth about \(store.short(o.valueGain)) more.", button: "Repair", amount: o.price) {
                        let r: SettingResult? = store.act { (g: inout GameEngine) -> SettingResult in g.startInventoryRepair(itemID: i.id, shopID: companyID) }
                        if let why = r?.reason { store.show(why, tone: "warn") }
                    }
                }
                .buttonStyle(SecondaryButtonStyle(size: .compact))
            }
        }
        .padding(.vertical, Theme.Space.m)
    }
}
