import Foundation
import GameCore
import Countries
import Employees
import Finance

/// Energy: the renewable power producer and the oil and gas company. Original: `FAM.energy` (engine/company/family_energy.js),
/// the round-24 oil and gas steps (features/world/oil_and_gas.js) and `coTaxRate`.
///
/// Where things are kept (same keys as the original save, so an imported company carries on):
///  power: `eq.turb.n` MW bought, `fm.build` [{n, ready}] MW still under construction;
///  oil:   `fm.fields` [{id, name, st dev|prod|depleted, res (thousand bbl), q0, age, bv, wl, capex, plat, rbl}], `fm.assets`
///         book value of the fields (counted as an asset), `fm.expl` this year's exploration spend, `fm.autoW`.
public enum EnergyModel {
    // MARK: Power

    public struct Source {
        public var name: String
        /// capacity factor multiplier, cost, weeks to build
        public var cf: Double, cost: Double, buildWeeks: Int
        /// output by calendar month
        public var seasonal: [Double]
    }

    public static let sources: [Source] = [
        Source(name: "Onshore wind", cf: 1, cost: 1, buildWeeks: 52, seasonal: [1.3, 1.25, 1.1, 0.9, 0.75, 0.65, 0.6, 0.7, 0.9, 1.1, 1.25, 1.3]),
        Source(name: "Small hydro", cf: 1.25, cost: 1.3, buildWeeks: 78, seasonal: [0.8, 0.7, 0.9, 1.4, 1.7, 1.4, 1.0, 0.8, 0.9, 1.0, 0.9, 0.8]),
        Source(name: "Solar park", cf: 0.31, cost: 0.55, buildWeeks: 26, seasonal: [0.1, 0.35, 0.9, 1.6, 2.1, 2.4, 2.3, 1.8, 1.0, 0.45, 0.1, 0.05]),
    ]

    /// 0 wind, 1 hydro, 2 solar (the company's "Source" choice).
    public static func sourceIndex(_ co: Company) -> Int { min(2, max(0, co.value("knob")["src"].int)) }
    public static func source(of co: Company) -> Source { sources[sourceIndex(co)] }

    /// Price strategy: 0 spot, 1 half hedged, 2 mostly hedged.
    public static let hedgeShare: [Double] = [0, 0.5, 0.9]

    public struct PowerResult: Equatable {
        public var megawatts = 0.0, megawattsBuilding = 0.0
        public var capacityMWh = 0.0, outputMWh = 0.0
        public var price = 0.0, revenue = 0.0, runningCost = 0.0
        public var season = 1.0, crew = 1.0
    }

    /// One week of a power plant, as a pure function of its inputs (so it can be compared with the original).
    /// `noise` is one standard normal draw. Original: `FAM.energy.power`.
    public static func powerWeek(megawattsBought: Double, building: Double, week: Int, month: Int, source src: Source, hedge: Int,
                                 capacityFactor tw: Double, opexRate: Double, condition cond: Double, technicianFTE: Double,
                                 capacityModifier: Double, demandModifier: Double, economyPower: Double, inflation: Double, noise: Double) -> PowerResult {
        var r = PowerResult()
        r.megawatts = max(0, megawattsBought - building)
        r.megawattsBuilding = building
        r.season = src.seasonal[month]
        r.crew = min(1, technicianFTE / max(0.5, 4 * max(0.5, r.megawatts / 30)))
        let mw = r.megawatts
        r.capacityMWh = mw * 168 * tw * src.cf * r.season
        let raw = mw * 168 * tw * src.cf * r.season * (0.75 + 0.25 * cond) * (0.8 + 0.2 * r.crew) * capacityModifier * (1 + noise * 0.08)
        r.outputMWh = min(raw, r.capacityMWh)
        let idx = pow(1 + inflation, Double(week) / 52)
        let spot = 650 * economyPower * idx
        let fixed = 650 * 1.0 * idx
        let share = hedgeShare[min(2, max(0, hedge))]
        r.price = spot * (1 - share) + fixed * 0.95 * share
        r.revenue = r.outputMWh * r.price * demandModifier
        r.runningCost = mw * 14e6 * opexRate / 52 * (1 + (1 - cond) * 0.6)
        return r
    }

