import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Events

public extension GameEngine {
    private static let ownerOnlyKinds: Set<String> = ["exit", "rofr", "div", "divq", "growth", "dorder"]

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
            if rank.rawValue <= Delegation.Rank.manager.rawValue, co.managerID != nil, !Delegation.managerMayTake(m, co, state, data: data) { continue }
            let scale = max(currency(for: co).scaledPrice(1000), co.lastWeekRevenue * 3)
            var best = 0, bestScore = -Double.infinity
            if m.actionID == StrategicDecisions.action {
                best = StrategicDecisions.defaultOption(of: m)
            } else {
                for (i, o) in m.options.enumerated() where o["fx"]["tier"].isNull {
                    let sc = Self.score(o["fx"], scale: scale)
                    if sc > bestScore { bestScore = sc; best = i }
                }
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
