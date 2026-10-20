import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// The player's own goals and how they are tracked: the daily goal with its streak, the first-steps checklist, and the
/// ambition paths with their milestones and legacy score. State lives in `rest["dy59"]`, `rest["fs58"]`, `rest["amb27"]`.
/// Originals: features/player/daily_goals.js (`DY59`), first_steps.js (`FS58`), ambitions.js (`R27` amb).
public enum PlayerGoals {
    // MARK: Shared facts

    static func live(_ s: GameState) -> [Company] { s.companies.filter { $0.status == .open && $0.type != "hold" } }
    static func staffCount(_ s: GameState) -> Int { live(s).reduce(0) { $0 + $1.staff.count + ($1.managerID != nil ? 1 : 0) } }
    static func openComplaints(_ s: GameState) -> Int { live(s).reduce(0) { $0 + Satisfaction.openComplaints($1).count } }

    // MARK: Daily goal

    public struct DailyGoal: Equatable, Sendable {
        public var id: String, title: String, progress: String
        public var done: Bool, claimed: Bool
        public var reward: Double
        /// Days in a row including today once claimed.
        public var streak: Int
    }

    static let dailyIDs: [(id: String, title: String)] = [
        ("start", "Open your first business"), ("weeks", "Play two weeks"), ("hire", "Hire someone"),
        ("cmp", "Answer the complaints waiting"), ("grow", "Grow your net worth by 1%")]

    static func dailyFits(_ id: String, _ s: GameState) -> Bool {
        switch id {
        case "start": return live(s).isEmpty
        case "weeks", "grow": return !live(s).isEmpty
        case "hire": return live(s).contains { $0.managerID == nil }
        case "cmp": return openComplaints(s) > 0
        default: return false
        }
    }

    static func dailyDone(_ id: String, _ b: JSONValue, _ s: GameState, nw: Double) -> Bool {
        switch id {
        case "start": return !live(s).isEmpty
        case "weeks": return s.week - b["week"].int >= 2
        case "hire": return staffCount(s) > b["staff"].int
        case "cmp": return openComplaints(s) < b["cmp"].int
        case "grow": return b["nw"].double > 0 && nw >= b["nw"].double * 1.01
        default: return false
        }
    }

    static func dailyProgress(_ id: String, _ b: JSONValue, _ s: GameState, nw: Double, _ cur: Currency) -> String {
        switch id {
        case "start": return live(s).isEmpty ? "Not yet" : "Open"
        case "weeks": return "\(min(2, s.week - b["week"].int)) of 2 weeks"
        case "hire": return staffCount(s) > b["staff"].int ? "Done" : "Not yet"
        case "cmp": return "\(openComplaints(s)) still open"
        case "grow": return (nw >= b["nw"].double ? "+" : "-") + cur.display(abs(nw - b["nw"].double)) + " of " + cur.display(b["nw"].double * 0.01) + " so far"
        default: return ""
        }
    }

    /// Today's goal; a new one is picked when the real day changes. `today` and `yesterday` are "yyyy-m-d" (the phone's own date).
    public static func dailyGoal(_ s: inout GameState, today: String, yesterday: String, data: GameData, currency cur: Currency) -> DailyGoal? {
        var d = s.rest["dy59"] ?? .object(["streak": 0, "last": ""])
        let nw = Valuation.netWorth(s, trades: data.catalog).total
        if d["d"].string != today {
            let fit = dailyIDs.filter { dailyFits($0.id, s) }
            let h = today.split(separator: "-").reduce(7) { ($0 * 31 + (Int($1) ?? 0)) & 0x7fffffff }
            d["d"] = .string(today); d["got"] = 0
            d["k"] = .string(fit.isEmpty ? "weeks" : fit[h % fit.count].id)
            d["b"] = .object(["week": .number(Double(s.week)), "staff": .number(Double(staffCount(s))), "cmp": .number(Double(openComplaints(s))), "nw": .number(nw)])
            s.rest["dy59"] = d
        }
        let id = d["k"].string
        guard let g = dailyIDs.first(where: { $0.id == id }) ?? dailyIDs.first(where: { $0.id == "weeks" }) else { return nil }
        let streak = d["last"].string == yesterday || d["last"].string == today ? d["streak"].int : 0
        let reward = cur.roundedStep(max(cur.scaledPrice(2500), nw * 0.0005) * Double(min(7, streak + 1)), about: 500)
        return DailyGoal(id: g.id, title: g.title, progress: dailyProgress(g.id, d["b"], s, nw: nw, cur), done: dailyDone(g.id, d["b"], s, nw: nw),
                         claimed: d["got"].int != 0, reward: reward, streak: streak)
    }

