import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

/// A fourth answer for players who run several companies: money bought against time or reputation. It is added to the owner's
/// decision when the event is bad and not urgent, and it is never taken as a default or by a manager's own scoring
/// (it carries `tier` = 4 in its effects).
extension EventEngine {
    static func openCompanyCount(_ s: GameState) -> Int { s.companies.filter { $0.status == .open && $0.type != "hold" }.count }

    /// Late game: three companies open, or two after about two years.
    public static func isLateGame(_ s: GameState) -> Bool {
        let n = openCompanyCount(s)
        return n >= 3 || (n >= 2 && s.week >= 104)
    }

    /// The worst loss or fine an answer can bring (gambles included), in the company's money.
    static func worstHit(_ fx: JSONValue) -> Double {
        var m = max(abs(fx["loss"].double), abs(fx["fine"].double))
        if !fx["gamble"].isNull { m = max(m, worstHit(fx["gamble"]["ok"]), worstHit(fx["gamble"]["bad"])) }
        return m
    }

    /// The extra answer for this decision, or nil when the player is not late-game or the event does not suit it.
    /// `options` are the resolved options (amounts already in the company's money).
    static func lateGameOption(_ e: GameEvent, options: [JSONValue], ctx: Context, company co: Company, state s: GameState) -> JSONValue? {
        guard isLateGame(s), e.tone == "bad", !e.blocking, e.expiresAfterWeeks >= 2, (2...3).contains(options.count) else { return nil }
        if let m = co.managerID, s.people[m] != nil {
            return .option("Hand it to your manager", "Saves your time: the manager picks the best answer for the business. A fee of a twentieth of a week's sales.",
                           effects: ["tier": .number(4), "delegate": .number(1), "cash": .number(-jsRound(ctx.wk * 0.05))])
        }
        let worst = options.map { worstHit($0["fx"]) }.max() ?? 0
        if (e.category == "liab" || e.category == "cyber") && worst > 0 {
            return .option("Settle quietly", "Pays about 60% of the worst case now and closes it with no story and no reputation loss.",
                           effects: ["tier": .number(4), "cash": .number(-jsRound(worst * 0.6))])
        }
        return .option("Hire a fixer", "Pays about a third of a week's sales to make it go away: no reputation or demand damage, and nothing gained either.",
                       effects: ["tier": .number(4), "cash": .number(-jsRound(ctx.wk * 0.35))])
    }

    /// Apply the chosen answer of an open decision. A delegated answer also runs the option the manager picks among the others.
    static func applyAnswer(_ s: inout GameState, companyIndex i: Int, message m: Message, option idx: Int, ctx: Context, event e: GameEvent, data: GameData, context fc: FinanceContext) {
        let fx = m.options[idx]["fx"]
        apply(&s, companyIndex: i, fx, ctx: ctx, event: e, data: data, context: fc)
        guard fx["delegate"].bool else { return }
        let base = m.options.filter { $0["fx"]["tier"].isNull }
        guard !base.isEmpty else { return }
        let co = s.companies[i]
        let q: Double = co.managerID.flatMap { s.people[$0] } != nil ? ManagerModel.quality(co, bd(data, co), people: s.people) : 0.5
        let pick = choose(co, options: base, ctx: ctx, quality: q, random: &s.random)
        let who = co.managerID.flatMap { s.people[$0]?.name } ?? "The manager"
        apply(&s, companyIndex: i, base[pick]["fx"], ctx: ctx, event: e, data: data, context: fc)
        s.note("\(co.name): \(who) took \"\(m.title)\" and chose: \(base[pick]["l"].string).", tone: "n", companyID: co.id)
    }
}
