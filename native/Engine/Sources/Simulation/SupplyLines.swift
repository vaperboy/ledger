import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum SupplyChange: Equatable, Sendable {
    case catalogue(line: String, offer: String)
    case input(String, SupplierSwitch)
}

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
    public var canSwitch: Bool { offers.contains { !$0.isCurrent && $0.blocked == nil } }
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
    func supplyLines(companyID: Int) -> [SupplyGroup] {
        guard let co = state.company(companyID), co.status.isLive, let bd = data.catalog[co.type], !SalesItems.firstChoicePending(co) else { return [] }
        let inputs = supplierInputs(companyID: companyID)
        let sold = salesItems(companyID: companyID)
        let sellsProducts = sold.isEmpty || sold.contains { !$0.isService }
        let sellsServices = sold.isEmpty || sold.contains { $0.isService }
        var rows: [SupplyRow] = []
        var used = Set<String>()
        for line in SupplyCatalogue.lines(co, bd) where !line.automatic && (line.id != "pack" || sellsProducts) && (line.id != "mat" || sellsServices) && (line.input != "goods" || sellsProducts) {
            let input = line.input.flatMap { id in inputs.first { $0.id == id } }
            if let i = input { used.insert(i.id) }
            rows.append(supplyRow(co, bd, line, input))
        }
        for i in inputs where !used.contains(i.id) { rows.append(supplyRowForInput(co, i)) }
        var order = SupplyCatalogue.groups
        for r in rows where !order.contains(r.group) { order.append(r.group) }
        return order.compactMap { g in
            let rs = rows.filter { $0.group == g }
            return rs.isEmpty ? nil : SupplyGroup(name: g, rows: rs)
        }
    }

    func supplyAsk(companyID: Int, itemID: String) -> SupplyAsk? {
        if !ItemModels.offers(state, companyID: companyID, itemID: itemID, data: data).isEmpty { return .item }
        guard let co = state.company(companyID), co.value("sc")["mat"].isNull,
              salesItems(companyID: companyID).first(where: { $0.id == itemID })?.isService == true,
              let row = supplyLines(companyID: companyID).flatMap({ $0.rows }).first(where: { $0.id == "mat" }),
              row.governed == nil, row.canSwitch else { return nil }
        return .line("mat")
    }

    @discardableResult
    mutating func chooseSupply(companyID: Int, change: SupplyChange) -> SupplierSwitchResult {
        if let co = state.company(companyID), let bd = data.catalog[co.type] {
            let key: String
            switch change { case .input(let id, _): key = id; case .catalogue(let line, _): key = line }
            for l in SupplyCatalogue.lines(co, bd) where l.id == key || l.input == key {
                if PlayerSupply.contract(state, buyer: companyID, line: l.id) != nil, !isPlayerOffer(change) { update { s, _, _ in PlayerSupply.end(&s, buyer: companyID, line: l.id) } }
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
    private func supplyStarsTrust(_ stars: String) -> Double? {
        guard stars.hasSuffix("stars"), let v = stars.split(separator: " ").first.flatMap({ Double($0) }) else { return nil }
        return min(0.995, max(0.8, 0.85 + (v - 2.6) / 2.2 * 0.14))
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
    private func supplySource(_ kind: SupplierProviderKind) -> String { kind == .outside || kind == .noneFixed ? "Market" : "Company" }

    private func supplyRow(_ co: Company, _ bd: Trade, _ line: SupplyCatalogue.Line, _ input: SupplierInput?) -> SupplyRow {
        let cur = SupplyCatalogue.current(state, co, bd, line: line, data: data)
        let spend = SupplyCatalogue.weeklySpend(co, line: line.id)
        var weekly = spend?.now, before = spend?.before
        if line.input == "repair" { weekly = nil; before = nil }
        if (weekly ?? 0) <= 0, let y = input?.yearlySpend, y > 0 { weekly = y / 52; before = nil }
        var offers: [SupplyOfferRow] = []
        let linked = input?.current.map { $0.kind == .ownCompany || $0.kind == .businessCustomer } ?? false
        let folded = line.tiers && line.input != "goods" && line.input != "repair" && !linked
        var nowPF = 1.0
        if line.input == "goods" { nowPF = input?.current?.priceFactor ?? 1 } else if folded { nowPF = cur.priceFactor } else if linked { nowPF = 1 }
        let marketWeekly = weekly.map { $0 / max(0.01, nowPF) }
        let curPF = linked ? (input?.current?.priceFactor ?? 1) : nowPF
        let shownNow: Double? = marketWeekly.map { $0 * curPF }
        if line.input == "goods" || line.input == "repair", let inp = input {
            let list = inp.options.filter { ($0.vendorID != nil && $0.kind != .outside) || $0.kind == .noneFixed }
            let cheapest: [SupplierOption] = list.filter { !$0.isCurrent }.sorted { (a: SupplierOption, b: SupplierOption) -> Bool in
                let pa: Double = a.priceFactor ?? 1, pb: Double = b.priceFactor ?? 1
                return pa < pb
            }
            let shown: [SupplierOption] = Array((list.filter { $0.isCurrent } + cheapest).prefix(4))
            for o in shown {
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
                offers.append(SupplyOfferRow(id: o.id, name: o.name, detail: detail, quality: goods ? supplyClassWord(co) : "Solid", reliability: supplyStarsWord(o.reliability),
                                             trust: supplyStarsTrust(o.reliability), source: supplySource(o.kind), lead: supplyLeadWord(line.leadDays), weekly: w,
                                             weeklyVsNow: vs, isCurrent: o.isCurrent, blocked: o.blocked, change: .input(inp.id, o.change)))
            }
        } else {
            if line.tiers {
                for o in SupplyCatalogue.offers(state, co, bd, line: line, data: data) {
                    var w: Double?
                    if let m = marketWeekly { w = m * o.priceFactor }
                    var vs: Double?
                    if let w, let n = shownNow { vs = w - n }
                    var detail: String = "Whoever the market offers"
                    if !o.isMarket { detail = o.owner + (o.relationshipWord.map { " · " + $0 } ?? "") }
                    let rel: String = o.isMarket ? "Steady" : SupplyCatalogue.reliabilityWord(o.reliability)
                    offers.append(SupplyOfferRow(id: o.id, name: o.name, detail: detail, quality: SupplyCatalogue.qualityWord(tier: o.tier), reliability: rel,
                                                 trust: o.reliability, source: o.isMarket ? "Market" : o.id.hasPrefix("P:") ? "Player" : "Company",
                                                 lead: supplyLeadWord(o.leadDays), weekly: w, weeklyVsNow: vs, isCurrent: !linked && o.id == cur.id, blocked: nil,
                                                 change: .catalogue(line: line.id, offer: o.id)))
                }
            }
            for o in input?.options ?? [] where o.kind == .ownCompany || o.kind == .businessCustomer || (!line.tiers && o.kind == .outside) {
                var w: Double?
                if let m = marketWeekly { w = m * (o.priceFactor ?? 1) }
                var vs: Double?
                if let w, let n = shownNow { vs = w - n }
                let outside: Bool = o.kind == .outside
                offers.append(SupplyOfferRow(id: o.id, name: o.name, detail: outside ? "Whoever the market offers" : o.subtitle, quality: "Solid",
                                             reliability: outside ? "Steady" : supplyOwnReliability(o), trust: outside ? 0.97 : supplyOwnShare(o).map { Double($0) / 100 },
                                             source: supplySource(o.kind), lead: supplyLeadWord(line.leadDays), weekly: w, weeklyVsNow: vs, isCurrent: o.isCurrent,
                                             blocked: o.blocked, change: .input(input?.id ?? line.id, o.change)))
            }
        }
        let now = offers.first { $0.isCurrent } ?? offers.first
        var note: String?
        if SupplyCatalogue.missedRecently(state, co, bd, line: line, data: data) { note = "A delivery was missed recently, so fewer customers were served." }
        let curName = now?.name ?? cur.name
        return SupplyRow(id: line.id, group: line.group, title: line.name, kind: line.kind, scale: Self.supplyScale(line), current: curName, quality: now?.quality ?? "Solid",
                         reliability: now?.reliability ?? "Steady", weekly: shownNow ?? weekly, weeklyBefore: before, note: note, governed: input?.governedBy, offers: offers)
    }

    private func supplyRowForInput(_ co: Company, _ i: SupplierInput) -> SupplyRow {
        let cat = IntercompanySupply.kind(i.id)?.category ?? "oth"
        var offers: [SupplyOfferRow] = []
        for o in i.options {
            let outside: Bool = o.kind == .outside
            var w: Double?
            if let y = i.yearlySpend { w = y / 52 * (o.priceFactor ?? 1) }
            offers.append(SupplyOfferRow(id: o.id, name: o.name, detail: outside ? "Whoever the market offers" : o.subtitle, quality: "Solid",
                                         reliability: outside ? "Steady" : supplyOwnReliability(o), trust: outside ? 0.97 : supplyOwnShare(o).map { Double($0) / 100 },
                                         source: supplySource(o.kind), lead: outside ? "As needed" : "Same week", weekly: w, weeklyVsNow: nil, isCurrent: o.isCurrent,
                                         blocked: o.blocked, change: .input(i.id, o.change)))
        }
        let now = offers.first { $0.isCurrent } ?? offers.first
        return SupplyRow(id: i.id, group: cat == "cogs" ? "Stock and ingredients" : "Other supplies", title: i.title, kind: i.title, scale: i.what, current: now?.name ?? "Market",
                         quality: now?.quality ?? "Solid", reliability: now?.reliability ?? "Steady", weekly: i.yearlySpend.map { $0 / 52 }, weeklyBefore: nil,
                         note: nil, governed: i.governedBy, offers: offers)
    }

    private static func supplyScale(_ line: SupplyCatalogue.Line) -> String {
        line.isCogs ? "Follows what you sell" : line.variable ? "Follows how busy the place is" : "Follows the size of the place"
    }
}
