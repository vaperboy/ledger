import Foundation
import GameCore
import Countries
import Employees
import Finance

/// The market map: your share of each market you are in, worked out from sales against what each rival sells there (banks, insurers
/// and funds against the whole country). What you SEE depends on who is looking: nobody (only a feeling, in words), a head-office
/// data analyst (ranges, sharper with experience) or a market analyst in the company (close numbers, a report every month).
/// Original: features/world/market_map_and_reviews.js (`markets`, `truthOf`, `know`, `est`, `snap`, `reportLines`).
/// The analyst roles: a market analyst is hired into a company like any worker (role `mktan`; `analystHireVerdict` says what the hire
/// gives), a data analyst (`ana`) into the head office (`hireDataAnalyst`, paid monthly from `weekly` until the head-office branch
/// pays its staff itself). `weight` is the "weight in the economy" block (share of business loans, jobs, regulator attention).
public enum MarketMap {
    public enum Kind: String { case local, national }

    public struct Market: Identifiable, Equatable {
        public var id: String            // the market key
        public var kind: Kind
        public var type: String
        public var cityID: String
        public var countryCode: String
        public var companyIDs: [Int]
    }

    public struct Player: Identifiable, Equatable {
        public var id: String
        public var name: String
        public var revenue: Double
        public var share: Double
        public var rivalID: Int?         // nil for national players, who are only names
    }

    public struct Truth: Equatable {
        public var mine: Double, total: Double, share: Double
        public var players: [Player]
    }

    static let national: [String: (label: String, noun: String, base: Double, word: String)] = [
        "bank": ("Bank deposits", "deposits", 450_000, "Bank"), "insco": ("Insurance", "premiums", 14_000, "Insurance"), "fund": ("Fund assets", "fund assets", 300_000, "Asset Management"),
    ]

    // MARK: Which markets

    public static func markets(_ s: GameState, data: GameData) -> [Market] {
        var by: [String: Market] = [:], order: [String] = []
        for co in s.companies where co.status == .open {
            guard let bd = data.catalog[co.type] else { continue }
            let k: String, kind: Kind
            if RivalGroups.localFamilies.contains(bd.family), bd.normalDemand > 0 { k = Rivals.key(co); kind = .local }
            else if national[co.type] != nil { k = "fin|\(co.type)|\(co.countryCode)"; kind = .national }
            else { continue }
            if by[k] == nil { by[k] = Market(id: k, kind: kind, type: co.type, cityID: co.cityID, countryCode: co.countryCode, companyIDs: []); order.append(k) }
            by[k]!.companyIDs.append(co.id)
        }
        return order.compactMap { by[$0] }
    }

    public static func market(of co: Company, _ s: GameState, data: GameData) -> Market? { markets(s, data: data).first { $0.companyIDs.contains(co.id) } }

    public static func label(_ m: Market, data: GameData, withCity: Bool) -> String {
        if m.kind == .national { return national[m.type]?.label ?? m.type }
        let city = data.countries.city(m.cityID, preferring: m.countryCode)?.city.name ?? m.cityID
        return (data.catalog[m.type]?.name ?? m.type) + (withCity ? " · " + city : "")
    }

    // MARK: Sales

    /// A company's sales in a year, from the last weeks. Original: `annRev`.
    public static func annualRevenue(_ co: Company) -> Double {
        let L = co.value("rv26").array
        if L.count >= 2 { return L.reduce(0) { $0 + $1.double } / Double(L.count) * 52 }
        let h = co.monthlyHistory.suffix(3)
        if !h.isEmpty { return h.reduce(0) { $0 + $1.revenue } / Double(h.count) * 12 }
        return co.lastWeekRevenue * 52
    }

    static func nationalTotal(_ m: Market, data: GameData) -> Double {
        let c = data.countries[m.countryCode] ?? data.countries.countries[0]
        return max(1, c.populationMillions * 1e6 * (national[m.type]?.base ?? 100_000) * pow(c.marketStrength, 2) * c.priceLevel)
    }

    static func size(_ co: Company) -> Double {
        let fm = co.value("fm")
        return co.type == "bank" ? fm["dep"].double : co.type == "fund" ? fm["aum"].double : annualRevenue(co)
    }