    /// Turbines ordered are built over time: they only produce when ready. Original: `FAM.energy.afterBuy`.
    static func afterBuy(_ s: inout GameState, _ i: Int, _ bd: Trade, equipmentID: String, quantity: Double) {
        guard bd.hasTrait("power"), equipmentID == "turb" else { return }
        var fm = s.companies[i].value("fm")
        var q = fm["build"].array
        q.append(.object(["n": .number(quantity), "ready": .number(Double(s.week + source(of: s.companies[i]).buildWeeks))]))
        fm["build"] = .array(q)
        s.companies[i].set("fm", fm)
    }

    static func powerContext(_ s: inout GameState, _ i: Int, _ bd: Trade, _ data: GameData) -> CompanyWeek.WeekContext {
        var co = s.companies[i]
        var fm = co.value("fm")
        let queue = fm["build"].array
        let building = queue.filter { $0["ready"].double > Double(s.week) }.reduce(0) { $0 + $1["n"].double }
        let nextReady = queue.filter { $0["ready"].double > Double(s.week) }.map { $0["ready"].double }.min()
        fm["build"] = .array(queue.filter { $0["ready"].double > Double(s.week) })
        let turb = co.value("eq")["turb"]
        let bought = turb.isNull ? 0 : turb["n"].double
        let cond = turb.isNull ? 1 : turb["cond"].double
        let tables = data.catalog.tables
        let fte = StaffModel.fullTimeEquivalents(role: "windtech", staff: co.staff, people: s.people, week: s.week, salesRoles: tables.salesRoles)
        let noise = s.random.gauss()
        let r = powerWeek(megawattsBought: bought, building: building, week: s.week, month: GameCalendar.month(week: s.week), source: source(of: co),
                          hedge: co.value("knob")["hedge"].int, capacityFactor: bd.trait("cf") ?? 0.36, opexRate: bd.trait("opex") ?? 0.025,
                          condition: cond, technicianFTE: fte, capacityModifier: DemandModel.modifier(co, "cap"),
                          demandModifier: DemandModel.modifier(co, "dem"), economyPower: s.economy.power, inflation: s.economy.inflation, noise: noise)
        fm["mw"] = .number(r.megawatts)
        fm["inb"] = .number(r.megawattsBuilding)
        fm["readyIn"] = nextReady.map { .number($0 - Double(s.week)) } ?? .null
        fm["price"] = .number(r.price)
        fm["season"] = .number(r.season)
        co.set("fm", fm)
        s.companies[i] = co
        return CompanyWeek.WeekContext(units: r.outputMWh, rev: r.revenue, cogs: r.runningCost, D: r.outputMWh, cap: r.capacityMWh,
                                       util: r.capacityMWh > 0 ? r.outputMWh / max(1, r.capacityMWh) : 0, price: r.price, paidDuringWeek: 0)
    }

    static func currency(_ s: GameState, _ co: Company, _ data: GameData) -> Currency {
        Currency(country: data.countries.resolve(co.countryCode, orHome: s.homeCountryCode), rates: ExchangeRates(drift: s.exchangeRates.values))
    }

    // MARK: Oil and gas

    static let neutralFields = ["Atlas", "Beacon", "Cormorant", "Delta", "Eagle", "Falcon", "Granite", "Harrier", "Ivory", "Juniper"]
    static let neutralDiscoveries = ["Aurora", "Boreas", "Cobalt", "Drake", "Ember", "Fulmar", "Gannet", "Heron"]

    /// Long-run price per barrel and the share sold on term contracts. Original: the 'sell' knob in `FAM.energy.oil`.
    public static func oilPrice(contracts: Bool, economyOil: Double, inflation: Double, week: Int) -> Double {
        let lr = 780 * pow(pow(1 + inflation, Double(week) / 52), 0.5)
        let term = contracts ? 0.6 : 0.0
        return lr * economyOil * (1 - term) + lr * 0.95 * term
    }

    /// Cost of lifting a barrel. Original: `R24.oilLift`.
    public static func liftingCost(materials: Double, inflation: Double, week: Int) -> Double {
        200 * (0.7 + 0.3 * materials) * pow(pow(1 + inflation, Double(week) / 52), 0.5)
    }

    /// What a stake of `kbbl` thousand barrels costs. Original: `oilAcquire`.
    public static func stakePrice(kbbl: Double, economyOil: Double) -> Double { jsRound(kbbl * 1000 * 190 * pow(economyOil, 0.5)) }

