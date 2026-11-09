import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// The Suppliers screen of a company as one list of what it buys, grouped by what is supplied (not by vendor). Each row is a line of the trade's
/// supply catalogue (`SupplyCatalogue`): its current supplier, a word for quality and reliability, what it cost this week against the week
/// before, and the offers to switch to. Stock and repairs read the existing goods and repair suppliers, and kinds your own companies can supply
/// read the existing own-company switch; the other lines use the catalogue's own offers. Nothing is decided here.

public enum SupplyChange: Equatable, Sendable {
    /// A supplier of a catalogue line ("market" or a supplier id).
    case catalogue(line: String, offer: String)
    /// The existing switch of an input (stock, repairs, an own-company supply).
    case input(String, SupplierSwitch)
}

public struct SupplyOfferRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var detail: String
    public var quality: String
    public var reliability: String
    public var terms: String
    public var lead: String
    /// What it would cost a week at this company's activity (nil when it is billed per job).
    public var weekly: Double?
    /// Against the supplier used now: positive costs more a week.
    public var weeklyVsNow: Double?
    public var isCurrent: Bool
    public var blocked: String?
    public var change: SupplyChange
}

public struct SupplyRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var group: String
    public var title: String
    /// The same kind of purchase in general words, shared by every trade ("Linen and laundry").
    public var kind: String
    /// What the line is, in words ("Cleaning and hygiene supplies").
    public var scale: String
    public var current: String
    public var quality: String
    public var reliability: String
    public var weekly: Double?
    public var weeklyBefore: Double?
    /// A delivery missed recently.
    public var note: String?
    /// Why a chain's rule or a franchise agreement fixes the choice; nil when the company decides.
    public var governed: String?
    public var offers: [SupplyOfferRow]
    public var canSwitch: Bool { offers.contains { !$0.isCurrent && $0.blocked == nil } }
}

public struct SupplyGroup: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var rows: [SupplyRow]
}

public extension GameEngine {
    /// What the company buys, grouped by what is supplied. Empty for a trade that buys nothing.
    func supplyLines(companyID: Int) -> [SupplyGroup] {
        guard let co = state.company(companyID), co.status.isLive, let bd = data.catalog[co.type] else { return [] }
        let inputs = supplierInputs(companyID: companyID)
        var rows: [SupplyRow] = []
        var used = Set<String>()
        for line in SupplyCatalogue.lines(co, bd) {
            let input = line.input.flatMap { id in inputs.first { $0.id == id } }
            if let i = input { used.insert(i.id) }
            rows.append(supplyRow(co, bd, line, input))
        }
        // Inputs the catalogue does not name (a service one of your own companies could supply) get a row of their own.
        for i in inputs where !used.contains(i.id) { rows.append(supplyRowForInput(co, i)) }
        var order = SupplyCatalogue.groups
        for r in rows where !order.contains(r.group) { order.append(r.group) }
        return order.compactMap { g in
            let rs = rows.filter { $0.group == g }
            return rs.isEmpty ? nil : SupplyGroup(name: g, rows: rs)
        }
    }

    /// Whether the company has anything to show on its Suppliers screen.
    func hasSupplyLines(companyID: Int) -> Bool {
        guard let co = state.company(companyID), co.status.isLive else { return false }
        return !supplyLines(companyID: companyID).isEmpty || !supplyLinks().filter { $0.supplierID == companyID }.isEmpty
    }

    /// Switch the supplier of one row. Choosing an outside supplier of a kind your own company supplied ends that supply first.
    @discardableResult
    mutating func chooseSupply(companyID: Int, change: SupplyChange) -> SupplierSwitchResult {
        switch change {
        case .input(let input, let c):
            return switchSupplier(companyID: companyID, input: input, to: c)
        case .catalogue(let line, let offer):
            guard let co = state.company(companyID), let bd = data.catalog[co.type], let l = SupplyCatalogue.lines(co, bd).first(where: { $0.id == line }) else { return .unknown }
            if let k = l.input, k != "goods", k != "repair", IntercompanySupply.kind(k) != nil,
               IntercompanySupply.link(state, buyer: companyID, kind: k) != nil || AccountSupply.link(state, buyer: companyID, kind: k) != nil {
                if switchSupplier(companyID: companyID, input: k, to: .outside) != .ok { return .governed }
            }
            var ok = false
            update { s, d, _ in ok = SupplyCatalogue.choose(&s, companyID: companyID, line: line, offer: offer, data: d) }
            return ok ? .ok : .notAllowed
        }
    }