    /// The true picture of one market. Original: `truthOf`.
    public static func truth(_ s: GameState, _ m: Market, data: GameData) -> Truth {
        let cos = m.companyIDs.compactMap { s.company($0) }
        guard let co = cos.first else { return Truth(mine: 0, total: 1, share: 0, players: []) }
        let w = World(state: s, data: data)
        if m.kind == .local, let bd = w.trade(co) {
            let my = cos.reduce(0) { $0 + annualRevenue($1) }
            let riv = Rivals.rivals(s, for: co).map { r in Player(id: "r\(r.id)", name: r.name, revenue: Rivals.yearlyRevenue(bd, r, w, co), share: 0, rivalID: r.id) }
            let tot = my + riv.reduce(0) { $0 + $1.revenue }
            return Truth(mine: my, total: tot, share: tot > 0 ? my / tot : 0, players: riv.map { var p = $0; p.share = tot > 0 ? p.revenue / tot : 0; return p }.sorted { $0.revenue > $1.revenue })
        }
        let tot = nationalTotal(m, data: data)
        let my = min(tot * 0.95, cos.reduce(0) { $0 + size($1) })
        let c = data.countries[m.countryCode] ?? data.countries.countries[0]
        let rest = max(0, 1 - my / tot)
        let base = [0.31, 0.21, 0.14, 0.09]
        var players: [Player] = []
        for i in 0..<4 {
            var h = HashedRandom("\(s.seed):26f:\(m.type):\(m.countryCode):\(i)")
            var r = DeterministicRandom(seed: Int(h.next() * 1_000_000_000))
            let root = RivalGroups.brandRoot(c, family: "fin", &r)
            let sh = base[i] * (0.8 + h.next() * 0.4) * rest
            players.append(Player(id: "f\(m.type)\(m.countryCode)\(i)", name: root + " " + (national[m.type]?.word ?? "Group"), revenue: sh * tot, share: sh, rivalID: nil))
        }
        return Truth(mine: my, total: tot, share: my / tot, players: players)
    }

    /// Has a big player noticed you? A newcomer is invisible until it takes a real share. Original: `noticed`, `coShare`.
    static func noticed(_ s: GameState, _ co: Company, _ bd: Trade, _ w: World) -> Bool {
        guard co.status == .open else { return false }
        let mine = annualRevenue(co)
        let theirs = Rivals.rivals(s, for: co).reduce(0) { $0 + Rivals.yearlyRevenue(bd, $1, w, co) }
        let sh = mine > 0 ? mine / (mine + theirs) : 0
        let age = s.week - (co.openedWeek ?? co.foundedWeek)
        return (age >= 26 && sh >= 0.12) || sh >= 0.22 || !co.value("flags")["pw"].isNull
    }

    // MARK: Who is looking

    public struct Knowledge: Equatable {
        public enum Level: Int { case feeling = 0, dataAnalyst = 1, marketAnalyst = 2 }
        public var level: Level
        public var skill: Double
        public var name: String
        public var id: String
        public init(level: Level, skill: Double, name: String, id: String) { self.level = level; self.skill = skill; self.name = name; self.id = id }
        /// Nobody is measuring: only a feeling.
        public static let nobody = Knowledge(level: .feeling, skill: 0, name: "", id: "me")
    }

    /// A market analyst in one of the companies, else the head office's data analyst, else only a feeling. Original: `know`, `mktanOf`.
    public static func knowledge(_ s: GameState, _ m: Market) -> Knowledge {
        for id in m.companyIDs {
            if let co = s.company(id), let st = co.staff.first(where: { $0.role == "mktan" }) {
                let p = s.people[st.id]
                return Knowledge(level: .marketAnalyst, skill: clamp((p?.value("skill").double ?? 55) / 100, 0.2, 0.98), name: p?.name ?? "Your market analyst", id: String(st.id))
            }
        }
        return dataAnalyst(s) ?? .nobody
    }

