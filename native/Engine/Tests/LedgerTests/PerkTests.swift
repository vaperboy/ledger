import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Staff perks, hosting a deal on what you own and lending a piece to a manager: they cost real money, change real numbers, books balance.
final class PerkTests: XCTestCase {
    private func openCafe(_ e: inout GameEngine) throws -> Int {
        e.update { s, _, _ in Ledger.move(&s, .me, 800_000_000, why: "Test funds") }
        let res = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 30_000_000)
        guard case .success(let id) = res else { throw XCTSkip("could not start: \(res)") }
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].status = .open
            s.companies[i].staff = [
                StaffMember(raw: ["id": 9001, "role": "waiter", "wage": 30000, "w0": 0, "tired": 20]),
                StaffMember(raw: ["id": 9002, "role": "lead", "wage": 40000, "w0": 0, "tired": 10]),
            ]
        }
        return id
    }

    func testPerksCostMoneyEaseTirednessAndKeepPeople() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        let id = try openCafe(&e)
        XCTAssertEqual(e.toggleStaffPerk(companyID: id, perk: "gym"), true)
        XCTAssertEqual(e.toggleStaffPerk(companyID: id, perk: "lunch"), true)
        XCTAssertNil(e.toggleStaffPerk(companyID: id, perk: "nope"))
        XCTAssertGreaterThan(e.staffPerksMonthlyTotal(companyID: id), 0)
        XCTAssertGreaterThan(e.staffPerksFewerLeavePercent(companyID: id), 5)
        let co0 = try XCTUnwrap(e.state.company(id))
        let worker = co0.staff[0]
        XCTAssertEqual(StaffPerks.quitFactor(co0, worker), 0.95 * 0.94, accuracy: 1e-9)
        XCTAssertGreaterThan(StaffPerks.pull(co0), 0.3)
        let cash0 = co0.cash
        e.update { s, d, _ in StaffPerks.weekly(&s, data: d) }
        let co1 = try XCTUnwrap(e.state.company(id))
        XCTAssertLessThan(co1.cash, cash0, "perks are paid with the wages")
        XCTAssertEqual(co1.staff[0].tiredness, 20 - 1.5, accuracy: 1e-9)
        XCTAssertEqual(e.toggleStaffPerk(companyID: id, perk: "gym"), false)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testHostingCostsMoneyAndLendingWearsThePiece() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        let id = try openCafe(&e)
        XCTAssertEqual(e.buyLuxury(itemID: "e2"), .ok)
        XCTAssertEqual(e.buyLuxury(itemID: "c15"), .ok)
        let island = try XCTUnwrap(e.luxuryPieces.first { $0.item.id == "e2" })
        XCTAssertEqual(e.hostingVenues.map { $0.id }, [island.id])
        let cost = try XCTUnwrap(e.hostingCost(pieceID: island.id))
        let cash0 = e.state.cash
        guard case .ok = e.hostDeal(pieceID: island.id, guest: .investors) else { return XCTFail("host") }
        XCTAssertEqual(e.state.cash, cash0 - cost, accuracy: 1)
        XCTAssertGreaterThan(StaffPerks.hosted(e.state, "inv"), 0)
        XCTAssertEqual(e.hostDeal(pieceID: island.id, guest: .investors), .wait, "an evening a month at most")

        // lend the car to the manager of the cafe
        e.update { s, _, _ in
            s.people[9100] = Person(raw: ["id": 9100, "name": "Anna Berg", "age": 40, "role": "mgr", "skill": 80])
            s.companies[s.companyIndex(id)!].managerID = 9100
            s.companies[s.companyIndex(id)!].set("mood", 60)
        }
        let car = try XCTUnwrap(e.lendablePieces.first { $0.item.id == "c15" })
        XCTAssertEqual(e.rewardCandidates.filter { $0.isManager }.count, 1)
        XCTAssertEqual(e.lendPiece(pieceID: car.id, companyID: id, staffID: nil), .ok(name: "Anna Berg"))
        XCTAssertEqual(e.state.company(id)?.num("mood") ?? 0, 70, accuracy: 1e-9)
        XCTAssertGreaterThan(e.state.people[9100]?.num("ret27") ?? 0, Double(e.state.week), "rival headhunters leave a lent-to manager alone")
        let worn = try XCTUnwrap(e.luxuryPieces.first { $0.id == car.id })
        XCTAssertLessThan(worn.value, car.value)
        XCTAssertNotNil(e.lentTo(pieceID: car.id))
        XCTAssertTrue(e.lendablePieces.filter { $0.id == car.id }.isEmpty, "a lent car is away")
        e.update { s, d, _ in s.week += 27; StaffPerks.weekly(&s, data: d) }
        XCTAssertNil(e.lentTo(pieceID: car.id))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