    public static func explorationCost(inflation: Double, week: Int) -> Double { jsRound(300e6 * pow(1 + inflation, Double(week) / 52)) }

    /// One producing field for one week: the barrels (thousand), the book value used up. Original: the 'prod' branch.
    public static func fieldWeek(reserves: Double, initialRate q0: Double, age: Int, plateau: Double, capacityModifier: Double, crew: Double,
                                 noise: Double, bookValue: Double) -> (barrels: Double, depletion: Double) {
        let q = q0 * exp(-0.0028 * max(0, Double(age) - plateau)) * capacityModifier * (0.8 + 0.2 * crew) * (1 + noise * 0.03)
        let b = min(q, reserves)
        let dpl = reserves > 0 ? bookValue * b / reserves : 0
        return (b, dpl)
    }

    static func oilContext(_ s: inout GameState, _ i: Int, _ bd: Trade, _ data: GameData) -> CompanyWeek.WeekContext {
        var co = s.companies[i]
        let id = co.id
        var fm = co.value("fm")
        var fields = fm["fields"].array
        // A manager buys stakes in producing fields when there is money; frontier strategy adds exploration.
        let risk = co.value("knob")["risk"].isNull ? 1 : co.value("knob")["risk"].int
        let infl = pow(1 + s.economy.inflation, Double(s.week) / 52)
        if let mid = co.managerID, s.people[mid] != nil, co.status == .open, Double(s.week) - (fm["autoW"].isNull ? -99 : fm["autoW"].double) >= 26,
           Double(fields.filter { $0["st"].string != "depleted" }.count) < 2 + co.size {
            let k = [10000.0, 5000, 2000, 1000].first { co.cash > $0 * 1000 * 190 * pow(s.economy.oil, 0.5) + 60e6 * infl + co.lastWages * 26 }
            s.companies[i].set("fm", fm)
            if let k = k, acquire(&s, i, kbbl: k, data: data) == .ok {
                fm = s.companies[i].value("fm"); fm["autoW"] = .number(Double(s.week)); fields = fm["fields"].array
                s.companies[i].set("fm", fm)
                s.note("\(s.people[mid]?.name ?? "The manager") bought a stake in a producing field.", tone: "good", companyID: id)
            } else if risk == 2, co.cash > 2.5e9 * infl, s.random.chance(0.3) {
                fm = s.companies[i].value("fm"); fm["autoW"] = .number(Double(s.week))
                s.companies[i].set("fm", fm)
                _ = explore(&s, i, data: data)
                fm = s.companies[i].value("fm"); fields = fm["fields"].array
            }
            co = s.companies[i]
        }
        let price = oilPrice(contracts: co.value("knob")["sell"].int == 1, economyOil: s.economy.oil, inflation: s.economy.inflation, week: s.week)
        let fte = StaffModel.fullTimeEquivalents(role: "offshore", staff: co.staff, people: s.people, week: s.week, salesRoles: data.catalog.tables.salesRoles)
        let crew = min(1, fte / max(1, 10 * co.size))
        let capMod = DemandModel.modifier(co, "cap")
        var bbl = 0.0
        for n in fields.indices {
            var f = fields[n]
            if f["st"].string == "dev" {
                f["wl"] = .number(f["wl"].double - 1)
                let c = f["capex"].double / 156
                developmentCash(&s, i, field: &f, c, data: data)
                Payments.companyPays(&s, companyID: id, amount: c, category: nil)
                f["bv"] = .number(f["bv"].double + c)
                if f["wl"].double <= 0 {
                    f["st"] = "prod"; f["age"] = 0
                    s.note("Field \"\(f["name"].string)\" starts production!", tone: "good", companyID: id)
                }
            } else if f["st"].string == "prod" {
                f["age"] = .number(f["age"].double + 1)
                if f["bv"].isNull { f["bv"] = .number(f["res"].double * 1000 * 190) }
                let r = fieldWeek(reserves: f["res"].double, initialRate: f["q0"].double, age: f["age"].int, plateau: f["plat"].double, capacityModifier: capMod,
                                  crew: crew, noise: s.random.gauss(), bookValue: f["bv"].double)
                f["bv"] = .number(f["bv"].double - r.depletion)
                Payments.book(&s, companyID: id, category: "dep", amount: r.depletion)
                f["res"] = .number(f["res"].double - r.barrels)
                bbl += r.barrels
                if f["res"].double < 10 {
                    Payments.book(&s, companyID: id, category: "dep", amount: f["bv"].double)
                    f["bv"] = 0
                    f["st"] = "depleted"
                    s.note("Field \"\(f["name"].string)\" is depleted.", tone: "n", companyID: id)
                }
            }
            fields[n] = f
        }
        co = s.companies[i]
        fm = co.value("fm")
        fm["fields"] = .array(fields)
        fm["assets"] = .number(fields.filter { $0["st"].string != "depleted" }.reduce(0) { $0 + $1["bv"].double })
        fm["price"] = .number(price)
        co.set("fm", fm)
        s.companies[i] = co
        let rev = bbl * 1000 * price * DemandModel.modifier(co, "dem")
        let cogs = bbl * 1000 * liftingCost(materials: s.economy.materials, inflation: s.economy.inflation, week: s.week)
        return CompanyWeek.WeekContext(units: bbl, rev: rev, cogs: cogs, D: bbl, cap: bbl, util: 0.8, price: price, paidDuringWeek: 0)
    }

