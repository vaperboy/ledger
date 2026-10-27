import Foundation
import GameCore
import Countries
import Finance

/// The finance manager. Original: `genFinManagers`, `hireFinManager`, `fmAdd`, `fmWithdraw`, `fireFinManager`, the manager part of
/// `investWeek` (engine/world/investing.js) and `ACT.hfin` with the weekly 'week.after' step of the holdings
/// (features/world/rivals_holdings_software.js).
///
/// Two different people share the name in the original and are kept apart here:
///  - the fund manager you hand your own money to (Investing screen): `rest["fm"]` = { npc, mandate, fee, bal, cost, skill, ret, warned },
///    `rest["fmPool"]` = ids of the three candidates, who live in `people` with role "fin";
///  - the finance manager of the main office (role "fin" in `rest["office"].staff`), who runs holding companies: the entry's `holds`
///    lists the holding ids. Each week he invests spare cash of those holdings in the index fund and sells units to cover a negative balance.
public enum FinanceManager {
    public enum Mandate: String, CaseIterable, Sendable {
        case cautious = "cons", balanced = "bal", aggressive = "aggr"
        /// Share of the index move that is followed, steady weekly return, and weekly noise.
        var parameters: (beta: Double, drift: Double, noise: Double) {
            switch self {
            case .cautious: return (0.5, 0.0003, 0.004)
            case .balanced: return (0.8, 0.0006, 0.007)
            case .aggressive: return (1.15, 0.0009, 0.013)
            }
        }
        public var title: String { self == .cautious ? "Cautious" : self == .balanced ? "Balanced" : "Aggressive" }
    }

    public struct Candidate: Equatable, Identifiable, Sendable {
        public var id: Int
        public var name: String
        public var age: Int
        /// What the CV says (may be exaggerated); the true skill is never shown.
        public var claimedSkill: Double
        public var yearsClaimed: Double
        /// Yearly fee as a share of the managed money.
        public var fee: Double
    }

    public enum HireResult: Equatable, Sendable { case ok, busy, notEnoughCash, tooSmall, unknown }

    /// The running arrangement, if any.
    public struct Account: Equatable, Sendable {
        public var personID: Int
        public var name: String
        public var mandate: Mandate
        public var fee: Double
        public var balance: Double
        public var cost: Double
        public var result: Double { cost > 0 ? balance / cost - 1 : 0 }
    }

    // MARK: Your own fund manager

    public static func account(_ s: GameState) -> Account? {
        guard let f = s.rest["fm"], !f.isNull, let m = Mandate(rawValue: f["mandate"].string) else { return nil }
        return Account(personID: f["npc"].int, name: s.people[f["npc"].int]?.name ?? "Your fund manager", mandate: m,
                       fee: f["fee"].double, balance: f["bal"].double, cost: f["cost"].double)
    }

