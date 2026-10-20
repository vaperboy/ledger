import Foundation
import GameCore
import Countries
import Finance

/// Rival groups: about ten named groups per country with an owner, a strategy, cash, debt and an ambition. They own many of the local
/// rivals you meet, and every month some of them make a move: cut prices beside you, open next door, buy an independent rival, push
/// marketing, raise prices or go abroad. Groups that overreach get into trouble and sell cheaply; some go bankrupt.
/// Original: features/world/rival_groups.js (`STRAT`, `ensureCC`, `assign`, `groupMonth`, `MOVES`, `onDistress`, `onCollapse`, `cutsWeek`, `monthTick`).
/// Bids for your companies (`bid`, answered in Events/RivalBids), poaching your manager (`poach`), buying your suppliers (`buysup`: dearer goods for
/// everyone who buys there) and the ranking of the biggest companies (`CompanyRanking`) are in.
public enum RivalGroups {
    struct Strategy { var name: String, text: String, margin: Double, growth: Double, leverage: Double, weights: [(String, Double)] }
    static let strategies: [(String, Strategy)] = [
        ("cost", Strategy(name: "Cost leader", text: "Low prices and thin margins. Wins on volume.", margin: 0.055, growth: 0.006, leverage: 0.5,
                          weights: [("undercut", 6), ("beside", 2), ("buyrival", 1), ("buysup", 2), ("poach", 1), ("abroad", 1), ("bid", 1), ("campaign", 1)])),
        ("premium", Strategy(name: "Premium", text: "Higher prices, better quality, a strong brand.", margin: 0.14, growth: 0.005, leverage: 0.3,
                             weights: [("campaign", 4), ("poach", 1.5), ("beside", 1), ("buyrival", 1), ("abroad", 2), ("bid", 1), ("raise", 3)])),
        ("acq", Strategy(name: "Acquirer", text: "Grows by buying others, often with borrowed money.", margin: 0.08, growth: 0.004, leverage: 0.9,
                         weights: [("buyrival", 6), ("buysup", 3), ("bid", 5), ("abroad", 1), ("poach", 0.5)])),
        ("expand", Strategy(name: "Aggressive expander", text: "Opens new sites fast and takes risks.", margin: 0.07, growth: 0.011, leverage: 0.8,
                            weights: [("beside", 6), ("undercut", 2), ("abroad", 3), ("campaign", 2), ("poach", 1)])),
        ("cautious", Strategy(name: "Cautious", text: "Slow and steady, with a strong balance sheet.", margin: 0.11, growth: 0.003, leverage: 0.15,
                              weights: [("campaign", 2), ("raise", 2), ("buyrival", 1)])),
    ]
    static func strategy(_ id: String) -> Strategy { strategies.first { $0.0 == id }?.1 ?? strategies[0].1 }
    static let groupWord: [String: String] = ["NO": "Gruppen", "SE": "Gruppen", "DE": "Gruppe", "FR": "Groupe", "ES": "Grupo", "BR": "Grupo", "PL": "Grupa", "NL": "Groep",
                                              "CH": "Gruppe", "MX": "Grupo", "IT": "Gruppo", "DK": "Gruppen", "FI": "Konserni"]
    static let localFamilies: Set<String> = ["svc", "venue", "retail", "project", "prod", "logi"]

    public struct Group: Identifiable, Equatable {
        public var id: String, name: String, owner: String, strategy: String, strategyName: String, strategyText: String
        public var branches: Int, revenue: Double, margin: Double, cash: Double, debt: Double
        public var trades: [String], countries: [String], moves: [(week: Int, text: String)], troubleSince: Int?, gone: Bool, ambition: String
        public var inTrouble: Bool { troubleSince != nil }
        public var profit: Double { revenue * margin }
        public static func == (a: Group, b: Group) -> Bool { a.id == b.id && a.revenue == b.revenue && a.cash == b.cash && a.debt == b.debt }
        public var cashWord: String { cash > revenue * 0.15 ? "Strong" : cash > revenue * 0.05 ? "Solid" : cash > 0 ? "Tight" : "Very tight" }
        public var debtWord: String { debt > revenue * 1.1 ? "Very high" : debt > revenue * 0.6 ? "High" : debt > revenue * 0.25 ? "Moderate" : "Low" }
    }

    static func read(_ g: JSONValue) -> Group {
        let st = strategy(g["strat"].string)
        return Group(id: g["id"].string, name: g["name"].string, owner: g["owner"].string, strategy: g["strat"].string, strategyName: st.name, strategyText: st.text,
                     branches: g["br"].int, revenue: g["rev"].double, margin: g["m"].double, cash: g["cash"].double, debt: g["debt"].double,
                     trades: g["types"].array.map { $0.string }, countries: g["cs"].array.map { $0.string },
                     moves: g["mv"].array.map { ($0["w"].int, $0["t"].string) }, troubleSince: g["dist"].double != 0 ? g["dist"].int : nil, gone: g["gone"].double != 0,
                     ambition: g["amb"].string)
    }

    public static func group(_ s: GameState, id: String?) -> Group? {
        guard let id = id, !id.isEmpty, id != "0", let g = s.rest["g27"]?["g"][id], !g.isNull else { return nil }
        return read(g)
    }

