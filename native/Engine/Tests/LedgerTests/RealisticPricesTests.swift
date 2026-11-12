import XCTest
import GameCore
import Countries
@testable import Businesses
@testable import Simulation

final class RealisticPricesTests: XCTestCase {
    func testWarehouseAndIndustrialRentsAreAtOsloMarketLevel() throws {
        let t = try TradeCatalog.bundled().tables
        for k in ["warehouse", "industrial"] {
            let p = try XCTUnwrap(t.premises[k])
            XCTAssertTrue((1_200...1_600).contains(p.rentPerM2Year), "\(k) rent \(p.rentPerM2Year)")
            let yield = p.rentPerM2Year / p.pricePerM2
            XCTAssertTrue((0.05...0.08).contains(yield), "\(k): rent is \(yield) of the price")
        }
    }

    func testRepricedTradesKeepTheirRevenueAtNormalDemand() throws {
        let cat = try TradeCatalog.bundled()
        let gym = try XCTUnwrap(cat["gym"]), farm = try XCTUnwrap(cat["farm"])
        XCTAssertEqual(gym.normalDemand * gym.ticket, 1_606.509223267867 * 120, accuracy: 192_781 * 0.001)
        XCTAssertEqual(farm.normalDemand * farm.ticket, 63.151 * 5_200, accuracy: 328_385 * 0.001)
        XCTAssertEqual(gym.normalCapacity / gym.normalDemand, 1_691.0623402819651 / 1_606.509223267867, accuracy: 1e-3)
        let club = try XCTUnwrap(cat["club"])
        XCTAssertTrue((200...600).contains(club.ticket), "a match ticket of \(club.ticket)")
    }

    func testGymMembershipInOsloIsAboutSixHundredAMonth() throws {
        let e = try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 3, story: .fresh, tradeID: "gym", companyName: "Test Gym")
        let co = try XCTUnwrap(e.state.companies.first)
        let bd = try XCTUnwrap(e.data.catalog["gym"])
        let week = SalesItems.marketTicket(co, bd, World(state: e.state, data: e.data))
        XCTAssertTrue((450...800).contains(week * 52 / 12), "\(week) a member-week")
    }

    func testFarmProductsArePricedPerTonneAtRealisticKiloPrices() throws {
        let spec = try XCTUnwrap(FoodRecipes.specs["farm"])
        let sq = spec.products.reduce(0.0) { $0 + $1.customers }
        let norm = spec.products.reduce(0.0) { $0 + $1.customers / sq * $1.ratio }
        let bd = try XCTUnwrap(try TradeCatalog.bundled()["farm"])
        let perTonne = bd.ticket * bd.ticketMultiplier
        let kilo: [String: ClosedRange<Double>] = ["wheat": 3...8, "potatoes": 4...12, "vegbox": 20...50, "eggs": 25...60, "dairy": 5...15, "beef": 80...200, "apples": 8...25]
        for p in spec.products {
            let price = perTonne * p.ratio / norm / 1_000
            XCTAssertTrue(try XCTUnwrap(kilo[p.id]).contains(price), "\(p.id): \(price) a kilo (or litre)")
        }
    }

    func testCityLevelsAreNotCountedTwice() throws {
        let e = try GameEngine.newGame(countryCode: "LT", playerName: "T", seed: 3)
        let country = e.homeCountry
        for row in e.marketCities(countryCode: "LT") {
            let city = try XCTUnwrap(country.cities.first { $0.id == row.id })
            XCTAssertEqual(row.rentLevel, city.rent, accuracy: 1e-9)
            XCTAssertEqual(row.priceLevel, city.price, accuracy: 1e-9)
            XCTAssertEqual(row.wageLevel, city.wage, accuracy: 1e-9)
        }
    }
}