    /// Claim the daily reward. Original: `ACT.dy59claim`.
    @discardableResult
    public static func claimDailyGoal(_ s: inout GameState, today: String, yesterday: String, data: GameData, currency cur: Currency) -> Double? {
        guard let g = dailyGoal(&s, today: today, yesterday: yesterday, data: data, currency: cur), g.done, !g.claimed else { return nil }
        var d = s.rest["dy59"] ?? .object([:])
        d["streak"] = .number(Double(g.streak + 1)); d["last"] = .string(today); d["got"] = 1
        s.rest["dy59"] = d
        Payments.playerReceives(&s, g.reward, label: "Daily goal reached")
        return g.reward
    }

    // MARK: First steps

    public struct FirstStep: Equatable, Sendable {
        public var id: String, title: String, how: String, reward: String
        public var done: Bool, claimed: Bool
    }

    static let stepList: [(id: String, title: String, how: String, reward: String)] = [
        ("co", "Start a business", "New company: pick a trade. The small ones are cheap to start.", "A start-up grant from the town"),
        ("staff", "Hire your first worker", "In the company: Manage, Find workers. Check what they claim before you hire.", "The job centre pays a month of payroll tax"),
        ("open", "Open the doors", "Papers, premises, equipment and people in place: it opens by itself.", "The local paper writes about you"),
        ("week", "Read your week report", "Play until the week ends; the report shows what happened and where the money went.", "The bank likes what it sees"),
        ("sell", "Choose how you sell", "Sales: who you are for, and what else you offer. Or set your prices.", "Word gets around"),
        ("ad", "Run an ad", "Sales, Marketing: even a small campaign brings people in.", "The ad agency refunds your first week"),
        ("inbox", "Answer a decision", "Inbox: problems and offers wait there for your answer.", "People learn they can count on you"),
        ("pay", "Pay yourself", "Money: a salary, a dividend, or take money out. Leave enough for the bills.", "Your accountant's first month is free"),
        ("profit", "Make a profit in a month", "Keep the costs in check and the customers coming.", "Better terms from the bank"),
        ("mgr", "Hire a manager or an assistant", "Manage, Management: they run it day to day while you grow.", "The agency waives its fee"),
    ]

    static func stepsLive(_ s: GameState) -> [Company] { s.companies.filter { $0.status.isLive && $0.type != "hold" } }

    static func stepDone(_ id: String, _ s: GameState) -> Bool {
        let L = stepsLive(s)
        switch id {
        case "co": return !L.isEmpty
        case "staff": return L.contains { !$0.staff.isEmpty }
        case "open": return L.contains { $0.status == .open }
        case "week": return !((s.rest["reports"]?["week"] ?? .null).array.isEmpty)
        case "sell": return L.contains { $0.priceLevel != 0 || $0.value("knob").object.values.contains { $0.double != 0 } }
        case "ad": return L.contains { $0.value("mkt").object.values.contains { $0["b"].double > 0 } }
        case "inbox": return s.inbox.contains { !$0.options.isEmpty && !$0.value("pick").isNull }
        case "pay": return L.contains { $0.ownerMonthlySalary > 0 || $0.distributed > 0 }
        case "profit": return L.contains { $0.monthlyHistory.contains { $0.profit > 0 } }
        case "mgr": return L.contains { $0.managerID != nil || !$0.value("asst").isNull }
        default: return false
        }
    }

    /// Start the checklist on a new game (older saves do not get it). Original: `FS58.start`.
    public static func startFirstSteps(_ s: inout GameState) { s.rest["fs58"] = .object(["got": .object([:]), "off": 0, "w0": .number(Double(s.week))]) }

    public static func firstSteps(_ s: GameState) -> [FirstStep]? {
        guard let st = s.rest["fs58"] else { return nil }
        return stepList.map { FirstStep(id: $0.id, title: $0.title, how: $0.how, reward: $0.reward, done: stepDone($0.id, s), claimed: !st["got"][$0.id].isNull) }
    }
    public static func firstStepsHidden(_ s: GameState) -> Bool { s.rest["fs58"]?["off"].int ?? 1 != 0 }