    /// The groups that compete in a country.
    static func all(_ s: GameState) -> [JSONValue] { Array((s.rest["g27"]?["g"] ?? .null).object.values) }

    public static func groups(_ s: GameState, country cc: String) -> [Group] {
        all(s).filter { !$0["gone"].bool && $0["cs"].array.contains { $0.string == cc } }.map(read).sorted { $0.revenue > $1.revenue }
    }

    // MARK: Making the groups

    static func tradeRevenue(_ bd: Trade, _ c: Country) -> Double {
        let dem = c.cities.isEmpty ? 1 : c.cities.reduce(0) { $0 + $1.demand } / Double(c.cities.count)
        return (bd.normalDemand == 0 ? 1 : bd.normalDemand) * bd.ticket * dem * 0.9 * 52 * c.priceLevel
    }

    static func ensureCountry(_ s: inout GameState, _ cc: String, data: GameData) {
        var root = s.rest["g27"] ?? .object(["g": .object([:]), "cc": .object([:]), "cool": .object([:]), "sent": 0, "sentM": 0])
        if !root["cc"][cc].isNull { return }
        guard let c = data.countries[cc] else { return }
        let types = data.catalog.order.filter { id in
            guard let bd = data.catalog[id] else { return false }
            return localFamilies.contains(bd.family) && bd.normalDemand > 0
        }
        guard !types.isEmpty else { return }
        var ids: [JSONValue] = []
        for i in 0..<10 {
            var h = HashedRandom("\(s.seed):g27:\(cc):\(i)")
            let t0 = types[Int(h.next() * Double(types.count)) % types.count]
            let fam = data.catalog[t0]?.family ?? "svc"
            var sib = types.filter { $0 != t0 && ((data.catalog[$0]?.family ?? "") == fam || h.next() < 0.12) }
            var ts = [t0]
            let nT = 1 + Int(h.next() * 2.6)
            while ts.count < nT, !sib.isEmpty { ts.append(sib.remove(at: Int(h.next() * Double(sib.count)) % sib.count)) }
            let strat = strategies[Int(h.next() * Double(strategies.count)) % strategies.count]
            let br = Int(jsRound(exp(1.6 + h.next() * 3.1)))
            let rev = Double(br) * ts.reduce(0) { $0 + tradeRevenue(data.catalog[$1]!, c) } / Double(ts.count) * (0.7 + h.next() * 0.6)
            var r = DeterministicRandom(seed: Int(h.next() * 1_000_000_000))
            let brand = brandRoot(c, family: fam, &r)
            let existing = Set((root["g"].object.values).map { $0["name"].string })
            var name = brand + " " + (groupWord[cc] ?? "Group")
            if existing.contains(name) { name = brand + " " + c.cities[i % c.cities.count].name + " " + (groupWord[cc] ?? "Group") }
            let owner = (c.firstNames.isEmpty ? "Alex" : c.firstNames[Int(h.next() * Double(c.firstNames.count)) % c.firstNames.count]) + " "
                + (c.lastNames.isEmpty ? "Smith" : c.lastNames[Int(h.next() * Double(c.lastNames.count)) % c.lastNames.count])
            let tradeName = data.catalog[t0]?.name.lowercased() ?? "business"
            let ambition: String
            switch strat.0 {
            case "acq": ambition = "Buy up \(tradeName) businesses across \(c.name)"
            case "expand": ambition = h.next() < 0.5 ? "Go international" : "No. 1 in \(tradeName)"
            case "premium": ambition = "Build the best-known \(tradeName) brand"
            case "cost": ambition = "No. 1 in \(tradeName)"
            default: ambition = "Grow steadily without borrowing"
            }
            let g: JSONValue = .object(["id": .string("g\(cc)\(i)"), "cc": .string(cc), "name": .string(name), "brand": .string(brand), "owner": .string(owner),
                                        "strat": .string(strat.0), "types": .array(ts.map { .string($0) }), "br": .number(Double(br)), "rev": .number(rev.rounded()),
                                        "m": .number(strat.1.margin * (0.8 + h.next() * 0.4)), "cash": .number((rev * (0.04 + h.next() * 0.18)).rounded()),
                                        "debt": .number((rev * strat.1.leverage * (0.4 + h.next() * 0.9)).rounded()), "cs": .array([.string(cc)]), "mv": .array([]),
                                        "dist": 0, "gone": 0, "amb": .string(ambition)])
            root["g"]["g\(cc)\(i)"] = g
            ids.append(.string("g\(cc)\(i)"))
        }
        root["cc"][cc] = .array(ids)
        s.rest["g27"] = root
    }

    static let stop: Set<String> = ["AS", "ASA", "AB", "ApS", "Oy", "GmbH", "AG", "KG", "Ltd", "PLC", "LLC", "Inc", "Corp", "Co", "SA", "SL", "SAS", "SARL", "BV", "NV", "UAB", "og", "och", "und", "and", "&"]
    static func brandRoot(_ c: Country, family: String, _ r: inout DeterministicRandom) -> String {
        for _ in 0..<8 {
            let nm = CompanySetup.generateName(country: c, family: family, &r)
            let words = nm.split(separator: " ").map(String.init).filter { $0.count >= 3 && !$0.contains(".") && !stop.contains($0) && ($0.first?.isUppercase ?? false) }
            if let w0 = words.first { return words.count > 1 && w0.count < 5 ? w0 + " " + words[1] : w0 }
        }
        return c.name
    }

