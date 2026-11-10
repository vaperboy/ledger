import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

final class WorkplaceModeTests: XCTestCase {
    private func start(_ trade: String, seed: Int) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 300_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID) else { throw XCTSkip("start") }
        return (e, id)
    }

    private func tryHire(_ e: inout GameEngine, _ id: Int, role: String) -> Bool {
        var p = Person(raw: [:])
        e.update { s, d, _ in p = Hiring.generateCandidate(role: role, company: s.company(id), faces: false, state: &s, data: d) }
        return e.hire(personID: p.id, companyID: id, monthlyWage: p.askingMonthlyWage * 1.6) == .ok
    }

    func testWorkModesByRole() {
        XCTAssertEqual(Workplaces.mode(role: "cleaner"), .mobile)
        XCTAssertEqual(Workplaces.mode(role: "tutor"), .mobile)
        XCTAssertEqual(Workplaces.mode(role: "dev"), .remote)
        XCTAssertEqual(Workplaces.mode(role: "recept"), .onSite)
        XCTAssertFalse(Workplaces.needsPlace(role: "plumb"))
        XCTAssertTrue(Workplaces.needsPlace(role: "recept"))
    }

    func testCleaningCrewIsNotLimitedByTheKitchenTable() throws {
        var (e, id) = try start("cleaning", seed: 5)
        var hired = 0
        for _ in 0..<8 where tryHire(&e, id, role: "cleaner") { hired += 1 }
        XCTAssertGreaterThan(hired, Workplaces.homePlaces)
        XCTAssertNil(e.hireBlock(companyID: id, role: "cleaner"))
        let w = try XCTUnwrap(e.workplaces(companyID: id))
        XCTAssertLessThanOrEqual(w.used, Workplaces.homePlaces)
    }

    func testFullPlaceBlocksDeskRolesAndOffersABiggerPlace() throws {
        var (e, id) = try start("law", seed: 3)
        for _ in 0..<8 { _ = tryHire(&e, id, role: "recept") }
        let why = try XCTUnwrap(e.hireBlock(companyID: id, role: "recept"))
        XCTAssertTrue(why.contains("Move to bigger premises"))
        XCTAssertNil(e.hireBlock(companyID: id, role: "lawyer"))
        XCTAssertNotNil(e.roomListing(companyID: id))
        XCTAssertEqual(e.moveForRoom(companyID: id), .ok)
        XCTAssertNil(e.hireBlock(companyID: id, role: "recept"))
    }
}