    /// Claim the reward of a finished step; returns the line to show. Original: `FS58.claim`, `ACT.fs58claim`.
    public static func claimFirstStep(_ s: inout GameState, id: String, currency cur: Currency) -> String? {
        guard var st = s.rest["fs58"], st["got"][id].isNull, stepList.contains(where: { $0.id == id }), stepDone(id, s) else { return nil }
        var got = st["got"]; got[id] = .object(["w": .number(Double(s.week))]); st["got"] = got; s.rest["fs58"] = st
        func cash(_ v: Double, _ why: String) -> String { let a = cur.scaledPrice(v); Payments.playerReceives(&s, a, label: why); return cur.display(a) }
        func each(_ f: (inout Company) -> Void) { for i in s.companies.indices where s.companies[i].status.isLive && s.companies[i].type != "hold" { f(&s.companies[i]) } }
        switch id {
        case "co": return "The town gives new businesses a small grant: \(cash(25000, "Start-up grant from the town"))."
        case "staff": return "The job centre pays a month of payroll tax for your first hire: \(cash(6000, "Job centre: first hire"))."
        case "open":
            var name = "you"
            if let i = s.companies.firstIndex(where: { $0.status == .open && $0.type != "hold" }) { s.companies[i].awareness = min(100, s.companies[i].awareness + 8); name = s.companies[i].name }
            return "The local paper writes about \(name): more people know the name."
        case "week": s.credit = min(100, s.credit + 3); return "The bank likes a good start: your credit score is a little better."
        case "sell":
            if let i = s.companies.firstIndex(where: { $0.status.isLive && $0.type != "hold" && ($0.priceLevel != 0 || $0.value("knob").object.values.contains { $0.double != 0 }) }) { s.companies[i].awareness = min(100, s.companies[i].awareness + 5) }
            return "People talk about what you offer: more of them know the name."
        case "ad": return "The ad agency refunds your first week: \(cash(3000, "Ad agency: first week refunded"))."
        case "inbox": each { $0.reputation = min(100, $0.reputation + 1) }; return "People learn they can count on you: a little better reputation."
        case "pay": return "Your accountant waives the first month: \(cash(2500, "Accountant: first month free"))."
        case "profit": s.credit = min(100, s.credit + 5); return "A profitable month: the bank offers you better terms."
        default: return "The recruitment agency waives its fee for your first hire: \(cash(15000, "Recruitment agency: fee waived"))."
        }
    }

    public static func setFirstStepsHidden(_ s: inout GameState, _ hidden: Bool) {
        guard var st = s.rest["fs58"] else { return }
        st["off"] = hidden ? 1 : 0
        s.rest["fs58"] = st
    }

    // MARK: Ambitions

    public struct Milestone: Equatable, Sendable { public var id: String, text: String, now: Double, target: Double, reachedWeek: Int?; public var done: Bool { reachedWeek != nil } }
    public struct AmbitionPath: Equatable, Sendable { public var id: String, name: String, summary: String, perk: String }

    static let paths: [AmbitionPath] = [
        AmbitionPath(id: "titan", name: "Industrial titan", summary: "Build a chain of companies that feed each other: materials, production, transport, sales.", perk: "Group trade: your suppliers work 5, 8 or 12% cheaper for your own companies."),
        AmbitionPath(id: "dynasty", name: "Family dynasty", summary: "Own your companies outright, keep control, pay yourself well and never go bust.", perk: "Loyalty: lenders trust you (0.2 to 0.5 points lower interest)."),
        AmbitionPath(id: "dominator", name: "Market dominator", summary: "Be the biggest name in your markets: win share, buy rivals, outlast price wars.", perk: "Deal maker: rivals sell to you about 5, 8 or 12% cheaper."),
        AmbitionPath(id: "champion", name: "Hidden champion", summary: "Small, excellent and very profitable. The best reviews and margins nobody else gets.", perk: "Craft: quality settles 2, 3 or 4 points higher in all your companies."),
        AmbitionPath(id: "financier", name: "Financier", summary: "Make money with money: a holding company, a bank, investments and stakes.", perk: "Credit: you borrow 0.3, 0.5 or 0.8 points cheaper."),
        AmbitionPath(id: "global", name: "Global group", summary: "Plant your flag in many countries. More markets, more currencies, more rules to follow.", perk: "Global reach: setting up abroad costs 20, 35 or 50% less."),
    ]
    public static var ambitionPaths: [AmbitionPath] { paths }
    static let points = [10, 25, 60], tierBonus = [50, 150, 400]

