import XCTest
import GameCore
import Finance
import Businesses
import Simulation

/// Stage 2 item 4: the player does not choose who runs payroll; it is derived (qualified accountant, else suitable manager, else the player).
final class PayrollResponsibilityTests: XCTestCase {
    func testDerivedRuleAndLegacyChoiceKept() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 3)
        e.update { s, _, _ in Ledger.move(&s, .me, 300_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .soleTrader, fundWith: 100_000_000) else { return XCTFail("start") }
        _ = e.quickSetup(companyID: id)
        // No accountant, no manager: the player. Nobody was appointed automatically.
        XCTAssertNil(e.state.company(id)?.value("acc")["id"].isNull == false ? 1 : nil)
        var o = try XCTUnwrap(e.payrollOverview(companyID: id))
        XCTAssertEqual(o.responsibility?.who, .owner)
        XCTAssertEqual(o.mode, .manual)
        // A legacy choice is kept in the save but does not decide.
        _ = e.setPayrollMode(companyID: id, mode: .manager)
        o = try XCTUnwrap(e.payrollOverview(companyID: id))
        XCTAssertEqual(o.legacyChosenMode, .manager)
        XCTAssertEqual(o.responsibility?.who, .owner)
        XCTAssertEqual(o.mode, .manual)
        // The legal form requires an accountant: after conversion the accountant runs it, with no per-run fee.
        XCTAssertEqual(e.convertToLimited(companyID: id), .ok)
        o = try XCTUnwrap(e.payrollOverview(companyID: id))
        XCTAssertEqual(o.responsibility?.who, .accountant)
        XCTAssertEqual(o.mode, .accountant)
        XCTAssertGreaterThan(o.choices.first { $0.mode == .accountant }?.monthlyFee ?? 0, 0, "an external accountant charges a payroll service fee")
        XCTAssertEqual(o.choices.first { $0.mode == .manager }?.monthlyFee, 0)
        XCTAssertEqual(o.choices.first { $0.mode == .manual }?.monthlyFee, 0)
        XCTAssertEqual(o.legacyChosenMode, .manager, "nothing is lost")
        // Payroll runs through the existing engine and stays consistent.
        for _ in 0..<70 { _ = e.nextDay() }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        // The fee is booked in Accounting and shown on the run.
        let runs = try XCTUnwrap(e.payrollRuns(companyID: id))
        XCTAssertFalse(runs.isEmpty)
        XCTAssertGreaterThan(runs[0].serviceFee, 0)
        let fees = try XCTUnwrap(e.companyTransactions(companyID: id, search: "Payroll service"))
        XCTAssertFalse(fees.entries.isEmpty)
        XCTAssertEqual(fees.entries.first?.categoryID, "accounting")
        XCTAssertGreaterThan(try XCTUnwrap(e.payrollRunReview(companyID: id)).serviceFee, 0)
    }

    /// An employed accountant, a manager or the player running payroll charge nothing extra.
    func testNoServiceFeeWhenEmployedAccountantOrPlayerRunsPayroll() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 6)
        e.update { s, _, _ in Ledger.move(&s, .me, 300_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 100_000_000) else { return XCTFail("start") }
        XCTAssertGreaterThan(e.payrollOverview(companyID: id)?.choices.first { $0.mode == .accountant }?.monthlyFee ?? 0, 0)
        // Replace the external firm by an employed accountant.
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].raw.removeValue(forKey: "acc")
            var m = StaffMember(raw: [:]); m.id = 424242; m.set("role", "acct"); m.monthlyWage = 40000
            s.companies[i].staff = s.companies[i].staff + [m]
        }
        let o = try XCTUnwrap(e.payrollOverview(companyID: id))
        XCTAssertEqual(o.responsibility?.who, .accountant)
        XCTAssertTrue(o.choices.allSatisfy { $0.monthlyFee == 0 }, "an employed accountant is on salary: no extra fee")
    }


    func testNewSoleTraderGetsNoAutomaticAccountant() throws {
        var e = try GameEngine.newGame(countryCode: "DE", playerName: "Tester", seed: 4)
        e.update { s, _, _ in Ledger.move(&s, .me, 300_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .soleTrader, fundWith: 100_000_000) else { return XCTFail("start") }
        XCTAssertTrue(e.state.company(id)?.value("acc")["id"].isNull ?? true)
        guard case .success(let id2) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 100_000_000) else { return XCTFail("start limited") }
        XCTAssertFalse(e.state.company(id2)?.value("acc")["id"].isNull ?? true, "the legal form requires one (accountant agreement)")
    }
}
