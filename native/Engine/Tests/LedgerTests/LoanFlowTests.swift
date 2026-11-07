import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Two-stage loan flow, early repayment that charges nothing twice, payoff with accrued interest, schedule, loan records.
final class LoanFlowTests: XCTestCase {
    private func world(seed: Int = 21, loanAmount: Double = 3_000_000) throws -> (GameEngine, Int, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 400_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 120_000_000) else {
            XCTFail("start"); throw XCTSkip("no company")
        }
        _ = e.quickSetup(companyID: id)
        _ = e.openCompany(companyID: id)
        for _ in 0..<12 { _ = e.nextDay() }
        XCTAssertEqual(e.takeLoan(kind: "biz", amount: loanAmount, termMonths: 36, companyID: id), .ok)
        let loanID = try XCTUnwrap(e.state.loans.last { $0.companyID == id }).id
        return (e, id, loanID)
    }

    private func installments(_ e: GameEngine, _ id: Int) -> [Double] {
        (e.state.company(id)?.transactions ?? []).filter { $0["l"].string.hasPrefix("Loan payment") }.map { -$0["a"].double }
    }

    func testEarlyInstalmentIsNotChargedAgainAtMonthEnd() throws {
        var (e, id, loanID) = try world()
        var control = e
        let rec = try XCTUnwrap(e.loanRecords(companyID: id).first)
        XCTAssertFalse(rec.thisMonthSettled)
        guard case .paid(let paid) = e.payLoanInstalmentNow(loanID: loanID) else { return XCTFail("early payment") }
        XCTAssertEqual(paid, rec.instalment, accuracy: 1, "what is shown is what is taken")
        XCTAssertEqual(e.payLoanInstalmentNow(loanID: loanID), .alreadySettled)
        XCTAssertTrue(e.loanRecords(companyID: id).first?.thisMonthSettled ?? false)
        // The bills list no longer shows this month's instalment.
        let upcoming = e.financeOverview(companyID: id).upcoming.filter { $0.id == "loan\(loanID)" }
        XCTAssertTrue(upcoming.allSatisfy { $0.daysAway > 25 }, "the next month's is shown, not this month's")
        for _ in 0..<75 { _ = e.nextDay(); _ = control.nextDay() }
        let early = installments(e, id), ctl = installments(control, id)
        XCTAssertEqual(early.count, ctl.count, "same number of instalments over the period: the early one replaced one")
        let b1 = e.state.loans.first { $0.id == loanID }?.balance ?? 0
        let b2 = control.state.loans.first { $0.id == loanID }?.balance ?? 0
        XCTAssertEqual(b1, b2, accuracy: 2, "principal is the same: nothing was paid twice")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testPayoffChargesInterestAccruedToTheDay() throws {
        var (e, id, loanID) = try world()
        // Move well into a month (not just after a month end collection).
        while true {
            let l = try XCTUnwrap(e.state.loans.first { $0.id == loanID })
            let d = GameCalendar.date(week: e.state.week, dayOffset: e.state.day)
            if Banking.paidThroughMonth(l) != nil, d.day >= 12, !Banking.instalmentSettled(l, state: e.state) { break }
            _ = e.nextDay()
            if e.state.week > 40 { break }
        }
        let q = try XCTUnwrap(e.loanPayoffQuote(loanID: loanID))
        XCTAssertGreaterThan(q.accruedInterest, 0, "part-month interest is owed at payoff")
        let cash0 = try XCTUnwrap(e.state.company(id)).cash
        XCTAssertTrue(e.payOffLoan(loanID: loanID))
        XCTAssertNil(e.state.loans.first { $0.id == loanID })
        XCTAssertEqual(cash0 - (e.state.company(id)?.cash ?? 0), q.total, accuracy: 1)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testDisplayedInstalmentAfterPartRepaymentIsTheOneCollected() throws {
        var (e, id, loanID) = try world(loanAmount: 4_000_000)
        XCTAssertTrue(e.repayLoan(id: loanID, amount: 3_200_000))
        let shown = try XCTUnwrap(e.loanRecords(companyID: id).first).instalment
        let listed = try XCTUnwrap(e.financeOverview(companyID: id).upcoming.first { $0.id == "loan\(loanID)" }).amount
        XCTAssertEqual(listed, shown, accuracy: 1)
        let before = installments(e, id).count
        for _ in 0..<45 { _ = e.nextDay() }
        let collected = installments(e, id)
        XCTAssertGreaterThan(collected.count, before)
        XCTAssertEqual(collected.first ?? 0, shown, accuracy: max(5, shown * 0.01), "the instalment shown before month end is the one collected")
    }

    func testScheduleFromTheLiveLoan() throws {
        var (e, id, loanID) = try world()
        XCTAssertTrue(e.repayLoan(id: loanID, amount: 500_000))
        let rows = e.loanSchedule(loanID: loanID)
        let l = try XCTUnwrap(e.state.loans.first { $0.id == loanID })
        XCTAssertFalse(rows.isEmpty)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.principal }, l.balance, accuracy: 2)
        XCTAssertEqual(rows.last?.balance ?? -1, 0, accuracy: 1)
        XCTAssertEqual(rows.first?.number, 1)
        _ = id
        _ = e.payLoanInstalmentNow(loanID: loanID)
        let after = e.loanSchedule(loanID: loanID)
        XCTAssertNotEqual(after.first?.dateText, rows.first?.dateText, "paid this month: the schedule starts next month")
    }

    func testTwoStageFlowAssessmentThenAgreement() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 5)
        e.update { s, _, _ in s.credit = 90; s.loans.removeAll(); Ledger.move(&s, .me, 50_000_000, why: "Test funds") }
        let a = e.loanAssessment(kind: "cons", companyID: nil)
        XCTAssertTrue(a.approved)
        XCTAssertGreaterThan(a.maximum, a.minimum)
        XCTAssertEqual(a.payoutAccounts.map(\.id), [.current, .savings])
        XCTAssertFalse(a.examplesAtMaximum.isEmpty)
        XCTAssertTrue(a.conditions.count >= 3)
        let docs = LoanDocuments(fullName: e.state.player.name, incomeProof: .payslips)
        // Above the maximum: refused, nothing moves.
        let cash0 = e.state.cash
        if case .approved = e.applyForLoan(kind: "cons", amount: a.maximum + 100_000, termMonths: 36, companyID: nil, documents: docs, agreed: true) { XCTFail("above the maximum") }
        XCTAssertEqual(e.state.cash, cash0)
        // Below the maximum, paid into savings.
        let amount = (a.maximum / 2 / 1000).rounded() * 1000
        let sav0 = e.state.savings
        guard case .approved(let loanID, let fee, let net) = e.applyForLoan(kind: "cons", amount: amount, termMonths: 36, companyID: nil, documents: docs, agreed: true, payInto: .savings) else { return XCTFail("approved") }
        XCTAssertEqual(e.state.savings - sav0, net, accuracy: 1)
        XCTAssertEqual(net, amount - fee, accuracy: 1)
        XCTAssertEqual(e.state.cash, cash0, accuracy: 2, "the money went to savings, not the current account")
        let rec = try XCTUnwrap(e.loanRecords(companyID: 0).first { $0.id == loanID })
        XCTAssertEqual(rec.payoutAccount, "savings")
        XCTAssertEqual(rec.arrangementFee, fee, accuracy: 0.5)
        XCTAssertTrue(rec.number.hasPrefix("LN-"))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testSaveLoadKeepsLoanMonthMarker() throws {
        var (e, _, loanID) = try world()
        _ = e.payLoanInstalmentNow(loanID: loanID)
        let back = try JSONDecoder().decode(GameState.self, from: try JSONEncoder().encode(e.state))
        XCTAssertEqual(back, e.state)
        XCTAssertNotNil(Banking.paidThroughMonth(try XCTUnwrap(back.loans.first { $0.id == loanID })))
    }
}
