import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Exact numbers behind the venture actions, so screens show what the engine will use: investing in a startup, selling a startup stake or a fund
/// stake (optionally at the owner's own asking price), committing to a fund, buying into a group. The actions call these same functions.
public enum VentureSale {
    /// The owner may ask for between half and 1.4 times the quoted proceeds.
    public static let askLowest = 0.5, askHighest = 1.4

    /// What a sale brings at the default price, and what the owner may ask.
    public struct Quote: Equatable, Sendable {
        public var ok: Bool
        public var reason: String
        /// Share of the holding sold (1 for a whole fund stake).
        public var fraction: Double
        /// What that share is worth at full value.
        public var fairValue: Double
        /// Share of full value a buyer pays by default.
        public var factor: Double
        /// Cash received at the default price.
        public var proceeds: Double
        public var costBasis: Double
        public var taxableGain: Double
        /// Lowest and highest asking price (absolute amounts).
        public var askLowest: Double, askHighest: Double
        /// Percent of the startup still held afterwards (0 for a fund).
        public var remainingPercent: Double
        public var closesStake: Bool
        public var keepsBoardSeat: Bool

        static func unavailable(_ why: String) -> Quote {
            Quote(ok: false, reason: why, fraction: 0, fairValue: 0, factor: 0, proceeds: 0, costBasis: 0, taxableGain: 0, askLowest: 0, askHighest: 0, remainingPercent: 0, closesStake: false, keepsBoardSeat: false)
        }
    }

    /// The buyer's answer to an asking price. A counter-offer is the most the buyer will pay this week: asking exactly that is accepted.
    public enum Outcome: Equatable, Sendable {
        case sold(Double)
        case counter(Double)
        case declined(String)
        case unavailable(String)

        public var proceeds: Double { if case .sold(let p) = self { return p }; return 0 }
    }

    /// Lower or equal asks always sell at the ask. A higher ask sells when the buyer's reservation covers it, draws a counter-offer when it is
    /// within 12% of the reservation, and otherwise ends the talks for the week (`coolingDown`).
    static func resolve(quoted: Double, askMultiplier: Double?, reservation: Double, coolingDown: Bool) -> Outcome {
        guard let a = askMultiplier, abs(a - 1) > 1e-9 else { return .sold(quoted) }
        let m = clamp(a, askLowest, askHighest)
        let ask = jsRound(quoted * m)
        if m <= 1 { return .sold(ask) }
        let most = (quoted * reservation).rounded(.down)
        if ask <= most { return .sold(ask) }
        if coolingDown { return .declined("The buyer will not talk again this week.") }
        if m <= reservation + 0.12, most > quoted { return .counter(most) }
        return .declined("The buyer walks away from that price.")
    }
}

// MARK: Startups of others

public extension Startups {
    /// What putting money into a pitch would do, with the verdict `invest` will give.
    struct InvestQuote: Equatable {
        public var pitchID: Int
        public var name: String
        /// Rounded to 10,000 and capped at the round size.
        public var amount: Double
        public var minimum: Double
        public var postMoney: Double
        public var ownershipPercent: Double
        public var boardSeat: Bool
        /// Money the buyer can pay with (your cash and savings, or the holding's account).
        public var available: Double
        public var result: InvestResult
    }

    static func investQuote(_ s: GameState, pitchID: Int, amount: Double, holdingID: Int = 0, context fc: FinanceContext) -> InvestQuote {
        guard let d = (s.rest["deals_su"]?.array ?? []).first(where: { $0["id"].int == pitchID }) else {
            return InvestQuote(pitchID: pitchID, name: "", amount: 0, minimum: 0, postMoney: 0, ownershipPercent: 0, boardSeat: false, available: 0, result: .gone)
        }
        let minimum = fc.homeCurrency(s).scaledPrice(minimumInvestment)
        let rounded = (amount / 10000).rounded() * 10000
        let amt = min(rounded, d["raise"].double)
        let pct = amt / max(1, d["post"].double) * 100
        let available = holdingID == 0 ? Payments.liquid(s) : (s.company(holdingID)?.cash ?? 0)
        let result: InvestResult = rounded < minimum ? .tooSmall : available < amt ? .notEnoughMoney : .ok
        return InvestQuote(pitchID: pitchID, name: d["name"].string, amount: amt, minimum: minimum, postMoney: d["post"].double, ownershipPercent: pct, boardSeat: pct >= 20, available: available, result: result)
    }

