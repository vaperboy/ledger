import Foundation
import GameCore
import Countries
import Finance
import Businesses

public extension GameEngine {
    enum RenameResult: Equatable, Sendable { case ok, tooShort, nameTaken, notEnoughCash, partOfChain, cooldown, unknown }
    static let renameCooldownWeeks = 26
    enum CloseResult: Equatable, Sendable { case ok, unknown, notOpen, restricted(String) }

    func renameCost(companyID: Int) -> Double {
        guard let co = state.company(companyID) else { return 0 }
        let cur = context.currency(co.countryCode, state)
        return jsRound((cur.scaledPrice(2500) + cur.scaledPrice(15000) * co.size) / 500) * 500
    }

    func rebrandCost(companyID: Int) -> Double {
        guard let co = state.company(companyID) else { return 0 }
        return jsRound(context.currency(co.countryCode, state).scaledPrice(40000) * co.size / 1000) * 1000
    }

    func renameCooldownLeft(companyID: Int) -> Int {
        guard let co = state.company(companyID), let last = co.value("nameLog").array.last else { return 0 }
        return max(0, last["w"].int + Self.renameCooldownWeeks - state.week)
    }

    @discardableResult mutating func renameCompany(companyID: Int, to newName: String, skipCooldown: Bool = false) -> RenameResult {
        let n = newName.trimmingCharacters(in: .whitespaces)
        var r = RenameResult.unknown
        let cost = renameCost(companyID: companyID)
        update { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            if Chains.chain(s, of: s.companies[i]) != nil { r = .partOfChain; return }
            if !skipCooldown, let last = s.companies[i].value("nameLog").array.last, last["w"].int + Self.renameCooldownWeeks > s.week { r = .cooldown; return }
            if n.count < 2 || n == s.companies[i].name { r = .tooShort; return }
            if s.companies.contains(where: { $0.status.isLive && $0.id != companyID && $0.name.lowercased() == n.lowercased() }) { r = .nameTaken; return }
            guard Payments.companyPays(&s, companyID: companyID, amount: cost, category: "oth", label: "New name and signs") else { r = .notEnoughCash; return }
            let old = s.companies[i].name
            s.companies[i].name = n
            s.companies[i].awareness = jsRound(s.companies[i].awareness * 0.68 * 10) / 10
            var log = s.companies[i].value("nameLog").array ?? []
            log.append(.object(["w": .number(Double(s.week)), "from": .string(old)]))
            s.companies[i].set("nameLog", .array(log))
            s.note("\(old) is now called \(n).", companyID: companyID)
            r = .ok
        }
        return r
    }

    @discardableResult mutating func renameChain(chainID: Int, to newName: String) -> RenameResult {
        let n = newName.trimmingCharacters(in: .whitespaces)
        var r = RenameResult.unknown
        update { s, d, ctx in
            guard var ch = Chains.chain(s, id: chainID) else { return }
            if n.count < 2 || n == ch["name"].string { r = .tooShort; return }
            if Chains.all(s).contains(where: { $0["id"].int != chainID && $0["name"].string.lowercased() == n.lowercased() }) { r = .nameTaken; return }
            let stores = Chains.stores(s, ch)
            func cost(_ c: Company) -> Double { jsRound(ctx.currency(c.countryCode, s).scaledPrice(40000) * c.size / 1000) * 1000 }
            if stores.contains(where: { $0.cash < cost($0) }) { r = .notEnoughCash; return }
            let old = ch["name"].string
            ch["name"] = .string(n)
            var log = ch["nameLog"].array ?? []
            log.append(.object(["w": .number(Double(s.week)), "from": .string(old)]))
            ch["nameLog"] = .array(log)
            var all = s.rest["chains"]?.array ?? []
            if let k = all.firstIndex(where: { $0["id"].int == chainID }) { all[k] = ch }
            s.rest["chains"] = .array(all)
            for c in stores {
                guard let i = s.companyIndex(c.id) else { continue }
                _ = Payments.companyPays(&s, companyID: c.id, amount: cost(c), category: "oth", label: "Rebranding to \(n)")
                s.companies[i].name = Chains.storeName(s, chain: ch, c, data: d)
                s.companies[i].awareness = jsRound(s.companies[i].awareness * 0.75 * 10) / 10
                s.companies[i].set("hype", min(100, s.companies[i].num("hype") + 12))
                s.companies[i].reputation = jsRound((s.companies[i].reputation + (55 - s.companies[i].reputation) * 0.35) * 10) / 10
            }
            s.note("\(old) is now \(n). All \(stores.count) stores carry the new name.", tone: "good")
            r = .ok
        }
        return r
    }

