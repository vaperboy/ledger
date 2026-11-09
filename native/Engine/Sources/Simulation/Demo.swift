import Foundation
import GameCore
import Countries
import Finance
import Businesses

public extension GameEngine {
    /// Whether the debug-only games below may be made: on in debug builds, and in release builds only when the test run sets LEDGER_DEBUG_TOOLS=1, so no one can mint the showcase money.
    nonisolated(unsafe) package static var debugToolsEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return ProcessInfo.processInfo.environment["LEDGER_DEBUG_TOOLS"] == "1"
        #endif
    }()

    package enum DebugError: Error, Equatable { case debugToolsOff }

    /// A game in progress for screenshots, UI tests and demos: a café and a gym a few months in, payroll approved as it comes.
    /// Deterministic for a given seed. Not used by the normal game.
    /// `extraTrades`: more companies started next to the café and the gym (screenshot runs of other trades only).
    static func showcase(seed: Int = 2026, days: Int = 120, wealthy: Bool = false, board: Bool = false, extraTrades: [String] = []) throws -> GameEngine {
        guard debugToolsEnabled else { throw DebugError.debugToolsOff }
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Alex", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Showcase funds") }
        for trade in ["cafe", "gym"] + extraTrades {
            _ = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, fundWith: trade == "cafe" ? 4_000_000 : 9_000_000)
        }
        // Only for the screenshot tour of the Luxury app (it opens its doors to net worth well above the entry level).
        if wealthy { let extra = e.luxuryGateThreshold * 1.5; e.update { s, _, _ in Ledger.move(&s, .me, extra, why: "Showcase funds") } }
        e.resetHistory()
        for _ in 0..<days {
            e.nextDay()
            for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
            if e.state.isGameOver { break }
        }
        if board { e.addShowcaseBoard() }
        return e
    }

    /// Only for the Board screenshots (`-showcase-board`): the café gets a co-owner, so a board exists, and three loss months are written to its
    /// history. The decision list is then built by the engine.
    mutating func addShowcaseBoard() {
        guard let id = state.companies.first(where: { $0.type == "cafe" })?.id else { return }
        update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].set("holders", .array([.object(["name": "Ann Partner", "pct": 15, "in": 0, "k27": "quiet", "sat": 60, "w0": 0])]))
            let cash = max(1, s.companies[i].cash)   // sizes follow the company's own money, so they scale with the country
            s.companies[i].monthlyHistory = (0..<3).map { MonthRecord(monthIndex: $0, revenue: cash / 2, profit: -cash / 20, cash: cash) }
        }
    }
}
