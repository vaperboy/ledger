import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

/// Changing a company's pay day (original `pr29day`): the change applies at once only when this month's payroll is paid,
/// otherwise it is queued (`nday`) and applies after that payroll. No month is paid twice or skipped.
final class PaydayChangeTests: XCTestCase {
    private func cafe(seed: Int = 7) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 500_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 50_000_000) else {
            XCTFail("cafe could not be started"); throw XCTSkip("no cafe")
        }
        return (e, id)
    }

    private func go(_ s: inout GameState, to n: Int) {
        s.week = (n - GameCalendar.startDay) / 7
        s.day = (n - GameCalendar.startDay) % 7
        s.dayMode = true
    }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Int { GameCalendar.daysFromCivil(year: y, month: m, day: d) }
    private func cfg(_ e: GameEngine, _ id: Int) -> Payday.PayrollConfig {
        Payday.config(e.state.company(id)!, today: Payday.dayNumber(week: e.state.week, day: e.state.day))
    }

    /// Puts the company in a clean payroll state on `start`: run by the accountant, wages owed, this month's payday paid or not.
    private func prepare(_ e: inout GameEngine, _ id: Int, start: Int, paidThisMonth: Bool) {
        e.update { s, _, _ in
            go(&s, to: start)
            let i = s.companyIndex(id)!
            Ledger.moveRaw(&s, .company(id), 50_000_000 - s.companies[i].cash)
            s.companies[i].payables["wages"] = 1_000
            var c = Payday.PayrollConfig()
            c.mode = .accountant
            let mi = Payday.monthNumber(start)
            c.paidMonth = paidThisMonth ? mi : mi - 1
            c.billsMonth = mi - 1
            c.ownerPaidMonth = c.paidMonth
            s.companies[i].set("pr29", c.json)
        }
    }

    /// Runs the payday logic day by day from `from` to `to` (inclusive); wages are owed again on the 1st of each month.
    /// Returns the day numbers on which a payroll was paid.
    private func run(_ e: inout GameEngine, _ id: Int, from: Int, to: Int) -> [Int] {
        var paid: [Int] = []
        for n in from...to {
            e.update { s, data, ctx in
                go(&s, to: n)
                let i = s.companyIndex(id)!
                if Payday.civil(n).day == 1 { s.companies[i].payables["wages"] = (s.companies[i].payables["wages"] ?? 0) + 1_000 }
                let before = s.companies[i].payables["wages"] ?? 0
                Payday.onDay(&s, data: data, context: ctx)
                if (s.companies[s.companyIndex(id)!].payables["wages"] ?? 0) < before - 1 { paid.append(n) }
            }
        }
        return paid
    }

    // MARK: Pinned behaviour (before any change)

    func testDefaultPaydayIsThe25thAndPaysOncePerMonth() throws {
        var (e, id) = try cafe()
        let start = date(2026, 11, 2)
        prepare(&e, id, start: start, paidThisMonth: false)
        XCTAssertEqual(cfg(e, id).day, 25)
        XCTAssertNil(cfg(e, id).nextDay)
        let paid = run(&e, id, from: start, to: date(2027, 1, 31))
        let expected = [(2026, 11), (2026, 12), (2027, 1)].map { Payday.payDate(config: Payday.PayrollConfig(), year: $0.0, month: $0.1 - 1) }
        XCTAssertEqual(paid, expected)
    }

    /// Pins the date helpers: months are 0-based (0 = January), as every caller passes them. The 25th of November 2026 is a Wednesday,
    /// the 28th of February 2027 a Sunday (paid the Friday before), and bills fall on the last day of the month itself.
    func testPaydayAndBillDatesFallInTheMonthAsked() {
        let cfg = Payday.PayrollConfig()
        XCTAssertEqual(Payday.payDate(config: cfg, year: 2026, month: 10), date(2026, 11, 25))
        XCTAssertEqual(Payday.billDate(year: 2026, month: 10), date(2026, 11, 30))
        XCTAssertEqual(Payday.billDate(year: 2026, month: 11), date(2026, 12, 31))
        XCTAssertEqual(Payday.billDate(year: 2028, month: 1), date(2028, 2, 29), "leap year")
        var last = cfg; last.day = 0
        XCTAssertEqual(Payday.payDate(config: last, year: 2026, month: 11), date(2026, 12, 31))
        var c28 = cfg; c28.day = 28
        XCTAssertEqual(Payday.payDate(config: c28, year: 2027, month: 1), date(2027, 2, 26), "Sunday 28 Feb moves to Friday 26")
        var c1 = cfg; c1.day = 1
        XCTAssertEqual(Payday.payDate(config: c1, year: 2026, month: 10), date(2026, 11, 2), "Sunday 1 Nov moves to Monday only if Friday leaves the month")
    }

    // MARK: The setter

    func testChangeNowWhenThisMonthIsPaid() throws {
        var (e, id) = try cafe()
        prepare(&e, id, start: date(2026, 11, 27), paidThisMonth: true)
        let r = e.setPayday(companyID: id, day: 10)
        XCTAssertEqual(r, .changedNow(day: 10))
        XCTAssertEqual(cfg(e, id).day, 10)
        XCTAssertNil(cfg(e, id).nextDay)
        let info = try XCTUnwrap(e.paydayInfo(companyID: id))
        XCTAssertTrue(info.paidThisMonth)
        XCTAssertEqual(info.nextPayDay, Payday.payDate(config: cfg(e, id), year: 2026, month: 11), "next payday is next month's 10th (a Sunday moves to the Friday before)")
    }

    func testChangeIsQueuedWhenThisMonthIsNotPaidAndAppliesAfterThatPayroll() throws {
        var (e, id) = try cafe()
        let start = date(2026, 11, 3)
        prepare(&e, id, start: start, paidThisMonth: false)
        XCTAssertEqual(e.setPayday(companyID: id, day: 5), .queued(day: 5))
        XCTAssertEqual(cfg(e, id).day, 25, "still the old day")
        XCTAssertEqual(cfg(e, id).nextDay, 5)
        var old = Payday.PayrollConfig(); old.day = 25
        var new = Payday.PayrollConfig(); new.day = 5
        // November is paid on the old date, then the 5th applies. No month is paid twice or skipped.
        let paid = run(&e, id, from: start, to: date(2027, 2, 28))
        let expected = [Payday.payDate(config: old, year: 2026, month: 10),
                        Payday.payDate(config: new, year: 2026, month: 11),
                        Payday.payDate(config: new, year: 2027, month: 0),
                        Payday.payDate(config: new, year: 2027, month: 1)]
        XCTAssertEqual(paid, expected)
        XCTAssertEqual(cfg(e, id).day, 5)
        XCTAssertNil(cfg(e, id).nextDay)
    }

    func testMovingEarlierAfterPayingDoesNotPayThisMonthAgain() throws {
        var (e, id) = try cafe()
        let start = date(2026, 11, 26)          // the 25th has been paid
        prepare(&e, id, start: start, paidThisMonth: true)
        XCTAssertEqual(e.setPayday(companyID: id, day: 1), .changedNow(day: 1))
        let paid = run(&e, id, from: start, to: date(2027, 1, 15))
        var new = Payday.PayrollConfig(); new.day = 1
        XCTAssertEqual(paid, [Payday.payDate(config: new, year: 2026, month: 11), Payday.payDate(config: new, year: 2027, month: 0)])
    }

    func testMovingLaterBeforePayingPaysOnceOnTheOldDayThenTheNewOne() throws {
        var (e, id) = try cafe()
        let start = date(2026, 11, 20)
        prepare(&e, id, start: start, paidThisMonth: false)
        XCTAssertEqual(e.setPayday(companyID: id, day: 0), .queued(day: 0))
        let paid = run(&e, id, from: start, to: date(2027, 1, 31))
        var old = Payday.PayrollConfig(); old.day = 25
        var last = Payday.PayrollConfig(); last.day = 0
        XCTAssertEqual(paid, [Payday.payDate(config: old, year: 2026, month: 10), Payday.payDate(config: last, year: 2026, month: 11), Payday.payDate(config: last, year: 2027, month: 0)])
    }

    func testChangeIsQueuedWhileWagesAreLate() throws {
        var (e, id) = try cafe()
        prepare(&e, id, start: date(2026, 11, 28), paidThisMonth: true)
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var c = Payday.config(s.companies[i], today: Payday.dayNumber(week: s.week, day: s.day))
            c.lateSince = Payday.dayNumber(week: s.week, day: s.day); c.lateWhy = "cash"; c.lateMonth = c.paidMonth; c.lateOwed = 500
            s.companies[i].set("pr29", c.json)
        }
        XCTAssertEqual(e.setPayday(companyID: id, day: 12), .queued(day: 12), "a late payroll defers the change even though the month counts as paid")
        XCTAssertEqual(cfg(e, id).day, 25)
        let info = try XCTUnwrap(e.paydayInfo(companyID: id))
        XCTAssertFalse(info.changesImmediately)
        XCTAssertTrue(info.isLate)
    }

    func testChoosingTheCurrentDayDropsAQueuedChangeAndBadInputIsRefused() throws {
        var (e, id) = try cafe()
        prepare(&e, id, start: date(2026, 11, 3), paidThisMonth: false)
        XCTAssertEqual(e.setPayday(companyID: id, day: 15), .queued(day: 15))
        XCTAssertEqual(e.setPayday(companyID: id, day: 25), .queueCleared)
        XCTAssertNil(cfg(e, id).nextDay)
        XCTAssertEqual(e.setPayday(companyID: id, day: 25), .unchanged)
        XCTAssertEqual(e.setPayday(companyID: id, day: 31), .invalidDay)
        XCTAssertEqual(e.setPayday(companyID: id, day: 7), .invalidDay)
        XCTAssertEqual(e.setPayday(companyID: 999_999, day: 5), .noCompany)
        XCTAssertEqual(cfg(e, id).day, 25)
    }

    func testQueuedChangeAppliesWhenThereIsNothingToPay() throws {
        var (e, id) = try cafe()
        let start = date(2026, 11, 3)
        prepare(&e, id, start: start, paidThisMonth: false)
        XCTAssertEqual(e.setPayday(companyID: id, day: 5), .queued(day: 5))
        e.update { s, _, _ in s.companies[s.companyIndex(id)!].payables["wages"] = 0; s.companies[s.companyIndex(id)!].staff = []; s.companies[s.companyIndex(id)!].managerID = nil }
        e.update { s, data, ctx in
            go(&s, to: date(2026, 11, 26))
            Payday.onDay(&s, data: data, context: ctx)
        }
        XCTAssertEqual(cfg(e, id).day, 5)
        XCTAssertNil(cfg(e, id).nextDay)
        XCTAssertGreaterThanOrEqual(cfg(e, id).paidMonth, Payday.monthNumber(date(2026, 11, 26)))
    }

    // MARK: Cash timing read model

    func testReadModelShowsWhatEachChoiceMeansForCashTiming() throws {
        var (e, id) = try cafe()
        prepare(&e, id, start: date(2026, 11, 27), paidThisMonth: true)
        let info = try XCTUnwrap(e.paydayInfo(companyID: id))
        XCTAssertTrue(info.changesImmediately)
        XCTAssertEqual(info.choices.count, 9)
        let last = try XCTUnwrap(info.choices.first { $0.day == 0 })
        XCTAssertEqual(last.daysBeforeBills, 0, "wages and rent fall on the same day")
        let first = try XCTUnwrap(info.choices.first { $0.day == 1 })
        XCTAssertGreaterThan(first.daysBeforeBills, 25)
        XCTAssertEqual(info.choices.filter { $0.isCurrent }.map { $0.day }, [25])
        XCTAssertEqual(info.billDay, date(2026, 11, 30))
    }

    // MARK: Saves

    func testPendingDayRoundTripsAndOldSavesLoad() throws {
        var c = Payday.PayrollConfig()
        c.day = 10; c.nextDay = 1
        let j = c.json
        XCTAssertEqual(j["nday"].int, 1)
        XCTAssertEqual(Payday.PayrollConfig(json: j).nextDay, 1)
        var plain = Payday.PayrollConfig(); plain.day = 10
        XCTAssertTrue(plain.json["nday"].isNull, "no key unless a change is waiting")
        XCTAssertNil(Payday.PayrollConfig(json: plain.json).nextDay)

        var (e, id) = try cafe()
        prepare(&e, id, start: date(2026, 11, 3), paidThisMonth: false)
        _ = e.setPayday(companyID: id, day: 15)
        let data = try JSONEncoder().encode(e.state)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(Payday.config(back.company(id)!, today: Payday.dayNumber(week: back.week, day: back.day)).nextDay, 15)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    // MARK: Whole engine

    /// Through the real day loop: wages accrue weekly whatever the pay day, one payroll goes out per month, the books balance.
    func testRealDayLoopAccruesWagesAndPaysOncePerMonthAcrossAChange() throws {
        var (e, id) = try cafe(seed: 3)
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var c = Payday.config(s.companies[i], today: Payday.dayNumber(week: s.week, day: s.day))
            c.mode = .accountant
            s.companies[i].set("pr29", c.json)
            Ledger.moveRaw(&s, .company(id), 100_000_000)
        }
        // Staff so that wages exist.
        let staffBefore = e.state.company(id)!.staff.count
        try XCTSkipIf(staffBefore == 0, "this start-up has no staff to pay")
        var payrollDays: [Int] = []
        var changed = false
        for _ in 0..<110 {
            let pmBefore = cfg(e, id).paidMonth
            e.nextDay()
            let t = Payday.dayNumber(week: e.state.week, day: e.state.day)
            if cfg(e, id).paidMonth > pmBefore { payrollDays.append(t) }
            if !changed { _ = e.setPayday(companyID: id, day: 5); changed = true }
            if e.state.isGameOver { break }
        }
        XCTAssertGreaterThanOrEqual(payrollDays.count, 3, "payroll ran in the real loop: \(payrollDays)")
        let months = payrollDays.map { Payday.monthNumber($0) }
        XCTAssertEqual(months.count, Set(months).count, "never two payrolls in one month: \(payrollDays)")
        if months.count >= 2 { XCTAssertEqual(months.last! - months.first!, months.count - 1, "no month skipped") }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
