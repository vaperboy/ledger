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
        let ready: Bool = !e.claimableGoals().isEmpty
        e.tutorialAdvance(from: .readInbox)
        if ready {
            XCTAssertEqual(e.tutorialStep, .claimGoal)
            e.tutorialAdvance(from: .claimGoal)
        }
        XCTAssertTrue(e.tutorialComplete)
    }

    private func atReadInbox() throws -> GameEngine {
        var e = try fresh()
        e.update { s, _, _ in
            for step in [TutorialStep.openCompany, .pickSupplier, .setPrice, .nextDay, .openInbox] { Tutorial.advance(&s, from: step) }
        }
        XCTAssertEqual(e.tutorialStep, .readInbox)
        return e
    }

    func testReadingTheInboxEndsTheGuideWhenNoRewardIsReady() throws {
        var e = try atReadInbox()
        e.update { s, _, _ in
            s.rest["ldr"] = .object(["done": .object([:])])
            PlayerGoals.setDailyGoalsOff(&s, true)
        }
        if !e.claimableGoals().isEmpty { throw XCTSkip("a career goal is ready on day one") }
        e.tutorialAdvance(from: .readInbox)
        XCTAssertTrue(e.tutorialComplete, "the guide must not wait days for a goal")
    }

    func testAReadyRewardKeepsTheClaimStepUntilItIsClaimed() throws {
        var e = try atReadInbox()
        e.update { s, _, _ in s.rest["ldr"] = .object(["done": .object(["M1": .object(["w": .number(Double(s.week)), "u": .number(1)])])]) }
        XCTAssertTrue(e.claimableGoals().contains { $0.kind == .ladder && $0.goalID == "M1" })
        e.tutorialAdvance(from: .readInbox)
        XCTAssertEqual(e.tutorialStep, .claimGoal)
        e.nextDay()
        XCTAssertEqual(e.tutorialStep, .claimGoal, "a ready reward stays to be claimed")
        if case .notReady = e.claimGoal(kind: .ladder, id: "M1") { XCTFail("M1 should be claimable") }
        XCTAssertTrue(e.tutorialComplete)
    }

    func testAClaimStepWithNothingReadyEndsOnTheNextDay() throws {
        var e = try fresh()
        e.update { s, _, _ in
            for step in [TutorialStep.openCompany, .pickSupplier, .setPrice, .nextDay, .openInbox, .readInbox] { Tutorial.advance(&s, from: step) }
            s.rest["ldr"] = .object(["done": .object([:])])
            PlayerGoals.setDailyGoalsOff(&s, true)
        }
        XCTAssertEqual(e.tutorialStep, .claimGoal)
        e.nextDay()
        if e.claimableGoals().isEmpty { XCTAssertTrue(e.tutorialComplete) } else { XCTAssertEqual(e.tutorialStep, .claimGoal) }
    }

    func testOnlyAChosenSupplierMovesThePickStepOn() throws {
        var e = try fresh()
        let id = try XCTUnwrap(e.state.companies.first?.id)
        e.tutorialAdvance(from: .openCompany)
        let choice = try XCTUnwrap(e.firstItemChoices(companyID: id).first)
        XCTAssertFalse(e.chooseFirstItem(companyID: id, itemID: choice.id).isRefused)
        let item = try XCTUnwrap(e.salesItems(companyID: id).first)
        e.tutorialAdvance(from: .setPrice)
        e.tutorialAdvance(from: .nextDay)
        XCTAssertEqual(e.tutorialStep, .pickSupplier, "pricing or other steps never stand in for choosing a supplier")
        guard let ask = e.supplyAsk(companyID: id, itemID: item.id) else {
            e.tutorialAdvance(from: .pickSupplier)
            XCTAssertEqual(e.tutorialStep, .setPrice)
            return
        }
        switch ask {
        case .item:
            let offer = try XCTUnwrap(e.itemPage(companyID: id, itemID: item.id)?.offers.first { $0.fit != .cannot })
            XCTAssertFalse(e.setItemSupplier(companyID: id, itemID: item.id, vendorID: offer.vendorID).isRefused)
        case .line(let line):
            let row = try XCTUnwrap(e.supplyLines(companyID: id).flatMap { $0.rows }.first { $0.id == line })
            let other = try XCTUnwrap(row.offers.first { !$0.isCurrent && $0.blocked == nil })
            XCTAssertEqual(e.chooseSupply(companyID: id, change: other.change), .ok)
        }
        XCTAssertEqual(e.tutorialStep, .setPrice)
    }

    func testAHandymanFirstServiceAsksForASupplierAndPricesAfter() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 5, story: .fresh, tradeID: "handy", chooseFirstItem: true)
        let id = try XCTUnwrap(e.state.companies.first?.id)
        e.tutorialAdvance(from: .openCompany)
        let choice = try XCTUnwrap(e.firstItemChoices(companyID: id).first)
        XCTAssertFalse(e.chooseFirstItem(companyID: id, itemID: choice.id).isRefused)
        let item = try XCTUnwrap(e.salesItems(companyID: id).first)
        if let ask = e.supplyAsk(companyID: id, itemID: item.id), case .line(let line) = ask {
            let row = try XCTUnwrap(e.supplyLines(companyID: id).flatMap { $0.rows }.first { $0.id == line })
            let other = try XCTUnwrap(row.offers.first { !$0.isCurrent && $0.blocked == nil })
            XCTAssertEqual(e.chooseSupply(companyID: id, change: other.change), .ok)
        } else {
            e.tutorialAdvance(from: .pickSupplier)
        }
        XCTAssertEqual(e.tutorialStep, .setPrice)
        let page = try XCTUnwrap(e.itemPage(companyID: id, itemID: item.id))
        XCTAssertFalse(e.setItemPrice(companyID: id, itemID: item.id, price: page.item.marketPrice).isRefused, "the market price is always a valid choice")
        XCTAssertEqual(e.tutorialStep, .nextDay)
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