    /// The head office's data analyst, if there is one. Original: `anaInfo`.
    public static func dataAnalyst(_ s: GameState) -> Knowledge? {
        guard let st = (s.rest["office"]?["staff"].array ?? []).first(where: { $0["role"].string == "ana" }) else { return nil }
        let p = s.people[st["id"].int]
        return Knowledge(level: .dataAnalyst, skill: clamp((p?.value("skill").double ?? 55) / 100 + (p?.value("exp").double ?? 0) * 0.01, 0.2, 0.98), name: p?.name ?? "Your data analyst", id: String(st["id"].int))
    }

    public struct Estimate: Equatable {
        public var level: Knowledge.Level
        public var center: Double, low: Double, high: Double
    }

    /// A share (0...1) as the person looking sees it this month. Original: `est`.
    public static func estimate(_ v: Double, key: String, _ k: Knowledge, seed: Int, week: Int) -> Estimate {
        let mi = week / 4
        let a = HashedRandom.first("\(seed):26:\(key):\(mi):\(k.id)"), b = HashedRandom.first("\(seed):26:\(key)b:\(mi):\(k.id)")
        switch k.level {
        case .marketAnalyst:
            let c = v * (1 + (a - 0.5) * 0.06 * (1 - k.skill)), w = max(0.002, v * (0.015 + (1 - k.skill) * 0.05))
            return Estimate(level: .marketAnalyst, center: c, low: max(0, c - w), high: min(1, c + w))
        case .dataAnalyst:
            let u = min(0.01, v * 0.3 + 0.0004)
            var w: Double, c: Double
            if k.skill >= 0.65 { w = v * (0.06 + (1 - k.skill) * 0.12) + u; c = v * (1 + (a - 0.5) * 0.05) }
            else if b < 0.5 { w = v * 0.08 + u; c = v * (1 + (a - 0.5) * 0.28) }
            else { w = v * 0.55 + u * 4; c = v }
            return Estimate(level: .dataAnalyst, center: c, low: max(0, c - w / 2), high: min(1, c + w / 2))
        case .feeling:
            let c = clamp(v * (0.6 + a * 0.8), 0, 1)
            return Estimate(level: .feeling, center: c, low: c, high: c)
        }
    }

    static func percent(_ x: Double) -> String {
        x < 0.001 ? "under 0.1%" : x < 0.1 ? String(format: "%.1f%%", (x * 1000).rounded() / 10) : "\(Int(jsRound(x * 100)))%"
    }

    /// An estimate in words or numbers, by who is looking. Original: `shTxt`, `guessW`.
    public static func text(_ e: Estimate) -> String {
        switch e.level {
        case .marketAnalyst: return percent(e.center)
        case .dataAnalyst:
            func f(_ x: Double) -> String { x < 0.1 ? String(format: "%.1f", (x * 1000).rounded() / 10) : "\(Int(jsRound(x * 100)))" }
            return f(e.low) == f(e.high) ? f(e.low) + "%" : f(e.low) + "–" + f(e.high) + "%"
        case .feeling:
            let g = e.center
            return g < 0.04 ? "A tiny slice" : g < 0.1 ? "A small slice" : g < 0.2 ? "A fair slice" : g < 0.35 ? "One of the big ones" : "The biggest, I think"
        }
    }

    public static func sizeComparison(rival rev: Double, mine: Double) -> String {
        mine <= 0 ? "Bigger than you" : rev > mine * 1.3 ? "Bigger than you" : rev < mine * 0.75 ? "Smaller than you" : "About your size"
    }

    // MARK: History and reports

    public static func history(_ s: GameState, key: String) -> [(month: Int, share: Double, total: Double)] {
        (s.rest["ms26"]?[key].array ?? []).map { ($0["m"].int, $0["s"].double, $0["tot"].double) }
    }

