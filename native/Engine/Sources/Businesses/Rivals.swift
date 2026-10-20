import Foundation
import GameCore
import Countries
import Finance

/// Named rivals: each local market has a few competing businesses with an owner, a size, a price of their own, discounts, marketing
/// pushes, a mood towards you, and sometimes a group behind them. They live inside the market record (`rest["mk"][key]["riv"]`)
/// that `WorldWeek.competitors` already keeps, so the number of rivals and the market price index stay one thing.
/// Originals: `rivalsOfCore`, `rivalValue`, `meetRival`, `proposeBuy`, `acquireRival` (engine/world/rivals.js); `rivalWeek`
/// (features/world/rivals_run_businesses.js); `pwWeek`, `warCalc` (price wars); `remember`, `rivalWeek`, `moodOf` (world_around_you.js).
///
/// Everything random here is drawn from text-seeded generators (`HashedRandom`), so it never disturbs the main random stream.
public enum Rivals {
    static let noPrice: Set<String> = ["rent", "fin", "energy", "club", "hold"]

    public struct Rival: Identifiable, Equatable {
        public var id: Int
        public var name: String
        public var owner: String
        public var size: Double
        public var relationship: Double
        public var forSale: Bool
        public var priceFactor: Double          // relative to the market (1 = the going price)
        public var discountPercent: Int?        // running campaign
        public var marketing: Bool
        public var holdingPrices: Bool
        public var groupID: String?
        public var known: Bool                  // has noticed you
        public var memory: [(week: Int, text: String, change: Double)]
        public static func == (a: Rival, b: Rival) -> Bool { a.id == b.id && a.size == b.size && a.relationship == b.relationship }
    }

    // MARK: Reading

    public static func key(_ co: Company) -> String { co.type + "|" + co.cityID }

    public static func rivals(_ s: GameState, for co: Company) -> [Rival] { rivals(s, key: key(co)) }

    public static func rivals(_ s: GameState, key: String) -> [Rival] {
        (s.rest["mk"]?[key]["riv"].array ?? []).map { read($0, week: s.week) }
    }

    static func read(_ r: JSONValue, week: Int) -> Rival {
        Rival(id: r["id"].int, name: r["name"].string, owner: r["owner"].string, size: r["size"].double, relationship: r["rel"].double,
              forSale: r["listed"].bool, priceFactor: effectivePrice(r, week: week), discountPercent: running(r["camp16"], week) ? r["camp16"]["pct"].int : nil,
              marketing: r["mkt16"].double > Double(week), holdingPrices: r["hold16"].bool,
              groupID: r["g27"].isNull || r["g27"].string.isEmpty || r["g27"].string == "0" ? nil : r["g27"].string, known: !r["n31"].isNull && r["n31"].double != 0,
              memory: r["mem31"].array.map { ($0["w"].int, $0["t"].string, $0["d"].double) })
    }

    static func running(_ camp: JSONValue, _ week: Int) -> Bool { !camp.isNull && Double(week) < camp["end"].double }

    /// A rival's own price relative to the market. Original: `R18.effP`.
    static func effectivePrice(_ r: JSONValue, week: Int) -> Double {
        let pm = r["pm16"].isNull ? 1 : r["pm16"].double
        let ig = r["ig16"].isNull ? 1 : r["ig16"].double
        return pm / ig * (running(r["camp16"], week) ? 1 - r["camp16"]["pct"].double / 100 : 1)
    }

    static func initialPrice(seed: Int, id: Int) -> Double { jsRound((0.82 + HashedRandom.first("\(seed):rp:\(id)") * 0.4) * 1000) / 1000 }

    /// What a rival charges in money terms (for comparing with your own ticket). Original: `rivPrice`.
    public static func price(_ co: Company, _ r: Rival, _ w: World) -> Double {
        guard let bd = w.trade(co) else { return 0 }
        return Pricing.ticket(co, bd, w) / max(0.01, Pricing.priceIndex(co, w)) * r.priceFactor
    }

    // MARK: Numbers an analyst could read

    /// A rival's sales in a year; the same formula everywhere so the screens agree. Original: `truth(co, r).rev`, `rivRev`.
    public static func yearlyRevenue(_ bd: Trade, _ r: Rival, _ w: World, _ co: Company) -> Double {
        (bd.normalDemand == 0 ? 1 : bd.normalDemand) * bd.ticket * (w.city(co)?.demand ?? 1) * r.size * 0.9 * 52
    }

    /// What the rival business is worth. Original: `rivalValue`.
    public static func value(_ bd: Trade, _ r: Rival, _ w: World, _ co: Company) -> Double {
        let rev = yearlyRevenue(bd, r, w, co) / 52
        return roundTo(rev * 52 * (max(0.04, bd.margin) * 4.5 + 0.15), 1000)
    }

