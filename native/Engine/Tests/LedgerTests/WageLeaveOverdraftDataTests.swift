import XCTest
import GameCore
import Countries
import Employees
import Finance
import Simulation

/// Data consistency: overdraft rate follows the policy rate, one leave field, minimum wage on the median wage's scale, UMA present.
final class WageLeaveOverdraftDataTests: XCTestCase {
    func testOverdraftRateFollowsPolicyRate() throws {
        let book = try CountryBook.bundled()
        let no = try XCTUnwrap(book.countries.first { $0.code == "NO" })
        var s = try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 7).state
        s.economy.policyRate = no.startingPolicyRate
        XCTAssertEqual(Banking.overdraftRate(state: s, country: no, home: no), 0.14, accuracy: 1e-9, "reference economy keeps the original 14%")
        XCTAssertEqual(Banking.overdraftRate(state: s, country: no, home: no, personal: true), 0.16, accuracy: 1e-9)
        s.economy.policyRate += 0.02
        XCTAssertEqual(Banking.overdraftRate(state: s, country: no, home: no), 0.16, accuracy: 1e-9)
        for c in book.countries { XCTAssertTrue((0.04...0.25).contains(c.overdraftMargin), c.code) }
    }

    func testLeaveHasOneField() throws {
        let book = try CountryBook.bundled()
        XCTAssertEqual(book.countries.count, 23)
        XCTAssertEqual(LabourRules(code: "BR").leaveDays, 30); XCTAssertTrue(LabourRules(code: "BR").leaveCalendarDays)
        XCTAssertEqual(LabourRules(code: "AE").leaveDays, 30); XCTAssertTrue(LabourRules(code: "AE").leaveCalendarDays)
        XCTAssertEqual(LabourRules(code: "FI").leaveDays, 25); XCTAssertFalse(LabourRules(code: "FI").leaveCalendarDays)
        XCTAssertEqual(LabourRules(code: "FI").leaveWeeks, 5, accuracy: 1e-9)
        XCTAssertEqual(LabourRules(code: "SG").leaveDays, 7)
    }

    func testMinimumWageIsOnTheMedianScaleInEveryCountry() throws {
        for c in try CountryBook.bundled().countries {
            let median = c.wageLevel * ReferenceEconomy.medianWage / c.fx
            let ratio = LabourRules(country: c).minMonthly / median
            XCTAssertTrue((0.2...0.85).contains(ratio), "\(c.code) minimum / median = \(ratio)")
        }
    }

    func testMexicoUMAPresent() throws {
        let mx = try XCTUnwrap(try CountryBook.bundled().countries.first { $0.code == "MX" })
        XCTAssertGreaterThan(mx.contributionUnitMonthly, 0)
        XCTAssertEqual(mx.contributionUnitMonthly, 117.31 * 30.4 * mx.fx, accuracy: 5)
    }
}
