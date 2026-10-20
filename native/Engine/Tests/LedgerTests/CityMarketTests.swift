import XCTest
import GameCore
import Countries
import Businesses

/// Real-life population and demand by place (docs/CITY_DATA.md): city data spread, income bands, luxury demand and rivals by city.
final class CityMarketTests: XCTestCase {
    func data() throws -> GameData { try GameData.bundled() }

    func testEveryCountryHasARealisticSpreadOfPlaces() throws {
        let book = try CountryBook.bundled()
        var seen: Set<String> = []
        for c in book.countries {
            let pops = c.cities.map { $0.population }
            XCTAssertGreaterThanOrEqual(c.cities.count, 7, c.code)
            XCTAssertLessThanOrEqual(pops.min()!, 40, "\(c.code) has a small town")
            XCTAssertGreaterThanOrEqual(pops.max()!, 500, "\(c.code) has a big city")
            for city in c.cities {
                XCTAssertTrue(seen.insert(c.code + city.id).inserted, "\(c.code) \(city.id) twice")
                XCTAssertGreaterThanOrEqual(city.metro, city.population * 0.99, "\(c.code) \(city.id) metro")
                XCTAssertTrue((0.2...0.65).contains(city.inequality))
                XCTAssertTrue((0.3...6.5).contains(city.touristIndex), "\(c.code) \(city.id) tour \(city.touristIndex)")
            }
            XCTAssertTrue((0.2...0.6).contains(c.gini), c.code)
        }
        XCTAssertGreaterThanOrEqual(book.countries.reduce(0) { $0 + $1.cities.count }, 250)
    }

    func testIncomeBandsAddUpAndRichBigCitiesHaveMoreAffluentHouseholds() throws {
        let d = try data()
        let us = d.countries["US"]!, no = d.countries["NO"]!
        for c in d.countries.countries { for city in c.cities {
            let b = c.incomeBands(in: city)
            XCTAssertEqual(b.budget + b.middle + b.upper + b.affluent, 1, accuracy: 1e-9)
            XCTAssertTrue(b.budget >= 0 && b.middle >= 0 && b.upper >= 0 && b.affluent >= 0, "\(c.code) \(city.id)")
        } }
        let nyc = us.incomeBands(in: us.city("nyc")!), smallUS = us.incomeBands(in: us.city("smallus")!)
        XCTAssertGreaterThan(nyc.affluent, smallUS.affluent * 3)
        XCTAssertGreaterThan(us.incomeBands(in: us.city("sfo")!).affluent, us.incomeBands(in: us.city("la")!).affluent)
        XCTAssertLessThan(no.incomeBands(in: no.city("small")!).affluent, nyc.affluent)   // a small Norwegian town against New York
    }

    func testLuxuryDrawsCustomersInRichBigCitiesAndAlmostNoneInSmallTowns() throws {
        let d = try data()
        let tables = d.balance.cityMarket
        func ratio(_ trade: String, _ cc: String, _ city: String, pm: Double = 1) -> Double {
            let c = d.countries[cc]!
            return CityMarket.affordRatio(trade: trade, priceMultiplier: pm, country: c, city: c.city(city)!, tables: tables)
        }
        XCTAssertGreaterThan(ratio("boutique", "US", "la"), 1.5)
        XCTAssertLessThan(ratio("boutique", "NO", "small"), 0.5)
        XCTAssertGreaterThan(ratio("boutique", "US", "la"), 3 * ratio("boutique", "NO", "small"))
        // A luxury price position needs the rich: the town loses far more than at an average price
        XCTAssertLessThan(ratio("boutique", "NO", "small", pm: 1.9), ratio("boutique", "NO", "small", pm: 1))
        XCTAssertEqual(ratio("grocery", "US", "la"), 1)   // everyday trades: only size counts
        // Rivals follow the customers who can pay
        let us = d.countries["US"]!, no = d.countries["NO"]!
        XCTAssertGreaterThan(CityMarket.rivalDensity(trade: "boutique", country: us, city: us.city("la")!, tables: tables), 1)
        XCTAssertLessThan(CityMarket.rivalDensity(trade: "boutique", country: no, city: no.city("small")!, tables: tables), 1)
        XCTAssertEqual(CityMarket.rivalDensity(trade: "bakery", country: us, city: us.city("la")!, tables: tables), 1)
    }

    func testTouristsFollowTheCityNotOnlyTheCountry() throws {
        let d = try data()
        let it = d.countries["IT"]!
        XCTAssertGreaterThan(CityMarket.visitorShare(country: it, city: it.city("ven")), CityMarket.visitorShare(country: it, city: it.city("smallit")) * 3)
        XCTAssertGreaterThan(it.city("flr")!.touristIndex, it.city("tor")!.touristIndex)
    }

    func testReadModelForAScreen() throws {
        let d = try data()
        let la = try XCTUnwrap(CityMarket.profile(cityID: "la", countryCode: "US", data: d))
        let town = try XCTUnwrap(CityMarket.profile(cityID: "small", countryCode: "NO", data: d))
        XCTAssertEqual(la.tiers.map { $0.tier }, [.everyday, .premium, .luxury])
        XCTAssertGreaterThan(la.population, 3000)
        XCTAssertGreaterThan(la.metroPopulation, la.population)
        XCTAssertGreaterThan(la.tiers[2].potentialHouseholds, town.tiers[2].potentialHouseholds * 50)
        XCTAssertGreaterThan(la.tiers[2].demandFactor, 1)
        XCTAssertLessThan(town.tiers[2].demandFactor, 1)
        XCTAssertGreaterThan(la.tiers[2].rivals, town.tiers[2].rivals)
        XCTAssertGreaterThan(la.rentLevel, town.rentLevel)
        XCTAssertNotNil(la.trades.first { $0.tradeID == "boutique" })
        XCTAssertNil(CityMarket.profile(cityID: "nowhere", data: d))
    }

    func testGiniSpread() {
        XCTAssertEqual(IncomeModel.sigma(gini: 0.3), 0.7 * 1.0 * (IncomeModel.sigma(gini: 0.3) / 0.7), accuracy: 1e-12)
        XCTAssertEqual(erf(IncomeModel.sigma(gini: 0.41) / 2), 0.41, accuracy: 1e-9)
        XCTAssertEqual(IncomeModel.shareAbove(1, median: 1, gini: 0.3), 0.5, accuracy: 1e-9)
    }
}