    /// Sale of a share of your own stake at the market price (72% of fair value).
    static let stakeSellFactor = 0.72

    static func stakeRecord(_ s: GameState, _ id: Int) -> JSONValue? { (s.rest["startups"]?.array ?? []).first { $0["id"].int == id } }

    /// Factor on fair value the market pays: flat for your own shares, by tier for a holding's (a bigger stake is easier to sell whole).
    static func sellFactor(for f: JSONValue) -> Double {
        f["hid"].int == 0 ? stakeSellFactor : stakeSellFactor * HoldingStakes.sellFactor(beforePercent: f["pct"].double) / 0.8
    }

    /// The most a buyer would pay this week, as a multiple of the quoted proceeds: better, later-stage startups in a good economy draw more.
    static func buyerReservation(_ s: GameState, _ f: JSONValue) -> Double {
        var r = HashedRandom("\(s.seed):su:\(f["id"].int):\(s.week)")
        let head = clamp(0.02 + (f["q"].double - 0.4) * 0.4 + Double(f["stage"].int) * 0.03 + (s.economy.demand - 1) * 0.5, 0, 0.3)
        return 1 + head * (0.4 + 0.6 * r.next())
    }

    static func saleQuote(_ s: GameState, _ f: JSONValue, fraction: Double) -> VentureSale.Quote {
        guard f["st"].string == "live" else { return .unavailable("That startup is no longer running.") }
        guard fraction > 0 else { return .unavailable("Choose a share to sell.") }
        let frac = min(1, fraction)
        let pct = f["pct"].double, factor = sellFactor(for: f)
        let fair = f["val"].double * pct / 100 * frac
        let v = jsRound(fair * factor)
        let left = pct * (1 - frac)
        let cost = f["in"].double * frac
        return VentureSale.Quote(ok: true, reason: "", fraction: frac, fairValue: fair, factor: factor, proceeds: v, costBasis: cost, taxableGain: v - cost,
                                 askLowest: jsRound(v * VentureSale.askLowest), askHighest: jsRound(v * VentureSale.askHighest), remainingPercent: left,
                                 closesStake: left < 0.05, keepsBoardSeat: left >= 20)
    }

    /// What selling `fraction` (0...1) of one of your startup stakes brings at the default price.
    static func sellQuote(_ s: GameState, stakeID: Int, fraction: Double) -> VentureSale.Quote {
        guard let f = stakeRecord(s, stakeID), f["hid"].int == 0 else { return .unavailable("You hold no such stake.") }
        return saleQuote(s, f, fraction: fraction)
    }

    /// Sell part of a stake you or your holding (`holdingID`) own, at the default price or at an asking price (a multiple of the quoted proceeds).
    @discardableResult
    static func sellAsking(_ s: inout GameState, stakeID: Int, fraction: Double, askMultiplier: Double?, holdingID: Int = 0) -> VentureSale.Outcome {
        guard let f = stakeRecord(s, stakeID), f["hid"].int == holdingID else { return .unavailable("You hold no such stake.") }
        let q = saleQuote(s, f, fraction: fraction)
        guard q.ok else { return .unavailable(q.reason) }
        let outcome = VentureSale.resolve(quoted: q.proceeds, askMultiplier: askMultiplier, reservation: buyerReservation(s, f), coolingDown: f["nHi"].int == s.week)
        let week = Double(s.week)
        guard case .sold(let v) = outcome else {
            if case .declined = outcome { editStake(&s, stakeID) { $0["nHi"] = .number(week) } }
            return outcome
        }
        receive(&s, f, v, label: "Sold shares in \(f["name"].string)")
        if holdingID == 0 { s.tax.gains += v - q.costBasis }
        let frac = q.fraction
        editStake(&s, stakeID) { x in
            x["pct"] = .number(x["pct"].double * (1 - frac)); x["in"] = .number(x["in"].double * (1 - frac))
            x["seat"] = .bool(x["pct"].double >= 20)
            if x["pct"].double < 0.05 { x["st"] = "exit" }
        }
        return outcome
    }

