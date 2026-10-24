import XCTest
import GameCore
import Finance
import Simulation
@testable import Businesses

/// Buying an input from one of your business customers (original `ch39set`, `ch39off` and their weekly step).
final class AccountSupplyTests: XCTestCase {
    /// Two open cafes in the player's city: `buyer` and `owner` (the company whose key account will supply the buyer).
    private func twoCafes() throws -> (GameEngine, Int, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4242)
        var ids: [Int] = []
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 160_000_000, why: "Test funds")
            for _ in 0..<2 {
                guard case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, form: .limited, data: data, context: ctx) else { continue }
                let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
                _ = Payments.injectCash(&s, companyID: i, amount: (est?.total ?? 1_000_000) * 1.6 + 3_000_000)
                _ = CompanySetup.quickSetup(&s, companyID: i, data: data)
                ids.append(i)
            }
        }
        XCTAssertEqual(ids.count, 2)
        for _ in 0..<(8 * 7) { e.nextDay() }
        return (e, ids[0], ids[1])
    }

    func testSupplyFromABusinessCustomerSavesMoneyAndWarmsTheRelationship() throws {
        var (e, buyer, owner) = try twoCafes()
        XCTAssertEqual(e.state.company(buyer)?.status, .open)
        XCTAssertEqual(e.state.company(owner)?.status, .open)
        e.update { s, _, _ in
            let o = s.companyIndex(owner)!
            s.companies[o].set("accts", .array([
                .object(["id": 9001, "name": "Bright Cleaners", "f": 0.1, "rel": 40, "w0": .number(Double(s.week)), "disc": 0, "t": "cleaning"]),
                .object(["id": 9002, "name": "Stranger Cleaners", "f": 0.1, "rel": 10, "w0": .number(Double(s.week)), "disc": 0, "t": "cleaning"]),
            ]))
            let b = s.companyIndex(buyer)!
            s.companies[b].set("lastW", .object(["rev": 100_000]))
        }
        let cands = e.accountSupplyCandidates(buyer: buyer, kind: "clean")
        let good = try XCTUnwrap(cands.first { $0.accountID == 9001 })
        let stranger = try XCTUnwrap(cands.first { $0.accountID == 9002 })
        XCTAssertTrue(good.canBuy)
        XCTAssertFalse(stranger.canBuy, "only familiar or closer contacts sell to you")
        XCTAssertEqual(good.priceFactor, 0.95, accuracy: 1e-9, "2% below outside plus 3% for a relationship of 40")
        XCTAssertEqual(good.ownerCompanyID, owner)

        XCTAssertEqual(e.buyFromAccount(buyer: buyer, kind: "clean", accountID: 9002), .notKnownWell)
        XCTAssertEqual(e.buyFromAccount(buyer: buyer, kind: "clean", accountID: 12345), .unknownAccount)
        XCTAssertNil(e.accountSupplyLink(buyer: buyer, kind: "clean"))
        XCTAssertEqual(e.buyFromAccount(buyer: buyer, kind: "clean", accountID: 9001), .ok)
        XCTAssertEqual(e.accountSupplyLink(buyer: buyer, kind: "clean")?.accountID, 9001)

        let cash0 = try XCTUnwrap(e.state.company(buyer)).cash
        let rel0 = 40.0
        e.update { s, _, _ in AccountSupply.weekly(&s) }
        // 100 000 sales a week x 1.2% spent on cleaning x 5% below the outside price
        XCTAssertEqual(try XCTUnwrap(e.state.company(buyer)).cash - cash0, 60, accuracy: 1.01)
        XCTAssertEqual(try XCTUnwrap(e.accountSupplyLink(buyer: buyer, kind: "clean")).savedSoFar, 60, accuracy: 0.01)
        let rel1 = try XCTUnwrap(KeyAccounts.accounts(try XCTUnwrap(e.state.company(owner))).first { $0.id == 9001 }).relationship
        XCTAssertGreaterThan(rel1, rel0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")

        e.stopBuyingFromAccount(buyer: buyer, kind: "clean")
        XCTAssertNil(e.accountSupplyLink(buyer: buyer, kind: "clean"))
    }

    func testTheLinkEndsWhenTheAccountLeavesAndAnOwnSupplierReplacesIt() throws {
        var (e, buyer, owner) = try twoCafes()
        e.update { s, _, _ in
            let o = s.companyIndex(owner)!
            s.companies[o].set("accts", .array([.object(["id": 9001, "name": "Bright Cleaners", "f": 0.1, "rel": 40, "w0": .number(Double(s.week)), "disc": 0, "t": "cleaning"])]))
            let b = s.companyIndex(buyer)!
            s.companies[b].set("lastW", .object(["rev": 100_000]))
        }
        XCTAssertEqual(e.buyFromAccount(buyer: buyer, kind: "clean", accountID: 9001), .ok)
        // the account is gone: the buyer goes back to outside suppliers and hears about it
        let mails = e.state.inbox.count
        e.dropAccount(companyID: owner, accountID: 9001)
        e.update { s, _, _ in AccountSupply.weekly(&s) }
        XCTAssertNil(e.accountSupplyLink(buyer: buyer, kind: "clean"))
        XCTAssertGreaterThan(e.state.inbox.count, mails)

        // an own-company supplier for the same input ends a deal with a business customer
        e.update { s, _, _ in
            let o = s.companyIndex(owner)!
            s.companies[o].set("accts", .array([.object(["id": 9003, "name": "Bright Cleaners", "f": 0.1, "rel": 40, "w0": .number(Double(s.week)), "disc": 0, "t": "cleaning"])]))
        }
        XCTAssertEqual(e.buyFromAccount(buyer: buyer, kind: "clean", accountID: 9003), .ok)
        e.update { s, _, _ in
            // owner stands in as a cleaning company for this check
            let o = s.companyIndex(owner)!
            s.companies[o].type = "cleaning"
        }
        XCTAssertTrue(e.setSupplier(buyer: buyer, kind: "clean", supplier: owner, mode: "mkt"))
        XCTAssertNil(e.accountSupplyLink(buyer: buyer, kind: "clean"), "a new own supplier ends the deal with the business customer")
        XCTAssertNotNil(e.supplyLink(buyer: buyer, kind: "clean"))
    }
}
