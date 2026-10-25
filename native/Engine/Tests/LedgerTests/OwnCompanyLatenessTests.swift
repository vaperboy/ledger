import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

/// No cut-off between your own companies, but an own supplier left short-paid for long is flagged to the group and keeps back capacity.
final class OwnCompanyLatenessTests: XCTestCase {
    func testShortPaidOwnSupplierIsFlaggedAndDeliversLessThenRecovers() throws {
        var e = try ChainsTests.engine()
        let hotel = ChainsTests.start(&e, "hotel")
        let cleaning = ChainsTests.start(&e, "cleaning")
        for _ in 0..<40 where [hotel, cleaning].contains(where: { e.state.company($0)?.status != .open }) {
            e.update { s, d, _ in
                for id in [hotel, cleaning] { guard let co = s.company(id), let bd = d.catalog[co.type] else { continue }
                    for doc in Documents.needed(co, bd, World(state: s, data: d)) { _ = Documents.apply(doc, companyID: id, state: &s, data: d) } }
            }
            ChainsTests.play(&e, days: 7)
        }
        XCTAssertEqual(e.switchSupplier(companyID: hotel, input: "clean", to: .ownCompany(cleaning, mode: "mkt")), .ok)
        XCTAssertTrue(e.setSupplyPaymentTerms(companyID: hotel, input: "clean", term: "net14"))
        XCTAssertEqual(SupplyTerms.ownLateWeeks(e.state, buyer: hotel, supplier: cleaning), 0)
        // the buyer cannot pay: its account is far overdrawn
        for _ in 0..<(9 * 7) {
            e.update { s, _, _ in Ledger.set(&s, .company(hotel), to: -1_000_000_000_000) }
            e.nextDay()
        }
        let late = SupplyTerms.ownLateWeeks(e.state, buyer: hotel, supplier: cleaning)
        XCTAssertGreaterThanOrEqual(late, 4, "an invoice has been unpaid for weeks")
        XCTAssertTrue(SupplyTerms.ownSupplierStrained(e.state, buyer: hotel, supplier: cleaning))
        XCTAssertTrue(e.state.inbox.contains { $0.title.contains("short-paying") }, "the group is told")
        let option = try XCTUnwrap(e.supplierInputs(companyID: hotel).first { $0.id == "clean" }?.current)
        XCTAssertTrue(option.risks.contains { $0.contains("unpaid") })
        // nobody is cut off: the link is still there
        XCTAssertNotNil(IntercompanySupply.link(e.state, buyer: hotel, kind: "clean"))
        // pay up: the flag goes
        e.update { s, _, _ in Ledger.set(&s, .company(hotel), to: 1_000_000_000_000) }
        ChainsTests.play(&e, days: 14)
        XCTAssertEqual(SupplyTerms.ownLateWeeks(e.state, buyer: hotel, supplier: cleaning), 0)
        XCTAssertFalse(SupplyTerms.ownSupplierStrained(e.state, buyer: hotel, supplier: cleaning))
    }

    func testSettledWeeklyNeverGoesLate() throws {
        var e = try ChainsTests.engine("NO", seed: 21)
        let hotel = ChainsTests.start(&e, "hotel")
        let cleaning = ChainsTests.start(&e, "cleaning")
        ChainsTests.play(&e, days: 70)
        _ = e.switchSupplier(companyID: hotel, input: "clean", to: .ownCompany(cleaning, mode: "c10"))
        ChainsTests.play(&e, days: 182)
        XCTAssertEqual(SupplyTerms.ownLateWeeks(e.state, buyer: hotel, supplier: cleaning), 0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
