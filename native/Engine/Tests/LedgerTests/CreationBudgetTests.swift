import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

final class CreationBudgetTests: XCTestCase {
    private func game(_ code: String = "UK", seed: Int = 7, extra: Double = 0) throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: code, playerName: "T", seed: seed)
        if extra > 0 { e.update { s, _, _ in Ledger.move(&s, .me, extra, why: "Test funds") } }
        return e
    }

    func testPlanGroupsMandatoryOptionalAndWorkingCapitalAndShowsRemainingCash() throws {
        let e = try game(extra: 500_000_000)
        let city = e.state.player.cityID
        let plan = try XCTUnwrap(e.newCompanyPlan(tradeID: "cafe", cityID: city, size: 1))
        XCTAssertFalse(plan.lines.isEmpty)
        XCTAssertGreaterThan(plan.mandatoryTotal, 0)
        XCTAssertGreaterThan(plan.workingCapital, 0)
        XCTAssertFalse(plan.lines.contains { $0.id == "optEq" })
        let full = try XCTUnwrap(e.newCompanyPlan(tradeID: "cafe", cityID: city, size: 1, choices: SetupChoices(stock: .full, optionalEquipment: true, team: .standard)))
        XCTAssertGreaterThanOrEqual(full.neededNow, plan.neededNow)
        let none = try XCTUnwrap(e.newCompanyPlan(tradeID: "cafe", cityID: city, size: 1, choices: SetupChoices(stock: .none)))
        XCTAssertFalse(none.lines.contains { $0.id == "stock" })
        XCTAssertLessThanOrEqual(none.neededNow, plan.neededNow)
        XCTAssertEqual(plan.accountsAfter, max(0, plan.available - plan.registrationAndCapital - plan.intoCompany), accuracy: 0.5)
        XCTAssertGreaterThan(plan.personalReserve, 0)
    }

    func testRichPlayerKeepsReserveAndPoorPlayerIsOfferedAlternatives() throws {
        let rich = try game(extra: 2_000_000_000)
        let city = rich.state.player.cityID
        let p1 = try XCTUnwrap(rich.newCompanyPlan(tradeID: "restaurant", cityID: city, size: 2))
        XCTAssertTrue(p1.keepsReserve)
        XCTAssertTrue(p1.alternatives.isEmpty)
        let poor = try game()
        let p2 = try XCTUnwrap(poor.newCompanyPlan(tradeID: "restaurant", cityID: poor.state.player.cityID, size: 2, choices: SetupChoices(stock: .full, optionalEquipment: true, team: .standard)))
        XCTAssertGreaterThan(p2.shortfall, 0)
        XCTAssertFalse(p2.alternatives.isEmpty)
        XCTAssertTrue(p2.alternatives.allSatisfy { $0.saving > 0 })
        XCTAssertLessThanOrEqual(p2.intoCompany, max(0, p2.available - p2.registrationAndCapital - p2.personalReserve) + 1)
    }

    func testOptionalEquipmentStockAndExtraStaffAreNotBoughtUnlessChosen() throws {
        var e = try game(extra: 800_000_000)
        let city = e.state.player.cityID
        let plan = try XCTUnwrap(e.newCompanyPlan(tradeID: "cons", cityID: city, size: 1))
        guard case .success(let out) = e.startCompanyChoosingPremises(tradeID: "cons", cityID: city, size: 1, name: nil, pick: nil, choices: SetupChoices(stock: .none)) else { return XCTFail("start") }
        let co = try XCTUnwrap(e.state.company(out.companyID))
        let bd = try XCTUnwrap(e.data.catalog["cons"])
        XCTAssertTrue(co.staff.isEmpty, "nothing is hired for the player (owner decision, 2 Nov)")
        for item in bd.equipment { XCTAssertEqual(co.value("eq")[item.id]["n"].double, 0, "\(item.id) was not bought") }
        XCTAssertTrue(out.skipped.isEmpty, "nothing is bought or hired, so nothing is left out")
        XCTAssertEqual(OpeningChecklist.openingStockShare(co), 0)
    }

    func testOpeningStockFollowsTheChosenShare() throws {
        var e = try game(extra: 800_000_000)
        let city = e.state.player.cityID
        var paid: [SetupChoices.Stock: Double] = [:]
        for choice in SetupChoices.Stock.allCases {
            guard case .success(let out) = e.startCompanyChoosingPremises(tradeID: "grocery", cityID: city, size: 1, name: nil, pick: nil, choices: SetupChoices(stock: choice)) else { return XCTFail("start") }
            let id = out.companyID
            e.update { s, d, _ in
                guard let i = s.companyIndex(id) else { return }
                _ = CompanySetup.quickSetup(&s, companyID: id, data: d)
                for k in s.companies[i].value("docs").object.keys { var docs = s.companies[i].value("docs"); docs[k]["st"] = "ok"; s.companies[i].set("docs", docs) }
                _ = OpeningChecklist.open(&s, companyIndex: i, data: d)
                paid[choice] = s.companies[i].inventory
            }
        }
        XCTAssertEqual(paid[.none] ?? -1, 0, accuracy: 0.5)
        XCTAssertGreaterThan(paid[.full] ?? 0, 0)
        XCTAssertEqual(paid[.half] ?? 0, (paid[.full] ?? 0) * 0.5, accuracy: (paid[.full] ?? 0) * 0.02 + 1)
    }

    func testBudgetedHiringNeverBuysWagesTheCashCannotCarry() throws {
        var e = try game(extra: 200_000_000)
        let city = e.state.player.cityID
        guard case .success(let out) = e.startCompanyChoosingPremises(tradeID: "restaurant", cityID: city, size: 1, name: nil, pick: nil, choices: SetupChoices(team: .standard)) else { return XCTFail("start") }
        let co = try XCTUnwrap(e.state.company(out.companyID))
        let payroll = co.staff.reduce(0.0) { $0 + $1.monthlyWage }
        XCTAssertLessThanOrEqual(payroll * 2, max(co.cash + payroll * 2, 1) * 1.0 + 1)
        XCTAssertTrue(co.staff.isEmpty, "nobody is hired for the player")
        var legacy = try game(extra: 200_000_000)
        guard case .success(let lid) = legacy.startCompany(tradeID: "restaurant", cityID: city, size: 1) else { return XCTFail("start legacy") }
        let legacyPayroll = legacy.state.company(lid)!.staff.reduce(0.0) { $0 + $1.monthlyWage }
        XCTAssertGreaterThanOrEqual(legacyPayroll, payroll)
    }

    struct Cell { var accountNegative = false, companyNegative = false, companyBust = false, gameOver = false, started = false, hired = 0 }

    private func run(code: String, trade: String, budgeted: Bool, days: Int) throws -> Cell {
        var e = try GameEngine.newGame(countryCode: code, playerName: "T", seed: 11)
        let city = e.state.player.cityID
        guard let bd = e.data.catalog[trade] else { return Cell() }
        let country = e.homeCountry
        let c = country.cities.first { $0.id == city } ?? country.cities[0]
        let size = CompanySetup.recommendedSize(bd, city: c)
        guard SpecialFamilies.isStartable(bd), CompanySetup.banReason(trade, country: country) == nil,
              let plan = e.newCompanyPlan(tradeID: trade, cityID: city, size: size, withAlternatives: false), plan.registrationShortfall <= 0 else { return Cell() }
        var cell = Cell()
        var id = 0
        if budgeted {
            guard case .success(let out) = e.startCompanyChoosingPremises(tradeID: trade, cityID: city, size: size, name: nil, pick: nil) else { return Cell() }
            id = out.companyID
        } else {
            let into = max(0, min(plan.total * 1.15, plan.available - plan.registrationAndCapital))
            guard case .success(let i) = e.startCompany(tradeID: trade, cityID: city, size: size) else { return Cell() }
            id = i
        }
        cell.started = true
        cell.hired = e.state.company(id)?.staff.count ?? 0
        for _ in 0..<days {
            _ = e.nextDay()
            if e.state.cash < 0 || e.state.cash < -1 { cell.accountNegative = true }
            if let co = e.state.company(id) {
                if co.cash < -1 { cell.companyNegative = true }
                if co.status == .bust { cell.companyBust = true }
            }
            if e.state.isGameOver { cell.gameOver = true; break }
        }
        return cell
    }

    func testSetupMatrixBudgetedStartsDoNotEndInUnchosenNegatives() throws {
        let all = ProcessInfo.processInfo.environment["LEDGER_PROBE_ALL"] == "1"
        let e0 = try game()
        let trades = all ? e0.data.catalog.all.map { $0.id } : ["cons", "cafe", "restaurant", "gym", "airline", "taxi", "bakery", "law", "kiosk", "construction"]
        let codes = all ? e0.data.countries.countries.map { $0.code } : ["UK", "US"]
        var legacy = [String: Int](), careful = [String: Int](), n = 0
        for code in codes {
            for t in trades {
                let a = try run(code: code, trade: t, budgeted: false, days: 42)
                let b = try run(code: code, trade: t, budgeted: true, days: 42)
                guard a.started || b.started else { continue }
                n += 1
                for (k, v) in [("account", a.accountNegative), ("company", a.companyNegative), ("bust", a.companyBust), ("over", a.gameOver)] where v { legacy[k, default: 0] += 1 }
                for (k, v) in [("account", b.accountNegative), ("company", b.companyNegative), ("bust", b.companyBust), ("over", b.gameOver)] where v { careful[k, default: 0] += 1 }
            }
        }
        print("PROBE cells=\(n) legacy=\(legacy.sorted { $0.key < $1.key }) budgeted=\(careful.sorted { $0.key < $1.key })")
        XCTAssertGreaterThan(n, 0)
        XCTAssertLessThanOrEqual(careful["account", default: 0], legacy["account", default: 0])
        XCTAssertLessThanOrEqual(careful["company", default: 0], legacy["company", default: 0])
        XCTAssertLessThanOrEqual(careful["bust", default: 0] + careful["over", default: 0], legacy["bust", default: 0] + legacy["over", default: 0])
    }
}
