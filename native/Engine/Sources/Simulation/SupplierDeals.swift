import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum SupplierProviderKind: String, Equatable, Sendable { case outside, outsideVendor, ownCompany, businessCustomer, repairVendor, noneFixed }

public struct SupplierOption: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: SupplierProviderKind
    public var name: String
    public var subtitle: String
    public var change: SupplierSwitch
    public var isCurrent: Bool
    public var priceFactor: Double?
    public var yearlyVsMarket: Double?
    public var yearlyVsCurrent: Double?
    public var discount: Double?
    public var relationship: Double?
    public var relationshipWord: String?
    public var nextLevel: String?
    public var vendorID: String?
    public var quality: String?
    public var reliability: String
    public var terms: String
    public var delivery: String
    public var risks: [String]
    public var blocked: String?
    public var negotiable = false
    public var dealExtra: Double?
    public var coolingUntil: Int?
}

public struct PaymentTermChoice: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var detail: String
    public var isCurrent: Bool
    public var blocked: String?
}

public struct SupplierInput: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var what: String
    public var yearlySpend: Double?
    public var current: SupplierOption?
    public var options: [SupplierOption]
    public var noOwnProvider: String?
    public var paymentTerms: [PaymentTermChoice] = []
    public var governedBy: String?
}

public extension GameEngine {

    func supplierInputs(companyID: Int) -> [SupplierInput] {
        guard let co = state.company(companyID), co.status.isLive, let bd = data.catalog[co.type] else { return [] }
        var out: [SupplierInput] = []
        if Suppliers.hasGoods(bd, co) { out.append(supplierGoodsInput(co, bd)) }
        if !bd.equipment.isEmpty { out.append(supplierRepairInput(co)) }
        for k in IntercompanySupply.kindsFor(co) { out.append(supplierKindInput(co, k)) }
        for n in out.indices {
            out[n].governedBy = SupplyDeals.governedBy(state, co, input: out[n].id, data: data)
            out[n].paymentTerms = supplierPaymentTerms(co, input: out[n].id)
            for m in out[n].options.indices where out[n].options[m].kind == .outsideVendor || out[n].options[m].kind == .repairVendor {
                guard let vid = out[n].options[m].vendorID else { continue }
                out[n].options[m].negotiable = out[n].governedBy == nil
                out[n].options[m].coolingUntil = SupplyDeals.coolUntil(co, vendorID: vid, week: state.week)
                if out[n].options[m].isCurrent, let d = SupplyDeals.deal(co, input: out[n].id, week: state.week), d.vendorID == vid { out[n].options[m].dealExtra = d.extraDiscount }
            }
            out[n].current = out[n].options.first { $0.isCurrent }
        }
        return out
    }

    private func supplierPaymentTerms(_ co: Company, input: String) -> [PaymentTermChoice] {
        func pct(_ x: Double) -> String { String(format: "%.1f%%", abs(x) * 100) }
        if input == "goods" || input == "repair" {
            let repair = input == "repair"
            guard let v = repair ? Suppliers.repairVendor(state, company: co, data: data) : Suppliers.goodsVendor(state, company: co, data: data) else { return [] }
            let agreed = repair ? SupplyTerms.agreedRepairTerm(co) : SupplyTerms.agreedGoodsTerm(co)
            let active = (repair ? SupplyTerms.repairTerm(state, co, data: data) : SupplyTerms.goodsTerm(state, co, data: data))?.id ?? "monthly"
            let thing = repair ? "Each repair and upkeep bill" : "Each delivery"
            return SupplyTerms.vendorTerms.map { t in
                var detail = t.isMonthEnd ? (repair ? "Repair and upkeep bills are paid as they fall due, as usual." : "Bills are paid on the last day of the month, as usual.")
                    : t.days == 0 ? "\(thing) is paid on the spot." : "\(thing) is invoiced and paid \(t.days) days later."
                if t.priceEffect < 0 { detail += " \(pct(t.priceEffect)) off the price for paying at once." }
                if t.priceEffect > 0 { detail += " \(pct(t.priceEffect)) added to the price for the credit." }
                let blocked: String? = v.relationship >= t.minRelationship ? nil : "\(v.name) offers this only to \(Suppliers.relationshipWord(t.minRelationship).lowercased()) contacts or closer."
                return PaymentTermChoice(id: t.id, name: t.name, detail: detail, isCurrent: t.id == active && (agreed != nil || t.isMonthEnd), blocked: blocked)
            }
        }
        guard let k = IntercompanySupply.kind(input), let l = IntercompanySupply.link(state, buyer: co.id, kind: k.id) else { return [] }
        let cur = l.termsID ?? "weekly"
        return SupplyTerms.groupTerms.map { t in
            PaymentTermChoice(id: t.id, name: t.name, detail: t.days == 0 ? "Settled between the two companies' books every week." : "Invoiced weekly; the buyer owes it and the supplier holds the receivable until it is paid \(t.days) days later. Late payment carries interest.",
                              isCurrent: t.id == cur, blocked: nil)
        }
    }