    /// The three candidates offered (made on first look, kept until the manager is dismissed). Original: `S.fmPool` / `genFinManagers`.
    @discardableResult
    public static func pool(_ s: inout GameState, data: GameData) -> [Candidate] {
        if (s.rest["fmPool"]?.array ?? []).isEmpty {
            let c = data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode)
            var ids: [JSONValue] = []
            for i in 0..<3 {
                let id = s.makeID()
                let skill = Double(s.random.int(30, 92))
                let overstated = s.random.chance(0.3)
                let claim = clamp(skill + (overstated ? Double(s.random.int(8, 25)) : Double(s.random.int(-4, 4))), 20, 99)
                let track = (clamp((claim - 50) / 4 + 6 + s.random.gauss() * 2, 1, 18) * 10).rounded() / 10
                let name = Hiring.personName(c, &s.random)
                let age = s.random.int(32, 60)
                let fee = [0.008, 0.012, 0.016][i]
                s.people[id] = Person(raw: ["id": .number(Double(id)), "name": .string(name), "age": .number(Double(age)), "role": .string("fin"),
                                            "skill": .number(skill), "hired": .number(0), "claim": .number(claim),
                                            "fee": .number(fee), "track": .number(track)])
                ids.append(.number(Double(id)))
            }
            s.rest["fmPool"] = .array(ids)
            for v in ids { FaceBook.assign(personID: v.int, countryCode: c.code, sheet: .suits, state: &s) }
        }
        return candidates(s)
    }

    public static func candidates(_ s: GameState) -> [Candidate] {
        (s.rest["fmPool"]?.array ?? []).compactMap { v in
            guard let p = s.people[v.int], p.employerID == 0 else { return nil }
            return Candidate(id: p.id, name: p.name, age: p.age, claimedSkill: p.num("claim"), yearsClaimed: p.num("track"), fee: p.num("fee"))
        }
    }

    /// Hand `amount` to one of the candidates with a mandate. The money leaves your account (savings first if short).
    public static func hire(_ s: inout GameState, personID: Int, mandate: Mandate, amount: Double) -> HireResult {
        guard let n = s.people[personID], n.role == "fin" else { return .unknown }
        if account(s) != nil || n.employerID != 0 { return .busy }
        let amt = jsRound(amount)
        if amt < 1 { return .tooSmall }
        if Payments.liquid(s) < amt { return .notEnoughCash }
        Payments.transferFromSavings(&s, need: amt)
        Ledger.move(&s, .me, -amt, why: "To \(n.name), your fund manager")
        s.rest["fm"] = .object(["npc": .number(Double(personID)), "mandate": .string(mandate.rawValue), "fee": .number(n.num("fee")),
                                "bal": .number(amt), "cost": .number(amt), "skill": .number(n.skill), "ret": .number(0), "feesPaid": .number(0)])
        var p = n
        p.employerID = -3
        s.people[personID] = p
        s.note("\(n.name) now manages \(Int(amt)) of your money (\(mandate.title.lowercased()) mandate, fee \(String(format: "%.1f", n.num("fee") * 100))% a year).", tone: "good")
        return .ok
    }

    /// Put more money in (from the current account). Original: `fmAdd`.
    @discardableResult
    public static func add(_ s: inout GameState, amount: Double) -> Bool {
        let amt = jsRound(amount)
        guard var f = s.rest["fm"], !f.isNull, amt > 0, s.cash >= amt else { return false }
        Ledger.move(&s, .me, -amt, why: "To your fund manager")
        f["bal"] = .number(f["bal"].double + amt)
        f["cost"] = .number(f["cost"].double + amt)
        s.rest["fm"] = f
        return true
    }

    /// Take money out. A gain is taxed as a capital gain at year end. Original: `fmWithdraw`.
    @discardableResult
    public static func withdraw(_ s: inout GameState, amount: Double) -> Bool {
        guard var f = s.rest["fm"], !f.isNull, f["bal"].double > 0, amount > 0 else { return false }
        let bal = f["bal"].double
        let amt = min(jsRound(amount), bal)
        let frac = amt / bal
        let costPart = f["cost"].double * frac
        f["bal"] = .number(bal - amt)
        f["cost"] = .number(f["cost"].double * (1 - frac))
        s.rest["fm"] = f
        Ledger.move(&s, .me, amt, why: "From your fund manager")
        s.tax.gains += amt - costPart
        return true
    }

    /// Dismiss: everything comes back to you. Original: `fireFinManager`.
    @discardableResult
    public static func fire(_ s: inout GameState) -> Bool {
        guard let a = account(s) else { return false }
        s.rest["fm"] = .null
        s.rest["fmPool"] = .null
        if a.balance > 0 { Ledger.move(&s, .me, a.balance, why: "Fund manager let go: money back") }
        s.tax.gains += a.balance - a.cost
        if var p = s.people[a.personID] { p.employerID = 0; s.people[a.personID] = p }
        s.note("You let \(a.name) go. The managed money is back in your account.", tone: "n")
        return true
    }

    /// The bank forces a sale: the managed money is cashed in when cash is still short. Original: end of `liquidateInvestments`.
    public static func cashIn(_ s: inout GameState, need: Double) {
        guard s.cash < need, var f = s.rest["fm"], !f.isNull, f["bal"].double > 0 else { return }
        let bal = f["bal"].double
        s.tax.gains += bal - f["cost"].double
        f["bal"] = .number(0)
        f["cost"] = .number(0)
        s.rest["fm"] = f
        Ledger.move(&s, .me, bal, why: "Fund manager account cashed in to cover debts")
    }

    /// One week of the managed money: follows the market by the mandate, plus (or minus) the manager's skill, less the fee.
    static func weeklyManaged(_ s: inout GameState) {
        guard var f = s.rest["fm"], !f.isNull, let m = Mandate(rawValue: f["mandate"].string) else { return }
        let p = m.parameters
        let alpha = (f["skill"].double - 55) / 100 * 0.0035
        let noise = s.random.gauss() * p.noise * 0.4
        let r = p.beta * (s.rest["idxRet"]?.double ?? 0) + p.drift + alpha + noise - f["fee"].double / 52
        let before = f["bal"].double
        f["bal"] = .number(before * (1 + r))
        f["feesPaid"] = .number(f["feesPaid"].double + before * f["fee"].double / 52)
        f["ret"] = .number(f["ret"].double * 0.97 + r)
        let warn = f["bal"].double < f["cost"].double * 0.3 && !f["warned"].bool
        if warn { f["warned"] = .number(1) }
        s.rest["fm"] = f
        if warn {
            let name = s.people[f["npc"].int]?.name ?? "Your fund manager"
            s.addMessage(from: "Finance manager", title: "Heavy losses in managed portfolio", body: "Your finance manager \(name) has lost over 70%.", tone: "bad")
        }
    }

    // MARK: The finance manager of the main office and your holding companies

    static func officeFinanceIndex(_ s: GameState) -> Int? {
        (s.rest["office"]?["staff"].array ?? []).firstIndex { $0["role"].string == "fin" }
    }

    /// Ids of the holdings the office finance manager runs.
    public static func managedHoldings(_ s: GameState) -> [Int] {
        guard let k = officeFinanceIndex(s) else { return [] }
        return (s.rest["office"]?["staff"].array[k]["holds"].array ?? []).map { $0.int }
    }
    public static func manages(_ s: GameState, holdingID: Int) -> Bool { managedHoldings(s).contains(holdingID) }

    /// The office finance manager who negotiates share sales for a holding he runs, and how good he is (0.2...0.98: skill/100 plus
    /// a point per 100 years of experience). Original: `mg` / `s` in `raisePlan`.
    public static func negotiator(_ s: GameState, holdingID: Int) -> (name: String, skill: Double)? {
        guard manages(s, holdingID: holdingID), let k = officeFinanceIndex(s), let p = s.people[(s.rest["office"]?["staff"].array[k]["id"].int) ?? 0] else { return nil }
        return (p.name, clamp((p.value("skill").isNull ? 55 : p.value("skill").double) / 100 + p.value("exp").double * 0.01, 0.2, 0.98))
    }

    /// Let the finance manager run a holding, or take it back. Returns the new state (nil: no finance manager in the office).
    /// Original: `ACT.hfin`.
    @discardableResult
    public static func toggleHolding(_ s: inout GameState, holdingID: Int) -> Bool? {
        guard let k = officeFinanceIndex(s), var o = s.rest["office"], let h = s.company(holdingID), h.type == "hold" else { return nil }
        var staff = o["staff"].array
        var holds = staff[k]["holds"].array
        let now: Bool
        if let i = holds.firstIndex(where: { $0.int == holdingID }) { holds.remove(at: i); now = false } else { holds.append(.number(Double(holdingID))); now = true }
        staff[k]["holds"] = .array(holds)
        o["staff"] = .array(staff)
        s.rest["office"] = o
        let who = staff[k]["name"].string
        s.note(now ? "\(who) now runs \(h.name)." : "You run \(h.name) yourself again.", tone: "n", companyID: holdingID)
        return now
    }

    /// Spare cash of a managed holding goes into the index fund; a negative balance is covered by selling units.
    /// Original: the 'rivals_holdings_software weekly' step.
    static func weeklyHoldings(_ s: inout GameState, context fc: FinanceContext) {
        for id in managedHoldings(s) {
            guard let h = s.company(id), h.status == .open else { continue }
            let cur = fc.currency(h.countryCode, s)
            let buf = cur.scaledPrice(200000)
            if h.cash > buf * 3 {
                let amt = jsRound(h.cash - buf * 2)
                if HoldingModel.invest(&s, holdingID: id, amount: amt) { s.note("\(h.name) put \(cur.short(amt)) of spare cash in the index fund.", tone: "n", companyID: id) }
            } else if h.cash < 0 {
                let amt = -h.cash + buf
                if HoldingModel.divest(&s, holdingID: id, amount: amt) { s.note("\(h.name) sold index fund units to cover its account.", tone: "n", companyID: id) }
            }
        }
    }

    /// The weekly turn of both. Original: `investWeek` (manager part) and the holdings' 'week.after' step.
    public static func weekly(_ s: inout GameState, context fc: FinanceContext) {
        weeklyManaged(&s)
        weeklyHoldings(&s, context: fc)
    }
}