    public static func margin(_ bd: Trade, _ r: Rival, seed: Int, inPriceWar: Bool = false) -> Double {
        clamp(bd.margin + (HashedRandom.first("\(seed):m:\(r.id)") - 0.5) * 0.14, -0.12, 0.45)
    }

    /// How many weeks a rival could keep losing money. Original: `rivRun`.
    public static func holdOut(_ r: Rival, seed: Int) -> Int { Int(jsRound(6 + r.size * 8 + HashedRandom.first(String(r.id)) * 4)) }

    public static func staffCount(_ bd: Trade, _ r: Rival) -> Int { max(1, Int(jsRound(bd.standardStaff.reduce(0) { $0 + $1.count } * r.size))) }

    static func roundTo(_ v: Double, _ step: Double) -> Double { (v / step).rounded() * step }

    // MARK: Making rivals

    static func nextID(_ s: inout GameState) -> Int {
        let n = (s.rest["rivSeq"]?.int ?? 9_000_000) + 1
        s.rest["rivSeq"] = .number(Double(n))
        return n
    }

    /// Fill a market with its named rivals (the same every time for this game). Original: `rivalsOfCore`.
    static func ensure(_ s: inout GameState, key: String, trade bd: Trade, countryCode: String, data: GameData) {
        guard var mk = s.rest["mk"], !mk[key].isNull else { return }
        var m = mk[key]
        var riv = m["riv"].array
        let want = min(5, max(1, m["n"].int))
        guard riv.count < want || riv.count > want + 1 else { return }
        let country = data.countries[countryCode] ?? data.countries.countries[0]
        let taken = Set(riv.map { $0["name"].string } + s.companies.map { $0.name })
        var used = taken
        while riv.count < want {
            var h = HashedRandom("\(s.seed):rivals:\(key):\(riv.count)")
            var name = ""
            for g in 0..<40 {
                var r = DeterministicRandom(seed: Int(h.next() * 1_000_000_000) &+ g)
                name = CompanySetup.generateName(country: country, family: bd.family, &r)
                if !used.contains(name) { break }
            }
            used.insert(name)
            let owner = country.firstNames.isEmpty ? "Alex" : country.firstNames[Int(h.next() * Double(country.firstNames.count)) % country.firstNames.count]
                + " " + (country.lastNames.isEmpty ? "Smith" : country.lastNames[Int(h.next() * Double(country.lastNames.count)) % country.lastNames.count])
            let id = nextID(&s)
            let size = jsRound((0.45 + h.next() * 1.05) * 100) / 100
            riv.append(.object(["id": .number(Double(id)), "name": .string(name), "owner": .string(owner), "size": .number(size),
                                "rel": .number(jsRound(30 + h.next() * 25)), "listed": .bool(h.next() < 0.12), "ign": 0, "lock": 0, "meet": -99,
                                "pm16": .number(initialPrice(seed: s.seed, id: id)), "ig16": 1, "nx16": .number(Double(s.week + 4 + Int(h.next() * 14)))]))
        }
        if riv.count > want + 1 { riv.removeLast(riv.count - (want + 1)) }
        m["riv"] = .array(riv)
        mk[key] = m
        s.rest["mk"] = mk
    }

    /// Change one rival record in place.
    static func mutate(_ s: inout GameState, key: String, id: Int, _ body: (inout JSONValue) -> Void) {
        guard var mk = s.rest["mk"], !mk[key].isNull else { return }
        var m = mk[key]
        var riv = m["riv"].array
        guard let k = riv.firstIndex(where: { $0["id"].int == id }) else { return }
        body(&riv[k])
        m["riv"] = .array(riv)
        mk[key] = m
        s.rest["mk"] = mk
    }

    // MARK: Memory (world_around_you.js: rivals remember)

    static let temperaments = [("Proud", "takes things personally"), ("Calm", "thinks before acting"), ("Hot-headed", "hits back fast"),
                               ("Calculating", "waits for the right moment"), ("Old-school", "values a handshake"), ("Ambitious", "wants to be number one")]
    static let grudges: [(String, Double)] = [("Forgives quickly", 0.92), ("Holds a grudge", 0.97), ("Never forgets", 1)]

    public static func temperament(_ r: Rival) -> (name: String, text: String) { let t = temperaments[abs(String(r.id).hashValueStable) % temperaments.count]; return (t.0, t.1) }
    static func grudge(_ r: Rival) -> (String, Double) { grudges[abs((String(r.id) + "g").hashValueStable) % grudges.count] }

    /// A rival writes something down about you and thinks differently of you. Original: `remember`.
    static func remember(_ r: inout JSONValue, week: Int, text: String, change d: Double) {
        var mem = r["mem31"].array
        mem.insert(.object(["w": .number(Double(week)), "t": .string(text), "d": .number(d)]), at: 0)
        if mem.count > 20 { mem.removeLast(mem.count - 20) }
        r["mem31"] = .array(mem)
        let hot = ["Hot-headed", "Proud"].contains(temperament(read(r, week: week)).name) ? 1.3 : 1
        r["rel"] = .number(clamp((r["rel"].isNull ? 40 : r["rel"].double) + d * (d < 0 ? hot : 1), 0, 100))
        if r["n31"].isNull || r["n31"].double == 0 { r["n31"] = .number(Double(max(1, week))) }
    }

