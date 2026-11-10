import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

final class NegotiationTests: XCTestCase {
    private let cur = Currency(country: try! CountryBook.bundled()["UK"]!, rates: ExchangeRates())

    private func respond(_ offer: Double, _ p: Negotiation.Position, _ t: Negotiation.Temperament, rank: String = "worker",
                         state: inout Negotiation.State, random: inout DeterministicRandom) -> Negotiation.Response {
        Negotiation.respond(offer: offer, position: p, temperament: t, rank: rank, state: &state, week: 5, step: cur.stepSize(about: 100), random: &random)
    }
    private var steady: Negotiation.Temperament { Negotiation.temperament(id: "steady")! }

    func testAcceptCounterRefuseAndWalkAway() {
        let p = Negotiation.Position(opening: 1000, reservation: 900, direction: .higher)
        var r = DeterministicRandom(seed: 1)
        var st = Negotiation.State()
        XCTAssertEqual(respond(900, p, steady, state: &st, random: &r).answer, .accept, "at the reservation they accept")
        XCTAssertFalse(st.isOpen)
        XCTAssertEqual(respond(100, p, steady, state: &st, random: &r).answer, .refuse)
        XCTAssertEqual(st.round, 1)
        var seen = 0
        for seed in 1...200 {
            var rr = DeterministicRandom(seed: seed), s2 = Negotiation.State()
            let reply = respond(850, p, steady, state: &s2, random: &rr)
            guard case .counter(let c) = reply.answer else { return XCTFail("expected a counter") }
            XCTAssertGreaterThanOrEqual(c.amount, 900)
            if !reply.unrealistic { XCTAssertLessThanOrEqual(c.amount, 1000 + cur.stepSize(about: 100)) } else { XCTAssertGreaterThan(c.amount, 1000 * 1.2) }
            XCTAssertTrue(p.accepts(c.amount)); seen += 1
        }
        XCTAssertEqual(seen, 200)
        var rounds = 0
        var s3 = Negotiation.State()
        var rr = DeterministicRandom(seed: 3)
        while rounds < 50 {
            let a = respond(850, p, steady, state: &s3, random: &rr).answer
            if a == .walkAway { break }
            rounds += 1
        }
        XCTAssertEqual(rounds, Negotiation.patience(rank: "worker", temperament: steady))
        var s4 = Negotiation.State(), r4 = DeterministicRandom(seed: 4), last: Negotiation.Counter?
        for _ in 0..<rounds { if case .counter(let c) = respond(850, p, steady, state: &s4, random: &r4).answer { last = c } }
        XCTAssertEqual(last?.isFinal, true)
    }

    func testBuyerSideCountersMoveTheOtherWay() {
        let p = Negotiation.Position(opening: 100, reservation: 125, direction: .lower)
        var r = DeterministicRandom(seed: 2), st = Negotiation.State()
        XCTAssertEqual(respond(125, p, steady, state: &st, random: &r).answer, .accept)
        XCTAssertEqual(respond(120, p, steady, state: &st, random: &r).answer, .accept, "a lower price than the limit is fine for a buyer")
        for seed in 1...50 {
            var rr = DeterministicRandom(seed: seed), s2 = Negotiation.State()
            let reply = respond(150, p, steady, state: &s2, random: &rr)
            guard case .counter(let c) = reply.answer else { return XCTFail("counter") }
            if !reply.unrealistic { XCTAssertLessThanOrEqual(c.amount, 125 + 1e-6) } else { XCTAssertLessThan(c.amount, 100) }
        }
    }

    func testPatienceRisesWithTheLevelOfThePost() {
        let ranks = ["worker", "assistant", "manager", "teamHead", "chainManager", "ceo", "groupDirector"]
        let p = ranks.map { Negotiation.patience(rank: $0, temperament: steady) }
        XCTAssertEqual(p, p.sorted(), "patience never falls as the post gets senior: \(p)")
        XCTAssertGreaterThan(p.last!, p.first!)
        let flex = Negotiation.temperament(id: "flexible")!, stub = Negotiation.temperament(id: "stubborn")!
        XCTAssertGreaterThan(Negotiation.patience(rank: "manager", temperament: flex), Negotiation.patience(rank: "manager", temperament: stub))
    }

