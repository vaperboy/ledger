import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The Suppliers section's read model and its one switching action. They only read and call the existing rules.
final class SupplierDealsTests: XCTestCase {
    func testNextTierMatchesTheDiscountTable() {
        XCTAssertEqual(Suppliers.nextDiscountTier(0)?.discount, 0.01)
        XCTAssertEqual(Suppliers.nextDiscountTier(0)?.word, "Familiar")
        XCTAssertEqual(Suppliers.nextDiscountTier(0)?.from, 22)
        XCTAssertEqual(Suppliers.nextDiscountTier(40)?.discount, 0.05)
        XCTAssertNil(Suppliers.nextDiscountTier(100))
    }

    func testNoOwnProviderSaysWhatKindOfCompanyWouldProvideItAndRefusesASwitch() throws {
        var e = try ChainsTests.engine()
        let hotel = ChainsTests.start(&e, "hotel")
        ChainsTests.play(&e, days: 8 * 7)
        let clean = try XCTUnwrap(e.supplierInputs(companyID: hotel).first { $0.id == "clean" })
        XCTAssertNotNil(clean.noOwnProvider)
        XCTAssertTrue(clean.noOwnProvider?.contains("cleaning") ?? false, clean.noOwnProvider ?? "")
        XCTAssertEqual(clean.current?.kind, .outside)
        XCTAssertEqual(e.switchSupplier(companyID: hotel, input: "clean", to: .ownCompany(99999, mode: "mkt")), .notAllowed)
        XCTAssertNil(e.supplyLink(buyer: hotel, kind: "clean"))
    }

    func testSwitchingToAnOwnCompanyAndBackShowsPricesAndSaving() throws {
        var e = try ChainsTests.engine()
        let hotel = ChainsTests.start(&e, "hotel")
        let cleaning = ChainsTests.start(&e, "cleaning")
        ChainsTests.play(&e, days: 10 * 7)
        var clean = try XCTUnwrap(e.supplierInputs(companyID: hotel).first { $0.id == "clean" })
        XCTAssertNil(clean.noOwnProvider)
        let own = clean.options.filter { $0.kind == .ownCompany }
        XCTAssertEqual(own.count, IntercompanySupply.modes.count)
        for o in own {
            let pf = try XCTUnwrap(o.priceFactor)
            XCTAssertEqual(pf, e.supplyPriceFactor(supplier: cleaning, mode: IntercompanySupply.modes.first { o.id.hasSuffix(":" + $0.id) }!.id), accuracy: 1e-12)
            XCTAssertLessThanOrEqual(pf, 1)
            XCTAssertFalse(o.risks.isEmpty)
            XCTAssertFalse(o.terms.isEmpty)
        }
        XCTAssertEqual(try XCTUnwrap(own.first { $0.id.hasSuffix(":mkt") }).yearlyVsMarket ?? 1, 0, accuracy: 1e-9)

        XCTAssertEqual(e.switchSupplier(companyID: hotel, input: "clean", to: .ownCompany(cleaning, mode: "c10")), .ok)
        XCTAssertEqual(e.supplyLink(buyer: hotel, kind: "clean")?.mode, "c10")
        clean = try XCTUnwrap(e.supplierInputs(companyID: hotel).first { $0.id == "clean" })
        XCTAssertEqual(clean.current?.kind, .ownCompany)
        XCTAssertEqual(clean.current?.id, "o:\(cleaning):c10")
        XCTAssertEqual(e.supplierCurrentProviders(companyID: hotel).first { $0.inputID == "clean" }?.provider, e.state.company(cleaning)?.name)
        ChainsTests.play(&e, days: 6 * 7)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")

        XCTAssertEqual(e.switchSupplier(companyID: hotel, input: "clean", to: .outside), .ok)
        XCTAssertNil(e.supplyLink(buyer: hotel, kind: "clean"))
        XCTAssertEqual(try XCTUnwrap(e.supplierInputs(companyID: hotel).first { $0.id == "clean" }).current?.kind, .outside)
        // an input that is not a supply kind cannot be switched to an own company
        XCTAssertEqual(e.switchSupplier(companyID: hotel, input: "goods", to: .ownCompany(cleaning, mode: "mkt")), .notAllowed)
    }