    public static func mood(_ r: Rival) -> (word: String, tone: String) {
        if !r.known { return ("Has not noticed you", "") }
        let x = r.relationship
        return x < 22 ? ("Bitter", "bad") : x < 36 ? ("Wary", "warn") : x < 50 ? ("Neutral", "") : x < 64 ? ("Respectful", "good") : ("Friendly", "good")
    }

    public static func relationshipWord(_ x: Double) -> String {
        x < 22 ? "Hostile" : x < 36 ? "Cool" : x < 50 ? "Neutral" : x < 64 ? "Cordial" : x < 80 ? "Friendly" : "Close"
    }

    public static func nextMove(_ r: Rival) -> String {
        let m = mood(r).word, t = temperament(r).name
        if !r.known { return "They do not know you yet. That changes when you take a real share of their customers, or cross them." }
        switch m {
        case "Bitter": return t == "Calculating" ? "Likely waiting for a weak moment: a bad review week or a staff crisis." : "Likely to hit back: a price cut, poaching your people, or a bid for your customers."
        case "Wary": return t == "Hot-headed" ? "Could start a price war over a small thing." : "Watching you closely. One more push and it turns personal."
        case "Respectful": return t == "Old-school" || t == "Calm" ? "Might suggest working together, or selling to you one day." : "Competes hard but fair."
        case "Friendly": return "Open to deals: shared suppliers, referrals, maybe a sale."
        default: return "Getting to know you. What you do next decides how this goes."
        }
    }

    // MARK: The weekly life of the rivals

    /// Original: `rivalWeek` (rivals_run_businesses), `cutsWeek`, `pwWeek` and the world-around-you memory.
    public static func weekly(_ s: inout GameState, data: GameData) {
        // Group the open companies by market
        var byMarket: [String: [Int]] = [:]
        for (i, c) in s.companies.enumerated() where c.status == .open && c.type != "hold" && c.type != "club" { byMarket[key(c), default: []].append(i) }
        for k in byMarket.keys.sorted() {
            guard let idx = byMarket[k], let first = idx.first, let bd = data.catalog[s.companies[first].type] else { continue }
            ensure(&s, key: k, trade: bd, countryCode: s.companies[first].countryCode, data: data)
            RivalGroups.assign(&s, key: k, type: s.companies[first].type, countryCode: s.companies[first].countryCode, data: data)
            if !noPrice.contains(bd.family) { behave(&s, key: k, idx: idx, bd: bd, data: data) }
            remember(&s, key: k, idx: idx, data: data)
        }
        for i in s.companies.indices { priceWarWeek(&s, i, data: data) }
        collusionWeek(&s, data: data)
        if GameCalendar.isMonthEnd(week: s.week) { monthly(&s) }
        RivalGroups.weekly(&s, data: data)
    }

