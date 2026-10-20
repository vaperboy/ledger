import Foundation
import GameCore
import Countries
import Finance

/// Real-estate development: buy land, wait for zoning (which can be refused), build, sell the units. Original: `FAM.dev`
/// (engine/company/family_project.js) and the "Development projects" screen (ui/company/family.js).
///
/// The money: land and building costs are paid in cash as they fall due but are not an expense; they build up as
/// work in progress (an asset, `fm.assets`). Each unit sold books its share of that work in progress as cost of sales and
/// its price as revenue, so profit arrives in lumps, years after the first payment. A construction loan (up to 70% of the
/// building cost plus most of the land) is repaid from 70% of every sale.
public enum ProjectDeveloper {
    /// One development (a record in `fm.proj`; field names are the original's).
    public struct Project: JSONRecord, Identifiable {
        public var raw: [String: JSONValue]
        public init(raw: [String: JSONValue]) { self.raw = raw }
        public var id: Int { int("id") }
        public var name: String { get { str("name") } set { set("name", newValue) } }
        public var units: Int { get { int("units") } set { set("units", newValue) } }
        public var land: Double { get { num("land") } set { set("land", newValue) } }
        public var build: Double { get { num("build") } set { set("build", newValue) } }
        /// "zoning", "build", "sell" or "done"
        public var stage: String { get { str("st") } set { set("st", newValue) } }
        /// Weeks left of the current stage.
        public var weeksLeft: Int { get { int("wl") } set { set("wl", newValue) } }
        public var sold: Int { get { int("sold") } set { set("sold", newValue) } }
        public var revenue: Double { get { num("rev") } set { set("rev", newValue) } }
        public var unitPrice: Double { get { num("price") } set { set("price", newValue) } }
        public var priceMultiplier: Double { get { num("priceMult", 1) } set { set("priceMult", newValue) } }
        public var spent: Double { get { num("spent") } set { set("spent", newValue) } }
        /// Work in progress: what has been paid and not yet booked as cost of sales.
        public var workInProgress: Double { get { num("wip") } set { set("wip", newValue) } }
        /// Cost overrun added to the building cost.
        public var overrun: Double { get { num("over") } set { set("over", newValue) } }
        public var loanID: Int { get { int("loan") } set { set("loan", newValue) } }
        public var delay: Int { get { int("delay") } set { set("delay", newValue) } }
        public var isActive: Bool { stage != "done" }
    }

    public enum StartResult: Equatable { case started(Int), notEnoughCash, loanRefused, notADeveloper }

    /// What a project of a given size would cost and bring. Original: the numbers in `FAM.dev.start`.
    public struct Quote: Equatable {
        public var size: Double
        public var land: Double, build: Double, units: Int, fee: Double
        /// Cash needed now: land (or its 35% down payment when financed) and the zoning work.
        public var cashNow: Double
        public var financed: Bool
        public var loanAmount: Double
        public var unitPrice: Double
        public var expectedRevenue: Double
        public var totalCost: Double { land + build }
    }

    public static func projects(_ co: Company) -> [Project] { co.value("fm")["proj"].array.map { Project(raw: $0.object) } }
    static func setProjects(_ s: inout GameState, _ i: Int, _ list: [Project]) {
        var fm = s.companies[i].value("fm")
        fm["proj"] = .array(list.map { .object($0.raw) })
        fm["assets"] = .number(list.reduce(0) { $0 + $1.workInProgress })
        s.companies[i].set("fm", fm)
    }

    public static func quote(_ co: Company, _ bd: Trade, size sz: Double, financed: Bool, world w: World, homeCurrency: Currency) -> Quote {
        let tw = bd.traits
        let city = w.city(co)
        let land = homeCurrency.roundedStep((tw["land"] ?? 0) * sz * (city?.rent ?? 1) * w.economy.housing, about: 1000)
        let build = homeCurrency.roundedStep((tw["build"] ?? 0) * sz * (city?.price ?? 1) * w.economy.materials, about: 1000)
        let units = max(4, Int(jsRound((tw["units"] ?? 24) * sz)))
        let fee = (w.catalog.tables.raw["DOCS"]["regplan"][2].double) * sz.squareRoot()
        let down = financed ? land * 0.35 : land
        let loan = financed ? land - down + build * 0.7 : 0
        let unitPrice = homeCurrency.roundedStep((land + build) * 1.38 / Double(units) * Knobs.effect(co, bd, "t", w), about: 1000)
        return Quote(size: sz, land: land, build: build, units: units, fee: fee, cashNow: down + fee, financed: financed, loanAmount: loan,
                     unitPrice: unitPrice, expectedRevenue: unitPrice * Double(units) * w.economy.housing)
    }