    public enum DealResult: Equatable { case ok, cash, hit, dry }

    /// Buy a stake in a producing field. Original: `oilAcquire`.
    @discardableResult
    public static func acquire(_ s: inout GameState, _ i: Int, kbbl: Double, data: GameData) -> DealResult {
        let co = s.companies[i]
        let price = stakePrice(kbbl: kbbl, economyOil: s.economy.oil)
        if co.cash < price { return .cash }
        Payments.companyPays(&s, companyID: co.id, amount: price, category: nil, label: "Stake in producing field")
        let names = data.countries.resolve(co.countryCode, orHome: s.homeCountryCode).pack["flavour"]["oilFields"].array.map { $0.string }
        let name = s.random.pick(names.isEmpty ? neutralFields : names) + " " + s.random.pick(["A", "B", "North", "West", "East"]) + " (stake)"
        var fm = s.companies[i].value("fm")
        var fields = fm["fields"].array
        fields.append(.object(["id": .number(Double(s.makeID())), "name": .string(name), "st": "prod", "res": .number(kbbl), "q0": .number(kbbl * 0.0034), "age": 0, "bv": .number(price)]))
        fm["fields"] = .array(fields)
        s.companies[i].set("fm", fm)
        return .ok
    }

    /// Drill an exploration well. Original: `oilExplore` with the round-24 steps (cost booked, plateau, the decision).
    @discardableResult
    public static func explore(_ s: inout GameState, _ i: Int, data: GameData) -> DealResult {
        let co = s.companies[i]
        let id = co.id
        let c = explorationCost(inflation: s.economy.inflation, week: s.week)
        if co.cash < c { return .cash }
        let before = s.companies[i].cash
        Payments.companyPays(&s, companyID: id, amount: c, category: "oth", label: "Exploration well")
        let spent = before - s.companies[i].cash
        let risk = co.value("knob")["risk"].isNull ? 1 : co.value("knob")["risk"].int
        let ok = s.random.chance([0.14, 0.2, 0.28][min(2, max(0, risk))])
        var fm = s.companies[i].value("fm")
        fm["expl"] = .number(fm["expl"].double + spent)
        var fields = fm["fields"].array
        let infl = pow(1 + s.economy.inflation, Double(s.week) / 52)
        if ok {
            let vol = jsRound(exp(s.random.gauss() * 0.9 + 4.4)) * 1000
            let names = data.countries.resolve(co.countryCode, orHome: s.homeCountryCode).pack["flavour"]["oilDiscoveries"].array.map { $0.string }
            let name = s.random.pick(names.isEmpty ? neutralDiscoveries : names) + " " + String(s.random.int(1, 9))
            let fid = s.makeID()
            // plateau of about 14% of the reserves a year and full-cycle development costs (round-24 numbers)
            let res = vol
            let capex = jsRound(res * 1000 * 130 * pow(infl, 0.5))
            fields.append(.object(["id": .number(Double(fid)), "name": .string(name), "st": "dev", "res": .number(res), "q0": .number(res * 0.0028), "wl": 156,
                                   "capex": .number(capex), "bv": 0, "plat": 104]))
            fm["fields"] = .array(fields)
            s.companies[i].set("fm", fm)
            s.note("DISCOVERY! A well finds about \(Int(jsRound(vol / 1000))) million barrels. Development will take about 3 years.", tone: "good", companyID: id)
            s.news("A new oil discovery is announced.", tone: "good")
            let sell = jsRound(res * 1000 * 25 * pow(s.economy.oil, 0.5) / 1e5) * 1e5
            let cur = currency(s, co, data)
            let cash = s.companies[i].cash
            s.addMessage(kind: "ask", from: co.name, title: "Discovery: \(name)",
                         body: "About \(Int(jsRound(res / 1000))) million barrels. Developing it costs about \(cur.display(capex)) over three years before any oil flows. You have \(cur.display(cash)) in the company.",
                         companyID: id, tone: "good", status: "open",
                         options: [.option("Develop it ourselves", "You pay all of the development and keep all of the oil."),
                                   .option("Bring in a partner for half", "A partner pays half the development and takes half the field."),
                                   .option("Sell the discovery · \(cur.display(sell))", "Cash now; no development risk.")],
                         action: "oil24", data: .object(["f": .number(Double(fid)), "sell": .number(sell)]), expiresWeek: s.week + 4)
            return .hit
        }
        fm["fields"] = .array(fields)
        s.companies[i].set("fm", fm)
        s.note("The exploration well is dry. \(currency(s, co, data).display(c)) lost.", tone: "bad", companyID: id)
        return .dry
    }