    static func behave(_ s: inout GameState, key k: String, idx: [Int], bd: Trade, data: GameData) {
        guard var mk = s.rest["mk"], !mk[k].isNull else { return }
        var m = mk[k]
        var riv = m["riv"].array
        guard !riv.isEmpty else { return }
        let week = s.week
        let cos = idx.map { s.companies[$0] }
        let co0 = cos[0]
        let w = World(state: s, data: data)
        let cityName = data.countries.city(co0.cityID, preferring: co0.countryCode)?.city.name ?? "town"
        let newYear = week / 52 != (week - 1) / 52
        let infl = s.economy.inflation
        let util = co0.value("lastW")["util"].isNull ? 0.7 : co0.value("lastW")["util"].double
        let myP = Pricing.priceIndex(co0, w) / max(0.01, co0.num("ig", 1))
        var notes: [(String, String)] = []
        // Rivals that matched your cut carry it into their own prices.
        if !m["pil16"].isNull, m["pi"].double < m["pil16"].double - 0.02 {
            for j in riv.indices { riv[j]["pm16"] = .number(clamp(riv[j]["pm16"].double * m["pi"].double / m["pil16"].double, 0.7, 1.6)) }
        }
        for j in riv.indices {
            var r = riv[j]
            var h = HashedRandom("\(s.seed):rw:\(week):\(r["id"].int)")
            let name = r["name"].string
            if r["pm16"].isNull { r["pm16"] = .number(initialPrice(seed: s.seed, id: r["id"].int)) }
            if r["ig16"].isNull { r["ig16"] = 1 }
            if newYear {
                let holds = HashedRandom.first("\(s.seed):hold\(week / 52):\(r["id"].int)") < 0.15
                r["hold16"] = .bool(holds)
                if holds { notes.append(("\(name) is holding last year's prices in \(cityName).", "n")) }
            }
            if r["hold16"].bool { r["ig16"] = .number(r["ig16"].double * (1 + infl / 52)) }
            // Regular price reviews: small steps, up when busy, down when quiet or when you are much cheaper.
            if Double(week) >= r["nx16"].double {
                r["nx16"] = .number(Double(week + 8 + Int(h.next() * 15)))
                let dir = (-0.4 + h.next()) + (util > 0.9 ? 0.4 : 0) - (myP < effectivePrice(r, week: week) - 0.08 ? 0.5 : 0) - (r["size"].double < 0.7 ? 0.2 : 0)
                let step = (abs(dir) < 0.2 ? 0 : (dir > 0 ? 1.0 : -1.0)) * (0.02 + h.next() * 0.04)
                if step != 0 {
                    r["pm16"] = .number(clamp(jsRound(r["pm16"].double * (1 + step) * 1000) / 1000, 0.7, 1.6))
                    if abs(step) >= 0.04 { notes.append(("\(name) \(step > 0 ? "raised" : "cut") its prices about \(Int(jsRound(abs(step) * 100)))%.", step > 0 ? "n" : "bad")) }
                }
            }
            // Discounts where the trade does them
            if running(r["camp16"], week) == false { r["camp16"] = .null }
            let dm = PriceMoves.maxDiscount(co0.type)
            if dm > 0, r["camp16"].isNull, h.next() < 0.012 + (util < 0.6 ? 0.01 : 0) {
                let pct = min(dm, [10, 15, 20, 25][Int(h.next() * 4) % 4])
                let end = week + 1 + Int(h.next() * 3)
                r["camp16"] = .object(["pct": .number(Double(pct)), "end": .number(Double(end))])
                notes.append(("\(name) runs \(pct)% off for \(end - week) week\(end - week > 1 ? "s" : "").", "bad"))
            }
            // Marketing pushes
            if !r["mkt16"].isNull, Double(week) >= r["mkt16"].double { r["mkt16"] = .null; r["size"] = .number(jsRound(r["size"].double * 1.01 * 100) / 100) }
            if r["mkt16"].isNull, h.next() < 0.01 {
                r["mkt16"] = .number(Double(week + 4 + Int(h.next() * 7)))
                notes.append(("\(name) started a big marketing campaign.", "n"))
            }
            // Selling shares to grow
            if !r["listed"].bool, !r["sold16"].bool, r["size"].double > 1.1, h.next() < 0.0015 {
                r["sold16"] = true
                r["size"] = .number(jsRound(r["size"].double * 1.15 * 100) / 100)
                s.news("\(name) sells a stake to investors and plans to grow.")
                notes.append(("\(name) raised money by selling shares. Expect them to expand.", "n"))
            }
            // A stray price war victim's memory fades is handled in `remember`.
            riv[j] = r
        }
        // Opening next to you
        var hm = HashedRandom("\(s.seed):next:\(week):\(k)")
        let busy = cos.contains { $0.value("lastW")["util"].double > 0.85 || Reviews.rating($0) > 4 }
        if hm.next() < 0.0025 * (m["aggr"].isNull ? 1 : m["aggr"].double), busy, let bigK = riv.indices.max(by: { riv[$0]["size"].double < riv[$1]["size"].double }) {
            let tgt = cos[Int(hm.next() * Double(cos.count)) % cos.count]
            riv[bigK]["size"] = .number(jsRound(riv[bigK]["size"].double * 1.12 * 100) / 100)
            m["n"] = .number(m["n"].double + 1)
            if let ti = s.companyIndex(tgt.id) { PriceMoves.addModifier(&s, ti, key: "dem", multiplier: 0.92, weeks: 26) }
            let bn = riv[bigK]["name"].string
            s.addMessage(from: "Market", title: "\(bn) opens next to \(tgt.name)",
                         body: "\(bn) has opened a new site a few doors from \(tgt.name) in \(cityName). Expect fewer walk-ins for a while. You can answer with prices, marketing or a discount under Price moves.",
                         companyID: tgt.id, tone: "bad")
        }
        // The market price index is what the rivals actually charge, weighted by size.
        let wts = riv.map { $0["size"].double * ($0["mkt16"].isNull ? 1 : 1.1) }
        let tot = wts.reduce(0, +)
        if tot > 0 {
            let pi = zip(riv, wts).reduce(0) { $0 + effectivePrice($1.0, week: week) * $1.1 } / tot
            m["pi"] = .number(clamp(m["pi"].double + (pi - m["pi"].double) * 0.5, 0.7, 1.4))
            m["pil16"] = m["pi"]
        }
        let push = riv.contains { !$0["mkt16"].isNull }
        m["str16"] = .number(push ? 0.15 : 0)
        m["riv"] = .array(riv)
        mk[k] = m
        s.rest["mk"] = mk
        for n in notes { s.note(n.0, tone: n.1, companyID: co0.id) }
        rivalCalls(&s, cos: idx, market: m, riv: riv, bd: bd, data: data)
    }