    func supplierCurrentProviders(companyID: Int) -> [(inputID: String, title: String, provider: String)] {
        guard let co = state.company(companyID), co.status.isLive, let bd = data.catalog[co.type] else { return [] }
        var out: [(inputID: String, title: String, provider: String)] = []
        if Suppliers.hasGoods(bd, co), let v = Suppliers.goodsVendor(state, company: co, data: data) { out.append((inputID: "goods", title: "Goods", provider: v.name)) }
        if !bd.equipment.isEmpty, let v = Suppliers.repairVendor(state, company: co, data: data) { out.append((inputID: "repair", title: "Repairs and upkeep", provider: v.name)) }
        for k in IntercompanySupply.kindsFor(co) {
            if let l = IntercompanySupply.link(state, buyer: co.id, kind: k.id), let s = state.company(l.supplierID) {
                out.append((inputID: k.id, title: k.name, provider: s.name))
            } else {
                out.append((inputID: k.id, title: k.name, provider: supplierLineName(co, bd, line: k.id)))
            }
        }
        return out
    }

    // The player company that supplies a line when no own company does.
    func supplierLineName(_ co: Company, _ bd: Trade, line: String) -> String {
        if let l = SupplyCatalogue.lines(co, bd).first(where: { $0.id == line }), let o = SupplyCatalogue.current(state, co, bd, line: l, data: data) { return o.name }
        return Suppliers.lineSuppliers(state, company: co, line: line, data: data).first?.name ?? ""
    }

    private func supplierYearlyRevenue(_ co: Company) -> Double {
        let h = co.monthlyHistory.suffix(3)
        return h.isEmpty ? co.lastWeekRevenue * 52 : h.reduce(0.0) { $0 + $1.revenue } / Double(h.count) * 12
    }

    private func supplierPct(_ x: Double) -> String { "\(Int(saturating: (x * 100).rounded()))%" }

    private func supplierVendorOption(_ v: Suppliers.Vendor, id: String, kind: SupplierProviderKind, change: SupplierSwitch, current: Bool) -> SupplierOption {
        let next = Suppliers.nextDiscountTier(v.relationship)
        let agreed = Suppliers.agreement(state, scope: "goods") == v.id
        let terms = v.discount > 0 ? "\(supplierPct(v.discount)) off every order from your relationship" + (agreed ? " (includes the board agreement)" : "") : "List price, no relationship discount yet"
        return SupplierOption(id: id, kind: kind, name: v.name, subtitle: "\(v.owner) · \(v.relationshipWord)", change: change, isCurrent: current, priceFactor: nil,
                              yearlyVsMarket: nil, yearlyVsCurrent: nil, discount: v.discount, relationship: v.relationship, relationshipWord: v.relationshipWord,
                              nextLevel: next.map { "\($0.word) (from \(Int(saturating: $0.from.rounded()))): \(supplierPct($0.discount)) off every order" }, vendorID: v.id,
                              quality: nil, reliability: String(format: "%.1f stars", v.rating), terms: terms, delivery: "With your regular orders", risks: [], blocked: nil)
    }

    private func supplierGoodsInput(_ co: Company, _ bd: Trade) -> SupplierInput {
        let spend = supplierYearlyRevenue(co) * bd.costOfSales
        let offers = Sourcing.offers(state, company: co, data: data, classes: marketing.goodsClasses)
        let src = co.value("src")
        let auto = src["v"].isNull || src["v"].string == "auto"
        let curCost = offers.first { $0.current }?.costFactor
        var options: [SupplierOption] = offers.map { o in
            var x = supplierVendorOption(o.vendor, id: "v:" + o.vendor.id, kind: .outsideVendor, change: .goodsVendor(o.vendor.id), current: o.current)
            x.priceFactor = o.costFactor
            x.yearlyVsMarket = spend * (1 - o.costFactor)
            x.yearlyVsCurrent = curCost.map { spend * ($0 - o.costFactor) }
            x.quality = String(format: "%@ quality %+.0f points", Suppliers.goodsClassNames[min(2, max(0, o.goodsClass))], o.qualityShift)
            x.risks = ["Price rises, failures and cut deliveries can hit you."]
            return x
        }
        if let a = Suppliers.agreement(state, scope: "goods"), auto, let i = options.firstIndex(where: { $0.vendorID == a }) {
            options[i].subtitle += " · board agreement for all companies"
        }
        return SupplierInput(id: "goods", title: "Goods", what: "What the business sells or uses up: stock, ingredients, materials", yearlySpend: spend,
                             current: options.first { $0.isCurrent }, options: options, noOwnProvider: nil)
    }

