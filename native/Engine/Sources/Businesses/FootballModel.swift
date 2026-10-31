import Foundation
import GameCore
import Countries
import Finance

/// Football: the top league of each country that has one. You can buy a club (if its owners will sell) or found one in the second
/// tier; the manager picks the players, you set the wage budget, ticket prices and sponsors. Original: engine/world/football.js and
/// the round-24 steps in features/world/football_clubs.js (club debt, transfer windows, bids for your players).
///
/// Saved like the original (a legacy save carries on): `rest.clubs[country]` the clubs, `rest.lg[country]` the league, and for an
/// owned club `fm` {club id, div 1|2, wage share of revenue, tix -1..1, coach, asst, sp (sponsors), offers, last (form), hist (seasons),
/// titles, s (squad strength), val, R, sq, xw, book, amort, tin, tout, fill}.
public enum FootballModel {
    /// Accounting units per US dollar (the original's `USD`).
    public static let usd = 10.5
    static let suffixes = ["United", "FC", "Athletic", "City", "Sporting", "Rovers", "Town", "Wanderers", "Albion", "Rangers"]
    static let brandWords = ["Nordic", "Fjord", "Urban", "Bright", "Prime", "Hearth", "Peak", "Harbor", "Golden", "Fresh", "Anchor", "Summit", "Birch", "Clear", "Northern", "Blue", "Maple", "Ember"]
    static let sponsorIndustries = ["Bank", "Telecom", "Energy", "Airlines", "Brewery", "Insurance", "Motors", "Sportswear", "Foods", "Betting", "Cola", "Logistics"]
    static let bidderSuffixes = ["FC", "United", "City", "Athletic", "SK"]

    /// Sponsor slots in the order of the original: key, title, share of yearly revenue.
    public static let slots: [(key: String, title: String, share: Double)] = [
        ("shirt", "Shirt sponsor", 0.08), ("stad", "Stadium naming rights", 0.06), ("kit", "Kit supplier", 0.04),
        ("p1", "Official partner", 0.02), ("p2", "Official partner", 0.02),
    ]
    /// Transfer tiers: name, fee as a share of yearly revenue, squad strength added, extra wages as a share of revenue.
    public static let tiers: [(name: String, fee: Double, strength: Double, wages: Double)] = [
        ("Squad player", 0.04, 1.2, 0.006), ("First-team starter", 0.1, 3, 0.015), ("Star signing", 0.25, 7, 0.035),
    ]

    public struct LeagueInfo: Equatable { public var name: String; public var clubs: Int; public var low: Double; public var high: Double }

    public static func leagueInfo(_ c: Country) -> LeagueInfo? {
        let f = c.pack["football"]
        guard !f.isNull, f.array.count >= 3 else { return nil }
        return LeagueInfo(name: f[0].string, clubs: f[1].int, low: f[2][0].double, high: f[2][1].double)
    }

    /// Countries that have a league, in menu order.
    public static func countriesWithLeague(_ data: GameData) -> [Country] { data.countries.countries.filter { leagueInfo($0) != nil } }

    // MARK: Hashes the original uses

    /// Original: `fbHash`.
    static func hash(_ text: String) -> Int32 {
        var h: Int32 = 7
        for u in text.utf16 { h = h &* 31 &+ Int32(u) }
        return h
    }
    /// JavaScript `x | 0` for a double.
    static func toInt32(_ x: Double) -> Int32 {
        guard x.isFinite else { return 0 }
        let t = x.rounded(.towardZero)
        var m = t.truncatingRemainder(dividingBy: 4294967296.0)
        if m < 0 { m += 4294967296.0 }
        return Int32(truncatingIfNeeded: UInt32(m))
    }
    static func round100k(_ x: Double) -> Double { jsRound(x / 100000) * 100000 }

    // MARK: Clubs of a league

    /// The clubs of a country's top league, always the same for the same game seed. Original: `clubsOf` (creation part).
    public static func generateClubs(country c: Country, seed: Int) -> [JSONValue] {
        guard let L = leagueInfo(c) else { return [] }
        var r = DeterministicRandom(state: toInt32(Double(hash("club" + c.code)) * 2654435761.0 + Double(seed == 0 ? 1 : seed)))
        let n = L.clubs, lo = L.low * usd * 1e6, hi = L.high * usd * 1e6
        var out: [JSONValue] = []
        var used = Set<String>()
        let core = c.coreCities
        let cityNames = core.map { $0.name }
        for i in 0..<n {
            var name = ""
            var g = 0
            repeat {
                let first: String
                if i < cityNames.count && g < 1 { first = cityNames[i] } else { first = cleanName(r.pick(c.lastNames)) }
                name = first + " " + r.pick(suffixes)
                g += 1
            } while used.contains(name) && g < 20
            if used.contains(name) { name = r.pick(brandWords) + " " + name }
            used.insert(name)
            let val = round100k(lo * pow(hi / lo, pow(Double(n - 1 - i) / Double(max(1, n - 1)), 1.6)))
            let fixed = Double(i) < max(2, jsRound(Double(n) / 6)) && val > 2000 * usd * 1e6
            out.append(.object(["id": .string("\(c.code):\(i)"), "name": .string(name), "country": .string(c.code), "city": .string(core[i % core.count].id),
                                "rank0": .number(Double(i)), "val": .number(val), "owner": "ai", "fixed": .bool(fixed), "listed": false, "rel": 40, "ign": 0, "lock": 0]))
        }
        return out
    }

