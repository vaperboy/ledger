import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Events

/// The career: a rank title (Street Vendor to Tycoon) and an open-ended goal ladder that always shows the next short, medium and long goal.
/// It works in every save (it reads facts, never gates anything) and sits after the ten-step guide ladder (`PlayerGoals.ladder`).
/// State: `rest["car"]` = { done: { id: week }, rk: rank index celebrated, cos: [cosmetic ids] }; written only when something is earned.
public enum Career {
    // MARK: Ranks

    public struct Rank: Equatable, Sendable {
        public var index: Int
        public var title: String
        /// Net worth needed, before scaling to the player's currency.
        public var netWorth: Double
        /// Career goals finished that this rank also asks for.
        public var goals: Int
    }

    public static let ranks: [Rank] = [
        ("Street Vendor", 0.0, 0), ("Shopkeeper", 25_000, 2), ("Trader", 100_000, 4), ("Merchant", 400_000, 6), ("Entrepreneur", 1_000_000, 8),
        ("Executive", 5_000_000, 11), ("Magnate", 25_000_000, 14), ("Mogul", 100_000_000, 17), ("Tycoon", 1_000_000_000, 20)
    ].enumerated().map { Rank(index: $0.offset, title: $0.element.0, netWorth: $0.element.1, goals: $0.element.2) }

    /// The highest rank for which both asks hold: the net worth and the goals finished.
    public static func rankIndex(netWorth nw: Double, goalsDone: Int, currency cur: Currency) -> Int {
        ranks.last { nw >= cur.scaledPrice($0.netWorth) && goalsDone >= $0.goals }?.index ?? 0
    }

    public struct RankStatus: Equatable, Sendable {
        public var rank: Rank
        public var next: Rank?
        /// 0 to 1 towards the next rank: the slower of net worth and goals decides.
        public var progress: Double
        /// What is still missing, in words ("Net worth 100k", "2 more goals"); empty at the top.
        public var missing: String
    }

    public static func rankStatus(netWorth nw: Double, goalsDone: Int, currency cur: Currency) -> RankStatus {
        let i = rankIndex(netWorth: nw, goalsDone: goalsDone, currency: cur)
        let rank = ranks[i]
        guard i + 1 < ranks.count else { return RankStatus(rank: rank, next: nil, progress: 1, missing: "") }
        let n = ranks[i + 1]
        let lo = cur.scaledPrice(rank.netWorth), hi = cur.scaledPrice(n.netWorth)
        let pw = hi > lo ? min(1, max(0, (nw - lo) / (hi - lo))) : 1
        let pg = n.goals > rank.goals ? min(1, max(0, Double(goalsDone - rank.goals) / Double(n.goals - rank.goals))) : 1
        var miss: [String] = []
        if nw < hi { miss.append("Wealth built " + cur.display(hi)) }
        if goalsDone < n.goals { let k = n.goals - goalsDone; miss.append("\(k) more \(k == 1 ? "goal" : "goals")") }
        return RankStatus(rank: rank, next: n, progress: min(pw, pg), missing: miss.joined(separator: " and "))
    }

    // MARK: Goals

    public enum Horizon: Int, Sendable, CaseIterable {
        case short, medium, long
        public var label: String { ["Short", "Medium", "Long"][rawValue] }
    }

    struct Facts {
        var s: GameState
        var nw: Double
        /// Wealth built: net worth above what the player started with (the start already holds premises and equipment).
        var gain: Double { max(0, nw - (s.rest["car"]?["nw0"].double ?? nw)) }
        var cur: Currency
        var live: [Company]
        var trophies: Set<String>
        func money(_ v: Double) -> Double { cur.scaledPrice(v) }
    }

    struct Def {
        var id: String, title: String, body: String, horizon: Horizon
        /// Reward line: a title, a perk or a logo badge (what the player really gets).
        var reward: String
        /// Progress 0...1; 1 means done.
        var progress: (Facts) -> Double
        /// Extra effect on completion (small, real bonuses only).
        var grant: (inout GameState) -> Void = { _ in }
        /// Cosmetic unlocked by this goal (a company logo badge), "" for none.
        var cosmetic: String = ""
        /// Money the goal asks for, in reference units; shown in the player's currency wherever the text says {amt}.
        var amount: Double = 0
        func text(_ t: String, _ cur: Currency) -> String { amount == 0 ? t : t.replacingOccurrences(of: "{amt}", with: cur.short(cur.scaledPrice(amount))) }
    }

