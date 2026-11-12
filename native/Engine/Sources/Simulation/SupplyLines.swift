import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum SupplyChange: Equatable, Sendable {
    case catalogue(line: String, offer: String)
    case input(String, SupplierSwitch)
}

// One company that can supply a line: a player company (another player's, or your own).
public struct SupplyOfferRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var detail: String
    public var quality: String
    public var reliability: String
    public var trust: Double?
    public var source: String
    public var lead: String
    public var weekly: Double?
    public var weeklyVsNow: Double?
    public var isCurrent: Bool
    public var blocked: String?
    public var change: SupplyChange
    public var owner: String = ""
    public var ownerCode: String = ""
    public var logoID: String = ""
    public var tradeID: String = ""
    public var city: String = ""
    public var size: String = ""
    public var staff: Int = 0
    public var weeksTrading: Int = 0
    public var priceLevel: String = ""
    public var free: Int?
    public var fit: SupplyFit = .fine
    public var isOwn: Bool = false
}

public struct SupplyRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var group: String
    public var title: String
    public var kind: String
    public var scale: String
    public var current: String
    public var quality: String
    public var reliability: String
    public var weekly: Double?
    public var weeklyBefore: Double?
    public var note: String?
    public var governed: String?
    public var offers: [SupplyOfferRow]
    public var need: Int = 1
    public var input: String? = nil
    public var canSwitch: Bool { offers.contains { !$0.isCurrent && $0.blocked == nil } }
    public var now: SupplyOfferRow? { offers.first { $0.isCurrent } }
}

public enum SupplyAsk: Equatable, Sendable {
    case item
    case line(String)
}

public struct SupplyGroup: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var rows: [SupplyRow]
}

public extension GameEngine {
    // Only the lines this company needs, in the four groups of the supply map.
    func supplyLines(companyID: Int) -> [SupplyGroup] {
        guard let co = state.company(companyID), co.status.isLive, let bd = data.catalog[co.type], !SalesItems.firstChoicePending(co) else { return [] }
        let inputs = supplierInputs(companyID: companyID)
        let sold = salesItems(companyID: companyID)
        let sellsProducts = sold.isEmpty || sold.contains { !$0.isService }
        var rows: [SupplyRow] = []
        var used = Set<String>()
        for line in SupplyCatalogue.lines(co, bd) where !line.automatic && (line.input != "goods" || sellsProducts) {
            let input = line.input.flatMap { id in inputs.first { $0.id == id } }
            let own = inputs.first { $0.id == line.id && $0.id != line.input }
            if let i = input { used.insert(i.id) }
            if let o = own { used.insert(o.id) }
            rows.append(supplyRow(co, bd, line, input, own))
        }
        for i in inputs where !used.contains(i.id) && i.id != "goods" && i.id != "repair" { rows.append(supplyRowForInput(co, bd, i)) }
        var order = SupplyCatalogue.groups
        for r in rows where !order.contains(r.group) { order.append(r.group) }
        return order.compactMap { g in
            let rs = rows.filter { $0.group == g }
            return rs.isEmpty ? nil : SupplyGroup(name: g, rows: rs)
        }
    }

    func supplyAsk(companyID: Int, itemID: String) -> SupplyAsk? {
        if !ItemModels.offers(state, companyID: companyID, itemID: itemID, data: data).isEmpty { return .item }
        guard let co = state.company(companyID), let bd = data.catalog[co.type], let stock = SupplyCatalogue.stockLine(co, bd), stock.input != "goods",
              SupplyCatalogue.chosenID(co, line: stock.id) == nil,
              salesItems(companyID: companyID).first(where: { $0.id == itemID })?.isService == true,
              let row = supplyLines(companyID: companyID).flatMap({ $0.rows }).first(where: { $0.id == stock.id }),
              row.governed == nil, row.canSwitch else { return nil }
        return .line(stock.id)
    }

