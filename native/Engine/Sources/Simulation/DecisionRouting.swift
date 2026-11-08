import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Decisions go to the lowest rank that can take them. A new decision about a company gets a level (1 to 5, by its kind
/// and size against net worth); if the company has someone of that rank or above (a manager, a director, a CEO) they answer it, picking the
/// option that is best on its stated effects, and the Inbox lists it under Handled with their name. What stays with the owner: level 5, anything
/// with outside shareholders (sales, buy-outs), dividends, payroll (it has its own rule) and a manager's own pay and poaching.
public extension GameEngine {
    /// The kinds of decision that are never taken for the owner, whatever the level.
    private static let ownerOnlyKinds: Set<String> = ["exit", "rofr", "div", "divq", "growth"]

    /// A rough worth of an option from what it says it does, to pick the best one. Money counts at face value; reputation, quality and
    /// awareness count as a share of what the company turns over in a few weeks; a gamble counts by its chance.
    static func score(_ fx: JSONValue, scale: Double) -> Double {
        if fx.isNull { return 0 }
        var v = fx["cash"].double - abs(fx["fine"].double) - abs(fx["loss"].double) * 0.5
        v += fx["rep"].double * scale * 0.05 + fx["q"].double * scale * 0.04 + fx["aware"].double * scale * 0.02
        if !fx["gamble"].isNull {
            let g = fx["gamble"], p = g["p"].double
            v += p * score(g["ok"], scale: scale) + (1 - p) * score(g["bad"], scale: scale)
        }
        return v
    }

    /// Answer the fresh decisions a hired rank can take. Returns how many were taken for the owner.
    @discardableResult
    mutating func routeFreshDecisions(_ fresh: [Message]) -> Int {
        let nw = netWorth.total
        var taken = 0
        for m in fresh where (m.kind == "ask" || m.kind == "decision") && m.status == "open" && m.companyID != 0 && !m.options.isEmpty {
            if m.actionID.hasPrefix("pay29") || m.actionID.hasPrefix("mgr") || m.actionID == "prop" { continue }
            if Self.ownerOnlyKinds.contains(m.value("data")["kind"].string) { continue }
            guard let co = state.company(m.companyID), co.status == .open else { continue }
            let level = Delegation.level(of: m, netWorth: nw)
            guard level < 5 else { continue }
            let rank = Delegation.handler(level: level, state, co, data: data)
            guard rank != .owner else { continue }
            // With a manager in the company the decision is theirs only within their budget.
            if rank.rawValue <= Delegation.Rank.manager.rawValue, co.managerID != nil, !Delegation.managerMayTake(m, co, state, data: data) { continue }
            let scale = max(currency(for: co).scaledPrice(1000), co.lastWeekRevenue * 3)
            var best = 0, bestScore = -Double.infinity
            for (i, o) in m.options.enumerated() where o["fx"]["tier"].isNull {   // the owner-only late-game extra answer is not for a hired rank
                let sc = Self.score(o["fx"], scale: scale)
                if sc > bestScore { bestScore = sc; best = i }
            }
            let who: String = co.managerID.flatMap { state.people[$0]?.name }.map { "\($0), \(rank.title.lowercased())" } ?? rank.title.lowercased()
            if answer(messageID: m.id, option: best) {
                update { s, _, _ in if let k = s.inbox.firstIndex(where: { $0.id == m.id }) { s.inbox[k].handledBy = who } }
                taken += 1
            }
        }
        return taken
    }
}