    /// Money a stake's owner can spend: the holding's account for a holding's stake, otherwise your cash and savings.
    static func available(_ s: GameState, _ f: JSONValue) -> Double {
        f["hid"].int == 0 ? Payments.liquid(s) : (s.company(f["hid"].int)?.cash ?? 0)
    }
    static func pay(_ s: inout GameState, _ f: JSONValue, _ amount: Double, label: String) {
        let hid = f["hid"].int
        if hid != 0 {
            guard let hi = s.companyIndex(hid) else { return }
            Ledger.moveRaw(&s, .company(hid), -amount)
            s.companies[hi].addTransaction(week: s.week, amount: -amount, label: label)
        } else {
            Payments.transferFromSavings(&s, need: amount)
            Payments.playerPays(&s, amount, label: label)
        }
    }
    static func receive(_ s: inout GameState, _ f: JSONValue, _ amount: Double, label: String) {
        let hid = f["hid"].int
        if hid != 0 {
            guard let hi = s.companyIndex(hid) else { return }
            Ledger.moveRaw(&s, .company(hid), amount)
            s.companies[hi].addTransaction(week: s.week, amount: amount, label: label)
        } else {
            Payments.playerReceives(&s, amount, label: label)
        }
    }
}

// MARK: Private equity funds

public extension PrivateEquity {
    /// Whether a commitment is allowed, with the numbers behind the verdict `commit` will give.
    struct CommitCheck: Equatable {
        public var offerID: String
        public var name: String
        /// Rounded to a whole unit.
        public var amount: Double
        public var minimum: Double
        public var netWorth: Double
        /// Funds take money only from investors worth at least 1.5 times the commitment.
        public var requiredNetWorth: Double
        public var largestCommitment: Double
        public var result: CommitResult
    }
    static let netWorthMultiple = 1.5

    static func commitCheck(_ s: GameState, offerID: String, amount: Double, data: GameData) -> CommitCheck {
        guard let o = (s.rest["pe56"]?["offers"].array ?? []).first(where: { $0["id"].string == offerID }) else {
            return CommitCheck(offerID: offerID, name: "", amount: 0, minimum: 0, netWorth: 0, requiredNetWorth: 0, largestCommitment: 0, result: .gone)
        }
        let amt = jsRound(amount)
        let nw = Valuation.netWorth(s, trades: data.catalog).total
        // The amount is whole money, so compare it with the whole-money minimum: a scaled minimum can carry a fraction.
        let result: CommitResult = amt < jsRound(o["min"].double) ? .tooSmall : nw < amt * netWorthMultiple ? .notRichEnough : .ok
        return CommitCheck(offerID: offerID, name: o["n"].string, amount: amt, minimum: o["min"].double, netWorth: nw, requiredNetWorth: amt * netWorthMultiple,
                           largestCommitment: max(0, (nw / netWorthMultiple).rounded(.down)), result: result)
    }

    /// The most a secondary buyer would pay this week, as a multiple of the quoted price: a smaller discount than the usual one, drawn per fund and week.
    static func buyerReservation(_ s: GameState, _ f: JSONValue) -> Double {
        var r = HashedRandom("\(s.seed):pe-sale:\(f["id"].int):\(s.week)")
        let d = discount(f, s)
        return (1 - d * (0.3 + 0.5 * r.next())) / (1 - d)
    }

    /// What selling a fund stake on the secondary market brings at the default price.
    static func sellQuote(_ s: GameState, fundID: Int) -> VentureSale.Quote {
        guard let f = (s.rest["pe56"]?["mine"].array ?? []).first(where: { $0["id"].int == fundID && $0["st"].string == "live" }) else { return .unavailable("That fund stake is not for sale.") }
        let get = jsRound(f["nav"].double * (1 - discount(f, s)))
        let gain = max(0, f["dist"].double + get - f["paid"].double) - f["taxed"].double
        return VentureSale.Quote(ok: true, reason: "", fraction: 1, fairValue: f["nav"].double, factor: 1 - discount(f, s), proceeds: get, costBasis: f["paid"].double, taxableGain: max(0, gain),
                                 askLowest: jsRound(get * VentureSale.askLowest), askHighest: jsRound(get * VentureSale.askHighest), remainingPercent: 0, closesStake: true, keepsBoardSeat: false)
    }

