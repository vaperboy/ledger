import Foundation
import GameCore
import Countries
import Finance
import Businesses

public struct ItemPageData: Equatable, Sendable {
    public var item: SalesItem
    public var record: ItemModels.Record?
    public var modelLabel: String
    public var unitCost: Double
    public var live: ItemModels.LiveProfit
    public var fairValue: Double
    public var saleProbability: Double
    public var supply: ItemModels.SupplyLine?
    public var offers: [ItemModels.SupplyLine]
    public var statusWord: String
}

public extension GameEngine {
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
                            offers: ItemModels.offers(state, companyID: companyID, itemID: itemID, data: data), statusWord: word)
    }

    @discardableResult
    mutating func setItemSupplier(companyID: Int, itemID: String, vendorID: String?) -> SettingResult {
        let data = self.data
        return applySetting(refuse: { s in
            if let why = SalesItems.refusal(s, companyID: companyID, itemID: itemID, data: data) { return why }
            guard ItemModels.needsSupplier(s, companyID: companyID, itemID: itemID, data: data) else { return "This item needs no supplier." }
            return ItemModels.pickRefusal(s, companyID: companyID, itemID: itemID, vendorID: vendorID, data: data)
        }, probe: { $0.companySnapshot(companyID) }) { s, d, _ in
            ItemModels.migrateItem(&s, companyID: companyID, itemID: itemID, data: d)
            ItemModels.pick(&s, companyID: companyID, itemID: itemID, vendorID: vendorID, data: d)
            Tutorial.advance(&s, from: .pickSupplier)
        }
    }

    func itemMonthlyNeed(companyID: Int, itemID: String) -> Int { ItemModels.monthlyNeed(state, companyID: companyID, itemID: itemID, data: data) }
    func itemRepickWeeksLeft(companyID: Int, itemID: String) -> Int { ItemModels.repickWeeksLeft(state, companyID: companyID, itemID: itemID) }
    func itemCancelFee(companyID: Int, itemID: String) -> Double { ItemModels.cancelFee(state, companyID: companyID, itemID: itemID) }

    @discardableResult
    mutating func cancelItemSupplier(companyID: Int, itemID: String, bySupplier: Bool = false) -> SettingResult {
        let data = self.data
        var why: String?
        let r = applySetting(refuse: { s in
            if let w = SalesItems.refusal(s, companyID: companyID, itemID: itemID, data: data) { return w }
            guard s.company(companyID).flatMap({ ItemModels.record($0, itemID: itemID) })?.supplierID != nil else { return "There is no supplier to end." }
            return nil
        }, probe: { $0.companySnapshot(companyID) }) { s, d, _ in
            why = ItemModels.cancel(&s, companyID: companyID, itemID: itemID, bySupplier: bySupplier, data: d)
        }
        if let why { return .refused(why) }
        return r
    }

    @discardableResult
    mutating func removeFakePlayers() -> Int {
        var n = 0
        update { s, _, _ in n = Suppliers.removeFakes(&s) }
        return n
    }

    mutating func setRealSuppliers(count: Int) {
        guard Suppliers.realSuppliers(state) != max(0, count) else { return }
        update { s, _, _ in Suppliers.setRealSuppliers(&s, count: count) }
    }

    var fakePlayersRemoved: Bool { Suppliers.fakesOff(state) }
}