    /// One point a month per market, weekly sales per company, and a monthly report where a market analyst works. Original: `snap`, `sendReport`.
    public static func weekly(_ s: inout GameState, data: GameData) {
        for i in s.companies.indices where s.companies[i].status == .open {
            var L = s.companies[i].value("rv26").array
            L.append(.number(jsRound(s.companies[i].value("lastW")["rev"].double)))
            if L.count > 13 { L.removeFirst(L.count - 13) }
            s.companies[i].set("rv26", .array(L))
        }
        guard GameCalendar.isMonthEnd(week: s.week) else { return }
        payAnalysts(&s, data: data)
        let mi = s.week / 4
        var snaps = s.rest["ms26"] ?? .object([:])
        for m in markets(s, data: data) {
            let t = truth(s, m, data: data)
            var L = snaps[m.id].array
            if let last = L.last, last["m"].int == mi { L.removeLast() }
            L.append(.object(["m": .number(Double(mi)), "s": .number(jsRound(t.share * 10000) / 10000), "tot": .number(jsRound(t.total))]))
            if L.count > 24 { L.removeFirst(L.count - 24) }
            snaps[m.id] = .array(L)
        }
        s.rest["ms26"] = snaps
        for m in markets(s, data: data) {
            let k = knowledge(s, m)
            guard k.level == .marketAnalyst, let first = m.companyIDs.first else { continue }
            s.addMessage(from: k.name, title: "Market report: \(label(m, data: data, withCity: true))", body: report(s, m, k, data: data).joined(separator: " "), companyID: first)
        }
    }

    /// The lines of a market report. Original: `reportLines`.
    public static func report(_ s: GameState, _ m: Market, _ k: Knowledge, data: GameData) -> [String] {
        let t = truth(s, m, data: data), L = history(s, key: m.id)
        let e = estimate(t.share, key: "my" + m.id, k, seed: s.seed, week: s.week)
        var out: [String] = []
        let what = m.kind == .national ? "\(national[m.type]?.noun ?? "business") in \(data.countries[m.countryCode]?.name ?? m.countryCode)"
            : "\((data.catalog[m.type]?.name ?? m.type).lowercased()) sales in \(data.countries.city(m.cityID, preferring: m.countryCode)?.city.name ?? m.cityID)"
        var s1 = "Our share of \(what) is \(k.level == .marketAnalyst ? "about " : "")\(text(e))"
        if L.count >= 2, k.level == .marketAnalyst {
            let d = (t.share - L[L.count - 2].share) * 100
            s1 += abs(d) < 0.15 ? ", about the same as last month" : ", \(d > 0 ? "up" : "down") \(abs(d) < 1 ? String(format: "%.1f", abs(d)) : "\(Int(jsRound(abs(d))))") points on last month"
        }
        out.append(s1 + ".")
        if let big = t.players.first {
            out.append("Biggest rival: \(big.name) with \(text(estimate(big.share, key: "rv" + big.id, k, seed: s.seed, week: s.week))).")
        }
        if L.count >= 3, k.level == .marketAnalyst {
            let a = L[L.count - 3].share, b = L[L.count - 2].share, c = t.share
            if c < b - 0.003, b < a - 0.003 { out.append("Two months of lost ground in a row. Worth a look at prices, marketing and reviews.") }
            else if c > b + 0.003, b > a + 0.003 { out.append("Two months of growth in a row.") }
        }
        return out
    }

    // MARK: Hiring the analysts

    public struct HireVerdict: Equatable { public var ok: Bool, title: String, text: String }

    /// What a market analyst in this company gives instead of a capacity forecast. Original: `R26.mktanHire`.
    public static func analystHireVerdict(_ s: GameState, companyID: Int, data: GameData) -> HireVerdict {
        guard let co = s.company(companyID) else { return HireVerdict(ok: false, title: "Nothing to measure here", text: "") }
        let m = market(of: co, s, data: data)
        let has = co.staff.contains { $0.role == "mktan" }
        return HireVerdict(ok: m != nil && !has,
                           title: has ? "You already have a market analyst here" : m == nil ? "Nothing to measure here" : "Measures where you stand",
                           text: has ? "A second one adds cost, not insight." : m == nil ? "This kind of business has no market share to track."
                               : "Monthly reports on your market share; close numbers on the Market map. Sales stay the same.")
    }

    public static let dataAnalystRole = "ana"
    /// Monthly pay a data analyst in the head office starts from (before skill and the country). Original: `HQ_ROLES.ana`.
    static func dataAnalystBase(_ data: GameData) -> Double {
        let v = data.catalog.tables.raw["HQ_ROLES"]["ana"][1].double
        return v == 0 ? 64000 : v
    }

    public static func hasDataAnalyst(_ s: GameState) -> Bool { s.hasHeadOffice(dataAnalystRole) }