    @discardableResult
    mutating func chooseSupply(companyID: Int, change: SupplyChange) -> SupplierSwitchResult {
        if let co = state.company(companyID), let bd = data.catalog[co.type] {
            let key: String
            switch change { case .input(let id, _): key = id; case .catalogue(let line, _): key = line }
            for l in SupplyCatalogue.lines(co, bd) where l.id == key || l.input == key {
                if PlayerSupply.contract(state, buyer: companyID, line: l.id) != nil, !isPlayerOffer(change) { update { s, _, _ in PlayerSupply.end(&s, buyer: companyID, line: l.id) } }
                // A stock or upkeep supplier replaces an own company on the same line.
                if case .input(let id, let c) = change, id == "goods" || id == "repair", c != .outside, IntercompanySupply.link(state, buyer: companyID, kind: l.id) != nil {
                    _ = switchSupplier(companyID: companyID, input: l.id, to: .outside)
                }
            }
        }
        switch change {
        case .input(let input, let c):
            return switchSupplier(companyID: companyID, input: input, to: c)
        case .catalogue(let line, let offer):
            guard let co = state.company(companyID), let bd = data.catalog[co.type], let l = SupplyCatalogue.lines(co, bd).first(where: { $0.id == line }) else { return .unknown }
            if l.automatic { return .notAllowed }
            if let k = l.input, k != "goods", k != "repair", IntercompanySupply.kind(k) != nil,
               IntercompanySupply.link(state, buyer: companyID, kind: k) != nil || AccountSupply.link(state, buyer: companyID, kind: k) != nil {
                if switchSupplier(companyID: companyID, input: k, to: .outside) != .ok { return .governed }
            }
            var ok = false
            update { s, d, _ in ok = SupplyCatalogue.choose(&s, companyID: companyID, line: line, offer: offer, data: d) }
            if ok { update { s, _, _ in Tutorial.advance(&s, from: .pickSupplier) } }
            return ok ? .ok : .notAllowed
        }
    }

    private func isPlayerOffer(_ change: SupplyChange) -> Bool {
        if case .catalogue(_, let offer) = change { return offer.hasPrefix("P:") }
        return false
    }

    private func supplyLeadWord(_ days: Int) -> String { days <= 0 ? "Continuous" : days == 1 ? "Next day" : "\(days) days" }
    private func supplyStarsWord(_ stars: String) -> String {
        guard stars.hasSuffix("stars"), let v = stars.split(separator: " ").first.flatMap({ Double($0) }) else { return "Not yet tested" }
        return v < 3.4 ? "Patchy" : v < 4.2 ? "Steady" : "Dependable"
    }
    private func supplyClassWord(_ co: Company) -> String {
        let c = co.value("src")["c"]
        return SupplyCatalogue.qualityWord(tier: c.isNull ? 1 : min(2, max(0, c.int)))
    }
    private func supplyOwnShare(_ o: SupplierOption) -> Int? {
        guard o.reliability.contains("% delivered") else { return nil }
        return o.reliability.split(separator: "%").first.flatMap { Int($0) } ?? 100
    }
    private func supplyOwnReliability(_ o: SupplierOption) -> String {
        guard let n = supplyOwnShare(o) else { return "Not yet tested" }
        return n >= 95 ? "Dependable" : n >= 80 ? "Steady" : "Patchy"
    }
    private func supplyPriceLevel(_ factor: Double) -> String { factor < 0.97 ? "Under market price" : factor > 1.03 ? "Above market price" : "Market price" }
    private func supplyCostIndex(_ co: Company) -> Double { World(state: state, data: data).country(co).costIndex }

    // A player company row with the facts every supplier shows, and whether it can meet the need.
    private func supplierFacts(_ row: inout SupplyOfferRow, _ v: SupplyPlayers.Supplier?, need: Int) {
        guard let v else { return }
        row.owner = v.owner
        row.ownerCode = v.ownerCode
        row.logoID = v.logoID
        row.tradeID = v.tradeID
        row.city = v.city
        row.size = SupplyPlayers.sizeWord(v)
        row.staff = v.staff
        row.weeksTrading = v.weeksTrading
        let free = SupplyPlayers.free(v, need: Double(need))
        row.free = Int(saturating: free.rounded(.down))
        row.fit = row.isCurrent ? SupplyFit.of(free: free + Double(need), need: Double(need)) : SupplyFit.of(free: free, need: Double(need))
    }