    // MARK: Calls from rival owners (price matching, price fixing)

    /// A rival owner calls when your price has fallen clearly under the market's ("match") or now and then to ask what is up ("chat").
    /// Only a real cut makes them call. The illegal answers set the company's collusion flag: the market price index rises, and each week
    /// there is a small chance the authority finds out (`collusionWeek`). Original: `rivalCall` (economy_markets.js), 'rivalCall.before/after'.
    static func rivalCalls(_ s: inout GameState, cos idx: [Int], market m: JSONValue, riv: [JSONValue], bd: Trade, data: GameData) {
        guard !riv.isEmpty else { return }
        let w = World(state: s, data: data)
        let aggr = m["aggr"].isNull ? 1 : m["aggr"].double
        var h = HashedRandom("\(s.seed):rcall:\(s.week):\(idx.first ?? 0)")
        for i in idx where s.companies[i].status == .open {
            let co = s.companies[i]
            let p = Pricing.priceIndex(co, w) / max(0.01, co.num("ig", 1))
            let match = p < m["pi"].double - 0.035 && h.next() < 0.12 * aggr
            let chat = !match && h.next() < 0.01 * aggr / Double(max(1, idx.count))
            guard match || chat else { continue }
            let cut = PriceMoves.recentCut(co, week: s.week, balance: data.balance)
            if match && cut < 0.06 && co.value("flags")["pw"].isNull { continue }
            call(&s, i, kind: match ? "match" : "chat", cut: cut, rival: riv[Int(h.next() * Double(riv.count)) % riv.count], bd: bd)
        }
    }

    static func call(_ s: inout GameState, _ i: Int, kind: String, cut: Double, rival r: JSONValue, bd: Trade) {
        let co = s.companies[i]
        var flags = co.value("flags")
        if !flags["lastCall"].isNull, s.week - flags["lastCall"].int < 6 { return }
        flags["lastCall"] = .number(Double(s.week)); s.companies[i].set("flags", flags)
        let rname = "\(r["owner"].string.isEmpty ? "A rival" : r["owner"].string) (owner, rival \(bd.name.lowercased()))"
        let title: String, body: String, opts: [JSONValue]
        if kind == "match" {
            title = "\(rname) calls about your prices"
            body = "\"You cut your prices \(Int(jsRound(cut * 100)))% in a few weeks and our customers noticed. We have matched you. If you keep going down, we both bleed.\""
            opts = [.option("Hold your prices", "Stay aggressive."), .option("Raise prices back a step", "Cool things down.", effects: ["pr": 1]),
                    .option("Propose to \"coordinate\" prices", "Illegal. If caught: fine of 8% of turnover.", effects: ["coord": 1])]
        } else {
            title = "\(rname) calls to ask what's up"
            body = "\"Heard you are expanding. Just checking where you stand on prices and customers.\""
            opts = [.option("Be friendly, say nothing"), .option("Warn them off", "They may react aggressively.", effects: ["dem": .array([1, 1]), "warn": true]),
                    .option("Hint at a price understanding", "Illegal collusion.", effects: ["coord": true])]
        }
        let level = co.value("auth")["lvl"].int
        if co.managerID != nil, let mgr = s.people[co.managerID!], level >= 1 {
            // A manager with authority takes the call and holds the line (the original's manager never agrees to collude).
            s.addMessage(from: co.name, title: "Rival call handled by \(mgr.name)", body: title, companyID: co.id)
            return
        }
        let id = s.addMessage(kind: "decision", from: rname, title: title, body: body, companyID: co.id, tone: "n", status: "open", options: opts, expiresWeek: s.week + 2)
        if let k = s.inbox.firstIndex(where: { $0.id == id }) { s.inbox[k].set("ev", "rival_call"); s.inbox[k].set("cat", "none") }
    }

    /// The authority finds out about a price understanding: a fine of 8% of turnover, reputation down. Original: the 'coll' check in `weekCore`.
    static func collusionWeek(_ s: inout GameState, data: GameData) {
        for i in s.companies.indices where s.companies[i].status == .open || s.companies[i].status == .closed {
            guard s.companies[i].value("flags")["coll"].double != 0, s.random.chance(0.02) else { continue }
            let co = s.companies[i]
            let cur = World(state: s, data: data).currency(co)
            let fine = jsRound(max(cur.scaledPrice(50000), (MarketMap.annualRevenue(co) + co.lastWeekRevenue * 20) * 0.08))
            var f = co.value("flags"); f["coll"] = 0; s.companies[i].set("flags", f)
            Payments.companyPays(&s, companyID: co.id, amount: fine, category: "fine", label: "Competition fine")
            if let j = s.companyIndex(co.id) { s.companies[j].reputation = clamp(s.companies[j].reputation - 6, 0, 100) }
            s.addMessage(from: "Competition authority", title: "Price collusion uncovered at \(co.name)",
                         body: "The authority fined \(co.name) \(cur.display(fine)). Reputation took a hit.", companyID: co.id, tone: "bad")
            s.news("Competition authority fines a local company for price fixing.", tone: "bad")
        }
    }

