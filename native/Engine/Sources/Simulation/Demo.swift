import Foundation
import GameCore
import Countries
import Finance
import Businesses

public extension GameEngine {
    /// A game in progress for screenshots, UI tests and demos: a café and a gym a few months in, payroll approved as it comes.
    /// Deterministic for a given seed. Not used by the normal game.
    static func showcase(seed: Int = 2026, days: Int = 120, wealthy: Bool = false) throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Alex", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Showcase funds") }
        for trade in ["cafe", "gym"] {
            _ = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: .limited, fundWith: trade == "cafe" ? 4_000_000 : 9_000_000)
        }
        // Only for the screenshot tour of the Luxury app (it opens its doors to net worth well above the entry level).
        if wealthy { let extra = e.luxuryGateThreshold * 1.5; e.update { s, _, _ in Ledger.move(&s, .me, extra, why: "Showcase funds") } }
        e.resetHistory()
        for _ in 0..<days {
            e.nextDay()
            for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
            if e.state.isGameOver { break }
        }
        return e
    }
}
