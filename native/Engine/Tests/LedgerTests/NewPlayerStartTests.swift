import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

final class NewPlayerStartTests: XCTestCase {
    private func fresh(_ country: String = "NO", trade: String = "cafe", seed: Int = 1) throws -> GameEngine {
        try GameEngine.newGame(countryCode: country, playerName: "T", seed: seed, story: .fresh, tradeID: trade, companyName: "Test Café")
    }

    func testCompanyIsOpenOnDayOneWithNoLoan() throws {
        for code in ["NO", "US", "JP"] {
            let e = try fresh(code)
            let co = try XCTUnwrap(e.state.companies.first)
            XCTAssertEqual(co.status, .open, code)
            XCTAssertEqual(co.name, "Test Café")
            XCTAssertTrue(e.state.loans.isEmpty)
            XCTAssertEqual(e.state.week, 0)
            XCTAssertEqual(co.cash, e.state.cash, accuracy: 0.5, code)
            XCTAssertGreaterThan(e.state.cash, 0, code)
            XCTAssertTrue(e.openingChecklist(companyID: co.id).allSatisfy { $0.isDone }, code)
            XCTAssertEqual(e.lifeStory, .fresh)
        }
    }

    func testCashLeftAfterSetupCoversEightWeeksOfCosts() throws {
        for code in ["NO", "US"] {
            let e = try fresh(code)
            let co = try XCTUnwrap(e.state.companies.first)
            let weekly = e.context.weeklyCost(co, e.state)
            XCTAssertGreaterThanOrEqual(co.cash, weekly * 8 - 1, code)
        }
    }

    func testAmbitionIsHeldBackUntilTheLadderRaisesIt() throws {
        var e = try fresh()
        XCTAssertFalse(e.ambitionVisible)
        XCTAssertFalse(e.ambitionCardPending)
        e.update { s, _, _ in
            var l = s.rest["ldr"] ?? .object([:]); l["amb"] = 1; s.rest["ldr"] = l
            s.week = 9
        }
        XCTAssertTrue(e.ambitionVisible)
        XCTAssertTrue(e.ambitionCardPending, "the card may appear after M7 even past week 4")
        XCTAssertTrue(e.chooseAmbition(path: "titan"))
        XCTAssertTrue(e.ambitionChangeIsFree)
        e.update { s, _, _ in s.week = 14 }
        XCTAssertFalse(e.ambitionChangeIsFree, "four weeks after it was chosen")
    }

    func testABillTheCashCannotCoverWaitsUntilTomorrowWithoutConsequences() throws {
        var e = try fresh()
        let id = try XCTUnwrap(e.state.companies.first?.id)
        e.update { s, data, ctx in
            guard let i = s.companyIndex(id) else { return }
            Ledger.set(&s, to: 10)
            s.companies[i].payables["other"] = 5000
            s.companies[i].payables["rent"] = 0
            var cfg = Payday.config(s.companies[i], today: Payday.dayNumber(week: s.week, day: s.day))
            cfg.billsMonth = -5
            s.companies[i].set("pr29", cfg.json)
            Payday.onDay(&s, data: data, context: ctx)
            XCTAssertEqual(s.companies[i].payables["other"] ?? 0, 5000, accuracy: 0.5, "nothing paid, nothing lost")
            XCTAssertEqual(s.companies[i].cash, 10, accuracy: 0.5, "no overdraft")
            XCTAssertNotNil(s.rest["tight"])
            Ledger.set(&s, to: 9000)
            Payday.onDay(&s, data: data, context: ctx)
            XCTAssertNil(s.rest["tight"], "paid the next day, banner gone")
            XCTAssertEqual(s.companies[i].payables["other"] ?? 0, 0, accuracy: 1)
            XCTAssertGreaterThanOrEqual(s.companies[i].cash, 0)
        }
    }

    func testNoOverdraftProtectionEndsAfterTwelveWeeks() throws {
        var e = try fresh()
        XCTAssertTrue(e.data.balance.firstYear.noOverdraftActive(e.state))
        e.update { s, _, _ in s.week = 12 }
        XCTAssertFalse(e.data.balance.firstYear.noOverdraftActive(e.state))
    }

    func testFirstNinetyDaysOfTheDefaultCafeAreSensible() throws {
        for code in ["NO", "US", "JP", "BR"] {
            var e = try fresh(code, seed: 7)
            let id = try XCTUnwrap(e.state.companies.first?.id)
            let start = e.state.company(id)?.cash ?? 0
            var cash: [Double] = []
            for _ in 0..<91 { _ = e.nextDay(); cash.append(e.state.company(id)?.cash ?? 0) }
            let co = try XCTUnwrap(e.state.company(id))
            print("FIRST90 \(code) start=\(start) w4=\(cash[27]) w8=\(cash[55]) w13=\(cash[90]) status=\(co.status)")
            XCTAssertEqual(co.status, .open, code)
            XCTAssertGreaterThanOrEqual(cash.min() ?? 0, 0, "\(code): never below zero in the protected weeks")
        }
    }
}
