import XCTest
import GameCore
import Countries
import Employees
import Businesses
import Simulation

/// The Reward menu of group employees prices a reward before it is confirmed: a course costs once and changes no pay; a benefit costs every month.
final class GroupRewardPreviewTests: XCTestCase {
    func testTrainingCostsOnceAndBenefitCostsEveryMonth() throws {
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "Alex", seed: 5)
        let course = e.groupRewardPreview(personID: -1, kind: .training)
        XCTAssertGreaterThan(course.oneOffCost, 0)
        XCTAssertEqual(course.wageAfter, course.wageBefore)
        XCTAssertFalse(course.lines.isEmpty)
        let benefit = e.groupRewardPreview(personID: -1, kind: .futureBenefits)
        XCTAssertGreaterThan(benefit.employerCostPerMonth, 0)
        XCTAssertEqual(benefit.oneOffCost, 0)
    }
}
