import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

/// A sale between two of your companies in the same country is a taxable supply: the supplier owes the VAT, a registered buyer reclaims it
/// (the group pays nothing net), a buyer below the registration threshold bears it as a cost. Books balance on both sides.
final class IntercompanyTaxTests: XCTestCase {
    private func setup(buyerRegistered: Bool, country: String = "NO") throws -> (GameEngine, buyer: Int, supplier: Int) {
        var e = try ChainsTests.engine(country)
        let hotel = ChainsTests.start(&e, "hotel")
        let cleaning = ChainsTests.start(&e, "cleaning")
        for _ in 0..<40 where [hotel, cleaning].contains(where: { e.state.company($0)?.status != .open }) {
            e.update { s, d, _ in
                for id in [hotel, cleaning] { guard let co = s.company(id), let bd = d.catalog[co.type] else { continue }
                    for doc in Documents.needed(co, bd, World(state: s, data: d)) { _ = Documents.apply(doc, companyID: id, state: &s, data: d) } }
            }
            ChainsTests.play(&e, days: 7)
        }
        e.update { s, _, _ in
            // the supplier is big enough to charge VAT; the buyer is registered (or not)
            for (id, rev) in [(cleaning, 2_000_000_000.0), (hotel, buyerRegistered ? 2_000_000_000.0 : 1_000.0)] {
                let i = s.companyIndex(id)!
                s.companies[i].monthlyHistory = (0..<12).map { MonthRecord(monthIndex: $0, revenue: rev, profit: 0, cash: 0) }
                var lw = s.companies[i].value("lastW"); lw["rev"] = .number(max(lw["rev"].double, 5_000_000)); lw["cap"] = .number(1_000_000); s.companies[i].set("lastW", lw)
            }
        }
        XCTAssertEqual(e.switchSupplier(companyID: hotel, input: "clean", to: .ownCompany(cleaning, mode: "mkt")), .ok)
        return (e, hotel, cleaning)
    }

    private func settleOnce(_ e: inout GameEngine, hotel: Int, cleaning: Int) -> (vatSupplier: Double, vatBuyer: Double, cashSupplier: Double, cashBuyer: Double, revenueBooked: Double) {
        var out = (0.0, 0.0, 0.0, 0.0, 0.0)
        e.update { s, d, _ in
            let v0 = (s.company(cleaning)!.vatBalance, s.company(hotel)!.vatBalance)
            let c0 = (s.company(cleaning)!.cash, s.company(hotel)!.cash)
            let r0 = s.company(cleaning)!.books.week["rev"] ?? 0
            IntercompanySupply.weekly(&s, data: d)
            out = (s.company(cleaning)!.vatBalance - v0.0, s.company(hotel)!.vatBalance - v0.1, s.company(cleaning)!.cash - c0.0, s.company(hotel)!.cash - c0.1,
                   (s.company(cleaning)!.books.week["rev"] ?? 0) - r0)
        }
        return out
    }

    func testRegisteredBuyerReclaimsTheVatTheSupplierOwes() throws {
        var (e, hotel, cleaning) = try setup(buyerRegistered: true)
        let r = settleOnce(&e, hotel: hotel, cleaning: cleaning)
        XCTAssertGreaterThan(r.revenueBooked, 0, "a sale was booked")
        XCTAssertGreaterThan(r.vatSupplier, 0, "the supplier owes output VAT on the transfer")
        XCTAssertEqual(r.vatBuyer, -r.vatSupplier, accuracy: 1e-9, "the registered buyer reclaims exactly that")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testBuyerBelowTheThresholdBearsTheVatAsACost() throws {
        var (e, hotel, cleaning) = try setup(buyerRegistered: false)
        let hotelBefore = e.state.company(hotel)!.books.week["oth"] ?? 0
        let r = settleOnce(&e, hotel: hotel, cleaning: cleaning)
        guard r.vatSupplier > 0 else { return XCTFail("no VAT charged: \(r)") }
        XCTAssertEqual(r.vatBuyer, 0, accuracy: 1e-9, "no input credit")
        XCTAssertGreaterThan((e.state.company(hotel)!.books.week["oth"] ?? 0) - hotelBefore, 0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testPaidOnInvoiceTheInvoiceCarriesTheVatAndTheBooksBalanceOverAYear() throws {
        for seed in [5, 17] {
            var e = try ChainsTests.engine("NO", seed: seed)
            let hotel = ChainsTests.start(&e, "hotel")
            let cleaning = ChainsTests.start(&e, "cleaning")
            ChainsTests.play(&e, days: 70)
            _ = e.switchSupplier(companyID: hotel, input: "clean", to: .ownCompany(cleaning, mode: "c10"))
            _ = e.setSupplyPaymentTerms(companyID: hotel, input: "clean", term: "net14")
            ChainsTests.play(&e, days: 364)
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "seed \(seed): \(Ledger.gaps(e.state))")
            let owed = e.supplierInvoices(companyID: hotel).reduce(0) { $0 + $1.amount }
            XCTAssertTrue(owed.isFinite && owed >= 0)
            XCTAssertLessThan(e.supplierInvoices(companyID: hotel).count, 12, "invoices are paid, not piling up")
        }
    }
}
