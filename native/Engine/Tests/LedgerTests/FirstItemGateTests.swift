import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

final class FirstItemGateTests: XCTestCase {
    private func pendingCompany(_ trade: String) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 90_000_000, why: "Test funds") }
        guard case .success(let out) = e.startCompanyChoosingPremises(tradeID: trade, cityID: e.state.player.cityID, size: 1, name: nil, pick: nil, fundWith: 20_000_000) else { throw XCTSkip("could not start") }
        e.update { s, _, _ in let i = s.companyIndex(out.companyID)!; s.companies[i].status = .open }
        return (e, out.companyID)
    }

    private func context() -> CompanyWeek.WeekContext {
        CompanyWeek.WeekContext(units: 5, rev: 100, cogs: 20, D: 5, cap: 10, util: 0.5, price: 20, paidDuringWeek: 0)
    }

    func testGateZeroesSalesOfSelfModelledWeeks() throws {
        var ran = 0
        for trade in ["estate", "realdev"] {
            guard let made = try? pendingCompany(trade) else { continue }
            ran += 1
            let co = try XCTUnwrap(made.0.state.company(made.1))
            XCTAssertTrue(SalesItems.firstChoicePending(co), trade)
            var ctx = context()
            SalesItems.gate(&ctx, co)
            XCTAssertEqual(ctx.rev, 0, trade)
            XCTAssertEqual(ctx.units, 0, trade)
            XCTAssertEqual(ctx.D, 0, trade)
            XCTAssertEqual(ctx.cogs, 20, "costs are not gated")
            var settled = co
            settled.set(SalesItems.pickKey, .object(["p": .bool(false), "hide": .array([])]))
            var open = context()
            SalesItems.gate(&open, settled)
            XCTAssertEqual(open.rev, 100, "nothing is gated once the choice is made")
        }
        if ran == 0 { throw XCTSkip("no rental or developer trade could be started") }
    }

    func testPendingRentalCompanyBooksNoSales() throws {
        var (e, id) = try pendingCompany("estate")
        for _ in 0..<7 { _ = e.nextDay() }
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).lastWeekRevenue, 0, accuracy: 1e-9)
    }

    func testLateStartersStayHiddenUnlessChosen() throws {
        var (e, id) = try pendingCompany("bakery")
        let pick = try XCTUnwrap(e.firstItemChoices(companyID: id).first)
        XCTAssertEqual(e.chooseFirstItem(companyID: id, itemID: pick.id), .applied)
        func add(_ itemID: String) {
            e.update { s, _, _ in
                let i = s.companyIndex(id)!
                let it = SalesItems.Item(id: itemID, name: itemID, isService: false, unitShare: 0.2, ratio: 1, priceMultiplier: 1, discountPercent: 0, discountWeeks: 0, listedForGroup: false)
                s.companies[i].set(SalesItems.key, .array(s.companies[i].value(SalesItems.key).array + [SalesItems.encode(it)]))
            }
        }
        add("w9x:7"); add("n5"); add("w8u:p77")
        let co = try XCTUnwrap(e.state.company(id))
        let hidden = SalesItems.hiddenIDs(co)
        XCTAssertTrue(hidden.contains("w9x:7"), "a starter a module adds later is hidden")
        XCTAssertFalse(hidden.contains("n5"), "the owner's own item is shown")
        XCTAssertFalse(hidden.contains("w8u:p77"), "a rental unit follows an asset the owner bought")
        XCTAssertFalse(hidden.contains(pick.id))
        let list = SalesItems.items(co, e.data.catalog[co.type]!)
        XCTAssertEqual(list.first { $0.id == "w9x:7" }?.unitShare ?? -1, 0, accuracy: 1e-12, "it carries no customers")
        XCTAssertFalse(e.salesItems(companyID: id).contains { $0.id == "w9x:7" })
    }

    func testSingleChosenProductStaysWithinASaneRangeOfTheFullRange() throws {
        let (e, id) = try pendingCompany("bakery")
        let starters = e.firstItemChoices(companyID: id)
        XCTAssertGreaterThanOrEqual(starters.count, 2)
        let i = try XCTUnwrap(e.state.companyIndex(id))
        let bd = try XCTUnwrap(e.data.catalog[e.state.companies[i].type])
        var full = e.state
        SalesItems.seedStarters(&full, i, data: e.data)
        full.companies[i].set(SalesItems.pickKey, .null)
        let fullCustomers = DemandModel.compute(full.companies[i], bd, World(state: full, data: e.data)).customers
        XCTAssertGreaterThan(fullCustomers, 0)
        XCTAssertEqual(SalesItems.ticketFactor(full.companies[i]), 1, accuracy: 1e-9)
        for st in starters {
            var one = e
            XCTAssertEqual(one.chooseFirstItem(companyID: id, itemID: st.id), .applied)
            let co = try XCTUnwrap(one.state.company(id))
            let customers = DemandModel.compute(co, bd, World(state: one.state, data: one.data)).customers
            let potential = customers * SalesItems.ticketFactor(co)
            XCTAssertGreaterThan(customers, 0, st.name)
            XCTAssertLessThanOrEqual(customers, fullCustomers * 1.0001, "\(st.name): one product must not draw more customers than the full range")
            XCTAssertGreaterThanOrEqual(customers, fullCustomers * 0.25 - 1e-9, "\(st.name): customers \(customers) of \(fullCustomers)")
            XCTAssertLessThanOrEqual(potential, fullCustomers * 2, "\(st.name): sales potential \(potential) against \(fullCustomers) for the full range")
            XCTAssertGreaterThanOrEqual(potential, fullCustomers * 0.1, "\(st.name): sales potential \(potential) against \(fullCustomers)")
        }
    }

    func testRangeFactorIsOneWithNothingHidden() throws {
        let (e, id) = try pendingCompany("bakery")
        XCTAssertEqual(SalesItems.rangeFactor(try XCTUnwrap(e.state.company(id))), 1)
        var one = e
        let pick = try XCTUnwrap(one.firstItemChoices(companyID: id).first)
        XCTAssertEqual(one.chooseFirstItem(companyID: id, itemID: pick.id), .applied)
        let f = SalesItems.rangeFactor(try XCTUnwrap(one.state.company(id)))
        XCTAssertLessThan(f, 1)
        XCTAssertGreaterThanOrEqual(f, 0.25)
    }
}
