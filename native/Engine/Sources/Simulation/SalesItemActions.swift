import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Per-item prices, discounts, company-specific items and selling to your other companies (`SalesItems`, `OwnListings`).
/// Prices are in accounting units, like `Pricing.ticket`.
public extension GameEngine {
    func salesItems(companyID: Int) -> [SalesItem] { SalesItems.rows(state, companyID: companyID, data: data) }

    /// Pure: units, revenue and profit change per week for a price (and discount percent) on one item.
    func itemForecast(companyID: Int, itemID: String, price: Double, discountPercent: Double) -> ItemForecast {
        SalesItems.forecast(state, companyID: companyID, itemID: itemID, price: price, discountPercent: discountPercent, data: data)
    }

    /// A free-name suggestion for a new product or service, made from the company name and trade.
    func suggestedItemName(companyID: Int, isService: Bool) -> String {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return "" }
        return SalesItems.suggestedName(co, bd, isService: isService, seed: state.seed)
    }

    /// Any real number is kept as typed; the price must lie between 30% and 300% of the market price.
    @discardableResult
    mutating func setItemPrice(companyID: Int, itemID: String, price: Double) -> SettingResult {
        let data = self.data
        return applySetting(refuse: { s in
            if let why = SalesItems.refusal(s, companyID: companyID, itemID: itemID, data: data) { return why }
            guard price.isFinite else { return "Enter a price." }
            let r = SalesItems.rows(s, companyID: companyID, data: data).first { $0.id == itemID }
            guard let m = r?.marketPrice, m > 0, price >= m * SalesItems.ratioRange.lowerBound, price <= m * SalesItems.ratioRange.upperBound else { return "That price is too far from the market price." }
            return nil
        }, probe: { $0.companySnapshot(companyID) }) { s, d, _ in
            SalesItems.setPrice(&s, companyID: companyID, itemID: itemID, price: price, data: d)
        }
    }

    /// A discount of `percent` for `weeks` weeks (0 percent ends it). Deepest allowed is the trade's own limit.
    @discardableResult
    mutating func setItemDiscount(companyID: Int, itemID: String, percent: Double, weeks: Int) -> SettingResult {
        let data = self.data
        return applySetting(refuse: { s in
            if let why = SalesItems.refusal(s, companyID: companyID, itemID: itemID, data: data) { return why }
            guard percent.isFinite, percent >= 0 else { return "A discount cannot be negative." }
            if percent > 0 {
                let deepest = Double(PriceMoves.maxDiscount(s.company(companyID)?.type ?? ""))
                guard deepest > 0 else { return "This trade does not discount." }
                guard percent <= deepest else { return "This trade does not discount deeper than \(Int(deepest))%." }
                guard (1...26).contains(weeks) else { return "A discount runs 1 to 26 weeks." }
            }
            return nil
        }, probe: { $0.companySnapshot(companyID) }) { s, d, _ in
            SalesItems.setDiscount(&s, companyID: companyID, itemID: itemID, percent: percent, weeks: weeks, data: d)
        }
    }

    @discardableResult
    mutating func addSalesItem(companyID: Int, name: String, isService: Bool) -> SettingResult {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = self.data
        return applySetting(refuse: { s in
            if let why = SalesItems.refusal(s, companyID: companyID, itemID: nil, data: data) { return why }
            guard !clean.isEmpty, clean.count <= 40 else { return "Give it a name of up to 40 letters." }
            guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return nil }
            let list = SalesItems.items(co, bd)
            if list.count >= SalesItems.maxItems { return "That is as many items as one company can sell." }
            if list.contains(where: { $0.name.lowercased() == clean.lowercased() }) { return "There is already an item with that name." }
            return nil
        }, probe: { $0.companySnapshot(companyID) }) { s, d, _ in
            SalesItems.add(&s, companyID: companyID, name: clean, isService: isService, data: d)
        }
    }

    /// Offer an item to your other companies (or stop).
    @discardableResult
    mutating func setItemListedForGroup(companyID: Int, itemID: String, listed: Bool) -> SettingResult {
        let data = self.data
        return applySetting(refuse: { SalesItems.refusal($0, companyID: companyID, itemID: itemID, data: data) }, probe: { $0.companySnapshot(companyID) }) { s, d, _ in
            SalesItems.setListed(&s, companyID: companyID, itemID: itemID, listed: listed, data: d)
        }
    }

    func ownCompanyListings(forBuyer companyID: Int) -> [OwnListing] { OwnListings.listings(state, buyer: companyID, data: data) }

    @discardableResult
    mutating func buyFromOwnCompany(buyer: Int, seller: Int, itemID: String, quantity: Int) -> SettingResult {
        var why: String?
        let before = state.company(buyer)?.cash
        update { s, d, _ in why = OwnListings.buy(&s, buyer: buyer, seller: seller, itemID: itemID, quantity: quantity, data: d) }
        if let why { return .refused(why) }
        return state.company(buyer)?.cash == before ? .unchanged : .applied
    }
}
