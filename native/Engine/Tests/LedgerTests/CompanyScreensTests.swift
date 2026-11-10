import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

final class CompanyScreensTests: XCTestCase {
    private func game(seed: Int = 7) throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 500_000_000, why: "Test funds") }
        return e
    }

    func testPlanReplacesStandardPremisesCostWithTheChosenPlace() throws {
        let e = try game()
        let city = e.state.player.cityID
        guard let base = e.newCompanyPlan(tradeID: "cafe", cityID: city, size: 1) else { return XCTFail("no plan") }
        XCTAssertEqual(base.premisesKind, .place)
        XCTAssertGreaterThan(base.options.count, 2)
        let std = base.options[base.standardIndex]
        XCTAssertEqual(base.premisesCost, std.rentUpfront, accuracy: 0.5)
        XCTAssertEqual(base.total, base.estimate.total - base.estimate.premises + std.rentUpfront, accuracy: 0.5)
        let buy = e.newCompanyPlan(tradeID: "cafe", cityID: city, size: 1, pick: .init(listingIndex: 0, buy: true))!
        XCTAssertEqual(buy.premisesCost, base.options[0].buyUpfront, accuracy: 0.5)
        XCTAssertGreaterThan(buy.options[0].buyUpfront, buy.options[0].rentUpfront)
        XCTAssertTrue(buy.risks.contains { $0.contains("mortgage") })
        XCTAssertEqual(buy.personalLeft, max(0, buy.available - buy.registrationAndCapital - buy.intoCompany), accuracy: 0.5)
    }

    func testPlanForHomeAndNoPremisesTrades() throws {
        let e = try game()
        let city = e.state.player.cityID
        let home = e.newCompanyPlan(tradeID: "cons", cityID: city, size: 1)!
        XCTAssertEqual(home.premisesKind, .home)
        XCTAssertTrue(home.options.isEmpty)
        XCTAssertTrue(home.risks.contains { $0.contains("starts at home") })
    }

    func testStartingWithAPickedPlaceRentsOrBuysIt() throws {
        var e = try game()
        let city = e.state.player.cityID
        guard case .success(let rented) = e.startCompanyChoosingPremises(tradeID: "cafe", cityID: city, size: 1, name: nil, pick: .init(listingIndex: 4, buy: false)) else { return XCTFail("not started") }
        XCTAssertEqual(rented.premises, .ok)
        let p1 = e.state.company(rented.companyID)!.value("prem")
        XCTAssertFalse(p1["owned"].bool)
        XCTAssertGreaterThan(p1["m2"].double, 0)
        guard case .success(let bought) = e.startCompanyChoosingPremises(tradeID: "cafe", cityID: city, size: 1, name: nil, pick: .init(listingIndex: 1, buy: true)) else { return XCTFail("not started") }
        XCTAssertEqual(bought.premises, .ok)
        XCTAssertTrue(e.state.company(bought.companyID)!.value("prem")["owned"].bool)
        guard case .success(let std) = e.startCompanyChoosingPremises(tradeID: "cafe", cityID: city, size: 1, name: nil, pick: nil) else { return XCTFail("not started") }
        XCTAssertNil(std.premises)
        XCTAssertTrue(e.state.company(std.companyID)!.value("prem").isNull)
    }

    func testInsuranceNeedsAnInsurerAndAdvisersCanBeHired() throws {
        var e = try game()
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID) else { return XCTFail() }
        e.prepareAdvisers(companyID: id)
        var o = e.coverageOverview(companyID: id)!
        XCTAssertNil(o.insurer)
        XCTAssertEqual(o.policies.count, 6)
        XCTAssertNotNil(o.accountant)
        XCTAssertEqual(e.toggleInsurancePolicy(companyID: id, product: "prop"), .done)
        XCTAssertEqual(e.coverageOverview(companyID: id)?.insurer?.name, "Atlas Insurance")
        let insurers = e.adviserChoices(companyID: id, kind: .insurer)
        XCTAssertFalse(insurers.isEmpty)
        XCTAssertEqual(e.chooseAdviser(companyID: id, kind: .insurer, providerID: insurers[0].id), .done)
        o = e.coverageOverview(companyID: id)!
        XCTAssertEqual(o.insurer?.id, insurers[0].id)
        XCTAssertEqual(o.activeCount, 1)
        XCTAssertGreaterThan(o.weeklyPremiums, 0)
        XCTAssertTrue(e.adviserChoices(companyID: id, kind: .insurer).first { $0.isCurrent } != nil)
        XCTAssertEqual(e.chooseAdviser(companyID: id, kind: .insurer, providerID: 0), .removed)
        XCTAssertNil(e.coverageOverview(companyID: id)!.insurer)
    }

    private func twoCompaniesAwaitingPayrollApproval() throws -> (GameEngine, [Int], Message) {
        var e = try game()
        var ids: [Int] = []
        for _ in 0..<2 {
            guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID) else { throw XCTSkip("no company") }
            ids.append(id)
        }
        var days = 0
        while !e.openDecisions.contains(where: { $0.actionID == "pay29all" }), days < 200 * 7 { e.nextDay(); days += 1 }
        let msg = try XCTUnwrap(e.openDecisions.first { $0.actionID == "pay29all" }, "an approval message")
        XCTAssertTrue(ids.allSatisfy { id in msg.value("data")["ids"].array.contains { $0.int == id } }, "one message for both companies")
        return (e, ids, msg)
    }

    func testMovingAHomeCompanyIntoAPlaceAndBack() throws {
        var e = try game()
        guard case .success(let id) = e.startCompany(tradeID: "cons", cityID: e.state.player.cityID) else { return XCTFail() }
        XCTAssertTrue(e.isWorkingFromHome(companyID: id))
        XCTAssertNil(e.moveHomeQuote(companyID: id))
        let l = e.premisesListings(companyID: id)
        XCTAssertGreaterThan(l.count, 2)
        XCTAssertEqual(e.takePremises(companyID: id, listing: l[2], buy: false), .ok)
        XCTAssertFalse(e.isWorkingFromHome(companyID: id))
        let q = e.moveHomeQuote(companyID: id)!
        XCTAssertFalse(q.isOwned)
        XCTAssertGreaterThan(q.proceeds, 0)
        let before = e.state.company(id)!.cash
        XCTAssertTrue(e.giveUpPremises(companyID: id))
        XCTAssertEqual(e.state.company(id)!.cash - before, q.proceeds, accuracy: 1)
        XCTAssertTrue(e.isWorkingFromHome(companyID: id))
    }
}