    /// What rivals notice and remember. Original: `rivalWeek` (world_around_you.js).
    static func remember(_ s: inout GameState, key k: String, idx: [Int], data: GameData) {
        guard let riv = s.rest["mk"]?[k]["riv"].array, !riv.isEmpty else { return }
        let w = World(state: s, data: data)
        for r in riv {
            let id = r["id"].int
            var h = HashedRandom("\(s.seed):mem:\(s.week):\(id)")
            let gr = grudge(read(r, week: s.week)).1
            mutate(&s, key: k, id: id) { rr in
                var mem = rr["mem31"].array
                if !mem.isEmpty, gr < 1, h.next() < 1 - gr { mem.removeLast(); rr["mem31"] = .array(mem) }
            }
            for i in idx {
                let co = s.companies[i]
                let cityName = data.countries.city(co.cityID, preferring: co.countryCode)?.city.name ?? "town"
                let known = !(s.rest["mk"]?[k]["riv"].array.first { $0["id"].int == id }?["n31"].isNull ?? true)
                if !known, let bd = w.trade(co), MarketMap.noticed(s, co, bd, w) {
                    let wk = s.week; mutate(&s, key: k, id: id) { remember(&$0, week: wk, text: "\(co.name) is taking customers from them in \(cityName).", change: -2) }
                }
                if known, co.priceLevel <= -1, co.value("flags")["pw"].isNull, s.week % 13 == 0 {
                    let wk = s.week; mutate(&s, key: k, id: id) { remember(&$0, week: wk, text: "You kept \(co.name)'s prices below theirs for a month.", change: -1) }
                }
                if known, co.int("rvN") >= 30, Reviews.rating(co) >= 4.5, !(s.rest["mk"]?[k]["riv"].array.first { $0["id"].int == id }?["rv31"].bool ?? true) {
                    let wk = s.week; mutate(&s, key: k, id: id) { rr in rr["rv31"] = true; remember(&rr, week: wk, text: "\(co.name) beat them on reviews: \(String(format: "%.1f", Reviews.rating(co))) stars.", change: -2) }
                }
            }
        }
    }

    /// Once a month rivals' relationships drift to neutral and some come up for sale. Original: `rivalMonth`.
    static func monthly(_ s: inout GameState) {
        guard var mk = s.rest["mk"] else { return }
        for key in mk.object.keys.sorted() {
            var m = mk[key]
            var riv = m["riv"].array
            guard !riv.isEmpty else { continue }
            for j in riv.indices {
                var h = HashedRandom("\(s.seed):rm:\(s.week):\(riv[j]["id"].int)")
                riv[j]["rel"] = .number(riv[j]["rel"].double + (45 - riv[j]["rel"].double) * 0.03)
                if !riv[j]["listed"].bool, h.next() < 0.03 { riv[j]["listed"] = true } else if riv[j]["listed"].bool, h.next() < 0.12 { riv[j]["listed"] = false }
            }
            m["riv"] = .array(riv)
            mk[key] = m
        }
        s.rest["mk"] = mk
    }

    // MARK: Price war

    public struct WarEstimate {
        public var holdOutWeeks: Int, yourWeeks: Int, toYou: Double, odds: Double, cost: Double, yourShare: Double
        public var biggestOther: Rival?
    }

    /// What a price war looks like before it starts. Original: `warCalc`.
    public static func warEstimate(_ s: GameState, _ co: Company, rival r: Rival, weeks wk: Int, data: GameData) -> WarEstimate? {
        let w = World(state: s, data: data)
        guard let bd = w.trade(co) else { return nil }
        let rs = rivals(s, for: co)
        let run = holdOut(r, seed: s.seed)
        let weekRev = co.value("lastW")["rev"].double
        let lossW = Double(jsRound((weekRev > 0 ? weekRev : Pricing.ticket(co, bd, w) * 10) * 0.3))
        let myRun = lossW > 0 ? Int((max(0, co.cash) / lossW).rounded(.down)) : 99
        let others = rs.filter { $0.id != r.id }
        let mine = co.size, oth = others.reduce(0) { $0 + $1.size }
        let toYou = clamp(mine * 1.6 / (mine * 1.6 + oth), 0.15, 0.95)
        var odds = clamp(0.25 + (co.cash > lossW * Double(run) * 1.3 ? 0.35 : co.cash > lossW * Double(run) * 0.7 ? 0.15 : 0) + (1.2 - r.size) * 0.2, 0.05, 0.9)
        if wk < run { odds *= clamp(Double(wk) / Double(run), 0.2, 1) * 0.7 }
        return WarEstimate(holdOutWeeks: run, yourWeeks: myRun, toYou: toYou, odds: odds, cost: lossW * Double(wk), yourShare: mine / (mine + oth + r.size),
                           biggestOther: others.max { $0.size < $1.size })
    }