    struct Facts {
        var s: GameState, data: GameData, cur: Currency
        var liveCos: [Company]
        func annual(_ c: Company) -> Double { MarketMap.annualRevenue(c) }
        var rev: Double { liveCos.reduce(0) { $0 + annual($1) * $1.ownership / 100 } }
        var jobs: Double { liveCos.reduce(0) { $0 + Double($1.staff.count + ($1.managerID != nil ? 1 : 0)) } + Double(s.rest["office"]?["staff"].array.count ?? 0) }
        var nw: Double { Valuation.netWorth(s, trades: data.catalog).total }
        var links: Double { Double(IntercompanySupply.links(s).count) }
        var fams: Double { Double(Set(liveCos.compactMap { data.catalog[$0.type]?.family }).count) }
        var prodOwn: Bool { liveCos.contains { ["prod", "project"].contains(data.catalog[$0.type]?.family ?? "") } }
        func ebit(_ c: Company) -> Double { CompanyFigures.yearlyProfitEstimate(c, currentWeek: s.week) }
        var full: Double { Double(liveCos.filter { $0.type != "hold" && $0.ownership >= 99.9 && ebit($0) > 0 }.count) }
        var dividends: Double { s.stats.dividendsReceived }
        var years: Double { Double(s.week) / 52 }
        var control: Bool { liveCos.allSatisfy { $0.ownership >= 67 } }
        func rated(_ min: Double, _ n: Int) -> Double { Double(liveCos.filter { $0.value("rvN").int >= n && Pricing.rating($0) >= min }.count) }
        func marginBest(_ minRev: Double) -> Double { liveCos.map { c in let r = annual(c); return r >= minRev && r > 0 ? ebit(c) / r : 0 }.max() ?? 0 }
        var profitPerPerson: Double { liveCos.reduce(0) { $0 + ebit($1) * $1.ownership / 100 } / max(1, jobs) }
        var countries: Double { Double(Set(liveCos.map(\.countryCode)).count) }
        var abroad: Bool { liveCos.contains { $0.countryCode != s.homeCountryCode } }
        var abroadShare: Double { rev > 0 ? liveCos.filter { $0.countryCode != s.homeCountryCode }.reduce(0) { $0 + annual($1) * $1.ownership / 100 } / rev : 0 }
        func has(_ t: String) -> Bool { liveCos.contains { $0.type == t && $0.status == .open } }
        var listedHold: Bool { liveCos.contains { $0.type == "hold" && $0.flag("listed") } }
        var portfolio: Double { let n = Valuation.netWorth(s, trades: data.catalog); return n.stocks + n.crypto + n.funds }
        var stakes: Double { Double((s.rest["startups"]?.array ?? []).filter { $0["st"].string != "exit" && $0["pct"].double > 0 }.count) }
        var franchAbroad: Bool { liveCos.contains { $0.countryCode != s.homeCountryCode && (!$0.value("franchise").isNull || !$0.value("foreignOf").isNull || !$0.value("branch").isNull) } }
    }

    struct MS { var id: String; var text: (Double) -> String; var prog: (Facts, Double) -> (Double, Double) }
    static func d(_ id: String, _ text: @escaping (Double) -> String, _ prog: @escaping (Facts, Double) -> (Double, Double)) -> MS { MS(id: id, text: text, prog: prog) }
    static func flag(_ b: Bool) -> (Double, Double) { (b ? 1 : 0, 1) }

