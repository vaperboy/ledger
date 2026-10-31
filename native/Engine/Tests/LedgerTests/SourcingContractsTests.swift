import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Volume contracts with business customers, the repair supplier's discount and the protection of supply from inside.
final class SourcingContractsTests: XCTestCase {
    func testContractFeedsDemandIsInvoicedLaterAndTheBooksBalance() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        ChainsTests.play(&e, days: 12 * 7)
        let before = try XCTUnwrap(e.state.company(id))
        try XCTSkipUnless(before.value("lastW")["units"].double > 0, "the cafe did not trade in the test run")
        let terms = VolumeContracts.Terms(name: "Office catering", customer: "Test Offices", units: 3, discount: 0.1, weeks: 13, paymentWeeks: 4, reliability: 0.95)
        let cid = try XCTUnwrap(e.signContract(companyID: id, terms: terms))
        XCTAssertEqual(e.volumeContracts(companyID: id).first?.customer, "Test Offices")
        XCTAssertEqual(e.contractLoad(companyID: id).units, 3, accuracy: 1e-9)
        let revBefore = before.books.total["rev"] ?? 0
        ChainsTests.play(&e, days: 2 * 7)
        let after = try XCTUnwrap(e.state.company(id))
        // The customer's units are part of the week's demand and revenue.
        XCTAssertGreaterThan(after.books.total["rev"] ?? 0, revBefore)
        XCTAssertGreaterThan(after.value("lastW")["D"].double, 0)
        // What came in as cash is invoiced: it is a receivable of this contract that falls due after the delay.
        if (e.data.catalog["cafe"]?.businessShare ?? 1) < 1 {
            XCTAssertTrue(after.receivables.contains { $0.int("ct") == cid }, "the contract's money should be invoiced")
        }
        let d = try XCTUnwrap(e.contractDetail(companyID: id, contractID: cid))
        XCTAssertGreaterThan(d.price, 0)
        XCTAssertGreaterThan(d.weeksLeft, 0)
        ChainsTests.play(&e, days: 8 * 7)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        // Ending it early costs a penalty and a little reputation.
        let cash0 = try XCTUnwrap(e.state.company(id)).cash
        if e.volumeContracts(companyID: id).contains(where: { $0.id == cid }) {
            XCTAssertTrue(e.endContract(companyID: id, contractID: cid))
            XCTAssertFalse(e.volumeContracts(companyID: id).contains { $0.id == cid })
            XCTAssertLessThan(try XCTUnwrap(e.state.company(id)).cash, cash0)
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testRepairDiscountAndSupplyFromInsideProtection() throws {
        var e = try ChainsTests.engine()
        let cafe = ChainsTests.start(&e, "cafe")
        let bakery = ChainsTests.start(&e, "bakery")
        ChainsTests.play(&e, days: 10 * 7)
        // A repair supplier you know well gives a discount on upkeep and service.
        let v = try XCTUnwrap(e.supplierCandidates(companyID: cafe, scope: "fix").first)
        e.update { s, _, _ in s.rest["vr"] = .object([v.id: .object(["r": 95, "w": .number(Double(s.week)), "meet": -99])]) }
        e.switchSupplier(companyID: cafe, input: "repair", to: .repairVendor(v.id))
        let co = try XCTUnwrap(e.state.company(cafe))
        XCTAssertGreaterThan(Suppliers.repairDiscount(e.state, company: co, data: e.data), 0.1)
        XCTAssertGreaterThan(try XCTUnwrap(e.sourcingSummary(companyID: cafe)).repairDiscount, 0.1)
        // Goods offers are listed cheapest first with their cost and quality effect.
        let offers = e.sourcingOffers(companyID: cafe)
        XCTAssertFalse(offers.isEmpty)
        XCTAssertEqual(offers.map { $0.costFactor }, offers.map { $0.costFactor }.sorted())
        // Supply from inside: no outside supplier events while your own bakery supplies the bread.
        XCTAssertFalse(e.isSuppliedFromInside(companyID: cafe))
        XCTAssertFalse(Sourcing.shields(e.state, companyID: cafe, eventID: "g_supply"))
        XCTAssertEqual(e.switchSupplier(companyID: cafe, input: "bread", to: .ownCompany(bakery, mode: "mkt")), .ok)
        XCTAssertTrue(e.isSuppliedFromInside(companyID: cafe))
        XCTAssertTrue(Sourcing.shields(e.state, companyID: cafe, eventID: "g_supply"))
        XCTAssertFalse(Sourcing.shields(e.state, companyID: cafe, eventID: "g_break"))
        ChainsTests.play(&e, days: 10 * 7)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }
}
