import Foundation
import GameCore
import Countries
import Finance
import Businesses

public extension GameEngine {
    func salesItems(companyID: Int) -> [SalesItem] {
        guard let co = state.company(companyID) else { return [] }
        if SalesItems.firstChoicePending(co) { return [] }
        let hidden = SalesItems.hiddenIDs(co)
        let rows = SalesItems.rows(state, companyID: companyID, data: data)
        return hidden.isEmpty ? rows : rows.filter { !hidden.contains($0.id) }
    }

    func needsFirstItemChoice(companyID: Int) -> Bool { state.company(companyID).map(SalesItems.firstChoicePending) ?? false }

    func firstItemChoices(companyID: Int) -> [SalesItem] {
        guard let co = state.company(companyID), SalesItems.firstChoicePending(co), let i = state.companyIndex(companyID),
              let bd = data.catalog[co.type] else { return [] }
        var seeded = state
        SalesItems.seedStarters(&seeded, i, data: data)
        let offered = Set(SalesItems.starterIDs(bd, SalesItems.items(seeded.companies[i], bd)))
        return SalesItems.rows(seeded, companyID: companyID, data: data).filter { offered.contains($0.id) }
    }

    func itemPriceRange(companyID: Int) -> ClosedRange<Double> {
        state.company(companyID).flatMap { data.catalog[$0.type] }.map { SalesItems.range(for: $0) } ?? SalesItems.priceRange
    }

    @discardableResult
    mutating func chooseFirstItem(companyID: Int, itemID: String) -> SettingResult {
        let data = self.data
        return applySetting(refuse: { s in
            guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return "That company no longer exists." }
            guard co.status == .open else { return "Only an open company sells things." }
            guard SalesItems.firstChoicePending(co), let i = s.companyIndex(companyID) else { return "You have already chosen what to sell." }
            var seeded = s
            SalesItems.seedStarters(&seeded, i, data: data)
            return SalesItems.starterIDs(bd, SalesItems.items(seeded.companies[i], bd)).contains(itemID) ? nil : "That choice is not on offer."
        }, probe: { $0.companySnapshot(companyID) }) { s, d, _ in
            SalesItems.settlePick(&s, companyID: companyID, keeping: itemID, data: d)
        }
    }

    func itemForecast(companyID: Int, itemID: String, price: Double, discountPercent: Double) -> ItemForecast {
        SalesItems.forecast(state, companyID: companyID, itemID: itemID, price: price, discountPercent: discountPercent, data: data)
    }

    func suggestedItemName(companyID: Int, isService: Bool) -> String {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return "" }
        return SalesItems.suggestedName(co, bd, isService: isService, seed: state.seed)
    }

    @discardableResult
    mutating func setItemPrice(companyID: Int, itemID: String, price: Double) -> SettingResult {
        let data = self.data
        let result = applySetting(refuse: { s in
            if let why = SalesItems.refusal(s, companyID: companyID, itemID: itemID, data: data) { return why }
            guard price.isFinite else { return "Enter a price." }
            let r = SalesItems.rows(s, companyID: companyID, data: data).first { $0.id == itemID }
            guard let m = r?.marketPrice, m > 0 else { return "That price is too far from the market price." }
            guard price >= m * SalesItems.priceFloor else { return "That price is too far below the market price." }
            let ceiling = s.company(companyID).flatMap { data.catalog[$0.type] }.map { SalesItems.ceiling(for: $0) } ?? SalesItems.priceCeiling
            guard price <= m * ceiling else { return "Customers will not pay that: the most this sells for is about \(Int(saturating: (ceiling * 100).rounded()))% of the market price." }
            return nil
        }, probe: { $0.companySnapshot(companyID) }) { s, d, _ in
            SalesItems.setPrice(&s, companyID: companyID, itemID: itemID, price: price, data: d)
            if let i = s.companyIndex(companyID) { s.companies[i].set("chose", 1) }
        }
        if !result.isRefused { tutorialAdvance(from: .setPrice) }
        return result
    }

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
            if percent > 0, let i = s.companyIndex(companyID) { s.companies[i].set("chose", 1) }
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
            let hidden = SalesItems.hiddenIDs(co)
            let list = SalesItems.items(co, bd).filter { !hidden.contains($0.id) }
            if list.count >= SalesItems.maxItems { return "That is as many items as one company can sell." }
            if list.contains(where: { $0.name.lowercased() == clean.lowercased() }) { return "There is already an item with that name." }
            return nil
        }, probe: { $0.companySnapshot(companyID) }) { s, d, _ in
            SalesItems.add(&s, companyID: companyID, name: clean, isService: isService, data: d)
        }
    }

    func newItemOptions(companyID: Int, isService: Bool) -> NewItemOptionList {
        NewItemOptions.list(state, companyID: companyID, isService: isService, data: data)
    }

    func hasMarketAdvisor(companyID: Int) -> Bool { state.company(companyID).map(NewItemOptions.hasAdvisor) ?? false }

    @discardableResult
    mutating func addNewItem(companyID: Int, optionID: String) -> SettingResult {
        let svc = optionID.hasPrefix("svc:")
        guard let o = NewItemOptions.list(state, companyID: companyID, isService: svc, data: data).options.first(where: { $0.id == optionID }) else {
            return .refused("That choice is no longer on offer.")
        }
        return addSalesItem(companyID: companyID, name: o.name, isService: o.isService)
    }

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
