import Foundation
import GameCore
import Countries
import Finance

public enum Advisers {
    public enum Kind: String, CaseIterable, Sendable {
        case law, insurer = "ins"
        var ownTrade: String { switch self { case .law: return "law"; case .insurer: return "insco" } }
        var field: String { self == .insurer ? "insr" : "law" }
    }

    public enum Result: Equatable, Sendable { case done, removed, unknown, needInsurer }

    public static func pool(_ s: inout GameState, companyID: Int, kind: Kind, data: GameData) -> [JSONValue] {
        guard let co = s.company(companyID) else { return [] }
        let p = Providers.pool(for: co.countryCode, state: &s, countries: data.countries)
        switch kind { case .law: return p.lawyers; case .insurer: return p.insurers }
    }

    public static func current(_ co: Company, _ kind: Kind) -> JSONValue { co.value(kind.field) }

    public static func ownFirms(_ s: GameState, for companyID: Int, kind: Kind) -> [Company] {
        s.companies.filter { $0.type == kind.ownTrade && $0.status == .open && $0.id != companyID }
    }

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
        case .law:
            p["fee"] = .number(rnl(3500 * (0.7 + q * 2.4) * wage * 0.85))
        case .insurer:
            p["premM"] = .number(jsRound((0.82 + q * 0.35 - 0.08) * 100) / 100); p["payM"] = .number(jsRound((0.7 + q * 0.29) * 100) / 100); p["fee"] = 0
        }
        return .object(p)
    }

    @discardableResult
    public static func pick(_ s: inout GameState, companyID: Int, kind: Kind, providerID: Int, data: GameData) -> Result {
        guard let i = s.companyIndex(companyID) else { return .unknown }
        if providerID == 0 { s.companies[i].set(kind.field, .null); return .removed }
        guard let a = pool(&s, companyID: companyID, kind: kind, data: data).first(where: { $0["id"].int == providerID }) else { return .unknown }
        switch kind {
        case .law:
            s.companies[i].set("law", .object(["id": a["id"], "name": a["name"], "fee": a["fee"], "q": a["q"], "rating": a["rating"], "w0": .number(Double(s.week))]))
        case .insurer:
            s.companies[i].set("insr", .object(["id": a["id"], "name": a["name"], "premM": a["premM"], "payM": a["payM"], "rating": a["rating"]]))
        }
        return .done
    }

    @discardableResult
    public static func pickOwn(_ s: inout GameState, companyID: Int, kind: Kind, firmID: Int, data: GameData) -> Result {
        guard let i = s.companyIndex(companyID), let oc = s.company(firmID), oc.status == .open, oc.type == kind.ownTrade, oc.id != companyID else { return .unknown }
        let p = ownProvider(s, kind: kind, firm: oc, data: data)
        let w0 = JSONValue.number(Double(s.week)), own = JSONValue.number(Double(oc.id))
        switch kind {
        case .law:
            s.companies[i].set("law", .object(["id": p["id"], "name": p["name"], "fee": p["fee"], "q": p["q"], "rating": p["rating"], "own": own, "w0": w0]))
        case .insurer:
            s.companies[i].set("insr", .object(["id": p["id"], "name": p["name"], "premM": p["premM"], "payM": p["payM"], "rating": p["rating"], "own": own]))
        }
        return .done
    }

    @discardableResult
    public static func togglePolicy(_ s: inout GameState, companyID: Int, product: String) -> Result {
        guard let i = s.companyIndex(companyID) else { return .unknown }
        var ins = s.companies[i].value("ins")
        if !ins[product].bool && s.companies[i].value("insr").isNull {
            s.companies[i].set("insr", .object(["id": .string("atlas"), "name": .string("Atlas Insurance"), "premM": .number(1.0), "payM": .number(0.95), "rating": .number(4.3)]))
        }
        let turningOn = !ins[product].bool
        ins[product] = ins[product].bool ? 0 : 1
        s.companies[i].set("ins", ins)
        recordPolicyNumber(&s, companyIndex: i, product: product, on: turningOn)
        if s.companies[i].managerID != nil {
            var own = s.companies[i].value("insOwn"); own[product] = 1; s.companies[i].set("insOwn", own)
        }
        return .done
    }

    static func recordPolicyNumber(_ s: inout GameState, companyIndex i: Int, product: String, on: Bool) {
        var nos = s.companies[i].value("polNo")
        if on {
            var r = HashedRandom("\(s.seed):pol:\(s.companies[i].id):\(product):\(s.week):\(s.day)")
            let digits: String = (0..<5).map { _ in String(Int(saturating: (r.next() * 10).rounded(.down))) }.joined()
            let no = "AT-" + String(GameCalendar.year(week: s.week)) + "-" + digits
            nos[product] = .object(["no": .string(no), "w": .number(Double(s.week)), "d": .number(Double(s.day))])
            s.companies[i].set("polNo", nos)
        } else if !nos[product].isNull {
            nos[product] = .null
            s.companies[i].set("polNo", .object(nos.object.filter { !$0.value.isNull }))
        }
    }

    public static func policyRecord(_ co: Company, product: String) -> (number: String, week: Int, day: Int)? {
        let r = co.value("polNo")[product]
        guard !r.isNull, co.value("ins")[product].bool else { return nil }
        return (r["no"].string, r["w"].int, r["d"].int)
    }

    public static func premiumFactor(_ co: Company) -> Double { co.value("insr").isNull ? 1 : co.value("insr")["premM"].double }
    public static func payoutReliability(_ co: Company) -> Double { co.value("insr").isNull ? 0.93 : co.value("insr")["payM"].double }

    static func weekly(_ s: inout GameState, _ i: Int) {
        let co = s.companies[i]
        if !co.value("law").isNull {
            let f = co.value("law")["fee"].double * 12 / 52 * (s.hasHeadOffice("law") ? 0.85 : 1)
            Payments.companyPays(&s, companyID: co.id, amount: f, category: "oth")
            if let o = ownerFirm(s, co.value("law")), f > 0 { Payments.companyReceives(&s, companyID: o, amount: f, category: "rev", label: "Legal fees from \(co.name)") }
        }
    }

    static func premiumsPaid(_ s: inout GameState, _ i: Int, total t: Double) {
        guard t > 0, let o = ownerFirm(s, s.companies[i].value("insr")) else { return }
        Payments.companyReceives(&s, companyID: o, amount: t * 0.85, category: "rev", label: "Premium from \(s.companies[i].name)")
        if let oi = s.companyIndex(o) {
            var fm = s.companies[oi].value("fm"); fm["prem"] = .number(fm["prem"].double + t * 0.85); s.companies[oi].set("fm", fm)
        }
    }

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