    static func ratio(_ a: Double, _ b: Double) -> Double { b <= 0 ? 1 : min(1, max(0, a / b)) }
    static func bestMonth(_ f: Facts) -> Double { f.live.compactMap { $0.monthlyHistory.last?.profit }.max() ?? 0 }
    static func bump(_ s: inout GameState, rep: Double = 0, aware: Double = 0, credit: Double = 0) {
        for i in s.companies.indices where s.companies[i].status.isLive && s.companies[i].type != "hold" {
            s.companies[i].reputation = min(100, s.companies[i].reputation + rep)
            s.companies[i].awareness = min(100, s.companies[i].awareness + aware)
        }
        s.credit = min(100, s.credit + credit)
    }

    static let defs: [Def] = [
        Def(id: "k1", title: "Three profitable weeks in a row", body: "Your net worth rises three weeks running.", horizon: .short, reward: "Title: Steady Hand",
            progress: { ratio(Double($0.s.rest["miles"]?["s"].int ?? 0), 3) }, grant: { bump(&$0, aware: 3) }),
        Def(id: "k2", title: "A cash cushion of {amt}", body: "Hold {amt} in cash across your companies at once.", horizon: .short, reward: "Credit score up",
            progress: { f in ratio(f.live.reduce(0) { $0 + $1.cash }, f.money(200_000)) }, grant: { bump(&$0, credit: 2) }, amount: 200_000),
        Def(id: "k3", title: "Regulars", body: "Get one company's reputation to 70.", horizon: .short, reward: "Logo badge: Star",
            progress: { f in ratio(f.live.map { $0.reputation }.max() ?? 0, 70) }, cosmetic: "logo.star"),
        Def(id: "k4", title: "A team of five", body: "Have five people on the payroll.", horizon: .short, reward: "Title: Boss",
            progress: { f in ratio(Double(PlayerGoals.staffCount(f.s)), 5) }, grant: { bump(&$0, rep: 1) }),
        Def(id: "k5", title: "A {amt} month", body: "One company makes {amt} of profit in a single month.", horizon: .medium, reward: "Logo badge: Gold coin",
            progress: { f in ratio(bestMonth(f), f.money(30_000)) }, cosmetic: "logo.coin", amount: 30_000),
        Def(id: "k6", title: "Debt-free", body: "Take a loan, then pay it all back.", horizon: .medium, reward: "Credit score up",
            progress: { f in !f.s.loans.isEmpty ? 0.5 : (f.s.rest["ach28d"] != nil ? 1 : 0) }, grant: { bump(&$0, credit: 4) }),
        Def(id: "k7", title: "Build {amt} of wealth", body: "Grow your net worth by {amt} from where you started.", horizon: .medium, reward: "Logo badge: Laurel",
            progress: { f in ratio(f.gain, f.money(100_000)) }, cosmetic: "logo.laurel", amount: 100_000),
        Def(id: "k8", title: "Second store", body: "Own two live companies.", horizon: .medium, reward: "Local fame: awareness up",
            progress: { f in ratio(Double(f.live.count), 2) }, grant: { bump(&$0, aware: 5) }),
        Def(id: "k9", title: "A profitable year", body: "Close a full year in profit.", horizon: .medium, reward: "Title: Year-Rounder",
            progress: { f in Gates.profitableYears(f.s) >= 1 ? 1 : ratio(Double(f.live.map { $0.monthlyHistory.count }.max() ?? 0), 12) * 0.9 }),
        Def(id: "k10", title: "Five trophies", body: "Fill the first shelf of the trophy wall.", horizon: .medium, reward: "Logo badge: Cup",
            progress: { f in ratio(Double(f.trophies.count), 5) }, cosmetic: "logo.cup"),
        Def(id: "k11", title: "Three companies", body: "Own three companies and the group layer opens.", horizon: .long, reward: "Title: Group Owner",
            progress: { f in ratio(Double(f.live.count), 3) }, grant: { bump(&$0, rep: 2) }),
        Def(id: "k12", title: "A chain of three", body: "Run three stores under one name.", horizon: .long, reward: "Logo badge: Banner",
            progress: { f in f.trophies.contains("ch3") ? 1 : 0 }, cosmetic: "logo.banner"),
        Def(id: "k13", title: "First franchisee", body: "Let someone else open a unit under your name.", horizon: .long, reward: "Title: Franchisor",
            progress: { f in f.trophies.contains("fr1") ? 1 : 0 }),
        Def(id: "k14", title: "Build {amt} of wealth", body: "Grow your net worth by {amt}: your first real fortune.", horizon: .long, reward: "Logo badge: Diamond",
            progress: { f in ratio(f.gain, f.money(1_000_000)) }, grant: { bump(&$0, rep: 3, credit: 3) }, cosmetic: "logo.diamond", amount: 1_000_000),
        Def(id: "k15", title: "Holding company", body: "Put your companies under a holding.", horizon: .long, reward: "Title: Holding Chief",
            progress: { f in f.s.companies.contains { $0.type == "hold" && $0.status.isLive } ? 1 : 0 }),
        Def(id: "k16", title: "Ten trophies", body: "Half the wall is lit.", horizon: .long, reward: "Logo badge: Crown",
            progress: { f in ratio(Double(f.trophies.count), 10) }, cosmetic: "logo.crown"),
        Def(id: "k17", title: "Listed on the exchange", body: "Anyone can buy shares in your group.", horizon: .long, reward: "Title: Public Figure",
            progress: { f in f.trophies.contains("listed") ? 1 : 0 }),
        Def(id: "k18", title: "Build {amt} of wealth", body: "Grow your net worth by {amt}.", horizon: .long, reward: "Logo badge: Skyline",
            progress: { f in ratio(f.gain, f.money(10_000_000)) }, cosmetic: "logo.skyline", amount: 10_000_000),
        Def(id: "k19", title: "Build {amt} of wealth", body: "Grow your net worth by {amt}: Mogul territory.", horizon: .long, reward: "Title: Mogul",
            progress: { f in ratio(f.gain, f.money(100_000_000)) }, amount: 100_000_000),
        Def(id: "k21", title: "Known in town", body: "Get one company's awareness to 60: people know the name.", horizon: .short, reward: "Logo badge: Bell",
            progress: { f in ratio(f.live.map { $0.awareness }.max() ?? 0, 60) }, cosmetic: "logo.bell"),
        Def(id: "k22", title: "Three good months", body: "One company makes a profit three months in a row.", horizon: .short, reward: "Credit score up",
            progress: { f in f.live.contains { c in c.monthlyHistory.suffix(3).count == 3 && c.monthlyHistory.suffix(3).allSatisfy { $0.profit > 0 } } ? 1 : ratio(Double(f.live.map { c in c.monthlyHistory.reversed().prefix { $0.profit > 0 }.count }.max() ?? 0), 3) },
            grant: { bump(&$0, credit: 3) }),
        Def(id: "k23", title: "Twelve rising weeks", body: "Your net worth rises in twelve weeks in a row, at your best.", horizon: .medium, reward: "Title: Compounder",
            progress: { f in ratio(Double(f.s.rest["miles"]?["bs"].int ?? 0), 12) }, grant: { bump(&$0, aware: 4) }),
        Def(id: "k24", title: "A name people trust", body: "Get one company's reputation to 90.", horizon: .medium, reward: "Logo badge: Seal",
            progress: { f in ratio(f.live.map { $0.reputation }.max() ?? 0, 90) }, cosmetic: "logo.seal"),
        Def(id: "k25", title: "A team of ten", body: "Have ten people on the payroll.", horizon: .medium, reward: "Title: Employer",
            progress: { f in ratio(Double(PlayerGoals.staffCount(f.s)), 10) }, grant: { bump(&$0, rep: 2) }),
        Def(id: "k26", title: "A war chest of {amt}", body: "Hold {amt} in cash across your companies at once.", horizon: .medium, reward: "Credit score up",
            progress: { f in ratio(f.live.reduce(0) { $0 + $1.cash }, f.money(600_000)) }, grant: { bump(&$0, credit: 3) }, amount: 600_000),
        Def(id: "k20",title: "Thirty trophies", body: "A wall full of proof.", horizon: .long, reward: "Logo badge: Gold crest",
            progress: { f in ratio(Double(f.trophies.count), 30) }, cosmetic: "logo.crest"),
    ]