    // Own companies that can take over this line, as rows.
    private func ownRows(_ co: Company, _ k: SupplierInput, line: String, lead: String, marketWeekly: Double?, shownNow: Double?) -> [SupplyOfferRow] {
        k.options.filter { $0.kind == .ownCompany || ($0.kind == .businessCustomer && $0.isCurrent) }.map { (o: SupplierOption) -> SupplyOfferRow in
            var w: Double?
            if let m = marketWeekly { w = m * (o.priceFactor ?? 1) }
            var vs: Double?
            if let w, let n = shownNow { vs = w - n }
            let share: Int? = supplyOwnShare(o)
            var row = SupplyOfferRow(id: o.id, name: o.name, detail: o.subtitle, quality: "Solid", reliability: supplyOwnReliability(o), trust: share.map { Double($0) / 100 },
                                     source: o.kind == .ownCompany ? "Your company" : "Company", lead: lead, weekly: w, weeklyVsNow: vs, isCurrent: o.isCurrent, blocked: o.blocked,
                                     change: .input(k.id, o.change))
            row.isOwn = o.kind == .ownCompany
            row.priceLevel = supplyPriceLevel(o.priceFactor ?? 1)
            if let n = share { row.fit = n >= 95 ? .fine : n >= 80 ? .mayFallShort : .cannot }
            return row
        }
    }

    private func supplyRow(_ co: Company, _ bd: Trade, _ line: SupplyCatalogue.Line, _ input: SupplierInput?, _ ownInput: SupplierInput?) -> SupplyRow {
        let need = SupplyCatalogue.needUnits(co, bd, line: line.id, costIndex: supplyCostIndex(co))
        let spend = SupplyCatalogue.weeklySpend(co, line: line.id)
        var weekly = spend?.now, before = spend?.before
        if line.input == "repair" { weekly = nil; before = nil }
        if (weekly ?? 0) <= 0, let y = (input ?? ownInput)?.yearlySpend, y > 0 { weekly = y / 52; before = nil }
        var kindInput: SupplierInput? = ownInput
        if kindInput == nil, let i = input, IntercompanySupply.kind(i.id) != nil { kindInput = i }
        let linked = kindInput?.current.map { $0.kind == .ownCompany || $0.kind == .businessCustomer } ?? false
        let cur = SupplyCatalogue.current(state, co, bd, line: line, data: data)
        var nowPF = 1.0
        if line.input == "goods" { nowPF = input?.current?.priceFactor ?? 1 } else if !linked, let c = cur { nowPF = c.priceFactor }
        let marketWeekly = weekly.map { $0 / max(0.01, nowPF) }
        let curPF = linked ? (kindInput?.current?.priceFactor ?? 1) : nowPF
        let shownNow: Double? = marketWeekly.map { $0 * curPF }
        let pool: [SupplyPlayers.Supplier] = Suppliers.lineSuppliers(state, company: co, line: line.id, data: data)
        var offers: [SupplyOfferRow] = []
        if line.input == "goods" || line.input == "repair", let inp = input {
            for o in inp.options where o.vendorID != nil {
                var w: Double?
                if line.input == "goods", let p = o.priceFactor, let m = marketWeekly { w = m * p }
                var vs: Double?
                if let w, let n = shownNow { vs = w - n }
                var detail: String = o.subtitle
                if line.input == "repair" {
                    let d: Double = o.discount ?? 0
                    detail = d > 0 ? "Cuts upkeep bills by \(Int(saturating: (d * 100).rounded()))%" : "Standard upkeep bills"
                }
                let goods: Bool = line.input == "goods"
                let supplier = pool.first { $0.id == o.vendorID }
                var row = SupplyOfferRow(id: o.id, name: o.name, detail: detail, quality: goods ? supplyClassWord(co) : "Solid", reliability: supplyStarsWord(o.reliability),
                                         trust: supplier?.reliability, source: "Player", lead: supplyLeadWord(line.leadDays), weekly: w,
                                         weeklyVsNow: vs, isCurrent: o.isCurrent && !linked, blocked: o.blocked, change: .input(inp.id, o.change))
                row.priceLevel = supplyPriceLevel(o.priceFactor ?? 1)
                supplierFacts(&row, supplier, need: need)
                offers.append(row)
            }
        } else if line.tiers {
            for o in SupplyCatalogue.offers(state, co, bd, line: line, data: data) {
                var w: Double?
                if let m = marketWeekly { w = m * o.priceFactor }
                var vs: Double?
                if let w, let n = shownNow { vs = w - n }
                let detail: String = o.owner + (o.relationshipWord.map { " · " + $0 } ?? "")
                var row = SupplyOfferRow(id: o.id, name: o.name, detail: detail, quality: SupplyCatalogue.qualityWord(tier: o.tier), reliability: SupplyCatalogue.reliabilityWord(o.reliability),
                                         trust: o.reliability, source: "Player", lead: supplyLeadWord(o.leadDays), weekly: w, weeklyVsNow: vs,
                                         isCurrent: !linked && o.id == cur?.id, blocked: nil, change: .catalogue(line: line.id, offer: o.id))
                row.priceLevel = supplyPriceLevel(o.priceFactor)
                supplierFacts(&row, pool.first { $0.id == o.id }, need: need)
                offers.append(row)
            }
        }
        if let k = kindInput { offers += ownRows(co, k, line: line.id, lead: supplyLeadWord(line.leadDays), marketWeekly: marketWeekly, shownNow: shownNow) }
        let now = offers.first { $0.isCurrent } ?? offers.first
        var note: String?
        if SupplyCatalogue.missedRecently(state, co, bd, line: line, data: data) { note = "A delivery was missed recently, so fewer customers were served." }
        return SupplyRow(id: line.id, group: line.group, title: line.name, kind: line.kind, scale: Self.supplyScale(line), current: now?.name ?? "", quality: now?.quality ?? "Solid",
                         reliability: now?.reliability ?? "Steady", weekly: shownNow ?? weekly, weeklyBefore: before, note: note,
                         governed: input?.governedBy ?? ownInput?.governedBy, offers: offers, need: need, input: line.input)
    }

