import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Small player actions of the original that belong to none of the bigger systems: renaming, closing and winding up
/// a company, turning a sole trader into a limited company, and a few switches on a company.
/// Original: features/company/rename_and_rebrand.js, features/people/owner_hours_clients_assistants.js (`clgo`, `reopen`),
/// engine/core/api.js `windUp`, engine/company/company.js `convertToAS`, ui/company/money.js `ccheck`, ui/company/family.js `autostock`,
/// features/sales/realistic_odds.js `inflset`.
public extension GameEngine {
    enum RenameResult: Equatable, Sendable { case ok, tooShort, nameTaken, notEnoughCash, partOfChain, unknown }
    enum CloseResult: Equatable, Sendable { case ok, unknown, notOpen }
    enum ConvertResult: Equatable, Sendable { case ok, alreadyLimited, notEnoughCash, unknown }

    /// New name and signs for one company. Original: `renameCost`.
    func renameCost(companyID: Int) -> Double {
        guard let co = state.company(companyID) else { return 0 }
        let cur = context.currency(co.countryCode, state)
        return jsRound((cur.scaledPrice(2500) + cur.scaledPrice(15000) * co.size) / 500) * 500
    }

    /// Cost for one store of a chain to rebrand. Original: `rebrandCost`.
    func rebrandCost(companyID: Int) -> Double {
        guard let co = state.company(companyID) else { return 0 }
        return jsRound(context.currency(co.countryCode, state).scaledPrice(40000) * co.size / 1000) * 1000
    }

    private func nameIsTaken(_ n: String, except ids: Set<Int>) -> Bool {
        state.companies.contains { $0.status.isLive && !ids.contains($0.id) && $0.name.lowercased() == n.lowercased() }
    }