    /// Decide which local rivals belong to a group (once). Original: `assign`.
    static func assign(_ s: inout GameState, key k: String, type: String, countryCode cc: String, data: GameData) {
        guard let riv = s.rest["mk"]?[k]["riv"].array, riv.contains(where: { $0["g27"].isNull }) else { return }
        ensureCountry(&s, cc, data: data)
        let cand = all(s).filter { !$0["gone"].bool && $0["cs"].array.contains { $0.string == cc } && $0["types"].array.contains { $0.string == type } }
            .sorted { $0["id"].string < $1["id"].string }
        for r in riv where r["g27"].isNull {
            let h = HashedRandom.first("\(s.seed):ga:\(r["id"].int)")
            let p = r["size"].double > 1.1 ? 0.62 : r["size"].double > 0.8 ? 0.45 : 0.25
            let pick: String = (!cand.isEmpty && h < p) ? cand[Int(h * 1009) % cand.count]["id"].string : "0"
            Rivals.mutate(&s, key: k, id: r["id"].int) { $0["g27"] = .string(pick) }
        }
    }

    // MARK: Weekly and monthly

    static func profit(_ g: JSONValue, _ s: GameState) -> Double { g["rev"].double * g["m"].double - g["debt"].double * (s.economy.policyRate + 0.025) }
    static func holdWeeks(_ g: JSONValue) -> Int {
        Int(clamp((6 + (g["cash"].double / max(1, g["rev"].double)) * 90 - (g["debt"].double / max(1, g["rev"].double)) * 6).rounded(), 3, 40))
    }
    static func logMove(_ g: inout JSONValue, week: Int, _ text: String) {
        var mv = g["mv"].array
        mv.insert(.object(["w": .number(Double(week)), "t": .string(text)]), at: 0)
        if mv.count > 10 { mv.removeLast(mv.count - 10) }
        g["mv"] = .array(mv)
    }
    static func pay(_ g: inout JSONValue, _ amt: Double) {
        g["cash"] = .number(g["cash"].double - amt.rounded())
        if g["cash"].double < 0 { g["debt"] = .number(g["debt"].double - g["cash"].double); g["cash"] = 0 }
    }

    static func weekly(_ s: inout GameState, data: GameData) {
        guard s.rest["g27"] != nil || s.companies.contains(where: { $0.status == .open }) else { return }
        // A rival's price cut runs out.
        if let mk = s.rest["mk"] {
            for k in mk.object.keys.sorted() {
                for r in mk[k]["riv"].array where !r["uc27"].isNull && Double(s.week) >= r["uc27"]["end"].double {
                    let from = r["uc27"]["from"].double
                    Rivals.mutate(&s, key: k, id: r["id"].int) { rr in
                        rr["pm16"] = .number(max(rr["pm16"].double, jsRound(from * 0.97 * 1000) / 1000)); rr["uc27"] = .null
                    }
                    if let cid = r["uc27"]["co"].double != 0 ? Int(r["uc27"]["co"].double) : nil, s.company(cid) != nil {
                        s.note("\(r["name"].string) ended its price cut.", companyID: cid)
                    }
                }
            }
        }
        guard GameCalendar.isMonthEnd(week: s.week) else { return }
        monthTick(&s, data: data)
    }

    static func myCountries(_ s: GameState) -> [String] {
        var out = Set(s.companies.filter { $0.status == .open || $0.status == .setup }.map { $0.countryCode })
        out.insert(s.homeCountryCode)
        return out.sorted()
    }

    /// Every rival a group has in the player's markets.
    public static func members(_ s: GameState, groupID: String) -> [(companyIndex: Int, key: String, rivalID: Int)] {
        var out: [(companyIndex: Int, key: String, rivalID: Int)] = []
        for (i, co) in s.companies.enumerated() where co.status == .open {
            let k = Rivals.key(co)
            for r in s.rest["mk"]?[k]["riv"].array ?? [] where r["g27"].string == groupID && !out.contains(where: { $0.rivalID == r["id"].int }) { out.append((i, k, r["id"].int)) }
        }
        return out
    }

