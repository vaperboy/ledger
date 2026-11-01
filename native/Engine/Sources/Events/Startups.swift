import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Startups, both ways. (1) Startups YOU found: pick a sector and a product, put in seed money, hire builders, raise rounds from investors,
/// switch the finished product on in your own companies, pitch it to rivals, shut it down or sell it at an exit. (2) Startups of other people
/// that you invest in: pitches arrive every four weeks, you buy a percentage, they raise rounds, ask for bridge money, fail or exit.
/// Originals: features/player/selling_startups_and_crisis.js (`foundedWeek`, `fpitch`...), features/player/startup_sectors.js (the nine
/// sectors, `f17go`, `weekly`, `p17go`), engine/world/investing.js (`genStartup`, `investStartup`, `startupsWeek`, `ACTS.round`, `ACTS.bridge`).
///
/// State: `rest["founded"]` (yours), `rest["startups"]` (stakes in others'), `rest["deals_su"]` + `rest["deals_suW"]` (the pitches on offer).
/// The money from a sector product used by your companies comes through `StartupProducts` (demand and capacity steps).
///
/// Not faithful: the software startup of the earlier rounds (`f.sw`, with a software shop in equipment buying) is folded into the SaaS
/// sector of the nine (`sw16`); a social app's marketing boost is not applied; pitching to rivals needs rivals as individual businesses
/// (`rest["mk"][key].riv`), which the Competition port provides, so the list is empty until then.
public enum Startups {
    public static let rounds = ["Pre-seed", "Seed", "Series A", "Series B", "Growth"]
    public static let capitalWords = ["", "Low", "Medium", "High", "Very high", "Huge"]
    public static let stakeStages = ["Seed (building product)", "Launch (finding the market)", "Growth (scaling)", "Exit-ready"]
    public static let minimumInvestment = 50_000.0

    // MARK: Reading

    public struct Product: Equatable {
        public var sector: String, product: String, model: String, phase: String
        public var builders: Int, selfHours: Double, progress: Double, customers: Double, revenueWeekly: Double, internalPrice: Double
        public var usedBy: [Int]
        public var ready: Bool { phase == "beta" || phase == "live" }
    }
    public struct Founded: Identifiable, Equatable {
        public var id: Int
        public var name: String, productName: String, sectorName: String
        public var live: Bool, exited: Bool
        public var stage: Int, ownership: Double, valuation: Double, cash: Double, burn: Double, invested: Double, exitValue: Double
        public var quality: Double, traction: Double
        public var runwayWeeks: Int
        public var offers: [Funding.FundOffer]
        public var product: Product?
        /// The real company behind it (open it for people, pay, marketing, shares), its team, the builders among them, the team asked for at founding, the price.
        public var companyID: Int
        public var teamSize: Int
        public var developers: Int
        public var teamWanted: Int
        public var price: Double
        public var stageName: String { live ? rounds[min(stage, 4)] : exited ? "Acquired" : "Shut down" }
    }

    static func product(_ w: JSONValue) -> Product? {
        w.isNull ? nil : Product(sector: w["cat"].string, product: w["prod"].string, model: w["model"].string, phase: w["phase"].string, builders: w["devs"].int,
                                 selfHours: w["selfH"].double, progress: w["prog"].double, customers: w["cust"].double, revenueWeekly: w["revW"].double,
                                 internalPrice: w["int"].double, usedBy: w["use"].array.map { $0.int })
    }
    /// A startup as the screens see it: the company's own cash, people, shares and value, and the product record.
    static func read(_ f: JSONValue, _ s: GameState) -> Founded {
        let co = s.company(f["cid"].int)
        let cash = co?.cash ?? 0
        let payroll = (co?.staff.reduce(0.0) { $0 + $1.monthlyWage * $1.partTimeShare } ?? 0) * 12 / 52
        let burn = payroll * 1.12 + (co.map { $0.value("prem")["rent"].double * 12 / 52 } ?? 0)
        let status = co?.status
        let live = status?.isLive ?? false
        let exited = status == .sold && f["st"].string == "exit"
        let val = f["val"].double
        return Founded(id: f["id"].int, name: co?.name ?? f["name"].string, productName: f["secn"].string, sectorName: StartupProducts.sector(f["sec"].string)?.name ?? "",
                       live: live, exited: exited, stage: stageIndex(f), ownership: co?.ownership ?? f["pct"].double, valuation: val,
                       cash: cash, burn: burn, invested: co?.injectedCapital ?? f["in"].double, exitValue: f["exitV"].double, quality: f["q"].double, traction: f["tr"].double,
                       runwayWeeks: CompanyFigures.runwayWeeks(cash: cash, weeklyLoss: max(0, burn - f["sw16"]["revW"].double)).map { Int($0) } ?? 0,
                       offers: Funding.offers(s, companyID: f["cid"].int),
                       product: product(f["sw16"]), companyID: f["cid"].int, teamSize: co?.staff.count ?? 0, developers: co.map { StartupModel.developers($0) } ?? 0,
                       teamWanted: f["wantTeam"].int, price: f["sw16"]["price"].double)
    }
    /// Stage by what is true: building, launched, with customers, with real revenue, scaling.
    static func stageIndex(_ f: JSONValue) -> Int {
        let w = f["sw16"]
        if w["phase"].string != "live" { return 0 }
        let rev = w["revW"].double
        return rev <= 0 ? 1 : w["cust"].double < 100 ? 2 : w["cust"].double < 500 ? 3 : 4
    }
    public static func founded(_ s: GameState) -> [Founded] { (s.rest["founded"]?.array ?? []).map { read($0, s) } }
    public static func founded(_ s: GameState, id: Int) -> Founded? { founded(s).first { $0.id == id } }

