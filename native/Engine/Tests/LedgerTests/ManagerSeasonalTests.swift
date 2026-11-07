import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// A manager's seasonal help (hired like the owner would, paid only in season) and the factory / furniture volume tenders.
final class ManagerSeasonalTests: XCTestCase {
    func testSeasonalCrewIsHiredPartTimeForTheSeasonAndTheBooksBalance() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        ChainsTests.play(&e, days: 14)
        let co0 = try XCTUnwrap(e.state.company(id))
        let role = try XCTUnwrap(co0.staff.first?.role, "the cafe has staff after the quick set-up")
        let before = co0.staff.count
        var got = 0
        e.update { s, d, _ in got = ManagerModel.hireSeasonalCrew(&s, companyID: id, role: role, months: [6, 7, 8], count: 2, data: d) }
        XCTAssertGreaterThan(got, 0)
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.staff.count, before + got)
        let crew = co.staff.filter { !$0.value("seas").isNull }
        XCTAssertEqual(crew.count, got)
        XCTAssertTrue(crew.allSatisfy { ($0.weeklyHours ?? 0) > 0 && $0.value("seas").array.map { $0.int } == [6, 7, 8] })
        ChainsTests.play(&e, days: 8 * 7)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testFactoriesAndFurnitureWorkshopsTenderForVolume() {
        for trade in ["factory", "furniture"] {
            let offers = ProjectTenders.catalog[trade] ?? []
            XCTAssertFalse(offers.isEmpty, trade)
            XCTAssertTrue(offers.allSatisfy { $0.volume }, trade)
        }
        XCTAssertNil(ProjectTenders.catalog["farm"], "the original's farm has no way to sell a contract into")
    }
}
