import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum Startups {
    public static let rounds = ["Pre-seed", "Seed", "Series A", "Series B", "Growth"]
    public static let capitalWords = ["", "Low", "Medium", "High", "Very high", "Huge"]
    public static let stakeStages = ["Seed (building product)", "Launch (finding the market)", "Growth (scaling)", "Exit-ready"]
    public static let minimumInvestment = 50_000.0

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
                       runwayWeeks: CompanyFigures.runwayWeeks(cash: cash, weeklyLoss: max(0, burn - f["sw16"]["revW"].double)).map { Int(saturating: $0) } ?? 0,
                       offers: Funding.offers(s, companyID: f["cid"].int),
                       product: product(f["sw16"]), companyID: f["cid"].int, teamSize: co?.staff.count ?? 0, developers: co.map { StartupModel.developers($0) } ?? 0,
                       teamWanted: f["wantTeam"].int, price: f["sw16"]["price"].double)
    }
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

    public static func investorInterest(_ s: GameState, _ f: Founded, sectorCapitalNeed ck: Int) -> Double {
        Funding.interest(s, capitalNeed: ck, traction: clamp(f.traction + Double(f.stage) * 0.15, 0, 1))
    }
    public static func investorInterest(_ s: GameState, startupID: Int) -> Double {
        guard let raw = (s.rest["founded"]?.array ?? []).first(where: { $0["id"].int == startupID }) else { return 0 }
        return Funding.interest(s, capitalNeed: raw["ck"].int, traction: clamp(raw["tr"].double + raw["stage"].double * 0.15, 0, 1))
    }

    public static func freeHours(_ s: GameState) -> Double { min(20, max(0, 80 - CapacityModel.ownerHoursCommitted(s))) }
    static func builderCost(_ sector: String, _ cur: Currency) -> Double { cur.scaledPrice(sector == "clean" || sector == "health" ? 75000 : 65000) }

    public struct Plan: Equatable {
        public var seed: Double, builders: Int, weeksToTest: Int?, weeksToSell: Int?, buildersMonthly: Double, runwayWeeks: Int, interest: Double, capitalNeed: Int
    }
    public static func plan(_ s: GameState, sector id: String, who: String, seedMultiple m: Double, context fc: FinanceContext) -> Plan? {
        guard let d = StartupProducts.sector(id) else { return nil }
        let cur = fc.homeCurrency(s)
        let seed = cur.scaledPrice(d.seed) * m
        let devs = who == "c4" ? 4 : who == "c2" ? 2 : 0, selfH = who == "self" && d.canBuildYourself ? freeHours(s) : 0
        let speed = Double(devs) + selfH / 40 * 0.7, wk = speed > 0 ? Int(saturating: (d.work / speed).rounded(.up)) : nil
        let dc = builderCost(id, cur)
        return Plan(seed: seed, builders: devs, weeksToTest: wk.map { Int(saturating: (Double($0) / 2).rounded(.up)) }, weeksToSell: wk, buildersMonthly: Double(devs) * dc,
                    runwayWeeks: Int(saturating: (CompanyFigures.runwayWeeks(cash: seed, weeklyLoss: cur.scaledPrice(d.seed) / 26 + Double(devs) * dc * 12 / 52) ?? 0).rounded()),
                    interest: Funding.interest(s, capitalNeed: d.capitalNeed, traction: 0.05), capitalNeed: d.capitalNeed)
    }
    public static func companiesThatCanUse(_ s: GameState, sector: String, product: String, data: GameData) -> [(company: Company, effect: StartupProducts.Effect)] {
        s.companies.filter { $0.status == .open || $0.status == .setup }.compactMap { c in
            guard let bd = data.catalog[c.type], let x = StartupProducts.effect(sector: sector, product: product, trade: bd) else { return nil }
            return (c, x)
        }
    }

    public enum FoundResult: Equatable { case ok(Int), notEnoughMoney(Double), unknownSector }

    @discardableResult
    public static func found(_ s: inout GameState, name: String?, sector: String, product: String, model: String, who: String, seedMultiple: Double,
                             data: GameData, context fc: FinanceContext) -> FoundResult {
        guard let d = StartupProducts.sector(sector) else { return .unknownSector }
        let cur = fc.homeCurrency(s)
        let seed = cur.scaledPrice(d.seed) * seedMultiple
        let c = data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode)
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
        Payments.recordInvestment(&s, companyID: id, amount: seed)
        Payments.playerPays(&s, fee, label: "Registration of \(nm)", companyID: id)
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

    public enum LaunchResult: Equatable { case ok, notReady, badPrice }

    @discardableResult
    public static func launch(_ s: inout GameState, startupID: Int, price: Double) -> LaunchResult {
        guard let k = index(s, startupID), let f = s.rest["founded"]?.array[k], f["sw16"]["phase"].string == "ready" else { return .notReady }
        guard price > 0 else { return .badPrice }
        edit(&s, startupID) { $0["sw16"]["phase"] = "live"; $0["sw16"]["price"] = .number(price) }
        s.note("\(f["name"].string) is launched.", tone: "good", companyID: startupID)
        s.news("\(f["name"].string) launches.", tone: "good")
        return .ok
    }

    @discardableResult
    public static func setPrice(_ s: inout GameState, startupID: Int, price: Double) -> Bool {
        guard price > 0, let k = index(s, startupID), let f = s.rest["founded"]?.array[k], ["live", "ready"].contains(f["sw16"]["phase"].string) else { return false }
        edit(&s, startupID) { $0["sw16"]["price"] = .number(price) }
        return true
    }

    public static func launchPreview(_ s: GameState, startupID: Int, price: Double, data: GameData, context fc: FinanceContext) -> StartupModel.Funnel? {
        guard let f = (s.rest["founded"]?.array ?? []).first(where: { $0["id"].int == startupID }), let co = s.company(startupID),
              let d = StartupProducts.sector(f["sw16"]["cat"].string) else { return nil }
        let cur = fc.currency(co.countryCode, s)
        let q = StartupModel.quality(s, co, base: f["q0"].double)
        return StartupModel.expectedFunnel(s, co, sector: d, model: f["sw16"]["model"].string, price: price, awareness: co.awareness, customers: f["sw16"]["cust"].double, quality: q, currency: cur)
    }

    public enum RoundResult: Equatable { case offers(Int), none, tooSoon(weeksLeft: Int), notLive }

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

    @discardableResult
    public static func shutDown(_ s: inout GameState, startupID: Int) -> Bool {
        guard let i = s.companyIndex(startupID), s.companies[i].status.isLive else { return false }
        for m in s.companies[i].staff { if var p = s.people[m.id] { p.employerID = 0; s.people[m.id] = p } }
        s.companies[i].staff = []
        s.companies[i].status = .sold
        edit(&s, startupID) { $0["st"] = "failed" }
        Funding.bump(&s, "fails")
        return true
    }

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
    @discardableResult
    public static func toggleOwnerHours(_ s: inout GameState, startupID: Int) -> Bool {
        guard let k = index(s, startupID), let f = s.rest["founded"]?.array[k], !f["sw16"].isNull else { return false }
        if f["sw16"]["selfH"].double > 0 { edit(&s, startupID) { $0["sw16"]["selfH"] = 0 }; return true }
        let left = freeHours(s)
        guard left >= 5, StartupProducts.sector(f["sw16"]["cat"].string)?.canBuildYourself == true else { return false }
        edit(&s, startupID) { $0["sw16"]["selfH"] = .number(left) }
        return true
    }
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
    public static func setInternalPrice(_ s: inout GameState, startupID: Int, percent: Double) {
        edit(&s, startupID) { if !$0["sw16"].isNull { $0["sw16"]["int"] = .number(min(100, max(0, percent))) } }
    }

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
    public static func rivalTargets(_ s: GameState, startupID: Int, data: GameData) -> [RivalTarget] {
        guard let raw = (s.rest["founded"]?.array ?? []).first(where: { $0["id"].int == startupID }), raw["st"].string == "live", let p = product(raw["sw16"]), p.ready else { return [] }
        var seen = Set<Int>(), out: [RivalTarget] = []
        for c in s.companies where c.status == .open {
            guard let bd = data.catalog[c.type], bd.family != "club" else { continue }
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
            let cnt = max(1, Int(saturating: (1 + (riv["size"].isNull ? 1 : riv["size"].double) * 3).rounded()))
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
                s.news("Startup \(co.name) shuts down.", tone: "n", companyID: co.id)
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
                        "sig": .object(["team": .number(pitchSignal(q, weight: 45, base: 30, noise: s.random.gauss() * 22)), "market": .number(clamp(jsRound(s.random.range(35, 90)), 5, 99)),
                                        "traction": .number(pitchSignal(q, weight: 35, base: 25, noise: s.random.gauss() * 28))])])
    }

    /// A pitch score hints at hidden quality but mostly reflects how well the founders sell: half of it is presentation and noise.
    static func pitchSignal(_ q: Double, weight: Double, base: Double, noise: Double) -> Double {
        clamp(jsRound(base + q * weight + noise), 3, 99)
    }

    /// Chance a startup reaches its next stage. Most fail: an average one exits about one time in seven, the best about one in three.
    static func survivalChance(quality q: Double, help: Double, stage: Int, demand: Double, bear: Bool) -> Double {
        clamp(0.35 + q * 0.4 + help * 0.04 + (demand - 1) * 0.3 - Double(stage) * 0.04 + (bear ? -0.08 : 0), 0.1, 0.8)
    }

    /// How much the valuation grows when a stage is reached.
    static func stageMultiple(_ roll: Double) -> Double { 1.3 + roll * 0.7 }

    /// The sale price at exit as a multiple of the last valuation: usually a modest trade sale, sometimes a fire sale, rarely a big win.
    static func exitMultiple(quality q: Double, kind: Double, roll: Double) -> Double {
        if kind < 0.02 { return 5 + roll * 7 }
        if kind < 0.02 + q * 0.5 { return 1 + roll * 1.5 }
        return 0.3 + roll * 0.7
    }

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

    @discardableResult
    public static func invest(_ s: inout GameState, pitchID: Int, amount: Double, context fc: FinanceContext) -> InvestResult {
        let q = investQuote(s, pitchID: pitchID, amount: amount, context: fc)
        guard q.result == .ok, let d = (s.rest["deals_su"]?.array ?? []).first(where: { $0["id"].int == pitchID }) else { return q.result }
        Payments.playerPays(&s, q.amount, label: "Invested in \(d["name"].string)")
        openStake(&s, pitch: d, amount: q.amount)
        if q.boardSeat { s.note("You hold \(String(format: "%.1f", q.ownershipPercent))% of \(d["name"].string) and get a board seat.", tone: "good") }
        return .ok
    }

    static func openStake(_ s: inout GameState, pitch d: JSONValue, amount amt: Double) {
        let pct = amt / d["post"].double * 100
        let f: JSONValue = .object(["id": .number(Double(s.makeID())), "name": d["name"], "sec": d["sec"], "q": d["q"], "st": "live", "stage": 0, "pct": .number(pct), "in": .number(amt), "val": d["post"],
                                    "w0": .number(Double(s.week)), "wNext": .number(Double(s.week + s.random.int(26, 52))), "seat": .bool(pct >= 20), "help": 0,
                                    "rounds": .array([.object(["w": .number(Double(s.week)), "amt": .number(amt), "pct": .number(pct)])]), "sig": d["sig"]])
        s.rest["startups"] = .array((s.rest["startups"]?.array ?? []) + [f])
        s.rest["deals_su"] = .array((s.rest["deals_su"]?.array ?? []).filter { $0["id"].int != d["id"].int })
    }

    static func editStake(_ s: inout GameState, _ id: Int, _ body: (inout JSONValue) -> Void) {
        guard var list = s.rest["startups"]?.array, let k = list.firstIndex(where: { $0["id"].int == id }) else { return }
        body(&list[k]); s.rest["startups"] = .array(list)
    }

    @discardableResult
    public static func help(_ s: inout GameState, stakeID: Int) -> Bool {
        guard let f = (s.rest["startups"]?.array ?? []).first(where: { $0["id"].int == stakeID }), f["seat"].bool, f["st"].string == "live", f["helpedW"].int != s.week || f["helpedW"].isNull else { return false }
        let wk = Double(s.week)
        editStake(&s, stakeID) { $0["help"] = .number(min(2, $0["help"].double + 0.25)); $0["helpedW"] = .number(wk) }
        return true
    }

    @discardableResult
    public static func sellStake(_ s: inout GameState, stakeID: Int, fraction: Double) -> Double {
        sellAsking(&s, stakeID: stakeID, fraction: fraction, askMultiplier: nil).proceeds
    }

    static func weeklyStakes(_ s: inout GameState) {
        guard var list = s.rest["startups"]?.array, !list.isEmpty else { return }
        for k in list.indices {
            var f = list[k]
            if f["st"].string != "live" || s.week < f["wNext"].int { continue }
            let bear = s.rest["mkt"]?["regime"].string == "bear"
            let pS = survivalChance(quality: f["q"].double, help: f["help"].double, stage: f["stage"].int, demand: s.economy.demand, bear: bear)
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
            let mult = stageMultiple(s.random.next())
            f["val"] = .number(f["val"].double * mult)
            if f["stage"].int >= 3 {
                let kind = s.random.next(), roll = s.random.next()
                let exitV = f["val"].double * exitMultiple(quality: f["q"].double, kind: kind, roll: roll)
                let proceeds = exitV * f["pct"].double / 100
                f["st"] = "exit"; f["val"] = 0
                Payments.playerReceives(&s, proceeds, label: "Exit: \(name)")
                s.tax.gains += proceeds - f["in"].double
                s.note("Exit: \(name) was acquired. Your stake pays \(Int(proceeds)) (\(String(format: "%.1f", proceeds / max(1, f["in"].double)))x).", tone: "good")
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

    public static func answer(_ s: inout GameState, message m: Message, option idx: Int) -> Bool {
        let data = m.value("data"), sid = data["sid"].int
        guard let f = (s.rest["startups"]?.array ?? []).first(where: { $0["id"].int == sid }) else { return true }
        if m.actionID == "round" {
            if idx == 0 {
                let mine = data["myShare"].double
                if Payments.liquid(s) < mine { return false }
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
        let need = data["need"].double
        if idx == 0 {
            if Payments.liquid(s) < need { return false }
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
