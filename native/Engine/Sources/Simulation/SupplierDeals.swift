import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// The Suppliers section of a company: for each input the company uses (goods, repairs, and every service one of your own companies could
/// supply) who provides it now, the real options with price, terms, reliability and risks, and the one action that switches provider.
/// Everything is read from the existing rules (`Suppliers`, `Sourcing`, `IntercompanySupply`, `AccountSupply`); nothing is decided here.
/// Prices are shown against the market price (1 = market) and yearly amounts are estimates from the company's last three months, in its currency.

public enum SupplierProviderKind: String, Equatable, Sendable { case outside, outsideVendor, ownCompany, businessCustomer, repairVendor, noneFixed }

public struct SupplierOption: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: SupplierProviderKind
    public var name: String
    public var subtitle: String
    public var change: SupplierSwitch
    public var isCurrent: Bool
    /// Price against the market price (1 = market). nil when the option has no price of its own (repairs: see `discount`).
    public var priceFactor: Double?
    /// Yearly saving (positive) or extra cost (negative) against buying at the market price, and against the provider used now.
    public var yearlyVsMarket: Double?
    public var yearlyVsCurrent: Double?
    /// Discount on bills (repairs) or on every order (goods).
    public var discount: Double?
    public var relationship: Double?
    public var relationshipWord: String?
    /// What the next relationship level would bring.
    public var nextLevel: String?
    /// Supplier id for "take to lunch" (named outside suppliers only).
    public var vendorID: String?
    public var quality: String?
    public var reliability: String
    public var terms: String
    public var delivery: String
    public var risks: [String]
    /// Why this option cannot be chosen now.
    public var blocked: String?
    /// An outside supplier: the price can be negotiated (a talk through the shared Negotiation module).
    public var negotiable = false
    /// The extra discount a negotiated deal gives while it lasts (current supplier only).
    public var dealExtra: Double?
    /// The supplier will not talk until this week (they ended the last talk).
    public var coolingUntil: Int?
}

/// One way to pay for an input.
public struct PaymentTermChoice: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var detail: String
    public var isCurrent: Bool
    /// Why it is not offered now.
    public var blocked: String?
}

public struct SupplierInput: Identifiable, Equatable, Sendable {
    /// "goods", "repair" or the id of an intercompany supply kind ("clean", "freight" ...).
    public var id: String
    public var title: String
    public var what: String
    public var yearlySpend: Double?
    public var current: SupplierOption?
    public var options: [SupplierOption]
    /// Set when no provider of your own exists: what kind of company would provide it.
    public var noOwnProvider: String?
    /// How the input is paid for now and the other ways (goods from an outside supplier; an own company supplying it). Empty when there is no choice.
    public var paymentTerms: [PaymentTermChoice] = []
    /// Set when the chain's rule fixes this input for the company.
    public var governedBy: String?
}

public extension GameEngine {
    // MARK: Reading