    private func supplierRepairInput(_ co: Company) -> SupplierInput {
        let cands = Suppliers.candidates(state, company: co, scope: "fix", data: data)
        let cur = Suppliers.repairVendor(state, company: co, data: data)
        func opt(_ v: Suppliers.Vendor) -> SupplierOption {
            var x = supplierVendorOption(v, id: "f:" + v.id, kind: .repairVendor, change: .repairVendor(v.id), current: v.id == cur?.id)
            x.terms = v.discount > 0 ? "\(supplierPct(v.discount)) off repair and upkeep bills" : "Standard bills, no discount yet"
            x.risks = []
            return x
        }
        var options: [SupplierOption] = cands.map(opt)
        if let c = cur, !options.contains(where: { $0.vendorID == c.id }) { options.insert(opt(c), at: 0) }
        return SupplierInput(id: "repair", title: "Repairs and upkeep", what: "Servicing of your equipment: the discount cuts every upkeep and service bill", yearlySpend: nil,
                             current: options.first { $0.isCurrent }, options: options, noOwnProvider: nil)
    }

    private func supplierKindInput(_ co: Company, _ k: IntercompanySupply.Kind) -> SupplierInput {
        let spend = IntercompanySupply.yearlySpend(co, k)
        let link = IntercompanySupply.link(state, buyer: co.id, kind: k.id)
        let acctLink = AccountSupply.link(state, buyer: co.id, kind: k.id)
        let cogs = k.category == "cogs"
        let outsideRisk = cogs ? ["Exposed to supplier events: price rises, failures, cut deliveries."] : []
        let dway = k.delivered ? IntercompanySupply.deliveryWay(co.type, data.balance) : nil
        let outsideRel = dway.map { "\(Int(saturating: (($0.options["rel"] ?? 1) * 100).rounded()))% of orders reach the customer" }
        var options: [SupplierOption] = []
        let usual: String = data.catalog[co.type].map { supplierLineName(co, $0, line: k.id) } ?? ""
        options.append(SupplierOption(id: "out", kind: .outside, name: usual.isEmpty ? k.name : usual, subtitle: "Player company", change: .outside, isCurrent: link == nil && acctLink == nil,
                                      priceFactor: 1, yearlyVsMarket: 0, yearlyVsCurrent: nil, discount: nil, relationship: nil, relationshipWord: nil, nextLevel: nil, vendorID: nil,
                                      quality: nil, reliability: outsideRel ?? "Dependable",
                                      terms: k.delivered ? "Usual price per delivered order (\(supplierPct(k.buyers[co.type] ?? 0)) of the order value), paid as you deliver" : "Usual price, paid as you buy",
                                      delivery: k.delivered ? "Orders that are not delivered bring no customers" : (k.local ? "Same city" : "Same country"), risks: outsideRisk, blocked: nil))
        for sp in IntercompanySupply.suppliers(state, for: co, kind: k) {
            for m in IntercompanySupply.modes {
                let pf = IntercompanySupply.priceFactor(mode: m.id, supplier: sp, data: data, perkCut: Ambitions.supplyCostCut(state, data))
                let isCur = link?.supplierID == sp.id && link?.mode == m.id
                var risks = ["If \(sp.name) is short of people or closes, you pay for emergency supply (+20%) and below 80% delivered your reputation suffers."]
                if !k.noCapacity { risks.append("\(sp.name) holds back part of its own capacity for you.") }
                if SupplyTerms.ownSupplierStrained(state, buyer: co.id, supplier: sp.id) {
                    risks.append("\(co.name) has left \(sp.name) unpaid for \(SupplyTerms.ownLateWeeks(state, buyer: co.id, supplier: sp.id)) weeks, so it delivers only part of what it could. Pay what is overdue.")
                }
                if m.id != "mkt" && pf >= 1 { risks.append("\(sp.name) runs at no margin today, so this mode gives no saving yet.") }
                let delivered: String? = isCur ? link.map { "\(Int(saturating: ($0.lastShare * 100).rounded()))% delivered last week" } : nil
                options.append(SupplierOption(id: "o:\(sp.id):\(m.id)", kind: .ownCompany, name: sp.name, subtitle: "Yours · \(m.name)", change: .ownCompany(sp.id, mode: m.id), isCurrent: isCur,
                                              priceFactor: pf, yearlyVsMarket: spend * (1 - pf), yearlyVsCurrent: nil, discount: nil, relationship: nil, relationshipWord: nil, nextLevel: nil,
                                              vendorID: nil, quality: nil, reliability: delivered ?? "Not measured until it delivers",
                                              terms: "\(m.name), settled weekly between the two companies' books, VAT as on any sale in the country (reclaimed once the buyer is past the VAT threshold); never above the usual price",
                                              delivery: k.local ? "Same city" : "Same country", risks: risks, blocked: nil))
            }
        }
        if let a = acctLink, let c = AccountSupply.candidates(state, buyer: co.id, kind: k.id, data: data).first(where: { $0.accountID == a.accountID }) {
            // Kept only while an earlier deal runs; new ones are not offered.
            options.append(SupplierOption(id: "c:\(c.accountID)", kind: .businessCustomer, name: c.accountName, subtitle: "Business customer of \(c.ownerCompanyName)",
                                          change: .businessCustomer(c.accountID), isCurrent: true, priceFactor: c.priceFactor, yearlyVsMarket: c.yearlySaving, yearlyVsCurrent: nil,
                                          discount: nil, relationship: c.relationship, relationshipWord: Rivals.relationshipWord(c.relationship), nextLevel: nil, vendorID: nil,
                                          quality: nil, reliability: "Warms every week you buy", terms: "2% below the usual price, plus your relationship discount",
                                          delivery: k.local ? "Same city" : "Same country", risks: [], blocked: nil))
        }
        if let curPf = options.first(where: { $0.isCurrent })?.priceFactor {
            for i in options.indices { options[i].yearlyVsCurrent = options[i].priceFactor.map { spend * (curPf - $0) } }
        }
        var none: String?
        if !options.contains(where: { $0.kind == .ownCompany }) {
            let names = k.suppliers.prefix(4).compactMap { data.catalog[$0]?.name.lowercased() }
            none = "None of your companies provides this yet. A " + (names.isEmpty ? "matching" : names.joined(separator: " or a ")) + " company of yours"
                + (k.local ? " in the same city" : " in the same country") + " could."
        }
        var what = "A service or input this trade buys; one of your own companies can provide it"
        if k.delivered {
            let on = co.value("sw33")["on"]["platform"].bool
            what = "Couriers that take delivery orders to customers. The delivery add-on only brings customers for the orders that get delivered, and you pay for each delivery. "
                + (on ? "The add-on is on." : "The add-on is off, so nothing is delivered and nothing is paid.")
        }
        return SupplierInput(id: k.id, title: k.name, what: what, yearlySpend: spend,
                             current: options.first { $0.isCurrent }, options: options, noOwnProvider: none)
    }

