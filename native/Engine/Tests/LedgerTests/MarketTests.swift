import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The equipment market, the choice of premises and the luxury shop run, and the books balance.
final class MarketTests: XCTestCase {
    private func cafe(_ e: inout GameEngine) throws -> Int {
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
        let res = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 30_000_000)
        guard case .success(let id) = res else { throw XCTSkip("could not start: \(res)") }
        return id
    }

    func testBrandsAreDataAndStableAndPremisesCanBeChosen() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        let id = try cafe(&e)
        let needs = e.equipmentNeeds(companyID: id)
        XCTAssertFalse(needs.isEmpty)
        let item = try XCTUnwrap(needs.first { !$0.isVehicle && !$0.isSoftware })
        let a = e.equipmentOffers(companyID: id, equipmentID: item.equipmentID)
        XCTAssertEqual(a.count % 3, 0, "each brand comes in three classes")
        XCTAssertGreaterThanOrEqual(a.count, 9)
        XCTAssertEqual(a, e.equipmentOffers(companyID: id, equipmentID: item.equipmentID), "the same seed gives the same catalogue")
        XCTAssertTrue(a.filter { $0.cls == 2 }.allSatisfy { $0.priceFactor > a.filter { $0.cls == 0 }.map { $0.priceFactor }.min() ?? 0 })

        let listings = e.premisesListings(companyID: id)
        XCTAssertEqual(listings.count, 5)
        XCTAssertEqual(e.takePremises(companyID: id, listing: listings[1]), .ok)
        XCTAssertEqual(e.state.company(id)?.value("prem")["lname"].string, listings[1].name)
        XCTAssertEqual(e.takePremises(companyID: id, listing: listings[3]), .ok, "moving returns the old deposit")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testBuyNewUsedAndLeaseItemByItem() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        let id = try cafe(&e)
        let machines = e.equipmentNeeds(companyID: id).filter { !$0.isVehicle && !$0.isSoftware && $0.kind != "svc" }
        let item = try XCTUnwrap(machines.first)
        let premium = try XCTUnwrap(e.equipmentOffers(companyID: id, equipmentID: item.equipmentID).first { $0.cls == 2 })
        let n0 = e.state.company(id)?.value("eq")[item.equipmentID]["n"].double ?? 0
        XCTAssertEqual(e.buyEquipmentItem(companyID: id, equipmentID: item.equipmentID, offer: premium, quantity: 2, payment: .cash), .ok)
        let rec = try XCTUnwrap(e.state.company(id)?.value("eq")[item.equipmentID])
        XCTAssertEqual(rec["n"].double, n0 + 2)
        XCTAssertTrue(rec["mods"].array.contains { $0["nm"].string == premium.name })

        let used = e.usedListings(companyID: id, equipmentID: item.equipmentID)
        if let u = used.first {
            XCTAssertEqual(e.buyUsedItem(companyID: id, equipmentID: item.equipmentID, listing: u, payment: .cash), .ok)
            XCTAssertFalse(e.usedListings(companyID: id, equipmentID: item.equipmentID).contains { $0.id == u.id }, "a bought listing is gone")
            let owned = try XCTUnwrap(e.ownedEquipment(companyID: id).first { $0.equipmentID == item.equipmentID })
            XCTAssertEqual(owned.units.count, Int(n0) + 3)
            XCTAssertTrue(owned.units.contains { $0.boughtUsed })
            let unit = try XCTUnwrap(owned.units.first { $0.boughtUsed })
            XCTAssertGreaterThan(e.sellEquipmentUnit(companyID: id, equipmentID: item.equipmentID, unitID: unit.id), 0)
        }
        // the weeks run with the brand's units
        for _ in 0..<(6 * 7) { _ = e.nextDay() }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testSubscriptionLeaseAndVehicleOfferWork() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 9)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "taxi", cityID: e.state.player.cityID, form: .limited, fundWith: 40_000_000) else { throw XCTSkip("no taxi") }
        let needs = e.equipmentNeeds(companyID: id)
        let car = try XCTUnwrap(needs.first { $0.isVehicle })
        let makes = e.vehicleOffers(companyID: id, equipmentID: car.equipmentID)
        XCTAssertFalse(makes.isEmpty)
        let v0 = e.state.company(id)?.value("veh").array.count ?? 0
        XCTAssertEqual(e.buyVehicleItem(companyID: id, equipmentID: car.equipmentID, offer: makes[0], payment: .finance), .ok)
        XCTAssertEqual(e.buyVehicleItem(companyID: id, equipmentID: car.equipmentID, offer: makes[0], payment: .lease), .ok)
        XCTAssertEqual(e.state.company(id)?.value("veh").array.count, v0 + 2)
        XCTAssertFalse(e.usedListings(companyID: id, equipmentID: car.equipmentID).isEmpty)
        if let soft = needs.first(where: { $0.isSoftware && $0.subscription }), let o = e.equipmentOffers(companyID: id, equipmentID: soft.equipmentID).first(where: { $0.cls == 1 }) {
            XCTAssertEqual(e.subscribeSoftware(companyID: id, equipmentID: soft.equipmentID, plan: 1, offer: o), .ok)
            XCTAssertNotNil(e.ownedEquipment(companyID: id).first { $0.subscription != nil })
        }
        for _ in 0..<(6 * 7) { _ = e.nextDay() }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testLuxuryBuyHoldEarnAndSell() throws {
        var e = try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 4)
        e.update { s, _, _ in Ledger.move(&s, .me, 600_000_000, why: "Test funds") }
        let nw0 = e.netWorth.total
        XCTAssertEqual(e.buyLuxury(itemID: "j1"), .ok)
        XCTAssertEqual(e.buyLuxury(itemID: "e2"), .ok)
        XCTAssertEqual(e.buyLuxury(itemID: "nope"), .unknownItem)
        XCTAssertEqual(e.luxuryPieces.count, 2)
        XCTAssertGreaterThan(e.luxuryValue, 300_000_000)
        XCTAssertLessThan(abs(e.netWorth.total - nw0), 1, "buying changes cash into the piece at the same value")
        let jet = try XCTUnwrap(e.luxuryPieces.first { $0.item.id == "j1" })
        e.setLuxuryUse(pieceID: jet.id, use: "charter")
        let cash0 = e.state.cash
        for _ in 0..<(30 * 7) { _ = e.nextDay() }
        XCTAssertNotEqual(e.state.cash, cash0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        XCTAssertGreaterThan(e.sellLuxury(pieceID: jet.id), 0)
        XCTAssertEqual(e.luxuryPieces.count, 1)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testCompanyCarCountsInTheCompanyNotInPersonalWorth() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        let id = try cafe(&e)
        e.update { s, _, _ in Ledger.moveRaw(&s, .company(id), 20_000_000) ; Ledger.moveRaw(&s, .me, -20_000_000) }
        e.update { s, _, _ in s.companies[s.companyIndex(id)!].status = .open }
        guard let c = e.luxuryCompanies(itemID: "c15").first(where: { $0.id == id }) else { throw XCTSkip("company not eligible") }
        XCTAssertEqual(e.buyLuxury(itemID: "c15", throughCompany: c.id), .ok)
        XCTAssertEqual(e.luxuryValue, 0, "a company's car is not personal")
        XCTAssertEqual(e.state.company(id)?.num("luxBV") ?? 0, 1_300_000, accuracy: 1)
        for _ in 0..<(8 * 7) { _ = e.nextDay() }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
