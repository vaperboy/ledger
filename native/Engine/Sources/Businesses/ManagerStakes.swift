import Foundation
import GameCore
import Countries
import Finance

/// Owners and the big meeting. Buying back a co-owner's stake and the dividend policy of a limited company (own27), and the big offers to buy
/// a share of another group that come when your net worth is large (bigmeet). Original: features/company/owner_investors.js (`own27buy`, `own27pol`),
/// features/player/selling_startups_and_crisis.js (`bigWeek`, `bigacc`, `bigctr`, `bigwalk`, `stakesWeek`). Stakes are in `rest["stakes"]`, the offer in `rest["bigOff"]`.
extension ManagerModel {
    public static let dividendPolicies: [(key: String, label: String)] = [("none", "Keep it in the company"), ("low", "Pay out a little"), ("mid", "Pay out half"), ("high", "Pay out most")]

    public static func setDividendPolicy(_ s: inout GameState, companyID: Int, policy: String) {
        guard let i = s.companyIndex(companyID), dividendPolicies.contains(where: { $0.key == policy }) else { return }
        s.companies[i].set("dp27", policy)
    }

    /// What a co-owner wants for their stake: value, with a premium unless they are unhappy.
    public static func buyBackPrice(_ s: GameState, companyID: Int, holderName: String, data: GameData) -> Double? {
        guard let co = s.company(companyID), let h = co.value("holders").array.first(where: { $0["name"].string == holderName }) else { return nil }
        let v = max(0, Valuation.companyValue(co, state: s, trades: data.catalog))
        let sat = h["sat"].isNull ? 60 : h["sat"].double
        return World(state: s, data: data).currency(co).roundedStep(v * h["pct"].double / 100 * (sat < 40 ? 1.0 : 1.12), about: 1000)
    }

    @discardableResult
    public static func buyBackStake(_ s: inout GameState, companyID: Int, holderName: String, data: GameData) -> Bool {
        guard let i = s.companyIndex(companyID), let price = buyBackPrice(s, companyID: companyID, holderName: holderName, data: data), Payments.liquid(s) >= price else { return false }
        var H = s.companies[i].value("holders").array
        guard let k = H.firstIndex(where: { $0["name"].string == holderName }) else { return false }
        Payments.playerPays(&s, price, label: "Bought \(holderName)'s stake in \(s.companies[i].name)", companyID: companyID)
        s.companies[i].ownership = min(100, s.companies[i].ownership + H[k]["pct"].double)
        H.remove(at: k)
        s.companies[i].set("holders", .array(H))
        if let n = s.people.values.first(where: { $0.name == holderName }) { removeSeat(&s, personID: n.id) }
        return true
    }

    // MARK: Big meeting

    public struct BigOffer: Equatable, Sendable { public var target: String; public var seller: String; public var sellerCompany: String; public var percent: Double; public var price: Double; public var yield: Double; public var expiresWeek: Int; public var countered: Bool }
    public static func bigOffer(_ s: GameState) -> BigOffer? {
        guard let o = s.rest["bigOff"], !o.isNull else { return nil }
        return BigOffer(target: o["tgt"].string, seller: o["seller"].string, sellerCompany: o["sellerCo"].string, percent: o["pct"].double, price: o["price"].double, yield: o["yld"].double, expiresWeek: o["exp"].int, countered: o["ctr"].bool)
    }
    public struct Stake: Equatable, Sendable { public var name: String; public var percent: Double; public var value: Double; public var yield: Double }
    public static func stakes(_ s: GameState) -> [Stake] { (s.rest["stakes"]?.array ?? []).map { Stake(name: $0["name"].string, percent: $0["pct"].double, value: $0["val"].double, yield: $0["yld"].double) } }

