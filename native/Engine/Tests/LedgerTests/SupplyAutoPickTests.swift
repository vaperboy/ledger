import XCTest
import GameCore
import Finance
import Simulation
@testable import Businesses

final class SupplyAutoPickTests: XCTestCase {
    private func opened(_ trade: String, seed: Int = 3) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed, story: .fresh, tradeID: trade, chooseFirstItem: true)
        let id = try XCTUnwrap(e.state.companies.first?.id)
        if let choice = e.firstItemChoices(companyID: id).first {
            XCTAssertFalse(e.chooseFirstItem(companyID: id, itemID: choice.id).isRefused, trade)
        }
        return (e, id)
    }

    func testEveryStarterTradeOpensWithStockAndUpkeepSupplied() throws {
        for trade in TradeUnlocks.starterIDs {
            let (e, id) = try opened(trade)
            let co = try XCTUnwrap(e.state.company(id), trade)
            XCTAssertTrue(SupplyAutoPick.applies(co), trade)
            for group in e.supplyLines(companyID: id) where SupplyAutoPick.isAutomatic(group: group.name) {
                for row in group.rows where row.governed == nil && !row.offers.isEmpty {
                    XCTAssertNotNil(row.now, "\(trade): \(row.id) has no supplier")
                }
            }
            for r in ItemModels.records(co) where r.model == .stk || r.model == .made {
                let offers = e.itemPage(companyID: id, itemID: r.id)?.offers ?? []
                if offers.isEmpty { continue }
                let vendor = try XCTUnwrap(r.supplierID, "\(trade): \(r.id) has no supplier")
                XCTAssertTrue(offers.contains { $0.vendorID == vendor }, "\(trade): \(r.id) supplier is not one the player can see")
                XCTAssertEqual(ItemModels.repickWeeksLeft(e.state, companyID: id, itemID: r.id), 0, "\(trade): an automatic pick is free to change")
            }
        }
    }

    func testTheFairestSupplierIsTheMostReliableAtTheUsualPriceOrBelow() {
        func p(_ id: String, tier: Int, rel: Double, slot: Int) -> SupplyPlayers.Supplier {
            SupplyPlayers.Supplier(id: id, name: id, tradeID: "wholesale", owner: "", ownerCode: "", city: "", countryCode: "UK", lineID: "food", tier: tier,
                                   quality: 0, reliability: rel, capacityFactor: 4, load: 0.3, staff: 5, weeksTrading: 50, logoID: "mark", slot: slot)
        }
        let list = [p("std", tier: 1, rel: 0.985, slot: 0), p("cheap", tier: 0, rel: 0.9, slot: 1), p("dear", tier: 2, rel: 0.995, slot: 2), p("usual", tier: 1, rel: 0.96, slot: 3)]
        XCTAssertEqual(SupplyAutoPick.fairest(list)?.id, "std", "dearer suppliers are never picked for the player")
        XCTAssertEqual(SupplyAutoPick.fairest([p("a", tier: 1, rel: 0.95, slot: 2), p("b", tier: 1, rel: 0.95, slot: 1)])?.id, "b", "ties go to the lower slot")
        XCTAssertEqual(SupplyAutoPick.fairest([p("dear", tier: 2, rel: 0.99, slot: 2)])?.id, "dear", "with only dearer ones, the line still gets one")
        XCTAssertNil(SupplyAutoPick.fairest([]))
    }

    func testAnOwnCompanySuppliesTheNewCompanyFirst() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4243)
        var bakery = 0
        var cafe = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 160_000_000, why: "Test funds")
            guard case .success(let b) = CompanySetup.create(&s, tradeID: "bakery", cityID: s.player.cityID, data: data, context: ctx), let bi = s.companyIndex(b) else { return }
            s.companies[bi].status = .open
            bakery = b
            guard case .success(let c) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, data: data, context: ctx) else { return }
            cafe = c
        }
        XCTAssertGreaterThan(bakery, 0)
        XCTAssertGreaterThan(cafe, 0)
        let link = try XCTUnwrap(IntercompanySupply.link(e.state, buyer: cafe, kind: "bread"), "the own bakery should supply the new cafe's bread")
        XCTAssertEqual(link.supplierID, bakery)
        XCTAssertEqual(link.mode, "mkt")
        XCTAssertNil(IntercompanySupply.link(e.state, buyer: cafe, kind: "clean"), "services stay the player's choice")
    }

    func testThePlayerCanStillChangeAnAutomaticPick() throws {
        let (e0, id) = try opened("cafe")
        var e = e0
        guard let row = e.supplyLines(companyID: id).flatMap({ $0.rows }).first(where: { SupplyAutoPick.isAutomatic(group: $0.group) && $0.canSwitch && $0.governed == nil }),
              let other = row.offers.first(where: { !$0.isCurrent && $0.blocked == nil }) else { throw XCTSkip("no other supplier on offer") }
        XCTAssertEqual(e.chooseSupply(companyID: id, change: other.change), .ok)
        let after = try XCTUnwrap(e.supplyLines(companyID: id).flatMap { $0.rows }.first { $0.id == row.id })
        XCTAssertEqual(after.now?.id, other.id)
    }

    func testCompaniesOpenedBeforeTheRuleKeepTheirProducts() throws {
        let (e0, id) = try opened("cafe")
        var e = e0
        e.update { s, data, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].raw["asup"] = nil
            for r in ItemModels.records(s.companies[i]) { ItemModels.setSupplier(&s, companyID: id, itemID: r.id, vendorID: nil) }
            SupplyAutoPick.fillItems(&s, i, data: data)
        }
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertTrue(ItemModels.records(co).allSatisfy { $0.supplierID == nil }, "only companies opened under the rule are filled")
    }
}