    public struct Goal: Equatable, Sendable, Identifiable {
        public var id: String, title: String, body: String, reward: String
        public var horizon: Horizon
        public var progress: Double
        public var done: Bool
    }

    static func facts(_ s: GameState, data: GameData, currency cur: Currency) -> Facts {
        let got = Trophies.entries(s).filter { $0.reachedWeek != nil }.map { $0.id }
        return Facts(s: s, nw: Valuation.netWorth(s, trades: data.catalog).total, cur: cur,
                     live: s.companies.filter { $0.status.isLive && $0.type != "hold" }, trophies: Set(got))
    }

    static func isDone(_ s: GameState, _ id: String) -> Bool { !(s.rest["car"]?["done"][id] ?? .null).isNull }
    public static func goalsDone(_ s: GameState) -> Int { s.rest["car"]?["done"].object.count ?? 0 }
    public static func cosmetics(_ s: GameState) -> [String] { (s.rest["car"]?["cos"].array ?? []).map { $0.string } }

    /// All goals with progress.
    public static func goals(_ s: GameState, data: GameData, currency cur: Currency) -> [Goal] {
        let f = facts(s, data: data, currency: cur)
        return defs.map { d in
            let done = isDone(s, d.id)
            return Goal(id: d.id, title: d.text(d.title, cur), body: d.text(d.body, cur), reward: d.reward, horizon: d.horizon, progress: done ? 1 : min(1, d.progress(f)), done: done)
        }
    }