    /// Letters, accents and spaces only. Original: `.replace(/[^A-Za-zÀ-ž ]/g, '')`.
    static func cleanName(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { (0x41...0x5A).contains($0.value) || (0x61...0x7A).contains($0.value) || (0xC0...0x17E).contains($0.value) || $0.value == 0x20 }))
    }

    static func clubs(_ s: GameState, _ cc: String) -> [JSONValue] { s.rest["clubs"]?[cc].array ?? [] }

    /// The clubs of a country, made on first use and then kept in the save. Original: `clubsOf`.
    @discardableResult
    public static func ensureClubs(_ s: inout GameState, _ country: Country) -> [JSONValue] {
        var all = s.rest["clubs"] ?? .object([:])
        if !all[country.code].isNull { return all[country.code].array }
        let list = generateClubs(country: country, seed: s.seed)
        all[country.code] = .array(list)
        s.rest["clubs"] = all
        return list
    }

    static func setClub(_ s: inout GameState, _ cc: String, id: String, _ f: (inout JSONValue) -> Void) {
        var all = s.rest["clubs"] ?? .object([:])
        var list = all[cc].array
        guard let k = list.firstIndex(where: { $0["id"].string == id }) else { return }
        f(&list[k])
        all[cc] = .array(list)
        s.rest["clubs"] = all
    }

    static func findClub(_ s: GameState, id: String) -> JSONValue? {
        let cc = String(id.split(separator: ":").first ?? "")
        return clubs(s, cc).first { $0["id"].string == id }
    }

    static func clubBase(rank0: Double, n: Int) -> Double { 28 + 57 * (Double(n - 1) - rank0) / Double(max(1, n - 1)) }

    // MARK: League

    struct Row { var id: String; var s: Double; var pts: Int; var gp: Int; var hg: Int }
    struct Result { var r: String; var home: Bool; var opp: String }
    struct League {
        var season: Int, w0: Int
        var t: [Row]
        var res: [String: Result]

        init(season: Int, w0: Int, clubs: [JSONValue]) {
            self.season = season; self.w0 = w0; res = [:]
            t = clubs.map { Row(id: $0["id"].string, s: FootballModel.clubBase(rank0: $0["rank0"].double, n: clubs.count), pts: 0, gp: 0, hg: 0) }
        }
        init(json j: JSONValue) {
            season = j["season"].int; w0 = j["w0"].int
            t = j["t"].array.map { Row(id: $0["id"].string, s: $0["s"].double, pts: $0["pts"].int, gp: $0["gp"].int, hg: $0["hg"].int) }
            res = [:]
            for (k, v) in j["res"].object { res[k] = Result(r: v["r"].string, home: v["home"].bool, opp: v["opp"].string) }
        }
        var json: JSONValue {
            var r: [String: JSONValue] = [:]
            for (k, v) in res { r[k] = .object(["r": .string(v.r), "home": .bool(v.home), "opp": .string(v.opp)]) }
            return .object(["season": .number(Double(season)), "w0": .number(Double(w0)),
                            "t": .array(t.map { .object(["id": .string($0.id), "s": .number($0.s), "pts": .number(Double($0.pts)), "gp": .number(Double($0.gp)), "hg": .number(Double($0.hg))]) }),
                            "res": .object(r), "last": .object([:])])
        }
        /// Table order: points, then strength. Original: `tableRank`.
        var sorted: [Row] {
            t.enumerated().sorted { a, b in a.element.pts != b.element.pts ? a.element.pts > b.element.pts : (a.element.s != b.element.s ? a.element.s > b.element.s : a.offset < b.offset) }.map { $0.element }
        }
        func rank(of id: String) -> Int { (sorted.firstIndex { $0.id == id } ?? -1) + 1 }
        var matchWeeks: Int { min(2 * (t.count - 1), 40) }
    }

    static func league(_ s: inout GameState, _ country: Country) -> League {
        var all = s.rest["lg"] ?? .object([:])
        if !all[country.code].isNull { return League(json: all[country.code]) }
        let lg = League(season: 1, w0: s.week, clubs: ensureClubs(&s, country))
        all[country.code] = lg.json
        s.rest["lg"] = all
        return lg
    }

    static func saveLeague(_ s: inout GameState, _ cc: String, _ lg: League) {
        var all = s.rest["lg"] ?? .object([:])
        all[cc] = lg.json
        s.rest["lg"] = all
    }

    static func readLeague(_ s: GameState, _ cc: String) -> League? {
        guard let j = s.rest["lg"]?[cc], !j.isNull else { return nil }
        return League(json: j)
    }

    static func sig(_ x: Double) -> Double { 1 / (1 + exp(-x)) }

    /// Open clubs of the player in a country.
    static func ownedClubs(_ s: GameState, country cc: String? = nil) -> [Int] {
        s.companies.indices.filter { s.companies[$0].type == "club" && s.companies[$0].status == .open && !s.companies[$0].value("fm").isNull && (cc == nil || s.companies[$0].countryCode == cc!) }
    }

    /// Every league with a club of yours plays a round. Original: `clubLeaguesWeek`, `leagueStep`.
    public static func leaguesWeek(_ s: inout GameState, data: GameData) {
        var done = Set<String>()
        for i in ownedClubs(s) {
            let cc = s.companies[i].countryCode
            if done.contains(cc) { continue }
            done.insert(cc)
            if let c = data.countries[cc] { leagueStep(&s, c, data: data) }
        }
    }

    static func leagueStep(_ s: inout GameState, _ country: Country, data: GameData) {
        var lg = league(&s, country)
        let own = ownedClubs(s, country: country.code)
        for i in own {
            if let k = lg.t.firstIndex(where: { $0.id == s.companies[i].value("fm")["club"].string }) {
                let st = strength(s, i)
                lg.t[k].s = st
                var fm = s.companies[i].value("fm"); fm["s"] = .number(st); s.companies[i].set("fm", fm)
            }
        }
        let sw = s.week - lg.w0
        let M = lg.matchWeeks
        lg.res = [:]
        if sw >= 6 && sw < 6 + M {
            let order = s.random.shuffled(Array(lg.t.indices))
            var k = 0
            while k + 1 < order.count {
                let ia = order[k], ib = order[k + 1]
                k += 2
                func div(_ r: Row) -> Int { own.first { s.companies[$0].value("fm")["club"].string == r.id }.map { s.companies[$0].value("fm")["div"].int } ?? 1 }
                let sa = lg.t[ia].s - (div(lg.t[ia]) == 2 ? 10 : 0), sb = lg.t[ib].s - (div(lg.t[ib]) == 2 ? 10 : 0)
                let e = (sa - sb) / 22 + 0.22
                let pw = sig(e), pd = 0.26 * (1 - abs(pw - 0.5))
                let x = s.random.range(0, 1)
                let ra: String = x < pd ? "D" : (x < pd + (1 - pd) * pw ? "W" : "L")
                let rb = ra == "W" ? "L" : ra == "L" ? "W" : "D"
                lg.t[ia].gp += 1; lg.t[ib].gp += 1
                lg.t[ia].pts += ra == "W" ? 3 : ra == "D" ? 1 : 0
                lg.t[ib].pts += rb == "W" ? 3 : rb == "D" ? 1 : 0
                let ah = lg.t[ia].hg < lg.t[ib].hg || (lg.t[ia].hg == lg.t[ib].hg && s.random.chance(0.5))
                if ah { lg.t[ia].hg += 1 } else { lg.t[ib].hg += 1 }
                lg.res[lg.t[ia].id] = Result(r: ra, home: ah, opp: lg.t[ib].id)
                lg.res[lg.t[ib].id] = Result(r: rb, home: !ah, opp: lg.t[ia].id)
            }
        }
        if sw >= 51 { seasonEnd(&s, &lg, country, own: own) }
        saveLeague(&s, country.code, lg)
    }

    /// The strength of the player's team: the club's base, wages, the manager, form and signings. Original: `ownStrength`.
    static func strength(_ s: GameState, _ i: Int) -> Double {
        let fm = s.companies[i].value("fm")
        let cc = s.companies[i].countryCode
        let n = readLeague(s, cc)?.t.count ?? 1
        let club = findClub(s, id: fm["club"].string)
        var v = clubBase(rank0: club?["rank0"].double ?? 0, n: n) + (fm["wage"].double - 0.62) * 70 + ((fm["coach"].isNull ? 35 : fm["coach"]["skill"].double) - 60) * 0.35
        v -= fm["asst"].isNull ? 3 : 0
        v += fm["form"].double + fm["sq"].double
        if fm["div"].int == 2 { v = max(v, 40) }
        return clamp(v, 8, 98)
    }

    static func seasonEnd(_ s: inout GameState, _ lg: inout League, _ country: Country, own: [Int]) {
        let N = lg.t.count
        let sorted = lg.sorted
        let L = leagueInfo(country)
        for i in own {
            var fm = s.companies[i].value("fm")
            let id = s.companies[i].id
            let cid = fm["club"].string
            guard let club = findClub(s, id: cid) else { continue }
            let rank = (sorted.firstIndex { $0.id == cid } ?? -1) + 1
            let exp = Int(club["rank0"].double) + 1
            let div = fm["div"].int
            let R = clubRevenue(clubValue: club["val"].double, div: div)
            let prize = R * 0.04 * Double(N - rank) / Double(max(1, N - 1))
            Payments.companyReceives(&s, companyID: id, amount: prize, category: "rev", label: "League prize money")
            var hist = fm["hist"].array
            hist.insert(.object(["season": .number(Double(lg.season)), "rank": .number(Double(rank)), "div": .number(Double(div)), "pts": .number(Double(lg.t.first { $0.id == cid }?.pts ?? 0))]), at: 0)
            if hist.count > 12 { hist.removeLast() }
            fm["hist"] = .array(hist)
            if rank == 1 && div == 1 {
                fm["titles"] = .number(fm["titles"].double + 1)
                s.companies[i].reputation = min(100, s.companies[i].reputation + 6)
                s.note("\(s.companies[i].name) win the \(L?.name ?? "league")!", tone: "good", companyID: id)
            }
            var msg = "\(s.companies[i].name) finish \(rank) of \(N)."
            if div == 1 && rank > N - 3 {
                fm["div"] = 2
                msg += " They are relegated."
                var sp = fm["sp"]
                for (k, v) in sp.object { var x = v; x["wk"] = .number(v["wk"].double * 0.6); sp[k] = x }
                fm["sp"] = sp
            } else if div == 2 && rank <= 3 {
                fm["div"] = 1
                msg += " They are promoted!"
            }
            let newVal = round100k(club["val"].double * clamp(1 + Double(exp - rank) / Double(N) * 0.12, 0.88, 1.15) * 1.02)
            setClub(&s, country.code, id: cid) { $0["val"] = .number(newVal) }
            fm["val"] = .number(newVal)
            fm["R"] = .number(clubRevenue(clubValue: newVal, div: fm["div"].int))
            fm["s0"] = .null
            // contracts run out and players age: what you bought (or lost) fades over a season or two. Original: round-24 'seasonEnd' step.
            fm["sq"] = .number(fm["sq"].double * 0.65)
            fm["xw"] = .number(fm["xw"].double * 0.65)
            s.companies[i].set("fm", fm)
            s.note(msg, tone: rank <= 3 ? "good" : "n", companyID: id)
        }
        let ownIDs = Set(own.map { s.companies[$0].value("fm")["club"].string })
        for k in lg.t.indices {
            let rk = sorted.firstIndex { $0.id == lg.t[k].id } ?? 0
            if !ownIDs.contains(lg.t[k].id) {
                lg.t[k].s = clamp(lg.t[k].s * 0.75 + (28 + 57 * (Double(N - 1 - rk) / Double(max(1, N - 1)))) * 0.25 + s.random.gauss() * 3, 18, 92)
            }
            lg.t[k].pts = 0; lg.t[k].gp = 0; lg.t[k].hg = 0
        }
        lg.season += 1
        lg.w0 = s.week + 1
        lg.res = [:]
        for i in own { sponsorOffers(&s, i, country: country) }
    }

    /// Yearly revenue of a club from its value. Original: `clubRev`.
    public static func clubRevenue(clubValue: Double, div: Int) -> Double { clubValue / 3 * (div == 2 ? 0.45 : 1) }

    /// Clubs come up for sale and go off the market, and owners warm to you again. Original: `clubMonth`.
    public static func monthly(_ s: inout GameState) {
        guard var all = s.rest["clubs"], !all.isNull else { return }
        for cc in all.object.keys.sorted() {
            var list = all[cc].array
            for k in list.indices {
                guard list[k]["owner"].string == "ai", !list[k]["fixed"].bool else { continue }
                if !list[k]["listed"].bool && s.random.chance(list[k]["val"].double > 1e9 * 2 ? 0.01 : 0.03) { list[k]["listed"] = true }
                else if list[k]["listed"].bool && s.random.chance(0.1) { list[k]["listed"] = false }
                list[k]["rel"] = .number(list[k]["rel"].double + (40 - list[k]["rel"].double) * 0.03)
            }
            all[cc] = .array(list)
        }
        s.rest["clubs"] = all
    }

    // MARK: Buying and founding

    public struct Offer: Equatable {
        public enum Answer: String, Equatable { case accept, counter, reject, ignore }
        public var answer: Answer
        public var price: Double?
        public var debt: Double
        public var message: String
        public init(answer: Answer, price: Double?, debt: Double, message: String) { self.answer = answer; self.price = price; self.debt = debt; self.message = message }
    }

    /// The debt a club carries; you take it over when you buy it. Original: `R24.clubDebt`.
    static func clubDebt(_ club: JSONValue, seed: Int) -> Double {
        if !club["debt"].isNull { return club["debt"].double }
        let h = Double(Int(hash(club["id"].string + ":" + String(seed == 0 ? 1 : seed))) % 1000) / 1000
        return club["founded"].bool ? 0 : round100k(club["val"].double * (0.05 + 0.45 * h))
    }

    /// An offer for a club, as a multiple of its value. Original: `proposeClub` + the debt step.
    public static func propose(_ s: inout GameState, clubID: String, multiple mult: Double, currency cur: Currency) -> Offer {
        guard let club = findClub(s, id: clubID) else { return Offer(answer: .ignore, price: nil, debt: 0, message: "No such club.") }
        let cc = club["country"].string
        func update(_ f: (inout JSONValue) -> Void) { setClub(&s, cc, id: clubID, f) }
        if Double(s.week) < club["lock"].double { return Offer(answer: .ignore, price: nil, debt: 0, message: "The club board does not answer.") }
        if club["fixed"].bool {
            update { $0["ign"] = .number($0["ign"].double + 1) }
            return Offer(answer: .reject, price: nil, debt: 0, message: "The owners say the club is not for sale, at any price.")
        }
        let val = club["val"].double, rel = club["rel"].double, listed = club["listed"].bool
        let price = round100k(val * mult)
        if !listed && rel < 45 && s.random.chance(0.4) { return Offer(answer: .ignore, price: nil, debt: 0, message: "Your offer is ignored.") }
        let need = (listed ? 1.0 : 2.3) * (1.1 - rel / 400)
        let debt = clubDebt(club, seed: s.seed)
        func net(_ p: Double) -> Double { max(round100k(p - debt), round100k(val * 0.1)) }
        let tail = debt > 0 ? " On top, you take over \(cur.short(debt)) of club debt." : ""
        if mult >= need && (listed || s.random.chance(0.1)) {
            return Offer(answer: .accept, price: net(price), debt: debt, message: "The owners agree to sell at \(cur.short(net(price)))." + tail)
        }
        if listed && mult >= need * 0.88 {
            let p2 = round100k(val * need)
            return Offer(answer: .counter, price: net(p2), debt: debt, message: "The owners will sell for \(cur.short(net(p2))) and not less." + tail)
        }
        let ign = club["ign"].double + 1
        update { $0["ign"] = .number(ign); $0["rel"] = .number(max(0, $0["rel"].double - 5)) }
        if ign >= 3 {
            update { $0["lock"] = .number(Double(s.week + 52)) }
            return Offer(answer: .reject, price: nil, debt: 0, message: "The board ends the talks. They will not take your calls for a year.")
        }
        return Offer(answer: .reject, price: nil, debt: 0, message: listed ? "The offer is far below what the owners want." : "The club is not for sale.")
    }

    public enum BuyResult: Equatable { case ok(Int), notEnoughCash, notAvailable }

    /// Buy the club at the agreed price (the club's debt comes with it). Original: `buyClub` + the debt step.
    public static func buy(_ s: inout GameState, clubID: String, price: Double, data: GameData, context fc: FinanceContext) -> BuyResult {
        guard let club = findClub(s, id: clubID), club["owner"].string == "ai", let country = data.countries[club["country"].string] else { return .notAvailable }
        if s.cash < price { return .notEnoughCash }
        let debt = clubDebt(club, seed: s.seed)
        Payments.playerPays(&s, price, label: "Purchase of \(club["name"].string)")
        setClub(&s, country.code, id: clubID) { $0["owner"] = "you"; $0["listed"] = false }
        guard let id = makeClubCompany(&s, club: club, division: 1, cash: jsRound(club["val"].double * 0.03), country: country, data: data) else { return .notAvailable }
        if debt > 0 {
            var l = Loan(raw: [:])
            l.id = s.makeID(); l.kind = "biz"; l.name = "Club debt taken over"
            l.balance = debt; l.originalAmount = debt
            l.margin = Banking.creditMargin(s.credit) + 0.015
            l.termMonths = 240; l.companyID = id; l.startWeek = s.week; l.isGuaranteed = false
            l.monthlyPayment = Loans.annuity(principal: debt, yearlyRate: s.economy.policyRate + l.margin, months: 240)
            s.loans.append(l)
            setClub(&s, country.code, id: clubID) { $0["debt"] = 0 }
            s.note("\(club["name"].string) comes with \(fc.currency(country.code, s).short(debt)) of debt, repaid by the club over twenty years. Clubs rarely make money on football alone: plan to put in cash, or sell players.", tone: "n", companyID: id)
        }
        return .ok(id)
    }

    /// Value of a new club in the second tier. Original: `foundClub`.
    public static func foundingValue(_ country: Country) -> Double? {
        leagueInfo(country).map { round100k($0.low * usd * 1e6 * 0.5) }
    }

    /// Found a club in the second tier; it must earn promotion to the top league. Original: `foundClub`.
    public static func found(_ s: inout GameState, country: Country, cityID: String?, data: GameData) -> BuyResult {
        guard let val = foundingValue(country) else { return .notAvailable }
        if s.cash < val * 0.4 { return .notEnoughCash }
        var list = ensureClubs(&s, country)
        let city = cityID ?? country.cities[0].id
        let name = cleanName(s.random.pick(country.lastNames)) + " " + s.random.pick(suffixes)
        let club: JSONValue = .object(["id": .string("\(country.code):new\(s.makeID())"), "name": .string(name), "country": .string(country.code), "city": .string(city),
                                       "rank0": .number(Double(list.count - 1)), "val": .number(val), "owner": "you", "fixed": false, "listed": false, "rel": 50, "ign": 0, "lock": 0, "founded": 1])
        list.append(club)
        var all = s.rest["clubs"] ?? .object([:]); all[country.code] = .array(list); s.rest["clubs"] = all
        var lg = league(&s, country)
        lg.t.append(Row(id: club["id"].string, s: 34, pts: 0, gp: 0, hg: 0))
        saveLeague(&s, country.code, lg)
        Payments.playerPays(&s, jsRound(val * 0.4), label: "Founding of \(name)")
        guard let id = makeClubCompany(&s, club: club, division: 2, cash: jsRound(val * 0.4 * 0.5), country: country, data: data) else { return .notAvailable }
        return .ok(id)
    }

    /// The company that runs a club you own. Original: `makeClubCo`.
    static func makeClubCompany(_ s: inout GameState, club: JSONValue, division div: Int, cash: Double, country: Country, data: GameData) -> Int? {
        guard let id = SpecialFamilies.blankCompany(&s, tradeID: "club", country: country, cityID: club["city"].string, name: club["name"].string, size: 1, data: data),
              let i = s.companyIndex(id) else { return nil }
        s.companies[i].status = .open
        s.companies[i].openedWeek = s.week
        Ledger.set(&s, .company(id), to: cash)
        CompanySetup.chooseAccountant(&s, companyID: id, accountantID: nil, data: data)
        var docs = s.companies[i].value("docs")
        for d in ["registration", "accountant_agreement", "vat"] { docs[d] = .object(["st": "ok", "done": .number(Double(s.week)), "ok": .number(Double(s.week))]) }
        s.companies[i].set("docs", docs)
        let L = leagueInfo(country)
        let N = L?.clubs ?? 16
        let rank0 = club["rank0"].double
        s.companies[i].reputation = 55 + (Double(N) - rank0) * 1.2
        s.companies[i].awareness = min(100, 50 + (Double(N) - rank0) * 2.2)
        var fm: JSONValue = .object(["club": club["id"], "div": .number(Double(div)), "wage": 0.62, "tix": 0,
                                    "coach": .null, "asst": .null, "sp": .object([:]), "offers": .object([:]), "offW": -99,
                                    "last": .array([]), "hist": .array([]), "titles": 0, "s": 50, "val": club["val"]])
        fm["coach"] = generateCoach(&s, club: club, kind: "coach", boost: 0, country: country, data: data).json
        fm["asst"] = generateCoach(&s, club: club, kind: "asst", boost: 0, country: country, data: data).json
        s.companies[i].set("fm", fm)
        var lg = league(&s, country)
        if let k = lg.t.firstIndex(where: { $0.id == club["id"].string }) {
            lg.t[k].s = clubBase(rank0: rank0, n: lg.t.count)
            fm["s"] = .number(lg.t[k].s)
            s.companies[i].set("fm", fm)
            saveLeague(&s, country.code, lg)
        }
        sponsorOffers(&s, i, country: country)
        for slot in slots {
            if let o = s.companies[i].value("fm")["offers"][slot.key].array.first { _ = takeSponsor(&s, companyIndex: i, slot: slot.key, offerID: o["id"].int) }
        }
        sponsorOffers(&s, i, country: country)
        return id
    }

    // MARK: Sponsors

    static func sponsorOffers(_ s: inout GameState, _ i: Int, country: Country) {
        var fm = s.companies[i].value("fm")
        guard let club = findClub(s, id: fm["club"].string) else { return }
        let R = clubRevenue(clubValue: club["val"].double, div: fm["div"].int)
        let cur = Currency(country: country, rates: ExchangeRates(drift: s.exchangeRates.values))
        fm["offW"] = .number(Double(s.week))
        var offers = fm["offers"]
        for slot in slots {
            if !fm["sp"][slot.key].isNull, fm["sp"][slot.key]["until"].double > Double(s.week) { continue }
            var list: [JSONValue] = []
            for _ in 0..<3 {
                let name = s.random.pick(brandWords) + " " + s.random.pick(sponsorIndustries)
                let wk = cur.roundedStep(R * slot.share / 52 * s.random.range(0.8, 1.25) * (0.7 + (fm["s"].isNull ? 50 : fm["s"].double) / 150), about: 100)
                list.append(.object(["id": .number(Double(s.makeID())), "name": .string(name), "wk": .number(wk), "yrs": .number(Double(s.random.int(1, 3)))]))
            }
            offers[slot.key] = .array(list)
        }
        fm["offers"] = offers
        s.companies[i].set("fm", fm)
    }

    public enum SponsorResult: Equatable { case ok, gone }

    @discardableResult
    public static func takeSponsor(_ s: inout GameState, companyIndex i: Int, slot: String, offerID: Int) -> SponsorResult {
        var fm = s.companies[i].value("fm")
        guard let o = fm["offers"][slot].array.first(where: { $0["id"].int == offerID }) else { return .gone }
        fm["sp"][slot] = .object(["name": o["name"], "wk": o["wk"], "until": .number(Double(s.week) + o["yrs"].double * 52)])
        fm["offers"][slot] = .array([])
        s.companies[i].set("fm", fm)
        return .ok
    }

    // MARK: People: the manager and the assistant

    public struct Coach: Equatable, Identifiable {
        public var id: Int, name: String, skill: Double, wage: Double, age: Int, kind: String, interim: Bool
        var json: JSONValue {
            .object(["id": .number(Double(id)), "name": .string(name), "skill": .number(skill), "wage": .number(wage), "age": .number(Double(age)), "kind": .string(kind), "interim": .bool(interim)])
        }
        init(id: Int, name: String, skill: Double, wage: Double, age: Int, kind: String, interim: Bool = false) {
            self.id = id; self.name = name; self.skill = skill; self.wage = wage; self.age = age; self.kind = kind; self.interim = interim
        }
        init?(_ j: JSONValue) {
            guard !j.isNull else { return nil }
            self.init(id: j["id"].int, name: j["name"].string, skill: j["skill"].double, wage: j["wage"].double, age: j["age"].int, kind: j["kind"].string, interim: j["interim"].bool)
        }
        /// A word for the quality. Original: the UI's wording.
        public var quality: String { skill >= 80 ? "Outstanding" : skill >= 65 ? "Strong" : skill >= 45 ? "Capable" : "Developing" }
    }

    static func generateCoach(_ s: inout GameState, club: JSONValue, kind: String, boost: Double, country: Country, data: GameData) -> Coach {
        let N = Double(leagueInfo(country)?.clubs ?? 16)
        let top = clamp(1 - club["rank0"].double / N, 0, 1)
        let skill = jsRound(clamp(40 + top * 28 + s.random.gauss() * 10 + boost + (kind == "asst" ? -6 : 0), 25, 96))
        let R = clubRevenue(clubValue: club["val"].double, div: 1)
        let cur = Currency(country: country, rates: ExchangeRates(drift: s.exchangeRates.values))
        let ask = cur.roundedStep(R / 52 * 0.03 * (0.5 + skill / 70) * (kind == "asst" ? 0.4 : 1), about: 100)
        let name = Hiring.personName(country, &s.random)
        return Coach(id: s.makeID(), name: name, skill: skill, wage: ask, age: s.random.int(34, 63), kind: kind)
    }

    /// Four candidates for the job. Original: `clubCands`.
    public static func candidates(_ s: inout GameState, companyID: Int, kind: String, data: GameData) -> [Coach] {
        guard let i = s.companyIndex(companyID), let club = findClub(s, id: s.companies[i].value("fm")["club"].string),
              let country = data.countries[s.companies[i].countryCode] else { return [] }
        return (0..<4).map { _ in generateCoach(&s, club: club, kind: kind, boost: s.random.range(-8, 12), country: country, data: data) }
    }

    @discardableResult
    public static func hire(_ s: inout GameState, companyID: Int, coach c: Coach, kind: String) -> Bool {
        guard let i = s.companyIndex(companyID), s.companies[i].type == "club" else { return false }
        var fm = s.companies[i].value("fm")
        var h = c; h.kind = kind; h.interim = false
        if kind == "coach" { fm["coach"] = h.json; fm["coachNew"] = 0 } else { fm["asst"] = h.json }
        s.companies[i].set("fm", fm)
        return true
    }

    public static func dismissAssistant(_ s: inout GameState, companyID: Int) {
        guard let i = s.companyIndex(companyID) else { return }
        var fm = s.companies[i].value("fm"); fm["asst"] = .null; s.companies[i].set("fm", fm)
    }

    /// The manager is sacked; the assistant takes over or a caretaker steps in. Original: `clubSack`.
    public static func sackManager(_ s: inout GameState, companyIndex i: Int, reason why: String, data: GameData) {
        var fm = s.companies[i].value("fm")
        guard let old = Coach(fm["coach"]) else { return }
        let co = s.companies[i]
        let country = data.countries.resolve(co.countryCode, orHome: s.homeCountryCode)
        let cur = Currency(country: country, rates: ExchangeRates(drift: s.exchangeRates.values))
        if let a = Coach(fm["asst"]) {
            var c = a; c.kind = "coach"; c.skill = max(25, a.skill - 4); c.wage = cur.roundedStep(a.wage * 1.5, about: 100); c.interim = true
            fm["coach"] = c.json; fm["asst"] = .null; fm["coachNew"] = .number(Double(s.week))
            s.companies[i].set("fm", fm)
            s.addMessage(kind: "info", from: co.name, title: "\(old.name) sacked, \(a.name) takes over",
                         body: "After \(why), the club parted with the manager. The assistant \(a.name) is in charge for now. Find a permanent manager and a new assistant as soon as you can.", companyID: co.id, tone: "bad")
        } else {
            let c = Coach(id: s.makeID(), name: "Caretaker", skill: 35, wage: cur.roundedStep(1000 * country.wageLevel, about: 100), age: 50, kind: "coach", interim: true)
            fm["coach"] = c.json; fm["coachNew"] = .number(Double(s.week))
            s.companies[i].set("fm", fm)
            s.addMessage(kind: "info", from: co.name, title: "\(old.name) sacked",
                         body: "There is no assistant to step in, so a caretaker leads the team. Hire a manager quickly.", companyID: co.id, tone: "bad")
        }
    }

    // MARK: Budget

    public static func setWageShare(_ s: inout GameState, companyID: Int, share: Double) {
        guard let i = s.companyIndex(companyID), s.companies[i].type == "club" else { return }
        var fm = s.companies[i].value("fm"); fm["wage"] = .number(clamp(share, 0.4, 0.95)); s.companies[i].set("fm", fm)
    }
    public static func setTicketLevel(_ s: inout GameState, companyID: Int, level: Int) {
        guard let i = s.companyIndex(companyID), s.companies[i].type == "club" else { return }
        var fm = s.companies[i].value("fm"); fm["tix"] = .number(Double(min(1, max(-1, level)))); s.companies[i].set("fm", fm)
    }

    // MARK: The week of the club

    /// Original: `clubWeek` + the round-24 step (extra wages, write-off of signings, bids for your players).
    static func context(_ s: inout GameState, _ i: Int, _ bd: Trade, _ data: GameData) -> CompanyWeek.WeekContext {
        var co = s.companies[i]
        var fm = co.value("fm")
        let country = data.countries.resolve(co.countryCode, orHome: s.homeCountryCode)
        let lg = league(&s, country)
        guard let club = findClub(s, id: fm["club"].string) else {
            return CompanyWeek.WeekContext(units: 0, rev: 0, cogs: 0, D: 1, cap: 1, util: 0.7, price: 1, paidDuringWeek: 0)
        }
        let div = fm["div"].int
        let R = clubRevenue(clubValue: club["val"].double, div: div)
        fm["R"] = .number(R)
        let res = lg.res[fm["club"].string]
        let strengthNow = fm["s"].isNull ? 50 : fm["s"].double
        var rev = 0.0
        let tv = R * 0.46 / 52
        rev += tv
        var spons = 0.0
        var sp = fm["sp"]
        for (k, v) in sp.object.sorted(by: { $0.key < $1.key }) { if v["until"].double > Double(s.week) { spons += v["wk"].double } else { sp[k] = .null } }
        sp = .object(sp.object.filter { !$0.value.isNull })
        fm["sp"] = sp
        rev += spons
        let merch = R * 0.12 / 52 * (0.7 + strengthNow / 200 + (co.reputation - 50) / 400)
        rev += merch
        let M = Double(lg.matchWeeks)
        var md = 0.0
        let tix = fm["tix"].double
        if let r = res, r.home {
            let fill = clamp(0.5 + strengthNow / 250 + (co.reputation - 50) / 250 - tix * 0.07, 0.3, 1)
            md = R * 0.20 / (M / 2) * (fill / 0.75) * (1 + tix * 0.15)
            rev += md
            fm["fill"] = .number(fill)
        }
        let wages = fm["wage"].double * R / 52
        let coachW = (fm["coach"].isNull ? 0 : fm["coach"]["wage"].double) + (fm["asst"].isNull ? 0 : fm["asst"]["wage"].double)
        let ops = R * 0.3 / 52
        var cogs = ops   // the playing and coaching wages go to the wages line (below), not the cost of sales
        var wageBill = wages + coachW
        fm["wk"] = .object(["tv": .number(tv), "spons": .number(spons), "merch": .number(merch), "match": .number(md), "wages": .number(wages), "coaches": .number(coachW), "ops": .number(ops)])
        if let r = res {
            var last = fm["last"].array
            last.append(.string(r.r))
            if last.count > 8 { last.removeFirst() }
            fm["last"] = .array(last)
            co.reputation = clamp(co.reputation + (r.r == "W" ? 0.35 : r.r == "L" ? -0.3 : 0.02), 0, 100)
        }
        co.set("fm", fm)
        s.companies[i] = co
        if res != nil, !fm["coach"].isNull, fm["last"].array.count >= 8, fm["coachNew"].double == 0 {
            let pts = fm["last"].array.reduce(0) { $0 + ($1.string == "W" ? 3 : $1.string == "D" ? 1 : 0) }
            let rank = lg.rank(of: fm["club"].string), N = Double(lg.t.count)
            if pts <= 5 && Double(rank) > N * 0.6 && s.random.chance(0.12) { sackManager(&s, companyIndex: i, reason: "poor results", data: data) }
        }
        fm = s.companies[i].value("fm")
        if fm["coachNew"].double != 0 && Double(s.week) - fm["coachNew"].double > 8 { fm["coachNew"] = 0 }
        let fillNow = fm["fill"].double
        if s.week % 4 == 0 && Double(s.week) - fm["offW"].double >= 13 {
            s.companies[i].set("fm", fm)
            sponsorOffers(&s, i, country: country)
            fm = s.companies[i].value("fm")
        }
        // The round-24 step: extra wages for players signed (or saved by selling), signings written off over three years.
        wageBill += fm["xw"].double * R / 52
        var dep = 0.0
        var amort = fm["amort"].array
        for k in amort.indices where amort[k]["left"].double > 0 { dep += amort[k]["a"].double; amort[k]["left"] = .number(amort[k]["left"].double - 1) }
        amort = amort.filter { $0["left"].double > 0 }
        fm["amort"] = .array(amort)
        if dep > 0 { fm["book"] = .number(max(0, fm["book"].double - dep)) }
        s.companies[i].set("fm", fm)
        if dep > 0 { Payments.book(&s, companyID: co.id, category: "dep", amount: dep) }
        if wageBill > 0 { Payments.companyPays(&s, companyID: co.id, amount: wageBill, category: "wages", label: "Players' and coaches' wages") }
        // Bids for your players arrive while a transfer window is open.
        if let win = transferWindow(s, lg) {
            let open = s.inbox.contains { $0.actionID == "club24" && $0.companyID == co.id && $0.status == "open" }
            if s.random.chance(win == "summer" ? 0.15 : 0.08) && !open {
                let f = s.random.range(0.04, 0.15) * (0.6 + strengthNow / 100)
                let fee = round100k(R * f), pts = f * 22, xw2 = f * 0.12
                let who = Hiring.personName(country, &s.random)
                let to = s.random.pick(brandWords) + " " + s.random.pick(bidderSuffixes)
                let cur = Currency(country: country, rates: ExchangeRates(drift: s.exchangeRates.values))
                s.addMessage(kind: "ask", from: co.name, title: "\(to) bid \(cur.short(fee)) for \(who)",
                             body: "\(who) is one of your \(pts > 4 ? "best players" : "regular starters"). Selling brings cash now but weakens the team (about \(String(format: "%.1f", pts)) strength points) until you replace him.",
                             companyID: co.id, tone: "n", status: "open",
                             options: [.option("Sell for \(cur.short(fee))", "Cash now, weaker squad."), .option("Keep him", "No change.")],
                             action: "club24", data: .object(["who": .string(who), "to": .string(to), "fee": .number(fee), "pts": .number(pts), "xw": .number(xw2)]), expiresWeek: s.week + 2)
            }
        }
        return CompanyWeek.WeekContext(units: res != nil ? 1 : 0, rev: rev, cogs: cogs, D: 1, cap: 1, util: fillNow != 0 ? fillNow : 0.7, price: 1, paidDuringWeek: 0)
    }

    // MARK: Transfers

    /// "summer" in the first six weeks of the season, "winter" in weeks 26-29, otherwise nil. Original: `R24.window`.
    static func transferWindow(_ s: GameState, _ lg: League) -> String? {
        let sw = s.week - lg.w0
        return sw >= 0 && sw < 6 ? "summer" : sw >= 26 && sw < 30 ? "winter" : nil
    }

    public static func window(_ s: GameState, companyID: Int) -> (name: String?, weeksToOpen: Int) {
        guard let co = s.company(companyID), let lg = readLeague(s, co.countryCode) else { return (nil, 0) }
        let sw = s.week - lg.w0
        let w = transferWindow(s, lg)
        return (w, w != nil ? 0 : (sw < 26 ? 26 - sw : 52 - sw))
    }

    public static func signingFee(_ s: GameState, companyID: Int, tier: Int) -> Double {
        guard let co = s.company(companyID), let club = findClub(s, id: co.value("fm")["club"].string) else { return 0 }
        return round100k(clubRevenue(clubValue: club["val"].double, div: co.value("fm")["div"].int) * tiers[tier].fee)
    }

    public enum SignResult: Equatable { case ok, closed, cash }

    /// Buy a player now, in a transfer window. The fee is written off over three years. Original: `R24.sign`.
    public static func sign(_ s: inout GameState, companyID: Int, tier: Int) -> SignResult {
        guard let i = s.companyIndex(companyID), tier >= 0, tier < tiers.count, let lg = readLeague(s, s.companies[i].countryCode) else { return .closed }
        if transferWindow(s, lg) == nil { return .closed }
        let fee = signingFee(s, companyID: companyID, tier: tier)
        if s.companies[i].cash < fee { return .cash }
        Payments.companyPays(&s, companyID: companyID, amount: fee, category: nil, label: "Transfer fee: \(tiers[tier].name.lowercased())")
        var fm = s.companies[i].value("fm")
        let T = tiers[tier]
        fm["sq"] = .number(fm["sq"].double + T.strength)
        fm["xw"] = .number(fm["xw"].double + T.wages)
        fm["book"] = .number(fm["book"].double + fee)
        var am = fm["amort"].array
        am.append(.object(["a": .number(fee / 156), "left": 156]))
        fm["amort"] = .array(am)
        fm["tin"] = .number(fm["tin"].double + fee)
        s.companies[i].set("fm", fm)
        return .ok
    }

    /// The owner answers a bid for a player. Original: `ACTS.club24` and `R24.sell`.
    public static func answerBid(_ s: inout GameState, message m: Message, option idx: Int) {
        guard let i = s.companyIndex(m.companyID), !s.companies[i].value("fm").isNull else { return }
        let d = m.value("data")
        if d["done"].bool { return }
        if let k = s.inbox.firstIndex(where: { $0.id == m.id }) { var dd = d; dd["done"] = 1; s.inbox[k].set("data", dd) }
        guard idx == 0 else { return }
        var fm = s.companies[i].value("fm")
        // The player's remaining book value (his share of the unamortised signing fees) is written off at the sale; the sale books only the
        // difference to the fee, once: a gain in revenue or a loss.
        let share = fm["sq"].double > 0 ? clamp(d["pts"].double / fm["sq"].double, 0, 1) : 0
        var am = fm["amort"].array
        var writeOff = 0.0
        for k in am.indices { writeOff += share * am[k]["a"].double * am[k]["left"].double; am[k]["a"] = .number(am[k]["a"].double * (1 - share)) }
        fm["amort"] = .array(am)
        fm["book"] = .number(max(0, fm["book"].double - writeOff))
        s.companies[i].set("fm", fm)
        Payments.companyReceives(&s, companyID: m.companyID, amount: d["fee"].double, category: nil, label: "Transfer fee received")
        let result = jsRound(d["fee"].double) - writeOff
        if result > 0 { Payments.book(&s, companyID: m.companyID, category: "rev", amount: result) }
        else if result < 0 { Payments.book(&s, companyID: m.companyID, category: "loss", amount: -result) }
        fm = s.companies[i].value("fm")
        fm["sq"] = .number(fm["sq"].double - d["pts"].double)
        fm["xw"] = .number(max(-0.05, fm["xw"].double - d["xw"].double))
        fm["tout"] = .number(fm["tout"].double + d["fee"].double)
        s.companies[i].set("fm", fm)
        s.companies[i].reputation = clamp(s.companies[i].reputation - d["pts"].double * 0.3, 0, 100)
        s.note("\(s.companies[i].name) sold \(d["who"].string) to \(d["to"].string).", tone: "good", companyID: m.companyID)
    }

    // MARK: Reading for screens

    public struct TableRow: Identifiable, Equatable {
        public var id: String, name: String
        public var position: Int, points: Int, played: Int
        public var isYours: Bool
    }
    public struct ClubInfo: Identifiable, Equatable {
        public var id: String, name: String, city: String
        public var value: Double
        public var owner: String
        public var isFixed: Bool, isListed: Bool
        public var rank: Int
    }
    public struct Summary: Equatable {
        public var leagueName = "", season = 1
        public var division = 1
        public var position = 0, clubs = 0, points = 0, played = 0
        public var form: [String] = []
        public var titles = 0
        public var squadStrength = 0.0
        public var clubValue = 0.0
        public var yearlyRevenue = 0.0
        public var wageShare = 0.62, ticketLevel = 0
        public var weekly: [String: Double] = [:]
        public var fill = 0.0
        public var debt = 0.0
        public var coach: Coach?, assistant: Coach?
        public var seasons: [(season: Int, rank: Int, division: Int)] = []
        public var sponsors: [(slot: String, title: String, name: String, weekly: Double, yearsLeft: Double)] = []
        public var offers: [String: [(id: Int, name: String, weekly: Double, years: Int)]] = [:]
        public var tradedIn = 0.0, tradedOut = 0.0
        public var table: [TableRow] = []
        public var wageToRevenue: Double { let w = weekly; let rev = (w["tv"] ?? 0) + (w["spons"] ?? 0) + (w["merch"] ?? 0) + yearlyMatchday / 52; return rev > 0 ? ((w["wages"] ?? 0) + (w["coaches"] ?? 0)) / rev : 0 }
        var yearlyMatchday: Double = 0
        public static func == (a: Summary, b: Summary) -> Bool { a.leagueName == b.leagueName && a.position == b.position && a.points == b.points && a.clubValue == b.clubValue }
    }

    public static func wordForStrength(_ s: Double) -> String { s >= 80 ? "Elite" : s >= 65 ? "Strong" : s >= 50 ? "Solid" : s >= 35 ? "Weak" : "Poor" }

    public static func summary(_ co: Company, _ s: GameState, data: GameData) -> Summary? {
        let fm = co.value("fm")
        guard co.type == "club", !fm.isNull, let country = data.countries[co.countryCode], let club = findClub(s, id: fm["club"].string) else { return nil }
        var r = Summary()
        r.leagueName = leagueInfo(country)?.name ?? ""
        r.division = fm["div"].int
        r.clubValue = club["val"].double
        r.yearlyRevenue = clubRevenue(clubValue: r.clubValue, div: r.division)
        r.yearlyMatchday = r.yearlyRevenue * 0.20 * (fm["fill"].double == 0 ? 0.9 : fm["fill"].double / 0.75)
        r.squadStrength = fm["s"].isNull ? 50 : fm["s"].double
        r.titles = fm["titles"].int
        r.wageShare = fm["wage"].double
        r.ticketLevel = fm["tix"].int
        r.form = fm["last"].array.map { $0.string }
        r.fill = fm["fill"].double
        r.weekly = fm["wk"].object.mapValues { $0.double }
        r.debt = s.loans.filter { $0.companyID == co.id }.reduce(0) { $0 + $1.balance }
        r.coach = Coach(fm["coach"]); r.assistant = Coach(fm["asst"])
        r.tradedIn = fm["tin"].double; r.tradedOut = fm["tout"].double
        r.seasons = fm["hist"].array.map { ($0["season"].int, $0["rank"].int, $0["div"].int) }
        for slot in slots {
            let cur = fm["sp"][slot.key]
            if !cur.isNull, cur["until"].double > Double(s.week) {
                r.sponsors.append((slot.key, slot.title, cur["name"].string, cur["wk"].double, (cur["until"].double - Double(s.week)) / 52))
            }
            r.offers[slot.key] = fm["offers"][slot.key].array.map { (id: $0["id"].int, name: $0["name"].string, weekly: $0["wk"].double, years: $0["yrs"].int) }
        }
        if let lg = readLeague(s, co.countryCode) {
            r.season = lg.season
            r.clubs = lg.t.count
            r.position = lg.rank(of: fm["club"].string)
            let me = lg.t.first { $0.id == fm["club"].string }
            r.points = me?.pts ?? 0; r.played = me?.gp ?? 0
            let names = Dictionary(uniqueKeysWithValues: clubs(s, co.countryCode).map { ($0["id"].string, $0["name"].string) })
            r.table = lg.sorted.enumerated().map { TableRow(id: $0.element.id, name: names[$0.element.id] ?? $0.element.id, position: $0.offset + 1, points: $0.element.pts, played: $0.element.gp, isYours: $0.element.id == fm["club"].string) }
        } else { r.clubs = leagueInfo(country)?.clubs ?? 0 }
        return r
    }

    /// The clubs of a country as the buying screen lists them. Makes them (without saving) if the league was not opened yet.
    public static func clubList(_ s: GameState, country: Country) -> [ClubInfo] {
        let list = s.rest["clubs"]?[country.code].isNull == false ? clubs(s, country.code) : generateClubs(country: country, seed: s.seed)
        return list.map { ClubInfo(id: $0["id"].string, name: $0["name"].string, city: $0["city"].string, value: $0["val"].double, owner: $0["owner"].string,
                                   isFixed: $0["fixed"].bool, isListed: $0["listed"].bool, rank: $0["rank0"].int + 1) }
    }
}