    /// Milestones per tier of a path. `f` multiplies the targets past tier III so a path never runs out.
    static func tierMilestones(_ k: String, _ tier: Int, _ cur: Currency) -> [MS] {
        func m(_ v: Double) -> String { cur.display(cur.scaledPrice(v)) }
        func K(_ v: Double) -> Double { cur.scaledPrice(v) }
        func n(_ v: Double) -> String { String(Int(v)) }
        let t = min(2, tier)
        switch k {
        case "titan": return [
            [d("t1a", { _ in "Own a production or building company" }, { f, _ in flag(f.prodOwn) }), d("t1b", { _ in "Two of your companies supply each other" }, { f, _ in (f.links, 2) }),
             d("t1c", { _ in "Group sales of \(m(30e6)) a year" }, { f, _ in (f.rev, K(30e6)) }), d("t1d", { _ in "50 people work for you" }, { f, _ in (f.jobs, 50) })],
            [d("t2a", { _ in "Four supply links inside the group" }, { f, _ in (f.links, 4) }), d("t2b", { _ in "Companies in three different kinds of business" }, { f, _ in (f.fams, 3) }),
             d("t2c", { _ in "Group sales of \(m(200e6)) a year" }, { f, _ in (f.rev, K(200e6)) }), d("t2d", { _ in "300 people work for you" }, { f, _ in (f.jobs, 300) })],
            [d("t3a", { x in "\(n(8 * x)) supply links inside the group" }, { f, x in (f.links, 8 * x) }), d("t3b", { x in "Group sales of \(m(1e9 * x)) a year" }, { f, x in (f.rev, K(1e9 * x)) }),
             d("t3c", { x in "\(n(1500 * x)) people work for you" }, { f, x in (f.jobs, 1500 * x) })]][t]
        case "dynasty": return [
            [d("d1a", { _ in "Own all of two profitable companies" }, { f, _ in (f.full, 2) }), d("d1b", { _ in "Pay yourself \(m(2e6)) in dividends" }, { f, _ in (f.dividends, K(2e6)) }),
             d("d1c", { _ in "Three years without a bankruptcy" }, { f, _ in (min(3, (Double(f.s.week) - max(0, f.s.stats.raw["bustW"]?.double ?? 0)) / 52), 3) }),
             d("d1d", { _ in "Keep at least two thirds of every company" }, { f, _ in flag(f.control && !f.liveCos.isEmpty) })],
            [d("d2a", { _ in "Own all of four profitable companies" }, { f, _ in (f.full, 4) }), d("d2b", { _ in "Pay yourself \(m(20e6)) in dividends" }, { f, _ in (f.dividends, K(20e6)) }),
             d("d2c", { _ in "Ten years in business" }, { f, _ in (f.years, 10) }), d("d2d", { _ in "Net worth of \(m(100e6))" }, { f, _ in (f.nw, K(100e6)) })],
            [d("d3a", { x in "Pay yourself \(m(150e6 * x)) in dividends" }, { f, x in (f.dividends, K(150e6 * x)) }), d("d3b", { x in "Net worth of \(m(1e9 * x))" }, { f, x in (f.nw, K(1e9 * x)) }),
             d("d3c", { _ in "Still two thirds of every company (four or more)" }, { f, _ in flag(f.control && f.liveCos.count >= 4) })]][t]
        case "dominator": return [
            [d("m1c", { _ in "Buy a rival" }, { f, _ in (f.s.rest["amb27"]?["cnt"]["buy"].double ?? 0, 1) })],
            [d("m2c", { _ in "Win a price war" }, { f, _ in (f.s.rest["amb27"]?["cnt"]["pw"].double ?? 0, 1) }), d("m2d", { _ in "Buy three rivals" }, { f, _ in (f.s.rest["amb27"]?["cnt"]["buy"].double ?? 0, 3) })],
            [d("m3d", { x in "Buy \(n(5 * x)) rivals" }, { f, x in (f.s.rest["amb27"]?["cnt"]["buy"].double ?? 0, 5 * x) })]][t]
        case "champion": return [
            [d("h1a", { _ in "A company rated 4.3 or better (50+ reviews)" }, { f, _ in (f.rated(4.3, 50), 1) }), d("h1b", { _ in "A 20% profit margin over a year" }, { f, _ in (f.marginBest(K(1e6)) * 100, 20) }),
             d("h1c", { _ in "Profit of \(m(300000)) per person working for you" }, { f, _ in (f.profitPerPerson, K(300000)) })],
            [d("h2a", { _ in "A company rated 4.6 or better (200+ reviews)" }, { f, _ in (f.rated(4.6, 200), 1) }), d("h2b", { _ in "A 30% margin with sales over \(m(10e6))" }, { f, _ in (f.marginBest(K(10e6)) * 100, 30) }),
             d("h2c", { _ in "A company abroad" }, { f, _ in flag(f.abroad) }), d("h2d", { _ in "Profit of \(m(700000)) per person" }, { f, _ in (f.profitPerPerson, K(700000)) })],
            [d("h3a", { x in "\(n(3 * x)) companies rated 4.5 or better" }, { f, x in (f.rated(4.5, 200), 3 * x) }), d("h3b", { x in "A 35% margin with sales over \(m(50e6 * x))" }, { f, x in (f.marginBest(K(50e6 * x)) * 100, 35) }),
             d("h3c", { x in "Profit of \(m(1.5e6 * x)) per person" }, { f, x in (f.profitPerPerson, K(1.5e6 * x)) })]][t]
        case "financier": return [
            [d("f1a", { _ in "Own a holding company" }, { f, _ in flag(f.has("hold")) }), d("f1b", { _ in "Investments worth \(m(5e6))" }, { f, _ in (f.portfolio, K(5e6)) }),
             d("f1c", { _ in "Own a bank, insurer or fund" }, { f, _ in flag(f.has("bank") || f.has("insco") || f.has("fund")) })],
            [d("f2a", { _ in "Own a bank" }, { f, _ in flag(f.has("bank")) }), d("f2c", { _ in "A listed holding company" }, { f, _ in flag(f.listedHold) }),
             d("f2d", { _ in "Investments worth \(m(100e6))" }, { f, _ in (f.portfolio, K(100e6)) })],
            [d("f3b", { x in "Net worth of \(m(2e9 * x))" }, { f, x in (f.nw, K(2e9 * x)) }), d("f3c", { x in "Stakes in \(n(5 * x)) startups" }, { f, x in (f.stakes, 5 * x) })]][t]
        default: return [
            [d("g1a", { _ in "Companies in two countries" }, { f, _ in (f.countries, 2) }), d("g1b", { _ in "A franchise or branch abroad" }, { f, _ in flag(f.franchAbroad) }),
             d("g1c", { _ in "Group sales of \(m(20e6)) a year" }, { f, _ in (f.rev, K(20e6)) })],
            [d("g2a", { _ in "Companies in four countries" }, { f, _ in (f.countries, 4) }), d("g2b", { _ in "30% of sales from abroad" }, { f, _ in (f.abroadShare * 100, 30) })],
            [d("g3a", { x in "Companies in \(n(min(15, 8 + 3 * (x > 1 ? log(x) / log(3) : 0)))) countries" }, { f, x in (f.countries, min(15, 8 + 3 * (x > 1 ? log(x) / log(3) : 0))) }),
             d("g3c", { x in "Group sales of \(m(2e9 * x)) a year" }, { f, x in (f.rev, K(2e9 * x)) })]][t]
        }
    }

