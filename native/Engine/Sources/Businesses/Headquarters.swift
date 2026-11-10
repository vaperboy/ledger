import Foundation
import GameCore
import Countries
import Employees
import Finance

public enum Headquarters {

    public struct Tier: Identifiable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var monthlyRent: Double
        public var desks: Int
        public var rooms: Int
        public var note: String
    }
    public struct Role: Identifiable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var monthlyPay: Double
        public var text: String
    }

    public static func tiers(_ data: GameData) -> [Tier] {
        data.catalog.tables.raw["OFFICE_T"].array.map { Tier(id: $0["id"].string, name: $0["n"].string, monthlyRent: $0["rentM"].double, desks: $0["desks"].int, rooms: $0["rooms"].int, note: $0["note"].string) }
    }
    public static func roles(_ data: GameData) -> [Role] {
        let order = ["pa", "hr", "acc", "law", "ana", "perf", "mkt", "proc", "strat", "fin"]
        let r = data.catalog.tables.raw["HQ_ROLES"]
        return order.compactMap { k in r[k].isNull ? nil : Role(id: k, title: k == "pa" ? "Personal assistant" : r[k][0].string, monthlyPay: r[k][1].double, text: r[k][2].string) }
    }
    public static func role(_ id: String, _ data: GameData) -> Role? { roles(data).first { $0.id == id } }

    static func office(_ s: GameState) -> JSONValue { s.rest["office"] ?? .null }
    public static func staff(_ s: GameState) -> [JSONValue] { office(s)["staff"].array }
    public static func tier(_ s: GameState, _ data: GameData) -> Tier? { tiers(data).first { $0.id == office(s)["tier"].string } }
    public static func has(_ s: GameState, _ role: String) -> Bool { s.hasHeadOffice(role) }

    public static func established(_ s: GameState) -> Bool {
        let o = office(s)
        if o.isNull { return false }
        if !o["set"].isNull || o["tier"].string != "home" || !o["staff"].array.isEmpty { return true }
        let md = s.rest["org56"]?["md"] ?? .null
        return !md.isNull && s.people[md["npc"].int] != nil
    }

    public static func monthlyCost(_ s: GameState, _ data: GameData) -> Double {
        guard let t = tier(s, data) else { return 0 }
        return staff(s).reduce(rent(s, tier: t, cityID: office(s)["city"].string, data: data) * 1.02) { $0 + $1["wage"].double * 1.14 }
    }

    static func officePayer(_ s: GameState, amount: Double) -> Company? {
        s.companies.first(where: { $0.type == "hold" && $0.status == .open && $0.cash > amount * 3 })
    }

    public static func employerName(_ s: GameState, _ data: GameData) -> String {
        officePayer(s, amount: max(1, monthlyCost(s, data)))?.name ?? "Your group office"
    }

    public static func fame(_ s: GameState, _ data: GameData) -> Double {
        let live = s.liveCompanies
        let nw = max(1, Valuation.netWorth(s, trades: data.catalog).total)
        var f = 11 * log10(max(1, nw / 3e5)) + 3 * Double(live.count)
        let w = World(state: s, data: data)
        let aw = live.map { $0.awareness }.max() ?? 0
        let ol = live.map { Double(Competition.chainOutlets($0, w)) }.max() ?? 1
        f += 0.25 * aw + 5 * log2(max(1, ol))
        f += Luxury.fameBonus(s) + 4 * Double(Abroad.foreignCountries(s).count)
        return clamp(f, 0, 100)
    }
    public static func fameLabel(_ f: Double) -> String { f >= 80 ? "World famous" : f >= 60 ? "Nationally famous" : f >= 40 ? "Well known in business" : f >= 20 ? "Known locally" : "Unknown" }
    public static func fameSalary(_ f: Double) -> Double { 0.75 + f / 55 }

    static func inflation(_ s: GameState, _ data: GameData) -> Double { World(state: s, data: data).inflationIndex }

    public static func rent(_ s: GameState, tier t: Tier, cityID: String, data: GameData) -> Double {
        let w = World(state: s, data: data)
        let cur = ManagerModel.playerCurrency(s, data)
        let country = w.countries[s.homeCountryCode]
        let rentIndex = country?.city(cityID)?.rent ?? 1
        return cur.tidy(cur.scaledPrice(t.monthlyRent) * rentIndex * w.inflationIndex)
    }

    public static func desksUsed(_ s: GameState) -> Int {
        staff(s).count + ManagerModel.regionals(s).filter { $0["payCo"].isNull }.count + ((s.rest["group"]?["ceo"].isNull ?? true) ? 0 : 1)
    }

    public enum RentResult: Equatable, Sendable { case ok, bad, desks, notEnoughCash }

    public static func rentOffice(_ s: inout GameState, tier id: String, cityID: String? = nil, data: GameData) -> RentResult {
        guard let t = tiers(data).first(where: { $0.id == id }) else { return .bad }
        let old = office(s)
        let city = cityID ?? s.player.cityID
        if staff(s).count + desksUsedOutsideStaff(s) > t.desks { return .desks }
        let cost = rent(s, tier: t, cityID: city, data: data)
        if !old.isNull && old["tier"].string != id {
            if Payments.liquid(s) < cost { return .notEnoughCash }
            Payments.playerPays(&s, cost, label: "Office move: first month deposit")
        }
        s.rest["office"] = .object(["tier": .string(id), "city": .string(city), "since": .number(Double(s.week)), "staff": old["staff"].isNull ? .array([]) : old["staff"],
                                    "perfAuto": old["perfAuto"], "set": .number(Double(s.week))])
        return .ok
    }
    static func desksUsedOutsideStaff(_ s: GameState) -> Int { desksUsed(s) - staff(s).count }

    public static func setPerformanceAuto(_ s: inout GameState, _ on: Bool) { var o = office(s); o["perfAuto"] = .bool(on); s.rest["office"] = o }

    public static func unlocked(_ s: GameState, _ role: String, _ data: GameData) -> Bool {
        let live = s.liveCompanies
        let n = live.count, mgrs = live.filter { $0.managerID != nil }.count, staffN = live.reduce(0) { $0 + $1.staff.count }
        switch role {
        case "pa": return true
        case "hr": return n >= 2 || staffN >= 8
        case "acc", "proc": return n >= 2
        case "law", "ana", "mkt": return n >= 3
        case "perf": return mgrs >= 2
        case "strat": return n >= 4 && Valuation.netWorth(s, trades: data.catalog).total >= ManagerModel.playerCurrency(s, data).scaledPrice(2e7)
        case "fin": return s.companies.contains { $0.type == "hold" && $0.status == .open }
        default: return true
        }
    }
    public static func unlockText(_ role: String) -> String {
        ["hr": "2 companies or 8 staff", "acc": "2 companies", "law": "3 companies", "ana": "3 companies", "proc": "2 companies", "perf": "2 managed companies",
         "mkt": "3 companies", "strat": "4 companies and a large net worth", "fin": "a holding company"][role] ?? ""
    }

    public enum RoomResult: String, Equatable, Sendable { case ok, office, bad, locked, have, homeoffice, desks }

    public static func room(_ s: GameState, role: String, data: GameData) -> RoomResult {
        if !established(s) { return .office }
        if self.role(role, data) == nil { return .bad }
        if !unlocked(s, role, data) { return .locked }
        if has(s, role) { return .have }
        if office(s)["tier"].string == "home" { return role == "pa" ? .ok : .homeoffice }
        if let t = tier(s, data), desksUsed(s) >= t.desks { return .desks }
        return .ok
    }

    public static func result(_ s: GameState, role: String, data: GameData) -> String {
        let cos = s.liveCompanies.filter { $0.status == .open }
        switch role {
        case "pa": return "Your right hand: every decision waits one more week, and they sit on every board."
        case "hr": return "Fewer quits and problem workers among \(cos.reduce(0) { $0 + $1.staff.count }) staff in \(cos.count) companies."
        case "acc": return "Accountant fees x0.8 in all companies."
        case "law": return "Fines and legal fees x0.85 or less in all companies."
        case "ana": return "Detailed reports on sales, capacity and outlook."
        case "perf": return "Monthly scorecards for \(cos.filter { $0.managerID != nil }.count) managed companies."
        case "mkt": return "Campaigns work about 10% better in \(cos.count) companies."
        case "proc": return "Best supplier deals for every manager."
        case "strat": return "A written memo with concrete suggestions for each company every quarter."
        case "fin": return "Runs your holding companies."
        default: return ""
        }
    }

    public enum SearchMode: String, Sendable { case network, ad, agency }

    public static func search(_ s: inout GameState, role: String, mode: SearchMode, data: GameData) -> [Person]? {
        guard room(s, role: role, data: data) == .ok, let r = self.role(role, data) else { return nil }
        let cur = ManagerModel.playerCurrency(s, data)
        let cost = mode == .ad ? cur.scaledPrice(1500) : mode == .agency ? cur.scaledPrice(12000) : 0
        if mode == .network {
            var cd = s.rest["netCD"] ?? .object([:])
            if cd["hq:\(role)"].double > Double(s.week) { return nil }
            cd["hq:\(role)"] = .number(Double(s.week + 4)); s.rest["netCD"] = cd
        }
        if cost > 0 { guard s.cash >= cost else { return nil }; Payments.playerPays(&s, cost, label: "Recruiting") }
        let f = fame(s, data), cap = Double(Int(saturating: (42 + f * 0.58).rounded()))
        let count = mode == .agency ? 4 : mode == .ad ? 3 : 2
        return (0..<count).map { _ in
            var n = ManagerModel.generateCandidate(company: nil, type: "gen", state: &s, data: data)
            n.role = "hq_\(role)"
            if n.skill > cap { n.skill = cap; n.claimedSkill = min(n.claimedSkill, cap + 8) }
            n.askingMonthlyWage = cur.roundedStep(cur.scaledPrice(r.monthlyPay) * (0.6 + n.skill / 120) * fameSalary(f), about: 100)
            if mode == .agency { n.set("checked", true) }
            s.people[n.id] = n
            return n
        }
    }

    public enum HireResult: Equatable, Sendable { case ok, refuse, taken, blocked(RoomResult), countered(Negotiation.Counter), walkedAway }

    public static func goingRate(role: String, state s: GameState, data: GameData) -> Double {
        guard let r = self.role(role, data) else { return 0 }
        return ManagerModel.playerCurrency(s, data).roundedStep(ManagerModel.playerCurrency(s, data).scaledPrice(r.monthlyPay) * fameSalary(fame(s, data)), about: 100)
    }

    public static func hire(_ s: inout GameState, role: String, personID: Int, monthlyWage wage: Double, data: GameData) -> HireResult {
        let r = room(s, role: role, data: data)
        guard r == .ok, let n0 = s.people[personID] else { return .blocked(r) }
        if n0.employerID != 0 { return .taken }
        switch Hiring.answer(personID: personID, employer: -3, rank: "headOffice", offer: wage, currency: ManagerModel.playerCurrency(s, data), about: 100, state: &s).answer {
        case .refuse: return .refuse
        case .walkAway: return .walkedAway
        case .counter(let c): return .countered(c)
        case .accept: break
        }
        guard var n = s.people[personID] else { return .refuse }
        n.employerID = -3
        s.people[personID] = n
        var o = office(s)
        var l = o["staff"].array
        l.append(.object(["id": .number(Double(personID)), "role": .string(role), "name": .string(n.name), "wage": .number(wage), "w0": .number(Double(s.week))]))
        o["staff"] = .array(l)
        s.rest["office"] = o
        s.note("\(n.name) joins your main office as \(self.role(role, data)?.title.lowercased() ?? role).", tone: "good")
        return .ok
    }

    @discardableResult
    public static func fire(_ s: inout GameState, personID: Int) -> Bool {
        guard var o = s.rest["office"], o["staff"].array.contains(where: { $0["id"].int == personID }) else { return false }
        if var n = s.people[personID] { n.employerID = 0; s.people[personID] = n }
        o["staff"] = .array(o["staff"].array.filter { $0["id"].int != personID })
        s.rest["office"] = o
        ManagerModel.removeSeat(&s, personID: personID)
        return true
    }

    static func payHeadOffice(_ s: inout GameState, _ amt: Double, label: String) {
        let a = jsRound(amt)
        if a <= 0 { return }
        if let h = officePayer(s, amount: a) {
            Payments.companyPays(&s, companyID: h.id, amount: a, category: "wages", label: label)
            return
        }
        Payments.playerPays(&s, a, label: label)
    }

    static func monthly(_ s: inout GameState, data: GameData) {
        guard let t = tier(s, data) else { return }
        let o = office(s)
        var cost = rent(s, tier: t, cityID: o["city"].string, data: data) * 1.02
        for x in o["staff"].array { cost += x["wage"].double * 1.14 }
        if cost > 0 { payHeadOffice(&s, cost, label: "Main office and its staff") }
        if GameCalendar.monthIndex(week: s.week) % 3 == 2 && has(s, "strat") { strategyMemo(&s, data: data) }
        let auto = o["perfAuto"].isNull ? true : o["perfAuto"].bool
        if has(s, "perf") && auto { managerScorecards(&s, data: data) }
    }

    public struct Scorecard: Identifiable, Equatable, Sendable {
        public var id: Int
        public var companyName: String
        public var managerName: String
        public var score: Int
        public var margin: Double
        public var reputation: Int
        public var quality: Int
        public var fraud: Double
        public var weeks: Int
    }

    public static func review(_ s: GameState, companyID: Int) -> Scorecard? {
        guard let co = s.company(companyID), let mid = co.managerID, let n = s.people[mid] else { return nil }
        let h = Array(co.monthlyHistory.suffix(3))
        let rev = h.reduce(0) { $0 + $1.revenue }, pr = h.reduce(0) { $0 + $1.profit }
        let margin = rev > 0 ? pr / rev : 0
        let mist = n.num("mist"), fraud = co.value("flags")["fraud"].double
        let tl = co.value("tg58")["log"].array.suffix(3)
        let tg: Double? = tl.isEmpty ? nil : tl.reduce(0.0) { $0 + $1["n"].double / max(1, $1["of"].double) } / Double(tl.count)
        let score = jsRound(clamp(50 + clamp(margin * 100, -25, 25) * 0.9 + (co.reputation - 50) * 0.3 + (co.quality - 50) * 0.2 - mist * 4 - (fraud > 0 ? 25 : 0) + (tg.map { ($0 - 0.5) * 20 } ?? 0), 0, 100))
        return Scorecard(id: co.id, companyName: co.name, managerName: n.name, score: Int(score), margin: margin, reputation: Int(saturating: jsRound(co.reputation)), quality: Int(saturating: jsRound(co.quality)),
                         fraud: fraud, weeks: s.week - co.int("mgrW0"))
    }
    @discardableResult
    public static func managerScorecards(_ s: inout GameState, data: GameData) -> [Scorecard] {
        let L = s.companies.filter { ($0.status == .open || $0.status == .closed) && $0.managerID != nil }.compactMap { review(s, companyID: $0.id) }.sorted { $0.score > $1.score }
        guard let best = L.first, let worst = L.last else { return [] }
        for c in L { if let i = s.companyIndex(c.id) { s.companies[i].set("lastRev", .object(["score": .number(Double(c.score)), "w": .number(Double(s.week))])) } }
        func f(_ x: Scorecard) -> String {
            "\(x.companyName) (\(x.managerName)): " + (x.score >= 80 ? "excellent" : x.score >= 65 ? "good" : x.score >= 50 ? "acceptable" : x.score >= 35 ? "weak" : "poor")
        }
        if has(s, "perf") {
            s.addMessage(kind: "info", from: staff(s).first { $0["role"].string == "perf" }?["name"].string ?? "Performance analyst", title: "Manager scorecards",
                         body: "Best: \(f(best))" + (L.count > 1 ? ". Weakest: \(f(worst))" : "") + ".", tone: worst.score < 40 ? "bad" : "good", status: "done", sev: 1)
        }
        return L
    }

    static func strategyMemo(_ s: inout GameState, data: GameData) {
        guard has(s, "strat") else { return }
        var out: [String] = []
        for co in s.companies where co.status == .open {
            let u: Double? = co.value("lastW")["util"].isNull ? nil : co.value("lastW")["util"].double
            let wc = max(1, ManagerModel.weekCost(s, co, data: data))
            let h = co.monthlyHistory.suffix(3)
            let rev = h.reduce(0) { $0 + $1.revenue }, pr = h.reduce(0) { $0 + $1.profit }
            var l: [String] = []
            if rev > 0 && pr / rev < 0.03 { l.append("Margins are thin (\(Int(saturating: jsRound(pr / rev * 100)))%). Review prices and supplier terms.") }
            if let u = u, u > 0.95 { l.append("Demand is above what we can deliver. Add staff, equipment or space.") }
            if let u = u, u < 0.5 { l.append("Less than half of capacity is used. Push marketing before adding cost.") }
            if co.cash < wc * 8 { l.append("Cash is thin. Hold off on new spending.") }
            if co.cash > wc * 40 && pr > 0 { l.append("Idle cash. Pay a dividend or expand.") }
            if co.reputation < 45 { l.append("Reputation is weak. Fix service quality before spending on ads.") }
            if co.managerID == nil && co.staff.count >= 6 { l.append("The team is large enough to justify a manager.") }
            if !l.isEmpty { out.append("\(co.name): " + l.prefix(3).joined(separator: " ")) }
        }
        s.addMessage(kind: "info", from: staff(s).first { $0["role"].string == "strat" }?["name"].string ?? "Strategy analyst", title: "Quarterly strategy memo",
                     body: out.isEmpty ? "No concerns this quarter. All companies look healthy." : out.joined(separator: "\n"), tone: "n", status: "done", sev: 1)
    }

    public struct RightHand: Equatable, Sendable {
        public var personID: Int
        public var decidesForYou: Bool
        public var briefing: String
    }

    public static func rightHand(_ s: GameState) -> RightHand? {
        guard let pa = staff(s).first(where: { $0["role"].string == "pa" && s.people[$0["id"].int] != nil }) else { return nil }
        let lh = s.rest["lh"] ?? .null
        return RightHand(personID: pa["id"].int, decidesForYou: lh["auto"].isNull ? true : lh["auto"].bool, briefing: lh["brief"].isNull ? "month" : lh["brief"].string)
    }
    public static func setRightHand(_ s: inout GameState, decidesForYou: Bool? = nil, briefing: String? = nil) {
        var lh = s.rest["lh"] ?? .object(["auto": 1, "brief": "month", "pa": 1])
        if let a = decidesForYou { lh["auto"] = .number(a ? 1 : 0) }
        if let b = briefing { lh["brief"] = .string(b) }
        s.rest["lh"] = lh
    }
}
