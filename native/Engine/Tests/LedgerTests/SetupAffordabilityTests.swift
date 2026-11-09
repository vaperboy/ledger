import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// A first company is affordable: the picker prices the size the money carries, the minimum includes what the trade cannot open without,
/// and the checklist states its cost and can always be finished from the owner's money or a loan.
final class SetupAffordabilityTests: XCTestCase {
    private func game(seed: Int = 11) throws -> GameEngine { try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed) }

    func testMinimumToOpenIncludesRequiredEquipmentAndVehicles() throws {
        let e = try game(seed: 3)
        var rich = e.state; rich.cash += 1e12
        let est = try XCTUnwrap(CompanySetup.estimate(tradeID: "cleaning", cityID: e.state.player.cityID, size: 1, state: rich, data: e.data))
        XCTAssertGreaterThan(est.requiredEquipment + est.requiredVehicles, 0)
        XCTAssertEqual(est.minimumToOpen, est.documents + est.premisesLeast + est.property + est.wait + est.registration + est.shareCapital + est.abroad + est.requiredEquipmentUpfront + est.requiredVehicles, accuracy: 0.01)
        XCTAssertGreaterThan(est.minimumToOpen, est.documents)
        // equipment that can be financed takes a down payment, and the cheapest place is no dearer than the standard one
        XCTAssertLessThan(est.requiredEquipmentUpfront, est.requiredEquipment)
        let cafe = try XCTUnwrap(CompanySetup.estimate(tradeID: "cafe", cityID: e.state.player.cityID, size: 1, state: rich, data: e.data))
        XCTAssertGreaterThan(cafe.premises, 0)
        XCTAssertLessThanOrEqual(cafe.premisesLeast, cafe.premises)
        XCTAssertLessThan(cafe.minimumToOpen, cafe.documents + cafe.premises + cafe.requiredEquipment)
    }

    func testPickerStartsEachTradeAtTheLargestSizeTheMoneyCarries() throws {
        let e = try game()
        let rows = e.tradeAffordability()
        XCTAssertGreaterThanOrEqual(rows.filter { $0.isFunded }.count, 8, "a new player can start several kinds of business")
        for r in rows where r.blocked == nil {
            let bd = try XCTUnwrap(e.data.catalog[r.tradeID])
            XCTAssertGreaterThanOrEqual(r.size, bd.minSize - 0.001)
            XCTAssertLessThanOrEqual(r.size, r.recommendedSize + 0.001)
            if r.isFunded { XCTAssertLessThanOrEqual(r.minimum ?? 0, r.available + 0.5) }
        }
        // with plenty of money every trade starts at its natural size
        var rich = e
        rich.update { s, _, _ in Ledger.move(&s, .me, 1e11, why: "Test funds") }
        for r in rich.tradeAffordability() where r.blocked == nil { XCTAssertFalse(r.isScaledDown, r.tradeID) }
        // the picker row and the start size agree
        let row = try XCTUnwrap(e.tradePickerRows().first { $0.isFunded })
        XCTAssertEqual(e.affordableStartSize(tradeID: row.tradeID, cityID: e.state.player.cityID), rows.first { $0.tradeID == row.tradeID }?.size)
    }

    func testFundedFirstCompanyCanFinishItsChecklist() throws {
        let e0 = try game(seed: 5)
        let city = e0.state.player.cityID
        let funded = e0.tradeAffordability().filter { $0.isFunded }.prefix(6)
        XCTAssertFalse(funded.isEmpty)
        for row in funded {
            var e = try game(seed: 5)
            let bd = try XCTUnwrap(e.data.catalog[row.tradeID])
            let choices = e.suggestedChoices(tradeID: row.tradeID, cityID: city, size: row.size)
            let plan = try XCTUnwrap(e.newCompanyPlan(tradeID: row.tradeID, cityID: city, size: row.size, choices: choices))
            XCTAssertTrue(plan.isFunded, row.tradeID)
            guard case .success(let out) = e.startCompanyChoosingPremises(tradeID: row.tradeID, cityID: city, size: row.size, name: nil, pick: nil, fundWith: plan.intoCompany, choices: choices) else {
                XCTFail("start \(row.tradeID)"); continue
            }
            let f = try XCTUnwrap(e.setupFunding(companyID: out.companyID))
            XCTAssertTrue(f.isCompletable, "\(row.tradeID) missing \(f.missing)")
            e.fundSetup(companyID: out.companyID)
            let after = try XCTUnwrap(e.setupFunding(companyID: out.companyID))
            XCTAssertLessThanOrEqual(after.missing, 0.5, row.tradeID)
        }
    }

    func testChecklistItemsStateTheirCost() throws {
        var e = try game(seed: 8)
        guard case .success(let id) = e.startCompany(tradeID: "cleaning", cityID: e.state.player.cityID, fundWith: 0, quickSetup: false) else { throw XCTSkip("start") }
        let items = e.openingChecklist(companyID: id)
        let eq = items.filter { $0.id.hasPrefix("eq:") && !$0.isDone }
        XCTAssertFalse(eq.isEmpty)
        for i in eq { XCTAssertGreaterThan(i.cost, 0, i.id); XCTAssertFalse(i.detail.isEmpty, i.id) }
        let f = try XCTUnwrap(e.setupFunding(companyID: id))
        XCTAssertEqual(f.missing, items.filter { !$0.isDone }.reduce(0) { $0 + $1.cost } - max(0, try XCTUnwrap(e.state.company(id)).cash), accuracy: 0.5)
    }
}
