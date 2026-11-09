import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

/// Rank titles, the career goal ladder, and (with LEDGER_PLAYTEST=1) the pacing probe of the first year.
final class CareerTests: XCTestCase {
    private func cafe(_ code: String = "UK", trade: String = "cafe", seed: Int = 7) throws -> GameEngine {
        try GameEngine.newGame(countryCode: code, playerName: "T", seed: seed, story: .fresh, tradeID: trade, companyName: "Test")
    }

    func testRankNeedsBothNetWorthAndGoals() throws {
        let cur = try UKCurrency()
        XCTAssertEqual(Career.rankIndex(netWorth: 0, goalsDone: 0, currency: cur), 0)
        // Rich but no goals: stays a Street Vendor.
        XCTAssertEqual(Career.rankIndex(netWorth: cur.scaledPrice(2e9), goalsDone: 0, currency: cur), 0)
        // Goals but poor: also stays low.
        XCTAssertEqual(Career.rankIndex(netWorth: 0, goalsDone: 20, currency: cur), 0)
        XCTAssertEqual(Career.ranks[Career.rankIndex(netWorth: cur.scaledPrice(30_000), goalsDone: 2, currency: cur)].title, "Shopkeeper")
        XCTAssertEqual(Career.ranks[Career.rankIndex(netWorth: cur.scaledPrice(2e9), goalsDone: 20, currency: cur)].title, "Tycoon")
        // Ranks only go up with both asks.
        var last = 0
        for k in 0...20 {
            let i = Career.rankIndex(netWorth: cur.scaledPrice(Double(k) * 1e8), goalsDone: k, currency: cur)
            XCTAssertGreaterThanOrEqual(i, last); last = i
        }
    }

    func testRankStatusProgressIsTheSlowerAsk() throws {
        let cur = try UKCurrency()
        let a = Career.rankStatus(netWorth: cur.scaledPrice(60_000), goalsDone: 3, currency: cur)
        XCTAssertEqual(a.rank.title, "Shopkeeper")
        XCTAssertEqual(a.next?.title, "Trader")
        XCTAssertEqual(a.progress, 0.47, accuracy: 0.02)   // wealth gives 0.47, goals 0.5: the slower decides
        XCTAssertTrue(a.missing.contains("Wealth"))
        let top = Career.rankStatus(netWorth: cur.scaledPrice(5e9), goalsDone: 30, currency: cur)
        XCTAssertNil(top.next); XCTAssertEqual(top.progress, 1)
    }

    func testGoalsAlwaysShowNextShortMediumLong() throws {
        let e = try cafe()
        let next = e.careerNextGoals
        XCTAssertEqual(next.map { $0.horizon }, [.short, .medium, .long])
        XCTAssertEqual(Set(Career.defs.map { $0.id }).count, Career.defs.count)
        XCTAssertTrue(next.allSatisfy { !$0.done && $0.progress < 1 })
    }

    func testSweepFinishesGoalOnceRewardsAndCelebrates() throws {
        var e = try cafe()
        e.update { s, _, _ in
            Career.bump(&s)   // no-op shape check
            s.rest["miles"] = .object(["s": 3])
        }
        e.sweepCareer()
        XCTAssertTrue(Career.isDone(e.state, "k1"))
        XCTAssertTrue(e.pendingCelebrations.contains { $0.title == "Three profitable weeks in a row" })
        let n = e.pendingCelebrations.count
        e.sweepCareer()   // never twice
        XCTAssertEqual(e.pendingCelebrations.count, n)
        XCTAssertEqual(Career.goalsDone(e.state), 1)
    }

    func testCosmeticBadgeUnlockedWithGoal() throws {
        var e = try cafe()
        e.update { s, _, _ in for i in s.companies.indices { s.companies[i].reputation = 80 } }
        e.sweepCareer()
        XCTAssertFalse(e.careerCosmetics.contains("logo.star"), "the badge comes with the claim")
        e.claimGoal(kind: .career, id: "k3")
        XCTAssertTrue(e.careerCosmetics.contains("logo.star"))
    }

    // MARK: Pacing probe (prints the timeline; LEDGER_PLAYTEST=1)

    private func nw(_ e: GameEngine) -> Double { Valuation.netWorth(e.state, trades: e.data.catalog).total }

    private func play(_ e: inout GameEngine, expert: Bool, days: Int, log: inout [String]) {
        let id = e.state.companies.first!.id
        let cur = e.homeCurrency
        let channels = ["google", "meta", "seo"].filter { e.marketing.channels[$0] != nil }
        if expert {
            for k in channels { if let ch = e.marketing.channels[k], ch.budgetOptions.count > 1 { _ = e.setCampaign(companyID: id, channel: k, weeklyBudget: ch.budgetOptions[1]) } }
        }
        var seenLadder = 0, seenCareer = 0, seenCele = 0
        for d in 1...days {
            e.nextDay()
            for m in e.openDecisions where !m.options.isEmpty { _ = e.answer(messageID: m.id, option: 0) }
            let l = Gates.goalsDone(e.state), c = Career.goalsDone(e.state)
            let cel = e.pendingCelebrations.count
            if l > seenLadder { log.append("  day \(d) (wk \(e.state.week)): ladder M\(l) done") ; seenLadder = l }
            if c > seenCareer { log.append("  day \(d) (wk \(e.state.week)): career goals \(c)") ; seenCareer = c }
            if cel != seenCele { seenCele = cel }
            if expert, d % 28 == 0, Gates.goalDone(e.state, 8), Gates.companiesOwned(e.state) < 3, e.state.cash + (e.state.company(id)?.cash ?? 0) > cur.scaledPrice(300_000) {
                _ = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, name: "Cafe \(d)", fundWith: cur.scaledPrice(100_000))
            }
            if [10, 70, 364].contains(d) { log.append("  day \(d): rank \(e.careerStatus.rank.title), net worth \(cur.display(nw(e))), celebrations waiting \(e.pendingCelebrations.count)") }
        }
    }

    func testPacingTimeline() throws {
        // (UKCurrency lives below)
        guard ProcessInfo.processInfo.environment["LEDGER_PLAYTEST"] == "1" else { throw XCTSkip("set LEDGER_PLAYTEST=1") }
        var out: [String] = []
        for (code, trade) in [("UK", "cafe"), ("US", "barber"), ("DE", "bakery"), ("UK", "foodtruck")] {
            for expert in [false, true] {
                var e = try cafe(code, trade: trade)
                var log: [String] = ["\(code)/\(trade) \(expert ? "expert" : "beginner") start nw \(e.homeCurrency.display(nw(e)))"]
                play(&e, expert: expert, days: 364, log: &log)
                out += log
            }
        }
        print("PACING\n" + out.joined(separator: "\n"))
    }
}