    @discardableResult mutating func closeCompany(companyID: Int, weeks: Int, giveUpRent: Bool = false, pauseSubscriptions: Bool = false) -> CloseResult {
        var r = CloseResult.unknown
        update { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            guard s.companies[i].status == .open else { r = .notOpen; return }
            if let why = PublicRules.restriction(s, companyID: companyID, change: .close) { r = .restricted(why); return }
            let prem = s.companies[i].value("prem")
            if giveUpRent, prem["m2"].double > 0, !prem["owned"].bool {
                _ = Payments.companyPays(&s, companyID: companyID, amount: prem["rent"].double * prem["m2"].double / 12 * 3, category: "rent", label: "Notice period")
                if prem["dep"].double > 0 { Payments.companyReceives(&s, companyID: companyID, amount: prem["dep"].double, category: nil, label: "Lease deposit returned") }
                s.companies[i].set("prem", .null)
            }
            s.companies[i].status = .closed
            s.companies[i].set("closeW", max(1, weeks)); s.companies[i].set("closeTot", max(1, weeks))
            s.companies[i].set("subPause", pauseSubscriptions)
            s.companies[i].set("idle", 0)
            r = .ok
        }
        return r
    }

    @discardableResult mutating func reopenCompany(companyID: Int) -> CloseResult {
        var r = CloseResult.unknown
        update { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            guard s.companies[i].status == .closed else { r = .notOpen; return }
            s.companies[i].status = .open
            s.companies[i].set("closeW", 0); s.companies[i].set("subPause", false); s.companies[i].set("idle", 0)
            r = .ok
        }
        return r
    }

    func windUpEstimate(companyID: Int) -> Double {
        guard let co = state.company(companyID), co.status.isLive else { return 0 }
        if state.isBranch(co) { return 0 }
        let (rest, _) = Self.windUpFigures(co, state)
        return max(0, rest) * co.ownership / 100
    }

    private static func billsOf(_ co: Company) -> Double {
        CompanyFigures.billsOwed(co)
    }

    private static func windUpFigures(_ co: Company, _ s: GameState) -> (rest: Double, debts: Double) {
        let cash: Double = max(0, CompanyFigures.assets(co)) * 0.55
        let loans: Double = s.loans.filter { $0.companyID == co.id }.reduce(0.0) { $0 + $1.balance }
        let bills = billsOf(co)
        return (cash - loans - bills, loans + bills)
    }

    @discardableResult mutating func windUpCompany(companyID: Int) -> Bool {
        if isBranch(companyID: companyID) { if case .success = closeBranch(storeID: companyID) { return true }; return false }
        var done = false
        update { s, _, _ in
            guard let i = s.companyIndex(companyID), s.companies[i].status.isLive else { return }
            HeldMoney.settle(&s, companyID: companyID)
            let co = s.companies[i]
            let cash: Double = max(0, CompanyFigures.assets(co)) * 0.55
            let ownLoans = s.loans.filter { $0.companyID == co.id }
            let loanSum: Double = ownLoans.reduce(0.0) { $0 + $1.balance }
            let bills = Self.billsOf(co)
            let frac = loanSum > 0 ? clamp((cash - bills) / loanSum, 0, 1) : 1
            var personal = 0.0
            for l in ownLoans {
                let left = l.balance * (1 - frac)
                if left > 1, l.isGuaranteed, let li = s.loans.firstIndex(where: { $0.id == l.id }) {
                    personal += left
                    Banking.close(loanID: l.id, repaid: l.balance * frac, state: &s)
                    if let k = s.loans.firstIndex(where: { $0.id == l.id }) { s.loans[k].name += " (taken over by you)"; s.loans[k].companyID = 0 } else { _ = li }
                } else {
                    Banking.close(loanID: l.id, repaid: l.balance * frac, state: &s)
                }
            }
            var rest = cash - loanSum - bills
            if rest < 0 { rest = 0 }
            if rest > 0 {
                Payments.playerReceives(&s, rest * co.ownership / 100, label: "Liquidation of \(co.name)", companyID: co.id)
            }
            for m in s.companies[i].staff { if var person = s.people[m.id] { person.employerID = 0; s.people[m.id] = person } }
            if let mid = s.companies[i].managerID, var mgr = s.people[mid] { mgr.employerID = 0; s.people[mid] = mgr }
            s.companies[i].staff = []
            s.companies[i].managerID = nil
            EquipmentMarket.endAllLeases(&s, companyIndex: i)
            s.companies[i].status = .sold
            s.stats.companiesSold += 1
            for k in s.inbox.indices where s.inbox[k].companyID == co.id && s.inbox[k].status == "open" { s.inbox[k].set("status", "done") }
            s.note("\(co.name) is closed down and its things sold.", companyID: co.id)
            done = true
        }
        return done
    }

