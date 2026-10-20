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
        public var stageName: String { live ? rounds[min(stage, 4)] : exited ? "Acquired" : "Shut down" }
    }

    static func product(_ w: JSONValue) -> Product? {
        w.isNull ? nil : Product(sector: w["cat"].string, product: w["prod"].string, model: w["model"].string, phase: w["phase"].string, builders: w["devs"].int,
                                 selfHours: w["selfH"].double, progress: w["prog"].double, customers: w["cust"].double, revenueWeekly: w["revW"].double,
                                 internalPrice: w["int"].double, usedBy: w["use"].array.map { $0.int })
    }
    static func read(_ f: JSONValue) -> Founded {
        let burn = f["burn"].double, cash = f["cash"].double
        return Founded(id: f["id"].int, name: f["name"].string, productName: f["secn"].string, sectorName: StartupProducts.sector(f["sec"].string)?.name ?? "",
                       live: f["st"].string == "live", exited: f["st"].string == "exit", stage: f["stage"].int, ownership: f["pct"].double, valuation: f["val"].double,
                       cash: cash, burn: burn, invested: f["in"].double, exitValue: f["exitV"].double, quality: f["q"].double, traction: f["tr"].double,
                       runwayWeeks: burn > 0 ? max(0, Int(cash / burn)) : 0,
                       offers: f["offers"].array.enumerated().map { n, o in Funding.FundOffer(id: n, kind: o["k"].string, name: o["name"].string, amount: o["amt"].double, preMoney: o["pre"].double, pct: o["pct"].double, says: o["says"].string, countered: o["ctr"].bool) },
                       product: product(f["sw16"]))
    }
    public static func founded(_ s: GameState) -> [Founded] { (s.rest["founded"]?.array ?? []).map(read) }
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
                    runwayWeeks: Int((cur.scaledPrice(d.seed) * m / (cur.scaledPrice(d.seed) / 26 + Double(devs) * dc * 12 / 52)).rounded()),
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

    /// Found a startup. who: "self", "c2" (two builders) or "c4"; seedMultiple 1, 2 or 4. Original: `ACT.f17go`.
    @discardableResult
    public static func found(_ s: inout GameState, name: String?, sector: String, product: String, model: String, who: String, seedMultiple: Double,
                             data: GameData, context fc: FinanceContext) -> FoundResult {
        guard let d = StartupProducts.sector(sector) else { return .unknownSector }
        let cur = fc.homeCurrency(s)
        let seed = cur.scaledPrice(d.seed) * seedMultiple
        if Payments.liquid(s) < seed { return .notEnoughMoney(seed) }
        Payments.transferFromSavings(&s, need: seed)
        Payments.playerPays(&s, seed, label: "Founded a startup")
        let rec = Funding.record(s)
        let c = data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode)
        var nm = (name ?? "").trimmingCharacters(in: .whitespaces)
        if nm.isEmpty {
            let root = (c.companyNameStarts.isEmpty ? "Nova" : s.random.pick(c.companyNameStarts)).filter { $0.isLetter }
            nm = String(root.prefix(5)) + s.random.pick(["ly", " Labs", "io", " Tech"])
        }
        let devs = who == "c4" ? 4 : who == "c2" ? 2 : 0
        let selfH = who == "self" && d.canBuildYourself ? freeHours(s) : 0
        let q = clamp(s.random.range(0.25, 0.7) + Double(rec.exits) * 0.05 - Double(rec.fails) * 0.02, 0.1, 0.92)
        let price: Double = model == "once" ? cur.scaledPrice(15000) : model == "sub" ? cur.scaledPrice(1200) : cur.scaledPrice(800)
        let f: JSONValue = .object([
            "id": .number(Double(s.makeID())), "name": .string(nm), "sec": .string(sector), "secn": .string(StartupProducts.productName(sector: sector, product: product)),
            "ck": .number(Double(d.capitalNeed)), "stage": 0, "pct": 100, "val": .number(seed * 1.2), "cash": .number(seed),
            "burn": .number(seed / (26 * seedMultiple) + Double(devs) * builderCost(sector, cur) * 12 / 52), "in": .number(seed), "q": .number(q), "tr": 0.05,
            "w0": .number(Double(s.week)), "wNext": .number(Double(s.week + s.random.int(20, 34))), "st": "live", "offers": .array([]),
            "sw16": .object(["cat": .string(sector), "prod": .string(product), "model": .string(model), "devs": .number(Double(devs)), "selfH": .number(selfH), "prog": 0,
                             "phase": "build", "cust": 0, "revW": 0, "int": 0, "use": .array([]), "deals": .array([]), "price": .number(price)]),
        ])
        s.rest["founded"] = .array((s.rest["founded"]?.array ?? []) + [f])
        s.note("\(nm) is founded.", tone: "good")
        return .ok(f["id"].int)
    }

    // MARK: Raising rounds, putting in money, shutting down

    public enum RoundResult: Equatable { case offers(Int), none, tooSoon(weeksLeft: Int), notLive }

    /// Pitch to investors for a round. Original: `ACT.fpitch`.
    @discardableResult
    public static func pitchRound(_ s: inout GameState, startupID: Int, data: GameData) -> RoundResult {
        guard let k = index(s, startupID), let f = s.rest["founded"]?.array[k], f["st"].string == "live" else { return .notLive }
        if !f["pitchW"].isNull, s.week - f["pitchW"].int < 4 { return .tooSoon(weeksLeft: 4 - (s.week - f["pitchW"].int)) }
        let it = Funding.interest(s, capitalNeed: f["ck"].int, traction: clamp(f["tr"].double + f["stage"].double * 0.15, 0, 1))
        let list = Funding.makeOffers(&s, countryCode: s.homeCountryCode, data: data, interest: it, amount: max(f["burn"].double * 26, f["val"].double * 0.3), preMoney: max(f["val"].double, f["in"].double * 1.5))
        let wk = Double(s.week)
        edit(&s, startupID) { $0["pitchW"] = .number(wk); $0["offers"] = .array(list) }
        return list.isEmpty ? .none : .offers(list.count)
    }

    @discardableResult
    public static func acceptRound(_ s: inout GameState, startupID: Int, index n: Int) -> Bool {
        guard let k = index(s, startupID), let f = s.rest["founded"]?.array[k], f["offers"].array.indices.contains(n) else { return false }
        let o = f["offers"].array[n]
        edit(&s, startupID) {
            $0["cash"] = .number($0["cash"].double + o["amt"].double)
            $0["val"] = .number(o["pre"].double + o["amt"].double)
            $0["pct"] = .number($0["pct"].double * (1 - o["pct"].double / 100))
            $0["burn"] = .number($0["burn"].double * 1.35)
            $0["warn"] = 0
            $0["offers"] = .array([])
        }
        Funding.bump(&s, "raised", o["amt"].double)
        s.note("\(f["name"].string) raised \(Int(o["amt"].double)) from \(o["name"].string).", tone: "good")
        return true
    }

    public static func declineRound(_ s: inout GameState, startupID: Int, index n: Int) {
        edit(&s, startupID) { var l = $0["offers"].array; if l.indices.contains(n) { l.remove(at: n) }; $0["offers"] = .array(l) }
    }

    /// Put your own money into the startup. Original: `ACT.ftopgo`.
    @discardableResult
    public static func topUp(_ s: inout GameState, startupID: Int, amount: Double) -> Bool {
        let a = jsRound(amount)
        guard a > 0, let k = index(s, startupID), s.rest["founded"]?.array[k]["st"].string == "live", Payments.liquid(s) >= a else { return false }
        Payments.transferFromSavings(&s, need: a)
        Payments.playerPays(&s, a, label: "Put money into \(s.rest["founded"]!.array[k]["name"].string)")
        edit(&s, startupID) { $0["cash"] = .number($0["cash"].double + a); $0["in"] = .number($0["in"].double + a); $0["warn"] = 0 }
        return true
    }

    /// Close it. Your share of the cash that is left comes back; it counts as a failed startup. Original: `ACT.fshut`.
    @discardableResult
    public static func shutDown(_ s: inout GameState, startupID: Int) -> Double? {
        guard let k = index(s, startupID), let f = s.rest["founded"]?.array[k], f["st"].string == "live" else { return nil }
        let back = max(0, f["cash"].double) * f["pct"].double / 100
        if back > 0 { Payments.playerReceives(&s, back, label: "Closed \(f["name"].string)") }
        edit(&s, startupID) { $0["st"] = "failed"; $0["val"] = 0 }
        Funding.bump(&s, "fails")
        return back
    }

    // MARK: The product: builders, your hours, use in your companies, internal price

    public static func setBuilders(_ s: inout GameState, startupID: Int, delta: Int, context fc: FinanceContext) {
        let cur = fc.homeCurrency(s)
        edit(&s, startupID) { f in
            guard !f["sw16"].isNull else { return }
            let old = f["sw16"]["devs"].int, n = max(0, min(10, old + delta))
            f["burn"] = .number(f["burn"].double + Double(n - old) * builderCost(f["sw16"]["cat"].string, cur) * 12 / 52)
            f["sw16"]["devs"] = .number(Double(n))
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

    static func addMod(_ s: inout GameState, _ i: Int, _ k: String, _ m: Double, _ w: Double) { EventEngine.addModifier(&s, i, key: k, multiplier: m, weeks: w) }

    /// Cash burns, milestones come (valuation up or down), products progress, customers and revenue arrive. Original: `foundedWeek` + startup_sectors `weekly`.
    public static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        _ = pitches(&s, data: data)
        guard var list = s.rest["founded"]?.array, !list.isEmpty else { weeklyStakes(&s); return }
        for k in list.indices where list[k]["st"].string == "live" {
            var f = list[k]
            let name = f["name"].string
            f["cash"] = .number(f["cash"].double - f["burn"].double)
            f["tr"] = .number(clamp(f["tr"].double + (f["q"].double - 0.3) * 0.012 + s.random.gauss() * 0.004, 0, 1))
            if f["cash"].double < 0 {
                f["st"] = "failed"; f["val"] = 0
                Funding.bump(&s, "fails")
                s.note("\(name) ran out of money and shut down.", tone: "bad")
                s.news("Startup \(name) shuts down.", tone: "n")
                list[k] = f; continue
            }
            if f["cash"].double < f["burn"].double * 6 && !f["warn"].bool {
                f["warn"] = 1
                s.addMessage(from: name, title: "\(name) has about \(Int(f["cash"].double / max(1, f["burn"].double))) weeks of money left",
                             body: "Raise a round or put in more money, or it shuts down.", tone: "bad")
            }
            if s.week >= f["wNext"].int {
                f["wNext"] = .number(Double(s.week + s.random.int(20, 34)))
                if s.random.chance(clamp(f["q"].double * 0.9 + f["tr"].double * 0.3 - f["stage"].double * 0.05, 0.1, 0.9)) {
                    f["stage"] = .number(min(4, f["stage"].double + 1))
                    f["val"] = .number(f["val"].double * s.random.range(1.8, 3.2))
                    s.note("\(name) hit its milestone and is now at \(rounds[f["stage"].int]) stage.", tone: "good")
                    if f["stage"].int >= 4 && s.random.chance(0.5 + f["q"].double * 0.3) {
                        let ex = f["val"].double * s.random.range(1.2, 2.8), pr = ex * f["pct"].double / 100
                        Payments.playerReceives(&s, pr, label: "Exit: \(name)")
                        s.tax.gains += max(0, pr - f["in"].double)
                        f["st"] = "exit"; f["exitV"] = .number(ex); f["val"] = 0
                        Funding.bump(&s, "exits")
                        s.note("EXIT! \(name) was acquired. Your \(Int(f["pct"].double.rounded()))% pays \(Int(pr)).", tone: "good")
                        s.news("\(name) is acquired for \(fc.homeCurrency(s).short(ex)).", tone: "good")
                    }
                } else {
                    f["val"] = .number(f["val"].double * s.random.range(0.6, 0.95))
                    s.note("\(name) missed its milestone. The valuation fell.", tone: "bad")
                }
            }
            if f["st"].string == "live", !f["sw16"].isNull { productWeek(&s, &f, data: data, context: fc) }
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

    /// Building, testing, selling, and the bill your own companies pay. Original: startup_sectors `weekly`.
    static func productWeek(_ s: inout GameState, _ f: inout JSONValue, data: GameData, context fc: FinanceContext) {
        let w = f["sw16"]
        guard let d = StartupProducts.sector(w["cat"].string) else { return }
        let speed = w["devs"].double + w["selfH"].double / 40 * 0.7 * CapacityModel.ownerFactor(s)
        var phase = w["phase"].string, prog = w["prog"].double, cust = w["cust"].double
        let name = f["name"].string, q = f["q"].double
        let cur = fc.homeCurrency(s)
        if phase != "live" {
            prog = min(1, prog + speed / d.work * (0.7 + q * 0.6))
            if phase == "build" && prog >= 0.5 { phase = "beta"; s.note("\(name) is ready to test. You can switch it on in your own companies.", tone: "good") }
            if prog >= 1 { phase = "live"; s.note("\(name) is launched.", tone: "good"); s.news("\(name) launches.", tone: "good") }
        }
        var rev = 0.0
        let arpu = cur.scaledPrice(d.arpu)
        if phase == "live" {
            let nc = max(0, ((q * 2.2 + f["tr"].double * 3 + w["devs"].double * 0.3) * d.growth * (1 + cust / 250) * s.random.range(0.2, 1.3)).rounded())
            cust = (cust * (1 - 0.005 - (1 - q) * 0.02)).rounded() + nc
            let one = ["once", "sale", "lic"].contains(w["model"].string)
            rev = one ? nc * arpu * 8 : cust * arpu * 12 / 52 * (w["model"].string == "both" ? 1.15 : 1)
            f["tr"] = .number(clamp(f["tr"].double + min(0.01, rev / max(1, f["burn"].double) * 0.004), 0, 1))
        } else if phase == "beta" { cust = max(cust, 2 + (prog * 8).rounded(.down)) }
        // Your companies pay the internal price
        var gl = Set<Int>()
        for idv in w["use"].array {
            guard let ci = s.companyIndex(idv.int), s.companies[ci].status == .open else { continue }
            if phase == "beta" && s.random.chance(0.1) {
                var g = s.companies[ci].value("gl16"); g[String(f["id"].int)] = .number(Double(s.week + 1)); s.companies[ci].set("gl16", g)
                s.note("\(name) (test version) failed at \(s.companies[ci].name) this week.", tone: "bad", companyID: s.companies[ci].id)
                gl.insert(ci)
            }
            let fee = jsRound(arpu * w["int"].double / 100 * 12 / 52)
            if fee > 0 { _ = Payments.companyPays(&s, companyID: s.companies[ci].id, amount: fee, category: "oth", label: "Own product: \(name)"); rev += fee }
            if let bd = data.catalog[s.companies[ci].type], let x = StartupProducts.effect(sector: w["cat"].string, product: w["prod"].string, trade: bd), x.c > 0 {
                addMod(&s, ci, "cogsup", 1 - x.c * (phase == "live" ? 1 : 0.6) * (0.6 + q * 0.6), 2)
            }
        }
        f["sw16"]["phase"] = .string(phase); f["sw16"]["prog"] = .number(prog); f["sw16"]["cust"] = .number(cust); f["sw16"]["revW"] = .number(jsRound(rev))
        f["cash"] = .number(f["cash"].double + rev)
        if rev > 0 { f["val"] = .number(max(f["val"].double, rev * 52 * 3)) }
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
