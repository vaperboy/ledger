import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// The big meeting (late game): once your net worth is large, every quarter or so someone offers you a minority stake (25 to 49%) in a group. You pay
/// part yourself and borrow up to 60% over ten years; the stake pays a yearly profit share every month end and moves with the market.
/// Original: `bigWeek`, `V.bigmeet`, `ACT.bigacc`, `bigctr`, `bigwalk`, `stakesWeek` (features/player/selling_startups_and_crisis.js).
///
/// State: `rest["bigOff"]` = the offer on the table, `rest["stakes"]` = the stakes you hold { id, name, pct, val, yld, w0 }.
public enum BigMeeting {
    public struct Offer: Equatable {
        public var id: Int
        public var target: String, seller: String, sellerCompany: String
        public var pct: Int
        public var price: Double
        public var yield: Double
        public var expiresWeek: Int
        public var countered: Bool
        public var yearlyProfitShare: Double { price * yield }
        /// What the bank would lend: 60% of the price.
        public var bankMaximum: Double { (price * 0.6).rounded() }
    }
    public struct Stake: Identifiable, Equatable {
        public var id: Int
        public var name: String
        public var pct: Double
        public var value: Double
        public var yield: Double
        public var yearlyProfitShare: Double { value * yield }
    }

    public static func offer(_ s: GameState) -> Offer? {
        guard let o = s.rest["bigOff"], !o.isNull else { return nil }
        return Offer(id: o["id"].int, target: o["tgt"].string, seller: o["seller"].string, sellerCompany: o["sellerCo"].string, pct: o["pct"].int, price: o["price"].double,
                     yield: o["yld"].double, expiresWeek: o["exp"].int, countered: o["ctr"].bool)
    }
    public static func stakes(_ s: GameState) -> [Stake] {
        (s.rest["stakes"]?.array ?? []).map { Stake(id: $0["id"].int, name: $0["name"].string, pct: $0["pct"].double, value: $0["val"].double, yield: $0["yld"].double) }
    }
    /// What you must put in yourself and what you would borrow. Original: `ACT.bigacc`.
    public static func financing(_ s: GameState, price: Double, context fc: FinanceContext) -> (own: Double, borrow: Double) {
        let borrow = min((price * 0.6).rounded(), max(0, (price - max(0, Payments.liquid(s) - fc.homeCurrency(s).scaledPrice(100_000))).rounded()))
        return (price - borrow, borrow)
    }
    /// A warning shown on the screen when a 2-point rise in rates would make the interest cost more than the profit share.
    public static func ratesWarning(_ s: GameState, _ o: Offer) -> Bool { (s.economy.policyRate + 0.045) * o.bankMaximum > o.price * o.yield }

    // MARK: Actions

    public enum AcceptResult: Equatable { case ok, needsOwnMoney(Double), noOffer }

    @discardableResult
    public static func accept(_ s: inout GameState, context fc: FinanceContext) -> AcceptResult {
        guard let o = offer(s) else { return .noOffer }
        let f = financing(s, price: o.price, context: fc)
        if Payments.liquid(s) < f.own { return .needsOwnMoney(f.own) }
        if f.borrow > 0 {
            let rate = s.economy.policyRate + 0.02
            var l = Loan(raw: [:])
            l.id = s.makeID(); l.kind = "mort"; l.name = "Acquisition loan: \(o.target)"
            l.balance = f.borrow; l.originalAmount = f.borrow; l.margin = 0.02; l.monthlyPayment = Loans.annuity(principal: f.borrow, yearlyRate: rate, months: 120)
            l.termMonths = 120; l.companyID = 0; l.startWeek = s.week; l.isGuaranteed = false; l.bankCompanyID = 0
            s.loans.append(l)
            Payments.playerReceives(&s, f.borrow, label: "Acquisition loan")
        }
        Payments.transferFromSavings(&s, need: o.price)
        Payments.playerPays(&s, o.price, label: "Bought \(o.pct)% of \(o.target)")
        s.rest["stakes"] = .array((s.rest["stakes"]?.array ?? []) + [.object(["id": .number(Double(s.makeID())), "name": .string(o.target), "pct": .number(Double(o.pct)), "val": .number(o.price), "yld": .number(o.yield), "w0": .number(Double(s.week))])])
        s.rest["bigOff"] = .null
        s.note("You bought \(o.pct)% of \(o.target).", tone: "good")
        return .ok
    }

    /// Ask for 10% off, once. They accept (45%) or walk away. Original: `ACT.bigctr`.
    @discardableResult
    public static func counter(_ s: inout GameState) -> Bool? {
        guard var o = s.rest["bigOff"], !o.isNull, !o["ctr"].bool else { return nil }
        o["ctr"] = 1
        if s.random.chance(0.45) {
            o["price"] = .number((o["price"].double * 0.9 / 1e5).rounded() * 1e5)
            s.rest["bigOff"] = o
            return true
        }
        s.rest["bigOff"] = .null
        s.note("\(o["seller"].string) walked away from the deal.", tone: "n")
        return false
    }
    public static func walkAway(_ s: inout GameState) { s.rest["bigOff"] = .null }

    // MARK: The week

    public static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        if let o = s.rest["bigOff"], !o.isNull, s.week >= o["exp"].int { s.rest["bigOff"] = .null }
        // a new offer
        if (s.rest["bigOff"] ?? .null).isNull, s.week % 13 == 7 {
            let nw = Valuation.netWorth(s, trades: data.catalog).total
            if nw >= fc.homeCurrency(s).scaledPrice(40e6), s.random.chance(0.35) {
                let c = data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode)
                let word = s.random.pick(["Nord", "Atlas", "Crown", "Harbor", "Summit", "Vanguard", "Orion"])
                let pct = s.random.pick([25, 30, 40, 49])
                let o: JSONValue = .object(["id": .number(Double(s.makeID())), "tgt": .string(word + " Group"),
                                            "seller": .string(Funding.personName(&s, countryCode: c.code, data: data)), "sellerCo": .string(Funding.fundName(&s, countryCode: c.code, data: data)),
                                            "pct": .number(Double(pct)), "price": .number((nw * s.random.range(0.5, 1.1) / 1e5).rounded() * 1e5), "yld": .number(s.random.range(0.06, 0.1)),
                                            "w": .number(Double(s.week)), "exp": .number(Double(s.week + 3)), "ctr": 0])
                s.rest["bigOff"] = o
                s.addMessage(from: o["seller"].string, title: "Big meeting: \(pct)% of \(o["tgt"].string)", body: "An offer is on the table for 3 weeks.", tone: "good")
            }
        }
        // stakes drift and pay out at month end
        guard var list = s.rest["stakes"]?.array, !list.isEmpty else { return }
        for k in list.indices {
            list[k]["val"] = .number(max(0, list[k]["val"].double * (1 + 0.003 + s.random.gauss() * 0.015)))
            if GameCalendar.isMonthEnd(week: s.week) {
                Payments.playerReceives(&s, jsRound(list[k]["val"].double * list[k]["yld"].double / 12), label: "Profit share: \(list[k]["name"].string)")
            }
        }
        s.rest["stakes"] = .array(list)
    }
}
