import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

final class DaySlicesTests: XCTestCase {
    private func engine(cafes count: Int, seed: Int = 4242) throws -> (GameEngine, [Int]) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        var ids: [Int] = []
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 400_000_000, why: "Test funds")
            for _ in 0..<count {
                guard case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, data: data, context: ctx) else { continue }
                let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, size: 1, state: s, data: data)
                Payments.injectCash(&s, companyID: i, amount: (est?.total ?? 1_000_000) * 1.6 + 3_000_000)
                _ = CompanySetup.quickSetup(&s, companyID: i, data: data)
                ids.append(i)
            }
        }
        return (e, ids)
    }

    private func lastRun(_ e: GameEngine, _ id: Int) -> Int { e.state.company(id)?.value("slotRun").int ?? -1 }

    func testSlotsSpreadConsecutiveCompaniesOverAllSevenWeekdays() {
        XCTAssertEqual(Set((0..<7).map { GameCalendar.slot(ofCompany: 1000 + $0) }).count, 7)
        XCTAssertEqual(GameCalendar.slot(ofCompany: 1007), GameCalendar.slot(ofCompany: 1000))
    }

    func testACycleStartsOnTheSlotDayAndEqualsTheWeekFromThenOn() {
        let id = 1003
        let slot = GameCalendar.slot(ofCompany: id)
        for week in 3...5 {
            for day in 0..<7 {
                XCTAssertEqual(GameCalendar.cycle(companyID: id, week: week, day: day), day < slot ? week - 1 : week)
            }
        }
    }

    func testEachMonthEndWeekHasExactlyOneLastDayOfTheMonth() {
        for week in 0..<400 {
            let days = (0..<7).filter { GameCalendar.isMonthEnd(week: week, day: $0) }
            XCTAssertEqual(days.count, GameCalendar.isMonthEnd(week: week) ? 1 : 0, "week \(week)")
            let years = (0..<7).filter { GameCalendar.isYearEnd(week: week, day: $0) }
            XCTAssertEqual(years.count, GameCalendar.isYearEnd(week: week) ? 1 : 0, "week \(week)")
        }
    }

    func testCompaniesRunTheirModelOnTheirOwnWeekday() throws {
        var (e, ids) = try engine(cafes: 4)
        XCTAssertEqual(ids.count, 4)
        var runDays = Set<Int>()
        var previous: [Int: Int] = [:]
        for _ in 0..<(4 * 7) {
            e.nextDay()
            for id in ids {
                let now = lastRun(e, id)
                if let before = previous[id], now != before {
                    XCTAssertEqual(e.state.day, GameCalendar.slot(ofCompany: id), "company \(id) ran on day \(e.state.day)")
                    XCTAssertEqual(now, e.state.week * 7 + e.state.day)
                    runDays.insert(e.state.day)
                }
                previous[id] = now
            }
        }
        XCTAssertEqual(runDays, Set(ids.map { GameCalendar.slot(ofCompany: $0) }), "every company ran, each on its own day")
        XCTAssertGreaterThan(runDays.count, 1, "the companies do not all act on the same day")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testExactlyOneModelRunInAnySevenDays() throws {
        var (e, ids) = try engine(cafes: 1)
        let id = try XCTUnwrap(ids.first)
        for _ in 0..<(3 * 7) { e.nextDay() }
        var runs: [Int] = []
        var before = lastRun(e, id)
        for _ in 0..<(8 * 7) {
            e.nextDay()
            let now = lastRun(e, id)
            runs.append(now != before ? 1 : 0)
            before = now
        }
        for start in 0...(runs.count - 7) { XCTAssertEqual(runs[start..<(start + 7)].reduce(0, +), 1, "window from day \(start)") }
    }

    func testNothingWaitsForTheWeekToClose() throws {
        var (e, ids) = try engine(cafes: 7)
        let slots = Set(ids.map { GameCalendar.slot(ofCompany: $0) })
        var ranOn = Set<Int>()
        var previous: [Int: Int] = [:]
        for _ in 0..<(5 * 7) {
            let out = e.nextDay()
            for id in ids {
                let now = lastRun(e, id)
                if let before = previous[id], now != before { ranOn.insert(e.state.day); if out.completedWeek { XCTAssertEqual(GameCalendar.slot(ofCompany: id), 0) } }
                previous[id] = now
            }
        }
        XCTAssertEqual(ranOn, slots)
        XCTAssertGreaterThanOrEqual(slots.count, 3)
    }

    func testAStepsMoneyIsReleasedOverSevenDaysAndLeavesNoGap() throws {
        var (e, ids) = try engine(cafes: 1)
        let id = try XCTUnwrap(ids.first)
        for _ in 0..<(4 * 7) { e.nextDay() }
        var before = lastRun(e, id)
        while true {
            e.nextDay()
            let now = lastRun(e, id)
            if now != before { break }
            before = now
        }
        XCTAssertEqual(HeldMoney.today(e.state), lastRun(e, id))
        for k in 1...6 {
            e.nextDay()
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "day \(k): \(Ledger.gaps(e.state))")
        }
        e.nextDay()
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testSettlingHeldMoneyMidBatchStillBalances() throws {
        var (e, ids) = try engine(cafes: 1)
        let id = try XCTUnwrap(ids.first)
        for _ in 0..<(6 * 7 + 3) { e.nextDay() }
        var s = e.state
        let held = HeldMoney.remaining(s, companyID: id)
        let cash = try XCTUnwrap(s.company(id)).cash
        XCTAssertEqual(HeldMoney.settle(&s, companyID: id), held, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(s.company(id)).cash, cash + held, accuracy: 0.01)
        XCTAssertEqual(HeldMoney.remaining(s, companyID: id), 0)
        XCTAssertTrue(Ledger.gaps(s).isEmpty)
    }

    func testASavedWeekFromTheWeeklyTurnLoadsAndIsFinishedByTheDays() throws {
        let (e0, _) = try engine(cafes: 1)
        var s = e0.state
        s.week = 5; s.day = 2
        s.rest["pend"] = .object(["rows": .array([.object(["a": .number(800), "l": .string("Sale"), "co": .number(0), "d": .number(3)])]),
                                  "co": .array([.array([.number(1001), .number(700), .number(0)])]), "msgs": .array([]), "news": .array([])])
        let legacyRemaining = HeldMoney.remaining(s, companyID: 1001)
        let legacyPlayer = HeldMoney.playerRemaining(s)
        let e = GameEngine(state: s, data: e0.data, events: e0.events, marketing: e0.marketing)
        XCTAssertEqual(e.state.rest["pend"]?["v"].int, 2)
        XCTAssertEqual(HeldMoney.remaining(e.state, companyID: 1001), legacyRemaining, accuracy: 0.001)
        XCTAssertEqual(HeldMoney.playerRemaining(e.state), legacyPlayer, accuracy: 0.001)
        XCTAssertEqual(e.state.rest["sliceStart"]?.int, 6, "the week that was already worked out is not worked out again")
    }

    func testAMonthClosesOnItsRealLastDay() throws {
        var (e, ids) = try engine(cafes: 1)
        let id = try XCTUnwrap(ids.first)
        var count = e.state.company(id)?.monthlyHistory.count ?? 0
        var closes = 0
        for _ in 0..<(14 * 7) {
            e.nextDay()
            let n = e.state.company(id)?.monthlyHistory.count ?? 0
            if n != count {
                closes += 1
                XCTAssertTrue(GameCalendar.isMonthEnd(week: e.state.week, day: e.state.day), "closed on week \(e.state.week) day \(e.state.day)")
                count = n
            }
        }
        XCTAssertGreaterThanOrEqual(closes, 2)
    }
}