    @discardableResult
    mutating func switchSupplier(companyID: Int, input: String, to change: SupplierSwitch) -> SupplierSwitchResult {
        var r = SupplierSwitchResult.unknown
        update { s, d, _ in
            guard let co = s.company(companyID), co.status.isLive else { return }
            if let std = SupplyDeals.franchiseStandard(co, input: input) {
                r = std == change ? SupplyDeals.perform(&s, d, companyID: companyID, input: input, to: change) : .governed
                return
            }
            if SupplyDeals.governedBy(s, co, input: input) != nil { r = .governed; return }
            r = SupplyDeals.perform(&s, d, companyID: companyID, input: input, to: change)
            if r == .ok { Tutorial.advance(&s, from: .pickSupplier) }
        }
        return r
    }

    @discardableResult
    mutating func negotiateSupplier(companyID: Int, input: String, vendorID: String, ask: Double) -> SupplyDeals.Talk {
        var r = SupplyDeals.Talk.notAllowed
        update { s, d, _ in r = SupplyDeals.negotiate(&s, d, companyID: companyID, input: input, vendorID: vendorID, ask: ask) }
        return r
    }

    @discardableResult
    mutating func setGoodsPaymentTerms(companyID: Int, term: String?) -> Bool {
        var ok = false
        update { s, d, _ in ok = SupplyTerms.setGoodsTerm(&s, companyID: companyID, term: term, data: d) }
        return ok
    }

    @discardableResult
    mutating func setRepairPaymentTerms(companyID: Int, term: String?) -> Bool {
        var ok = false
        update { s, d, _ in ok = SupplyTerms.setRepairTerm(&s, companyID: companyID, term: term, data: d) }
        return ok
    }

    @discardableResult
    mutating func setSupplyPaymentTerms(companyID: Int, input: String, term: String?) -> Bool {
        var ok = false
        update { s, _, _ in ok = IntercompanySupply.setTerms(&s, buyer: companyID, kind: input, term: term) }
        return ok
    }

    func supplierInvoices(companyID: Int) -> [SupplyTerms.Invoice] { SupplyTerms.invoices(state, buyer: companyID) }
}
