import XCTest
import GameCore
import Countries
@testable import Businesses
import Simulation

final class TutorialTests: XCTestCase {
    private func fresh(_ trade: String = "cafe", seed: Int = 11) throws -> GameEngine {
        try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed, story: .fresh, tradeID: trade, chooseFirstItem: true)
    }

    private func companyID(_ e: GameEngine) throws -> Int { try XCTUnwrap(e.state.companies.first?.id) }

    /// A fresh game on the price step with its first product chosen.
    private func atSetPrice(_ trade: String = "cafe", seed: Int = 11) throws -> (GameEngine, Int, SalesItem) {
        var e = try fresh(trade, seed: seed)
        let id = try companyID(e)
        e.tutorialSaw(.company)
        XCTAssertEqual(e.tutorialStep, .setPrice)
        let choice = try XCTUnwrap(e.firstItemChoices(companyID: id).first)
        XCTAssertFalse(e.chooseFirstItem(companyID: id, itemID: choice.id).isRefused)
        XCTAssertEqual(e.tutorialStep, .setPrice, "picking the product is not yet setting its price")
        let item = try XCTUnwrap(e.salesItems(companyID: id).first)
        return (e, id, item)
    }

    /// A fresh game moved straight to a step, with one unread message waiting.
    private func at(_ target: TutorialStep) throws -> GameEngine {
        var e = try fresh()
        e.update { s, _, _ in
            s.addMessage(from: "Bank", title: "First news", body: "Info")
            for step in TutorialStep.allCases {
                if Tutorial.step(s) == target { break }
                Tutorial.advance(&s, from: step)
            }
        }
        XCTAssertEqual(e.tutorialStep, target)
        return e
    }

    func testFreshGameStartsOnOpenCompanyAndOtherStartsHaveNone() throws {
        let e = try fresh()
        XCTAssertEqual(e.tutorialStep, .openCompany)
        XCTAssertFalse(e.tutorialComplete)
        let loan = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 11)
        XCTAssertTrue(loan.tutorialComplete)
    }

    func testStepsRunInTheOrderThePlayerMeetsThem() {
        XCTAssertEqual(TutorialStep.allCases, [.openCompany, .setPrice, .nextDay, .openInbox, .readInbox, .claimGoal])
        XCTAssertEqual(Tutorial.stepCount, 6)
    }

    // MARK: Open the company

    func testOpeningTheCompanyByAnyRouteMovesOnOnce() throws {
        var e = try fresh()
        e.tutorialSaw(.company)
        XCTAssertEqual(e.tutorialStep, .setPrice)
        e.tutorialSaw(.company)
        XCTAssertEqual(e.tutorialStep, .setPrice, "seeing the company again changes nothing")
    }

    func testPickingTheFirstProductCountsAsOpeningTheCompany() throws {
        var e = try fresh()
        let id = try companyID(e)
        let choice = try XCTUnwrap(e.firstItemChoices(companyID: id).first)
        XCTAssertFalse(e.chooseFirstItem(companyID: id, itemID: choice.id).isRefused)
        XCTAssertEqual(e.tutorialStep, .setPrice)
    }

    func testSeeingTheInboxEarlyDoesNotSkipTheCompany() throws {
        var e = try fresh()
        e.tutorialSaw(.inbox)
        XCTAssertEqual(e.tutorialStep, .openCompany)
    }

    // MARK: Set the price

    func testKeepingTheShownPriceCounts() throws {
        let (e0, id, item) = try atSetPrice()
        var e = e0
        XCTAssertFalse(e.setItemPrice(companyID: id, itemID: item.id, price: item.price).isRefused)
        XCTAssertEqual(e.tutorialStep, .nextDay)
    }

    func testTheMarketCheapAndPremiumPricesAllCount() throws {
        for factor in [1.0, 0.9, 1.1] {
            let (e0, id, item) = try atSetPrice()
            var e = e0
            let range = e.itemPriceRange(companyID: id)
            let price = item.marketPrice * min(max(factor, range.lowerBound), range.upperBound)
            XCTAssertFalse(e.setItemPrice(companyID: id, itemID: item.id, price: price).isRefused, "price factor \(factor)")
            XCTAssertEqual(e.tutorialStep, .nextDay, "price factor \(factor)")
        }
    }

    func testAServiceFirstProductPricesTheSameWay() throws {
        let (e0, id, item) = try atSetPrice("handy", seed: 5)
        var e = e0
        let page = try XCTUnwrap(e.itemPage(companyID: id, itemID: item.id))
        XCTAssertFalse(e.setItemPrice(companyID: id, itemID: item.id, price: page.item.marketPrice).isRefused, "the market price is always a valid choice")
        XCTAssertEqual(e.tutorialStep, .nextDay)
    }

    func testPricingFromAnywhereAlsoCountsTheOpenStep() throws {
        var e = try fresh()
        let id = try companyID(e)
        let choice = try XCTUnwrap(e.firstItemChoices(companyID: id).first)
        e.update { s, d, _ in SalesItems.settlePick(&s, companyID: id, keeping: choice.id, data: d) }
        XCTAssertEqual(e.tutorialStep, .openCompany)
        let item = try XCTUnwrap(e.salesItems(companyID: id).first)
        XCTAssertFalse(e.setItemPrice(companyID: id, itemID: item.id, price: item.price).isRefused)
        XCTAssertEqual(e.tutorialStep, .nextDay, "a price set means the company was open")
    }

    func testARefusedPriceKeepsTheStep() throws {
        let (e0, id, item) = try atSetPrice()
        var e = e0
        XCTAssertTrue(e.setItemPrice(companyID: id, itemID: item.id, price: -1).isRefused)
        XCTAssertEqual(e.tutorialStep, .setPrice)
    }

    func testChoosingASupplierNeverMovesTheGuide() throws {
        let (e0, id, item) = try atSetPrice()
        var e = e0
        if let page = e.itemPage(companyID: id, itemID: item.id),
           let other = page.offers.first(where: { $0.vendorID != page.record?.supplierID && $0.fit != .cannot }) {
            _ = e.setItemSupplier(companyID: id, itemID: item.id, vendorID: other.vendorID)
        }
        if let row = e.supplyLines(companyID: id).flatMap({ $0.rows }).first(where: { $0.canSwitch }),
           let other = row.offers.first(where: { !$0.isCurrent && $0.blocked == nil }) {
            _ = e.chooseSupply(companyID: id, change: other.change)
        }
        XCTAssertEqual(e.tutorialStep, .setPrice)
    }

    func testNothingToPricePassesThePriceStep() throws {
        let (e0, id, _) = try atSetPrice()
        var e = e0
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].managerID = 999_999 } }
        e.settleTutorial()
        XCTAssertEqual(e.tutorialStep, .nextDay, "a manager sets the prices, so there is nothing for the player to set")
    }

    func testOldSavesOnTheSupplierStepResumeOnPricing() throws {
        var e = try fresh()
        e.update { s, _, _ in s.rest[Tutorial.key] = .object(["step": .string("pickSupplier")]) }
        XCTAssertEqual(e.tutorialStep, .setPrice)
        XCTAssertEqual(e.tutorialPosition, 2)
    }

    // MARK: Next day

    func testNextDayMovesOnFromItsStep() throws {
        var e = try at(.nextDay)
        e.nextDay()
        XCTAssertEqual(e.tutorialStep, .openInbox)
    }

    func testNextDayNeverStandsInForPricing() throws {
        let (e0, _, _) = try atSetPrice()
        var e = e0
        e.nextDay()
        XCTAssertEqual(e.tutorialStep, .setPrice)
    }

    // MARK: Inbox

    func testOpeningTheInboxByAnyRouteMovesOn() throws {
        var e = try at(.openInbox)
        e.tutorialSaw(.inbox)
        XCTAssertEqual(e.tutorialStep, .readInbox)
    }

    func testAnInboxWithNothingNewPassesTheReadingStep() throws {
        var e = try at(.openInbox)
        e.update { s, _, _ in for i in s.inbox.indices { s.inbox[i].isRead = true } }
        e.tutorialSaw(.inbox)
        XCTAssertNotEqual(e.tutorialStep, .readInbox)
        XCTAssertNotEqual(e.tutorialStep, .openInbox)
    }

    func testReadingAnyMessageFinishesTheReadingStep() throws {
        var e = try at(.readInbox)
        let id = try XCTUnwrap(e.state.inbox.first { !$0.isRead }?.id)
        e.markMessageRead(id)
        XCTAssertTrue(e.state.inbox.first { $0.id == id }?.isRead ?? false)
        XCTAssertNotEqual(e.tutorialStep, .readInbox)
    }

    func testReadingAMessageAlsoCountsOpeningTheInbox() throws {
        var e = try at(.openInbox)
        let id = try XCTUnwrap(e.state.inbox.first { !$0.isRead }?.id)
        e.markMessageRead(id)
        XCTAssertNotEqual(e.tutorialStep, .openInbox)
        XCTAssertNotEqual(e.tutorialStep, .readInbox)
    }

    func testReadingBeforeTheDayHasPassedDoesNotSkipTheDay() throws {
        var e = try at(.nextDay)
        let id = try XCTUnwrap(e.state.inbox.first { !$0.isRead }?.id)
        e.markMessageRead(id)
        XCTAssertEqual(e.tutorialStep, .nextDay)
    }

    // MARK: Claim

    func testReadingTheInboxEndsTheGuideWhenNoRewardIsReady() throws {
        var e = try at(.readInbox)
        e.update { s, _, _ in
            s.rest["ldr"] = .object(["done": .object([:])])
            PlayerGoals.setDailyGoalsOff(&s, true)
        }
        if !e.claimableGoals().isEmpty { throw XCTSkip("a career goal is ready on day one") }
        e.tutorialAdvance(from: .readInbox)
        XCTAssertTrue(e.tutorialComplete, "the guide must not wait days for a goal")
    }

    func testAReadyRewardKeepsTheClaimStepUntilItIsClaimed() throws {
        var e = try at(.readInbox)
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
        var e = try at(.claimGoal)
        e.update { s, _, _ in
            s.rest["ldr"] = .object(["done": .object([:])])
            PlayerGoals.setDailyGoalsOff(&s, true)
        }
        e.nextDay()
        if e.claimableGoals().isEmpty { XCTAssertTrue(e.tutorialComplete) } else { XCTAssertEqual(e.tutorialStep, .claimGoal) }
    }

    // MARK: The whole walk

    func testTheWholeWalkEndsTheGuide() throws {
        let (e0, id, item) = try atSetPrice()
        var e = e0
        XCTAssertFalse(e.setItemPrice(companyID: id, itemID: item.id, price: item.price).isRefused)
        e.nextDay()
        XCTAssertEqual(e.tutorialStep, .openInbox)
        e.update { s, _, _ in s.addMessage(from: "Bank", title: "News", body: "Info") }
        e.tutorialSaw(.inbox)
        if e.tutorialStep == .readInbox {
            let unread = try XCTUnwrap(e.tutorialInboxGuide.first)
            e.markMessageRead(unread)
        }
        if e.tutorialStep == .claimGoal, let goal = e.claimableGoals().first {
            _ = e.claimGoal(kind: goal.kind, id: goal.goalID)
        }
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
        let id = try companyID(e)
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

    func testThePositionCountsFromOneAndEndsWithTheTutorial() throws {
        var e = try fresh()
        XCTAssertEqual(e.tutorialPosition, 1)
        e.tutorialSaw(.company)
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
        e.tutorialSaw(.company)
        e.update { s, _, _ in Tutorial.sync(&s) }
        XCTAssertEqual(e.tutorialStep, .setPrice, "a live company keeps the guide going")
        e.update { s, _, _ in
            s.companies.removeAll()
            Tutorial.sync(&s)
        }
        XCTAssertTrue(e.tutorialComplete)
    }
}
