import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Events
import Simulation

final class OwnershipExpansionTests: XCTestCase {
    func testBuyingARivalMovesMoneyThroughTheLedger() throws {
        var e = try ChainsTests.engine("UK")
        let cafe = ChainsTests.start(&e, "cafe")
        ChainsTests.play(&e, days: 56)
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
        for name in ["save_cafe_week3", "save_cafe_week15"] {
            let old = try Golden.state(name)
            for k in ["fm", "fmPool", "amb27", "ach28", "org56"] { _ = old.rest[k]?["bal"].double; _ = old.rest[k]?["path"].string }
            XCTAssertNil(FinanceManager.account(old), "no fund manager in an old save")
            XCTAssertEqual(Ambitions.perk(old, e.data, "global"), -1)
            _ = old.companies[0].value("tg58")["bo"].int
            XCTAssertEqual(VolumeContracts.committedUnits(old.companies[0]), 0)
            XCTAssertEqual(try JSONDecoder().decode(GameState.self, from: try JSONEncoder().encode(old)), old)
        }
    }
}
