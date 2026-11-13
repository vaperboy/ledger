import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

final class MoneyPackTests: XCTestCase {
    private func game(_ code: String = "UK") throws -> GameEngine {
        try GameEngine.newGame(countryCode: code, playerName: "T", seed: 7)
    }

    func testThePacksAndBonusesAreTheOnesTheStoreSells() {
        XCTAssertEqual(MoneyPacks.packs.map(\.id), ["handful", "bundle", "case", "safe", "mountain"])
        XCTAssertEqual(MoneyPacks.packs.map(\.gold), [10, 50, 125, 250, 530])
        XCTAssertEqual(MoneyPacks.packs.map(\.bonusPercent), [0, 5, 10, 15, 20])
        XCTAssertEqual(MoneyPacks.free.gold, 2)
        XCTAssertTrue(MoneyPacks.free.isFree)
        XCTAssertEqual(MoneyPacks.price(MoneyPacks.free), 0, "the free pack costs no gold")
        XCTAssertEqual(MoneyPacks.freePerDay, 2)
    }

    func testEachPackPaysTheGoldRateWithItsBonus() {
        let expected: [String: Double] = ["handful": 10_000, "bundle": 52_500, "case": 137_500, "safe": 287_500, "mountain": 636_000]
        for p in MoneyPacks.packs {
            XCTAssertEqual(MoneyPacks.gameMoney(p), expected[p.id], p.id)
            XCTAssertEqual(MoneyPacks.gameMoney(p), GoldValue.gameMoney(gold: Double(p.gold)) * Double(100 + p.bonusPercent) / 100, accuracy: 0.5, p.id)
        }
        XCTAssertEqual(MoneyPacks.gameMoney(MoneyPacks.free), 2_000)
        let rates: [Double] = MoneyPacks.packs.map { MoneyPacks.gameMoney($0) / Double($0.gold) }
        XCTAssertEqual(rates, rates.sorted(), "a bigger pack never gives less per gold")
    }

    func testTheAmountInEachCurrencyFollowsTheExchangeRate() throws {
        let book = try CountryBook.bundled()
        for code in ["NO", "US", "JP"] {
            let cur = Currency(country: try XCTUnwrap(book[code]), rates: ExchangeRates())
            for p in MoneyPacks.packs + [MoneyPacks.free] {
                XCTAssertEqual(MoneyPacks.local(p, currency: cur) * cur.rate, MoneyPacks.gameMoney(p), accuracy: 1e-6, "\(code) \(p.id)")
            }
        }
        let nok = Currency(country: try XCTUnwrap(book["NO"]), rates: ExchangeRates())
        XCTAssertEqual(MoneyPacks.local(MoneyPacks.packs[0], currency: nok), 10_000, accuracy: 1e-9, "10 gold is 10,000 kroner")
    }

    func testAPackPaysIntoTheAccountThroughTheLedgerAndTheBooksBalance() throws {
        for code in ["NO", "UK", "US"] {
            var e = try game(code)
            for p in MoneyPacks.packs {
                let before = e.state.cash
                let paid = try XCTUnwrap(e.claimMoneyPack(p.id, claimID: "buy-" + p.id), "\(code) \(p.id)")
                XCTAssertEqual(paid, MoneyPacks.gameMoney(p))
                XCTAssertEqual(e.state.cash, before + paid, accuracy: 1e-6)
                XCTAssertEqual(e.state.statement.first?.label, "Money bought with gold")
                XCTAssertEqual(e.state.statement.first?.amount, paid)
                XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(code) \(p.id)")
            }
        }
    }

    func testTheFreePackHasItsOwnNameAndEachClaimPaysOnce() throws {
        var e = try game()
        XCTAssertNotNil(e.claimMoneyPack("free", claimID: "ad-1"))
        XCTAssertEqual(e.state.statement.first?.label, MoneyPacks.freeLabel)
        XCTAssertNil(e.claimMoneyPack("free", claimID: "ad-1"), "the same claim pays once")
        XCTAssertNil(e.claimMoneyPack("nope", claimID: "x"), "an unknown pack pays nothing")
        XCTAssertNil(e.claimMoneyPack("handful", claimID: ""))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testGoldIsTakenFromTheWalletAndNeverGoesBelowZero() {
        var w = GoldWallet(balance: 60)
        let bundle: MoneyPack = MoneyPacks.packs[1]
        XCTAssertTrue(w.spend(MoneyPacks.price(bundle)))
        XCTAssertEqual(w.balance, 10)
        XCTAssertFalse(w.spend(MoneyPacks.price(MoneyPacks.packs[2])), "125 gold is more than is left")
        XCTAssertEqual(w.balance, 10)
        XCTAssertTrue(w.spend(MoneyPacks.price(MoneyPacks.free)))
        XCTAssertEqual(w.balance, 10, "the free pack takes no gold")
    }

    func testTheFreePackIsCappedAtTwoADayAndTheCapResetsTomorrow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var l = AdLedger()
        XCTAssertEqual(AdPolicy.freeMoneyLeft(now: now, l), 2)
        XCTAssertTrue(AdPolicy.canOfferFreeMoney(entitlements: .free, now: now, l))
        AdPolicy.recordFreeMoney(now: now, &l)
        XCTAssertEqual(AdPolicy.freeMoneyLeft(now: now, l), 1)
        AdPolicy.recordFreeMoney(now: now, &l)
        XCTAssertEqual(AdPolicy.freeMoneyLeft(now: now, l), 0)
        XCTAssertFalse(AdPolicy.canOfferFreeMoney(entitlements: .free, now: now, l), "two a day")
        XCTAssertFalse(AdPolicy.canOfferFreeMoney(entitlements: EntitlementSnapshot(owned: [.pro]), now: now, l), "the cap holds for ad-free players too")
        XCTAssertTrue(AdPolicy.canOfferFreeMoney(entitlements: .free, now: now.addingTimeInterval(2 * 86_400), l), "a new day")
    }

    func testADeclinedAdQuietsTheOfferButNotForAdFreePlayers() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var l = AdLedger()
        l.noteDeclined(now: now)
        XCTAssertFalse(AdPolicy.canOfferFreeMoney(entitlements: .free, now: now, l))
        XCTAssertTrue(AdPolicy.canOfferFreeMoney(entitlements: EntitlementSnapshot(owned: [.pro]), now: now, l), "no ad is shown to them")
    }

    func testTheCapSurvivesASaveAndOldSavesStartAtZero() throws {
        var l = AdLedger()
        let now = Date()
        AdPolicy.recordFreeMoney(now: now, &l)
        let back: AdLedger = try JSONDecoder().decode(AdLedger.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back.freeMoneyToday, 1)
        let old: AdLedger = try JSONDecoder().decode(AdLedger.self, from: Data("{}".utf8))
        XCTAssertEqual(old.freeMoneyToday, 0)
    }
}