    func testGoodsSupplierChoiceAndRelationshipImprovesTheTerms() throws {
        var e = try ChainsTests.engine()
        let cafe = ChainsTests.start(&e, "cafe")
        ChainsTests.play(&e, days: 8 * 7)
        let goods = try XCTUnwrap(e.supplierInputs(companyID: cafe).first { $0.id == "goods" })
        let vendors = goods.options.filter { $0.kind == .outsideVendor }
        XCTAssertFalse(vendors.isEmpty)
        let pick = try XCTUnwrap(vendors.first { $0.vendorID != goods.current?.vendorID })
        let before = try XCTUnwrap(pick.priceFactor)
        XCTAssertNotNil(pick.nextLevel, "a stranger has a next relationship level")
        XCTAssertEqual(e.switchSupplier(companyID: cafe, input: "goods", to: .goodsVendor("V-XX-0")), .notAllowed)
        XCTAssertEqual(e.switchSupplier(companyID: cafe, input: "goods", to: .goodsVendor(pick.vendorID!)), .ok)
        XCTAssertEqual(e.currentGoodsSupplier(companyID: cafe)?.id, pick.vendorID)

        // a better relationship is a better price, through the existing discount
        e.update { s, _, _ in Suppliers.bumpPublic(&s, pick.vendorID!, by: 60) }
        let after = try XCTUnwrap(e.supplierInputs(companyID: cafe).first { $0.id == "goods" }?.options.first { $0.vendorID == pick.vendorID })
        XCTAssertTrue(after.isCurrent)
        XCTAssertLessThan(try XCTUnwrap(after.priceFactor), before)
        XCTAssertGreaterThan(after.discount ?? 0, pick.discount ?? 0)

        XCTAssertEqual(e.switchSupplier(companyID: cafe, input: "goods", to: .goodsVendor("auto")), .ok)
        XCTAssertTrue(try XCTUnwrap(e.supplierInputs(companyID: cafe).first { $0.id == "goods" }?.options.first { $0.id == "v:auto" }).isCurrent)
    }

    func testBusinessCustomerNeedsARelationshipAndRepairChoiceWorks() throws {
        var e = try ChainsTests.engine()
        let buyer = ChainsTests.start(&e, "cafe")
        let owner = ChainsTests.start(&e, "cafe")
        ChainsTests.play(&e, days: 8 * 7)
        e.update { s, _, _ in
            let o = s.companyIndex(owner)!
            s.companies[o].set("accts", .array([
                .object(["id": 9001, "name": "Bright Cleaners", "f": 0.1, "rel": 40, "w0": .number(Double(s.week)), "disc": 0, "t": "cleaning"]),
                .object(["id": 9002, "name": "Stranger Cleaners", "f": 0.1, "rel": 10, "w0": .number(Double(s.week)), "disc": 0, "t": "cleaning"]),
            ]))
        }
        let clean = try XCTUnwrap(e.supplierInputs(companyID: buyer).first { $0.id == "clean" })
        let stranger = try XCTUnwrap(clean.options.first { $0.id == "c:9002" })
        XCTAssertNotNil(stranger.blocked)
        XCTAssertEqual(e.switchSupplier(companyID: buyer, input: "clean", to: .businessCustomer(9002)), .notKnownWell)
        XCTAssertEqual(e.switchSupplier(companyID: buyer, input: "clean", to: .businessCustomer(9001)), .ok)
        XCTAssertEqual(try XCTUnwrap(e.supplierInputs(companyID: buyer).first { $0.id == "clean" }).current?.kind, .businessCustomer)
        XCTAssertEqual(e.switchSupplier(companyID: buyer, input: "clean", to: .outside), .ok)
        XCTAssertNil(e.accountSupplyLink(buyer: buyer, kind: "clean"))

        if let repair = e.supplierInputs(companyID: buyer).first(where: { $0.id == "repair" }), let v = repair.options.first(where: { $0.kind == .repairVendor }) {
            XCTAssertEqual(e.switchSupplier(companyID: buyer, input: "repair", to: v.change), .ok)
            XCTAssertEqual(e.currentRepairSupplier(companyID: buyer)?.id, v.vendorID)
            XCTAssertEqual(e.switchSupplier(companyID: buyer, input: "repair", to: .repairVendor("auto")), .ok)
        }
    }
}