    static func monthTick(_ s: inout GameState, data: GameData) {
        CompanyRanking.snapshot(&s, data: data)
        let mine = myCountries(s)
        for cc in mine { ensureCountry(&s, cc, data: data) }
        guard var root = s.rest["g27"] else { return }
        let ids = root["g"].object.keys.sorted()
        let mi = s.week / 4
        // The life of each group
        for id in ids where !root["g"][id]["gone"].bool {
            var g = root["g"][id]
            let st = strategy(g["strat"].string)
            var h = HashedRandom("\(s.seed):gm:\(id):\(mi)")
            let home = g["cc"].string == s.homeCountryCode
            let dem = home ? s.economy.demand : 1
            let grow = st.growth * (0.6 + h.next() * 0.8) + (dem - 1) * 0.08 + (g["dist"].double != 0 ? -0.006 : 0)
            g["rev"] = .number((g["rev"].double * (1 + grow)).rounded())
            g["m"] = .number(clamp(g["m"].double + (h.next() - 0.5) * 0.01 + (dem - 1) * 0.02 + (st.margin - g["m"].double) * 0.1, -0.08, 0.3))
            g["cash"] = .number((g["cash"].double + profit(g, s) / 12 * 0.75).rounded())
            if g["cash"].double < 0 { g["debt"] = .number((g["debt"].double - g["cash"].double).rounded()); g["cash"] = 0 }
            if g["cash"].double > g["rev"].double * 0.25, g["debt"].double > 0 {
                let d = min(g["debt"].double, g["cash"].double - g["rev"].double * 0.15)
                g["debt"] = .number(g["debt"].double - d.rounded()); g["cash"] = .number(g["cash"].double - d.rounded())
            }
            g["br"] = .number(Double(max(1, Int(jsRound(g["br"].double * (1 + grow))))))
            let lev = g["debt"].double / max(1, g["rev"].double)
            if g["dist"].double == 0, lev > 1.15, profit(g, s) < 0 {
                g["dist"] = .number(Double(s.week)); logMove(&g, week: s.week, "Money troubles: selling assets")
                root["g"][id] = g; s.rest["g27"] = root
                onDistress(&s, groupID: id)
                root = s.rest["g27"]!; g = root["g"][id]
            } else if g["dist"].double != 0, lev < 0.8, profit(g, s) > 0 {
                g["dist"] = 0; s.note("\(g["name"].string) has recovered from its money troubles.")
            } else if g["dist"].double != 0, s.week - g["dist"].int > 52, lev > 1.4 {
                root["g"][id] = g; s.rest["g27"] = root
                onCollapse(&s, groupID: id)
                root = s.rest["g27"]!; continue
            }
            root["g"][id] = g
        }
        s.rest["g27"] = root
        // Moves: only groups that compete with you somewhere
        var sent = 0
        for id in ids {
            guard let g = s.rest["g27"]?["g"][id], !g["gone"].bool, g["cs"].array.contains(where: { mine.contains($0.string) }) else { continue }
            var h = HashedRandom("\(s.seed):gmv:\(id):\(mi)")
            let st = strategy(g["strat"].string)
            let p = 0.2 * (g["strat"].string == "cautious" ? 0.5 : (g["strat"].string == "expand" || g["strat"].string == "acq") ? 1.25 : 1) * (g["dist"].double != 0 ? 0.4 : 1)
            if h.next() > p { continue }
            let tot = st.weights.reduce(0) { $0 + $1.1 }
            var x = h.next() * tot
            var kindName = st.weights[0].0
            for w in st.weights { if x < w.1 { kindName = w.0; break }; x -= w.1 }
            if ["undercut", "beside", "buysup", "poach", "bid"].contains(kindName), sent >= 3 { continue }
            if move(&s, id, kindName, &h, data: data), ["undercut", "beside", "buysup", "poach", "bid"].contains(kindName) { sent += 1 }
        }
    }

    // MARK: Moves

    static func targets(_ s: GameState, _ g: JSONValue, data: GameData) -> [Int] {
        let w = World(state: s, data: data)
        return s.companies.indices.filter { i in
            let c = s.companies[i]
            guard c.status == .open, g["cs"].array.contains(where: { $0.string == c.countryCode }), g["types"].array.contains(where: { $0.string == c.type }),
                  let bd = data.catalog[c.type], localFamilies.contains(bd.family) else { return false }
            return MarketMap.noticed(s, c, bd, w)
        }
    }

