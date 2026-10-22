import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

/// Missed bills, missed loan instalments, an unpaid VAT return, rent between two companies of yours, and loan rates abroad.
/// Written by tracing the code (no Swift toolchain was available when they were added).
final class BillsAndLoansTests: XCTestCase {
    private func cafe(seed: Int = 7) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 500_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 5_000_000) else {
            XCTFail("cafe could not be started"); throw XCTSkip("no cafe")
        }
        return (e, id)
    }

    /// Leaves the company with exactly zero spendable money (cash at the bottom of its overdraft room).
    private func drain(_ s: inout GameState, _ id: Int, _ ctx: FinanceContext) {
        let i = s.companyIndex(id)!
        let room = ctx.overdraftRoom(s.companies[i], s)
        Ledger.moveRaw(&s, .company(id), -(s.companies[i].cash + room))
    }

    private func fund(_ s: inout GameState, _ id: Int, _ amount: Double) {
        Ledger.moveRaw(&s, .company(id), amount - s.companies[s.companyIndex(id)!].cash)
    }

    // MARK: (1) Late fees and supplier cut-off

    func testMissedSupplierBillsCarryLateInterestAndCutOffSuppliers() throws {
        var (e, id) = try cafe(seed: 21)
        var cash0 = 0.0
        e.update { s, _, ctx in
            drain(&s, id, ctx)
            let i = s.companyIndex(id)!
            s.companies[i].payables = ["other": 5_000_000]
            cash0 = s.companies[i].cash
            let t = Payday.dayNumber(week: s.week, day: s.day)
            _ = Payday.payBills(&s, i, today: t, context: ctx)
        }
        var co = try XCTUnwrap(e.state.company(id))
        var t = Payday.dayNumber(week: e.state.week, day: e.state.day)
        XCTAssertEqual(co.cash, cash0, accuracy: 1, "nothing could be paid")
        XCTAssertEqual(co.payables["other"] ?? 0, 5_000_000, accuracy: 1, "no fee on the first miss")
        XCTAssertEqual(Payday.config(co, today: t).arrears["other"] ?? 0, 5_000_000, accuracy: 1)
        XCTAssertEqual(co.int("supCut"), 0)

        e.update { s, _, ctx in
            let i = s.companyIndex(id)!
            _ = Payday.payBills(&s, i, today: t, context: ctx)
        }
        co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.payables["other"] ?? 0, 5_100_000, accuracy: 2, "2 % late interest on the 5 000 000 left over")
        XCTAssertGreaterThan(co.books.year["int"] ?? 0, 0)
        XCTAssertEqual(co.int("supCut"), 1, "second miss: stock only against cash")
        XCTAssertTrue(e.state.inbox.contains { $0.title.hasPrefix("Late fees") })

        e.update { s, _, ctx in
            let i = s.companyIndex(id)!
            _ = Payday.payBills(&s, i, today: t, context: ctx)
        }
        co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.int("supCut"), 2, "third miss: no stock at all")

        // Recovery: pay everything.
        e.update { s, _, ctx in
            fund(&s, id, 50_000_000)
            let i = s.companyIndex(id)!
            _ = Payday.payBills(&s, i, today: t, context: ctx)
        }
        co = try XCTUnwrap(e.state.company(id))
        t = Payday.dayNumber(week: e.state.week, day: e.state.day)
        XCTAssertLessThan(co.payables["other"] ?? 0, 1)
        XCTAssertEqual(co.int("supCut"), 0)
        XCTAssertEqual(Payday.config(co, today: t).billShortMonths, 0)
        XCTAssertTrue(e.state.inbox.contains { $0.title.hasPrefix("Suppliers deliver normally") })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testOldSaveWithoutArrearsLoads() throws {
        let cfg = Payday.PayrollConfig(json: .object(["day": 25, "pm": 3, "bs": 1]))
        XCTAssertTrue(cfg.arrears.isEmpty)
        XCTAssertEqual(Payday.PayrollConfig(json: cfg.json).billShortMonths, 1)
        var withArrears = cfg
        withArrears.arrears["rent"] = 120
        XCTAssertEqual(Payday.PayrollConfig(json: withArrears.json).arrears["rent"], 120)
    }

    // MARK: (4) Rent: the landlord is paid when the tenant pays

    func testLandlordIsPaidWhenTenantPaysNotWeekly() throws {
        var (e, tenant) = try cafe(seed: 31)
        guard case .success(let landlord) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 5_000_000) else {
            throw XCTSkip("no second company")
        }
        e.update { s, data, ctx in
            let ti = s.companyIndex(tenant)!, li = s.companyIndex(landlord)!
            s.companies[li].status = .open
            s.companies[ti].set("prem", .object(["kind": "office", "m2": 50, "rent": 52_000, "owned": false, "val": 0, "loan": 0]))
            s.companies[ti].set("landlord", .object(["co": .number(Double(landlord)), "pid": 999]))
            s.companies[ti].payables = [:]
            fund(&s, tenant, 50_000_000)
            let landlordCash = s.companies[li].cash
            for _ in 0..<4 { CompanyCosts.rent(&s, companyIndex: ti, data: data) }
            XCTAssertEqual(s.companies[li].cash, landlordCash, accuracy: 0.5, "rent accrued, nothing received yet")
            let owed = s.companies[ti].payables["rent"] ?? 0
            XCTAssertGreaterThan(owed, 0)
            let tenantCash = s.companies[ti].cash
            let t = Payday.dayNumber(week: s.week, day: s.day)
            _ = Payday.payBills(&s, ti, today: t, context: ctx)
            let paid = tenantCash - s.companies[ti].cash
            XCTAssertGreaterThanOrEqual(paid, owed - 1)
            XCTAssertEqual(s.companies[li].cash - landlordCash, owed * 0.97, accuracy: 2, "landlord gets 97 % of what was paid, in the same month")
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testLandlordGetsNothingWhileTenantCannotPay() throws {
        var (e, tenant) = try cafe(seed: 32)
        guard case .success(let landlord) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 5_000_000) else {
            throw XCTSkip("no second company")
        }
        e.update { s, _, ctx in
            let ti = s.companyIndex(tenant)!, li = s.companyIndex(landlord)!
            s.companies[li].status = .open
            s.companies[ti].set("landlord", .object(["co": .number(Double(landlord)), "pid": 999]))
            drain(&s, tenant, ctx)
            s.companies[ti].payables = ["rent": 2_000_000]
            let before = s.companies[li].cash
            _ = Payday.payBills(&s, ti, today: Payday.dayNumber(week: s.week, day: s.day), context: ctx)
            XCTAssertEqual(s.companies[li].cash, before, accuracy: 0.5)
            XCTAssertEqual(s.companies[ti].payables["rent"] ?? 0, 2_000_000, accuracy: 1)
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    // MARK: (2) Company loan instalments

    private func addLoan(_ s: inout GameState, company id: Int, balance: Double = 1_000_000) -> Int {
        var l = Loan(raw: [:])
        l.id = s.makeID(); l.kind = "biz"; l.name = "Business loan"; l.balance = balance; l.originalAmount = balance
        l.margin = 0.04; l.termMonths = 60; l.companyID = id; l.startWeek = s.week; l.monthlyPayment = 25_000
        s.loans.append(l)
        return l.id
    }

    func testMissedInstalmentEscalatesAndRecovers() throws {
        var (e, id) = try cafe(seed: 41)
        var loanID = 0
        e.update { s, _, ctx in
            loanID = addLoan(&s, company: id)
            drain(&s, id, ctx)
        }
        let cash0 = try XCTUnwrap(e.state.company(id)).cash
        var balance = 1_000_000.0
        for n in 1...3 {
            e.update { s, _, ctx in Banking.collectMonthlyInstalments(state: &s, context: ctx) }
            let l = try XCTUnwrap(e.state.loans.first { $0.id == loanID })
            XCTAssertEqual(l.int("miss"), n)
            XCTAssertGreaterThan(l.balance, balance, "unpaid interest and a penalty are added")
            balance = l.balance
            XCTAssertEqual(try XCTUnwrap(e.state.company(id)).cash, cash0, accuracy: 1, "no cash moved")
        }
        var co = try XCTUnwrap(e.state.company(id))
        XCTAssertTrue(co.flag("loanFrozen"))
        XCTAssertGreaterThan(co.int("loanCall"), e.state.week - 1)
        XCTAssertGreaterThan(co.books.year["int"] ?? 0, 0)
        e.update { s, _, ctx in
            let off = Banking.offer(kind: "biz", amount: 10_000, company: s.companies[s.companyIndex(id)!], state: s, netWorth: 1e9, context: ctx)
            XCTAssertEqual(off.maximum, 0, "the bank lends nothing more")
        }
        XCTAssertTrue(e.state.inbox.contains { $0.title.hasPrefix("Bank calls the loan") })

        // Money comes in, the next instalment is paid: back on track.
        e.update { s, _, ctx in
            fund(&s, id, 100_000_000)
            Banking.collectMonthlyInstalments(state: &s, context: ctx)
        }
        co = try XCTUnwrap(e.state.company(id))
        let l = try XCTUnwrap(e.state.loans.first { $0.id == loanID })
        XCTAssertEqual(l.int("miss"), 0)
        XCTAssertFalse(co.flag("loanFrozen"))
        XCTAssertEqual(co.int("loanCall"), 0)
        XCTAssertLessThan(co.cash, 100_000_000, "the instalment left the account")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testCalledLoanEndsInBankruptcy() throws {
        var (e, id) = try cafe(seed: 42)
        e.update { s, data, ctx in
            _ = addLoan(&s, company: id)
            Failure.bankrupt(&s, companyIndex: s.companyIndex(id)!, reason: "loan", data: data, context: ctx)
        }
        XCTAssertEqual(e.state.company(id)?.status, .bust)
        XCTAssertTrue(e.state.inbox.contains { $0.body.contains("called its loan") })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testPaidInstalmentIsUnchangedWhenCashAllows() throws {
        var (e, id) = try cafe(seed: 43)
        var loanID = 0
        e.update { s, _, _ in loanID = addLoan(&s, company: id); fund(&s, id, 50_000_000) }
        e.update { s, _, ctx in Banking.collectMonthlyInstalments(state: &s, context: ctx) }
        let l = try XCTUnwrap(e.state.loans.first { $0.id == loanID })
        XCTAssertEqual(l.int("miss"), 0)
        XCTAssertLessThan(l.balance, 1_000_000)
        XCTAssertLessThan(try XCTUnwrap(e.state.company(id)).cash, 50_000_000)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    // MARK: (3) VAT return

    func testUnpaidVatReturnIsLateAndPenalised() throws {
        var (e, id) = try cafe(seed: 51)
        var filingWeek = 0, otherWeek = 0
        e.update { s, data, _ in
            let c = data.countries.resolve(s.companies[s.companyIndex(id)!].countryCode, orHome: s.homeCountryCode)
            let freq = max(1, c.vatFilingMonths == 0 ? 2 : c.vatFilingMonths)
            filingWeek = (60..<200).first { GameCalendar.monthIndex(week: $0) % freq == freq - 1 } ?? 0
            otherWeek = (filingWeek..<filingWeek + 40).first { GameCalendar.monthIndex(week: $0) % freq != freq - 1 } ?? filingWeek
        }
        try XCTSkipIf(filingWeek == 0)
        e.update { s, data, ctx in
            s.week = filingWeek
            drain(&s, id, ctx)
            let i = s.companyIndex(id)!
            s.companies[i].vatBalance = 5_000_000
            let cash0 = s.companies[i].cash
            MonthEnd.closeMonth(&s, companyIndex: i, data: data, context: ctx)
            let co = s.companies[i]
            XCTAssertGreaterThanOrEqual(co.cash, cash0 - 1, "no silent overdraft")
            XCTAssertGreaterThan(co.vatBalance, 5_000_000, "penalty added")
            XCTAssertGreaterThan(co.num("vatOver"), 5_000_000)
            XCTAssertGreaterThanOrEqual(co.unpaidMonths, 1, "counts as unpaid")
        }
        XCTAssertTrue(e.state.inbox.contains { $0.title.hasPrefix("VAT return not paid") })
        // Interest runs, and paying it clears everything.
        e.update { s, data, ctx in
            s.week = otherWeek
            let i = s.companyIndex(id)!
            let owed0 = s.companies[i].vatBalance
            if otherWeek != filingWeek {
                MonthEnd.closeMonth(&s, companyIndex: i, data: data, context: ctx)
                XCTAssertGreaterThan(s.companies[i].vatBalance, owed0 - 1, "1 % interest, still unpaid")
            }
            fund(&s, id, 500_000_000)
            MonthEnd.closeMonth(&s, companyIndex: i, data: data, context: ctx)
            XCTAssertEqual(s.companies[i].num("vatOver"), 0, accuracy: 1)
            XCTAssertLessThan(abs(s.companies[i].vatBalance), 100, "paid up")
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    // MARK: (5) Loan rates abroad

    func testCompanyLoanRateUsesItsOwnCountry() throws {
        var (e, id) = try cafe(seed: 61)
        var shift = 0.0, homeShift = 1.0
        e.update { s, data, ctx in
            homeShift = Banking.countryRateShift(companyID: id, state: s, context: ctx)
            let i = s.companyIndex(id)!
            s.companies[i].countryCode = "BR"
            shift = Banking.countryRateShift(companyID: id, state: s, context: ctx)
            let expected = (data.countries["BR"]?.startingPolicyRate ?? 0) - (data.countries[s.homeCountryCode]?.startingPolicyRate ?? 0)
            XCTAssertEqual(shift, expected, accuracy: 1e-9)
        }
        XCTAssertEqual(homeShift, 0, accuracy: 1e-12, "a company at home pays the home rate")
        XCTAssertGreaterThan(shift, 0.05, "Brazil's policy rate is far above the UK's")
        var loanID = 0
        e.update { s, _, _ in
            loanID = addLoan(&s, company: id)
            fund(&s, id, 50_000_000)
            var b = s.companies[s.companyIndex(id)!].books; b.month = [:]; b.year = [:]; s.companies[s.companyIndex(id)!].books = b
        }
        let policy = e.state.economy.policyRate
        e.update { s, _, ctx in Banking.collectMonthlyInstalments(state: &s, context: ctx) }
        let b = try XCTUnwrap(e.state.company(id)).books
        let interest = b.year["int"] ?? 0
        let expected = 1_000_000 * (policy + shift + 0.04) / 12
        XCTAssertEqual(interest, expected, accuracy: expected * 0.01 + 1)
        XCTAssertNotNil(e.state.loans.first { $0.id == loanID })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