    static func index(_ s: GameState, _ id: Int) -> Int? { (s.rest["founded"]?.array ?? []).firstIndex { $0["id"].int == id } }
    static func edit(_ s: inout GameState, _ id: Int, _ body: (inout JSONValue) -> Void) {
        guard var list = s.rest["founded"]?.array, let k = list.firstIndex(where: { $0["id"].int == id }) else { return }
        body(&list[k]); s.rest["founded"] = .array(list)
    }

    /// How attractive a startup of yours is to investors. Original: `interest(f.ck, clamp(f.tr + f.stage * 0.15, 0, 1))`.
    public static func investorInterest(_ s: GameState, _ f: Founded, sectorCapitalNeed ck: Int) -> Double {
        Funding.interest(s, capitalNeed: ck, traction: clamp(f.traction + Double(f.stage) * 0.15, 0, 1))
    }
    public static func investorInterest(_ s: GameState, startupID: Int) -> Double {
        guard let raw = (s.rest["founded"]?.array ?? []).first(where: { $0["id"].int == startupID }) else { return 0 }
        return Funding.interest(s, capitalNeed: raw["ck"].int, traction: clamp(raw["tr"].double + raw["stage"].double * 0.15, 0, 1))
    }

    /// Hours a week you could still give to building something yourself, at most 20. Original: `freeH`.
    public static func freeHours(_ s: GameState) -> Double { min(20, max(0, 80 - CapacityModel.ownerHoursCommitted(s))) }
    static func builderCost(_ sector: String, _ cur: Currency) -> Double { cur.scaledPrice(sector == "clean" || sector == "health" ? 75000 : 65000) }

    /// Plan of a startup before you found it: weeks to test and to sell, builders' monthly cost, runway. Original: the `sheet` tiles.
    public struct Plan: Equatable {
        public var seed: Double, builders: Int, weeksToTest: Int?, weeksToSell: Int?, buildersMonthly: Double, runwayWeeks: Int, interest: Double, capitalNeed: Int
    }
    public static func plan(_ s: GameState, sector id: String, who: String, seedMultiple m: Double, context fc: FinanceContext) -> Plan? {
        guard let d = StartupProducts.sector(id) else { return nil }
        let cur = fc.homeCurrency(s)
        let seed = cur.scaledPrice(d.seed) * m
        let devs = who == "c4" ? 4 : who == "c2" ? 2 : 0, selfH = who == "self" && d.canBuildYourself ? freeHours(s) : 0
        let speed = Double(devs) + selfH / 40 * 0.7, wk = speed > 0 ? Int((d.work / speed).rounded(.up)) : nil
        let dc = builderCost(id, cur)
        return Plan(seed: seed, builders: devs, weeksToTest: wk.map { Int((Double($0) / 2).rounded(.up)) }, weeksToSell: wk, buildersMonthly: Double(devs) * dc,
                    runwayWeeks: Int((CompanyFigures.runwayWeeks(cash: seed, weeklyLoss: cur.scaledPrice(d.seed) / 26 + Double(devs) * dc * 12 / 52) ?? 0).rounded()),
                    interest: Funding.interest(s, capitalNeed: d.capitalNeed, traction: 0.05), capitalNeed: d.capitalNeed)
    }
    /// Your own companies that could use this product, with the effect each would get.
    public static func companiesThatCanUse(_ s: GameState, sector: String, product: String, data: GameData) -> [(company: Company, effect: StartupProducts.Effect)] {
        s.companies.filter { $0.status == .open || $0.status == .setup }.compactMap { c in
            guard let bd = data.catalog[c.type], let x = StartupProducts.effect(sector: sector, product: product, trade: bd) else { return nil }
            return (c, x)
        }
    }

    // MARK: Founding

    public enum FoundResult: Equatable { case ok(Int), notEnoughMoney(Double), unknownSector }

