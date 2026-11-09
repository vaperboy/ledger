import XCTest
import GameCore
import Countries
import Employees
import Finance
import Businesses
import Simulation

/// One employer-cost function; the hiring preview equals what payroll books (part-time, seasonal, full-time) in six countries.
final class EmployerCostTests: XCTestCase {
    func testPreviewEqualsWhatPayrollBooksInSixCountries() throws {
        for code in ["UK", "US", "DE", "PL", "MX", "JP"] {
            var e = try GameEngine.newGame(countryCode: code, playerName: "Tester", seed: 9)
            e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
            guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, fundWith: 200_000_000) else { XCTFail("start \(code)"); continue }
            let variants: [(String, Hiring.Terms)] = [("full", Hiring.Terms()), ("part", Hiring.Terms(hours: 20)), ("season", Hiring.Terms(hours: 30, seasonMonths: Array(1...12)))]
            for (name, terms) in variants {
                var pid = 0
                e.update { s, d, _ in pid = Hiring.generateCandidate(role: "cook", company: s.company(id), tier: "mid", state: &s, data: d).id }
                let wage = e.marketWage(role: "cook", companyID: id) * 1.8
                let preview = try XCTUnwrap(e.hiringEmployerCost(companyID: id, personID: pid, monthlyWage: wage, terms: terms), "\(code) \(name)")
                XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: wage, terms: terms), .ok, "\(code) \(name)")
                let co = try XCTUnwrap(e.state.company(id))
                let booked = e.employerCost(companyID: id, personID: pid)
                XCTAssertEqual(booked?.totalMonthly ?? -1, preview.totalMonthly, accuracy: 0.5, "\(code) \(name): preview equals profile")
                // Payroll's weekly accrual of this one person equals the breakdown (without benefits).
                var solo = co
                solo.staff = co.staff.filter { $0.id == pid }
                solo.managerID = nil
                let weekly = Payroll.weeklyCost(solo, country: try XCTUnwrap(e.data.countries[code]), skipOffSeason: false)
                XCTAssertEqual(weekly * 52 / 12, (booked?.totalMonthly ?? 0) - (booked?.benefits ?? 0), accuracy: 0.5, "\(code) \(name): payroll books the previewed cost")
                XCTAssertEqual(preview.totalAnnual, preview.totalMonthly * 12, accuracy: 0.001)
                if LabourRules(country: try XCTUnwrap(e.data.countries[code])).leaveWeeks > 0 { XCTAssertGreaterThan(preview.paidLeaveCover, 0, "\(code): paid-leave cover is part of the number") }
                if name != "full" { XCTAssertLessThan(preview.workingPercentage, 1, "\(code) \(name)") }
            }
            let m = try XCTUnwrap(e.teamMetrics(companyID: id))
            XCTAssertEqual(m.workers, (e.state.company(id)?.staff.count ?? 0) + (e.state.company(id)?.managerID == nil ? 0 : 1))
            XCTAssertGreaterThan(m.averageHourlyRate, 0)
            XCTAssertEqual(m.totalMonthlyCost, e.companyEmployerCost(companyID: id)?.totalMonthly ?? -1, accuracy: 0.5)
        }
    }
}
