import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// One data-driven Prime-time TV channel, named from each country's own media data; no country codes in code.
final class PrimeTimeChannelTests: XCTestCase {
    func testEveryCountryGetsTheChannelNamedFromItsOwnMedia() throws {
        let tables = try MarketingTables.bundled()
        let base = try XCTUnwrap(tables.channels["primetime"])
        XCTAssertTrue(base.isPrimeTime && base.isNational && base.isHighVariance && base.needsCountryMedia && base.popScaled)
        XCTAssertEqual(tables.channels.values.filter { $0.isPrimeTime }.count, 1, "the 23 per-country channels are one")
        let book = try CountryBook.bundled()
        XCTAssertEqual(book.countries.count, 23)
        for c in book.countries {
            let ch = try XCTUnwrap(base.offered(in: c), c.code)
            XCTAssertEqual(ch.name, c.pack["media"]["prime"][0].string, c.code)
            XCTAssertFalse(ch.name.isEmpty)
            XCTAssertTrue(ch.note.contains("national footprint"), c.code)
            let cur = Currency(country: c, rates: ExchangeRates())
            XCTAssertGreaterThan(ch.scale(in: cur), 0, c.code)
            XCTAssertTrue(ch.budgets(in: cur).dropFirst().allSatisfy { $0 > 0 }, c.code)
        }
    }

    func testScaleFollowsPopulationAndACountryWithoutMediaDoesNotOfferIt() throws {
        let tables = try MarketingTables.bundled()
        let base = try XCTUnwrap(tables.channels["primetime"])
        let book = try CountryBook.bundled()
        let big = try XCTUnwrap(book.countries.max { $0.populationMillions < $1.populationMillions })
        let small = try XCTUnwrap(book.countries.min { $0.populationMillions < $1.populationMillions })
        func perPrice(_ c: Country) -> Double { base.scale(in: Currency(country: c, rates: ExchangeRates())) / c.costIndex }
        let expected = (max(2, big.populationMillions) / max(2, small.populationMillions)).squareRoot()
        XCTAssertEqual(perPrice(big) / perPrice(small), expected, accuracy: expected * 0.001)
        var none = big
        none.pack["media"] = .null
        XCTAssertNil(base.offered(in: none))
        // an ordinary channel does not depend on population
        let google = try XCTUnwrap(tables.channels["google"])
        XCTAssertEqual(google.scale(in: Currency(country: big, rates: ExchangeRates())) / big.costIndex, google.scale, accuracy: 1e-6)
    }

    func testPlayerCanBuyItAndItRunsLikeAnyCampaignWithTheMinimumLock() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        let ch = try XCTUnwrap(e.marketingChannels(companyID: id).first { $0.isPrimeTime })
        XCTAssertEqual(e.marketingChannels(companyID: id).last?.id, "primetime", "listed last")
        XCTAssertEqual(ch.name, e.homeCountry.pack["media"]["prime"][0].string)
        let cur = e.currency(for: try XCTUnwrap(e.state.company(id)))
        let b = try XCTUnwrap(ch.budgets(in: cur).dropFirst().first)
        XCTAssertEqual(e.setCampaign(companyID: id, channel: "primetime", weeklyBudget: b, weeks: 4), .done)
        if case .refused = e.setCampaign(companyID: id, channel: "primetime", weeklyBudget: 0) {} else { XCTFail("minimum 4 weeks") }
        ChainsTests.play(&e, days: 7 * 6)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testManagersNeverPickIt() throws {
        let tables = try MarketingTables.bundled()
        // the only channels managers buy (ManagerWeek, ManagerProposals) and the chain's brand marketing
        for k in ["google", "meta"] { XCTAssertFalse(try XCTUnwrap(tables.channels[k]).isPrimeTime) }
        let brandPool = tables.channels.values.filter { !$0.isPrimeTime && !$0.isNational && !$0.isHighVariance }
        XCTAssertFalse(brandPool.contains { $0.id == "primetime" })
    }
}