    /// Found a startup: a REAL company (limited, home-based) funded with the seed money, whose builders are hired and paid like any staff.
    /// who: "self", "c2" (two builders) or "c4"; seedMultiple 1, 2 or 4. The builders are hired only as far as the seed carries their wages for
    /// three months; the rest are shown as wanted and can be hired from the company's team screen. Original: `ACT.f17go` (the blob is gone).
    @discardableResult
    public static func found(_ s: inout GameState, name: String?, sector: String, product: String, model: String, who: String, seedMultiple: Double,
                             data: GameData, context fc: FinanceContext) -> FoundResult {
        guard let d = StartupProducts.sector(sector) else { return .unknownSector }
        let cur = fc.homeCurrency(s)
        let seed = cur.scaledPrice(d.seed) * seedMultiple
        let c = data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode)
        // Like any limited company it is registered (fee) and has an accountant (owner decision).
        let fee = c.registrationFee
        if Payments.liquid(s) < seed + fee { return .notEnoughMoney(seed + fee) }
        let rec = Funding.record(s)
        var nm = (name ?? "").trimmingCharacters(in: .whitespaces)
        if nm.isEmpty {
            let root = (c.companyNameStarts.isEmpty ? "Nova" : s.random.pick(c.companyNameStarts)).filter { $0.isLetter }
            nm = String(root.prefix(5)) + s.random.pick(["ly", " Labs", "io", " Tech"])
        }
        guard let id = SpecialFamilies.blankCompany(&s, tradeID: StartupModel.tradeID, country: c, cityID: s.player.cityID, name: nm, size: 1, data: data),
              let i = s.companyIndex(id) else { return .unknownSector }
        s.companies[i].status = .open
        s.companies[i].openedWeek = s.week
        s.companies[i].ownerHours = 0
        Payments.transferFromSavings(&s, need: seed + fee)
        Payments.injectCash(&s, companyID: id, amount: seed)
        Payments.playerPays(&s, fee, label: "Registration of \(nm)", companyID: id)
        CompanySetup.chooseAccountant(&s, companyID: id, accountantID: nil, data: data)
        s.companies[i].set("cap", .object(["total": .number(Double(CapTable.initialShares)), "me": .number(Double(CapTable.initialShares))]))
        let wanted = who == "c4" ? 4 : who == "c2" ? 2 : 0
        var hired = 0
        for _ in 0..<wanted {
            guard let co = s.company(id) else { break }
            let payroll: Double = co.staff.reduce(0.0) { $0 + $1.monthlyWage }
            let next: Double = Hiring.marketWage(role: "dev", company: co, state: s, data: data)
            if co.cash < (payroll + next) * 1.12 * 3 { break }
            let cands = Hiring.search(role: "dev", company: co, mode: .network, faces: false, state: &s, data: data)
            if AutoHire.hireWorker(role: "dev", companyID: id, candidates: cands, state: &s, data: data) != nil { hired += 1 } else { break }
        }
        // The first support hire is part of the default founding team: someone has to look after the first customers.
        var support = 0
        if let co = s.company(id) {
            let payroll: Double = co.staff.reduce(0.0) { $0 + $1.monthlyWage }
            let next: Double = Hiring.marketWage(role: "ittech", company: co, state: s, data: data)
            if co.cash >= (payroll + next) * 1.12 * 3 {
                let cands = Hiring.search(role: "ittech", company: co, mode: .network, faces: false, state: &s, data: data)
                if AutoHire.hireWorker(role: "ittech", companyID: id, candidates: cands, state: &s, data: data) != nil { support = 1 }
            }
        }
        let selfH = who == "self" && d.canBuildYourself ? freeHours(s) : 0
        let q0 = clamp(s.random.range(0.25, 0.7) + Double(rec.exits) * 0.05 - Double(rec.fails) * 0.02, 0.1, 0.92)
        let reference = cur.scaledPrice(d.arpu)
        let price: Double = ["once", "sale", "lic"].contains(model) ? reference * 2 : reference / 12 * (model == "both" ? 0.7 : 1)
        let f: JSONValue = .object([
            "id": .number(Double(id)), "cid": .number(Double(id)), "name": .string(nm), "sec": .string(sector), "secn": .string(StartupProducts.productName(sector: sector, product: product)),
            "ck": .number(Double(d.capitalNeed)), "stage": 0, "pct": 100, "val": .number(seed), "in": .number(seed), "q": .number(q0), "q0": .number(q0), "tr": 0.05,
            "w0": .number(Double(s.week)), "st": "live", "wantTeam": .number(Double(wanted)), "hiredTeam": .number(Double(hired)), "support": .number(Double(support)),
            "sw16": .object(["cat": .string(sector), "prod": .string(product), "model": .string(model), "devs": .number(Double(hired)), "selfH": .number(selfH), "prog": 0,
                             "phase": "build", "cust": 0, "revW": 0, "int": 0, "use": .array([]), "deals": .array([]), "price": .number(price)]),
        ])
        s.rest["founded"] = .array((s.rest["founded"]?.array ?? []) + [f])
        s.note("\(nm) is founded as a company of yours.", tone: "good", companyID: id)
        return .ok(id)
    }

    // MARK: Launch

    public enum LaunchResult: Equatable { case ok, notReady, badPrice }

    /// The launch decision once the product is finished: the price from now on (the marketing campaign is set by the caller through the ordinary
    /// campaigns). Revenue starts the next week.
    @discardableResult
    public static func launch(_ s: inout GameState, startupID: Int, price: Double) -> LaunchResult {
        guard let k = index(s, startupID), let f = s.rest["founded"]?.array[k], f["sw16"]["phase"].string == "ready" else { return .notReady }
        guard price > 0 else { return .badPrice }
        edit(&s, startupID) { $0["sw16"]["phase"] = "live"; $0["sw16"]["price"] = .number(price) }
        s.note("\(f["name"].string) is launched.", tone: "good", companyID: startupID)
        s.news("\(f["name"].string) launches.", tone: "good")
        return .ok
    }

    /// Change the price of a launched product. Customers answer next week.
    @discardableResult
    public static func setPrice(_ s: inout GameState, startupID: Int, price: Double) -> Bool {
        guard price > 0, let k = index(s, startupID), let f = s.rest["founded"]?.array[k], ["live", "ready"].contains(f["sw16"]["phase"].string) else { return false }
        edit(&s, startupID) { $0["sw16"]["price"] = .number(price) }
        return true
    }

    /// What the launch screen shows for a price: the expected first weeks without luck. The campaign budget is read from the company's own plan.
    public static func launchPreview(_ s: GameState, startupID: Int, price: Double, data: GameData, context fc: FinanceContext) -> StartupModel.Funnel? {
        guard let f = (s.rest["founded"]?.array ?? []).first(where: { $0["id"].int == startupID }), let co = s.company(startupID),
              let d = StartupProducts.sector(f["sw16"]["cat"].string) else { return nil }
        let cur = fc.currency(co.countryCode, s)
        let q = StartupModel.quality(s, co, base: f["q0"].double)
        return StartupModel.expectedFunnel(s, co, sector: d, model: f["sw16"]["model"].string, price: price, awareness: co.awareness, customers: f["sw16"]["cust"].double, quality: q, currency: cur)
    }

    // MARK: Raising rounds, putting in money, shutting down

    public enum RoundResult: Equatable { case offers(Int), none, tooSoon(weeksLeft: Int), notLive }

    /// Pitch to investors for a round: the ordinary company pitch (`Funding.pitch`), sized to 26 weeks of the team's cost against the company's value.
    /// The offers, their share counts and their terms are `Funding`'s and `CapTable`'s, the same as for any company of yours.
    @discardableResult
    public static func pitchRound(_ s: inout GameState, startupID: Int, data: GameData) -> RoundResult {
        guard let co = s.company(startupID), co.status.isLive else { return .notLive }
        let fc = FinanceContext(countries: data.countries, trades: data.catalog)
        let weeklyCost = (co.staff.reduce(0.0) { $0 + $1.monthlyWage } * 12 / 52) * 1.12 + fc.weeklyCost(co, s)
        let amount = max(weeklyCost * 26, fc.currency(co.countryCode, s).scaledPrice(100000))
        switch Funding.pitch(&s, companyID: startupID, amount: amount, data: data, context: fc) {
        case .offers(let n): return .offers(n)
        case .none: return RoundResult.none
        case .tooSoon(let w): return .tooSoon(weeksLeft: w)
        case .notLimited: return .notLive
        }
    }

    @discardableResult
    public static func acceptRound(_ s: inout GameState, startupID: Int, index n: Int) -> Bool { Funding.acceptOffer(&s, companyID: startupID, index: n) }

    public static func declineRound(_ s: inout GameState, startupID: Int, index n: Int) { Funding.declineOffer(&s, companyID: startupID, index: n) }

    /// Put your own money into the company (an owner investment, no new shares).
    @discardableResult
    public static func topUp(_ s: inout GameState, startupID: Int, amount: Double) -> Bool {
        let a = jsRound(amount)
        guard a > 0, let co = s.company(startupID), co.status.isLive, Payments.liquid(s) >= a else { return false }
        return Payments.injectCash(&s, companyID: startupID, amount: a)
    }

    /// Close it: the ordinary winding-up is `GameEngine.windUpCompany`; this keeps the old entry point for the founder's record and returns what you got back.
    @discardableResult
    public static func shutDown(_ s: inout GameState, startupID: Int) -> Double? {
        guard let i = s.companyIndex(startupID), s.companies[i].status.isLive else { return nil }
        let co = s.companies[i]
        let back = max(0, co.cash) * co.ownership / 100
        if back > 0 { Payments.playerReceives(&s, back, label: "Closed \(co.name)", companyID: startupID) }
        Ledger.set(&s, .company(startupID), to: 0)
        for m in s.companies[i].staff { if var p = s.people[m.id] { p.employerID = 0; s.people[m.id] = p } }
        s.companies[i].staff = []
        s.companies[i].status = .sold
        edit(&s, startupID) { $0["st"] = "failed" }
        Funding.bump(&s, "fails")
        return back
    }

    // MARK: The product: builders, your hours, use in your companies, internal price

    /// Hire one more builder (delta > 0) or let one go (delta < 0) through the ordinary hiring and dismissal. Pay, notice and severance are the company's.
    public static func setBuilders(_ s: inout GameState, startupID: Int, delta: Int, data: GameData) {
        guard s.company(startupID) != nil else { return }
        if delta > 0 {
            for _ in 0..<delta {
                guard let co = s.company(startupID) else { return }
                var tries = 0
                while tries < 4 {
                    tries += 1
                    let cands = Hiring.search(role: "dev", company: co, mode: .network, faces: false, state: &s, data: data)
                    if AutoHire.hireWorker(role: "dev", companyID: startupID, candidates: cands, state: &s, data: data) != nil { break }
                }
            }
        } else if delta < 0 {
            for _ in 0..<(-delta) {
                guard let co = s.company(startupID), let m = co.staff.filter({ $0.role == "dev" }).max(by: { $0.hiredWeek < $1.hiredWeek }) else { return }
                _ = Dismissal.dismiss(&s, companyID: startupID, staffID: m.id, reason: .redundancy, data: data)
            }
        }
    }
    /// Give (or take back) your own hours to the product. Fails when you have fewer than 5 free.
    @discardableResult
    public static func toggleOwnerHours(_ s: inout GameState, startupID: Int) -> Bool {
        guard let k = index(s, startupID), let f = s.rest["founded"]?.array[k], !f["sw16"].isNull else { return false }
        if f["sw16"]["selfH"].double > 0 { edit(&s, startupID) { $0["sw16"]["selfH"] = 0 }; return true }
        let left = freeHours(s)
        guard left >= 5, StartupProducts.sector(f["sw16"]["cat"].string)?.canBuildYourself == true else { return false }
        edit(&s, startupID) { $0["sw16"]["selfH"] = .number(left) }
        return true
    }
    /// Switch the product on or off in one of your companies (once it is testable). Original: `ACT.w17use`.
    @discardableResult
    public static func toggleUse(_ s: inout GameState, startupID: Int, companyID: Int) -> Bool {
        guard let k = index(s, startupID), let f = s.rest["founded"]?.array[k], !f["sw16"].isNull, f["sw16"]["phase"].string != "build" else { return false }
        edit(&s, startupID) { f in
            var u = f["sw16"]["use"].array
            if let n = u.firstIndex(where: { $0.int == companyID }) { u.remove(at: n) } else { u.append(.number(Double(companyID))) }
            f["sw16"]["use"] = .array(u)
        }
        return true
    }
    /// What your companies pay the startup for using it: 0, 25, 50 or 100 (% of the price). Original: `ACT.w17int`.
    public static func setInternalPrice(_ s: inout GameState, startupID: Int, percent: Double) {
        edit(&s, startupID) { if !$0["sw16"].isNull { $0["sw16"]["int"] = .number(percent) } }
    }

    // MARK: Pitching the product to rivals

    public struct RivalTarget: Identifiable, Equatable {
        public var id: Int
        public var marketKey: String
        public var name: String, owner: String
        public var relationship: Double
        public var waitWeeks: Int
        public var alreadyCustomer: Bool
        public var odds: Double
    }
    static func trust(_ rel: Double) -> Double { clamp((rel - 45) / 45, 0, 1) }
    /// Rivals of your companies that could use the product, best relationship first, at most ten. Original: `targets`.
    public static func rivalTargets(_ s: GameState, startupID: Int, data: GameData) -> [RivalTarget] {
        guard let raw = (s.rest["founded"]?.array ?? []).first(where: { $0["id"].int == startupID }), raw["st"].string == "live", let p = product(raw["sw16"]), p.ready else { return [] }
        var seen = Set<Int>(), out: [RivalTarget] = []
        for c in s.companies where c.status == .open {
            guard let bd = data.catalog[c.type], bd.family != "hold", bd.family != "club" else { continue }
            if p.sector != "saas", StartupProducts.effect(sector: p.sector, product: p.product, trade: bd) == nil { continue }
            let key = c.type + "|" + c.cityID
            for r in s.rest["mk"]?[key]["riv"].array ?? [] where !seen.contains(r["id"].int) {
                seen.insert(r["id"].int)
                let wait = r["p17"][String(startupID)].isNull ? 0 : max(0, 8 - (s.week - r["p17"][String(startupID)].int))
                let rel = r["rel"].double, t = trust(rel)
                let odds = t * 0.92 + (1 - t) * clamp(raw["q"].double * 0.85 - 0.12 - (p.phase == "beta" ? 0.15 : 0), 0.03, 0.85)
                out.append(RivalTarget(id: r["id"].int, marketKey: key, name: r["name"].string, owner: r["owner"].string, relationship: rel, waitWeeks: wait,
                                       alreadyCustomer: raw["sw16"]["deals"].array.contains { $0["rid"].int == r["id"].int }, odds: odds))
            }
        }
        return Array(out.sorted { $0.relationship > $1.relationship }.prefix(10))
    }
    /// Pitch the product to one rival. Returns true if they signed up. Original: `ACT.p17go`.
    @discardableResult
    public static func pitchToRival(_ s: inout GameState, startupID: Int, rivalID: Int, data: GameData) -> Bool? {
        guard let t = rivalTargets(s, startupID: startupID, data: data).first(where: { $0.id == rivalID }), t.waitWeeks == 0, !t.alreadyCustomer,
              var mk = s.rest["mk"], var riv = mk[t.marketKey]["riv"].array.first(where: { $0["id"].int == rivalID }),
              let n = mk[t.marketKey]["riv"].array.firstIndex(where: { $0["id"].int == rivalID }), let k = index(s, startupID) else { return nil }
        var p17 = riv["p17"]; p17[String(startupID)] = .number(Double(s.week)); riv["p17"] = p17
        let f = s.rest["founded"]!.array[k]
        let tr = trust(riv["rel"].double)
        let ok = s.random.chance(t.odds)
        if ok {
            let cnt = max(1, Int((1 + (riv["size"].isNull ? 1 : riv["size"].double) * 3).rounded()))
            riv["rel"] = .number(min(100, riv["rel"].double + 3))
            let chk = tr > 0.6 && f["q"].double < 0.45 ? s.week + s.random.int(6, 10) : 0
            let wk = Double(s.week)
            edit(&s, startupID) { f in
                f["sw16"]["cust"] = .number(f["sw16"]["cust"].double + Double(cnt))
                f["sw16"]["deals"] = .array(f["sw16"]["deals"].array + [.object(["rid": .number(Double(rivalID)), "n": .number(Double(cnt)), "w": .number(wk), "chk": .number(Double(chk)), "mk": .string(t.marketKey)])])
            }
            s.addMessage(from: riv["owner"].string.isEmpty ? riv["name"].string : riv["owner"].string, title: "\(riv["name"].string) buys \(f["name"].string)",
                         body: tr > 0.6 ? "\"I trust you. If you built it, we will use it.\"" : "\"We tried it and it does what we need. Count us in.\"", tone: "good")
        } else if tr < 0.3, s.random.chance(0.3) { riv["rel"] = .number(max(0, riv["rel"].double - 2)) }
        var arr = mk[t.marketKey]["riv"].array; arr[n] = riv
        mk[t.marketKey]["riv"] = .array(arr)
        s.rest["mk"] = mk
        return ok
    }

    // MARK: The week

    /// A startup saved before startups became companies (no `cid`): it becomes a real company holding the cash the blob had, with the builders on the
    /// payroll and your share as it was. Nothing the player had is lost; the record keeps its product and takes the company's id.
    static func migrateLegacy(_ s: inout GameState, data: GameData) {
        guard var list = s.rest["founded"]?.array else { return }
        var changed = false
        for k in list.indices where list[k]["cid"].isNull && list[k]["st"].string == "live" {
            var f = list[k]
            let c = data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode)
            guard let id = SpecialFamilies.blankCompany(&s, tradeID: StartupModel.tradeID, country: c, cityID: s.player.cityID, name: f["name"].string, size: 1, data: data),
                  let i = s.companyIndex(id) else { continue }
            s.companies[i].status = .open
            s.companies[i].openedWeek = s.week
            s.companies[i].ownerHours = 0
            Ledger.set(&s, .company(id), to: max(0, f["cash"].double))
            s.companies[i].injectedCapital = f["in"].double
            s.companies[i].ownership = clamp(f["pct"].double, 0.01, 100)
            s.companies[i].set("cap", .null)
            CapTable.normalise(&s, i)
            var hired = 0
            for _ in 0..<max(0, f["sw16"]["devs"].int) {
                let cands = Hiring.search(role: "dev", company: s.companies[i], mode: .network, faces: false, state: &s, data: data)
                if AutoHire.hireWorker(role: "dev", companyID: id, candidates: cands, state: &s, data: data) != nil { hired += 1 }
            }
            f["id"] = .number(Double(id)); f["cid"] = .number(Double(id)); f["q0"] = f["q"]; f["wantTeam"] = f["sw16"]["devs"]; f["hiredTeam"] = .number(Double(hired))
            list[k] = f
            changed = true
        }
        if changed { s.rest["founded"] = .array(list) }
    }

    /// Once a week: keep each startup's record in line with its company (value, share, builders), notice the end of the company (broke or sold),
    /// warn when the money runs short, and settle rival deals. The product itself runs inside the company's own week (`StartupModel.context`).
    public static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        _ = pitches(&s, data: data)
        migrateLegacy(&s, data: data)
        guard var list = s.rest["founded"]?.array, !list.isEmpty else { weeklyStakes(&s); return }
        for k in list.indices where list[k]["st"].string == "live" {
            var f = list[k]
            guard let co = s.company(f["cid"].int) else { f["st"] = "failed"; list[k] = f; continue }
            if co.status == .bust {
                f["st"] = "failed"; f["val"] = 0
                Funding.bump(&s, "fails")
                s.news("Startup \(co.name) shuts down.", tone: "n")
                list[k] = f; continue
            }
            if co.status == .sold {
                f["st"] = "exit"; f["val"] = 0
                Funding.bump(&s, "exits")
                list[k] = f; continue
            }
            f["val"] = .number(Valuation.companyValue(co, state: s, trades: data.catalog))
            f["pct"] = .number(co.ownership)
            f["in"] = .number(co.injectedCapital)
            f["sw16"]["devs"] = .number(Double(StartupModel.developers(co)))
            f["stage"] = .number(Double(stageIndex(f)))
            let payroll = co.staff.reduce(0.0) { $0 + $1.monthlyWage * $1.partTimeShare } * 12 / 52 * 1.12
            let net = payroll + fc.weeklyCost(co, s) - f["sw16"]["revW"].double
            let runway = CompanyFigures.runwayWeeks(cash: co.cash, weeklyLoss: max(0, net))
            if let r = runway, r < 6, !f["warn"].bool {
                f["warn"] = 1
                s.addMessage(from: co.name, title: "\(co.name) has about \(Int(r)) weeks of money left",
                             body: "Raise a round or put in more money, cut costs, or the company runs out of cash.", companyID: co.id, tone: "bad")
            } else if (runway ?? 99) >= 10 { f["warn"] = 0 }
            list[k] = f
        }
        s.rest["founded"] = .array(list)
        // Rival deals: a friend who bought a poor product out of trust may regret it.
        for k in list.indices where list[k]["st"].string == "live" && !list[k]["sw16"].isNull {
            for d in list[k]["sw16"]["deals"].array where d["chk"].int != 0 && s.week >= d["chk"].int {
                guard var mk = s.rest["mk"], let key = Optional(d["mk"].string), !mk[key].isNull, var arr = Optional(mk[key]["riv"].array),
                      let n = arr.firstIndex(where: { $0["id"].int == d["rid"].int }) else { continue }
                if s.random.chance(0.6) {
                    arr[n]["rel"] = .number(max(0, arr[n]["rel"].double - 12))
                    mk[key]["riv"] = .array(arr); s.rest["mk"] = mk
                    edit(&s, list[k]["id"].int) { $0["sw16"]["cust"] = .number(max(0, $0["sw16"]["cust"].double - d["n"].double)) }
                    s.note("\(arr[n]["name"].string) dropped \(list[k]["name"].string): it did not work well for them. They are less friendly now.", tone: "bad")
                }
                edit(&s, list[k]["id"].int) { f in f["sw16"]["deals"] = .array(f["sw16"]["deals"].array.map { x in var y = x; if y["rid"].int == d["rid"].int { y["chk"] = 0 }; return y }) }
            }
        }
        weeklyStakes(&s)
    }

    // MARK: Startups of others: pitches, stakes, rounds and bridges

    public struct Pitch: Identifiable, Equatable {
        public var id: Int
        public var name: String, sector: String, blurb: String
        public var raise: Double, preMoney: Double, postMoney: Double
        public var team: Int, market: Int, traction: Int
    }
    public struct Stake: Identifiable, Equatable {
        public var id: Int
        public var name: String, sector: String
        public var stage: Int
        public var live: Bool, failed: Bool
        public var ownership: Double, invested: Double, value: Double
        public var boardSeat: Bool
        public var stageName: String { stakeStages[min(max(0, stage), 3)] }
    }

    static let neutralWords = ["Nova", "Harbor", "Quanta", "Lumen", "Meridian", "Wave", "Spire", "Flux", "Summit", "Growth", "Raven", "Alba"]

    static func genPitch(_ s: inout GameState, data: GameData) -> JSONValue {
        let c = data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode)
        let q = s.random.range(0.2, 0.92)
        let raise = (s.random.range(0.8, 6) * 1e6 / 1e5).rounded() * 1e5
        let pre = (raise * s.random.range(2.5, 6) / 1e5).rounded() * 1e5
        let words = c.pack["names"]["startupWords"].array.map { $0.string }
        let sec = s.random.pick(StartupProducts.sectors).name
        let name = s.random.pick(words.isEmpty ? neutralWords : words) + s.random.pick(["ly", "ify", "io", "works", " Labs", " Group", "tech"])
        let blurb = s.random.pick([s.random.pick(["Founders from a big energy company.", "Founders from a large bank.", "Founders from a media group.", "Founders from a telecom company.", "Founders who built an app before."]),
                                   "Two engineers with a working prototype.", "Early customers and a waitlist.", "Serial founder, second company.", "University spin-out with a patent."])
        return .object(["id": .number(Double(s.makeID())), "name": .string(name), "sec": .string(sec), "q": .number(q), "raise": .number(raise), "pre": .number(pre), "post": .number(pre + raise),
                        "stage": 0, "blurb": .string(blurb),
                        "sig": .object(["team": .number(clamp(jsRound(q * 100 + s.random.gauss() * 12), 5, 99)), "market": .number(clamp(jsRound(s.random.range(35, 90)), 5, 99)),
                                        "traction": .number(clamp(jsRound(q * 90 + s.random.gauss() * 18), 3, 99))])])
    }

    /// The three pitches on offer; a new set every four weeks. Original: `startupDeals`.
    public static func pitches(_ s: inout GameState, data: GameData) -> [Pitch] {
        if s.rest["deals_su"] == nil || s.week - (s.rest["deals_suW"]?.int ?? 0) >= 4 {
            s.rest["deals_su"] = .array([genPitch(&s, data: data), genPitch(&s, data: data), genPitch(&s, data: data)])
            s.rest["deals_suW"] = .number(Double(s.week))
        }
        return (s.rest["deals_su"]?.array ?? []).map {
            Pitch(id: $0["id"].int, name: $0["name"].string, sector: $0["sec"].string, blurb: $0["blurb"].string, raise: $0["raise"].double, preMoney: $0["pre"].double, postMoney: $0["post"].double,
                  team: $0["sig"]["team"].int, market: $0["sig"]["market"].int, traction: $0["sig"]["traction"].int)
        }
    }
    /// The pitches already drawn (read only; `weekly` keeps them fresh).
    public static func pitchesOnOffer(_ s: GameState) -> [Pitch] {
        (s.rest["deals_su"]?.array ?? []).map {
            Pitch(id: $0["id"].int, name: $0["name"].string, sector: $0["sec"].string, blurb: $0["blurb"].string, raise: $0["raise"].double, preMoney: $0["pre"].double, postMoney: $0["post"].double,
                  team: $0["sig"]["team"].int, market: $0["sig"]["market"].int, traction: $0["sig"]["traction"].int)
        }
    }
    public static func stakes(_ s: GameState) -> [Stake] {
        (s.rest["startups"]?.array ?? []).map { Stake(id: $0["id"].int, name: $0["name"].string, sector: $0["sec"].string, stage: $0["stage"].int, live: $0["st"].string == "live", failed: $0["st"].string == "failed",
                                                      ownership: $0["pct"].double, invested: $0["in"].double, value: $0["val"].double * $0["pct"].double / 100, boardSeat: $0["seat"].bool) }
    }

    public enum InvestResult: Equatable { case ok, tooSmall, notEnoughMoney, gone }

    /// Put money into a pitch. Original: `investStartup`.
    @discardableResult
    public static func invest(_ s: inout GameState, pitchID: Int, amount: Double, context fc: FinanceContext) -> InvestResult {
        guard let d = (s.rest["deals_su"]?.array ?? []).first(where: { $0["id"].int == pitchID }) else { return .gone }
        var amt = (amount / 10000).rounded() * 10000
        if amt < fc.homeCurrency(s).scaledPrice(minimumInvestment) { return .tooSmall }
        amt = min(amt, d["raise"].double)
        if Payments.liquid(s) < amt { return .notEnoughMoney }
        Payments.transferFromSavings(&s, need: amt)
        Payments.playerPays(&s, amt, label: "Invested in \(d["name"].string)")
        let pct = amt / d["post"].double * 100
        let f: JSONValue = .object(["id": .number(Double(s.makeID())), "name": d["name"], "sec": d["sec"], "q": d["q"], "st": "live", "stage": 0, "pct": .number(pct), "in": .number(amt), "val": d["post"],
                                    "w0": .number(Double(s.week)), "wNext": .number(Double(s.week + s.random.int(26, 52))), "seat": .bool(pct >= 20), "help": 0,
                                    "rounds": .array([.object(["w": .number(Double(s.week)), "amt": .number(amt), "pct": .number(pct)])]), "sig": d["sig"]])
        s.rest["startups"] = .array((s.rest["startups"]?.array ?? []) + [f])
        s.rest["deals_su"] = .array((s.rest["deals_su"]?.array ?? []).filter { $0["id"].int != pitchID })
        if pct >= 20 { s.note("You hold \(String(format: "%.1f", pct))% of \(d["name"].string) and get a board seat.", tone: "good") }
        return .ok
    }

    static func editStake(_ s: inout GameState, _ id: Int, _ body: (inout JSONValue) -> Void) {
        guard var list = s.rest["startups"]?.array, let k = list.firstIndex(where: { $0["id"].int == id }) else { return }
        body(&list[k]); s.rest["startups"] = .array(list)
    }

    /// Spend a week on the board of a startup you hold 20% or more of; it improves their odds. Original: `helpStartup`.
    @discardableResult
    public static func help(_ s: inout GameState, stakeID: Int) -> Bool {
        guard let f = (s.rest["startups"]?.array ?? []).first(where: { $0["id"].int == stakeID }), f["seat"].bool, f["st"].string == "live", f["helpedW"].int != s.week || f["helpedW"].isNull else { return false }
        let wk = Double(s.week)
        editStake(&s, stakeID) { $0["help"] = .number(min(2, $0["help"].double + 0.25)); $0["helpedW"] = .number(wk) }
        return true
    }

    /// Sell a fraction of your stake at 72% of fair value. Original: `sellStartupStake`.
    @discardableResult
    public static func sellStake(_ s: inout GameState, stakeID: Int, fraction: Double) -> Double {
        guard let f = (s.rest["startups"]?.array ?? []).first(where: { $0["id"].int == stakeID }), f["st"].string == "live" else { return 0 }
        let v = f["val"].double * f["pct"].double / 100 * fraction * 0.72
        Payments.playerReceives(&s, v, label: "Sold shares in \(f["name"].string)")
        s.tax.gains += v - f["in"].double * fraction
        editStake(&s, stakeID) { x in
            x["pct"] = .number(x["pct"].double * (1 - fraction)); x["in"] = .number(x["in"].double * (1 - fraction))
            x["seat"] = .bool(x["pct"].double >= 20)
            if x["pct"].double < 0.05 { x["st"] = "exit" }
        }
        return v
    }

    static func weeklyStakes(_ s: inout GameState) {
        guard var list = s.rest["startups"]?.array, !list.isEmpty else { return }
        for k in list.indices {
            var f = list[k]
            if f["st"].string != "live" || s.week < f["wNext"].int { continue }
            let bear = s.rest["mkt"]?["regime"].string == "bear"
            let pS = clamp(f["q"].double * 0.85 + f["help"].double * 0.08 + (s.economy.demand - 1) * 0.5 - f["stage"].double * 0.06 + (bear ? -0.1 : 0), 0.08, 0.92)
            let name = f["name"].string
            if !s.random.chance(pS) {
                if f["stage"].int <= 2 && !f["bridged"].bool && s.random.chance(0.5) {
                    f["bridged"] = 1
                    let need = (f["val"].double * 0.15 / 10000).rounded() * 10000
                    s.addMessage(kind: "ask", from: name, title: "\(name) is running out of money before the next milestone",
                                 body: "Founders ask for a bridge round of \(Int(need)) at a flat valuation. Without it they shut down.", tone: "n", status: "open",
                                 options: [.option("Invest \(Int(need)) (\((need / max(1, f["val"].double) * 1000).rounded() / 10)% more)", "Chance of survival 55%."), .option("Pass (and be diluted)", "Others may fund it.")],
                                 action: "bridge", data: .object(["sid": f["id"], "need": .number(need)]), expiresWeek: s.week + 3)
                    f["wNext"] = .number(Double(s.week + 4)); f["pending"] = 1
                    list[k] = f; continue
                }
                f["st"] = "failed"; f["val"] = 0
                s.note("\(name) shut down. Your investment of \(Int(f["in"].double)) is lost.", tone: "bad")
                s.news("Startup \(name) shuts down.", tone: "n")
                list[k] = f; continue
            }
            f["stage"] = .number(f["stage"].double + 1)
            let mult = s.random.range(1.8, 4.2) * (f["stage"].int >= 3 ? 1.5 : 1)
            f["val"] = .number(f["val"].double * mult)
            if f["stage"].int >= 3 {
                let acq = s.random.chance(f["q"].double * 0.7)
                let exitV = f["val"].double * (acq ? s.random.range(1.5, 4) : s.random.range(0.7, 1.4))
                let proceeds = exitV * f["pct"].double / 100
                f["st"] = "exit"; f["val"] = 0
                Payments.playerReceives(&s, proceeds, label: "Exit: \(name)")
                s.tax.gains += proceeds - f["in"].double
                s.note("EXIT! \(name) was acquired. Your stake pays \(Int(proceeds)) (\(String(format: "%.1f", proceeds / max(1, f["in"].double)))x).", tone: "good")
                s.news("\(name) is acquired in a deal valued at \(Int(exitV)).", tone: "good")
                list[k] = f; continue
            }
            let raise = (f["val"].double * 0.2 / 10000).rounded() * 10000
            let mine = (raise * f["pct"].double / 100 / 10000).rounded() * 10000
            s.addMessage(kind: "ask", from: name, title: "\(name) reaches \"\(stakeStages[min(3, f["stage"].int)])\" and raises a round",
                         body: "New valuation \(Int(f["val"].double)). They raise \(Int(raise)) (20%). Take your pro-rata of \(Int(mine)) to avoid dilution?", tone: "n", status: "open",
                         options: [.option("Take pro-rata \(Int(mine))", "Keep your share."), .option("Skip (diluted by 20%)", "Your stake shrinks but value rose.")],
                         action: "round", data: .object(["sid": f["id"], "raise": .number(raise), "myShare": .number(mine)]), expiresWeek: s.week + 3)
            f["pending"] = 1
            f["wNext"] = .number(Double(s.week + s.random.int(30, 60)))
            list[k] = f
        }
        for k in list.indices where list[k]["st"].string == "live" && list[k]["pending"].bool && list[k]["wNext"].int - s.week > 20 { list[k]["pending"] = 0 }
        s.rest["startups"] = .array(list)
    }

    /// The answer to a pro-rata round ("round") or a bridge ("bridge"). Returns false when you lack the money (the message stays open). Original: `ACTS.round`, `ACTS.bridge`.
    public static func answer(_ s: inout GameState, message m: Message, option idx: Int) -> Bool {
        let data = m.value("data"), sid = data["sid"].int
        guard let f = (s.rest["startups"]?.array ?? []).first(where: { $0["id"].int == sid }) else { return true }
        if m.actionID == "round" {
            if idx == 0 {
                let mine = data["myShare"].double
                if Payments.liquid(s) < mine { return false }
                Payments.transferFromSavings(&s, need: mine)
                Payments.playerPays(&s, mine, label: "New funding round: \(f["name"].string)")
                let wk = Double(s.week)
                editStake(&s, sid) { x in
                    x["in"] = .number(x["in"].double + mine)
                    x["rounds"] = .array(x["rounds"].array + [.object(["w": .number(wk), "amt": .number(mine), "pct": x["pct"]])])
                    x["seat"] = .bool(x["pct"].double >= 20)
                }
            } else { editStake(&s, sid) { x in x["pct"] = .number(x["pct"].double * 0.8); x["seat"] = .bool(x["pct"].double >= 20) } }
            return true
        }
        // bridge
        let need = data["need"].double
        if idx == 0 {
            if Payments.liquid(s) < need { return false }
            Payments.transferFromSavings(&s, need: need)
            Payments.playerPays(&s, need, label: "Bridge money for \(f["name"].string)")
            let lives = s.random.chance(0.55), wk = Double(s.week)
            editStake(&s, sid) { x in
                x["in"] = .number(x["in"].double + need); x["pct"] = .number(x["pct"].double + need / max(1, x["val"].double) * 100); x["help"] = .number(x["help"].double + 0.5)
                if lives { x["wNext"] = .number(wk + 20) } else { x["st"] = "failed"; x["val"] = 0 }
                x["pending"] = 0
            }
            s.note(lives ? "The bridge worked: \(f["name"].string) continues." : "\(f["name"].string) failed anyway. The bridge is lost.", tone: lives ? "good" : "bad")
        } else {
            let lives = s.random.chance(0.35), wk = Double(s.week)
            editStake(&s, sid) { x in
                x["pct"] = .number(x["pct"].double * 0.9)
                if lives { x["wNext"] = .number(wk + 20) } else { x["st"] = "failed"; x["val"] = 0 }
                x["pending"] = 0
            }
            if !lives { s.note("\(f["name"].string) shut down.", tone: "bad") }
        }
        return true
    }
}
