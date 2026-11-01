import Foundation
import GameCore
import Countries
import Finance

/// Choosing and using the accountant, law firm and insurer of a company, including your own group firms, and the
/// insurance policies a company holds. Originals: `pickLaw`, `pickInsurer`, `pickAccountant`, `insrMult`, `insrPay`, `lawWeek`
/// (engine/suppliers/providers.js, engine/company/company.js), `ownProv`, `pickOwn`, `ownFirms` (engine/suppliers/own_group.js)
/// and the actions `provpick`, `ownpick`, `toggleins` (ui/screens/providers.js, ui/company/view.js).
public enum Advisers {
    public enum Kind: String, CaseIterable, Sendable {
        case accountant = "acc", law, insurer = "ins"
        /// The trade a group company must be to serve as this provider. Original: `ownFirms`.
        var ownTrade: String { switch self { case .accountant: return "acctfirm"; case .law: return "law"; case .insurer: return "insco" } }
        /// The field of the company record that holds the choice.
        var field: String { self == .insurer ? "insr" : self == .accountant ? "acc" : "law" }
    }

    public enum Result: Equatable, Sendable { case done, removed, unknown, needInsurer }

    // MARK: Reading

    /// The providers on offer in the company's country. Original: `poolFor(co.country)`.
    public static func pool(_ s: inout GameState, companyID: Int, kind: Kind, data: GameData) -> [JSONValue] {
        guard let co = s.company(companyID) else { return [] }
        let p = Providers.pool(for: co.countryCode, state: &s, countries: data.countries)
        switch kind { case .accountant: return p.accountants; case .law: return p.lawyers; case .insurer: return p.insurers }
    }

    public static func current(_ co: Company, _ kind: Kind) -> JSONValue { co.value(kind.field) }

    /// Companies of yours that can serve as the provider. Original: `ownFirms`.
    public static func ownFirms(_ s: GameState, for companyID: Int, kind: Kind) -> [Company] {
        s.companies.filter { $0.type == kind.ownTrade && $0.status == .open && $0.id != companyID }
    }

    /// A group firm judged by the same numbers as the others, with a group discount. Original: `ownProv`.
    public static func ownProvider(_ s: GameState, kind: Kind, firm oc: Company, data: GameData) -> JSONValue {
        let r = Pricing.rating(oc)
        let q = Providers.quality(fromRating: r)
        let wage = data.countries[oc.countryCode]?.wageLevel ?? 1
        var p: [String: JSONValue] = ["id": .string("own\(oc.id)"), "name": .string(oc.name + " (yours)"), "rating": .number(r),
                                      "q": .number(0.4 + q * 0.52), "own": .number(Double(oc.id)), "w0": .number(Double(s.week))]
        let reviews = jsRound(oc.num("rvN") != 0 ? oc.num("rvN") : oc.lastWeekUnits / 20)
        if reviews != 0 { p["reviews"] = .number(reviews) }
        let cur = data.countries[oc.countryCode].map { Currency(country: $0, rates: ExchangeRates()) }
        func rnl(_ v: Double) -> Double { cur?.roundedStep(v, about: 100) ?? (v / 100).rounded() * 100 }
        switch kind {
        case .accountant:
            p["tier"] = ""; p["fee"] = .number(rnl(1400 * (0.7 + q * 1.9) * wage * 0.85)); p["err"] = .number(max(0.015, 0.14 - q * 0.12))
        case .law:
            p["fee"] = .number(rnl(3500 * (0.7 + q * 2.4) * wage * 0.85))
        case .insurer:
            p["premM"] = .number(jsRound((0.82 + q * 0.35 - 0.08) * 100) / 100); p["payM"] = .number(jsRound((0.7 + q * 0.29) * 100) / 100); p["fee"] = 0
        }
        return .object(p)
    }

    // MARK: Choosing

    /// Hire a provider (providerID 0 removes a law firm or an insurer). Original: `ACT.provpick`.
    @discardableResult
    public static func pick(_ s: inout GameState, companyID: Int, kind: Kind, providerID: Int, data: GameData) -> Result {
        guard let i = s.companyIndex(companyID) else { return .unknown }
        if providerID == 0 && kind != .accountant { s.companies[i].set(kind.field, .null); return .removed }
        guard let a = pool(&s, companyID: companyID, kind: kind, data: data).first(where: { $0["id"].int == providerID }) ?? (kind == .accountant ? pool(&s, companyID: companyID, kind: kind, data: data).dropFirst().first : nil) else { return .unknown }
        switch kind {
        case .accountant:
            if s.companies[i].value("acc")["id"].int == a["id"].int { return .done }
            s.companies[i].set("acc", .object(["id": a["id"], "name": a["name"], "tier": a["tier"], "fee": a["fee"], "q": a["q"], "err": a["err"], "rating": a["rating"], "w0": .number(Double(s.week))]))
            markAccountantDocument(&s, i)
        case .law:
            s.companies[i].set("law", .object(["id": a["id"], "name": a["name"], "fee": a["fee"], "q": a["q"], "rating": a["rating"], "w0": .number(Double(s.week))]))
        case .insurer:
            s.companies[i].set("insr", .object(["id": a["id"], "name": a["name"], "premM": a["premM"], "payM": a["payM"], "rating": a["rating"]]))
        }
        return .done
    }

