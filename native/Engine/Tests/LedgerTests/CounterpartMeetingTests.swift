import XCTest
import GameCore
import Finance
import Businesses
import Simulation

/// Pins the "meet a counterpart" rule: supplier lunch, rival lunch, key-account dinner and the manager meeting. Each costs a set
/// amount (scaled), can be repeated only after four weeks, and warms the relationship. Written against the four separate copies and
/// kept green after they were merged into `CounterpartMeeting`.
final class CounterpartMeetingTests: XCTestCase {
    private func game(_ country: String = "UK", seed: Int = 7) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: country, playerName: "T", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 500_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 50_000_000) else { throw XCTSkip("no cafe") }
        return (e, id)
    }

    private func addRival(_ e: inout GameEngine, _ id: Int) -> Int {
        var rid = 0
        e.update { s, _, _ in
            let co = s.company(id)!
            let k = Rivals.key(co)
            var mk = s.rest["mk"] ?? .object([:])
            var m = mk[k].isNull ? JSONValue.object([:]) : mk[k]
            var riv = m["riv"].array
            if riv.isEmpty { riv = [.object(["id": 41, "name": "Rival Cafe", "owner": "R. Owner", "size": 1.0, "rel": 30, "known": true])] }
            riv[0]["meet"] = .number(-99)
            rid = riv[0]["id"].int
            m["riv"] = .array(riv); mk[k] = m; s.rest["mk"] = mk
        }
        return rid
    }

    private func setWeek(_ e: inout GameEngine, _ delta: Int) { e.update { s, _, _ in s.week += delta } }

    // MARK: Supplier lunch

    func testSupplierLunch() throws {
        var (e, _) = try game()
        let vid = "V-UK-3"
        let cost = e.homeCurrency.scaledPrice(5000)
        let cash0 = e.state.cash
        XCTAssertEqual(e.lunchWithSupplier(vendorID: vid), .ok)
        XCTAssertEqual(cash0 - e.state.cash, jsRound(cost), accuracy: 0.5)
        let rel = e.state.rest["vr"]![vid]["r"].double
        XCTAssertEqual(rel, 7, "seed 7, week 0: the first draw of 5...9")
        XCTAssertGreaterThanOrEqual(rel, 5); XCTAssertLessThanOrEqual(rel, 9)
        XCTAssertEqual(e.state.rest["vr"]![vid]["meet"].int, e.state.week)
        // Again at once: wait, nothing paid.
        let cash1 = e.state.cash
        XCTAssertEqual(e.lunchWithSupplier(vendorID: vid), .wait)
        XCTAssertEqual(e.state.cash, cash1)
        setWeek(&e, 3); XCTAssertEqual(e.lunchWithSupplier(vendorID: vid), .wait)
        setWeek(&e, 1); XCTAssertEqual(e.lunchWithSupplier(vendorID: vid), .ok)
        XCTAssertEqual(e.lunchWithSupplier(vendorID: "nope"), .unknown)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testSupplierLunchNeedsCash() throws {
        var (e, _) = try game()
        e.update { s, _, _ in Ledger.move(&s, .me, -(s.cash - 100), why: "Spend") }
        let cash = e.state.cash
        XCTAssertEqual(e.lunchWithSupplier(vendorID: "V-UK-3"), .cash)
        XCTAssertEqual(e.state.cash, cash)
        XCTAssertNil(e.state.rest["vr"]?["V-UK-3"]["meet"].isNull == false ? 1 : nil)
    }

    // MARK: Rival lunch

    func testRivalLunch() throws {
        var (e, id) = try game()
        let rid = addRival(&e, id)
        let co = try XCTUnwrap(e.state.company(id))
        let before = try XCTUnwrap(Rivals.rivals(e.state, for: co).first { $0.id == rid }).relationship
        let cost = e.homeCurrency.scaledPrice(4000)
        let cash0 = e.state.cash
        let wk = e.state.week
        XCTAssertEqual(e.meetRival(companyID: id, rivalID: rid), .ok)
        XCTAssertEqual(cash0 - e.state.cash, jsRound(cost), accuracy: 0.5)
        var h = HashedRandom("\(e.state.seed):lunch:\(wk):\(rid)")
        let gain = 4 + (h.next() * 6).rounded(.down)
        let after = try XCTUnwrap(Rivals.rivals(e.state, for: co).first { $0.id == rid })
        // The lunch gain, then the memory entry adds its own +4 (as the game has always done).
        XCTAssertEqual(after.relationship, min(100, min(100, before + gain) + 4))
        XCTAssertEqual(after.memory.first?.text, "Had lunch with you.")
        XCTAssertEqual(after.memory.first?.change, 4)
        XCTAssertEqual(e.meetRival(companyID: id, rivalID: rid), .wait)
        setWeek(&e, 3); XCTAssertEqual(e.meetRival(companyID: id, rivalID: rid), .wait)
        setWeek(&e, 1); XCTAssertEqual(e.meetRival(companyID: id, rivalID: rid), .ok)
        XCTAssertEqual(e.meetRival(companyID: id, rivalID: 9999), .missing)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testRivalLunchNeedsCash() throws {
        var (e, id) = try game()
        let rid = addRival(&e, id)
        e.update { s, _, _ in Ledger.move(&s, .me, -(s.cash - 100), why: "Spend") }
        let cash = e.state.cash
        XCTAssertEqual(e.meetRival(companyID: id, rivalID: rid), .cash)
        XCTAssertEqual(e.state.cash, cash)
    }

    // MARK: Key-account dinner

    func testAccountDinner() throws {
        var (e, id) = try game()
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].set("accts", .array([.object(["id": 1, "name": "Acme Catering", "f": 0.2, "rel": 20, "w0": .number(Double(s.week)), "disc": 10])]))
        }
        let cost = e.homeCurrency.scaledPrice(6000)
        let cash0 = e.state.cash
        let wk = e.state.week
        XCTAssertEqual(e.meetAccount(companyID: id, accountID: 1), .ok)
        XCTAssertEqual(cash0 - e.state.cash, jsRound(cost), accuracy: 0.5)
        var h = HashedRandom("\(e.state.seed):meet:\(wk):1")
        let expected = min(100, 20 + (4 + (h.next() * 4).rounded(.down)) * (1 - pow(20.0 / 100, 1.6)))
        let a = try XCTUnwrap(e.keyAccountInfo(try XCTUnwrap(e.state.company(id))).accounts.first)
        XCTAssertEqual(a.relationship, expected, accuracy: 1e-9)
        XCTAssertEqual(a.lastMeeting, wk)
        XCTAssertEqual(e.meetAccount(companyID: id, accountID: 1), .wait)
        setWeek(&e, 3); XCTAssertEqual(e.meetAccount(companyID: id, accountID: 1), .wait)
        setWeek(&e, 1); XCTAssertEqual(e.meetAccount(companyID: id, accountID: 1), .ok)
        XCTAssertEqual(e.meetAccount(companyID: id, accountID: 77), .missing)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testAccountDinnerNeedsCash() throws {
        var (e, id) = try game()
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].set("accts", .array([.object(["id": 1, "name": "Acme", "f": 0.2, "rel": 20, "w0": 0, "disc": 10])]))
            Ledger.move(&s, .me, -(s.cash - 100), why: "Spend")
        }
        let cash = e.state.cash
        XCTAssertEqual(e.meetAccount(companyID: id, accountID: 1), .cash)
        XCTAssertEqual(e.state.cash, cash)
    }

    // MARK: Manager meeting

    private func gameWithManager() throws -> (GameEngine, Int) {
        var (e, id) = try game()
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: id, monthlyWage: cands[0].askingMonthlyWage * 1.2), .ok)
        return (e, id)
    }

    func testManagerMeetingIsFreeAndWaitsFourWeeks() throws {
        var (e, id) = try gameWithManager()
        let cash0 = e.state.cash, inbox0 = e.state.inbox.count, comp0 = e.state.company(id)!.cash
        let wk = e.state.week
        XCTAssertTrue(e.meetManager(companyID: id))
        XCTAssertEqual(e.state.cash, cash0); XCTAssertEqual(e.state.company(id)!.cash, comp0)
        XCTAssertEqual(e.state.inbox.count, inbox0 + 1)
        XCTAssertEqual(e.state.inbox.last?.title, "Re: \(e.state.company(id)!.name)")
        XCTAssertEqual(e.state.company(id)!.value("meetW").int, wk)
        XCTAssertFalse(e.meetManager(companyID: id))
        setWeek(&e, 3); XCTAssertFalse(e.meetManager(companyID: id))
        setWeek(&e, 1); XCTAssertTrue(e.meetManager(companyID: id))
        var e2 = try game()
        XCTAssertFalse(e2.0.meetManager(companyID: e2.1), "no manager")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    /// The board "call a meeting" uses a three-week cool-down on the same stamp (original: `callMeeting`), not four.
    func testCallMeetingCoolDownIsThreeWeeks() throws {
        var (e, id) = try gameWithManager()
        XCTAssertEqual(e.callMeeting(companyID: id, goal: "review", tone: "casual"), .ok(1))
        XCTAssertEqual(e.callMeeting(companyID: id, goal: "review", tone: "casual"), .wait)
        setWeek(&e, 2); XCTAssertEqual(e.callMeeting(companyID: id, goal: "review", tone: "casual"), .wait)
        setWeek(&e, 1); XCTAssertEqual(e.callMeeting(companyID: id, goal: "review", tone: "casual"), .ok(1))
    }
}