    static func ambition(_ s: GameState) -> JSONValue {
        s.rest["amb27"] ?? .object(["path": .null, "tier": .object([:]), "done": .object([:]), "score": 0, "since": 0, "cnt": .object(["buy": 0, "pw": 0, "bankfin": 0, "ipo": 0]), "hist": .array([]), "ask": 0])
    }
    public static func ambitionPath(_ s: GameState) -> String? { let p = ambition(s)["path"]; return p.isNull ? nil : p.string }
    public static func legacyScore(_ s: GameState) -> Int { ambition(s)["score"].int }
    public static func ambitionTier(_ s: GameState, _ k: String) -> Int { ambition(s)["tier"][k].int }

    /// The milestones of the current level of the chosen path, with progress.
    public static func milestones(_ s: GameState, data: GameData, currency cur: Currency) -> [Milestone] {
        guard let k = ambitionPath(s) else { return [] }
        let a = ambition(s), t = ambitionTier(s, k)
        let x = t < 3 ? 1.0 : pow(3, Double(t - 2))
        let facts = Facts(s: s, data: data, cur: cur, liveCos: s.companies.filter { $0.status == .open || $0.status == .closed })
        return tierMilestones(k, t, cur).map { m in
            let id = t < 3 ? m.id : "\(m.id)_\(t)"
            let p = m.prog(facts, x)
            return Milestone(id: id, text: m.text(x), now: p.0, target: p.1, reachedWeek: a["done"][id].isNull ? nil : a["done"][id].int)
        }
    }

