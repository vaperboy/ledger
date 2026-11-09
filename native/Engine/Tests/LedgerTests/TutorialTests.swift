import XCTest
import GameCore
import Countries
@testable import Businesses
import Simulation

/// The new-player tutorial: it is in the save, moves on only when the player does the step, and holds back the quick set-up until it is done.
final class TutorialTests: XCTestCase {
    private func fresh() throws -> GameEngine {
        try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 11, story: .fresh, tradeID: "cafe", chooseFirstItem: true)
    }

    func testFreshGameStartsOnOpenCompanyAndOtherStartsHaveNone() throws {
        let e = try fresh()
        XCTAssertEqual(e.tutorialStep, .openCompany)
        XCTAssertFalse(e.tutorialComplete)
        let loan = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 11)
        XCTAssertTrue(loan.tutorialComplete)
    }

    func testOpeningSupplierPricingDayAndGoalWalkTheSteps() throws {
        var e = try fresh()
        let id = try XCTUnwrap(e.state.companies.first { $0.type != "hold" }?.id)
        e.tutorialAdvance(from: .setPrice)
        XCTAssertEqual(e.tutorialStep, .openCompany)
        e.tutorialAdvance(from: .openCompany)
        XCTAssertEqual(e.tutorialStep, .pickSupplier)
        let choice = try XCTUnwrap(e.firstItemChoices(companyID: id).first)
        XCTAssertFalse(e.chooseFirstItem(companyID: id, itemID: choice.id).isRefused)
        XCTAssertEqual(e.tutorialStep, .pickSupplier)
        let item = try XCTUnwrap(e.salesItems(companyID: id).first)
        // A price set early does not skip the supplier step.
        XCTAssertFalse(e.setItemPrice(companyID: id, itemID: item.id, price: item.price).isRefused)
        XCTAssertEqual(e.tutorialStep, .pickSupplier)
        e.tutorialAdvance(from: .pickSupplier)
        XCTAssertEqual(e.tutorialStep, .setPrice)
        XCTAssertFalse(e.setItemPrice(companyID: id, itemID: item.id, price: item.price).isRefused)
        XCTAssertEqual(e.tutorialStep, .nextDay)
        e.nextDay()
        XCTAssertEqual(e.tutorialStep, .claimGoal)
        e.tutorialAdvance(from: .claimGoal)
        XCTAssertTrue(e.tutorialComplete)
    }

    func testSkipEndsTheTutorialAtAnyStep() throws {
        var e = try fresh()
        e.tutorialFinish()
        XCTAssertTrue(e.tutorialComplete)
    }

    func testStateSurvivesASaveRoundTrip() throws {
        let e = try fresh()
        let data = try JSONEncoder().encode(e.state)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(Tutorial.step(back), .openCompany)
    }

    func testStandardTeamAndExtraEquipmentAreNeverBoughtForThePlayer() throws {
        var e = try fresh()
        let id = try XCTUnwrap(e.state.companies.first { $0.type != "hold" }?.id)
        XCTAssertTrue(e.quickSetup(companyID: id).isEmpty)
        var wide = SetupChoices()
        wide.team = .standard
        wide.optionalEquipment = true
        let held = e.tutorialLimited(wide)
        XCTAssertEqual(held.team, .minimum)
        XCTAssertFalse(held.optionalEquipment)
        e.tutorialFinish()
        XCTAssertEqual(e.tutorialLimited(wide).team, .minimum, "never bought for the player, tutorial or not")
    }
}