    /// Use one of your own firms as provider. Original: `pickOwn`.
    @discardableResult
    public static func pickOwn(_ s: inout GameState, companyID: Int, kind: Kind, firmID: Int, data: GameData) -> Result {
        guard let i = s.companyIndex(companyID), let oc = s.company(firmID), oc.status == .open, oc.type == kind.ownTrade, oc.id != companyID else { return .unknown }
        let p = ownProvider(s, kind: kind, firm: oc, data: data)
        let w0 = JSONValue.number(Double(s.week)), own = JSONValue.number(Double(oc.id))
        switch kind {
        case .accountant:
            s.companies[i].set("acc", .object(["id": p["id"], "name": p["name"], "tier": p["tier"], "fee": p["fee"], "q": p["q"], "err": p["err"], "rating": p["rating"], "own": own, "w0": w0]))
            markAccountantDocument(&s, i)
        case .law:
            s.companies[i].set("law", .object(["id": p["id"], "name": p["name"], "fee": p["fee"], "q": p["q"], "rating": p["rating"], "own": own, "w0": w0]))
        case .insurer:
            s.companies[i].set("insr", .object(["id": p["id"], "name": p["name"], "premM": p["premM"], "payM": p["payM"], "rating": p["rating"], "own": own]))
        }
        return .done
    }

    /// The accountant agreement is held from the moment a firm is chosen. Original: `pickAccountant` (the `acctr` document).
    static func markAccountantDocument(_ s: inout GameState, _ i: Int) {
        var docs = s.companies[i].value("docs")
        docs["accountant_agreement"] = .object(["st": "ok", "done": .number(Double(s.week)), "ok": .number(Double(s.week))])
        s.companies[i].set("docs", docs)
    }

    /// Switch one insurance policy on or off. Needs an insurer. Original: `ACT.toggleins`.
    @discardableResult
    public static func togglePolicy(_ s: inout GameState, companyID: Int, product: String) -> Result {
        guard let i = s.companyIndex(companyID) else { return .unknown }
        var ins = s.companies[i].value("ins")
        if !ins[product].bool && s.companies[i].value("insr").isNull { return .needInsurer }
        ins[product] = ins[product].bool ? 0 : 1
        s.companies[i].set("ins", ins)
        if s.companies[i].managerID != nil {
            var own = s.companies[i].value("insOwn"); own[product] = 1; s.companies[i].set("insOwn", own)
        }
        return .done
    }

    // MARK: In the weekly turn

    /// Premium multiplier of the chosen insurer. Original: `insrMult`.
    public static func premiumFactor(_ co: Company) -> Double { co.value("insr").isNull ? 1 : co.value("insr")["premM"].double }
    /// How reliably the insurer pays a claim. Original: `insrPay`.
    public static func payoutReliability(_ co: Company) -> Double { co.value("insr").isNull ? 0.93 : co.value("insr")["payM"].double }

    /// The weekly legal fee, and the fees of your own firms. Original: `lawWeek`; `accWeek` (own accountant income).
    static func weekly(_ s: inout GameState, _ i: Int, accountantFee amt: Double) {
        let co = s.companies[i]
        if !co.value("law").isNull {
            let f = co.value("law")["fee"].double * 12 / 52 * (s.hasHeadOffice("law") ? 0.85 : 1)
            Payments.companyPays(&s, companyID: co.id, amount: f, category: "oth")
            if let o = ownerFirm(s, co.value("law")), f > 0 { Payments.companyReceives(&s, companyID: o, amount: f, category: "rev", label: "Legal fees from \(co.name)") }
        }
        if amt > 0, let o = ownerFirm(s, co.value("acc")), o != co.id {
            Payments.companyReceives(&s, companyID: o, amount: amt, category: "rev", label: "Accounting for \(co.name)")
        }
    }

    /// The premiums go to your own insurer when you chose it. Original: `insWeek`.
    static func premiumsPaid(_ s: inout GameState, _ i: Int, total t: Double) {
        guard t > 0, let o = ownerFirm(s, s.companies[i].value("insr")) else { return }
        Payments.companyReceives(&s, companyID: o, amount: t * 0.85, category: "rev", label: "Premium from \(s.companies[i].name)")
        if let oi = s.companyIndex(o) {
            var fm = s.companies[oi].value("fm"); fm["prem"] = .number(fm["prem"].double + t * 0.85); s.companies[oi].set("fm", fm)
        }
    }

    /// An insurance claim paid out to a company: the insurer may haggle, and your own insurer carries the cost.
    /// Original: the `fx.loss` branch of `applyFx` (engine/events/engine.js). Returns the amount paid.
    public static func claimPaid(_ s: inout GameState, _ i: Int, paid: Double) -> Double {
        var paid = paid
        if paid > 0 && s.random.chance(1 - payoutReliability(s.companies[i])) {
            paid = jsRound(paid * s.random.range(0.3, 0.7))
            s.note("Your insurer paid only part of the claim at \(s.companies[i].name).", tone: "bad", companyID: s.companies[i].id)
        }
        if paid > 0, let o = ownerFirm(s, s.companies[i].value("insr")), let oi = s.companyIndex(o) {
            Payments.companyPays(&s, companyID: o, amount: paid, category: "oth", label: "Claim paid for \(s.companies[i].name)")
            var fm = s.companies[oi].value("fm"); fm["claims"] = .number(fm["claims"].double + paid); s.companies[oi].set("fm", fm)
        }
        return paid
    }

    private static func ownerFirm(_ s: GameState, _ provider: JSONValue) -> Int? {
        guard !provider["own"].isNull, let o = s.company(provider["own"].int), o.status == .open else { return nil }
        return o.id
    }
}
