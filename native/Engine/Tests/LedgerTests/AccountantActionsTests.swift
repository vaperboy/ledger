import XCTest
import GameCore
import Finance
import Businesses
import Simulation

/// The player chooses the accountant; the fee follows the choice and payroll responsibility is still derived from it.
final class AccountantActionsTests: XCTestCase {
    private func game(_ seed: Int) throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 300_000_000, why: "Test funds") }
        return e
    }

    func testOffersExistOnlyAfterPrepare() throws {
        var e = try game(11)
        let code = e.state.homeCountryCode
        e.prepareAccountants(countryCode: code)
        let offers = e.accountantOffers(countryCode: code)
        XCTAssertGreaterThan(offers.count, 1)
        XCTAssertEqual(offers.filter { $0.isDefault }.count, 1)
        XCTAssertEqual(offers.filter { $0.isDefault }.first?.id, offers[1].id)
        e.prepareAccountants(countryCode: code)
        XCTAssertEqual(e.accountantOffers(countryCode: code), offers, "preparing twice does not change the pool")
    }

    func testSetAccountantChangesFeeAndPayrollStillDerived() throws {
        var e = try game(12)
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 100_000_000) else { return XCTFail("start") }
        let code = try XCTUnwrap(e.state.company(id)?.countryCode)
        let offers = e.accountantOffers(countryCode: code)
        let current = try XCTUnwrap(e.state.company(id)?.value("acc")["id"].int)
        XCTAssertEqual(current, offers.first { $0.isDefault }?.id)
        let other = try XCTUnwrap(offers.first { $0.id != current && $0.monthlyFee != offers.first { $0.id == current }?.monthlyFee })
        XCTAssertEqual(e.setAccountant(companyID: id, accountantID: other.id), .applied)
        let acc = try XCTUnwrap(e.state.company(id)?.value("acc"))
        XCTAssertEqual(acc["id"].int, other.id)
        XCTAssertEqual(acc["fee"].double, other.monthlyFee, accuracy: 0.001)
        XCTAssertEqual(e.companyOverviewStats(companyID: id)?.accountant, other.name)
        XCTAssertEqual(e.setAccountant(companyID: id, accountantID: other.id), .unchanged)
        XCTAssertTrue(e.setAccountant(companyID: id, accountantID: -5).isRefused)
        XCTAssertTrue(e.setAccountant(companyID: 987_654, accountantID: other.id).isRefused)
        let o = try XCTUnwrap(e.payrollOverview(companyID: id))
        XCTAssertEqual(o.responsibility?.who, .accountant)
        XCTAssertEqual(o.responsibility?.name, other.name)
        XCTAssertEqual(o.mode, .accountant)
        for _ in 0..<35 { _ = e.nextDay() }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testSoleTraderAppointsAccountantAndPayrollFollows() throws {
        var e = try game(13)
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .soleTrader, fundWith: 100_000_000) else { return XCTFail("start") }
        XCTAssertEqual(e.payrollOverview(companyID: id)?.responsibility?.who, .owner)
        let code = try XCTUnwrap(e.state.company(id)?.countryCode)
        e.prepareAccountants(countryCode: code)
        let pick = try XCTUnwrap(e.accountantOffers(countryCode: code).last)
        XCTAssertEqual(e.setAccountant(companyID: id, accountantID: pick.id), .applied)
        XCTAssertEqual(e.payrollOverview(companyID: id)?.responsibility?.who, .accountant)
    }

    func testNewCompanyTakesTheChosenAccountant() throws {
        var e = try game(14)
        let code = e.state.homeCountryCode
        e.prepareAccountants(countryCode: code)
        let pick = try XCTUnwrap(e.accountantOffers(countryCode: code).first { !$0.isDefault })
        let r = e.startCompanyChoosingPremises(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, size: nil, name: nil, pick: nil, fundWith: 100_000_000, accountantID: pick.id)
        guard case .success(let out) = r else { return XCTFail("start") }
        XCTAssertEqual(e.state.company(out.companyID)?.value("acc")["id"].int, pick.id)
    }

    func testConversionTakesTheChosenAccountant() throws {
        var e = try game(15)
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .soleTrader, fundWith: 100_000_000) else { return XCTFail("start") }
        let code = try XCTUnwrap(e.state.company(id)?.countryCode)
        e.prepareAccountants(countryCode: code)
        let pick = try XCTUnwrap(e.accountantOffers(countryCode: code).first { !$0.isDefault })
        XCTAssertEqual(e.convertToLimited(companyID: id, accountantID: pick.id), .ok)
        XCTAssertEqual(e.state.company(id)?.value("acc")["id"].int, pick.id)
    }
}
