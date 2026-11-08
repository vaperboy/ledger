import Foundation
import GameCore
import Countries

/// Pressure that grows with success, so a veteran keeps something to fear without any single week being able to end the game:
/// rivals bid for the market leader's key accounts and best staff, and complaints left open and wages paid late compound into a
/// reputation loss that costs customers. Every roll is hashed from the seed (it draws nothing from the game's random stream), is capped,
/// and is scaled by the game mode (`Difficulty.threatScale`). Creditor pressure and the market regime warnings live in
/// `CreditorPressure` and `Markets`.
public enum Threat {
    /// Bids start after the first half year: until then the first-year protections are the design.
    static let firstBidWeek = 26
    /// Weeks a company is left alone after a rival has bid for something of it.
    static let bidCooldownWeeks = 12

    /// A line for the day result: something bad was drawn and did not land (a manager, insurance, a warranty or a rival's lost bid).
    public static func survived(_ s: inout GameState, companyID: Int, text: String) {
        s.note("Survived it: " + text, tone: "good", companyID: companyID)
    }

    /// 0 below the group threshold (`rest["group"]["big"]`), rising to 1 at eight times it.
    public static func wealth(_ s: GameState) -> Double {
        let big = s.rest["group"]?["big"].double ?? 0
        guard big > 0, let nw = s.netWorthHistory.last, nw > big else { return 0 }
        return clamp(log2(nw / big) / 3, 0, 1)
    }

    /// The company's place among the named rivals of its local market (1 = the largest), and how many are in it.
    static func marketRank(_ s: GameState, _ co: Company, data: GameData) -> (rank: Int, of: Int)? {
        guard let bd = data.catalog[co.type] else { return nil }
        let riv = Rivals.rivals(s, for: co)
        guard !riv.isEmpty else { return nil }
        let w = World(state: s, data: data)
        let mine = MarketMap.annualRevenue(co)
        let bigger = riv.filter { Rivals.yearlyRevenue(bd, $0, w, co) > mine }.count
        return (1 + bigger, riv.count + 1)
    }

    /// Weekly: the success-scaled threats of a company that is doing well.
    public static func weekly(_ s: inout GameState, data: GameData) {
        leaderBids(&s, data: data)
        reputationDebt(&s)
    }

    // MARK: Rivals bid for what you have

    /// Chance in a company-week that a rival goes after a key account or the best employee: only for the first or second in its market,
    /// more for a wealthy owner, never above a few percent.
    static func bidChance(rank: Int, wealth: Double, difficulty d: Difficulty) -> Double {
        let place = rank == 1 ? 1.0 : rank == 2 ? 0.4 : 0
        return min(0.06, 0.03 * place * (0.25 + wealth) * d.threatScale)
    }

    static func leaderBids(_ s: inout GameState, data: GameData) {
        guard s.week >= firstBidWeek else { return }
        let d = Difficulty.of(s)
        let rich = wealth(s)
        for i in s.companies.indices where s.companies[i].status == .open && s.companies[i].type != "hold" && s.companies[i].type != "club" {
            let co = s.companies[i]
            guard s.week - co.int("rbid") >= bidCooldownWeeks else { continue }
            let hasAccounts = !co.value("accts").array.isEmpty
            guard hasAccounts || co.staff.count >= 3, let place = marketRank(s, co, data: data) else { continue }
            var h = HashedRandom("\(s.seed):rbid:\(s.week):\(co.id)")
            guard h.next() < bidChance(rank: place.rank, wealth: rich, difficulty: d) else { continue }
            s.companies[i].set("rbid", .number(Double(s.week)))
            let rival = Rivals.rivals(s, for: co).max { $0.size < $1.size }?.name ?? "A rival"
            if hasAccounts && (co.staff.count < 3 || h.next() < 0.6) { KeyAccounts.rivalApproach(&s, i, rival: rival, &h) }
            else { staffApproach(&s, i, rival: rival, &h) }
        }
    }

    /// A rival tries to hire away the best employee. A manager and a good name make staying likelier; if they go, the post is for you to refill.
    static func staffApproach(_ s: inout GameState, _ i: Int, rival: String, _ h: inout HashedRandom) {
        let co = s.companies[i]
        guard let best = co.staff.max(by: { (s.people[$0.id]?.skill ?? 0) < (s.people[$1.id]?.skill ?? 0) }) else { return }
        let who = s.people[best.id]?.name ?? "Your best employee"
        let stay = 0.5 + (co.managerID != nil ? 0.15 : 0) + clamp(co.reputation - 50, 0, 50) / 250
        if h.next() < stay {
            survived(&s, companyID: co.id, text: "\(rival) tried to hire \(who) away from \(co.name) and failed.")
            return
        }
        s.companies[i].staff = co.staff.filter { $0.id != best.id }
        if var p = s.people[best.id] { p.employerID = 0; s.people[best.id] = p }
        s.note("\(who) left \(co.name) for \(rival), who made an offer.", tone: "bad", companyID: co.id)
    }

    // MARK: Complaint debt and late wages

    /// Complaints left open for two weeks and wages paid late build a debt that fades slowly. Above the threshold it wears reputation down and, through word of
    /// mouth, takes a few percent off demand for a few weeks. A company that answers its complaints and pays on time never feels it.
    static func reputationDebt(_ s: inout GameState) {
        let d = Difficulty.of(s)
        for i in s.companies.indices where s.companies[i].status == .open && s.companies[i].type != "hold" {
            let co = s.companies[i]
            let waiting = co.value("compl").array.filter { $0["st"].string == "open" && s.week - $0["w"].int >= 2 }.count
            let load = Double(waiting) * 0.25 + (co.wageShortfall > 0 ? 1 : 0)
            let debt = co.num("rdebt") * 0.8 + load
            s.companies[i].set("rdebt", .number(debt))
            guard debt > debtThreshold else {
                if debt < 1, co.value("rdebtNote").bool { s.companies[i].set("rdebtNote", .bool(false)) }
                continue
            }
            let over = min(4, debt - debtThreshold)
            s.companies[i].reputation = clamp(co.reputation - min(0.5, 0.12 * over * d.threatScale), 0, 100)
            if s.week % 2 == 0 { PriceMoves.addModifier(&s, i, key: "dem", multiplier: 1 - min(0.06, 0.012 * over * d.threatScale), weeks: 3) }
            if !co.value("rdebtNote").bool {
                s.companies[i].set("rdebtNote", .bool(true))
                s.note("Unanswered complaints and late wages are costing \(co.name) its good name, and customers with it. Answer the complaints and pay on time.", tone: "bad", companyID: co.id)
            }
        }
    }

    static let debtThreshold = 2.5
}
