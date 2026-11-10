import XCTest
import GameCore
import Countries
@testable import Businesses
import Simulation

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
        let id = try XCTUnwrap(e.state.companies.first?.id)
        e.tutorialAdvance(from: .setPrice)
        XCTAssertEqual(e.tutorialStep, .openCompany)
        e.tutorialAdvance(from: .openCompany)
        XCTAssertEqual(e.tutorialStep, .pickSupplier)
        let choice = try XCTUnwrap(e.firstItemChoices(companyID: id).first)
        XCTAssertFalse(e.chooseFirstItem(companyID: id, itemID: choice.id).isRefused)
        XCTAssertEqual(e.tutorialStep, .pickSupplier)
        let item = try XCTUnwrap(e.salesItems(companyID: id).first)
        XCTAssertFalse(e.setItemPrice(companyID: id, itemID: item.id, price: item.price).isRefused)
        XCTAssertEqual(e.tutorialStep, .pickSupplier)
        e.tutorialAdvance(from: .pickSupplier)
        XCTAssertEqual(e.tutorialStep, .setPrice)
        XCTAssertFalse(e.setItemPrice(companyID: id, itemID: item.id, price: item.price).isRefused)
        XCTAssertEqual(e.tutorialStep, .nextDay)
        e.nextDay()
        XCTAssertEqual(e.tutorialStep, .openInbox)
        e.tutorialAdvance(from: .openInbox)
        XCTAssertEqual(e.tutorialStep, .readInbox)
        e.tutorialAdvance(from: .readInbox)
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
        let id = try XCTUnwrap(e.state.companies.first?.id)
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

    func testInboxGuideSkipsDecisionsAndReadMessages() throws {
        var e = try fresh()
        e.update { s, _, _ in
            s.addMessage(from: "Bank", title: "First news", body: "Info")
            s.addMessage(kind: "ask", from: "Staff", title: "A question", body: "Decide", status: "open")
        }
        let guide = e.tutorialInboxGuide
        XCTAssertFalse(guide.isEmpty)
        XCTAssertLessThanOrEqual(guide.count, 3)
        for m in e.state.inbox where guide.contains(m.id) { XCTAssertFalse(m.status == "open" && m.isOwnerAddressed) }
        XCTAssertFalse(guide.contains { id in e.state.inbox.first { $0.id == id }?.title == "A question" })
    }

    func testStepsRunInTheOrderThePlayerMeetsThem() {
        XCTAssertEqual(TutorialStep.allCases, [.openCompany, .pickSupplier, .setPrice, .nextDay, .openInbox, .readInbox, .claimGoal])
        XCTAssertEqual(Tutorial.stepCount, 7)
    }

    func testThePositionCountsFromOneAndEndsWithTheTutorial() throws {
        var e = try fresh()
        XCTAssertEqual(e.tutorialPosition, 1)
        e.tutorialAdvance(from: .openCompany)
        XCTAssertEqual(e.tutorialPosition, 2)
        e.tutorialFinish()
        XCTAssertNil(e.tutorialPosition)
    }

    func testReplayStartsAgainFromTheFirstStepEvenAfterASkip() throws {
        var e = try fresh()
        e.tutorialFinish()
        XCTAssertTrue(e.tutorialComplete)
        e.tutorialRestart()
        XCTAssertEqual(e.tutorialStep, .openCompany)
        XCTAssertEqual(e.tutorialPosition, 1)
    }

    func testAStepThatCanNoLongerBeDoneDoesNotTrapThePlayer() throws {
        var e = try fresh()
        e.tutorialAdvance(from: .openCompany)
        e.update { s, _, _ in Tutorial.sync(&s) }
        XCTAssertEqual(e.tutorialStep, .pickSupplier, "a live company keeps the guide going")
        e.update { s, _, _ in
            s.companies.removeAll()
            Tutorial.sync(&s)
        }
        XCTAssertTrue(e.tutorialComplete)
    }
}
