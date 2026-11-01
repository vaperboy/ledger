import XCTest
import GameCore
import Finance
import Businesses
import Simulation

final class InboxAndReportReadsTests: XCTestCase {
    func testMovementKinds() {
        XCTAssertEqual(GameEngine.movementKind("Payroll · 3 payslips"), .payroll)
        XCTAssertEqual(GameEngine.movementKind("Rent"), .bills)
        XCTAssertEqual(GameEngine.movementKind("Monthly bills: suppliers, insurance, leasing, fees"), .bills)
        XCTAssertEqual(GameEngine.movementKind("VAT settlement"), .tax)
        XCTAssertEqual(GameEngine.movementKind("Dividend"), .owner)
        XCTAssertEqual(GameEngine.movementKind("Loan to franchisee X"), .other)
    }

    func testShowcaseMovementsAreNewestFirstAndFilter() throws {
        let e = try GameEngine.showcase(days: 70)
        let all = e.companyMovements()
        XCTAssertFalse(all.isEmpty, "a showcase game a few months in has company movements")
        XCTAssertEqual(all.map { $0.week }, all.map { $0.week }.sorted(by: >))
        XCTAssertEqual(Set(all.map { $0.id }).count, all.count)
        let id = all[0].companyID
        XCTAssertTrue(e.companyMovements(companyID: id).allSatisfy { $0.companyID == id })
        let w = all[0].week
        XCTAssertTrue(e.companyMovements(weeks: w...w).allSatisfy { $0.week == w })
        XCTAssertTrue(all.contains { $0.kind == .payroll || $0.kind == .bills }, "payroll or bills were paid in two months")
    }

    func testExpiryAndAnsweredOutcome() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 3)
        var id = 0
        e.update { s, _, _ in
            id = s.addMessage(kind: "ask", from: "X", title: "Offer", body: "", status: "open", options: [.option("Accept"), .option("Decline")],
                              action: "ctv", data: .object(["k": "offer", "u": 1, "who": "Y", "when": 3]), expiresWeek: s.week + 2)
        }
        let m = e.state.inbox.first { $0.id == id }!
        XCTAssertEqual(e.expiryOutcome(m), "If you leave it, the offer lapses and nothing changes.")
        XCTAssertNil(e.answeredOutcome(m))
        XCTAssertTrue(e.answer(messageID: id, option: 1))
        let done = e.state.inbox.first { $0.id == id }!
        XCTAssertEqual(e.answeredOutcome(done), "You chose: Decline")
        XCTAssertNil(e.expiryOutcome(done))
    }

    func testYachtDinnerQuoteMatchesWhatIsCharged() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 5)
        XCTAssertNil(e.yachtDinnerQuote())
        e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
        guard let yacht = Luxury.categories.first(where: { $0.id == "yachts" })?.items.first else { return XCTFail("no yachts") }
        XCTAssertEqual(e.buyLuxury(itemID: yacht.id), .ok)
        guard let q = e.yachtDinnerQuote() else { return XCTFail("quote") }
        XCTAssertEqual(q.waitWeeks, 0)
        let before = e.state.cash
        guard case .ok = e.hostYachtDinner() else { return XCTFail("dinner") }
        XCTAssertEqual(before - e.state.cash, q.cost, accuracy: 0.5)
        XCTAssertEqual(e.yachtDinnerQuote()?.waitWeeks, 4)
    }
}
