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

/// What choosing an option does. One engine action, `switchSupplier`, carries it out.
public enum SupplierSwitch: Equatable, Sendable {
    /// A named outside supplier of goods ("auto" lets the manager or market choose).
    case goodsVendor(String)
    /// A named outside repair supplier ("auto" = none fixed).
    case repairVendor(String)
    /// Back to outside suppliers (for an input that your own companies could supply).
    case outside
    case ownCompany(Int, mode: String)
    case businessCustomer(Int)
}

public enum SupplierSwitchResult: Equatable, Sendable { case ok, notAllowed, notKnownWell, unknown }

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
}

public extension GameEngine {
    // MARK: Reading

    func supplierInputs(companyID: Int) -> [SupplierInput] {
        guard let co = state.company(companyID), co.status.isLive, let bd = data.catalog[co.type] else { return [] }
        var out: [SupplierInput] = []
        if Suppliers.hasGoods(bd, co) { out.append(supplierGoodsInput(co, bd)) }
        if !bd.equipment.isEmpty { out.append(supplierRepairInput(co)) }
        for k in IntercompanySupply.kindsFor(co) { out.append(supplierKindInput(co, k)) }
        return out
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
        var options: [SupplierOption] = []
        options.append(SupplierOption(id: "out", kind: .outside, name: "Outside suppliers", subtitle: "The market", change: .outside, isCurrent: link == nil && acctLink == nil,
                                      priceFactor: 1, yearlyVsMarket: 0, yearlyVsCurrent: nil, discount: nil, relationship: nil, relationshipWord: nil, nextLevel: nil, vendorID: nil,
                                      quality: nil, reliability: "Market supply", terms: "Market price, paid as you buy", delivery: "Whoever the market offers", risks: outsideRisk, blocked: nil))
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
        return SupplierInput(id: k.id, title: k.name, what: "A service or input this trade buys; one of your own companies can provide it", yearlySpend: spend,
                             current: options.first { $0.isCurrent }, options: options, noOwnProvider: none)
    }

    // MARK: The one action

    /// Switch the provider of one input. `input` is the id from `supplierInputs`.
    @discardableResult
    mutating func switchSupplier(companyID: Int, input: String, to change: SupplierSwitch) -> SupplierSwitchResult {
        var r = SupplierSwitchResult.unknown
        update { s, d, _ in
            guard let co = s.company(companyID), co.status.isLive else { return }
            switch change {
            case .goodsVendor(let id):
                guard input == "goods", id == "auto" || Suppliers.candidates(s, company: co, scope: "goods", data: d).contains(where: { $0.id == id }) else { r = .notAllowed; return }
                Suppliers.chooseGoodsVendor(&s, companyID: companyID, vendorID: id); r = .ok
            case .repairVendor(let id):
                guard input == "repair", id == "auto" || Suppliers.candidates(s, company: co, scope: "fix", data: d).contains(where: { $0.id == id }) else { r = .notAllowed; return }
                Suppliers.chooseRepairVendor(&s, companyID: companyID, vendorID: id); r = .ok
            case .outside:
                guard IntercompanySupply.kind(input) != nil else { r = .notAllowed; return }
                IntercompanySupply.clearSupplier(&s, buyer: companyID, kind: input)
                AccountSupply.clear(&s, buyer: companyID, kind: input); r = .ok
            case .ownCompany(let sid, let mode):
                guard let k = IntercompanySupply.kind(input), IntercompanySupply.suppliers(s, for: co, kind: k).contains(where: { $0.id == sid }) else { r = .notAllowed; return }
                r = IntercompanySupply.setSupplier(&s, buyer: companyID, kind: input, supplier: sid, mode: mode) ? .ok : .notAllowed
            case .businessCustomer(let aid):
                guard IntercompanySupply.kind(input) != nil else { r = .notAllowed; return }
                switch AccountSupply.set(&s, buyer: companyID, kind: input, accountID: aid, data: d) {
                case .ok: r = .ok
                case .notKnownWell: r = .notKnownWell
                case .notAllowed: r = .notAllowed
                case .unknownAccount: r = .unknown
                }
            }
        }
        return r
    }
}
