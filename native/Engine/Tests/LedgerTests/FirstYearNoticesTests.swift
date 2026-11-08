import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Events
import Simulation

/// The first-year honeymoon follows each company's own age, and every protection that ends says so in the Inbox.
final class FirstYearNoticesTests: XCTestCase {
    func testDemandRampFollowsTheCompanysAgeNotTheGameWeek() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        e.update { s, _, _ in
            s.week = 150
            if let i = s.companyIndex(id) { s.companies[i].status = .open; s.companies[i].openedWeek = 150 }
        }
        func firstYearPart() throws -> Double? {
            let w = World(state: e.state, data: e.data)
            let co = try XCTUnwrap(e.state.company(id))
            let bd = try XCTUnwrap(e.data.catalog[co.type])
            return DemandModel.compute(co, bd, w).parts.first { $0.name == "firstYear" }?.value
        }
        XCTAssertEqual(try firstYearPart(), 1.25, "a company opened in year 3 gets its own honeymoon")
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].openedWeek = 150 - 20 } }
        XCTAssertEqual(try firstYearPart(), 1.15)
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].openedWeek = 150 - 60 } }
        XCTAssertNil(try firstYearPart(), "after the first year the ramp is gone")
    }

    func testEachProtectionEndsWithOneInboxNotice() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        func titles() -> [String] { e.state.inbox.map { $0.title } }
        e.update { s, d, _ in
            s.rest["ldr"] = .object([:])
            s.week = 11; FirstYear.noticeSweep(&s, balance: d.balance)
        }
        XCTAssertFalse(titles().contains("Overdraft protection has ended"))
        e.update { s, d, _ in
            s.week = 12; FirstYear.noticeSweep(&s, balance: d.balance); FirstYear.noticeSweep(&s, balance: d.balance)
        }
        XCTAssertEqual(titles().filter { $0 == "Overdraft protection has ended" }.count, 1)
        e.update { s, d, _ in s.week = 27; FirstYear.noticeSweep(&s, balance: d.balance); FirstYear.noticeSweep(&s, balance: d.balance) }
        XCTAssertEqual(titles().filter { $0 == "The first-year safety nets are off" }.count, 1)
        e.update { s, d, _ in
            if let i = s.companyIndex(id) { s.companies[i].status = .open; s.companies[i].openedWeek = 0 }
            s.week = 52; FirstYear.noticeSweep(&s, balance: d.balance); FirstYear.noticeSweep(&s, balance: d.balance)
        }
        XCTAssertEqual(e.state.inbox.filter { $0.title.hasSuffix("has finished its first year") }.count, 1)
    }

    func testALaterCompanyGetsItsOwnAnniversaryNotice() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        e.update { s, d, _ in
            s.week = 200
            if let i = s.companyIndex(id) { s.companies[i].status = .open; s.companies[i].openedWeek = 148 }
            FirstYear.noticeSweep(&s, balance: d.balance)
        }
        let item = e.state.inbox.first { $0.title.hasSuffix("has finished its first year") }
        XCTAssertEqual(item?.companyID, id)
        XCTAssertFalse(e.state.inbox.contains { $0.title == "The first-year safety nets are off" }, "game-wide notices do not fire late")
    }

    func testEveryEventWithOptionsOffersAChoice() throws {
        let lib = try EventLibrary.bundled()
        for ev in lib.events.values where !ev.options.isEmpty {
            XCTAssertGreaterThanOrEqual(ev.options.count, 2, "\(ev.id): a decision needs a real trade-off")
        }
        for ev in lib.events.values where ev.options.isEmpty {
            XCTAssertTrue(ev.automatic || lib.special.contains(ev.id) || ["rival_call", "probe"].contains(ev.id), "\(ev.id): a no-option event is a notice")
        }
    }
}