    /// Sell a stake at the default price or at an asking price (a multiple of the quoted price). Nil when there is no such live stake.
    @discardableResult
    static func sellStakeAsking(_ s: inout GameState, fundID: Int, askMultiplier: Double?) -> VentureSale.Outcome? {
        guard var pe = s.rest["pe56"], var mine = Optional(pe["mine"].array), let k = mine.firstIndex(where: { $0["id"].int == fundID && $0["st"].string == "live" }) else { return nil }
        var f = mine[k]
        let q = sellQuote(s, fundID: fundID)
        let outcome = VentureSale.resolve(quoted: q.proceeds, askMultiplier: askMultiplier, reservation: buyerReservation(s, f), coolingDown: f["nHi"].int == s.week)
        guard case .sold(let get) = outcome else {
            if case .declined = outcome { f["nHi"] = .number(Double(s.week)); mine[k] = f; pe["mine"] = .array(mine); s.rest["pe56"] = pe }
            return outcome
        }
        Payments.playerReceives(&s, get, label: "Sold on the secondary market: \(f["n"].string)")
        let gain = max(0, f["dist"].double + get - f["paid"].double) - f["taxed"].double
        if gain > 0 { s.tax.gains += gain }
        f["dist"] = .number(f["dist"].double + get); f["nav"] = 0; f["st"] = "sold"
        mine[k] = f; pe["mine"] = .array(mine); s.rest["pe56"] = pe
        return outcome
    }
}

// MARK: Stakes in other groups

public extension GroupDeals {
    enum StakeFailure: Error, Equatable, Sendable {
        case noGroup, badFraction, badMultiplier, notWorthAnything
        /// You already hold this much of the group (0...1); the new share would take you over 100%.
        case alreadyHold(Double)
        case outbid
        case couldNotPay(Double)

        public var reason: String {
            switch self {
            case .noGroup: return "That group is not available."
            case .badFraction: return "Choose a share between 1% and 100%."
            case .badMultiplier: return "Bid between 0.5 and 3 times fair value."
            case .notWorthAnything: return "The group is not worth anything right now."
            case .alreadyHold(let p): return "You already own \(Int((p * 100).rounded()))% of this group."
            case .outbid: return "Another bidder won the stake."
            case .couldNotPay(let n): return "You could not raise \(Int(n.rounded())) in time."
            }
        }
    }

    struct StakeQuote: Equatable, Sendable {
        public var groupID: String
        public var name: String
        public var groupValue: Double
        public var fraction: Double, multiplier: Double, chance: Double
        /// What the stake costs if you win, rounded to 1,000.
        public var price: Double
        public var available: Double
        public var canAfford: Bool
        /// Set when the bid cannot be placed at all.
        public var refusal: StakeFailure?
    }

    static func stakeQuote(_ s: GameState, groupID: String, fraction: Double, multiplier: Double, chance: Double) -> StakeQuote {
        let avail = Payments.liquid(s)
        guard let g = GroupStakes.group(s, id: groupID) else {
            return StakeQuote(groupID: groupID, name: "", groupValue: 0, fraction: fraction, multiplier: multiplier, chance: chance, price: 0, available: avail, canAfford: false, refusal: .noGroup)
        }
        let v = GroupStakes.value(of: g, s)
        let price = stakePrice(value: v, fraction: fraction, multiplier: multiplier)
        let held = (s.rest["st27"]?.array ?? []).filter { $0["g"].string == groupID }.reduce(0) { $0 + $1["pct"].double }
        let refusal: StakeFailure? = !(fraction >= 0.01 && fraction <= 1) ? .badFraction : !(multiplier >= 0.5 && multiplier <= 3) ? .badMultiplier : v <= 0 ? .notWorthAnything : held + fraction > 1.0001 ? .alreadyHold(held) : nil
        return StakeQuote(groupID: groupID, name: g["name"].string, groupValue: v, fraction: fraction, multiplier: multiplier, chance: chance, price: price, available: avail, canAfford: avail >= price, refusal: refusal)
    }

    static func stakePrice(value v: Double, fraction: Double, multiplier: Double) -> Double { (v * fraction * multiplier / 1000).rounded() * 1000 }

    /// `buyStake` with the bid checked first and the outcome as a Result: the price paid on success.
    static func buyStakeChecked(_ s: inout GameState, groupID: String, fraction: Double, multiplier: Double, chance: Double, context fc: FinanceContext) -> Result<Double, StakeFailure> {
        if let why = stakeQuote(s, groupID: groupID, fraction: fraction, multiplier: multiplier, chance: chance).refusal { return .failure(why) }
        switch buyStake(&s, groupID: groupID, fraction: fraction, multiplier: multiplier, chance: chance, context: fc) {
        case .bought(let p): return .success(p)
        case .outbid: return .failure(.outbid)
        case .couldNotPay(let p): return .failure(.couldNotPay(p))
        case .noGroup: return .failure(.noGroup)
        }
    }
}