    /// Candidates for the head office's data analyst. Original: the head-office hiring screen for `ana`.
    public static func dataAnalystCandidates(_ s: inout GameState, count: Int = 4, data: GameData) -> [Person] {
        (0..<count).map { _ in
            var p = Hiring.generateCandidate(role: dataAnalystRole, company: nil, faces: false, state: &s, data: data)
            p.askingMonthlyWage = analystPay(state: s, data: data, skillFactor: 0.55 + p.skill / 110)
            s.people[p.id] = p
            return p
        }
    }

    /// `refused` is an insult with no figure named, `countered` names their own figure, `walkedAway` means the person took another job.
    public enum HQHire: Equatable { case ok, refused, taken, have, countered(Negotiation.Counter), walkedAway }

    /// The going monthly rate of a data analyst: the role's base pay in this economy, before anything about the person.
    public static func dataAnalystGoingRate(state s: GameState, data: GameData) -> Double {
        analystPay(state: s, data: data, skillFactor: 1)
    }

    /// The analyst's pay: the role's base times a skill factor (1 = the going rate), in this economy, to the hundred.
    static func analystPay(state s: GameState, data: GameData, skillFactor: Double) -> Double {
        (dataAnalystBase(data) * skillFactor * World(state: s, data: data).inflationIndex / 100).rounded() * 100
    }

    /// Hire the data analyst into the head office. At or above what they would settle for they accept; below it they counter, refuse or walk away.
    /// Original: `hireHQnpc`.
    public static func hireDataAnalyst(_ s: inout GameState, personID: Int, monthlyWage wage: Double, data: GameData) -> HQHire {
        if hasDataAnalyst(s) { return .have }
        guard let n0 = s.people[personID] else { return .refused }
        if n0.employerID != 0 { return .taken }
        switch Hiring.answer(personID: personID, employer: -3, rank: "analyst", offer: wage, currency: ManagerModel.playerCurrency(s, data), about: 100, state: &s).answer {
        case .refuse: return .refused
        case .walkAway: return .walkedAway
        case .counter(let c): return .countered(c)
        case .accept: break
        }
        guard var n = s.people[personID] else { return .refused }
        n.employerID = -3
        s.people[personID] = n
        var office = s.rest["office"] ?? .object(["tier": "home", "since": .number(Double(s.week)), "staff": .array([])])
        var staff = office["staff"].array
        staff.append(.object(["id": .number(Double(personID)), "role": .string(dataAnalystRole), "name": .string(n.name), "wage": .number(wage),
                              "w0": .number(Double(s.week)), "onb": .object([:]), "by": "mm"]))
        office["staff"] = .array(staff)
        s.rest["office"] = office
        return .ok
    }

    @discardableResult
    public static func fireDataAnalyst(_ s: inout GameState) -> Bool {
        guard var office = s.rest["office"], office["staff"].array.contains(where: { $0["role"].string == dataAnalystRole }) else { return false }
        for st in office["staff"].array where st["role"].string == dataAnalystRole {
            if var p = s.people[st["id"].int] { p.employerID = 0; s.people[p.id] = p }
        }
        office["staff"] = .array(office["staff"].array.filter { $0["role"].string != dataAnalystRole })
        s.rest["office"] = office
        return true
    }