    static func move(_ s: inout GameState, _ id: String, _ kind: String, _ h: inout HashedRandom, data: GameData) -> Bool {
        guard var g = s.rest["g27"]?["g"][id] else { return false }
        let troubled = g["dist"].double != 0
        let week = s.week
        func cooldown(_ k: String, _ w: Int) -> Bool {
            let cur = s.rest["g27"]?["cool"][k].double ?? 0
            if cur != 0, Double(week) < cur { return false }
            s.rest["g27"]?["cool"][k] = .number(Double(week + w)); return true
        }
        func save() { s.rest["g27"]?["g"][id] = g }
        let name = g["name"].string
        switch kind {
        case "undercut":
            let ms = members(s, groupID: id).filter { m in
                let r = s.rest["mk"]?[m.key]["riv"].array.first { $0["id"].int == m.rivalID }
                return (r?["uc27"].isNull ?? false) && MarketMap.noticed(s, s.companies[m.companyIndex], data.catalog[s.companies[m.companyIndex].type]!, World(state: s, data: data))
            }
            guard !ms.isEmpty, !troubled else { return false }
            let m = ms[Int(h.next() * Double(ms.count)) % ms.count]
            let co = s.companies[m.companyIndex]
            guard cooldown("uc:" + m.key, 20) else { return false }
            let pct = g["strat"].string == "cost" ? 15 + Int(h.next() * 11) : 10 + Int(h.next() * 9)
            let wk = min(holdWeeks(g), 8 + Int(h.next() * 9))
            guard let r = s.rest["mk"]?[m.key]["riv"].array.first(where: { $0["id"].int == m.rivalID }) else { return false }
            let from = r["pm16"].isNull ? 1 : r["pm16"].double
            Rivals.mutate(&s, key: m.key, id: m.rivalID) { rr in
                rr["uc27"] = .object(["end": .number(Double(week + wk)), "pct": .number(Double(pct)), "from": .number(from), "co": .number(Double(co.id)), "w": .number(Double(week))])
                rr["pm16"] = .number(clamp(jsRound(from * (1 - Double(pct) / 100) * 1000) / 1000, 0.6, 1.6))
            }
            PriceMoves.addModifier(&s, m.companyIndex, key: "dem", multiplier: 1 - Double(pct) / 300, weeks: Double(wk))
            let city = data.countries.city(co.cityID, preferring: co.countryCode)?.city.name ?? "town"
            logMove(&g, week: week, "Cut prices \(pct)% in \(city) (\(r["name"].string))"); save()
            s.addMessage(from: "Market", title: "\(r["name"].string) cut prices \(pct)%",
                         body: "\(r["name"].string), part of \(name), cut its prices about \(pct)% in \(city), right where \(co.name) competes. Some of your customers will try them. You can hold, answer with a discount, or start a price war.",
                         companyID: co.id, tone: "bad")
            return true
        case "beside":
            let ts = targets(s, g, data: data).filter { s.companies[$0].value("lastW")["util"].double > 0.7 || Reviews.rating(s.companies[$0]) >= 3.8 }
            guard !ts.isEmpty, !troubled, g["cash"].double >= g["rev"].double * 0.02 else { return false }
            let i = ts[Int(h.next() * Double(ts.count)) % ts.count]
            let co = s.companies[i], k = Rivals.key(co)
            guard cooldown("bs:" + k, 40), var mk = s.rest["mk"], !mk[k].isNull else { return false }
            let city = data.countries.city(co.cityID, preferring: co.countryCode)?.city.name ?? "town"
            let rid = Rivals.nextID(&s)
            let r: JSONValue = .object(["id": .number(Double(rid)), "name": .string(g["brand"].string + " " + city), "owner": g["owner"], "size": .number(jsRound((0.75 + h.next() * 0.35) * 100) / 100),
                                        "rel": 35, "listed": false, "ign": 0, "lock": 0, "meet": -99, "g27": .string(id), "pm16": .number(Rivals.initialPrice(seed: s.seed, id: rid)), "ig16": 1,
                                        "nx16": .number(Double(week + 6))])
            mk = s.rest["mk"]!
            mk[k]["riv"] = .array(mk[k]["riv"].array + [r]); mk[k]["n"] = .number(mk[k]["n"].double + 1)
            s.rest["mk"] = mk
            PriceMoves.addModifier(&s, i, key: "dem", multiplier: 0.93, weeks: 26)
            if let bd0 = data.catalog[co.type], let c0 = data.countries[co.countryCode] { pay(&g, tradeRevenue(bd0, c0) * 0.25) }
            g["br"] = .number(g["br"].double + 1)
            logMove(&g, week: week, "Opened \(r["name"].string) next to \(co.name)"); save()
            s.addMessage(from: "Market", title: "\(name) opens next to \(co.name)",
                         body: "\(name) opened \(r["name"].string) a few doors from \(co.name). They saw your customers queuing. Expect fewer walk-ins for a while.", companyID: co.id, tone: "bad")
            return true
        case "buyrival":
            var opts: [(Int, String, JSONValue)] = []
            for i in targets(s, g, data: data) { let k = Rivals.key(s.companies[i]); for r in s.rest["mk"]?[k]["riv"].array ?? [] where r["g27"].string == "0" && r["uc27"].isNull { opts.append((i, k, r)) } }
            guard !opts.isEmpty, !troubled else { return false }
            let x = opts[Int(h.next() * Double(opts.count)) % opts.count]
            let co = s.companies[x.0]
            guard let bd = data.catalog[co.type] else { return false }
            let w = World(state: s, data: data)
            let rv = Rivals.read(x.2, week: week)
            let price = Rivals.value(bd, rv, w, co) * (1 + 0.3 * h.next())
            guard g["cash"].double + g["rev"].double * 0.3 >= price, cooldown("br:" + x.1, 30) else { return false }
            Rivals.mutate(&s, key: x.1, id: rv.id) { rr in
                rr["g27"] = .string(id); rr["size"] = .number(jsRound(rr["size"].double * 1.08 * 100) / 100); rr["listed"] = false
                if g["strat"].string == "cost" { rr["pm16"] = .number(clamp(rr["pm16"].double * 0.94, 0.6, 1.6)) }
                if g["strat"].string == "premium" { rr["pm16"] = .number(clamp(rr["pm16"].double * 1.06, 0.6, 1.6)) }
            }
            pay(&g, price); g["br"] = .number(g["br"].double + 1)
            let city = data.countries.city(co.cityID, preferring: co.countryCode)?.city.name ?? "town"
            logMove(&g, week: week, "Bought \(rv.name) in \(city)"); save()
            s.note("\(name) bought \(rv.name) in \(city). " + (g["strat"].string == "cost" ? "Expect lower prices there." : g["strat"].string == "premium" ? "They will take it upmarket." : "It now has a big group behind it."), tone: "bad", companyID: co.id)
            s.news("\(name) buys \(rv.name).")
            return true
        case "campaign":
            let ms = members(s, groupID: id).filter { m in s.rest["mk"]?[m.key]["riv"].array.first { $0["id"].int == m.rivalID }?["mkt16"].isNull ?? false }
            guard !ms.isEmpty else { return false }
            let m = ms[Int(h.next() * Double(ms.count)) % ms.count]
            Rivals.mutate(&s, key: m.key, id: m.rivalID) { $0["mkt16"] = .number(Double(week + 4 + Int(h.next() * 7))) }
            let rn = s.rest["mk"]?[m.key]["riv"].array.first { $0["id"].int == m.rivalID }?["name"].string ?? "A rival"
            logMove(&g, week: week, "Marketing push for \(rn)"); save()
            s.note("\(name) started a big marketing push for \(rn).", companyID: s.companies[m.companyIndex].id)
            return true
        case "raise":
            let ms = members(s, groupID: id)
            guard !ms.isEmpty else { return false }
            for m in ms { Rivals.mutate(&s, key: m.key, id: m.rivalID) { $0["pm16"] = .number(clamp($0["pm16"].double * 1.06, 0.6, 1.6)) } }
            logMove(&g, week: week, "Raised prices about 6%"); save()
            s.note("\(name) raised its prices about 6%. Price-sensitive customers may look for an alternative, like you.", tone: "good", companyID: s.companies[ms[0].companyIndex].id)
            return true
        case "abroad":
            guard !troubled, g["cash"].double >= g["rev"].double * 0.05, g["br"].double >= 12, g["cs"].array.count < 4, cooldown("ab:" + id, 78) else { return false }
            let all = data.countries.countries.map { $0.code }.filter { c in !g["cs"].array.contains { $0.string == c } }
            let mine = myCountries(s).filter { all.contains($0) }
            let pool = (!mine.isEmpty && h.next() < 0.6) ? mine : all
            guard !pool.isEmpty else { return false }
            let cc = pool[Int(h.next() * Double(pool.count)) % pool.count]
            g["cs"] = .array(g["cs"].array + [.string(cc)]); pay(&g, g["rev"].double * 0.05)
            let cn = data.countries[cc]?.name ?? cc
            logMove(&g, week: week, "Entered \(cn)"); save()
            s.news("\(name) expands into \(cn).", tone: myCountries(s).contains(cc) ? "bad" : "n")
            return true
        case "poach":
            // Try to hire your best manager away: they ask you to match, pay a bonus or let them go.
            let types = g["types"].array.map { $0.string }
            let fam0 = types.first.flatMap { data.catalog[$0]?.family }
            let cands = s.companies.indices.filter { i in
                let c = s.companies[i]
                guard c.status == .open, let mid = c.managerID, c.value("mgrNotice").isNull, let p = s.people[mid], let bd = data.catalog[c.type],
                      g["cs"].array.contains(where: { $0.string == c.countryCode }), p.num("ret27") <= Double(week) else { return false }
                return types.contains(c.type) || bd.family == fam0
            }
            func q(_ i: Int) -> Double { ManagerModel.quality(s.companies[i], data.catalog[s.companies[i].type]!, people: s.people) }
            guard let ci = cands.max(by: { q($0) < q($1) }), q(ci) >= 0.45, cooldown("po:\(s.companies[ci].id)", 78), cooldown("po:all", 26),
                  let n = s.people[s.companies[ci].managerID ?? 0] else { return false }
            let co = s.companies[ci]
            let cur = World(state: s, data: data).currency(co)
            let offer = cur.roundedStep((co.managerMonthlyWage > 0 ? co.managerMonthlyWage : n.askingMonthlyWage) * (1.18 + h.next() * 0.17), about: 500)
            logMove(&g, week: week, "Tried to hire \(n.name) from \(co.name)"); save()
            s.addMessage(kind: "ask", from: n.name, title: "\(name) wants to hire your manager",
                         body: "\(n.name), who runs \(co.name), has an offer from \(name): \(cur.display(offer)) a month, against \(cur.display(co.managerMonthlyWage)) now. \(n.name.split(separator: " ").first.map(String.init) ?? n.name) likes it here, but the money is good.",
                         companyID: co.id, tone: "bad", status: "open",
                         options: [.option("Match it", "Pay \(cur.display(offer)) a month from now on."),
                                   .option("A retention bonus", "Three months' pay now. Most stay for at least a year; some still go."),
                                   .option("Let them go", "They leave in two weeks. You need a new manager.")],
                         action: "g27poach", data: .object(["co": .number(Double(co.id)), "n": .number(Double(n.id)), "g": .string(id), "offer": .number(offer)]), expiresWeek: week + 2)
            return true
        case "buysup":
            let T = targets(s, g, data: data)
            guard !T.isEmpty, !troubled else { return false }
            let co = s.companies[T[Int(h.next() * Double(T.count)) % T.count]]
            guard let v = goodsSupplier(s, co, data: data), s.rest["g27"]?["vown"][v.id].isNull ?? true, cooldown("sup:" + v.id, 80) else { return false }
            s.rest["g27"]?["vown"][v.id] = .string(id)
            pay(&g, g["rev"].double * 0.08)
            logMove(&g, week: week, "Bought the supplier \(v.name)"); save()
            var hit: [String] = []
            for j in s.companies.indices where s.companies[j].status == .open {
                if let w = goodsSupplier(s, s.companies[j], data: data), w.id == v.id {
                    hit.append(s.companies[j].name)
                    PriceMoves.addModifier(&s, j, key: "cogsup", multiplier: 1.06, weeks: 520)
                }
            }
            s.addMessage(from: "Market", title: "\(name) bought your supplier \(v.name)",
                         body: "\(v.name), which supplies \(hit.joined(separator: ", ")), now belongs to \(name), a competitor. Prices to you go up about 6% and deliveries come second to their own shops.",
                         companyID: co.id, tone: "bad")
            return true
        case "bid":
            guard !troubled else { return false }
            let acq = g["strat"].string == "acq"
            let types = g["types"].array.map { $0.string }
            let T = s.companies.indices.filter { i in
                let c = s.companies[i]
                return c.status == .open && c.type != "hold" && g["cs"].array.contains(where: { $0.string == c.countryCode }) && (types.contains(c.type) || acq)
                    && Valuation.companyValue(c, state: s, trades: data.catalog) > 0 && CompanyFigures.yearlyProfitEstimate(c, currentWeek: week) > 0
                    && week - (c.openedWeek ?? c.foundedWeek) > 78 && !(c.num("bid27") > Double(week))
            }
            guard let ti = T.max(by: { Valuation.companyValue(s.companies[$0], state: s, trades: data.catalog) < Valuation.companyValue(s.companies[$1], state: s, trades: data.catalog) }) else { return false }
            let co = s.companies[ti]
            let V0 = Valuation.companyValue(co, state: s, trades: data.catalog)
            let price = ((V0 * (acq ? 1.1 + h.next() * 0.3 : 1.0 + h.next() * 0.25)) / 1000).rounded() * 1000
            guard g["cash"].double + g["rev"].double * 0.6 - g["debt"].double * 0.3 >= price, cooldown("bid:all", 26) else { return false }
            s.companies[ti].set("bid27", Double(week + 104))
            let cur = World(state: s, data: data).currency(co)
            logMove(&g, week: week, "Bid \(cur.short(price)) for \(co.name)"); save()
            let out = 100 - co.ownership
            let pct = Int(jsRound((price / max(1, V0) - 1) * 100))
            let mine = price * co.ownership / 100
            s.addMessage(kind: "ask", from: "\(g["owner"].string), \(name)", title: "\(name) wants to buy \(co.name)",
                         body: "\(name) offers \(cur.display(price)) for all of \(co.name) (about \(abs(pct))% \(price >= V0 ? "above" : "below") what it is worth today). "
                            + (co.ownership < 100 ? "You own \(Int(jsRound(co.ownership)))%, so you would get \(cur.display(mine)). " : "")
                            + (out > 50 ? "Outside owners hold \(Int(jsRound(out)))%. If the price is good they can accept without you." : out >= 33.4 ? "Outside owners hold \(Int(jsRound(out)))% and will want a say." : ""),
                         companyID: co.id, tone: "n", status: "open",
                         options: [.option("Accept", "Sell now for \(cur.display(mine)) to you."), .option("Ask for more", "They may raise their offer, or walk away."),
                                   .option("Refuse", "Keep it. They may come back, or compete harder.")],
                         action: "g27bid", data: .object(["co": .number(Double(co.id)), "g": .string(id), "price": .number(price), "V0": .number(V0), "round": 0]), expiresWeek: week + 3)
            return true
        default: return false
        }
    }