    // A line only an own company can change (its cost is part of the trade's own cost model): the usual player supplier and own companies.
    private func supplyRowForInput(_ co: Company, _ bd: Trade, _ i: SupplierInput) -> SupplyRow {
        let spec = SupplyMap.line(i.id)
        let need = SupplyCatalogue.needUnits(co, bd, line: i.id, costIndex: supplyCostIndex(co))
        let weekly: Double? = i.yearlySpend.map { $0 / 52 }
        var offers: [SupplyOfferRow] = []
        let lead: String = supplyLeadWord(spec?.lead ?? 1)
        if let usual = i.options.first(where: { $0.kind == .outside }), let v = Suppliers.lineSuppliers(state, company: co, line: i.id, data: data).first {
            var row = SupplyOfferRow(id: v.id, name: v.name, detail: v.owner, quality: "Solid", reliability: SupplyCatalogue.reliabilityWord(v.reliability), trust: v.reliability,
                                     source: "Player", lead: lead, weekly: weekly, weeklyVsNow: nil, isCurrent: usual.isCurrent, blocked: nil, change: .input(i.id, .outside))
            row.priceLevel = supplyPriceLevel(1)
            supplierFacts(&row, v, need: need)
            offers.append(row)
        }
        offers += ownRows(co, i, line: i.id, lead: lead, marketWeekly: weekly, shownNow: weekly)
        let now = offers.first { $0.isCurrent } ?? offers.first
        return SupplyRow(id: i.id, group: spec?.group ?? "Services", title: i.title, kind: i.title, scale: i.what, current: now?.name ?? "",
                         quality: now?.quality ?? "Solid", reliability: now?.reliability ?? "Steady", weekly: weekly, weeklyBefore: nil,
                         note: nil, governed: i.governedBy, offers: offers, need: need, input: i.id)
    }

    private static func supplyScale(_ line: SupplyCatalogue.Line) -> String {
        line.isCogs ? "Follows what you sell" : line.variable ? "Follows how busy the place is" : "Follows the size of the place"
    }
}
