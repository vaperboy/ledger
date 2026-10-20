import Foundation
import GameCore
import Countries
import Employees
import Finance

/// Developing something new. A company runs one development project at a time: a new product line, a premium range, a menu
/// refresh, an own brand, an online shop, a store refit, a new service, automation. It costs money up front and takes weeks;
/// the team's skill and the company's quality decide whether it works fully, partly or not at all. What it gives fades as
/// rivals copy it: half of it is gone after about two years, 40% stays for good.
/// Original: features/company/product_development.js (`RD56`). State on the company: `rd56` = { run, done[] } and `rd56f`, the
/// current factors the weekly turn writes for `DemandModel.modifier` and the ticket price.
public enum Development {
    public struct Project: Equatable, Sendable {
        public var id: String, name: String, text: String
        /// "dem" demand, "tick" prices, "cogs" materials, "cap" capacity.
        public var kind: String
        public var size: Double
        public var weeks: Int
        /// Cost as a share of a year's sales.
        public var share: Double
    }

    static let table: [String: [Project]] = [
        "prod": [Project(id: "line", name: "A new product line", text: "More customers: about +6% demand", kind: "dem", size: 0.06, weeks: 16, share: 0.06),
                 Project(id: "prem", name: "A premium range", text: "People pay more: about +5% on prices", kind: "tick", size: 0.05, weeks: 20, share: 0.05),
                 Project(id: "lean", name: "A leaner process", text: "About 5% less on materials", kind: "cogs", size: 0.05, weeks: 12, share: 0.04)],
        "venue": [Project(id: "menu", name: "A new menu or concept", text: "More guests: about +5% demand", kind: "dem", size: 0.05, weeks: 8, share: 0.03),
                  Project(id: "sig", name: "A signature offer", text: "People pay more: about +4% on prices", kind: "tick", size: 0.04, weeks: 10, share: 0.03),
                  Project(id: "loyal", name: "A loyalty programme", text: "Regulars come back: about +4% demand", kind: "dem", size: 0.04, weeks: 6, share: 0.02)],
        "retail": [Project(id: "own", name: "An own brand", text: "Better margins: about 4% less on goods", kind: "cogs", size: 0.04, weeks: 18, share: 0.04),
                   Project(id: "web", name: "An online shop", text: "More customers: about +6% demand", kind: "dem", size: 0.06, weeks: 12, share: 0.04),
                   Project(id: "refit", name: "A store refit", text: "More customers: about +7% demand; partly closed while it is done", kind: "dem", size: 0.07, weeks: 6, share: 0.05)],
        "svc": [Project(id: "svc", name: "A new service", text: "More clients: about +6% demand", kind: "dem", size: 0.06, weeks: 12, share: 0.04),
                Project(id: "pack", name: "A fixed-price package", text: "Clients pay more: about +4% on prices", kind: "tick", size: 0.04, weeks: 8, share: 0.03),
                Project(id: "auto", name: "Automation and tools", text: "More done with the same team: about +5% capacity", kind: "cap", size: 0.05, weeks: 14, share: 0.04)],
        "other": [Project(id: "proc", name: "Better processes", text: "More done with the same people: about +5% capacity", kind: "cap", size: 0.05, weeks: 14, share: 0.04),
                  Project(id: "offer", name: "A new offer for customers", text: "More customers: about +4% demand", kind: "dem", size: 0.04, weeks: 12, share: 0.03)],
    ]

    public enum StartResult: Equatable, Sendable { case ok, notPossible, busy, recent, notEnoughCash }

    /// The projects a company can run (none for finance, energy, rental, clubs and holdings).
    public static func projects(for co: Company, data: GameData) -> [Project] {
        guard let bd = data.catalog[co.type] else { return [] }
        let f = bd.family
        if let t = table[f] { return t }
        return ["fin", "energy", "rent", "club", "hold"].contains(f) ? [] : table["other"]!
    }

    /// Cost of a project today: a share of a year's sales, at least a base amount. Original: `costOf`.
    public static func cost(_ p: Project, for co: Company, currency cur: Currency) -> Double {
        let yearly = max(co.value("lastW")["rev"].double * 52, co.monthlyHistory.suffix(12).reduce(0) { $0 + $1.revenue })
        return cur.roundedStep(max(cur.scaledPrice(40000), yearly * p.share), about: 1000)
    }

    /// The share of the effect still working: half is copied away after about two years, 40% stays for good. Original: `left`.
    static func remaining(_ d: JSONValue, week: Int) -> Double { 0.4 + 0.6 * pow(0.5, Double(week - d["w"].int) / 104) }

