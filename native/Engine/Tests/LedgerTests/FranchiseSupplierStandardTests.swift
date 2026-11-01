import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

/// A franchise agreement can require the brand's approved supplier for an input (`franchise.supStd`, from `franchise_standards.json`).
/// The single switch action honours it and says why.
final class FranchiseSupplierStandardTests: XCTestCase {
    private func franchised(trade: String, minTier: Int, seeds: [Int]) throws -> (GameEngine, Int, FranchiseBrands.Brand)? {
        for seed in seeds {
            var e = try ChainsTests.engine("NO", seed: seed)
            let w = World(state: e.state, data: e.data)
            guard let brand = FranchiseBrands.brands(trade, country: "NO", w).first(where: { $0.openness == "open" && $0.tier >= minTier }) else { continue }
            XCTAssertEqual(e.applyToFranchiseBrand(brand.id, country: "NO"), .ok)
            for _ in 0..<(4 * 7) { e.nextDay() }
            guard e.franchiseApplication(brand.id)["st"].string == "invited", let n = e.negotiateFranchise(brand.id, ask: FranchiseBrands.Ask()), n.kind == .accept, let terms = n.terms else { continue }
            e.signFranchiseTerms(brand.id, terms: terms)
            guard case .success(let id) = e.startFranchisedCompany(brandID: brand.id, cityID: e.state.player.cityID, form: .limited, name: "Franchised", fundWith: 3_000_000_000) else { continue }
            return (e, id, brand)
        }
        return nil
    }

    func testRequiredStandardsComeFromData() {
        XCTAssertEqual(FranchiseBrands.requiredSupplierInputs(tradeID: "cafe", tier: 2), ["goods"])
        XCTAssertEqual(FranchiseBrands.requiredSupplierInputs(tradeID: "cafe", tier: 1), [])
        XCTAssertEqual(FranchiseBrands.requiredSupplierInputs(tradeID: "gym", tier: 4), [])
    }

    func testFoodBrandFixesTheGoodsSupplierAndTheSwitchHonoursIt() throws {
        var found: (GameEngine, Int, FranchiseBrands.Brand)?
        for trade in ["cafe", "restaurant", "bakery"] { if found == nil { found = try franchised(trade: trade, minTier: 2, seeds: [11, 12, 13, 14, 15, 16]) } }
        var (e, id, brand) = try XCTUnwrap(found, "no open food brand of tier 2+ in these seeds")
        let std = try XCTUnwrap(SupplyDeals.franchiseStandard(e.state.company(id)!, input: "goods"))
        guard case .goodsVendor(let required) = std else { return XCTFail("\(std)") }
        XCTAssertEqual(e.currentGoodsSupplier(companyID: id)?.id, required, "the store starts on the approved supplier")
        let input = try XCTUnwrap(e.supplierInputs(companyID: id).first { $0.id == "goods" })
        XCTAssertTrue(input.governedBy?.contains(brand.name) ?? false, input.governedBy ?? "nil")
        // switching to anything else is refused with the reason; the supplier does not move
        XCTAssertEqual(e.switchSupplier(companyID: id, input: "goods", to: .goodsVendor("auto")), .governed)
        if let other = input.options.first(where: { $0.vendorID != nil && $0.vendorID != required })?.vendorID {
            XCTAssertEqual(e.switchSupplier(companyID: id, input: "goods", to: .goodsVendor(other)), .governed)
        }
        XCTAssertEqual(e.currentGoodsSupplier(companyID: id)?.id, required)
        // the approved supplier itself is allowed
        XCTAssertEqual(e.switchSupplier(companyID: id, input: "goods", to: .goodsVendor(required)), .ok)
        // the same brand picks the same supplier every time
        XCTAssertEqual(try XCTUnwrap(found).1, id)
        // other inputs stay free
        ChainsTests.play(&e, days: 28)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        XCTAssertNil(e.supplierInputs(companyID: id).first { $0.id == "repair" }?.governedBy)
    }

    func testBrandsThatRequireNothingLeaveNoKeyBehind() throws {
        let (e, id, _) = try XCTUnwrap(try franchised(trade: "gym", minTier: 1, seeds: [11, 12, 13, 14, 15, 16]), "no open gym brand")
        XCTAssertTrue(e.state.company(id)!.value("franchise")["supStd"].isNull)
        XCTAssertEqual(e.supplierInputs(companyID: id).first { $0.id == "goods" }?.governedBy, nil)
    }
}
