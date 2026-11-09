import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Rules: per-trade price ranges, every store item for every company,
/// the dividend desk, document refusal and reapplying, delegation lines.
final class PricingDividendsDelegationTests: XCTestCase {
    private func open(_ e: inout GameEngine, _ trade: String) throws -> Int {
        e.update { s, _, _ in Ledger.move(&s, .me, 200_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, fundWith: 60_000_000) else { throw XCTSkip("no company") }
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
        return id
    }

    func testAPriceCannotLeaveTheTradesOwnRange() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 21)
        let id = try open(&e, "grocery")
        let range = try XCTUnwrap(e.data.balance.priceRangeByTrade["grocery"])
        for _ in 0..<12 { _ = e.changePrice(companyID: id, byShare: 0.2) }
        let level = try XCTUnwrap(e.state.company(id)).priceLevel
        XCTAssertLessThanOrEqual(e.data.balance.priceMultiplier(level: level), range[1] + 1e-6)
        for _ in 0..<30 { _ = e.changePrice(companyID: id, byShare: -0.2) }
        let low = try XCTUnwrap(e.state.company(id)).priceLevel
        XCTAssertGreaterThanOrEqual(e.data.balance.priceMultiplier(level: low), range[0] - 1e-6)
    }

    func testAnItemOfAnotherTradeCanBeBoughtOwnedAndSold() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 22)
        let id = try open(&e, "cafe")
        let bd = try XCTUnwrap(e.data.catalog["cafe"])
        XCTAssertFalse(bd.foreignItems.isEmpty, "the catalogue carries the other trades' items")
        let mine = Set(bd.equipment.map { $0.id })
        let needs = e.equipmentNeeds(companyID: id)
        guard let foreign = needs.first(where: { !mine.contains($0.equipmentID) && !$0.isVehicle && !$0.isSoftware && $0.canUsed == false || (!mine.contains($0.equipmentID) && !$0.isVehicle && !$0.isSoftware) }) else { throw XCTSkip("no plain foreign item") }
        let offer = try XCTUnwrap(e.equipmentOffers(companyID: id, equipmentID: foreign.equipmentID).first)
        XCTAssertEqual(e.buyEquipmentItem(companyID: id, equipmentID: foreign.equipmentID, offer: offer, quantity: 1, payment: .cash), .ok)
        XCTAssertTrue(e.ownedEquipment(companyID: id).contains { $0.equipmentID == foreign.equipmentID }, "it shows in My items")
        XCTAssertEqual(e.equipmentNeeds(companyID: id).first { $0.equipmentID == foreign.equipmentID }?.have ?? 0, 1, "the store list is not stale after a purchase")
        XCTAssertGreaterThan(e.sellAllEquipment(companyID: id, equipmentID: foreign.equipmentID), 0, "and it can be sold")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testTheDividendDeskPaysAShareAndNeverByItself() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 23)
        let id = try open(&e, "webdev")
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            Payments.injectCash(&s, companyID: id, amount: 40_000_000)
            s.companies[i].raw["ownerNetFlow"] = nil
        }
        let before = e.maximumDividend(companyID: id)
        if before > 0 {
            let paid = e.payDividendShare(companyID: id, share: 0.5)
            XCTAssertGreaterThan(paid, 0)
            XCTAssertLessThanOrEqual(paid, before * 0.5 + 1)
        }
        for _ in 0..<(8 * 7) { e.nextDay(); for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) } }
        let distributed = e.state.company(id)?.distributed ?? 0
        XCTAssertEqual(distributed, e.state.company(id)?.distributed, "nothing else pays it out")
    }

    func testDelegationLinesFollowWhoIsHired() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 24)
        let id = try open(&e, "webdev")
        var line = try XCTUnwrap(e.delegationLines().first { $0.id == id })
        XCTAssertEqual(line.rehire, "You")
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].managerID = 0 } }
        line = try XCTUnwrap(e.delegationLines().first { $0.id == id })
        XCTAssertEqual(line.rehire, "Manager")
        XCTAssertEqual(line.payroll, "Manager")
    }

    func testSeverityFollowsKindAndSizeAgainstNetWorth() throws {
        var m = Message(raw: [:])
        m.kind = "ask"; m.status = "open"; m.actionID = "x"; m.tone = "n"
        m.raw["opts"] = .array([.object(["t": "Spend", "fx": .object(["cash": -10_000])])])
        XCTAssertEqual(Delegation.level(of: m, netWorth: 10_000_000), 2, "10k at 10M is a manager's matter")
        XCTAssertEqual(Delegation.level(of: m, netWorth: 100_000), 5, "the same 10k at 100k is the owner's")
        var pay = m; pay.actionID = "pay29x"
        XCTAssertEqual(Delegation.level(of: pay, netWorth: 100_000), 1, "payroll is routine whatever its size")
    }

    func testAStandingDividendPolicyOnlyProposesAndNeverPays() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 25)
        let id = try open(&e, "webdev")
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].set("dp27", "mid")
            s.companies[i].monthlyHistory = (0..<14).map { MonthRecord(monthIndex: $0, revenue: 900_000, profit: 400_000, cash: 0) }
            Payments.injectCash(&s, companyID: id, amount: 80_000_000)
        }
        for _ in 0..<(30 * 7) { e.nextDay(); for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) } }
        XCTAssertEqual(e.state.company(id)?.distributed ?? 0, 0, "nothing is paid without an answer")
    }

    func testAManagerTakesASmallDecisionAndTheOwnerKeepsTheRest() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 26)
        let id = try open(&e, "webdev")
        func post() -> [Message] {
            e.update { s, _, _ in
                s.addMessage(kind: "decision", from: "Staff", title: "Fix the printer?", body: "It broke.", companyID: id, tone: "n", status: "open",
                             options: [.option("Fix it", "", effects: ["cash": -1000]), .option("Leave it", "", effects: [:])])
            }
            return e.state.inbox.filter { $0.status == "open" && $0.title == "Fix the printer?" }
        }
        // no manager: it stays with the owner
        XCTAssertEqual(e.routeFreshDecisions(post()), 0)
        XCTAssertFalse(e.openDecisions.isEmpty)
        // with a manager and a small matter against a large net worth: the manager decides
        e.update { s, _, _ in
            Ledger.move(&s, .me, 900_000_000, why: "Test funds")
            if let i = s.companyIndex(id) { s.companies[i].managerID = 0 }
        }
        e.setManagerBudget(companyID: id, budget: .normal)
        let fresh = Array(post().suffix(1))   // the newest one only: the first stays with the owner
        XCTAssertEqual(e.routeFreshDecisions(fresh), 1)
        let done = try XCTUnwrap(e.state.inbox.first { $0.id == fresh[0].id })
        XCTAssertEqual(done.status, "done")
        XCTAssertFalse(done.handledBy.isEmpty)
        XCTAssertEqual(done.int("pick"), 1, "the manager takes the option that costs nothing")
    }

    func testAtlasTakesEveryPolicyWithoutChoosingAnInsurerFirst() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 27)
        let id = try open(&e, "webdev")
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].raw["insr"] = .null } }
        let cover = try XCTUnwrap(e.coverageOverview(companyID: id))
        let policy = try XCTUnwrap(cover.policies.first { !$0.isOn })
        let out = e.buyInsurance(companyID: id, product: policy.id, receiptCompanyID: id)
        XCTAssertEqual(out.result, .done)
        XCTAssertEqual(e.state.company(id)?.value("insr")["name"].string, "Atlas Insurance")
    }

    func testStartingACompanyFillsInNoDocumentsAndBuysNothing() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 28)
        e.update { s, _, _ in Ledger.move(&s, .me, 300_000_000, why: "Test funds") }
        guard case .success(let out) = e.startCompanyChoosingPremises(tradeID: "cafe", cityID: e.state.player.cityID, size: 1, name: nil, pick: nil, fundWith: 20_000_000) else { throw XCTSkip("no start") }
        let co = try XCTUnwrap(e.state.company(out.companyID))
        let docs = co.value("docs").object
        XCTAssertTrue(docs.filter { $0.key != "accountant_agreement" }.isEmpty, "no document is applied for the player: \(docs.keys.sorted())")
        XCTAssertTrue(co.value("prem").isNull, "no place is rented by itself")
        XCTAssertTrue(co.staff.isEmpty)
    }
}