    func supplierInputs(companyID: Int) -> [SupplierInput] {
        guard let co = state.company(companyID), co.status.isLive, let bd = data.catalog[co.type] else { return [] }
        var out: [SupplierInput] = []
        if Suppliers.hasGoods(bd, co) { out.append(supplierGoodsInput(co, bd)) }
        if !bd.equipment.isEmpty { out.append(supplierRepairInput(co)) }
        for k in IntercompanySupply.kindsFor(co) { out.append(supplierKindInput(co, k)) }
        for n in out.indices {
            out[n].governedBy = SupplyDeals.governedBy(state, co, input: out[n].id)
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
        if input == "goods" {
            guard let v = Suppliers.goodsVendor(state, company: co, data: data) else { return [] }
            let agreed = SupplyTerms.agreedGoodsTerm(co)
            let active = SupplyTerms.goodsTerm(state, co, data: data)?.id ?? "monthly"
            return SupplyTerms.vendorTerms.map { t in
                var detail = t.isMonthEnd ? "Bills are paid on the last day of the month, as usual." : t.days == 0 ? "Each delivery is paid on the spot." : "Each delivery is invoiced and paid \(t.days) days later."
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

    /// Lighter read for chain level: the name of the provider each input uses today, by input id.
    func supplierCurrentProviders(companyID: Int) -> [(inputID: String, title: String, provider: String)] {
        guard let co = state.company(companyID), co.status.isLive, let bd = data.catalog[co.type] else { return [] }
        var out: [(inputID: String, title: String, provider: String)] = []
        if Suppliers.hasGoods(bd, co) { out.append((inputID: "goods", title: "Goods", provider: Suppliers.goodsVendor(state, company: co, data: data)?.name ?? "Market")) }
        if !bd.equipment.isEmpty { out.append((inputID: "repair", title: "Repairs and upkeep", provider: Suppliers.repairVendor(state, company: co, data: data)?.name ?? "No fixed supplier")) }
        for k in IntercompanySupply.kindsFor(co) {
            if let l = IntercompanySupply.link(state, buyer: co.id, kind: k.id), let s = state.company(l.supplierID) {
                out.append((inputID: k.id, title: k.name, provider: s.name))
            } else if let a = AccountSupply.link(state, buyer: co.id, kind: k.id) {
                let n = AccountSupply.candidates(state, buyer: co.id, kind: k.id, data: data).first { $0.accountID == a.accountID }?.accountName ?? "Business customer"
                out.append((inputID: k.id, title: k.name, provider: n))
            } else {
                out.append((inputID: k.id, title: k.name, provider: "Outside suppliers"))
            }
        }
        return out
    }

    private func supplierYearlyRevenue(_ co: Company) -> Double {
        let h = co.monthlyHistory.suffix(3)
        return h.isEmpty ? co.lastWeekRevenue * 52 : h.reduce(0.0) { $0 + $1.revenue } / Double(h.count) * 12
    }

    private func supplierPct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }

    private func supplierVendorOption(_ v: Suppliers.Vendor, id: String, kind: SupplierProviderKind, change: SupplierSwitch, current: Bool) -> SupplierOption {
        let next = Suppliers.nextDiscountTier(v.relationship)
        let agreed = Suppliers.agreement(state, scope: "goods") == v.id
        let terms = v.discount > 0 ? "\(supplierPct(v.discount)) off every order from your relationship" + (agreed ? " (includes the board agreement)" : "") : "List price, no relationship discount yet"
        return SupplierOption(id: id, kind: kind, name: v.name, subtitle: "\(v.owner) · \(v.relationshipWord)", change: change, isCurrent: current, priceFactor: nil,
                              yearlyVsMarket: nil, yearlyVsCurrent: nil, discount: v.discount, relationship: v.relationship, relationshipWord: v.relationshipWord,
                              nextLevel: next.map { "\($0.word) (from \(Int($0.from.rounded()))): \(supplierPct($0.discount)) off every order" }, vendorID: v.id,
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
            x.risks = ["Outside supplier: price rises, failures and cut deliveries can hit you."]
            if o.current && auto { x.subtitle += " · picked by " + (co.managerID != nil ? "your manager" : "the market") }
            return x
        }
        if let a = Suppliers.agreement(state, scope: "goods"), auto, let i = options.firstIndex(where: { $0.vendorID == a }) {
            options[i].subtitle += " · board agreement for all companies"
        }
        let managerRisk = Sourcing.summary(state, company: co, data: data, classes: marketing.goodsClasses)?.managerMayOverpay ?? false
        let autoOpt = SupplierOption(id: "v:auto", kind: .outside, name: co.managerID != nil ? "Let the manager choose" : "Let the market choose", subtitle: "Re-picked every 26 weeks",
                                     change: .goodsVendor("auto"), isCurrent: auto, priceFactor: nil, yearlyVsMarket: nil, yearlyVsCurrent: nil, discount: nil, relationship: nil,
                                     relationshipWord: nil, nextLevel: nil, vendorID: nil, quality: nil, reliability: "Depends on who picks",
                                     terms: "Best offer by discount and quality when the buyer is skilled, otherwise whoever comes first",
                                     delivery: "With your regular orders", risks: managerRisk ? ["Your manager is not always good at finding the best deal."] : [], blocked: nil)
        return SupplierInput(id: "goods", title: "Goods", what: "What the business sells or uses up: stock, ingredients, materials", yearlySpend: spend,
                             current: options.first { $0.isCurrent }, options: options + [autoOpt], noOwnProvider: nil)
    }

    private func supplierRepairInput(_ co: Company) -> SupplierInput {
        let cands = Suppliers.candidates(state, company: co, scope: "fix", data: data)
        let cur = Suppliers.repairVendor(state, company: co, data: data)
        func opt(_ v: Suppliers.Vendor) -> SupplierOption {
            var x = supplierVendorOption(v, id: "f:" + v.id, kind: .repairVendor, change: .repairVendor(v.id), current: v.id == cur?.id)
            x.terms = v.discount > 0 ? "\(supplierPct(v.discount)) off repair and upkeep bills" : "Standard bills, no discount yet"
            x.risks = ["Outside supplier."]
            return x
        }
        var options: [SupplierOption] = cands.sorted { $0.discount > $1.discount }.map(opt)
        if let c = cur, !options.contains(where: { $0.vendorID == c.id }) { options.insert(opt(c), at: 0) }
        let none = SupplierOption(id: "f:none", kind: .noneFixed, name: "No fixed supplier", subtitle: "Standard bills", change: .repairVendor("auto"), isCurrent: cur == nil,
                                  priceFactor: nil, yearlyVsMarket: nil, yearlyVsCurrent: nil, discount: 0, relationship: nil, relationshipWord: nil, nextLevel: nil, vendorID: nil,
                                  quality: nil, reliability: "n/a", terms: "Repairs at standard prices", delivery: "As needed", risks: [], blocked: nil)
        let all = options + [none]
        return SupplierInput(id: "repair", title: "Repairs and upkeep", what: "Servicing of your equipment: the discount cuts every upkeep and service bill", yearlySpend: nil,
                             current: all.first { $0.isCurrent }, options: all, noOwnProvider: nil)
    }

    private func supplierKindInput(_ co: Company, _ k: IntercompanySupply.Kind) -> SupplierInput {
        let spend = IntercompanySupply.yearlySpend(co, k)
        let link = IntercompanySupply.link(state, buyer: co.id, kind: k.id)
        let acctLink = AccountSupply.link(state, buyer: co.id, kind: k.id)
        let cogs = k.category == "cogs"
        let outsideRisk = cogs ? ["Exposed to outside supplier events: price rises, failures, cut deliveries."] : []
        // A delivery service: the add-on's data says how reliable an outside courier is (the share of orders that reach the customer).
        let dway = k.delivered ? IntercompanySupply.deliveryWay(co.type, data.balance) : nil
        let outsideRel = dway.map { "Outside courier: \(Int((($0.options["rel"] ?? 1) * 100).rounded()))% of orders reach the customer" }
        var options: [SupplierOption] = []
        options.append(SupplierOption(id: "out", kind: .outside, name: k.delivered ? "Outside courier" : "Outside suppliers", subtitle: "The market", change: .outside, isCurrent: link == nil && acctLink == nil,
                                      priceFactor: 1, yearlyVsMarket: 0, yearlyVsCurrent: nil, discount: nil, relationship: nil, relationshipWord: nil, nextLevel: nil, vendorID: nil,
                                      quality: nil, reliability: outsideRel ?? "Market supply",
                                      terms: k.delivered ? "Market price per delivered order (\(supplierPct(k.buyers[co.type] ?? 0)) of the order value), paid as you deliver" : "Market price, paid as you buy",
                                      delivery: k.delivered ? "Orders that are not delivered bring no customers" : "Whoever the market offers", risks: outsideRisk, blocked: nil))
        for sp in IntercompanySupply.suppliers(state, for: co, kind: k) {
            for m in IntercompanySupply.modes {
                let pf = IntercompanySupply.priceFactor(mode: m.id, supplier: sp, data: data, perkCut: Ambitions.supplyCostCut(state, data))
                let isCur = link?.supplierID == sp.id && link?.mode == m.id
                var risks = ["If \(sp.name) is short of people or closes, you pay for emergency supply (+20%) and below 80% delivered your reputation suffers."]
                if !k.noCapacity { risks.append("\(sp.name) holds back part of its own capacity for you.") }
                if m.id != "mkt" && pf >= 1 { risks.append("\(sp.name) runs at no margin today, so this mode gives no saving yet.") }
                let delivered: String? = isCur ? link.map { "\(Int(($0.lastShare * 100).rounded()))% delivered last week" } : nil
                options.append(SupplierOption(id: "o:\(sp.id):\(m.id)", kind: .ownCompany, name: sp.name, subtitle: "Your company · \(m.name)", change: .ownCompany(sp.id, mode: m.id), isCurrent: isCur,
                                              priceFactor: pf, yearlyVsMarket: spend * (1 - pf), yearlyVsCurrent: nil, discount: nil, relationship: nil, relationshipWord: nil, nextLevel: nil,
                                              vendorID: nil, quality: nil, reliability: delivered ?? "Not measured until it delivers",
                                              terms: "\(m.name), settled weekly between the two companies' books, no VAT; never above the outside price",
                                              delivery: k.local ? "Same city" : "Same country", risks: risks, blocked: nil))
            }
        }
        for c in AccountSupply.candidates(state, buyer: co.id, kind: k.id, data: data) {
            let isCur = acctLink?.accountID == c.accountID
            let next = Suppliers.nextDiscountTier(c.relationship)
            let word = Rivals.relationshipWord(c.relationship)
            options.append(SupplierOption(id: "c:\(c.accountID)", kind: .businessCustomer, name: c.accountName, subtitle: "Business customer of \(c.ownerCompanyName) · \(word)",
                                          change: .businessCustomer(c.accountID), isCurrent: isCur, priceFactor: c.priceFactor, yearlyVsMarket: c.yearlySaving, yearlyVsCurrent: nil, discount: nil,
                                          relationship: c.relationship, relationshipWord: word,
                                          nextLevel: next.map { "\($0.word) (from \(Int($0.from.rounded()))): \(supplierPct($0.discount)) better price" },
                                          vendorID: nil, quality: nil, reliability: "Warms every week you buy",
                                          terms: "2% below the outside price, plus your relationship discount; weekly rebate booked as a lower cost",
                                          delivery: k.local ? "Same city" : "Same country",
                                          risks: ["Ends if they stop supplying; you buy outside again.", "Replaces any own-company supply of this input."],
                                          blocked: c.canBuy ? nil : "Get to know them better first (familiar or closer)."))
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

    // MARK: The actions

    /// Switch the provider of one input at the supplier's list terms. `input` is the id from `supplierInputs`. A store whose chain fixes the input
    /// cannot switch on its own (the chain's rule does it, `setChainSupplier`).
    @discardableResult
    mutating func switchSupplier(companyID: Int, input: String, to change: SupplierSwitch) -> SupplierSwitchResult {
        var r = SupplierSwitchResult.unknown
        update { s, d, _ in
            guard let co = s.company(companyID), co.status.isLive else { return }
            if SupplyDeals.governedBy(s, co, input: input) != nil { r = .governed; return }
            r = SupplyDeals.perform(&s, d, companyID: companyID, input: input, to: change)
        }
        return r
    }

    /// Ask an outside supplier for an extra discount (a share: 0.02 = two points) and use them. Own companies, business customers and "outside"
    /// need no talk. The answer is an agreement, the supplier's own figure to accept or counter, a refusal, or the end of the talks.
    @discardableResult
    mutating func negotiateSupplier(companyID: Int, input: String, vendorID: String, ask: Double) -> SupplyDeals.Talk {
        var r = SupplyDeals.Talk.notAllowed
        update { s, d, _ in r = SupplyDeals.negotiate(&s, d, companyID: companyID, input: input, vendorID: vendorID, ask: ask) }
        return r
    }

    /// How the company pays its goods supplier (nil or "monthly" = the usual monthly bill).
    @discardableResult
    mutating func setGoodsPaymentTerms(companyID: Int, term: String?) -> Bool {
        var ok = false
        update { s, d, _ in ok = SupplyTerms.setGoodsTerm(&s, companyID: companyID, term: term, data: d) }
        return ok
    }

    /// How the company pays one of your own companies that supplies an input (nil or "weekly" = settled every week).
    @discardableResult
    mutating func setSupplyPaymentTerms(companyID: Int, input: String, term: String?) -> Bool {
        var ok = false
        update { s, _, _ in ok = IntercompanySupply.setTerms(&s, buyer: companyID, kind: input, term: term) }
        return ok
    }

    /// Open supplier invoices of a company (what it owes on terms), oldest due first.
    func supplierInvoices(companyID: Int) -> [SupplyTerms.Invoice] { SupplyTerms.invoices(state, buyer: companyID) }
}