    /// Cut prices to the floor for some weeks to push one rival out. Original: `ACT.pwgo`.
    @discardableResult
    public static func startPriceWar(_ s: inout GameState, companyID: Int, rivalID: Int, weeks: Int, data: GameData) -> String? {
        guard let i = s.companyIndex(companyID), s.companies[i].status == .open else { return "Only an open company can start a price war." }
        guard s.companies[i].value("flags")["pw"].isNull else { return "A price war is already running." }
        let co = s.companies[i]
        guard let r = rivals(s, for: co).first(where: { $0.id == rivalID }), let est = warEstimate(s, co, rival: r, weeks: weeks, data: data) else { return "That rival is gone." }
        var f = co.value("flags")
        f["pw"] = .object(["rid": .number(Double(rivalID)), "end": .number(Double(s.week + weeks)), "prev": .number(co.priceLevel), "odds": .number(est.odds),
                           "share": .number(est.yourShare), "loss": 0, "to": .number(est.toYou)])
        s.companies[i].set("flags", f)
        s.companies[i].priceLevel = -3
        let wk = s.week; mutate(&s, key: key(co), id: rivalID) { remember(&$0, week: wk, text: "You started a price war with \(co.name).", change: -8) }
        return nil
    }

    public static func endPriceWar(_ s: inout GameState, companyID: Int) {
        guard let i = s.companyIndex(companyID), !s.companies[i].value("flags")["pw"].isNull else { return }
        var f = s.companies[i].value("flags")
        s.companies[i].priceLevel = f["pw"]["prev"].double
        f["pw"] = .null
        s.companies[i].set("flags", f)
    }

    /// Each week of a war: the price stays at the floor, the loss adds up, and at the end the rival folds or survives. Original: `pwWeek`.
    static func priceWarWeek(_ s: inout GameState, _ i: Int, data: GameData) {
        let co = s.companies[i]
        let pw = co.value("flags")["pw"]
        guard !pw.isNull else { return }
        if co.status != .open { var f = co.value("flags"); f["pw"] = .null; s.companies[i].set("flags", f); return }
        s.companies[i].priceLevel = -3
        var f = co.value("flags")
        f["pw"]["loss"] = .number(pw["loss"].double + Double(jsRound(co.value("lastW")["rev"].double * 0.3)))
        s.companies[i].set("flags", f)
        guard s.week >= pw["end"].int else { return }
        let k = key(co)
        let r = rivals(s, key: k).first { $0.id == pw["rid"].int }
        endPriceWar(&s, companyID: co.id)
        var h = HashedRandom("\(s.seed):pw:\(s.week):\(co.id)")
        if let r = r, h.next() < pw["odds"].double {
            removeRival(&s, key: k, id: r.id)
            let to = pw["to"].isNull ? 0.6 : pw["to"].double
            if let j = s.companyIndex(co.id) {
                s.companies[j].awareness = min(100, s.companies[j].awareness + 6 + 10 * to)
                if let bd = data.catalog[s.companies[j].type] { s.companies[j].size = min(bd.maxSize, s.companies[j].size + r.size * to * 0.25) }
            }
            // The customers spread out: what does not come to you goes to the rivals still standing.
            if var mk = s.rest["mk"], !mk[k].isNull {
                var riv = mk[k]["riv"].array
                let oth = riv.reduce(0) { $0 + $1["size"].double }
                if oth > 0 { for j in riv.indices { riv[j]["size"] = .number(jsRound((riv[j]["size"].double + r.size * (1 - to) * riv[j]["size"].double / oth) * 100) / 100) } }
                mk[k]["riv"] = .array(riv); s.rest["mk"] = mk
                if to < 0.5, let top = riv.max(by: { $0["size"].double < $1["size"].double }) {
                    s.note("Most of \(r.name)'s customers went to \(top["name"].string), not to you.", tone: "bad", companyID: co.id)
                }
            }
            s.note("\(r.name) could not survive the price war and closed. Its customers are up for grabs.", tone: "good", companyID: co.id)
            s.news("\(r.name) closes after a price war.")
        } else {
            s.note("\(r?.name ?? "The rival") survived the price war.", tone: "bad", companyID: co.id)
        }
        if pw["share"].double >= 0.35, h.next() < 0.3 {
            let cur = World(state: s, data: data).currency(co)
            let fine = Double(jsRound(max(cur.scaledPrice(50000), (co.books.year["rev"] ?? 0) * 0.05)))
            Payments.companyPays(&s, companyID: co.id, amount: fine, category: "fine", label: "Competition fine")
            if let j = s.companyIndex(co.id) { s.companies[j].reputation = clamp(s.companies[j].reputation - 5, 0, 100) }
            s.addMessage(from: "Competition authority", title: "Abuse of a dominant position at \(co.name)",
                         body: "The competition authority fined \(co.name) \(cur.display(fine)) for pricing to push out a rival.", companyID: co.id, tone: "bad")
        }
    }

