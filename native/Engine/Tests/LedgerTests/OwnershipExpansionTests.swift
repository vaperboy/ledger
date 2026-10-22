import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Events
import Simulation

/// Ownership, expansion and saves: a purchase, a holding or a foreign subsidiary changes the same books, net worth counts each company once,
/// and the rest keys added later (fm, fmPool, tg58, ct/sw33, amb27 pkAll, ach28, org56) survive a save.
final class OwnershipExpansionTests: XCTestCase {
    func testMovingIntoAndOutOfAHoldingNeverCountsACompanyTwice() throws {
        var e = try ChainsTests.engine("UK")
        let cafe = ChainsTests.start(&e, "cafe")
        guard case .success(let hid) = e.createHolding(name: "H", companies: []) else { return XCTFail("holding") }
        let own = try XCTUnwrap(e.state.company(cafe)).ownership / 100
        let value = Valuation.companyValue(try XCTUnwrap(e.state.company(cafe)), state: e.state, trades: e.data.catalog)
        let before = e.netWorth.total
        XCTAssertTrue(e.moveToHolding(companyID: cafe, holdingID: hid))
        // at once, without waiting for the weekly revaluation
        XCTAssertEqual(try XCTUnwrap(e.state.company(hid)).value("fm")["assets"].double, value * own, accuracy: 1)
        XCTAssertEqual(e.netWorth.total, before, accuracy: max(5, abs(before) * 0.001))
        XCTAssertTrue(e.releaseFromHolding(companyID: cafe))
        XCTAssertEqual(try XCTUnwrap(e.state.company(hid)).value("fm")["assets"].double, 0, accuracy: 1)
        XCTAssertEqual(e.netWorth.total, before, accuracy: max(5, abs(before) * 0.001))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testBuyingARivalMovesMoneyThroughTheLedger() throws {
        var e = try ChainsTests.engine("UK")
        let cafe = ChainsTests.start(&e, "cafe")
        ChainsTests.play(&e, days: 56)   // long enough to open and for the local market (and its rivals) to exist
        let co = try XCTUnwrap(e.state.company(cafe))
        let rival = try XCTUnwrap(Rivals.rivals(e.state, for: co).first)
        let price = e.rivalValue(companyID: cafe, rivalID: rival.id)
        let cash0 = e.state.cash
        guard case .ok(let id) = e.buyRival(companyID: cafe, rivalID: rival.id, price: price) else { return XCTFail("not bought") }
        XCTAssertLessThan(e.state.cash, cash0 - price + 1, "the price leaves your account")
        let bought = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(bought.ownership, 100)
        XCTAssertGreaterThan(bought.cash, 0, "start-up money was injected through Payments")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        XCTAssertFalse(Rivals.rivals(e.state, for: try XCTUnwrap(e.state.company(cafe))).contains { $0.id == rival.id })
    }

    func testSellingACompanyInAHoldingLeavesTheHoldingAssetsAtOnce() throws {
        var e = try ChainsTests.engine("UK")
        let cafe = ChainsTests.start(&e, "cafe")
        guard case .success(let hid) = e.createHolding(name: "H", companies: [cafe]) else { return XCTFail("holding") }
        e.update { s, d, c in
            let i = s.companyIndex(cafe)!
            _ = CompanySale.complete(&s, companyIndex: i, buyer: "Test", price: 1_000_000, data: d, context: c)
        }
        XCTAssertEqual(try XCTUnwrap(e.state.company(hid)).value("fm")["assets"].double, 0, accuracy: 1)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testExpandingAbroadCostsMoneyAndLinksTheSubsidiary() throws {
        var e = try ChainsTests.engine("UK")
        let cafe = ChainsTests.start(&e, "cafe")
        e.update { s, _, _ in s.companies[s.companyIndex(cafe)!].reputation = 60; s.companies[s.companyIndex(cafe)!].status = .open }
        let option = try XCTUnwrap(e.abroadOptions(companyID: cafe).first)
        let cash0 = e.state.cash
        guard case .success(let id) = e.expandAbroad(companyID: cafe, countryCode: option.countryCode) else { return XCTFail("no expansion") }
        let sub = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(sub.countryCode, option.countryCode)
        XCTAssertEqual(sub.value("foreignOf").int, cafe)
        XCTAssertLessThan(e.state.cash, cash0, "registration, share capital and the foreign fee come from you")
        XCTAssertTrue(Abroad.foreignCountries(e.state).contains(option.countryCode))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testNewRestKeysRoundTripAndOldSavesLoadWithDefaults() throws {
        var e = try ChainsTests.engine("UK")
        let cafe = ChainsTests.start(&e, "cafe")
        e.update { s, _, _ in
            s.rest["fm"] = .object(["npc": 7, "mandate": "balanced", "fee": 0.01, "bal": 1234.5, "cost": 1000, "warned": false])
            s.rest["fmPool"] = .array([1, 2, 3])
            s.rest["amb27"] = .object(["path": "global", "tier": .object(["global": 1]), "pkAll": true, "settle": 3])
            s.rest["ach28"] = .object(["acq": .object(["w": 4, "t": "x", "old": 1])])
            s.rest["org56"] = .object(["md": .object(["npc": 9])])
            let i = s.companyIndex(cafe)!
            s.companies[i].set("tg58", .object(["bo": 1, "log": .array([])]))
            s.companies[i].set("sw33", .object(["ct": .array([.object(["u": 5])]), "ref": 0]))
        }
        let data = try JSONEncoder().encode(e.state)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(back, e.state)
        XCTAssertEqual(back.rest["fm"]?["bal"].double, 1234.5)
        XCTAssertEqual(back.rest["amb27"]?["pkAll"].bool, true)
        XCTAssertEqual(back.company(cafe)?.value("sw33")["ct"].array.count, 1)
        XCTAssertEqual(back.company(cafe)?.value("tg58")["bo"].int, 1)
        // an old save loads and reads null-safe: the new keys are optional (a new game seeds some of them, so no assertion on absence)
        for name in ["save_cafe_week3", "save_cafe_week15"] {
            let old = try Golden.state(name)
            for k in ["fm", "fmPool", "amb27", "ach28", "org56"] { _ = old.rest[k]?["bal"].double; _ = old.rest[k]?["path"].string }
            XCTAssertNil(FinanceManager.account(old), "no fund manager in an old save")
            XCTAssertEqual(Ambitions.perk(old, e.data, "global"), -1)
            _ = old.companies[0].value("tg58")["bo"].int   // present in these saves already; reads null-safe either way
            XCTAssertEqual(VolumeContracts.committedUnits(old.companies[0]), 0)
            XCTAssertEqual(try JSONDecoder().decode(GameState.self, from: try JSONEncoder().encode(old)), old)
        }
    }
}
