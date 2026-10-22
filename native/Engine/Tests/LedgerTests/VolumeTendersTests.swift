import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Volume tenders of services (they become volume contracts) and the other ways to sell (platform, memberships ...).
final class VolumeTendersTests: XCTestCase {
    func testServiceCompanyGetsVolumeTenderBidsAndWinsAContract() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cleaning")
        var bidOn: Int?
        // A tender for the trade turns up about every nine weeks; bid for the first volume one (lowest price, higher quality).
        for _ in 0..<80 where bidOn == nil {
            ChainsTests.play(&e, days: 7)
            let co = try XCTUnwrap(e.state.company(id))
            if let t = ProjectTenders.openTenders(e.state, for: co).first(where: { $0.isVolume }) {
                var result = ProjectTenders.BidResult.closed
                e.update { s, d, _ in result = ProjectTenders.placeBid(&s, companyID: id, tenderID: t.id, priceFactor: 0.8, higherQuality: true, data: d) }
                if result == .sent { bidOn = t.id }
            }
        }
        try XCTSkipUnless(bidOn != nil, "no volume tender turned up or the company could not bid")
        for _ in 0..<12 { ChainsTests.play(&e, days: 7) }
        let won = e.volumeContracts(companyID: id).first { $0.tenderID == bidOn }
        try XCTSkipUnless(won != nil, "a rival won this tender")
        let c = try XCTUnwrap(won)
        XCTAssertTrue(c.higherQuality)
        XCTAssertGreaterThan(c.units, 0)
        XCTAssertGreaterThan(c.endWeek - c.startWeek, 100, "two years")
        XCTAssertEqual(c.extensionsLeft, 2)
        XCTAssertGreaterThan(e.contractLoad(companyID: id).units, 0)
        ChainsTests.play(&e, days: 6 * 7)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testPlatformMembershipAndAddOnsMoveRealMoneyAndTheBooksBalance() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        ChainsTests.play(&e, days: 10 * 7)
        let rows = e.waysToSell(companyID: id)
        XCTAssertTrue(rows.contains { $0.kind == "platform" && $0.canSwitch })
        XCTAssertTrue(rows.contains { $0.kind == "members" && $0.canSwitch })
        let oth0 = try XCTUnwrap(e.state.company(id)).books.total["oth"] ?? 0
        XCTAssertEqual(e.setWayToSell(companyID: id, kind: "platform", on: true), .changed)
        XCTAssertEqual(e.setWayToSell(companyID: id, kind: "members", on: true), .changed)
        XCTAssertEqual(e.setWayToSell(companyID: id, kind: "contract", on: true), .notSwitchable)
        XCTAssertEqual(e.setWayToSell(companyID: id, kind: "nothing", on: true), .notAWay)
        ChainsTests.play(&e, days: 8 * 7)
        let co = try XCTUnwrap(e.state.company(id))
        try XCTSkipUnless(co.value("lastW")["rev"].double > 0, "the cafe did not trade in the test run")
        XCTAssertGreaterThan(co.books.total["oth"] ?? 0, oth0, "commission and perks are costs")
        XCTAssertGreaterThan(co.value("sw33")["mem"].double, 0, "members build up")
        XCTAssertTrue(e.waysToSell(companyID: id).first { $0.kind == "platform" }?.isOn ?? false)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }
}
