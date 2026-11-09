import XCTest
import GameCore
import Finance
import Businesses
import Simulation

/// The board's one decision list: what is on it and why, the adviser's recommendation, the vote by shares, and what approving does.
final class BoardDecisionTests: XCTestCase {
    /// `count` limited cafes, each with a co-owner holding 15% (so a board exists).
    private func makeBoards(seed: Int, count: Int) throws -> (engine: GameEngine, ids: [Int], keys: [String]) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 300_000_000, why: "Test funds") }
        var ids: [Int] = [], keys: [String] = []
        for _ in 0..<count {
            guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, fundWith: 8_000_000) else { throw XCTSkip("could not start a company") }
            ids.append(id)
            e.update { s, _, _ in
                if let i = s.companyIndex(id) { s.companies[i].status = .open; s.companies[i].set("holders", .array([.object(["name": "Ann Partner", "pct": 15, "in": 0, "k27": "quiet", "sat": 60, "w0": 0])])) }
            }
            keys.append(try XCTUnwrap(e.boardKey(companyID: id)))
        }
        return (e, ids, keys)
    }

    private func history(_ e: inout GameEngine, _ id: Int, months: Int = 3, profit: Double) {
        e.update { s, _, _ in
            if let i = s.companyIndex(id) { s.companies[i].monthlyHistory = (0..<months).map { MonthRecord(monthIndex: $0, revenue: 40_000, profit: profit, cash: 10_000) } }
        }
    }

    func testNothingToDecideMeansAnEmptyListAndNoBadge() throws {
        let (e, _, keys) = try makeBoards(seed: 31, count: 1)
        XCTAssertTrue(e.boardDecisionList().isEmpty)
        XCTAssertEqual(e.boardOpenDecisions(key: keys[0]), 0)
        XCTAssertEqual(e.boardDecisionsWaiting, 0)
    }

    func testLossesRaiseASaleWithTheAdvisersRecommendation() throws {
        var (e, ids, keys) = try makeBoards(seed: 32, count: 1)
        history(&e, ids[0], profit: -6_000)
        let list = e.boardDecisionList()
        XCTAssertEqual(list.map { $0.kind }, ["sell"])
        let d = list[0]
        XCTAssertEqual(d.id, "sell:\(ids[0])")
        XCTAssertEqual(d.key, keys[0])
        XCTAssertTrue(d.recommends, "a loss of a seventh of sales is deep")
        XCTAssertFalse(d.advisor.isEmpty); XCTAssertFalse(d.reason.isEmpty); XCTAssertFalse(d.effect.isEmpty); XCTAssertFalse(d.risk.isEmpty)
        XCTAssertEqual(e.boardOpenDecisions(key: keys[0]), 1)
        XCTAssertEqual(e.boardDecisionList(key: keys[0]), list)
    }

    func testAMildLossIsRaisedButNotRecommended() throws {
        var (e, ids, _) = try makeBoards(seed: 32, count: 1)
        history(&e, ids[0], profit: -500)
        let d = try XCTUnwrap(e.boardDecisionList().first { $0.kind == "sell" })
        XCTAssertFalse(d.recommends)
    }

    func testApprovedSaleListsTheCompanyAndIsNotRaisedAgainAtOnce() throws {
        var (e, ids, keys) = try makeBoards(seed: 33, count: 1)
        history(&e, ids[0], profit: -6_000)
        let r = e.decideBoardItem(id: "sell:\(ids[0])", approve: true)
        guard case .done(let out) = r else { return XCTFail("\(r)") }
        XCTAssertTrue(out.contains("listed"))
        XCTAssertTrue((e.state.rest["sales"]?.array ?? []).contains { $0["co"].int == ids[0] }, "the company is really on the broker's list")
        XCTAssertTrue(e.boardDecisionList(key: keys[0]).isEmpty)
        XCTAssertEqual(e.decideBoardItem(id: "sell:\(ids[0])", approve: true), .gone, "an answered item cannot be answered twice")
    }

    func testDeclinedItemComesBackAfterTheQuietTime() throws {
        var (e, ids, _) = try makeBoards(seed: 34, count: 1)
        history(&e, ids[0], profit: -6_000)
        XCTAssertEqual(e.decideBoardItem(id: "sell:\(ids[0])", approve: false), .declined)
        XCTAssertFalse((e.state.rest["sales"]?.array ?? []).contains { $0["co"].int == ids[0] })
        XCTAssertTrue(e.boardDecisionList().isEmpty)
        e.update { s, _, _ in s.week += 13 }   // a declined item rests for twelve weeks
        XCTAssertEqual(e.boardDecisionList().map { $0.kind }, ["sell"], "the numbers still call for it")
    }

    func testCoOwnersCanVoteASaleDown() throws {
        var (e, ids, _) = try makeBoards(seed: 35, count: 1)
        history(&e, ids[0], profit: -6_000)
        // You hold 40% and a co-owner 60%: the shares decide. A rare change of heart is a hash of name and week, so look for a week they dissent.
        e.update { s, _, _ in
            guard let i = s.companyIndex(ids[0]) else { return }
            s.companies[i].ownership = 40
            s.companies[i].set("holders", .array([.object(["name": "Ann Partner", "pct": 60, "in": 0, "k27": "quiet", "sat": 60, "w0": 0])]))
        }
        var found = false
        for w in 20..<120 {
            e.update { s, _, _ in s.week = w }
            if !e.boardVote(kind: "sell", companyID: ids[0]).passes { found = true; break }
        }
        guard found else { throw XCTSkip("the co-owner never dissents in these weeks") }
        guard case .voteFailed(let pct) = e.decideBoardItem(id: "sell:\(ids[0])", approve: true) else { return XCTFail("the vote should fail") }
        XCTAssertEqual(pct, 40)
        XCTAssertFalse((e.state.rest["sales"]?.array ?? []).contains { $0["co"].int == ids[0] })
    }

    func testDividendIsRaisedWhenOwnersWaitAndSetsThePolicy() throws {
        var (e, ids, keys) = try makeBoards(seed: 36, count: 1)
        history(&e, ids[0], profit: 9_000)
        XCTAssertEqual(e.boardDecisionList().map { $0.kind }, ["dividend"])
        XCTAssertTrue(try XCTUnwrap(e.boardDecisionList().first).recommends)
        guard case .done = e.decideBoardItem(id: "dividend:\(ids[0])", approve: true) else { return XCTFail("approve") }
        XCTAssertEqual(e.dividendPolicy(companyID: ids[0]), "low")
        XCTAssertEqual(e.boardOpenDecisions(key: keys[0]), 0)
    }

    func testCapitalInjectionIsOfferedWhenCashRunsOutAndPutsMoneyIn() throws {
        var (e, ids, _) = try makeBoards(seed: 37, count: 1)
        history(&e, ids[0], profit: 2_000)
        e.update { s, _, _ in if let i = s.companyIndex(ids[0]) { s.companies[i].set("wkD", -2_000_000) } }
        let d = try XCTUnwrap(e.boardDecisionList().first { $0.kind == "inject" })
        XCTAssertGreaterThan(d.cost, 0)
        XCTAssertTrue(d.recommends, "the business itself holds up")
        let cash0 = try XCTUnwrap(e.state.company(ids[0])).cash
        guard case .done = e.decideBoardItem(id: d.id, approve: true) else { return XCTFail("approve") }
        XCTAssertGreaterThan(try XCTUnwrap(e.state.company(ids[0])).cash, cash0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testReplacingTheCEOIsRecommendedAfterThreeLosingMonthsAndLeavesAFollowUp() throws {
        var (e, ids, keys) = try makeBoards(seed: 38, count: 1)
        let cands = try XCTUnwrap(e.searchManagers(companyID: ids[0]))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: ids[0], monthlyWage: cands[0].askingMonthlyWage * 1.3), .ok)
        history(&e, ids[0], profit: -6_000)
        e.update { s, _, _ in
            s.week = 60
            if let i = s.companyIndex(ids[0]) { s.companies[i].set("mgrW0", 0) }
        }
        let d = try XCTUnwrap(e.boardDecisionList().first { $0.kind == "ceo" })
        XCTAssertTrue(d.recommends)
        guard case .done = e.decideBoardItem(id: d.id, approve: true) else { return XCTFail("approve") }
        XCTAssertNil(e.state.company(ids[0])?.managerID)
        XCTAssertTrue(e.boardFollowUps(key: keys[0]).contains { $0.text.contains("Appoint a new manager") })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testDeepLossesForHalfAYearRaiseClosingAndApprovingWindsTheCompanyUp() throws {
        var (e, ids, _) = try makeBoards(seed: 39, count: 1)
        history(&e, ids[0], months: 6, profit: -6_000)
        let d = try XCTUnwrap(e.boardDecisionList().first { $0.kind == "close" })
        XCTAssertTrue(d.recommends)
        guard case .done = e.decideBoardItem(id: d.id, approve: true) else { return XCTFail("approve") }
        XCTAssertFalse(try XCTUnwrap(e.state.company(ids[0])).status.isLive)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testRecommendedItemsComeFirstAcrossBoards() throws {
        var (e, ids, _) = try makeBoards(seed: 40, count: 2)
        history(&e, ids[0], profit: -500)      // mild loss: raised, not recommended
        history(&e, ids[1], profit: -6_000)    // deep loss: recommended
        let list = e.boardDecisionList()
        XCTAssertEqual(list.map { $0.companyID }, [ids[1], ids[0]])
    }

    /// A chain's CEO or chain manager proposes closing a location; it waits on the chain's board and the owner decides from the list.
    func testClosingALocationIsAProposalOnTheChainsBoard() throws {
        var e = try ChainsTests.engine("NO")
        let a = ChainsTests.start(&e, "cafe")
        ChainsTests.season(&e, a)
        let id = try XCTUnwrap(e.makeChain(companyID: a, name: "Khan Shop"))
        guard case .success(let b) = e.openLocation(chainID: id, cityID: e.state.player.cityID) else { throw XCTSkip("location not opened") }
        _ = e.openCompany(companyID: b)
        let key = "ch:\(id)"
        var first: Int?, again: Int?
        e.update { s, d, _ in
            first = ChainLocations.proposeClosure(&s, storeID: b, by: "Ann Lee, Chain manager", why: "Six months of losses.", data: d)
            again = ChainLocations.proposeClosure(&s, storeID: b, by: "Ann Lee, Chain manager", why: "Six months of losses.", data: d)
        }
        XCTAssertNotNil(first)
        XCTAssertNil(again, "the same proposal is not listed twice")
        XCTAssertEqual(e.locationProposals(chainID: id).count, 1)
        let d = try XCTUnwrap(e.boardDecisionList(key: key).first { $0.kind == "shut" })
        XCTAssertEqual(d.advisor, "Ann Lee, Chain manager")
        XCTAssertTrue(d.recommends)
        XCTAssertEqual(d.companyID, b)
        guard case .done = e.decideBoardItem(id: d.id, approve: true) else { return XCTFail("approve") }
        XCTAssertEqual(e.state.company(b).flatMap { ChainBranches.ending($0) }, "closed")
        XCTAssertTrue(e.locationProposals(chainID: id).isEmpty)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testDecliningALocationProposalDropsItAndItIsNotProposedAgainSoon() throws {
        var e = try ChainsTests.engine("NO")
        let a = ChainsTests.start(&e, "cafe")
        ChainsTests.season(&e, a)
        let id = try XCTUnwrap(e.makeChain(companyID: a, name: "Khan Shop"))
        guard case .success(let b) = e.openLocation(chainID: id, cityID: e.state.player.cityID) else { throw XCTSkip("location not opened") }
        _ = e.openCompany(companyID: b)
        var pid: Int?
        e.update { s, d, _ in pid = ChainLocations.proposeClosure(&s, storeID: b, by: "Ann Lee, Chain manager", why: "Losses.", data: d) }
        XCTAssertNotNil(pid)
        let d = try XCTUnwrap(e.boardDecisionList(key: "ch:\(id)").first { $0.kind == "shut" })
        XCTAssertEqual(e.decideBoardItem(id: d.id, approve: false), .declined)
        XCTAssertTrue(e.locationProposals(chainID: id).isEmpty)
        var again: Int?
        e.update { s, dt, _ in again = ChainLocations.proposeClosure(&s, storeID: b, by: "Ann Lee, Chain manager", why: "Losses.", data: dt) }
        XCTAssertNil(again, "turned down lately")
        XCTAssertFalse(e.state.company(b).map { ChainBranches.ending($0) != nil } ?? true)
    }

    /// Opening a location is the owner's proposal voted at once; with nobody else owning the chain it opens as asked.
    func testOpeningALocationGoesThroughTheBoardsVote() throws {
        var e = try ChainsTests.engine("NO")
        let a = ChainsTests.start(&e, "cafe")
        ChainsTests.season(&e, a)
        let id = try XCTUnwrap(e.makeChain(companyID: a, name: "Khan Shop"))
        let n0 = Chains.stores(e.state, try XCTUnwrap(Chains.chain(e.state, id: id))).count
        guard case .success = e.openLocation(chainID: id, cityID: e.state.player.cityID) else { throw XCTSkip("location not opened") }
        XCTAssertEqual(Chains.stores(e.state, try XCTUnwrap(Chains.chain(e.state, id: id))).count, n0 + 1)
        // a proposal from the chain's lead waits on the list until it is decided
        var pid: Int?
        e.update { s, d, _ in pid = ChainLocations.proposeOpen(&s, chainID: id, cityID: s.player.cityID, by: "Ann Lee, CEO", why: "Every store makes money.", data: d) }
        let p = try XCTUnwrap(pid)
        let item = try XCTUnwrap(e.boardDecisionList(key: "ch:\(id)").first { $0.kind == "open" })
        XCTAssertEqual(item.proposalID, p)
        XCTAssertGreaterThan(item.cost, 0)
        guard case .done = e.decideBoardItem(id: item.id, approve: true) else { return XCTFail("approve") }
        XCTAssertEqual(Chains.stores(e.state, try XCTUnwrap(Chains.chain(e.state, id: id))).count, n0 + 2)
        XCTAssertTrue(e.locationProposals(chainID: id).isEmpty)
    }

    func testBoardsAndDecisionsSurviveASaveAndAreDeterministic() throws {
        func run() throws -> String {
            var (e, ids, keys) = try makeBoards(seed: 41, count: 2)
            for id in ids { history(&e, id, profit: -6_000) }
            _ = e.decideBoardItem(id: "sell:\(ids[0])", approve: false)
            for _ in 0..<(7 * 30) { _ = e.nextDay() }
            let back = try JSONDecoder().decode(GameState.self, from: try JSONEncoder().encode(e.state))
            XCTAssertEqual(ManagerModel.board(back, key: keys[0]), ManagerModel.board(e.state, key: keys[0]))
            XCTAssertEqual(ManagerModel.boardDecisions(back, data: e.data), e.boardDecisionList())
            let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
            return try keys.map { String(decoding: try enc.encode(ManagerModel.board(e.state, key: $0)), as: UTF8.self) }.joined(separator: "|")
        }
        XCTAssertEqual(try run(), try run())
    }

    /// Three boards over two years: the badge stays small (one item of each kind per company at most) and the books balance.
    func testTwoYearsOfThreeBoardsKeepTheListSmall() throws {
        for seed in [51, 52, 53] {
            var (e, ids, _) = try makeBoards(seed: seed, count: 3)
            for id in ids { history(&e, id, profit: -6_000) }
            for _ in 0..<104 {
                for _ in 0..<7 { _ = e.nextDay() }
                XCTAssertLessThanOrEqual(e.boardDecisionsWaiting, 3 * 7 + 3 * 2, "seed \(seed)")
            }
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "seed \(seed): the books still balance")
        }
    }

    func testShowcaseBoardHasADecisionToMake() throws {
        let e = try GameEngine.showcase(board: true)
        XCTAssertGreaterThanOrEqual(e.boardDecisionsWaiting, 1)
        let d = try XCTUnwrap(e.boardDecisionList().first)
        XCTAssertFalse(d.effect.isEmpty)
    }
}