    static func removeRival(_ s: inout GameState, key k: String, id: Int) {
        guard var mk = s.rest["mk"], !mk[k].isNull else { return }
        mk[k]["riv"] = .array(mk[k]["riv"].array.filter { $0["id"].int != id })
        mk[k]["n"] = .number(max(1, mk[k]["n"].double - 1))
        s.rest["mk"] = mk
    }

    // MARK: Talking to and buying rivals

    public enum MeetResult: Equatable { case ok, wait, cash, missing }

    /// Lunch with the owner. Original: `meetRival`.
    public static func meet(_ s: inout GameState, companyID: Int, rivalID: Int, data: GameData) -> MeetResult {
        guard let co = s.company(companyID), let r = rivals(s, for: co).first(where: { $0.id == rivalID }) else { return .missing }
        let raw = s.rest["mk"]?[key(co)]["riv"].array.first { $0["id"].int == rivalID }?["meet"].double ?? -99
        if Double(s.week) - raw < 4 { return .wait }
        let cost = World(state: s, data: data).currency(co).scaledPrice(4000)
        if s.cash < cost { return .cash }
        Payments.playerPays(&s, cost, label: "Lunch and a meeting with \(r.owner)", companyID: companyID)
        var h = HashedRandom("\(s.seed):lunch:\(s.week):\(rivalID)")
        let gain = 4 + (h.next() * 6).rounded(.down)
        let wk = s.week
        mutate(&s, key: key(co), id: rivalID) { rr in
            rr["meet"] = .number(Double(wk))
            rr["rel"] = .number(min(100, rr["rel"].double + gain))
            remember(&rr, week: wk, text: "Had lunch with you.", change: 4)
        }
        return .ok
    }

    public enum OfferReply: Equatable {
        case ignore(String), accept(price: Double, message: String), counter(price: Double, message: String), reject(String)
    }

    /// Offer to buy a rival at a multiple of its value. Original: `proposeBuy` with the group's terms.
    public static func proposeBuy(_ s: inout GameState, companyID: Int, rivalID: Int, multiple mult0: Double, data: GameData) -> OfferReply? {
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return nil }
        let k = key(co)
        guard let r = rivals(s, key: k).first(where: { $0.id == rivalID }) else { return nil }
        let w = World(state: s, data: data)
        let raw = s.rest["mk"]?[k]["riv"].array.first { $0["id"].int == rivalID } ?? .null
        var mult = mult0, listed = r.forSale
        var scale = 1.0
        if let g = RivalGroups.group(s, id: r.groupID) {
            if g.inTrouble { listed = true; mult *= 1.45; scale = 1.45 } else { mult /= 1.15 }
        }
        if Double(s.week) < raw["lock"].double { return .ignore("\(r.owner) does not answer your calls.") }
        let V = value(bd, r, w, co)
        var price = roundTo(V * mult, 1000)
        var h = HashedRandom("\(s.seed):offer:\(s.week):\(rivalID):\(Int(mult0 * 100))")
        let cur = w.currency(co)
        if !listed, r.relationship < 45, h.next() < 0.35 {
            mutate(&s, key: k, id: rivalID) { $0["rel"] = .number(max(0, $0["rel"].double - 2)) }
            return .ignore("\(r.owner) never replies to your offer.")
        }
        let need = (listed ? 0.95 : 1.55) * (1.1 - r.relationship / 400)
        if mult >= need {
            if scale != 1 { price = roundTo(price / scale, 1000) }
            return .accept(price: price, message: "\(r.owner) accepts: \"\(listed ? "Good timing. I was ready to step back." : "Not what I planned, but that price is hard to refuse.")\"")
        }
        if mult >= need * 0.85 {
            let p2 = roundTo(V * need / scale, 1000)
            mutate(&s, key: k, id: rivalID) { $0["rel"] = .number(max(0, $0["rel"].double - 1)) }
            return .counter(price: p2, message: "\(r.owner) counters: \"I would sell at \(cur.display(p2)). Not a krone less.\"")
        }
        var lockUntil: Int?
        let wk = s.week
        mutate(&s, key: k, id: rivalID) { rr in
            rr["ign"] = .number(rr["ign"].double + 1)
            rr["rel"] = .number(max(0, rr["rel"].double - (listed ? 3 : 6)))
            if rr["ign"].double >= 3 { rr["lock"] = .number(Double(wk + 26)); lockUntil = wk + 26 }
        }
        if lockUntil != nil { return .reject("\(r.owner) is fed up with lowball offers and ends contact for now.") }
        return .reject("\(r.owner) turns you down: \"\(listed ? "That is well below what this business is worth." : "It is not for sale.")\"")
    }
}
