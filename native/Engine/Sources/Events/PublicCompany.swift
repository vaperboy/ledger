import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum PublicCompany {
    public static let minimumValue = 30_000_000.0
    public static let discount = 0.10
    public static let underwritingFee = 0.04
    public static let investors = "Public investors"

    public struct Offering: Equatable, Sendable {
        public var companyValue: Double
        public var shares: Int
        public var sharePrice: Double
        public var offerPrice: Double
        public var gross: Double
        public var fee: Double
        public var tax: Double
        public var net: Double
        public var ownershipAfter: Double
        public var maxPct: Int
    }

    public static func listingMinimum(_ s: GameState, _ fc: FinanceContext) -> Double { fc.homeCurrency(s).scaledPrice(minimumValue) }

    public static func maxPct(_ co: Company) -> Int {
        let room = co.ownership - Double(ExchangeRules.ownerFloorPercent)
        return room <= 0 ? 0 : min(99, Int((room / co.ownership * 100).rounded(.down)))
    }

    public static func problem(_ s: GameState, companyID: Int, pct: Int, data: GameData, context fc: FinanceContext) -> String? {
        guard let co = s.company(companyID) else { return "No such company." }
        if s.isBranch(co) { return SaleListings.branchNote }
        if co.status != .open { return "The company must be open to go public." }
        if PublicExchange.isRegistered(s, companyID: companyID) { return "It is already on the exchange." }
        if SaleListings.isListed(s, companyID: companyID) { return "It is already on the market: withdraw that first." }
        if SaleListings.boardBlock(s, companyID: companyID) != nil { return "\(co.name) has partners. It goes public only when a board meeting votes for it." }
        if Shareholders.isBlocked(s, companyID: companyID) { return "The other owners block big moves for now." }
        let age = s.week - co.foundedWeek
        if age < ExchangeRules.minimumAgeWeeks { return "It must have traded for \(ExchangeRules.minimumAgeWeeks) weeks: \(ExchangeRules.minimumAgeWeeks - age) to go." }
        let value = Valuation.companyValue(co, state: s, trades: data.catalog)
        if value < listingMinimum(s, fc) { return "It must be worth at least \(fc.homeCurrency(s).display(listingMinimum(s, fc))) first." }
        let most = maxPct(co)
        if most < 10 { return "You must keep more than half of the shares, and there is too little to sell." }
        if pct > most { return "You can sell at most \(most)% of your stake and still keep more than half." }
        return nil
    }

    public static func offering(_ s: GameState, companyID: Int, pct: Int, data: GameData, context fc: FinanceContext) -> Offering? {
        guard let co = s.company(companyID) else { return nil }
        let value = max(0, Valuation.companyValue(co, state: s, trades: data.catalog))
        let t = CapTable.table(co)
        let shares = Int(saturating: (Double(t.you) * Double(pct) / 100).rounded())
        let price = ExchangeRules.round4(value / Double(max(1, t.total)))
        let offer = ExchangeRules.round4(price * (1 - discount))
        let gross = jsRound(Double(shares) * offer)
        let fee = jsRound(gross * underwritingFee)
        let basis = co.injectedCapital * Double(shares) / Double(max(1, t.total))
        let tax = max(0, gross - fee - basis) * fc.homeCountry(s).capitalGainsTax
        return Offering(companyValue: value, shares: shares, sharePrice: price, offerPrice: offer, gross: gross, fee: fee, tax: tax, net: gross - fee - tax,
                        ownershipAfter: Double(t.you - shares) / Double(max(1, t.total)) * 100, maxPct: maxPct(co))
    }

    @discardableResult
    public static func goPublic(_ s: inout GameState, companyID: Int, pct: Int, data: GameData, context fc: FinanceContext) -> String? {
        if let why = problem(s, companyID: companyID, pct: pct, data: data, context: fc) { return why }
        guard let i = s.companyIndex(companyID), let o = offering(s, companyID: companyID, pct: pct, data: data, context: fc) else { return "No such company." }
        let co = s.companies[i]
        guard PublicExchange.register(&s, companyID: companyID, value: o.companyValue) else { return "It is already on the exchange." }
        let moved = CapTable.sellFromYou(&s, i, shares: o.shares, to: investors, paid: o.gross)
        guard moved > 0 else { return "There are no shares to sell." }
        let basis = co.injectedCapital * Double(moved) / Double(max(1, CapTable.table(co).total))
        let gross = jsRound(Double(moved) * o.offerPrice)
        Payments.playerReceives(&s, gross - jsRound(gross * underwritingFee), label: "Going public: \(Int(pct))% of \(co.name)", companyID: companyID)
        s.tax.gains += max(0, gross - jsRound(gross * underwritingFee) - basis)
        Funding.addBoardSeats(&s, i, 1)
        Shareholders.setPolicy(&s, companyID: companyID, policy: "none")
        s.addMessage(from: "Stock exchange", title: "\(co.name) is now listed",
                     body: "Its \(CapTable.table(s.companies[i]).total) shares trade from today at about \(fc.currency(co.countryCode, s).display(o.sharePrice)) each. You keep \(Int(s.companies[i].ownership.rounded()))% and control. Results come out every quarter, and the board pays a dividend by the payout you choose.",
                     companyID: companyID, tone: "good")
        return nil
    }

    public static func results(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        let now = PublicExchange.today(s)
        var book = ExchangeBook(s)
        var changed = false
        for id in book.instruments.keys.sorted() {
            guard var inst = book.instruments[id], inst.isOwn, !inst.halted, let i = s.companyIndex(inst.companyID), s.companies[i].status.isLive else { continue }
            let n = now - inst.listedDay
            guard n > 0, n % ExchangeRules.quarterDays == 0 else { continue }
            let co = s.companies[i]
            let h = co.monthlyHistory
            let q = h.suffix(3).reduce(0) { $0 + $1.profit }
            let before = h.count >= 6 ? h[(h.count - 6)..<(h.count - 3)].reduce(0) { $0 + $1.profit } : 0
            let revenue = h.suffix(3).reduce(0) { $0 + $1.revenue }
            let change = before != 0 ? (q - before) / max(1, abs(before)) : (q > 0 ? 0.1 : -0.1)
            let move = clamp(change, -0.4, 0.4) * 0.3 - (q < 0 ? 0.03 : 0)
            let old = inst.sentiment
            inst.sentiment = clamp(old * (1 + move), 0.7, 1.3)
            book.instruments[id] = inst
            changed = true
            let policy = Shareholders.policy(co)
            let wanted = jsRound((max(0, q) * (Shareholders.payout[policy] ?? 0) / 1000).rounded() * 1000)
            var dividendLine = "No dividend this quarter."
            book.write(to: &s)
            if wanted > 0 {
                switch PublicExchange.declareDividend(&s, companyID: co.id, amount: wanted) {
                case .ok(let dps):
                    dividendLine = "The board declares a dividend of \(fc.currency(co.countryCode, s).display(dps)) a share, \(Shareholders.policyNames[policy]?.lowercased() ?? "by your policy")."
                    let mine = jsRound(wanted * co.ownership / 100)
                    if mine > 0 {
                        s.tax.dividends += mine
                        s.stats.dividendsReceived += mine
                        PersonalFinance.withholdNow(&s, context: fc)
                    }
                case .refused(let why): dividendLine = "No dividend: \(why)"
                default: break
                }
            }
            book = ExchangeBook(s)
            let cur = fc.currency(co.countryCode, s)
            let word = q < 0 ? "a loss" : change >= 0.05 ? "better than last quarter" : change <= -0.05 ? "worse than last quarter" : "about the same as last quarter"
            let reaction = inst.sentiment > old + 0.005 ? "Investors like it: the price is lifted." : inst.sentiment < old - 0.005 ? "Investors are disappointed: the price falls." : "The price barely moves."
            s.addMessage(from: "Stock exchange", title: "Quarterly results: \(co.name)",
                         body: "Sales \(cur.display(revenue)), profit \(cur.display(q)): \(word). \(dividendLine) \(reaction)", companyID: co.id, tone: q < 0 ? "bad" : "good")
        }
        if changed { book.write(to: &s) }
    }
}