    /// Start a project. Original: `FAM.dev.start`.
    @discardableResult
    public static func start(_ s: inout GameState, companyID: Int, size sz: Double, financed: Bool, data: GameData, context: FinanceContext) -> StartResult {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type], ProjectModel.isDeveloper(bd) else { return .notADeveloper }
        let w = World(state: s, data: data)
        let co = s.companies[i]
        let q = quote(co, bd, size: sz, financed: financed, world: w, homeCurrency: context.homeCurrency(s))
        let down = financed ? q.land * 0.35 : q.land
        if co.cash < down + q.fee { return .notEnoughCash }
        var loanID = 0
        if financed {
            let offer = Banking.offer(kind: "biz", amount: q.loanAmount, company: co, state: s, netWorth: Valuation.netWorth(s, trades: data.catalog).total, context: context)
            if q.loanAmount > offer.maximum { return .loanRefused }
            var l = Loan(raw: [:])
            l.id = s.makeID(); l.kind = "biz"; l.name = "Construction loan"; l.balance = q.loanAmount; l.originalAmount = q.loanAmount
            l.margin = Banking.creditMargin(s.credit) + 0.018
            l.monthlyPayment = 0; l.termMonths = 36; l.companyID = companyID; l.startWeek = s.week; l.isGuaranteed = true
            Payments.companyPays(&s, companyID: companyID, amount: down, category: nil, label: "Land purchase")
            Payments.companyPays(&s, companyID: companyID, amount: q.fee, category: "oth", label: "Zoning work")
            s.loans.append(l)
            loanID = l.id
            Ledger.moveRaw(&s, .company(companyID), q.build * 0.7)
        } else {
            Payments.companyPays(&s, companyID: companyID, amount: down, category: nil, label: "Land purchase")
            Payments.companyPays(&s, companyID: companyID, amount: q.fee, category: "oth", label: "Zoning work")
        }
        var list = projects(s.companies[i])
        let n = s.companies[i].value("fm")["pn"].int + 1
        var p = Project(raw: [:])
        p.set("id", s.makeID())
        p.name = "Project \(n) (\(q.units) units)"
        p.units = q.units; p.land = q.land; p.build = q.build; p.stage = "zoning"
        p.weeksLeft = 22 + s.random.int(0, 8)
        p.sold = 0; p.revenue = 0; p.unitPrice = q.unitPrice; p.priceMultiplier = 1; p.spent = 0; p.workInProgress = q.land; p.overrun = 0
        p.loanID = loanID; p.delay = 0
        list.append(p)
        var fm = s.companies[i].value("fm"); fm["pn"] = .number(Double(n)); s.companies[i].set("fm", fm)
        setProjects(&s, i, list)
        return .started(p.id)
    }

    /// The manager's own baseline: with funds, a modest new project every so often.
    static func autoStart(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData, context: FinanceContext) {
        let co = s.companies[i]
        guard let mgr = co.managerID, s.people[mgr] != nil, co.status == .open else { return }
        let fm = co.value("fm")
        let last = fm["autoW"].isNull ? -99 : fm["autoW"].int
        let active = projects(co).filter { $0.isActive }.count
        guard s.week - last >= 10, active < 2, s.random.chance(0.35) else { return }
        let leveraged = co.value("knob")["fin"].int == 0
        let w = World(state: s, data: data)
        let home = context.homeCurrency(s)
        for sz in [1.0, 0.5, 0.4] {
            let q = quote(s.companies[i], bd, size: sz, financed: leveraged, world: w, homeCurrency: home)
            let full = quote(s.companies[i], bd, size: sz, financed: false, world: w, homeCurrency: home)
            let need = leveraged ? q.land * 0.35 + q.fee + q.build * 0.15 : q.land + q.fee + q.build * 1.05
            if s.companies[i].cash >= need * (active > 0 ? 3 : 1.1) {
                let r = start(&s, companyID: co.id, size: sz, financed: leveraged, data: data, context: context)
                if case .started = r {
                    setAuto(&s, i)
                    s.note("\(s.people[mgr]?.name ?? "The manager") started a new project.", tone: "good", companyID: co.id)
                    break
                }
                if r == .loanRefused, s.companies[i].cash >= (full.land + full.fee + full.build * 1.05) * 1.1 {
                    if case .started = start(&s, companyID: co.id, size: sz, financed: false, data: data, context: context) { setAuto(&s, i); break }
                }
            }
        }
    }
    static func setAuto(_ s: inout GameState, _ i: Int) {
        var fm = s.companies[i].value("fm"); fm["autoW"] = .number(Double(s.week)); s.companies[i].set("fm", fm)
    }

    /// Change the price of the units of a project (0.9 ... 1.1 of the standard). Original: `devprice`.
    public static func setPriceMultiplier(_ s: inout GameState, companyID: Int, projectID: Int, multiplier: Double) {
        guard let i = s.companyIndex(companyID) else { return }
        var list = projects(s.companies[i])
        guard let k = list.firstIndex(where: { $0.id == projectID }) else { return }
        list[k].priceMultiplier = clamp(multiplier, 0.8, 1.2)
        setProjects(&s, i, list)
    }

    /// The week of a developer: zoning, building, selling. Original: `FAM.dev.custom`.
    static func week(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData, context: FinanceContext) -> CompanyWeek.WeekContext {
        autoStart(&s, i, bd, data: data, context: context)
        let tw = bd.traits
        let id = s.companies[i].id
        var list = projects(s.companies[i])
        for k in list.indices where list[k].raw["wip"] == nil || list[k].raw["wip"] == .null {
            list[k].workInProgress = max(0, list[k].land + list[k].spent) // older saves
        }
        let H = s.economy.housing
        let w = World(state: s, data: data)
        let co0 = s.companies[i]
        let season = DemandModel.season(bd, w)
        var rev = 0.0, cogs = 0.0, sold = 0.0
        let wks = tw["wks"] ?? 70
        let mat = s.economy.materials

        func sellUnits(_ p: inout Project, _ f: Double) {
            let co = s.companies[i]
            let rate = Double(p.units) * 0.035 * f * exp(-(1 - H) * 5) * (0.7 + co.awareness / 150) * (0.8 + co.reputation / 250) * exp(-1.2 * (p.priceMultiplier - 1)) * season
            let n = min(Double(p.units - p.sold), Double(s.random.poisson(rate)))
            guard n > 0 else { return }
            let price = p.unitPrice * H * p.priceMultiplier
            let r = n * price
            // Cost of sales: this share of everything spent on the project so far (work in progress).
            let cs = p.workInProgress * n / Double(p.units - p.sold)
            p.workInProgress -= cs
            cogs += cs
            p.sold += Int(n)
            p.revenue += r
            rev += r
            sold += n
            if p.loanID != 0, let li = s.loans.firstIndex(where: { $0.id == p.loanID }) {
                let rep = min(s.loans[li].balance, r * 0.7)
                s.loans[li].balance -= rep
                Ledger.moveRaw(&s, .company(id), -rep)
                if s.loans[li].balance < 1 { s.loans.remove(at: li); p.loanID = 0 }
            }
        }

        for k in list.indices {
            var p = list[k]
            if p.stage == "zoning" {
                p.weeksLeft -= 1
                if p.weeksLeft <= 0 {
                    if s.random.chance(0.78 - (co0.managerID != nil ? 0 : 0.02)) {
                        p.stage = "build"; p.weeksLeft = Int(wks); p.spent = 0
                        s.note("Zoning approved for \(p.name).", tone: "good", companyID: id)
                    } else {
                        p.weeksLeft = 10
                        s.note("Zoning for \(p.name) delayed by objections.", tone: "bad", companyID: id)
                    }
                }
            } else if p.stage == "build" {
                let wk = p.build / wks
                let cost = (wk + p.overrun / wks) * mat
                Payments.companyPays(&s, companyID: id, amount: cost, category: nil, label: nil)
                p.spent += cost
                p.workInProgress += jsRound(cost)
                p.weeksLeft -= 1
                if p.delay > 0 { p.delay -= 1; p.weeksLeft += 1 }
                if p.weeksLeft <= 0 {
                    p.stage = "sell"
                    s.note("\(p.name) is complete and ready for sale.", tone: "good", companyID: id)
                }
                if Double(p.weeksLeft) < wks * 0.7 && p.sold < p.units { sellUnits(&p, 0.4) }
            } else if p.stage == "sell" {
                sellUnits(&p, 1)
                if p.sold >= p.units {
                    p.stage = "done"
                    s.note("\(p.name) sold out. Total sales \(w.currency(co0).short(p.revenue)).", tone: "good", companyID: id)
                }
            }
            list[k] = p
        }
        // Costs that came in after the last unit was sold
        for k in list.indices where list[k].stage == "done" && list[k].workInProgress > 0 {
            cogs += list[k].workInProgress
            list[k].workInProgress = 0
        }
        // Finished projects leave the list (the count and the last few are kept for the screen).
        var fm = s.companies[i].value("fm")
        var finished = fm["finished"].array
        for p in list where p.stage == "done" {
            finished.insert(.object(["name": .string(p.name), "units": .number(Double(p.units)), "rev": .number(p.revenue), "cost": .number(p.land + p.build + p.overrun), "w": .number(Double(s.week))]), at: 0)
        }
        fm["finished"] = .array(Array(finished.prefix(12)))
        fm["doneCount"] = .number(fm["doneCount"].double + Double(list.filter { $0.stage == "done" }.count))
        s.companies[i].set("fm", fm)
        list = list.filter { $0.stage != "done" }
        setProjects(&s, i, list)
        var ctx = CompanyWeek.WeekContext(units: sold, rev: rev, cogs: cogs, D: 0, cap: 0, util: list.isEmpty ? 0 : 0.7, price: bd.traits["land"] != nil ? 4_800_000 : 0, paidDuringWeek: 0)
        ctx.cogsIsAccounting = true
        return ctx
    }
}
