import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

private extension GameEngine {
    mutating func week() { for _ in 0..<7 { _ = nextDay() } }
}

final class NewItemOptionsTests: XCTestCase {
    func engine(_ trade: String = "bakery", weeks: Int = 3) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 200_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: .limited, fundWith: 100_000_000) else { throw XCTSkip("could not start") }
        for _ in 0..<weeks { e.week() }
        return (e, id)
    }

    /// Gives the company a market advisor through the duty route (any employee).
    func giveAdvisorDuty(_ e: inout GameEngine, _ id: Int) throws {
        e.update { s, _, _ in
            guard let i = s.companyIndex(id), !s.companies[i].staff.isEmpty else { return }
            s.companies[i].staff[0].set("duty", NewItemOptions.advisorRole)
        }
        guard e.hasMarketAdvisor(companyID: id) else { throw XCTSkip("no staff to give the duty") }
    }

    func testOptionsAreCompanySpecificAndStable() throws {
        let (e, id) = try engine()
        let first = e.state.company(id)!.name.split(separator: " ").first.map(String.init)!
        let l = e.newItemOptions(companyID: id, isService: false)
        XCTAssertTrue((4...6).contains(l.options.count))
        XCTAssertTrue(l.options.allSatisfy { !$0.isService })
        XCTAssertLessThanOrEqual(l.options.filter { $0.name.hasPrefix(first) }.count, 1, "the company name is a brand prefix on the signature item only")
        let present = Set(e.salesItems(companyID: id).map { $0.name.lowercased() })
        XCTAssertTrue(l.options.allSatisfy { !present.contains($0.name.lowercased()) })
        XCTAssertEqual(Set(l.options.map { $0.id }).count, l.options.count)
        XCTAssertEqual(l, e.newItemOptions(companyID: id, isService: false))
    }

    func testEveryTradeHasARealisticCatalog() throws {
        let (e, _) = try engine()
        let ids = e.data.catalog.order
        XCTAssertGreaterThanOrEqual(ids.count, 60)
        for id in ids {
            let rows = NewItemOptions.catalog[id] ?? []
            // the item trade groups replaced the add-item list of their trades with the real products they sell (4 or more); the others keep the wide generic list
            let minimum = ItemTradeGroups.all.contains(id) ? 4 : 6
            XCTAssertGreaterThanOrEqual(rows.count, minimum, "\(id) needs at least \(minimum) options")
            XCTAssertEqual(Set(rows.map { $0.name.lowercased() }).count, rows.count, "\(id) has duplicate names")
            XCTAssertLessThanOrEqual(rows.filter { $0.brand }.count, 1, "\(id): at most one branded item")
            XCTAssertTrue(rows.allSatisfy { !$0.name.isEmpty })
        }
        XCTAssertTrue(NewItemOptions.catalog["tutor"]!.contains { $0.name == "Exam preparation course" })
        XCTAssertTrue(NewItemOptions.catalog["carrental"]!.contains { $0.name == "Chauffeur service" })
        XCTAssertTrue(NewItemOptions.catalog["hotel"]!.contains { $0.name == "Spa weekend" })
    }

    func testNumbersNeedAnAdvisor() throws {
        var (e, id) = try engine()
        var l = e.newItemOptions(companyID: id, isService: false)
        XCTAssertFalse(l.hasMarketAdvisor)
        XCTAssertTrue(l.options.allSatisfy { $0.profitChange == nil && $0.marketChange == nil })
        XCTAssertFalse(e.hasMarketAdvisor(companyID: id))
        try giveAdvisorDuty(&e, id)
        l = e.newItemOptions(companyID: id, isService: false)
        XCTAssertTrue(l.hasMarketAdvisor)
        XCTAssertTrue(l.options.allSatisfy { ($0.profitChange ?? -1) >= 0 && $0.marketChange != nil })
    }

    func testAdvisorIsInTheRoleCatalog() throws {
        let (e, id) = try engine()
        XCTAssertTrue(e.recommendedRoles(companyID: id).contains { $0.id == "advisor" && !$0.filled })
    }

    func testVariantIsAddedAtOnce() throws {
        var (e, id) = try engine()
        let o = e.newItemOptions(companyID: id, isService: false).options[0]
        XCTAssertFalse(o.needsDevelopment)
        let cash = e.state.company(id)!.cash
        XCTAssertEqual(e.addNewItem(companyID: id, optionID: o.id), .applied)
        XCTAssertTrue(e.salesItems(companyID: id).contains { $0.name == o.name })
        XCTAssertEqual(e.state.company(id)!.cash, cash)
        XCTAssertFalse(e.newItemOptions(companyID: id, isService: false).options.contains { $0.name == o.name })
    }

    func testNewCategoryIsDevelopedThenAdded() throws {
        var (e, id) = try engine()
        let o = e.newItemOptions(companyID: id, isService: true).options[0]
        XCTAssertTrue(o.needsDevelopment)
        XCTAssertGreaterThan(o.developmentWeeks, 0)
        XCTAssertGreaterThan(o.developmentCost, 0)
        let before = e.salesItems(companyID: id).count
        let cash = e.state.company(id)!.cash
        XCTAssertEqual(e.addNewItem(companyID: id, optionID: o.id), .applied)
        XCTAssertEqual(e.salesItems(companyID: id).count, before)
        XCTAssertNotNil(Development.running(e.state.company(id)!))
        XCTAssertLessThan(e.state.company(id)!.cash, cash)
        // a second project is refused while this one runs
        let second = e.newItemOptions(companyID: id, isService: true).options[1].id
        if case .refused = e.addNewItem(companyID: id, optionID: second) {} else { XCTFail("second project should be refused") }
        for _ in 0..<(o.developmentWeeks + 2) { e.week() }
        XCTAssertNil(Development.running(e.state.company(id)!))
        let item = e.salesItems(companyID: id).first { $0.name == o.name }
        XCTAssertNotNil(item)
        XCTAssertTrue(item?.isService ?? false)
    }

    func testSaveReloadAndDeterminism() throws {
        var (a, id) = try engine()
        var b = a
        let o = a.newItemOptions(companyID: id, isService: true).options[0]
        a.addNewItem(companyID: id, optionID: o.id)
        b.addNewItem(companyID: id, optionID: o.id)
        let loaded = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(a.state))
        XCTAssertTrue(loaded == a.state)
        let (data, events, marketing) = try GameEngine.loadResources()
        var c = GameEngine(state: loaded, data: data, events: events, marketing: marketing)
        for _ in 0..<(o.developmentWeeks + 2) { a.week(); b.week(); c.week() }
        XCTAssertTrue(a.state == b.state)
        XCTAssertTrue(a.state == c.state)
        XCTAssertTrue(c.salesItems(companyID: id).contains { $0.name == o.name })
    }
}
