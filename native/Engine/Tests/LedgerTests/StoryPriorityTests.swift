import XCTest
import Simulation

/// The week report's story sentence: one test per rule, the priority order and the 110 character cap.
final class StoryPriorityTests: XCTestCase {
    func testRule1CashBelowZero() {
        let i = WeekStoryInput(cashBelowZeroCompany: "Nordvik Cafe", badEventHeadline: "A pipe burst.", badEventCostShare: 0.5, profit: 100, lastWeekProfit: -5)
        XCTAssertEqual(WeekStory.sentence(i), "Nordvik Cafe ran out of cash. A bill waits for next week.")
    }

    func testRule2BadEventOverTenPercent() {
        let i = WeekStoryInput(badEventHeadline: "A pipe burst in the kitchen. Repairs are costly.", badEventCostShare: 0.2, profit: 100, lastWeekProfit: -5)
        XCTAssertEqual(WeekStory.sentence(i), "A pipe burst in the kitchen.")
    }

    func testRule2IgnoredWhenCheap() {
        let i = WeekStoryInput(badEventHeadline: "A pipe burst.", badEventCostShare: 0.05, profit: 100, lastWeekProfit: -5)
        XCTAssertEqual(WeekStory.sentence(i), "First profitable week.")
    }

    func testRule3FlipToLossNamesTheRun() {
        let i = WeekStoryInput(profit: -50, lastWeekProfit: 80, profitableRunBefore: 4)
        XCTAssertEqual(WeekStory.sentence(i), "First loss in 5 weeks.")
    }

    func testRule3FlipToProfit() {
        let i = WeekStoryInput(profit: 50, lastWeekProfit: -80)
        XCTAssertEqual(WeekStory.sentence(i), "First profitable week.")
    }

    func testRule4CompletedGoal() {
        let i = WeekStoryInput(profit: 50, lastWeekProfit: 40, completedGoalPastTense: "You hired your first worker.", bestOfLast12: true)
        XCTAssertEqual(WeekStory.sentence(i), "You hired your first worker.")
    }

    func testRule5BestAndWorst() {
        XCTAssertEqual(WeekStory.sentence(WeekStoryInput(profit: 90, lastWeekProfit: 40, bestOfLast12: true)), "Your best week yet.")
        XCTAssertEqual(WeekStory.sentence(WeekStoryInput(profit: 10, lastWeekProfit: 40, worstOfLast12: true)), "Slowest week in three months.")
    }

    func testRule6TopSellerChange() {
        let i = WeekStoryInput(profit: 50, lastWeekProfit: 40, topSellerChange: "Harbour Bakery", briefing: "A profit of 50.")
        XCTAssertEqual(WeekStory.sentence(i), "Harbour Bakery is now your best seller.")
    }

    func testRule7Briefing() {
        let i = WeekStoryInput(profit: 50, lastWeekProfit: 40, briefing: "A profit of 50 on 200 of sales.")
        XCTAssertEqual(WeekStory.sentence(i), "A profit of 50 on 200 of sales.")
    }

    func testPriorityOrder() {
        var i = WeekStoryInput(profit: -50, lastWeekProfit: 80, profitableRunBefore: 2, completedGoalPastTense: "You hired.", bestOfLast12: true,
                               worstOfLast12: true, topSellerChange: "X", briefing: "Briefing.")
        XCTAssertEqual(WeekStory.sentence(i), "First loss in 3 weeks.")
        i.lastWeekProfit = -10
        XCTAssertEqual(WeekStory.sentence(i), "You hired.")
        i.completedGoalPastTense = nil
        XCTAssertEqual(WeekStory.sentence(i), "Your best week yet.")
        i.bestOfLast12 = false
        XCTAssertEqual(WeekStory.sentence(i), "Slowest week in three months.")
        i.worstOfLast12 = false
        XCTAssertEqual(WeekStory.sentence(i), "X is now your best seller.")
        i.topSellerChange = nil
        XCTAssertEqual(WeekStory.sentence(i), "Briefing.")
        i.badEventHeadline = "Fire."
        i.badEventCostShare = 0.3
        XCTAssertEqual(WeekStory.sentence(i), "Fire.")
        i.cashBelowZeroCompany = "A"
        XCTAssertEqual(WeekStory.sentence(i), "A ran out of cash. A bill waits for next week.")
    }

    func testCompanyThatDroveItIsNamedWhenItFits() {
        let i = WeekStoryInput(profit: 90, lastWeekProfit: 40, bestOfLast12: true, drivenBy: "Harbour Bakery")
        XCTAssertEqual(WeekStory.sentence(i), "Your best week yet. Harbour Bakery drove it.")
    }

    func testCapAtOneHundredTenCharacters() {
        let long = String(repeating: "word ", count: 60)
        let i = WeekStoryInput(badEventHeadline: long, badEventCostShare: 0.5, profit: 1, lastWeekProfit: 1)
        XCTAssertLessThanOrEqual(WeekStory.sentence(i).count, 110)
        let j = WeekStoryInput(profit: 1, lastWeekProfit: 1, briefing: long)
        XCTAssertLessThanOrEqual(WeekStory.sentence(j).count, 110)
        let k = WeekStoryInput(cashBelowZeroCompany: String(repeating: "N", count: 200))
        XCTAssertLessThanOrEqual(WeekStory.sentence(k).count, 110)
    }
}
