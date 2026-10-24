import XCTest
import GameCore
import Finance
import Businesses
import Events
import Simulation

/// Ambition perks reaching loans and quality, the finance manager negotiating a raise, and the "find a successor" search.
final class AmbitionPerksAndSuccessorTests: XCTestCase {
    func testFinancierPerkCutsTheLoanMarginAndRanksAreReal() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 21)
        e.update { s, _, _ in Ledger.move(&s, .me, 20_000_000, why: "Test funds") }
        guard case .success = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 8_000_000) else { throw XCTSkip("no company") }
        let plain = Banking.offer(kind: "cons", amount: 1000, company: nil, state: e.state, netWorth: 1_000_000, context: e.context).margin
        e.update { s, _, _ in
            s.rest["amb27"] = .object(["path": .string("financier"), "tier": .object(["financier": .number(1)]), "done": .object([:]), "score": 0, "since": 0, "settle": 0,
                                       "pkAll": .bool(false), "cnt": .object([:]), "hist": .array([]), "ask": 1])
        }
        XCTAssertEqual(Ambitions.loanMarginCut(e.state, e.data), 0.003, accuracy: 1e-9)
        let perked = Banking.offer(kind: "cons", amount: 1000, company: nil, state: e.state, netWorth: 1_000_000, context: e.context).margin
        XCTAssertEqual(plain - perked, 0.003, accuracy: 1e-9, "the engine's lending hook applies the perk")
        // A milestone about your rank among all companies now reads a real place (you run a company, so not the 999 of "no ranking").
        // Only an open (or closed) company counts in the table, so open the one still being set up.
        e.update { s, _, _ in for i in s.companies.indices { s.companies[i].status = .open } }
        let rank = try XCTUnwrap(e.yourRanking(scope: .country, metric: .revenue))
        XCTAssertGreaterThanOrEqual(rank.rank, 1)
        XCTAssertLessThanOrEqual(rank.rank, rank.of)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testSuccessorSearchAndFinanceManagerRaise() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 30_000_000) else { throw XCTSkip("no company") }
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: id, monthlyWage: cands[0].askingMonthlyWage * 1.2, profitBonus: 0.05), .ok)
        XCTAssertEqual(e.state.company(id)?.managerProfitBonus ?? 0, 0.05, accuracy: 1e-9)
        // The manager gives notice: the message offers a search, and answering it pays for one and keeps the candidates.
        e.update { s, _, _ in ManagerModel.resign(&s, companyIndex: s.companyIndex(id)!, why: "a better offer") }
        let ask = try XCTUnwrap(e.openDecisions.first { $0.actionID == ManagerTargets.successorAction })
        let cash0 = e.state.company(id)?.cash ?? 0
        XCTAssertTrue(e.answer(messageID: ask.id, option: 0))
        XCTAssertEqual(e.successorCandidates(companyID: id).count, 4)
        XCTAssertLessThan(e.state.company(id)?.cash ?? cash0, cash0, "the executive search cost money")
        let cash1 = e.state.company(id)?.cash ?? 0
        XCTAssertEqual(e.findSuccessor(companyID: id)?.count, 4)
        XCTAssertEqual(e.state.company(id)?.cash ?? 0, cash1, "a search already running is not paid twice")

        // The finance manager who runs a holding negotiates its raise: better terms than doing it yourself.
        let before = e.raisePlan(holdingID: id, goal: 5_000_000, publicOffering: false)
        XCTAssertNil(before.manager)
        var fin = 0
        e.update { s, _, _ in
            fin = s.makeID()
            s.people[fin] = Person(raw: ["id": .number(Double(fin)), "name": .string("Fin Manager"), "age": 45, "role": .string("fin"), "skill": 95, "exp": 10])
            s.rest["office"] = .object(["tier": .string("home"), "since": 0, "staff": .array([.object(["id": .number(Double(fin)), "role": .string("fin"), "name": .string("Fin Manager"),
                                                                                                         "holds": .array([.number(Double(id))])])])])
        }
        let after = e.raisePlan(holdingID: id, goal: 5_000_000, publicOffering: false)
        XCTAssertEqual(after.manager, "Fin Manager")
        XCTAssertEqual(try XCTUnwrap(after.managerSkill), 0.98, accuracy: 1e-9)
        XCTAssertLessThan(after.given, before.given, "an experienced negotiator sells fewer shares for the same money")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }
}
