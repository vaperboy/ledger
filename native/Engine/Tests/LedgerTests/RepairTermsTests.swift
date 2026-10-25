import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

/// Repair and upkeep bills can be put on payment terms like goods (`SupplyTerms`): cash on delivery, 30 or 60 days.
final class RepairTermsTests: XCTestCase {
    private func setup(seed: Int = 11) throws -> (GameEngine, Int, String) {
        var e = try ChainsTests.engine("NO", seed: seed)
        let id = ChainsTests.start(&e, "cafe")
        ChainsTests.play(&e, days: 14)
        let fix = try XCTUnwrap(e.supplierInputs(companyID: id).first { $0.id == "repair" })
        let vendor = try XCTUnwrap(fix.options.first { $0.vendorID != nil }?.vendorID)
        XCTAssertEqual(e.switchSupplier(companyID: id, input: "repair", to: .repairVendor(vendor)), .ok)
        return (e, id, vendor)
    }

    func testTermsNeedTheRelationshipAndShowInTheSection() throws {
        var (e, id, vendor) = try setup()
        XCTAssertFalse(e.setRepairPaymentTerms(companyID: id, term: "net30"), "a stranger offers no credit")
        XCTAssertTrue(e.setRepairPaymentTerms(companyID: id, term: "cod"))
        let terms = try XCTUnwrap(e.supplierInputs(companyID: id).first { $0.id == "repair" }).paymentTerms
        XCTAssertEqual(terms.first { $0.isCurrent }?.id, "cod")
        XCTAssertNotNil(terms.first { $0.id == "net30" }?.blocked)
        e.update { s, _, _ in Suppliers.bumpPublic(&s, vendor, by: 60) }
        XCTAssertTrue(e.setRepairPaymentTerms(companyID: id, term: "net30"))
        XCTAssertEqual(SupplyTerms.agreedRepairTerm(e.state.company(id)!), "net30")
        XCTAssertTrue(e.setRepairPaymentTerms(companyID: id, term: nil))
        XCTAssertNil(e.state.company(id)?.raw["pterm"], "nothing left behind")
    }

    func testUpkeepOnCreditBecomesAnInvoicePaidLaterAndTheBooksBalance() throws {
        var (e, id, vendor) = try setup()
        e.update { s, _, _ in Suppliers.bumpPublic(&s, vendor, by: 60) }
        XCTAssertTrue(e.setRepairPaymentTerms(companyID: id, term: "net30"))
        var seen = false
        for _ in 0..<(26 * 7) {
            e.nextDay()
            if e.supplierInvoices(companyID: id).contains(where: { $0.kind == "fix" }) { seen = true }
        }
        XCTAssertTrue(seen, "upkeep was invoiced")
        XCTAssertLessThan(e.supplierInvoices(companyID: id).count, 12)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testTermsLapseWhenTheRelationshipFalls() throws {
        var (e, id, vendor) = try setup()
        e.update { s, _, _ in Suppliers.bumpPublic(&s, vendor, by: 500) }
        XCTAssertTrue(e.setRepairPaymentTerms(companyID: id, term: "net60"))
        e.update { s, _, _ in Suppliers.dock(&s, vendor, by: 100) }
        ChainsTests.play(&e, days: 7)
        XCTAssertNil(SupplyTerms.agreedRepairTerm(e.state.company(id)!), "the supplier no longer offers it")
    }

    func testManySeedsOneYear() throws {
        for seed in [2, 9, 23] {
            var (e, id, vendor) = try setup(seed: seed)
            e.update { s, _, _ in Suppliers.bumpPublic(&s, vendor, by: 80) }
            _ = e.setRepairPaymentTerms(companyID: id, term: "net60")
            ChainsTests.play(&e, days: 364)
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "seed \(seed): \(Ledger.gaps(e.state))")
            XCTAssertLessThan(e.supplierInvoices(companyID: id).count, 20, "seed \(seed)")
        }
    }
}