    /// Original: `ACT.rn56go`. A third of those who knew the old name lose track of you.
    @discardableResult mutating func renameCompany(companyID: Int, to newName: String) -> RenameResult {
        let n = newName.trimmingCharacters(in: .whitespaces)
        var r = RenameResult.unknown
        let cost = renameCost(companyID: companyID)
        update { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            if Chains.chain(s, of: s.companies[i]) != nil { r = .partOfChain; return }
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

    /// Every store of the chain gets the new name; each pays its own signs. Original: `ACT.rb56go`.
    @discardableResult mutating func renameChain(chainID: Int, to newName: String) -> RenameResult {
        let n = newName.trimmingCharacters(in: .whitespaces)
        var r = RenameResult.unknown
        update { s, _, ctx in
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
                var nm = stores.count == 1 ? n : "\(n) \(c.cityID)", k = 2
                while s.companies.contains(where: { $0.status.isLive && $0.id != c.id && $0.name.lowercased() == nm.lowercased() }) { nm = "\(n) \(c.cityID) \(k)"; k += 1 }
                s.companies[i].name = nm
                s.companies[i].awareness = jsRound(s.companies[i].awareness * 0.75 * 10) / 10
                s.companies[i].set("hype", min(100, s.companies[i].num("hype") + 12))
                s.companies[i].reputation = jsRound((s.companies[i].reputation + (55 - s.companies[i].reputation) * 0.35) * 10) / 10
            }
            s.note("\(old) is now \(n). All \(stores.count) stores carry the new name.", tone: "good")
            r = .ok
        }
        return r
    }

    /// Close a company for some weeks; a rented space can be given up (three months' rent, deposit back). Original: `ACT.clgo`.
    @discardableResult mutating func closeCompany(companyID: Int, weeks: Int, giveUpRent: Bool = false, pauseSubscriptions: Bool = false) -> CloseResult {
        var r = CloseResult.unknown
        update { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            guard s.companies[i].status == .open else { r = .notOpen; return }
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

    /// Original: `ACT.reopen`.
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

    /// What winding the company up would pay you: its assets fetch about 55%, debts and loans come first. Original: `windUp`.
    func windUpEstimate(companyID: Int) -> Double {
        guard let co = state.company(companyID), co.status.isLive else { return 0 }
        let (rest, _) = Self.windUpFigures(co, state)
        return max(0, rest) * co.ownership / 100
    }

    private static func billsOf(_ co: Company) -> Double {
        let p = co.payables
        var b: Double = p["wages"] ?? 0
        b += p["other"] ?? 0
        b += p["inv"] ?? 0
        b += p["rent"] ?? 0
        b += max(0, co.vatBalance)
        b += p["tax"] ?? 0
        return b
    }

    private static func windUpFigures(_ co: Company, _ s: GameState) -> (rest: Double, debts: Double) {
        let cash: Double = max(0, co.cash) + max(0, CompanyFigures.assets(co) - co.cash) * 0.55
        let loans: Double = s.loans.filter { $0.companyID == co.id }.reduce(0.0) { $0 + $1.balance }
        let bills = billsOf(co)
        return (cash - loans - bills, loans + bills)
    }

    /// Everything sold at a discount, staff released, loans repaid as far as the money goes. Original: `ACT.winduo` / `windUp`.
    @discardableResult mutating func windUpCompany(companyID: Int) -> Bool {
        var done = false
        update { s, _, _ in
            guard let i = s.companyIndex(companyID), s.companies[i].status.isLive else { return }
            let co = s.companies[i]
            let cash: Double = max(0, co.cash) + max(0, CompanyFigures.assets(co) - co.cash) * 0.55
            let ownLoans = s.loans.filter { $0.companyID == co.id }
            let loanSum: Double = ownLoans.reduce(0.0) { $0 + $1.balance }
            let bills = Self.billsOf(co)
            let frac = loanSum > 0 ? clamp((cash - bills) / loanSum, 0, 1) : 1
            var personal = 0.0
            for l in ownLoans {
                let left = l.balance * (1 - frac)
                if left > 1, l.isGuaranteed || co.form == .soleTrader, let li = s.loans.firstIndex(where: { $0.id == l.id }) {
                    personal += left
                    Banking.close(loanID: l.id, repaid: l.balance * frac, state: &s)
                    if let k = s.loans.firstIndex(where: { $0.id == l.id }) { s.loans[k].name += " (taken over by you)"; s.loans[k].companyID = 0 } else { _ = li }
                } else {
                    Banking.close(loanID: l.id, repaid: l.balance * frac, state: &s)
                }
            }
            var rest = cash - loanSum - bills
            if rest < 0 {
                if co.form == .soleTrader { Ledger.move(&s, .me, min(0, rest + personal), why: "Shortfall winding up \(co.name)") }
                rest = 0
            }
            if rest > 0 {
                Payments.playerReceives(&s, rest * co.ownership / 100, label: co.form == .soleTrader ? "Closing \(co.name)" : "Liquidation of \(co.name)", companyID: co.id)
            }
            for m in s.companies[i].staff { if var person = s.people[m.id] { person.employerID = 0; s.people[m.id] = person } }
            if let mid = s.companies[i].managerID, var mgr = s.people[mid] { mgr.employerID = 0; s.people[mid] = mgr }
            s.companies[i].staff = []
            s.companies[i].managerID = nil
            s.companies[i].status = .sold
            Ledger.set(&s, .company(co.id), to: 0)
            s.stats.companiesSold += 1
            for k in s.inbox.indices where s.inbox[k].companyID == co.id && s.inbox[k].status == "open" { s.inbox[k].set("status", "done") }
            for k in s.companies.indices where s.companies[k].holdingID == co.id { s.companies[k].holdingID = 0 }
            s.note("\(co.name) is closed down and its things sold.", companyID: co.id)
            done = true
        }
        return done
    }

    /// Turn a sole trader into a limited company: registration and share capital come from your own account. Original: `convertToAS`.
    @discardableResult mutating func convertToLimited(companyID: Int) -> ConvertResult {
        var r = ConvertResult.unknown
        update { s, data, _ in
            guard let i = s.companyIndex(companyID), let country = data.countries[s.companies[i].countryCode] else { return }
            if s.companies[i].form == .limited { r = .alreadyLimited; return }
            let need = country.shareCapitalMinimum + country.registrationFee
            if s.cash < need { r = .notEnoughCash; return }
            Payments.playerPays(&s, country.registrationFee, label: "Registration and conversion fee", companyID: companyID)
            Payments.playerPays(&s, country.shareCapitalMinimum, label: "Share capital", companyID: companyID)
            Ledger.moveRaw(&s, .company(companyID), country.shareCapitalMinimum)
            s.companies[i].ownerNetFlow += country.shareCapitalMinimum
            s.companies[i].shareCapital = country.shareCapitalMinimum
            s.companies[i].injectedCapital += country.shareCapitalMinimum
            s.companies[i].form = .limited
            s.companies[i].addTransaction(week: s.week, amount: country.shareCapitalMinimum, label: "Share capital paid in")
            s.note("\(s.companies[i].name) is now a limited company.", tone: "good", companyID: companyID)
            r = .ok
        }
        return r
    }

    /// Check customers' credit before selling on account (a switch). Original: `ACT.ccheck`.
    mutating func setCreditCheck(companyID: Int, on: Bool) { setFlag(companyID, "ccheck", on) }
    /// Salmon farm stocking by itself (a switch). Original: `ACT.autostock`.
    mutating func setAutoStock(companyID: Int, on: Bool) { setFlag(companyID, "autoStock", on) }

    /// Let prices follow inflation by themselves or hold them where you set them. Original: `ACT.inflset`.
    mutating func setInflationHold(companyID: Int, hold: Bool) {
        update { s, _, _ in
            guard let i = s.companyIndex(companyID) else { return }
            s.companies[i].set("inflHold", hold ? 1 : 0)
            if !hold { s.companies[i].set("ig", 1) }
        }
    }

    // MARK: Staff: employment types, trial week, pay model, car

    /// THE way to hire a candidate (every worker hire goes through here to `Hiring.hire`): checks the offer against the ask, lifts it to the minimum wage,
    /// books the hire, makes the staff record and its paperwork, and answers `.ok`, `.taken` (has a job) or `.refused` (offer too low, or unknown person/company).
    /// Terms: full time with a chosen pay basis (the default), part time (weekly hours), seasonal (months), own car (estate agents only). Original: `HIRE_HOURS`, `HIRE_SEAS`, `HIRE_BASIS`, `ACT.offer` + `carc`.
    @discardableResult
    mutating func hire(personID: Int, companyID: Int, monthlyWage: Double, terms: Hiring.Terms = Hiring.Terms()) -> Hiring.HireResult {
        var r = Hiring.HireResult.refused
        update { s, data, _ in r = Hiring.hire(personID, into: companyID, monthlyWage: monthlyWage, state: &s, data: data, terms: terms) }
        return r
    }
    /// The months of the year a seasonal hire would be for by default: the busy months of the trade.
    func busyMonths(companyID: Int) -> [Int] { state.company(companyID).map { StaffTalks.busyMonths($0, data: data) } ?? [] }

    /// What the job normally pays here at full time: the employer's opening offer in a pay discussion, the same for everyone in the role.
    func marketWage(role: String, companyID: Int) -> Double { Hiring.marketWage(role: role, company: state.company(companyID), state: state, data: data) }

    /// Pay for a trial week and see what the person can really do. Original: `ACT.trial`.
    mutating func startTrialWeek(personID: Int, companyID: Int) -> Double? {
        var r: Double?
        update { s, data, _ in r = Hiring.trialWeek(personID, for: companyID, state: &s, data: data) }
        return r
    }
    mutating func setStaffHours(companyID: Int, staffID: Int, hours: Double) -> StaffTalks.OfferResult {
        var r = StaffTalks.OfferResult.unknown
        update { s, _, _ in r = StaffTalks.setStaffHours(&s, companyID: companyID, staffID: staffID, hours: hours) }
        return r
    }
    mutating func offerFullTime(companyID: Int, staffID: Int) -> StaffTalks.OfferResult {
        var r = StaffTalks.OfferResult.unknown
        update { s, d, _ in r = StaffTalks.offerFullTime(&s, companyID: companyID, staffID: staffID, data: d) }
        return r
    }
    mutating func offerPartTime(companyID: Int, staffID: Int, hours: Double = 20) -> StaffTalks.OfferResult {
        var r = StaffTalks.OfferResult.unknown
        update { s, _, _ in r = StaffTalks.offerPartTime(&s, companyID: companyID, staffID: staffID, hours: hours) }
        return r
    }
    @discardableResult mutating func toggleSeason(companyID: Int, staffID: Int, season: String) -> Bool {
        var r = false
        update { s, _, _ in r = StaffTalks.toggleSeason(&s, companyID: companyID, staffID: staffID, season: season) }
        return r
    }
    @discardableResult mutating func offerFixedSalary(companyID: Int, staffID: Int) -> Bool {
        var r = false
        update { s, d, _ in r = StaffTalks.offerFixedSalary(&s, companyID: companyID, staffID: staffID, data: d) }
        return r
    }
    // setPayModel and toggleOwnCar live in CompanyTabActions and PremisesActions (one wrapper each).
    /// Roles that sell and can be paid by commission.
    var salesRoles: Set<String> { data.catalog.tables.salesRoles }
    /// Why a person turned down an offer, in words.
    func refusalReason(companyID: Int, staffID: Int, want: String) -> String {
        guard let m = state.company(companyID)?.staff.first(where: { $0.id == staffID }) else { return "" }
        return StaffTalks.wishWhy(m, name: state.people[staffID]?.name ?? "", want: want)
    }

    // MARK: Chains, complaints, premises, accountant, development

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
    @discardableResult mutating func changeAccountant(companyID: Int, accountantID: Int) -> Bool {
        var r = false
        update { s, d, _ in r = CompanySetup.changeAccountant(&s, companyID: companyID, accountantID: accountantID, data: d) }
        return r
    }

    /// The accountants on offer in the company's country: id, name, fee a month, rating (1 to 5), and whether it is the current one.
    func accountantChoices(companyID: Int) -> [(id: Int, name: String, fee: Double, rating: Double, current: Bool)] {
        guard let co = state.company(companyID) else { return [] }
        var tmp = state
        let pool = Providers.pool(for: co.countryCode, state: &tmp, countries: data.countries).accountants
        return pool.map { ($0["id"].int, $0["name"].string, $0["fee"].double, $0["rating"].double, $0["id"].int == co.value("acc")["id"].int) }
    }

    func developmentProjects(companyID: Int) -> [(project: Development.Project, cost: Double)] {
        guard let co = state.company(companyID) else { return [] }
        let cur = context.currency(co.countryCode, state)
        return Development.projects(for: co, data: data).map { ($0, Development.cost($0, for: co, currency: cur)) }
    }
    mutating func startDevelopment(companyID: Int, project: String) -> Development.StartResult {
        var r = Development.StartResult.notPossible
        update { s, d, _ in r = Development.start(&s, companyID: companyID, project: project, data: d) }
        return r
    }

    // MARK: Goals

    /// "yyyy-m-d" of a real date, the key of the daily goal.
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
    @discardableResult mutating func claimDailyGoal(now: Date = Date()) -> Double? {
        var r: Double?
        let cur = homeCurrency
        update { s, d, _ in r = PlayerGoals.claimDailyGoal(&s, today: Self.dayString(now), yesterday: Self.dayString(now.addingTimeInterval(-86400)), data: d, currency: cur) }
        return r
    }
    var firstStepRewards: [PlayerGoals.FirstStep]? { PlayerGoals.firstSteps(state) }
    var firstStepRewardsHidden: Bool { PlayerGoals.firstStepsHidden(state) }
    mutating func claimFirstStep(id: String) -> String? {
        var r: String?
        let cur = homeCurrency
        update { s, _, _ in r = PlayerGoals.claimFirstStep(&s, id: id, currency: cur) }
        return r
    }
    mutating func setFirstStepsHidden(_ hidden: Bool) { update { s, _, _ in PlayerGoals.setFirstStepsHidden(&s, hidden) } }


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