    /// The next goal to chase for each horizon (short, medium, long): the open one closest to done in that horizon.
    public static func nextGoals(_ s: GameState, data: GameData, currency cur: Currency) -> [Goal] {
        let all = goals(s, data: data, currency: cur)
        return Horizon.allCases.compactMap { h in all.filter { $0.horizon == h && !$0.done }.max { $0.progress < $1.progress } }
    }

    public static func status(_ s: GameState, data: GameData, currency cur: Currency) -> RankStatus {
        rankStatus(netWorth: facts(s, data: data, currency: cur).gain, goalsDone: goalsDone(s), currency: cur)
    }

    /// Finishes goals whose progress reached 1 and celebrates them and rank-ups. Runs after each day.
    @discardableResult
    public static func sweep(_ s: inout GameState, data: GameData, currency cur: Currency) -> [String] {
        guard s.companies.contains(where: { $0.type != "hold" }) else { return [] }
        if s.rest["car"]?["nw0"].isNull ?? true {   // the baseline: what the player owns on the first day
            var c = s.rest["car"] ?? .object(["done": .object([:])])
            c["nw0"] = .number(Valuation.netWorth(s, trades: data.catalog).total); s.rest["car"] = c
        }
        let f = facts(s, data: data, currency: cur)
        var finished: [String] = []
        for d in defs where !isDone(s, d.id) && d.progress(f) >= 1 {
            var c = s.rest["car"] ?? .object(["done": .object([:])])
            var done = c["done"]; done[d.id] = .object(["w": .number(Double(s.week))]); c["done"] = done
            if !d.cosmetic.isEmpty { c["cos"] = .array((c["cos"].array ?? []) + [.string(d.cosmetic)]) }
            s.rest["car"] = c
            d.grant(&s)
            let title = d.text(d.title, cur)
            s.note("Goal reached: \(title)", tone: "good")
            Celebrations.add(&s, kind: "goal", title: title, detail: d.horizon.label + " goal reached", reward: d.reward, art: "goal.career", tier: d.horizon == .short ? 1 : 2)
            finished.append(d.id)
        }
        let st = rankStatus(netWorth: f.gain, goalsDone: goalsDone(s), currency: cur)
        let seen = s.rest["car"]?["rk"].int ?? 0
        if st.rank.index > seen {
            var c = s.rest["car"] ?? .object(["done": .object([:])]); c["rk"] = .number(Double(st.rank.index)); s.rest["car"] = c
            Celebrations.add(&s, kind: "milestone", title: "New rank: \(st.rank.title)", detail: st.next.map { "Next: \($0.title)" } ?? "The top of the ladder", reward: "Title: \(st.rank.title)", art: "milestone.rank", tier: 2)
        }
        return finished
    }
}

public extension GameEngine {
    /// The rank and its progress for Home and the profile.
    var careerStatus: Career.RankStatus { Career.status(state, data: data, currency: homeCurrency) }
    /// The next short, medium and long goal.
    var careerNextGoals: [Career.Goal] { Career.nextGoals(state, data: data, currency: homeCurrency) }
    var careerGoals: [Career.Goal] { Career.goals(state, data: data, currency: homeCurrency) }
    /// Logo badges earned (for company cosmetics).
    var careerCosmetics: [String] { Career.cosmetics(state) }
    mutating func sweepCareer() { update { s, d, ctx in Career.sweep(&s, data: d, currency: ctx.homeCurrency(s)) } }
}