    // MARK: Poaching, supplier purchases and bids: the follow-ups

    /// The goods supplier a company buys from (the first of its vendor list while vendor choice is not ported). Original: `goodsPick`.
    static func goodsSupplier(_ s: GameState, _ co: Company, data: GameData) -> (id: String, name: String)? {
        guard let bd = data.catalog[co.type], bd.costOfSales >= 0.03, !["fin", "energy", "rent", "club", "svc"].contains(bd.family),
              !bd.id.hasPrefix("engcons"), !bd.id.hasPrefix("event") else { return nil }
        let list = EquipmentMarket.vendors(for: "goods:" + co.type, count: EquipmentMarket.brandCount(co, state: s), family: bd.family, seed: s.seed,
                                           countryCode: co.countryCode, countries: data.countries, nouns: data.catalog.tables.raw["FAM_NOUN"])
        return list.first.map { ($0.id, $0.name) }
    }

    /// Is this supplier owned by a competitor?
    public static func supplierOwner(_ s: GameState, vendorID: String) -> String? {
        let o = s.rest["g27"]?["vown"][vendorID] ?? .null
        return o.isNull ? nil : o.string
    }

    /// The owner answers a call about the manager. Original: `ACTS.g27poach`.
    public static func answerPoach(_ s: inout GameState, message m: Message, option idx: Int, data: GameData) {
        let d = m.value("data")
        guard let ci = s.companyIndex(d["co"].int), let mid = s.companies[ci].managerID, mid == d["n"].int, var n = s.people[mid] else { return }
        let co = s.companies[ci]
        let gid = d["g"].string
        switch idx {
        case 0:
            s.companies[ci].managerMonthlyWage = d["offer"].double
            n.set("ret27", Double(s.week + 78)); s.people[mid] = n
            s.companies[ci].set("mood", min(100, ManagerModel.mood(co) + 6))
            s.note("\(n.name) stays at \(co.name) on the new pay.", tone: "good", companyID: co.id)
        case 1:
            Payments.companyPays(&s, companyID: co.id, amount: co.managerMonthlyWage * 3, category: "wages", label: "Retention bonus for \(n.name)")
            if s.random.chance(0.72) {
                n.set("ret27", Double(s.week + 52)); s.people[mid] = n
                s.note("\(n.name) takes the bonus and stays.", tone: "good", companyID: co.id)
            } else { poachGo(&s, ci, groupID: gid) }
        default: poachGo(&s, ci, groupID: gid)
        }
    }

