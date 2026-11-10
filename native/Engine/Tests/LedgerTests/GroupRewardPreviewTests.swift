import XCTest
import GameCore
import Countries
import Employees
import Businesses
import Simulation

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