    /// When the company cannot pay this week's share of the development, the bank lends against the field (reserve-based
    /// lending): interest only until the field produces, then repaid over seven years. Original: `R24.oilDevCash`.
    static func developmentCash(_ s: inout GameState, _ i: Int, field f: inout JSONValue, _ c: Double, data: GameData) {
        let co = s.companies[i]
        if co.cash >= c { return }
        let need = max(c - co.cash, c * 26)
        let limit = f["res"].double * 1000 * 100 - f["rbl"].double
        let amt = jsRound(min(need, limit) / 1e5) * 1e5
        if amt <= 0 { return }
        var l = Loan(raw: [:])
        l.id = s.makeID(); l.kind = "biz"; l.name = "Reserve-based loan: \(f["name"].string)"
        l.balance = amt; l.originalAmount = amt
        l.margin = Banking.creditMargin(s.credit) + 0.025
        l.termMonths = 84; l.companyID = co.id
        l.startWeek = s.week + f["wl"].int
        l.graceUntilWeek = s.week + f["wl"].int + 13
        l.isGuaranteed = false
        l.monthlyPayment = Loans.annuity(principal: amt, yearlyRate: s.economy.policyRate + l.margin, months: 84)
        s.loans.append(l)
        Payments.companyReceives(&s, companyID: co.id, amount: amt, category: nil, label: "Loan drawn")
        f["rbl"] = .number(f["rbl"].double + amt)
        s.note("The bank lends \(currency(s, co, data).short(amt)) against \(f["name"].string) to finish development.", tone: "n", companyID: co.id)
    }

    // MARK: Decisions and yearly steps

    /// The owner's answer (or the default) on a discovery. Original: `oilChoice`.
    static func choose(_ s: inout GameState, companyIndex i: Int, field fid: Int, option idx: Int, sell: Double) {
        var fm = s.companies[i].value("fm")
        var fields = fm["fields"].array
        guard let n = fields.firstIndex(where: { $0["id"].int == fid }) else { return }
        if idx == 1 {
            fields[n]["res"] = .number(jsRound(fields[n]["res"].double / 2))
            fields[n]["q0"] = .number(fields[n]["q0"].double / 2)
            fields[n]["capex"] = .number(fields[n]["capex"].double / 2)
            fields[n]["name"] = .string(fields[n]["name"].string + " (50%)")
            fm["fields"] = .array(fields)
            s.companies[i].set("fm", fm)
            s.note("A partner takes half of \(fields[n]["name"].string) and pays half the development.", tone: "good", companyID: s.companies[i].id)
        } else if idx == 2 {
            let name = fields[n]["name"].string
            fields.remove(at: n)
            fm["fields"] = .array(fields)
            s.companies[i].set("fm", fm)
            Payments.companyReceives(&s, companyID: s.companies[i].id, amount: sell, category: "rev", label: "Discovery sold: \(name)")
        }
    }