    /// They accept the offer and work out their notice. Original: `poachGo`.
    public static func poachGo(_ s: inout GameState, _ ci: Int, groupID gid: String) {
        let co = s.companies[ci]
        let g = s.rest["g27"]?["g"][gid] ?? .null
        let who = co.managerID.flatMap { s.people[$0]?.name } ?? "The manager"
        ManagerModel.resign(&s, companyIndex: ci, why: "I have accepted the offer", to: g.isNull ? "a competitor" : g["name"].string)
        guard !g.isNull else { return }
        s.rest["g27"]?["g"][gid]["mg"] = .number(g["mg"].double + 1)
        s.rest["g27"]?["g"][gid]["m"] = .number(min(0.3, g["m"].double + 0.004))
        var gg = s.rest["g27"]?["g"][gid] ?? g
        logMove(&gg, week: s.week, "Hired \(who) from \(co.name)")
        s.rest["g27"]?["g"][gid] = gg
    }

    /// After you sold a company to a group: it becomes one of the group's sites in the market; the group pays. Original: `sellToGroup` (after `acceptSale`).
    public static func completeSale(_ s: inout GameState, groupID gid: String, company co: Company, price: Double, data: GameData) {
        guard var g = s.rest["g27"]?["g"][gid], !g.isNull else { return }
        let k = Rivals.key(co)
        if var mk = s.rest["mk"], !mk[k].isNull, localFamilies.contains(data.catalog[co.type]?.family ?? "") {
            let rid = Rivals.nextID(&s)
            mk = s.rest["mk"]!
            let r: JSONValue = .object(["id": .number(Double(rid)), "name": .string(co.name), "owner": g["owner"], "size": .number(jsRound(clamp(co.size, 0.5, 2) * 100) / 100),
                                        "rel": 50, "listed": false, "ign": 0, "lock": 0, "meet": -99, "g27": .string(gid), "pm16": .number(Rivals.initialPrice(seed: s.seed, id: rid)), "ig16": 1,
                                        "nx16": .number(Double(s.week + 6))])
            mk[k]["riv"] = .array(mk[k]["riv"].array + [r]); mk[k]["n"] = .number(mk[k]["n"].double + 1)
            s.rest["mk"] = mk
        }
        pay(&g, price)
        g["br"] = .number(g["br"].double + 1)
        logMove(&g, week: s.week, "Bought \(co.name) from you")
        s.rest["g27"]?["g"][gid] = g
        s.news("\(g["name"].string) buys \(co.name).")
    }

