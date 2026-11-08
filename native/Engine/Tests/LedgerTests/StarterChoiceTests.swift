import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

/// A new company chooses its first product from three starters, sells only that one, and finds the rest under add-item.
final class StarterChoiceTests: XCTestCase {
    private func pending(_ trade: String) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 90_000_000, why: "Test funds") }
        guard case .success(let out) = e.startCompanyChoosingPremises(tradeID: trade, cityID: e.state.player.cityID, form: .limited, size: 1, name: nil, pick: nil, fundWith: 20_000_000) else { throw XCTSkip("could not start") }
        e.update { s, _, _ in let i = s.companyIndex(out.companyID)!; s.companies[i].status = .open }
        return (e, out.companyID)
    }

    func testChoiceIsExactlyThreeForMultiItemTrades() throws {
        for trade in ["cafe", "bakery", "kiosk"] {
            let (e, id) = try pending(trade)
            let choices = e.firstItemChoices(companyID: id)
            XCTAssertEqual(choices.count, 3, trade)
            let wanted = (e.data.catalog[trade]?.raw["starters"].array.map(\.string)) ?? []
            XCTAssertEqual(wanted.count, 3, trade)
            XCTAssertEqual(Set(choices.map { SalesItems.localID($0.id) }), Set(wanted), trade)
        }
    }

    func testOnlyTheChosenProductSellsAndTheRestAreAddable() throws {
        for trade in ["cafe", "bakery", "kiosk"] {
            var (e, id) = try pending(trade)
            let choices = e.firstItemChoices(companyID: id)
            let sold = choices[1]
            XCTAssertEqual(e.chooseFirstItem(companyID: id, itemID: sold.id), .applied, trade)
            XCTAssertEqual(e.salesItems(companyID: id).map(\.id), [sold.id], trade)
            var names = Set(e.newItemOptions(companyID: id, isService: false).options.map { $0.name.lowercased() })
            names.formUnion(e.retailAddableItems(companyID: id).map { $0.name.lowercased() })
            for other in choices where other.id != sold.id { XCTAssertTrue(names.contains(other.name.lowercased()), "\(trade): \(other.name) can be added later") }
            XCTAssertFalse(names.contains(sold.name.lowercased()), "\(trade): the item already sold is not offered")
        }
    }

    func testAnUnchosenStarterCanBeAdded() throws {
        var (e, id) = try pending("cafe")
        let choices = e.firstItemChoices(companyID: id)
        XCTAssertEqual(e.chooseFirstItem(companyID: id, itemID: choices[0].id), .applied)
        let o = try XCTUnwrap(e.newItemOptions(companyID: id, isService: false).options.first { $0.name == choices[1].name })
        XCTAssertEqual(e.addNewItem(companyID: id, optionID: o.id), .applied)
        XCTAssertTrue(e.salesItems(companyID: id).contains { $0.name == choices[1].name })
    }

    func testAChoiceOutsideTheThreeIsRefused() throws {
        var (e, id) = try pending("cafe")
        XCTAssertEqual(e.chooseFirstItem(companyID: id, itemID: "w3-nothing"), .refused("That choice is not on offer."))
    }

    func testSandboxIsLockedForFreePlayers() {
        XCTAssertFalse(EntitlementSnapshot.free.isUnlocked(.sandboxMode, now: Date()))
        XCTAssertTrue(EntitlementSnapshot(owned: [.pro]).isUnlocked(.sandboxMode, now: Date()))
        XCTAssertThrowsError(try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7, difficulty: .sandbox))
    }
}
