import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

/// Volume tenders (the salmon farm's supermarket chain, canteens, carriers ...): a won bid becomes a contract of the company.
final class VolumeTendersTests: XCTestCase {
    func testEveryTenderTradeExists() throws {
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 3)
        XCTAssertFalse(VolumeTenders.catalog["salmon"]?.isEmpty ?? true)
        for (trade, offers) in VolumeTenders.catalog {
            XCTAssertNotNil(e.data.catalog[trade], "unknown trade \(trade)")
            XCTAssertTrue(offers.allSatisfy { $0.volume }, trade)
        }
    }

    func testWonVolumeTenderBecomesContract() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 17)
        var id = 0, tid = 0
        var bidCost = 0.0, cashBefore = 0.0, cashAfterBid = 0.0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 500_000_000, why: "Test funds")
            guard case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, form: .limited, data: data, context: ctx) else { return }
            id = i
            Payments.injectCash(&s, companyID: id, amount: 20_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
            guard let co = s.company(id) else { return }
            var st = ProjectTenders.load(s)
            var t = ProjectTenders.make(&s, co, data: data, home: ctx.homeCurrency(s))
            t.set("rivals", 0); t.set("minR", 0); t.set("minY", 0); t.set("wP", 1)
            t.set("due", s.week + 1); t.set("award", s.week + 2)
            st.list.append(t)
            ProjectTenders.save(&s, st)
            tid = t.id
            bidCost = t.bidCost
            cashBefore = s.company(id)?.cash ?? 0
            XCTAssertTrue(t.isVolume)
            XCTAssertEqual(ProjectTenders.placeBid(&s, companyID: id, tenderID: tid, priceFactor: 0.95, higherQuality: false, data: data), .sent)
            cashAfterBid = s.company(id)?.cash ?? 0
        }
        XCTAssertGreaterThan(bidCost, 0)
        XCTAssertEqual(cashBefore - cashAfterBid, bidCost, accuracy: 1)
        for _ in 0..<(3 * 7) { e.nextDay() }
        let co = try XCTUnwrap(e.state.company(id))
        let won = VolumeContracts.contracts(co, week: e.state.week).first { $0.tenderID == tid }
        XCTAssertNotNil(won, "the won tender should be a contract")
        XCTAssertEqual(won?.isPublic, true)
        XCTAssertEqual(won?.discount ?? 0, 0.05, accuracy: 0.0001)
        XCTAssertTrue(e.state.inbox.contains { $0.title.hasPrefix("Award:") })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