    public static func running(_ co: Company) -> (project: String, weeksLeft: Int, cost: Double)? {
        let r = co.value("rd56")["run"]
        return r.isNull ? nil : (r["k"].string, r["wEnd"].int, r["cost"].double)
    }
    public static func finished(_ co: Company) -> [JSONValue] { co.value("rd56")["done"].array }

    /// Original: `RD.start`.
    public static func start(_ s: inout GameState, companyID: Int, project id: String, data: GameData) -> StartResult {
        guard let i = s.companyIndex(companyID), let p = projects(for: s.companies[i], data: data).first(where: { $0.id == id }) else { return .notPossible }
        var r = s.companies[i].value("rd56")
        if r.isNull { r = .object(["run": .null, "done": .array([])]) }
        if !r["run"].isNull { return .busy }
        if r["done"].array.contains(where: { $0["k"].string == id && s.week - $0["w"].int < 104 }) { return .recent }
        let c = cost(p, for: s.companies[i], currency: World(state: s, data: data).currency(s.companies[i]))
        guard s.companies[i].cash >= c else { return .notEnoughCash }
        Payments.companyPays(&s, companyID: companyID, amount: c, category: "oth", label: "Development: \(p.name)")
        r["run"] = .object(["k": .string(id), "w0": .number(Double(s.week)), "wEnd": .number(Double(s.week + p.weeks)), "cost": .number(c)])
        s.companies[i].set("rd56", r)
        refreshFactors(&s, i)
        return .ok
    }

    /// Finish projects that are due and write the factors the demand, capacity, price and cost models read. Run once a week
    /// per company. Original: the 'development projects finish' step.
    public static func weekly(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData) {
        var r = s.companies[i].value("rd56")
        guard !r.isNull else { return }
        let co = s.companies[i]
        if !r["run"].isNull, s.week >= r["run"]["wEnd"].int, co.status.isLive {
            let k = r["run"]["k"].string
            r["run"] = .null
            if let p = projects(for: co, data: data).first(where: { $0.id == k }) {
                let salesRoles = data.catalog.tables.salesRoles
                let sk = co.staff.isEmpty ? 50 : co.staff.reduce(0.0) { $0 + StaffModel.skill($1, person: s.people[$1.id], salesRoles: salesRoles) } / Double(co.staff.count)
                let mgrBonus = co.managerID != nil ? (ManagerModel.quality(co, bd, people: s.people) - 0.5) * 0.3 : 0
                let odds = clamp(0.45 + (sk - 50) / 160 + (co.quality - 50) / 200 + mgrBonus, 0.15, 0.9)
                let z = s.random.next()
                let got = z < odds ? 1.0 : z < odds + (1 - odds) * 0.4 ? 0.5 : 0
                var done = r["done"].array
                if got > 0 { done.append(.object(["k": .string(p.id), "kind": .string(p.kind), "mag": .number(p.size * got), "w": .number(Double(s.week)), "n": .string(p.name)])) }
                if done.count > 12 { done.removeFirst() }
                r["done"] = .array(done)
                s.companies[i].set("rd56", r)
                s.addMessage(kind: "info", from: co.managerID.flatMap { s.people[$0]?.name } ?? co.name,
                             title: got == 1 ? "\(p.name) is a success" : got > 0 ? "\(p.name): a partial success" : "\(p.name) did not work out",
                             body: got == 1 ? "\(p.text). Rivals will copy it in time." : got > 0 ? "It works, but about half as well as hoped." : "Customers did not take to it. The money is spent.",
                             companyID: co.id, tone: got > 0 ? "good" : "bad")
            } else { s.companies[i].set("rd56", r) }
        }
        refreshFactors(&s, i)
    }

    /// The current effect of everything developed, as multipliers. A store refit under way costs a sixth of capacity.
    static func refreshFactors(_ s: inout GameState, _ i: Int) {
        let r = s.companies[i].value("rd56")
        guard !r.isNull else { return }
        func mult(_ kind: String) -> Double { r["done"].array.reduce(1) { $1["kind"].string == kind ? $0 * (1 + $1["mag"].double * remaining($1, week: s.week)) : $0 } }
        let refit = r["run"]["k"].string == "refit" ? 0.84 : 1
        s.companies[i].set("rd56f", .object(["dem": .number(mult("dem")), "tick": .number(mult("tick")), "cap": .number(mult("cap") * refit), "cogsup": .number(2 - mult("cogs"))]))
    }

    /// The factor for `DemandModel.modifier` ("dem", "cap", "cogsup") and the ticket price ("tick"). 1 when nothing was developed.
    static func factor(_ co: Company, _ key: String) -> Double {
        let f = co.value("rd56f")
        return f.isNull || f[key].isNull ? 1 : f[key].double
    }
}
