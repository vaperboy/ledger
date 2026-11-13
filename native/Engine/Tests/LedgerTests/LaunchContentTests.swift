import XCTest
@testable import Events
@testable import Businesses
import GameCore
import Countries
import Finance
@testable import Simulation

final class LaunchContentTests: XCTestCase {
    func testTheGrantEventNamesTheCountrysOwnAuthority() throws {
        let lib = try EventLibrary.bundled()
        let text = try XCTUnwrap(lib["g_grant"]).text
        XCTAssertTrue(text.contains("{auth:grant}"), text)
        XCTAssertFalse(text.contains("Norge"), text)
        for c in try CountryBook.bundled().countries {
            XCTAssertFalse(c.pack["authorities"]["grant"].string.isEmpty, "\(c.code) has a grant authority")
        }
        let uk = try CountryBook.bundled().resolve("UK", orHome: "UK")
        let shown = TextTokens.resolve(text, country: uk, currency: Currency(country: uk, rates: ExchangeRates()))
        XCTAssertTrue(shown.hasPrefix("Innovate UK"), shown)
    }

    func testEventsSkipTradesWhereTheyMakeNoSense() throws {
        let lib = try EventLibrary.bundled()
        let data = try GameData.bundled()
        func applies(_ event: String, _ trade: String) throws -> Bool {
            try XCTUnwrap(lib[event], event).appliesTo(try XCTUnwrap(data.catalog[trade], trade))
        }
        for (event, trades) in [("r_shoplift", ["webshop", "cardealer"]), ("r_chain", ["webshop", "wholesale"]), ("r_priceWar", ["webshop", "wholesale"]),
                                ("l_gig", ["airline", "shipping", "wh3pl"]), ("l_hours", ["airline", "shipping"]), ("g_roadwork", ["skires"])] {
            for t in trades { XCTAssertFalse(try applies(event, t), "\(event) must not hit \(t)") }
        }
        XCTAssertTrue(try applies("r_shoplift", "kiosk"))
        XCTAssertTrue(try applies("l_gig", "courier"))
        for t in ["foodtruck", "electrician", "plumber", "construction", "cons", "resrent", "parking"] {
            for e in ["g_fire", "g_theft", "g_power"] { XCTAssertFalse(try applies(e, t), "\(e) needs premises, \(t) has none") }
        }
        for t in ["cafe", "factory", "hotel"] { XCTAssertTrue(try applies("g_fire", t), t) }
    }

    func testFlatLossFloorsFollowTheCompanysSize() throws {
        let lib = try EventLibrary.bundled()
        for id in ["g_fire", "g_theft", "g_break", "g_lawsuit", "g_fakerev"] {
            let e = try XCTUnwrap(lib[id], id)
            let json = String(data: try JSONEncoder().encode(e.options.map { $0.effects }), encoding: .utf8) ?? ""
            for flat in ["max(60000,", "max(15000,", "max(2500,", "max(1500,", "max(6000,", "max(20000,", "max(40000,", "max(8000,", "max(10000,"] {
                XCTAssertFalse(json.contains(flat), "\(id) still has a flat floor \(flat)")
            }
        }
    }

    func testEveryEventStillOnlyNamesRealTrades() throws {
        let lib = try EventLibrary.bundled()
        let data = try GameData.bundled()
        for (id, e) in lib.events {
            for t in e.excludedTrades { XCTAssertNotNil(data.catalog[t], "\(id) excludes unknown trade \(t)") }
        }
    }

    func testPlayersWhoSupplyABannedTradeAreImporters() throws {
        let book = try CountryBook.bundled()
        for slot in 0..<4 {
            let lt = SupplyPlayers.make(seed: 7, countryCode: "LT", line: "fish", trade: "salmon", slot: slot, countries: book)
            let words = try XCTUnwrap(SupplyPlayers.importWords["salmon"])
            XCTAssertTrue(words.contains { lt.name.hasSuffix($0) }, lt.name)
            let no = SupplyPlayers.make(seed: 7, countryCode: "NO", line: "fish", trade: "salmon", slot: slot, countries: book)
            XCTAssertFalse(words.contains { no.name.hasSuffix($0) }, no.name)
        }
        let fuel = SupplyPlayers.make(seed: 7, countryCode: "DE", line: "fuel", trade: "oilgas", slot: 0, countries: book)
        XCTAssertTrue(try XCTUnwrap(SupplyPlayers.importWords["oilgas"]).contains { fuel.name.hasSuffix($0) }, fuel.name)
    }

    func testElectriciansAndPlumbersSellProjects() throws {
        let data = try GameData.bundled()
        for id in ["electrician", "plumber"] { XCTAssertEqual(data.catalog[id]?.unit, "project", id) }
    }

    // Season 1 keeps its September start so season 2 opens around Easter 2027.
    func testSeasonOneKeepsItsStartSoSeasonTwoOpensAtEaster() {
        XCTAssertEqual(SeasonCatalog.firstSeasonStart, SeasonCatalog.eraDay(year: 2026, month: 9, day: 28))
    }

    func testAGoldPrizeNeverResetsThePity() {
        var pity = BoxPity()
        pity.record(.common)
        pity.record(.rare, isItem: false)
        XCTAssertEqual(pity.sinceRare, 2, "an 8 gold prize is not an item")
        pity.record(.rare, isItem: true)
        XCTAssertEqual(pity.sinceRare, 0)
        pity.record(.common)
        pity.record(.legendary)
        XCTAssertEqual(pity.sinceRare, 0, "an item defaults to counting")
    }

    func testTheOpenBoxRuleCountsOnlyItems() {
        var pity = BoxPity()
        for n in 0..<400 {
            let out = BoxOdds.open(.cabinet, pity: pity, ownedCosmetics: [], seed: "pity\(n)")
            switch out.result.content {
            case .gold, .money: XCTAssertGreaterThan(out.pity.sinceRare, 0, "a gold or money prize keeps counting")
            default: if out.result.rarity >= .rare { XCTAssertEqual(out.pity.sinceRare, 0) }
            }
            pity = out.pity
        }
    }
}
