import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

final class PlaytestTests: XCTestCase {
    typealias Run = (code: String, bankruptWeek: Int?, cashPositive: Bool, m7Week: Int?, m10Week: Int?)

    private func codes() throws -> [String] { try CountryBook.bundled().countries.map { $0.code } }

    private func fresh(_ code: String, seed: Int = 7) throws -> GameEngine {
        try GameEngine.newGame(countryCode: code, playerName: "T", seed: seed, story: .fresh, tradeID: "cafe", companyName: "Test Cafe")
    }

    private func answerFirst(_ e: inout GameEngine) {
        for m in e.openDecisions where !m.options.isEmpty { _ = e.answer(messageID: m.id, option: 0) }
    }

    private func liquid(_ e: GameEngine) -> Double {
        e.state.cash + e.state.companies.filter { $0.status.isLive }.reduce(0) { $0 + $1.cash }
    }

    private func isBroke(_ e: GameEngine) -> Bool { e.state.isGameOver || e.state.companies.contains { $0.status == .bust } }

    private func profitMonth(_ e: GameEngine) -> Bool { PlayerGoals.ladderCondition("M7", e.state) }

    private func idle(_ code: String, answering: Bool) throws -> Run {
        var e = try fresh(code)
        var bankrupt: Int? = nil, m7: Int? = nil
        for _ in 0..<364 {
            e.nextDay()
            if answering { answerFirst(&e) }
            if bankrupt == nil, isBroke(e) { bankrupt = e.state.week }
            if m7 == nil, profitMonth(e) { m7 = e.state.week }
        }
        return (code, bankrupt, liquid(e) > 0 && !e.state.isGameOver, m7, nil)
    }

    func testPassiveBotSurvivesToWeek27ButLosesMoneyInYearOne() throws {
        var rows: [String] = [], early: [String] = [], lost = 0
        let all = try codes()
        for c in all {
            var e = try fresh(c)
            let start = liquid(e)
            var bankrupt: Int? = nil
            for _ in 0..<364 {
                e.nextDay()
                answerFirst(&e)
                if bankrupt == nil, isBroke(e) { bankrupt = e.state.week }
            }
            let end = liquid(e)
            rows.append("\(c) bankrupt=\(bankrupt.map(String.init) ?? "-") change=\(Int(end - start))")
            if let w = bankrupt, w < 27 { early.append("\(c): week \(w)") }
            if end < start { lost += 1 }
        }
        print("PLAYTEST passive\n" + rows.joined(separator: "\n"))
        XCTAssertTrue(early.isEmpty, "bankrupt before week 27: " + early.joined(separator: "; "))
        let need = Int((Double(all.count) * 18.0 / 23.0).rounded(.up))
        XCTAssertGreaterThanOrEqual(lost, need, "a shop left on its defaults lost money in year 1 in \(lost) of \(all.count) countries")
    }

    func testHoarderBotRarelyReachesAProfitableMonthByWeek30() throws {
        var rows: [String] = [], reached = 0
        let all = try codes()
        for c in all {
            let r = try idle(c, answering: false)
            rows.append("\(c) M7=\(r.m7Week.map(String.init) ?? "-")")
            if let w = r.m7Week, w <= 30 { reached += 1 }
        }
        print("PLAYTEST hoarder\n" + rows.joined(separator: "\n"))
        let most = Int((Double(all.count) * 5.0 / 23.0).rounded(.down))
        XCTAssertLessThanOrEqual(reached, most, "M7 by week 30 without any choice in \(reached) of \(all.count) countries")
    }

    private func ladderBot(_ code: String, price: Double) throws -> Run {
        var e = try fresh(code)
        let id = try XCTUnwrap(e.state.companies.first?.id)
        let cur = e.homeCurrency
        let channels = ["google", "meta", "seo"].filter { e.marketing.channels[$0] != nil }
        _ = e.setPriceLevel(companyID: id, level: price)
        for k in channels { if let ch = e.marketing.channels[k], ch.budgetOptions.count > 1 { _ = e.setCampaign(companyID: id, channel: k, weeklyBudget: ch.budgetOptions[1]) } }
        var stoppedAds = false, alone = false, managerTried = false, second = false
        var bankrupt: Int? = nil, m7: Int? = nil, m10: Int? = nil
        var injected = false
        for day in 0..<364 {
            if !injected && day == 8 && !e.openDecisions.contains(where: { !$0.options.isEmpty }) {
                injected = true
                e.update { s, _, _ in
                    s.addMessage(kind: "ask", from: "Test", title: "A decision", body: "Pick one.", companyID: id, status: "open",
                                 options: [.option("Fine", "")], action: FirstYear.frozenAction)
                }
            }
            e.nextDay()
            answerFirst(&e)
            if bankrupt == nil, isBroke(e) { bankrupt = e.state.week }
            if !stoppedAds, Gates.goalDone(e.state, 5) { stoppedAds = true; for k in channels { _ = e.setCampaign(companyID: id, channel: k, weeklyBudget: 0) } }
            if !alone, Gates.goalDone(e.state, 3), let st = e.state.company(id)?.staff.first { alone = true; e.dismissStaff(companyID: id, staffID: st.id) }
            if m7 == nil, Gates.goalDone(e.state, 7) { m7 = e.state.week }
            if m7 != nil, !managerTried, !Gates.goalDone(e.state, 8), let c = e.searchManagers(companyID: id)?.first {
                managerTried = true
                _ = e.hireManager(personID: c.id, companyID: id, monthlyWage: c.askingMonthlyWage * 1.3)
            }
            if Gates.goalDone(e.state, 8), !second, Gates.companiesOwned(e.state) < 2 {
                second = true
                e.update { s, _, _ in Ledger.move(&s, .me, cur.scaledPrice(400_000), why: "Test funds") }
                _ = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, name: "Second Cafe")
            }
            if m10 == nil, Gates.goalDone(e.state, 10) { m10 = e.state.week; break }
        }
        return (code, bankrupt, true, m7, m10)
    }

    func testLadderBotReachesM7ByWeek20AndM10ByWeek40OnEveryCountry() throws {
        var fails: [String] = [], rows: [String] = []
        for c in try codes() {
            var best: Run = (c, nil, false, nil, nil)
            for price in [0.0, -1.0, 1.0] {
                best = try ladderBot(c, price: price)
                if let a = best.m7Week, a <= 20, let b = best.m10Week, b <= 40 { break }
            }
            rows.append("\(c) M7=\(best.m7Week.map(String.init) ?? "-") M10=\(best.m10Week.map(String.init) ?? "-")")
            if best.m7Week.map({ $0 > 20 }) ?? true { fails.append("\(c): M7 \(best.m7Week.map(String.init) ?? "never")") }
            if best.m10Week.map({ $0 > 40 }) ?? true { fails.append("\(c): M10 \(best.m10Week.map(String.init) ?? "never")") }
        }
        print("PLAYTEST ladder\n" + rows.joined(separator: "\n"))
        XCTAssertTrue(fails.isEmpty, fails.joined(separator: "; "))
    }
}