    func testUnrealisticCountersOccurAtTheDataRate() {
        for id in Negotiation.temperamentIDs {
            let t = Negotiation.temperament(id: id)!
            let p = Negotiation.Position(opening: 1000, reservation: 900, direction: .higher)
            var r = DeterministicRandom(seed: 99)
            var counters = 0, odd = 0
            for _ in 0..<4000 {
                var st = Negotiation.State()
                let reply = respond(850, p, t, state: &st, random: &r)
                if case .counter = reply.answer { counters += 1; if reply.unrealistic { odd += 1 } }
            }
            XCTAssertEqual(Double(odd) / Double(counters), Negotiation.overreachChance(of: t), accuracy: 0.03, id)
        }
    }

    func testDeterministicFromTheSameSeed() {
        func run() -> [Negotiation.Answer] {
            var r = DeterministicRandom(seed: 77), st = Negotiation.State(), out: [Negotiation.Answer] = []
            let p = Negotiation.Position(opening: 1000, reservation: 900, direction: .higher)
            for offer in [700.0, 850, 860, 870, 880, 890] { out.append(respond(offer, p, steady, rank: "manager", state: &st, random: &r).answer) }
            return out
        }
        XCTAssertEqual(run(), run())
    }

    func testStateRoundTripsThroughJSON() throws {
        var st = Negotiation.State(); st.party = 7; st.round = 2; st.lastOffer = 1234; st.counter = 1500; st.week = 9
        let data = try JSONEncoder().encode(st.json)
        XCTAssertEqual(Negotiation.State(json: try JSONDecoder().decode(JSONValue.self, from: data)), st)
    }

    func testNoDataMeansNoMagicNumbersInCode() throws {
        let t = Negotiation.temperamentIDs
        XCTAssertTrue(t.count >= 3)
        XCTAssertGreaterThan(Negotiation.insultLine, 0)
        XCTAssertGreaterThan(Negotiation.memoryWeeks, 0)
    }

