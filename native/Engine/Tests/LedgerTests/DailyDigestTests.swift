import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

final class DailyDigestTests: XCTestCase {
    func newEngine() throws -> GameEngine { try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4242) }

    func testTheDayCarriesReportLinesNotTheTextOfMessagesOrDecisions() throws {
        var e = try newEngine()
        e.update { s, _, _ in
            s.feedLine("A big order", tone: "good")
            s.feedLine("A fine arrived", tone: "bad")
            s.feedLine("Just so you know")
        }
        let ask = Message(raw: ["title": .string("Approve the budget"), "tone": .string("n"), "status": .string("open"), "opts": .array([.option("Ok")])])
        let news = Message(raw: ["title": .string("A rival opened"), "tone": .string("bad"), "status": .string("done")])
        let d = e.dailyDigest(fresh: [ask, news])
        XCTAssertEqual(d.wentWell, ["A big order"])
        XCTAssertEqual(d.staffMessages, ["A fine arrived"], "the decision pops up on Home and the message waits in the inbox")
        XCTAssertFalse(d.isEmpty)
    }

    func testNewMessagesAreCountedNotRepeated() throws {
        let e = try newEngine()
        let ask = Message(raw: ["title": .string("Approve the budget"), "tone": .string("n"), "status": .string("open"), "opts": .array([.option("Ok")])])
        let one = Message(raw: ["title": .string("A rival opened"), "tone": .string("bad"), "status": .string("done")])
        let two = Message(raw: ["title": .string("A letter"), "tone": .string("n"), "status": .string("done")])
        XCTAssertNil(e.dailyDigest(fresh: [ask]).newInboxTitle)
        XCTAssertEqual(e.dailyDigest(fresh: [one]).newInboxTitle, "1 message")
        XCTAssertEqual(e.dailyDigest(fresh: [one, two, ask]).newInboxTitle, "2 messages")
        XCTAssertFalse(e.dailyDigest(fresh: []).bestDayOfWeek)
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
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, size: 1, state: s, data: data)
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