    static func bigWeekly(_ s: inout GameState, data: GameData) {
        // stakes grow and pay a share each month
        var L = s.rest["stakes"]?.array ?? []
        for k in L.indices {
            L[k]["val"] = .number(max(0, L[k]["val"].double * (1 + 0.003 + s.random.gauss() * 0.015)))
            if GameCalendar.isMonthEnd(week: s.week) { Payments.playerReceives(&s, jsRound(L[k]["val"].double * L[k]["yld"].double / 12), label: "Profit share: \(L[k]["name"].string)") }
        }
        if !L.isEmpty { s.rest["stakes"] = .array(L) }
        if let o = s.rest["bigOff"], !o.isNull, s.week >= o["exp"].int { s.rest["bigOff"] = .null }
        guard (s.rest["bigOff"] ?? .null).isNull, s.week % 13 == 7 else { return }
        let cur = playerCurrency(s, data)
        let nw = Valuation.netWorth(s, trades: data.catalog).total
        guard nw >= cur.scaledPrice(40e6), s.random.chance(0.35) else { return }
        let w = World(state: s, data: data)
        let starts = w.countries[s.homeCountryCode]?.companyNameStarts ?? ["Nova"]
        let pct = s.random.pick([25.0, 30, 40, 49])
        let tgt = (starts.isEmpty ? "Nova" : s.random.pick(starts)) + " Group"
        s.rest["bigOff"] = .object(["id": .number(Double(s.makeID())), "tgt": .string(tgt), "seller": "Harbour Seller", "sellerCo": "Harbour Capital",
                                    "pct": .number(pct), "price": .number(jsRound(nw * s.random.range(0.5, 1.1) / 1e5) * 1e5), "yld": .number(s.random.range(0.06, 0.1)), "w": .number(Double(s.week)), "exp": .number(Double(s.week + 3)), "ctr": 0])
        s.addMessage(kind: "info", from: "Big meeting", title: "Big meeting: \(Int(pct))% of \(tgt)", body: "An offer is on the table for 3 weeks.", tone: "good", status: "done")
    }

    public enum BigResult: Equatable, Sendable { case ok, none, notEnoughCash, accepted(Double), walkedAway }

    /// Accept: you pay part yourself and borrow up to 60% over ten years. Original: `ACT.bigacc`.
    public static func acceptBigOffer(_ s: inout GameState, data: GameData) -> BigResult {
        guard let o = s.rest["bigOff"], !o.isNull else { return .none }
        let price = o["price"].double, cur = playerCurrency(s, data)
        let borrow = min(jsRound(price * 0.6), max(0, jsRound(price - max(0, Payments.liquid(s) - cur.scaledPrice(100000)))))
        let own = price - borrow
        if Payments.liquid(s) < own { return .notEnoughCash }
        if borrow > 0 {
            var l = Loan(raw: [:])
            l.id = s.makeID(); l.kind = "mort"; l.name = "Acquisition loan: \(o["tgt"].string)"; l.balance = borrow; l.set("amt0", borrow); l.margin = 0.02; l.termMonths = 120
            l.companyID = 0; l.startWeek = s.week; l.isGuaranteed = false
            l.monthlyPayment = Loans.annuity(principal: borrow, yearlyRate: s.economy.policyRate + 0.02, months: 120)
            s.loans.append(l)
            Payments.playerReceives(&s, borrow, label: "Acquisition loan")
        }
        Payments.playerPays(&s, price, label: "Bought \(Int(o["pct"].double))% of \(o["tgt"].string)")
        var L = s.rest["stakes"]?.array ?? []
        L.append(.object(["id": .number(Double(s.makeID())), "name": o["tgt"], "pct": o["pct"], "val": .number(price), "yld": o["yld"], "w0": .number(Double(s.week))]))
        s.rest["stakes"] = .array(L); s.rest["bigOff"] = .null
        s.note("You bought \(Int(o["pct"].double))% of \(o["tgt"].string).", tone: "good")
        return .accepted(price)
    }
    public static func counterBigOffer(_ s: inout GameState) -> BigResult {
        guard var o = s.rest["bigOff"], !o.isNull, !o["ctr"].bool else { return .none }
        o["ctr"] = true
        if s.random.chance(0.45) { o["price"] = .number(jsRound(o["price"].double * 0.9 / 1e5) * 1e5); s.rest["bigOff"] = o; return .ok }
        s.rest["bigOff"] = .null; return .walkedAway
    }
    public static func walkAwayFromBigOffer(_ s: inout GameState) { s.rest["bigOff"] = .null }
}