    /// Perk level (0-2) of a path, or nil if it is not the chosen path or the player is still settling in. Original: `R27.perk`.
    public static func perk(_ s: GameState, _ k: String, data: GameData) -> Int? {
        let a = ambition(s)
        guard ambitionPath(s) == k, s.week >= a["settle"].int else { return nil }
        let t = ambitionTier(s, k)
        let done = tierMilestonesDone(s, k, t, data: data)
        return min(2, t > 0 ? t - 1 + (done ? 1 : 0) : 0)
    }
    static func tierMilestonesDone(_ s: GameState, _ k: String, _ t: Int, data: GameData) -> Bool {
        let a = ambition(s)
        let cur = Currency(country: data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode), rates: ExchangeRates())
        return tierMilestones(k, t, cur).allSatisfy { !a["done"][t < 3 ? $0.id : "\($0.id)_\(t)"].isNull }
    }

    /// Choose or switch the path. A switch keeps what was reached; the new perk starts in half a year. Original: `ACT.amb27pick`.
    @discardableResult
    public static func chooseAmbition(_ s: inout GameState, path k: String, data: GameData, currency cur: Currency) -> Bool {
        guard paths.contains(where: { $0.id == k }) else { return false }
        var a = ambition(s)
        let switching = !a["path"].isNull
        a["path"] = .string(k); a["since"] = .number(Double(s.week))
        a["settle"] = .number(Double(!a["hist"].array.filter { !$0["path"].isNull }.isEmpty || a["was"].int != 0 ? s.week + 26 : 0))
        a["was"] = 1
        var tiers = a["tier"]; if tiers[k].isNull { tiers[k] = 0 }; a["tier"] = tiers
        s.rest["amb27"] = a
        _ = switching
        checkAmbition(&s, data: data, currency: cur)
        return true
    }

    /// Mark reached milestones and finish a level when all are reached. Original: `check`.
    static func checkAmbition(_ s: inout GameState, data: GameData, currency cur: Currency) {
        guard let k = ambitionPath(s) else { return }
        var a = ambition(s)
        let t = ambitionTier(s, k)
        let ms = milestones(s, data: data, currency: cur)
        let name = paths.first { $0.id == k }?.name ?? k
        let roman = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
        func log(_ text: String, _ pts: Int) {
            var h = a["hist"].array
            h.insert(.object(["w": .number(Double(s.week)), "t": .string(text), "path": .string(k), "pts": .number(Double(pts))]), at: 0)
            a["hist"] = .array(Array(h.prefix(40)))
        }
        for m in ms where !m.done && m.target > 0 && m.now >= m.target {
            var done = a["done"]; done[m.id] = .number(Double(s.week)); a["done"] = done
            let pts = points[min(2, t)] * (t > 2 ? t - 1 : 1)
            a["score"] = .number(Double(a["score"].int + pts))
            log(m.text, pts)
            s.addMessage(kind: "info", from: "Ambition", title: "Milestone: \(m.text)", body: "\(name) \(roman[min(9, t)]). +\(pts) legacy points.", tone: "good")
        }
        if ms.allSatisfy({ !a["done"][$0.id].isNull }) {
            let bonus = tierBonus[min(2, t)] * (t > 2 ? t - 1 : 1)
            a["score"] = .number(Double(a["score"].int + bonus))
            var tiers = a["tier"]; tiers[k] = .number(Double(t + 1)); a["tier"] = tiers
            log("\(name) \(roman[min(9, t)]) complete", bonus)
            s.news("\(s.player.name) reaches \(name.lowercased()) level \(roman[min(9, t)]).", tone: "good")
            s.addMessage(kind: "info", from: "Ambition", title: "\(name) \(roman[min(9, t)]) complete", body: "+\(bonus) legacy points. The next level asks for more.", tone: "good")
        }
        s.rest["amb27"] = a
    }

    /// Count a bought rival or a won price war for the market dominator path.
    public static func count(_ s: inout GameState, _ key: String) {
        var a = ambition(s)
        var c = a["cnt"]; c[key] = .number(c[key].double + 1); a["cnt"] = c
        s.rest["amb27"] = a
    }

    /// Weekly: check milestones every four weeks, and once a business runs, ask what the player wants to build. Original: 'ambitions weekly'.
    static func weekly(_ s: inout GameState, data: GameData, currency cur: Currency) {
        if s.week % 4 == 0 { checkAmbition(&s, data: data, currency: cur) }
        var a = ambition(s)
        if a["path"].isNull, a["ask"].int == 0, s.companies.contains(where: { $0.status == .open }), s.week > 4 {
            a["ask"] = .number(Double(s.week)); s.rest["amb27"] = a
            s.addMessage(kind: "info", from: "Ambition", title: "What do you want to build?",
                         body: "Pick an ambition: an industrial group, a family dynasty, the market leader, a hidden champion, a financier or a global group. Each rewards a different way to play and gives a perk.")
        }
    }
}