    // MARK: Trouble

    static func onDistress(_ s: inout GameState, groupID id: String) {
        let ms = members(s, groupID: id)
        for m in ms { let wk = s.week; Rivals.mutate(&s, key: m.key, id: m.rivalID) { $0["listed"] = true; $0["dist27"] = .number(Double(wk)) } }
        guard let g = s.rest["g27"]?["g"][id] else { return }
        s.news("\(g["name"].string) is in financial trouble and looks for buyers for parts of the business.", tone: "bad")
        if let first = ms.first {
            let names = ms.compactMap { m in s.rest["mk"]?[m.key]["riv"].array.first { $0["id"].int == m.rivalID }?["name"].string }.joined(separator: ", ")
            s.addMessage(from: "Business broker", title: "\(g["name"].string) is selling, cheaply",
                         body: "\(g["name"].string) is losing money and carries heavy debt. It will sell \(names) in your markets well below their usual price. If you want to expand, now is the time.",
                         companyID: s.companies[first.companyIndex].id, tone: "good")
        }
    }

    static func onCollapse(_ s: inout GameState, groupID id: String) {
        let ms = members(s, groupID: id)
        s.rest["g27"]?["g"][id]["gone"] = .number(Double(s.week))
        for m in ms {
            Rivals.removeRival(&s, key: m.key, id: m.rivalID)
            s.companies[m.companyIndex].awareness = min(100, s.companies[m.companyIndex].awareness + 6)
            PriceMoves.addModifier(&s, m.companyIndex, key: "dem", multiplier: 1.08, weeks: 26)
        }
        let name = s.rest["g27"]?["g"][id]["name"].string ?? "A group"
        s.news("\(name) goes bankrupt.", tone: "bad")
        if let f = ms.first { s.addMessage(from: "Market", title: "\(name) has gone bankrupt", body: "Its sites close. Some of their customers will come to you.", companyID: s.companies[f.companyIndex].id, tone: "good") }
    }
}
