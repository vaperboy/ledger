import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Customers, competition and reputation: the features run, and the books still balance.
final class CustomersCompetitionTests: XCTestCase {
    func engineWithCafe(weeks: Int) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 777)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 80_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6 + 3_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        for _ in 0..<(weeks * 7) { e.nextDay() }
        return (e, id)
    }

    func testReviewsRivalsAndMarketRunAndBooksBalance() throws {
        let (e, id) = try engineWithCafe(weeks: 20)
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.status, .open)
        let rv = e.reviewSummary(co)
        XCTAssertGreaterThan(rv.count, 0, "customers should have written reviews")
        XCTAssertEqual(rv.histogram.reduce(0, +), min(rv.count, 200))
        XCTAssertFalse(rv.lines.isEmpty)
        XCTAssertFalse(e.rivalRows(co).isEmpty, "a market has named rivals")
        XCTAssertFalse(e.reviewBoard().isEmpty)
        XCTAssertFalse(e.marketRows().isEmpty)
        let key = try XCTUnwrap(e.marketRows().first).id
        XCTAssertNotNil(e.marketDetail(key: key))
        XCTAssertNotNil(e.priceMoves(co))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testPriceWarDiscountAndPriceMoves() throws {
        var (e, id) = try engineWithCafe(weeks: 6)
        let rival = try XCTUnwrap(e.rivalRows(try XCTUnwrap(e.state.company(id))).first).rival
        XCTAssertEqual(e.startPriceWar(companyID: id, rivalID: rival.id, weeks: 3), .done)
        XCTAssertEqual(e.state.company(id)?.priceLevel, -3)
        for _ in 0..<(5 * 7) { e.nextDay() }
        XCTAssertTrue(e.state.company(id)?.value("flags")["pw"].isNull ?? false, "the war is over")
        XCTAssertEqual(e.startDiscount(companyID: id, percent: 10, weeks: 2), .done)
        XCTAssertEqual(e.priceMoves(try XCTUnwrap(e.state.company(id)))?.discountPercent, 10)
        for _ in 0..<(3 * 7) { e.nextDay() }
        XCTAssertNil(e.priceMoves(try XCTUnwrap(e.state.company(id)))?.discountPercent)
        _ = e.changePrice(companyID: id, byShare: 0.05)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testKeyAccountsBuyAndLeave() throws {
        var (e, id) = try engineWithCafe(weeks: 8)
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].set("accts", .array([.object(["id": 1, "name": "Acme Catering", "f": 0.2, "rel": 20, "w0": .number(Double(s.week)), "disc": 10])]))
            s.companies[i].reputation = 70
        }
        let before = e.state.company(id)?.books.total["rev"] ?? 0
        for _ in 0..<(8 * 7) { e.nextDay() }
        let co = try XCTUnwrap(e.state.company(id))
        let info = e.keyAccountInfo(co)
        XCTAssertTrue(info.allowed)
        XCTAssertGreaterThan(info.limit, 1)
        XCTAssertGreaterThan((co.books.total["rev"] ?? 0), before)
        if let a = info.accounts.first { XCTAssertGreaterThan(a.totalUnits, 0, "the account bought something") }
        XCTAssertEqual(e.meetAccount(companyID: id, accountID: 1) == .ok || e.meetAccount(companyID: id, accountID: 1) == .wait || e.keyAccountInfo(co).accounts.isEmpty, true)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testLawsuitAndCyberAttackDecisions() throws {
        var (e, id) = try engineWithCafe(weeks: 12)
        e.update { s, data, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].managerID = nil
            Lawsuits.begin(&s, companyIndex: i, weeklyRevenue: 20_000, data: data)
            Cyber.hit(&s, companyID: id, kind: "ransom", data: data)
            Cyber.hit(&s, companyID: id, kind: "leak", data: data)
            Cyber.hit(&s, companyID: id, kind: "fraud", data: data)
        }
        let open = e.openDecisions.filter { $0.companyID == id }
        let suit = try XCTUnwrap(open.first { $0.actionID == "sue16" })
        let ransom = try XCTUnwrap(open.first { $0.actionID == "cy56r" })
        let leak = try XCTUnwrap(open.first { $0.actionID == "cy56l" })
        XCTAssertTrue(e.answer(messageID: suit.id, option: 0))
        XCTAssertTrue(e.answer(messageID: ransom.id, option: 2))
        XCTAssertTrue(e.answer(messageID: leak.id, option: 1))
        for _ in 0..<(30 * 7) { e.nextDay() }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        XCTAssertTrue(e.cyberInfo(try XCTUnwrap(e.state.company(id))).status.log.count >= 3)
        e.setCyberLevel(companyID: id, level: 2)
        XCTAssertEqual(e.cyberInfo(try XCTUnwrap(e.state.company(id))).status.level, 2)
    }

    func testBuyingARival() throws {
        var (e, id) = try engineWithCafe(weeks: 8)
        let co = try XCTUnwrap(e.state.company(id))
        let rival = try XCTUnwrap(e.rivalRows(co).first).rival
        e.update { s, _, _ in Ledger.move(&s, .me, 200_000_000, why: "Funds for a purchase") }
        let value = e.rivalValue(companyID: id, rivalID: rival.id)
        XCTAssertGreaterThan(value, 0)
        let count = e.state.companies.count
        guard case .accept(let price, _)? = e.offerForRival(companyID: id, rivalID: rival.id, multiple: 3) else { return XCTFail("a generous offer should be accepted") }
        guard case .ok(let newID) = e.buyRival(companyID: id, rivalID: rival.id, price: price) else { return XCTFail("the purchase should work") }
        XCTAssertEqual(e.state.companies.count, count + 1)
        XCTAssertEqual(e.state.company(newID)?.name, rival.name)
        XCTAssertFalse(e.rivalRows(try XCTUnwrap(e.state.company(id))).contains { $0.id == rival.id })
        for _ in 0..<(4 * 7) { e.nextDay() }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }
}
