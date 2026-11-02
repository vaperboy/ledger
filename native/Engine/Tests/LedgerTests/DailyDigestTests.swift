import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The daily popup's figures come from the day's real trade and the day's real messages, nothing else.
final class DailyDigestTests: XCTestCase {
    func newEngine() throws -> GameEngine { try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4242) }

    func testMessagesAreSortedIntoWentWellAndNeedsALook() throws {
        let e = try newEngine()
        let good = Message(raw: ["title": .string("A big order"), "tone": .string("good"), "status": .string("done")])
        let ask = Message(raw: ["title": .string("Approve the budget"), "tone": .string("n"), "status": .string("open")])
        let bad = Message(raw: ["title": .string("A fine arrived"), "tone": .string("bad"), "status": .string("done")])
        let plain = Message(raw: ["title": .string("Just so you know"), "tone": .string("n"), "status": .string("done")])
        let d = e.dailyDigest(fresh: [good, ask, bad, plain])
        XCTAssertEqual(d.wentWell, ["A big order"])
        XCTAssertEqual(d.staffMessages, ["Approve the budget", "A fine arrived"])
        XCTAssertFalse(d.isEmpty)
    }

    func testNoCompaniesAndNoMessagesIsAnEmptyDay() throws {
        let e = try newEngine()
        let d = e.dailyDigest(fresh: [])
        XCTAssertEqual(d.sales, 0)
        XCTAssertEqual(d.revenue, 0)
        XCTAssertNil(d.bestCompany)
        XCTAssertTrue(d.isEmpty)
    }

    func testSalesAddUpToTheCompanysOwnDailyLog() throws {
        var e = try newEngine()
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 50_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        XCTAssertNotEqual(id, 0)
        while e.state.day != 0 && !e.state.isGameOver { e.nextDay() }
        var total = 0
        var seen = 0
        while e.state.day < 6 && !e.state.isGameOver {
            e.nextDay()
            guard e.state.day != 0 else { break }
            let d = e.dailyDigest(fresh: [])
            total += d.sales
            seen += 1
            XCTAssertGreaterThanOrEqual(d.revenue, 0)
        }
        XCTAssertGreaterThan(seen, 0)
        let log = e.state.companies.first { $0.id == id }?.value("dl") ?? .null
        let logged = Int(log["days"].object.values.reduce(0.0) { $0 + $1["u"].double })
        XCTAssertEqual(total, logged)
    }
}
