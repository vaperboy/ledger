import XCTest
import GameCore
import Countries
@testable import Simulation

final class GoldValueTests: XCTestCase {
    func testOneGoldIsAThousandGameKroner() throws {
        XCTAssertEqual(GoldPrices.gameNokPerGold, 1_000)
        XCTAssertEqual(GoldPrices.goldPerNok, 1, "the real-money price of gold is unchanged")
        XCTAssertEqual(GoldValue.gameMoney(gold: 1), 1_000)
        XCTAssertEqual(GoldValue.gold(gameMoney: 25_000), 25, accuracy: 1e-9)
        let book = try CountryBook.bundled()
        let usd = Currency(country: try XCTUnwrap(book["US"]), rates: ExchangeRates())
        let nok = Currency(country: try XCTUnwrap(book["NO"]), rates: ExchangeRates())
        XCTAssertEqual(GoldValue.local(gold: 1, currency: nok), 1_000, accuracy: 1e-9)
        XCTAssertEqual(GoldValue.local(gold: 1, currency: usd), 1_000 / usd.rate, accuracy: 1e-9)
        XCTAssertEqual(GoldValue.local(gold: 1, currency: usd), 100, accuracy: 10, "about 100 game dollars")
    }

    func testArtifactPricesFollowTheOneGoldRate() {
        for r in BoxRarity.allCases {
            XCTAssertGreaterThan(GoldPrices.artifactValue(r), 0, r.rawValue)
            XCTAssertEqual(Double(AuctionMarket.basePrice(r)), GoldValue.gameMoney(gold: GoldPrices.artifactValue(r)), accuracy: 0.5, r.rawValue)
        }
        XCTAssertEqual(AuctionMarket.suggestedStart(.common, priceLevel: 1), Int(GoldValue.gameMoney(gold: GoldPrices.artifactValue(.common))))
        XCTAssertLessThan(GoldPrices.artifactValue(.common), GoldPrices.artifactValue(.legendary))
    }

    func testAuctionPricesUseTheExchangeRateOnly() throws {
        for code in ["NO", "US", "JP"] {
            let e = try GameEngine.newGame(countryCode: code, playerName: "T", seed: 3)
            XCTAssertEqual(e.auctionPriceLevel, 1 / e.homeCurrency.rate, accuracy: 1e-12, code)
            let local = AuctionMarket.suggestedStart(.epic, priceLevel: e.auctionPriceLevel)
            XCTAssertEqual(Double(local) * e.homeCurrency.rate, GoldValue.gameMoney(gold: GoldPrices.artifactValue(.epic)), accuracy: GoldValue.gameMoney(gold: GoldPrices.artifactValue(.epic)) * 0.1, code)
        }
    }

    func testAPaidBoxIsWorthLessInGoldThanItCosts() {
        for kind in BoxKind.allCases where kind.isPaid {
            var worth = 0.0
            for row in BoxOdds.rows(kind) {
                let share = Double(row.weight) / Double(BoxOdds.totalWeight)
                switch row.prize {
                case .gold(let g): worth += share * Double(g)
                case .artifact, .profileCard, .companyCard: worth += share * GoldPrices.artifactValue(row.rarity)
                case .money(let m): worth += share * GoldValue.gold(gameMoney: Double(m))
                case .cosmetic: break
                }
            }
            XCTAssertLessThan(worth, Double(kind.price) * 0.6, "\(kind): worth \(worth) gold for a price of \(kind.price)")
        }
    }
}
