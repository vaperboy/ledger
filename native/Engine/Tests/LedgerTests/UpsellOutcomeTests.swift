import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

/// Selling extras at the till is an operating decision with an uncertain result: the extra follows how happy customers are with
/// the shop, it is not a fixed share of sales.
final class UpsellOutcomeTests: XCTestCase {
    private func extra(seed: Int, quality: Double, reputation: Double) throws -> Double {
        var e = try ChainsTests.engine(seed: seed)
        let id = ChainsTests.start(&e, "barber")
        var gained = 0.0
        e.update { s, d, _ in
            guard let i = s.companyIndex(id), let bd = d.catalog["barber"] else { return }
            s.companies[i].status = .open
            s.companies[i].quality = quality; s.companies[i].reputation = reputation
            s.companies[i].set("rvN", 10)
            s.companies[i].set("lastW", .object(["rev": 100_000, "units": 100, "util": 0.5]))
            s.companies[i].set("sw33", .object(["on": .object(["upsell": 1]), "paidUp": 1]))
            let before = s.companies[i].cash
            SalesWays.weekly(&s, i, bd, data: d)
            gained = s.companies[i].cash - before
        }
        return gained
    }

    func testTheUpsellFollowsTheRatingAndIsNotAFixedShareOfSalesAcrossSeeds() throws {
        for seed in [3, 11, 29] {
            let bad = try extra(seed: seed, quality: 0, reputation: 0)
            let mid = try extra(seed: seed, quality: 50, reputation: 50)
            let great = try extra(seed: seed, quality: 100, reputation: 100)
            XCTAssertEqual(bad, 0, accuracy: 1, "a badly rated shop sells no extras (seed \(seed))")
            XCTAssertGreaterThan(mid, bad)
            XCTAssertGreaterThan(great, mid)
        }
    }
}