    /// Pay head-office analysts hired here once a month. Original: `officeMonth` (staff part).
    static func payAnalysts(_ s: inout GameState, data: GameData) {
        let home = data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode)
        for st in s.rest["office"]?["staff"].array ?? [] where st["by"].string == "mm" {
            Payments.playerPays(&s, jsRound(st["wage"].double * home.employerCostFactor), label: "Head office: data analyst")
        }
    }

    // MARK: Reports on request

    /// Ask the market analyst for this month's report now; one every two weeks at most. Returns the reason it did not happen. Original: `ACT.mkt26rep`.
    public static func orderMarketReport(_ s: inout GameState, marketKey: String, data: GameData) -> String? {
        guard let m = markets(s, data: data).first(where: { $0.id == marketKey }) else { return "You are no longer in this market." }
        let k = knowledge(s, m)
        guard k.level == .marketAnalyst, let cid = m.companyIDs.first(where: { s.company($0)?.staff.contains { $0.role == "mktan" } ?? false }) ?? m.companyIDs.first,
              let i = s.companyIndex(cid) else { return "Only a market analyst writes these." }
        if s.week - (s.companies[i].value("mq26").isNull ? -99 : s.companies[i].int("mq26")) < 2 { return "Your analyst sent one last week. Give it a little time." }
        s.companies[i].set("mq26", s.week)
        s.addMessage(from: k.name, title: "Market report: \(label(m, data: data, withCity: true))", body: report(s, m, k, data: data).joined(separator: " "), companyID: cid)
        return nil
    }

    /// A report from the head-office data analyst on one company or all of them, sent as a message. Original: `analystReport` (meetings.js);
    /// without the brand-lift estimate and the two-month forecast, which need the marketing outlook.
    public static func dataAnalystReport(_ s: inout GameState, companyID: Int?, data: GameData) -> String? {
        guard hasDataAnalyst(s) else { return "You need a data analyst in the head office." }
        let cos = s.companies.filter { $0.status == .open && (companyID == nil || $0.id == companyID) }
        guard !cos.isEmpty else { return "Nothing to report on." }
        var body: [String] = []
        for co in cos {
            let h = co.value("rv26").array.map { $0.double }
            var ln: [String] = []
            if h.count >= 8 {
                let a = h.suffix(4).reduce(0, +) / 4, bs = Array(h.suffix(8).prefix(4)), b = bs.reduce(0, +) / Double(max(1, bs.count))
                if b > 0 { ln.append("Sales over the last four weeks are \(a >= b ? "up" : "down") \(Int(jsRound(abs(a / b - 1) * 100)))% on the four before.") }
            }
            let u = co.value("lastW")["util"]
            if !u.isNull { ln.append(u.double > 0.95 ? "We are at the limit of what we can deliver and turn people away." : u.double < 0.5 ? "We use less than half our capacity." : "We use about \(Int(jsRound(u.double * 100)))% of our capacity.") }
            if let m = market(of: co, s, data: data) {
                let t = truth(s, m, data: data), kk = knowledge(s, m)
                ln.append("Our share of the market is \(text(estimate(t.share, key: "my" + m.id, kk, seed: s.seed, week: s.week))).")
            }
            body.append("\(co.name): " + ln.joined(separator: " "))
        }
        let who = knowledge(s, Market(id: "", kind: .local, type: "", cityID: "", countryCode: "", companyIDs: [])).name
        s.addMessage(from: who.isEmpty ? "Data analyst" : who, title: companyID == nil ? "Report: all companies" : "Report: \(cos[0].name)", body: body.joined(separator: "\n"))
        return nil
    }

    // MARK: Weight in the economy

    public struct Weight: Equatable {
        public var jobs: Int
        public var debt: Double
        public var loanShare: Double
        public var biggestShare: Double
        /// "Low", "Watching", "Rising" or "High": how closely the competition authority looks, with a tone (pos, amb, neg or empty).
        public var attention: String
        public var tone: String
    }

    /// Share of all business loans, jobs you provide and how closely the regulator watches. Original: `weight`, `attention`.
    public static func weight(_ s: GameState, data: GameData) -> Weight {
        let live = s.companies.filter { $0.status == .open || $0.status == .closed }
        let jobs = live.reduce(0) { $0 + $1.staff.count + ($1.managerID != nil ? 1 : 0) + ($1.value("asst")["npc"].int != 0 ? 1 : 0) } + (s.rest["office"]?["staff"].array.count ?? 0)
        let debt = s.loans.reduce(0) { $0 + $1.balance }
        let c = data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode)
        let nat = max(1, c.populationMillions * 1e6 * 160_000 * pow(c.marketStrength, 2) * c.priceLevel)
        let top = markets(s, data: data).map { truth(s, $0, data: data).share }.max() ?? 0
        let a: (String, String) = top >= 0.35 ? ("High", "neg") : top >= 0.2 ? ("Rising", "amb") : top >= 0.1 ? ("Watching", "") : ("Low", "pos")
        return Weight(jobs: jobs, debt: debt, loanShare: debt / nat, biggestShare: top, attention: a.0, tone: a.1)
    }
}