    private func game(_ seed: Int = 31) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, fundWith: 20_000_000) else { throw XCTSkip("start") }
        return (e, id)
    }
    private func worker(_ e: inout GameEngine, _ id: Int, ask: Double? = nil, pers: String = "steady") -> Int {
        var pid = 0
        e.update { s, d, _ in
            var p = Hiring.generateCandidate(role: "barista", company: s.company(id), tier: "mid", state: &s, data: d)
            p.set("pers", pers)
            if let ask { p.askingMonthlyWage = ask }
            s.people[p.id] = p; pid = p.id
        }
        return pid
    }

    func testWorkerCountersThenAcceptsTheCounterAndBooksBalance() throws {
        var (e, id) = try game()
        let pid = worker(&e, id)
        let ask = e.state.people[pid]!.askingMonthlyWage
        let r = e.hire(personID: pid, companyID: id, monthlyWage: ask * 0.8)
        guard case .countered(let c) = r else { return XCTFail("expected a counter, got \(r)") }
        XCTAssertNotNil(e.state.people[pid]!.value("neg").object["n"], "the open talk is kept on the person")
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: c.amount), .ok)
        XCTAssertTrue(e.state.people[pid]!.value("neg").isNull, "a finished talk leaves no key")
        XCTAssertEqual(e.state.company(id)!.staff.first { $0.id == pid }?.monthlyWage, c.amount)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testInsultThenPatienceGoneTakesThePersonOffTheMarket() throws {
        var (e, id) = try game()
        let pid = worker(&e, id, ask: 1_000_000)
        let patience = Negotiation.patience(rank: "worker", temperament: Hiring.temperament(of: e.state.people[pid]!))
        for _ in 0..<patience { XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: 1000), .refused) }
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: 1000), .walkedAway)
        XCTAssertEqual(e.state.people[pid]!.employerID, Hiring.goneElsewhere)
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: 1_000_000), .taken)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testTalkSurvivesASaveAndIsForgottenAfterAWhile() throws {
        var (e, id) = try game()
        let pid = worker(&e, id)
        let ask = e.state.people[pid]!.askingMonthlyWage
        guard case .countered(let c1) = e.hire(personID: pid, companyID: id, monthlyWage: ask * 0.8) else { return XCTFail("counter") }
        let saved = try JSONEncoder().encode(e.state)
        var e2 = e
        e2.update { s, _, _ in s = try! JSONDecoder().decode(GameState.self, from: saved) }
        XCTAssertEqual(e2.state.people[pid]!.value("neg"), e.state.people[pid]!.value("neg"))
        let a = e.hire(personID: pid, companyID: id, monthlyWage: ask * 0.85), b = e2.hire(personID: pid, companyID: id, monthlyWage: ask * 0.85)
        XCTAssertEqual(a, b)
        _ = c1
        var e3 = e2
        e3.update { s, _, _ in s.week += Negotiation.memoryWeeks + 2 }
        let st = Negotiation.State.resume(e3.state.people[pid]!, party: id, week: e3.state.week)
        XCTAssertFalse(st.isOpen)
    }

    func testEveryKindOfHireCountersAndHigherPostsAreMorePatient() throws {
        var (e, id) = try game()
        var rounds: [String: Int] = [:]
        guard let m = e.searchManagers(companyID: id)?.first else { return XCTFail("managers") }
        e.update { s, _, _ in var p = s.people[m.id]!; p.set("pers", "steady"); p.askingMonthlyWage = 10_000_000; s.people[p.id] = p }
        var n = 0
        while n < 40 { let r = e.hireManager(personID: m.id, companyID: id, monthlyWage: 1000); if r == .walkedAway { break }; XCTAssertEqual(r, .refused); n += 1 }
        rounds["manager"] = n
        XCTAssertEqual(e.rentOffice(tier: "home"), .ok)
        guard let md = e.searchExecutive(.md)?.first else { return XCTFail("exec") }
        e.update { s, _, _ in var p = s.people[md.id]!; p.set("pers", "steady"); p.askingMonthlyWage = 10_000_000; s.people[p.id] = p }
        n = 0
        while n < 40 { let r = e.hireExecutive(.md, personID: md.id, monthlyWage: 1000); if r == .walkedAway { break }; XCTAssertEqual(r, .refused); n += 1 }
        rounds["md"] = n
        let w = worker(&e, id, ask: 10_000_000)
        n = 0
        while n < 40 { let r = e.hire(personID: w, companyID: id, monthlyWage: 1000); if r == .walkedAway { break }; XCTAssertEqual(r, .refused); n += 1 }
        rounds["worker"] = n
        XCTAssertLessThan(rounds["worker"]!, rounds["manager"]!)
        XCTAssertLessThan(rounds["manager"]!, rounds["md"]!)
        guard let a = e.searchAssistants(companyID: id)?.first else { return XCTFail("assistants") }
        if case .countered = e.hireAssistant(personID: a.id, companyID: id, monthlyWage: a.askingMonthlyWage * 0.8) {} else { XCTFail("assistant counter") }
        guard let t = e.searchTeam(companyID: id, key: "ceo")?.first else { return XCTFail("team") }
        if case .countered = e.hireTeam(companyID: id, key: "ceo", personID: t.id, monthlyWage: t.askingMonthlyWage * 0.8) {} else { XCTFail("team counter") }
        XCTAssertEqual(e.rentOffice(tier: "small"), .ok)
        guard let o = e.searchOffice(role: "pa", mode: .agency)?.first else { return XCTFail("office") }
        if case .countered = e.hireOffice(role: "pa", personID: o.id, monthlyWage: o.askingMonthlyWage * 0.8) {} else { XCTFail("office counter") }
        let an = e.dataAnalystCandidates()
        if let c = an.first, case .countered = e.hireDataAnalyst(personID: c.id, monthlyWage: c.askingMonthlyWage * 0.8) {} else { XCTFail("analyst counter") }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testGoingRateReadModelForEveryPost() throws {
        let (e, id) = try game()
        let posts: [HirePost] = [.worker(role: "barista"), .manager, .assistant, .team(key: "ops"), .team(key: "ceo"), .executive(.md), .executive(.region), .office(role: "pa"), .analyst]
        for p in posts { XCTAssertGreaterThan(e.goingRate(for: p, companyID: id), 0, "\(p)") }
        XCTAssertGreaterThan(e.goingRate(for: .team(key: "ceo"), companyID: id), e.goingRate(for: .manager, companyID: id))
        XCTAssertGreaterThan(e.goingRate(for: .manager, companyID: id), e.goingRate(for: .assistant, companyID: id))
    }
}