    func guaranteeTerms(loanID: Int) -> LoanGuarantee.Terms? { LoanGuarantee.terms(state, loanID: loanID) }

    @discardableResult mutating func offerGuaranteeRelease(loanID: Int, extraMargin: Double) -> LoanGuarantee.Answer {
        var r = LoanGuarantee.Answer.notPossible("That loan no longer exists.")
        update { s, _, _ in r = LoanGuarantee.offer(&s, loanID: loanID, extraMargin: extraMargin) }
        return r
    }


    mutating func setInflationHold(companyID: Int, hold: Bool) {
        update { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            s.companies[i].set("inflHold", hold ? 1 : 0)
            if !hold { s.companies[i].set("ig", 1) }
        }
    }

    @discardableResult
    mutating func hire(personID: Int, companyID: Int, monthlyWage: Double, terms: Hiring.Terms = Hiring.Terms()) -> Hiring.HireResult {
        var r = Hiring.HireResult.refused
        if let co = state.company(companyID), Workplaces.hireBlock(co, role: state.people[personID]?.role, data: data) != nil { return .refused }
        update { s, data, _ in r = Hiring.hire(personID, into: companyID, monthlyWage: monthlyWage, state: &s, data: data, terms: terms) }
        return r
    }
    func busyMonths(companyID: Int) -> [Int] { state.company(companyID).map { StaffTalks.busyMonths($0, data: data) } ?? [] }

    func marketWage(role: String, companyID: Int) -> Double { Hiring.marketWage(role: role, company: state.company(companyID), state: state, data: data) }

    mutating func startTrialWeek(personID: Int, companyID: Int) -> [WorkLog.Observation]? {
        var r: [WorkLog.Observation]?
        update { s, data, _ in r = Hiring.trialWeek(personID, for: companyID, state: &s, data: data) }
        return r
    }
    var salesRoles: Set<String> { data.catalog.tables.salesRoles }

    @discardableResult mutating func lendWorker(from: Int, to: Int, role: String) -> Bool {
        var r = false
        update { s, d, _ in r = Chains.lendWorker(&s, from: from, to: to, role: role, data: d) }
        return r
    }
    func staffShortages(chainID: Int) -> [Chains.Shortage] { Chains.staffShortages(state, chainID: chainID, data: data) }

    func openComplaints(companyID: Int) -> [JSONValue] { state.company(companyID).map(Satisfaction.openComplaints) ?? [] }

    @discardableResult mutating func giveUpPremises(companyID: Int) -> Bool {
        var r = false
        update { s, d, _ in r = CompanySetup.giveUpPremises(&s, companyID: companyID, data: d) }
        return r
    }

    static func dayString(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    mutating func dailyGoal(now: Date = Date()) -> PlayerGoals.DailyGoal? {
        var r: PlayerGoals.DailyGoal?
        let cur = homeCurrency
        update { s, d, _ in r = PlayerGoals.dailyGoal(&s, today: Self.dayString(now), yesterday: Self.dayString(now.addingTimeInterval(-86400)), data: d, currency: cur) }
        return r
    }
    var dailyGoalsOff: Bool { PlayerGoals.dailyGoalsOff(state) }
    mutating func setDailyGoalsOff(_ off: Bool) { update { s, _, _ in PlayerGoals.setDailyGoalsOff(&s, off) } }
    var pendingCelebrations: [Celebration] { Celebrations.pending(state) }
    func pendingAwards() -> [AwardInfo] {
        Celebrations.pending(state).map { AwardInfo(id: String($0.id), title: $0.title, detail: $0.detail, tier: $0.tier, artKey: $0.art) }
    }
    mutating func takeCelebrations() -> [Celebration] {
        var r: [Celebration] = []
        update { s, _, _ in r = Celebrations.take(&s) }
        return r
    }

    private mutating func setFlag(_ companyID: Int, _ key: String, _ on: Bool) {
        update { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            var f = s.companies[i].value("flags")
            if f.isNull { f = .object([:]) }
            f[key] = .number(on ? 1 : 0)
            s.companies[i].set("flags", f)
        }
    }
}
