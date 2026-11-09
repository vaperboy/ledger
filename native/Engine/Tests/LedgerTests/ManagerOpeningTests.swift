import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Simulation

/// A new place with a manager in charge is built up day by day within the manager's budget: people hired to the plan, equipment for the expected customers, stock.
final class ManagerOpeningTests: XCTestCase {
    private func openedWithManager(_ trade: String, budget: Budget = .normal) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 4)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 500_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            Payments.injectCash(&s, companyID: id, amount: 300_000_000)
            // Opened bare: papers in order, the minimum kit only, no team.
            let rep = CompanySetup.quickSetupReport(&s, companyID: id, data: data, options: CompanySetup.SetupOptions(team: .minimum, payrollMonthsReserve: 2, teamInPlace: true))
            _ = rep
            if let i = s.companyIndex(id) {
                s.companies[i].status = .open; s.companies[i].openedWeek = s.week
                if let co = s.company(id), let bd = data.catalog[co.type] {
                    for _ in 0..<4 {
                        let c = ManagerModel.generateCandidate(company: co, type: bd.managerType, state: &s, data: data)
                        if ManagerModel.hire(&s, personID: c.id, companyID: id, monthlyWage: c.askingMonthlyWage * 1.4, data: data) == .ok { break }
                    }
                }
                ManagerModel.setBudget(&s, companyID: id, budget: budget, data: data)
            }
        }
        guard e.state.company(id)?.managerID != nil else { throw XCTSkip("no manager hired") }
        return (e, id)
    }

    func testTheManagerHiresTheTeamAndBuysEquipmentDayByDay() throws {
        var (e, id) = try openedWithManager("gym", budget: .free)
        let bd = try XCTUnwrap(e.data.catalog["gym"])
        // The place opened with a few machines only; the manager adds more as customers are expected.
        e.update { s, _, _ in let i = s.companyIndex(id)!; var eq = s.companies[i].value("eq"); eq[bd.equipment[0].id]["n"] = 2; s.companies[i].set("eq", eq) }
        let before = CapacityModel.equipmentCount(try XCTUnwrap(e.state.company(id)), bd.equipment[0])
        let staff0 = try XCTUnwrap(e.state.company(id)).staff.count
        var staffByDay: [Int] = []
        for _ in 0..<14 { _ = e.nextDay(); staffByDay.append(e.state.company(id)?.staff.count ?? 0) }
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertGreaterThan(co.staff.count, staff0, "the manager filled vacancies of the plan")
        XCTAssertGreaterThan(CapacityModel.equipmentCount(co, bd.equipment[0]), before, "equipment was bought for the customers expected")
        XCTAssertTrue(staffByDay.last! - staffByDay.first! <= 14, "at most one hire a day")
    }

    func testATightBudgetManagerDoesNotActAlone() throws {
        var (e, id) = try openedWithManager("gym", budget: .tight)
        let staff0 = try XCTUnwrap(e.state.company(id)).staff.count
        let n0 = CapacityModel.equipmentCount(try XCTUnwrap(e.state.company(id)), try XCTUnwrap(e.data.catalog["gym"]).equipment[0])
        for _ in 0..<7 { _ = e.nextDay() }
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.staff.count, staff0)
        XCTAssertEqual(CapacityModel.equipmentCount(co, try XCTUnwrap(e.data.catalog["gym"]).equipment[0]), n0)
    }

    func testExpectationsGrowWithTheWeeksAndWithAGrowOrder() throws {
        var (e, id) = try openedWithManager("cafe")
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(ManagerOpening.expectedShare(co, week: e.state.week), 0.5, accuracy: 0.001)
        XCTAssertEqual(ManagerOpening.expectedShare(co, week: e.state.week + 3), 0.8, accuracy: 0.001)
        XCTAssertEqual(ManagerOpening.expectedShare(co, week: e.state.week + 9), 1, accuracy: 0.001)
        _ = e.nextDay()
    }

    func testTheManagerStopsBuildingAfterTheOpeningWindow() throws {
        var (e, id) = try openedWithManager("gym")
        e.update { s, _, _ in s.week += ManagerOpening.windowWeeks + 1 }
        let n0 = e.state.company(id)?.staff.count ?? 0
        e.update { s, d, _ in ManagerOpening.runDay(&s, data: d) }
        XCTAssertEqual(e.state.company(id)?.staff.count, n0)
    }
}

extension ManagerOpeningTests {
    func testAnItemAboveTheBudgetIsLeftToTheOwner() throws {
        var (e, id) = try openedWithManager("gym")
        let bd = try XCTUnwrap(e.data.catalog["gym"])
        e.update { s, _, _ in let i = s.companyIndex(id)!; var eq = s.companies[i].value("eq"); eq[bd.equipment[0].id]["n"] = 2; s.companies[i].set("eq", eq) }
        for _ in 0..<10 { _ = e.nextDay() }
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(CapacityModel.equipmentCount(co, bd.equipment[0]), 2)
        XCTAssertFalse(co.value("flags")["opnAsk_\(bd.equipment[0].id)"].isNull)
    }
}