    // MARK: Words

    private func supplyLeadWord(_ days: Int) -> String { days <= 0 ? "Continuous" : days == 1 ? "Next day" : "\(days) days" }
    private func supplyTermsWord(_ days: Int) -> String { days == 0 ? "Paid on delivery" : "Paid after \(days) days" }
    private func supplyStarsWord(_ stars: String) -> String {
        guard stars.hasSuffix("stars"), let v = stars.split(separator: " ").first.flatMap({ Double($0) }) else { return "Not yet tested" }
        return v < 3.4 ? "Patchy" : v < 4.2 ? "Steady" : "Dependable"
    }
    private func supplyClassWord(_ co: Company) -> String {
        let c = co.value("src")["c"]
        return SupplyCatalogue.qualityWord(tier: c.isNull ? 1 : min(2, max(0, c.int)))
    }
    private func supplyOwnReliability(_ o: SupplierOption) -> String {
        guard o.reliability.contains("% delivered") else { return "Not yet tested" }
        let n = o.reliability.split(separator: "%").first.flatMap { Int($0) } ?? 100
        return n >= 95 ? "Dependable" : n >= 80 ? "Steady" : "Patchy"
    }

    // MARK: Rows

    private func supplyRow(_ co: Company, _ bd: Trade, _ line: SupplyCatalogue.Line, _ input: SupplierInput?) -> SupplyRow {
        let cur = SupplyCatalogue.current(state, co, bd, line: line, data: data)
        let spend = SupplyCatalogue.weeklySpend(co, line: line.id)
        var weekly = spend?.now, before = spend?.before
        if line.input == "repair" { weekly = nil; before = nil }
        if (weekly ?? 0) <= 0, let y = input?.yearlySpend, y > 0 { weekly = y / 52; before = nil }
        var offers: [SupplyOfferRow] = []
        let linked = input?.current.map { $0.kind == .ownCompany || $0.kind == .businessCustomer } ?? false
        let folded = line.tiers && line.input != "goods" && line.input != "repair" && !linked
        // The price level the recorded spend is at, so another offer can be priced against it.
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
                                             terms: goods ? "As agreed with this supplier" : "Billed per job", lead: supplyLeadWord(line.leadDays), weekly: w,
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
                    let terms: String = o.isMarket ? "Paid as bought" : supplyTermsWord(o.termsDays)
                    offers.append(SupplyOfferRow(id: o.id, name: o.name, detail: detail, quality: SupplyCatalogue.qualityWord(tier: o.tier), reliability: rel, terms: terms,
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
                                             reliability: outside ? "Steady" : supplyOwnReliability(o), terms: outside ? "Paid as bought" : "Settled weekly between the books",
                                             lead: supplyLeadWord(line.leadDays), weekly: w, weeklyVsNow: vs, isCurrent: o.isCurrent, blocked: o.blocked,
                                             change: .input(input?.id ?? line.id, o.change)))
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
                                         reliability: outside ? "Steady" : supplyOwnReliability(o), terms: outside ? "Paid as bought" : "Settled weekly between the books",
                                         lead: outside ? "As needed" : "Same week", weekly: w, weeklyVsNow: nil, isCurrent: o.isCurrent, blocked: o.blocked, change: .input(i.id, o.change)))
        }
        let now = offers.first { $0.isCurrent } ?? offers.first
        return SupplyRow(id: i.id, group: cat == "cogs" ? "Stock and ingredients" : "Software and services", title: i.title, kind: i.title, scale: i.what, current: now?.name ?? "Market",
                         quality: now?.quality ?? "Solid", reliability: now?.reliability ?? "Steady", weekly: i.yearlySpend.map { $0 / 52 }, weeklyBefore: nil,
                         note: nil, governed: i.governedBy, offers: offers)
    }

    private static func supplyScale(_ line: SupplyCatalogue.Line) -> String {
        line.isCogs ? "Follows what you sell" : line.variable ? "Follows how busy the place is" : "Follows the size of the place"
    }
}
