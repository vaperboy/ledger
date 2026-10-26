import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

/// The reads and actions behind the company screens: the new-company plan with a chosen place, insurance and advisers,
/// payroll mode and approval, and moving a home-based company into a place and back.
final class CompanyScreensTests: XCTestCase {
    private func game(seed: Int = 7) throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 500_000_000, why: "Test funds") }
        return e
    }

    func testPlanReplacesStandardPremisesCostWithTheChosenPlace() throws {
        let e = try game()
        let city = e.state.player.cityID
        guard let base = e.newCompanyPlan(tradeID: "cafe", cityID: city, form: .limited, size: 1) else { return XCTFail("no plan") }
        XCTAssertEqual(base.premisesKind, .place)
        XCTAssertGreaterThan(base.options.count, 2)
        let std = base.options[base.standardIndex]
        XCTAssertEqual(base.premisesCost, std.rentUpfront, accuracy: 0.5)
        XCTAssertEqual(base.total, base.estimate.total - base.estimate.premises + std.rentUpfront, accuracy: 0.5)
        let buy = e.newCompanyPlan(tradeID: "cafe", cityID: city, form: .limited, size: 1, pick: .init(listingIndex: 0, buy: true))!
        XCTAssertEqual(buy.premisesCost, base.options[0].buyUpfront, accuracy: 0.5)
        XCTAssertGreaterThan(buy.options[0].buyUpfront, buy.options[0].rentUpfront)
        XCTAssertTrue(buy.risks.contains { $0.contains("mortgage") })
        XCTAssertEqual(buy.personalLeft, max(0, buy.available - buy.registrationAndCapital - buy.intoCompany), accuracy: 0.5)
    }

    func testPlanForHomeAndNoPremisesTrades() throws {
        let e = try game()
        let city = e.state.player.cityID
        let home = e.newCompanyPlan(tradeID: "cons", cityID: city, form: .soleTrader, size: 1)!
        XCTAssertEqual(home.premisesKind, .home)
        XCTAssertTrue(home.options.isEmpty)
        XCTAssertTrue(home.risks.contains { $0.contains("starts at home") })
    }

    func testStartingWithAPickedPlaceRentsOrBuysIt() throws {
        var e = try game()
        let city = e.state.player.cityID
        guard case .success(let rented) = e.startCompanyChoosingPremises(tradeID: "cafe", cityID: city, form: .limited, size: 1, name: nil, pick: .init(listingIndex: 4, buy: false), fundWith: 100_000_000) else { return XCTFail("not started") }
        XCTAssertEqual(rented.premises, .ok)
        let p1 = e.state.company(rented.companyID)!.value("prem")
        XCTAssertFalse(p1["owned"].bool)
        XCTAssertGreaterThan(p1["m2"].double, 0)
        guard case .success(let bought) = e.startCompanyChoosingPremises(tradeID: "cafe", cityID: city, form: .limited, size: 1, name: nil, pick: .init(listingIndex: 1, buy: true), fundWith: 200_000_000) else { return XCTFail("not started") }
        XCTAssertEqual(bought.premises, .ok)
        XCTAssertTrue(e.state.company(bought.companyID)!.value("prem")["owned"].bool)
        // No pick behaves like the standard start: quick set-up rents a place.
        guard case .success(let std) = e.startCompanyChoosingPremises(tradeID: "cafe", cityID: city, form: .limited, size: 1, name: nil, pick: nil, fundWith: 100_000_000) else { return XCTFail("not started") }
        XCTAssertNil(std.premises)
        XCTAssertGreaterThan(e.state.company(std.companyID)!.value("prem")["m2"].double, 0)
    }

    func testInsuranceNeedsAnInsurerAndAdvisersCanBeHired() throws {
        var e = try game()
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 50_000_000) else { return XCTFail() }
        e.prepareAdvisers(companyID: id)
        var o = e.coverageOverview(companyID: id)!
        XCTAssertNil(o.insurer)
        XCTAssertEqual(o.policies.count, 6)
        XCTAssertNotNil(o.accountant)
        XCTAssertEqual(e.toggleInsurancePolicy(companyID: id, product: "prop"), .needInsurer)
        let insurers = e.adviserChoices(companyID: id, kind: .insurer)
        XCTAssertFalse(insurers.isEmpty)
        XCTAssertEqual(e.chooseAdviser(companyID: id, kind: .insurer, providerID: insurers[0].id), .done)
        XCTAssertEqual(e.toggleInsurancePolicy(companyID: id, product: "prop"), .done)
        o = e.coverageOverview(companyID: id)!
        XCTAssertEqual(o.insurer?.id, insurers[0].id)
        XCTAssertEqual(o.activeCount, 1)
        XCTAssertGreaterThan(o.weeklyPremiums, 0)
        XCTAssertTrue(e.adviserChoices(companyID: id, kind: .insurer).first { $0.isCurrent } != nil)
        XCTAssertEqual(e.chooseAdviser(companyID: id, kind: .insurer, providerID: 0), .removed)
        XCTAssertNil(e.coverageOverview(companyID: id)!.insurer)
    }

    func testPayrollModeAndApproval() throws {
        var e = try game()
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 50_000_000) else { return XCTFail() }
        var o = e.payrollOverview(companyID: id)!
        XCTAssertEqual(o.mode, .manual)
        XCTAssertFalse(o.modeIsFixed)
        XCTAssertEqual(o.choices.first { $0.mode == .manager }?.unavailable, "Needs a manager first.")
        XCTAssertGreaterThan(o.choices.first { $0.mode == .accountant }!.monthlyFee, 0)
        e.setPayrollMode(companyID: id, mode: .accountant)
        o = e.payrollOverview(companyID: id)!
        XCTAssertEqual(o.mode, .accountant)
        XCTAssertTrue(o.choices.first { $0.mode == .accountant }!.isCurrent)
        // Not owner-run any more: nothing to approve.
        XCTAssertEqual(e.approvePayroll(companyID: id), .notNeeded("Payroll is not run by you at this company."))
        e.setPayrollMode(companyID: id, mode: .manual)
        // Approval needs wages on the books and an unpaid coming pay day.
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].payables["wages"] = 1_000 } }
        o = e.payrollOverview(companyID: id)!
        XCTAssertTrue(o.hasPayroll)
        if o.needsApproval {
            XCTAssertEqual(e.approvePayroll(companyID: id), .approved)
            XCTAssertTrue(e.payrollOverview(companyID: id)!.isApproved)
            XCTAssertEqual(e.approvePayroll(companyID: id), .alreadyApproved)
        }
        XCTAssertNil(e.runLatePayrollNow(companyID: id))
    }

    /// Two owner-run companies with staff, played until the Inbox asks to approve payroll for them.
    private func twoCompaniesAwaitingPayrollApproval() throws -> (GameEngine, [Int], Message) {
        var e = try game()
        e.update { s, _, _ in s.policy.autoPayroll = false }   // routine payroll is approved by policy otherwise
        var ids: [Int] = []
        for _ in 0..<2 {
            guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 50_000_000) else { throw XCTSkip("no company") }
            ids.append(id)
        }
        var days = 0
        while !e.openDecisions.contains(where: { $0.actionID == "pay29all" }), days < 200 * 7 { e.nextDay(); days += 1 }
        let msg = try XCTUnwrap(e.openDecisions.first { $0.actionID == "pay29all" }, "an approval message")
        XCTAssertTrue(ids.allSatisfy { id in msg.value("data")["ids"].array.contains { $0.int == id } }, "one message for both companies")
        return (e, ids, msg)
    }

    func testApprovingPayrollInCompanyClosesTheInboxMessageOnceEveryCompanyIsApproved() throws {
        var (e, ids, msg) = try twoCompaniesAwaitingPayrollApproval()
        XCTAssertEqual(e.approvePayroll(companyID: ids[0]), .approved)
        let mid = try XCTUnwrap(e.state.inbox.first { $0.id == msg.id })
        XCTAssertEqual(mid.status, "open", "the other company still waits")
        XCTAssertEqual(mid.value("data")["ids"].array.map { $0.int }, [ids[1]], "the message now asks only about the company left")
        XCTAssertEqual(e.approvePayroll(companyID: ids[1]), .approved)
        let done = try XCTUnwrap(e.state.inbox.first { $0.id == msg.id })
        XCTAssertEqual(done.status, "done")
        XCTAssertTrue(done.isRead)
        XCTAssertTrue(e.openDecisions.filter { $0.actionID == "pay29all" }.isEmpty)
        XCTAssertTrue(ids.allSatisfy { e.payrollOverview(companyID: $0)!.isApproved })
    }

    func testAnsweringThePayrollMessageInTheInboxApprovesBothCompaniesInCompany() throws {
        var (e, ids, msg) = try twoCompaniesAwaitingPayrollApproval()
        XCTAssertTrue(e.answer(messageID: msg.id, option: 0))
        XCTAssertEqual(e.state.inbox.first { $0.id == msg.id }?.status, "done")
        XCTAssertTrue(ids.allSatisfy { e.payrollOverview(companyID: $0)!.isApproved })
        XCTAssertEqual(e.approvePayroll(companyID: ids[0]), .alreadyApproved)
    }

    func testApprovingInCompanyFirstThenTheInboxMessageNeedsNoAnswer() throws {
        var (e, ids, msg) = try twoCompaniesAwaitingPayrollApproval()
        XCTAssertEqual(e.approvePayroll(companyID: ids[0]), .approved)
        XCTAssertEqual(e.approvePayroll(companyID: ids[1]), .approved)
        XCTAssertFalse(e.answer(messageID: msg.id, option: 0), "already closed")
        XCTAssertEqual(e.state.inbox.first { $0.id == msg.id }?.status, "done")
    }

    func testMovingAHomeCompanyIntoAPlaceAndBack() throws {
        var e = try game()
        guard case .success(let id) = e.startCompany(tradeID: "cons", cityID: e.state.player.cityID, form: .soleTrader, fundWith: 50_000_000) else { return XCTFail() }
        XCTAssertTrue(e.isWorkingFromHome(companyID: id))
        XCTAssertNil(e.moveHomeQuote(companyID: id))
        let l = e.premisesListings(companyID: id)
        XCTAssertGreaterThan(l.count, 2)
        XCTAssertEqual(e.takePremises(companyID: id, listing: l[2], buy: false), .ok)
        XCTAssertFalse(e.isWorkingFromHome(companyID: id))
        let q = e.moveHomeQuote(companyID: id)!
        XCTAssertFalse(q.isOwned)
        XCTAssertGreaterThan(q.proceeds, 0)
        let before = e.state.company(id)!.cash
        XCTAssertTrue(e.giveUpPremises(companyID: id))
        XCTAssertEqual(e.state.company(id)!.cash - before, q.proceeds, accuracy: 1)
        XCTAssertTrue(e.isWorkingFromHome(companyID: id))
    }
}