    /// The player answers an "oil24" message. Original: `ACTS.oil24`.
    public static func answer(_ s: inout GameState, message m: Message, option idx: Int) {
        guard let i = s.companyIndex(m.companyID) else { return }
        let d = m.value("data")
        if d["done"].bool { return }
        if let k = s.inbox.firstIndex(where: { $0.id == m.id }) { var dd = d; dd["done"] = 1; s.inbox[k].set("data", dd) }
        choose(&s, companyIndex: i, field: d["f"].int, option: idx, sell: d["sell"].double)
    }

    /// After the week's messages expired: a discovery nobody answered goes ahead (or a partner steps in if the cash is short),
    /// and in Norway the state refunds 78% of exploration costs to a company with no taxable income, once a year.
    /// Original: the 'oil_and_gas weekly' step.
    public static func weeklyAfter(_ s: inout GameState, data: GameData) {
        for k in s.inbox.indices {
            let m = s.inbox[k]
            guard m.actionID == "oil24", m.flag("auto"), !m.value("data")["done"].bool, let i = s.companyIndex(m.companyID) else { continue }
            var d = m.value("data"); d["done"] = 1; s.inbox[k].set("data", d)
            let fields = s.companies[i].value("fm")["fields"].array
            guard let f = fields.first(where: { $0["id"].int == d["f"].int }) else { continue }
            let opt = s.companies[i].cash < f["capex"].double * 1.1 ? 1 : 0
            choose(&s, companyIndex: i, field: d["f"].int, option: opt, sell: d["sell"].double)
            s.note("No answer on the discovery, so \(opt == 1 ? "a partner was brought in for half." : "development goes ahead.")", tone: "n", companyID: s.companies[i].id)
        }
        if s.week % 52 == 0 {
            for i in s.companies.indices {
                let co = s.companies[i]
                // The state refunds part of exploration costs where the country's data says so (`oilRefund`).
                let share = data.countries.resolve(co.countryCode, orHome: s.homeCountryCode).pack["oilRefund"].double
                guard co.type == "oilgas", share > 0, co.status != .bust, co.value("fm")["expl"].double > 0 else { continue }
                let ref = jsRound(co.value("fm")["expl"].double * share)
                if (co.payables["tax"] ?? 0) < 1 {
                    Payments.companyReceives(&s, companyID: co.id, amount: ref, category: nil, label: "Exploration cost refund (78%)")
                    s.note("\(co.name) gets \(currency(s, co, data).short(ref)) back from the state for last year's exploration.", tone: "good", companyID: co.id)
                }
                var fm = s.companies[i].value("fm"); fm["expl"] = 0; s.companies[i].set("fm", fm)
            }
        }
    }

    // MARK: Reading for screens

    public struct PlantSummary: Equatable {
        public var megawatts: Double, building: Double, weeksToReady: Int?
        public var outputMWh: Double, averagePrice: Double, source: String
    }
    public static func plant(_ co: Company) -> PlantSummary {
        let fm = co.value("fm"), lw = co.value("lastW")
        let units = lw["units"].double
        return PlantSummary(megawatts: fm["mw"].double, building: fm["inb"].double, weeksToReady: fm["readyIn"].isNull ? nil : fm["readyIn"].int,
                            outputMWh: units, averagePrice: units > 0 ? lw["rev"].double / units : 0, source: source(of: co).name)
    }

    public struct FieldInfo: Identifiable, Equatable {
        public var id: Int
        public var name: String
        public var state: String          // dev, prod, depleted
        public var millionBarrelsLeft: Double
        public var weeksToProduction: Int
        public var bookValue: Double
        public var weeklyBarrels: Double
    }
    public static func fields(_ co: Company) -> [FieldInfo] {
        co.value("fm")["fields"].array.map {
            FieldInfo(id: $0["id"].int, name: $0["name"].string, state: $0["st"].string, millionBarrelsLeft: $0["res"].double / 1000,
                      weeksToProduction: $0["wl"].int, bookValue: $0["bv"].double,
                      weeklyBarrels: $0["st"].string == "prod" ? $0["q0"].double * exp(-0.0028 * max(0, $0["age"].double - $0["plat"].double)) : 0)
        }
    }
}
