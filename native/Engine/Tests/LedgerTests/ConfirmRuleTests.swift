import XCTest
@testable import Events

/// The single "Are you sure" rule: a spend at or above the player's size and anything irreversible ask; everything else applies at once.
final class ConfirmRuleTests: XCTestCase {
    func testIrreversibleAlwaysAsks() {
        XCTAssertTrue(ConfirmRule.asks(irreversible: true, amount: nil, limit: nil))
        XCTAssertTrue(ConfirmRule.asks(irreversible: true, amount: 1, limit: 1_000))
    }

    func testNothingSpentNeverAsks() {
        XCTAssertFalse(ConfirmRule.asks(irreversible: false, amount: nil, limit: 0))
        XCTAssertFalse(ConfirmRule.asks(irreversible: false, amount: 0, limit: 0))
        XCTAssertFalse(ConfirmRule.asks(irreversible: false, amount: -5, limit: 100))
    }

    func testSpendsAreComparedWithTheChosenSize() {
        XCTAssertFalse(ConfirmRule.asks(irreversible: false, amount: 499, limit: 500))
        XCTAssertTrue(ConfirmRule.asks(irreversible: false, amount: 500, limit: 500))
        XCTAssertTrue(ConfirmRule.asks(irreversible: false, amount: 10_000, limit: 500))
    }

    func testAlwaysAskSizeAsksEverySpendAndUnknownCurrencyAsks() {
        XCTAssertTrue(ConfirmRule.asks(irreversible: false, amount: 1, limit: 0))
        XCTAssertTrue(ConfirmRule.asks(irreversible: false, amount: 1, limit: nil))
    }

    func testInboxRoutineAnswersNeverReachTheQuestion() {
        // An answer that spends nothing and cannot be undone is not a question at all, whatever the size.
        let none = DecisionConfirmation(amount: nil, irreversible: false)
        XCTAssertFalse(none.needsQuestion)
        XCTAssertFalse(ConfirmRule.asks(irreversible: none.irreversible, amount: none.amount, limit: 0))
    }
}
