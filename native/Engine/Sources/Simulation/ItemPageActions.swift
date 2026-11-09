import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Everything the item page shows, in one read (`ItemModels`). Money is in accounting units.
public struct ItemPageData: Equatable, Sendable {
    public var item: SalesItem
    /// nil for an old titles-only item: the page then shows what exists and no stock blocks.
    public var record: ItemModels.Record?
    public var modelLabel: String
    /// Cost of one unit now (a record's own, or the trade's cost-of-sales share for an old item).
    public var unitCost: Double
    public var live: ItemModels.LiveProfit
    public var fairValue: Double
    /// Weekly chance one interested customer buys at the price shown.
    public var saleProbability: Double
    public var supply: ItemModels.SupplyLine?
    public var offers: [ItemModels.SupplyLine]
    /// One word for the list: "In stock 12", "Being fixed", "Reserved", "Selling", "Sold out".
    public var statusWord: String
}

public extension GameEngine {
    /// The page of one item at a proposed price (nil price = the item's own price, after no discount).
    func itemPage(companyID: Int, itemID: String, price: Double? = nil) -> ItemPageData? {
        guard let it = salesItems(companyID: companyID).first(where: { $0.id == itemID }), let co = state.company(companyID) else { return nil }
        let p = price ?? it.price
        guard let live = ItemModels.liveProfit(state, companyID: companyID, itemID: itemID, price: p, data: data) else { return nil }
        let rec = ItemModels.record(co, itemID: itemID)
        let fair = (rec?.fair ?? 0) > 0 ? rec!.fair : it.marketPrice
        let word = ItemModels.statusWord(rec, it)
        return ItemPageData(item: it, record: rec, modelLabel: rec?.model.label ?? (it.isService ? "Service" : "Product"), unitCost: live.cost, live: live,
                            fairValue: fair, saleProbability: ItemModels.saleProbability(price: p, fair: fair),
                            supply: rec == nil ? nil : ItemModels.supply(state, companyID: companyID, itemID: itemID, data: data),
                            offers: rec == nil ? [] : ItemModels.offers(state, companyID: companyID, itemID: itemID, data: data), statusWord: word)
    }

    /// Choose which supplier supplies one item (a record is needed; an old titles-only item has none).
    @discardableResult
    mutating func setItemSupplier(companyID: Int, itemID: String, vendorID: String?) -> SettingResult {
        let data = self.data
        return applySetting(refuse: { s in
            if let why = SalesItems.refusal(s, companyID: companyID, itemID: itemID, data: data) { return why }
            guard let co = s.company(companyID), ItemModels.record(co, itemID: itemID) != nil else { return "This item has no stock to supply." }
            return nil
        }, probe: { $0.companySnapshot(companyID) }) { s, _, _ in
            ItemModels.setSupplier(&s, companyID: companyID, itemID: itemID, vendorID: vendorID)
            Tutorial.advance(&s, from: .pickSupplier)
        }
    }
}
