import XCTest
import GameCore
import Countries
import Finance
import Employees
@testable import Businesses
import Simulation

final class ContractTalkTests: XCTestCase {
    private func shop(_ trade: String = "cafe", country: String = "UK", seed: Int = 5) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: country, playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, fundWith: 30_000_000) else { throw XCTSkip("no company") }
        var days = 0
        while e.state.company(id)?.status != .open, days < 60 * 7 { e.nextDay(); days += 1 }
        e.update { s, _, _ in s.rest["ownHrsFixed"] = true }
        e.update { s, _, _ in if let i = s.companyIndex(id), s.companies[i].value("prem")["kind"].string == "office" || s.companies[i].value("prem")["kind"].isNull { var p = s.companies[i].value("prem"); if p.isNull { p = .object([:]) }; p["m2"] = .number(900); s.companies[i].set("prem", p) } }
        return (e, id)
    }

    private func hire(_ e: inout GameEngine, _ id: Int, role: String = "barista", pers: String = "steady", hours: Double? = nil, needsHours: Double? = nil) -> Int {
        var pid = 0
        e.update { s, d, _ in
            let need = max(hours ?? 0, needsHours ?? 0)
            var p = Hiring.generateCandidate(role: role, company: s.company(id), tier: "mid", state: &s, data: d)
            var tries = 0
            while let cap = Hiring.maxHoursPerWeek(personID: p.id), cap < need, tries < 60 {
                p = Hiring.generateCandidate(role: role, company: s.company(id), tier: "mid", state: &s, data: d); tries += 1
            }
            p.set("pers", pers); p.set("sec", 0.1)
            s.people[p.id] = p; pid = p.id
        }
        let wage = e.state.people[pid]!.askingMonthlyWage * 1.5
        let r = hours.map { e.hire(personID: pid, companyID: id, monthlyWage: wage, terms: Hiring.Terms(hours: $0)) } ?? e.hire(personID: pid, companyID: id, monthlyWage: wage)
        XCTAssertEqual(r, .ok)
        e.update { s, _, _ in var f = s.company(id)!.value("flags"); f["noquit"] = 1; s.companies[s.companyIndex(id)!].set("flags", f) }
        return pid
    }

    private func member(_ e: GameEngine, _ id: Int, _ pid: Int) -> StaffMember? { e.state.company(id)?.staff.first { $0.id == pid } }
    private func wage(_ e: GameEngine, _ id: Int, _ pid: Int) -> Double { member(e, id, pid)?.monthlyWage ?? 0 }

    private func ask(_ e: inout GameEngine, _ id: Int, _ pid: Int, _ topic: ContractTalk.Topic) {
        e.update { s, d, _ in ContractTalk.employeeAsks(&s, companyIndex: s.companyIndex(id)!, staffID: pid, topic: topic, data: d) }
    }

    private func reseed(_ e: inout GameEngine, _ n: Int) { e.update { s, _, _ in s.random = DeterministicRandom(seed: n) } }

    func testARiseYouOfferIsAlwaysTakenWhateverThePerson() throws {
        let (e0, id) = try shop()
        for pers in ["driven", "steady", "loyal", "arrogant", "lazy", "restless"] {
            for pct in [0.03, 0.06, 0.1, 0.25] {
                var e = e0
                let pid = hire(&e, id, pers: pers)
                let before = wage(e, id, pid)
                let r = e.contractPropose(companyID: id, personID: pid, proposal: .init(.payRise, amount: pct))
                guard case .agreed = r else { XCTFail("\(pers) \(pct): a rise is taken, got \(r)"); continue }
                XCTAssertGreaterThan(wage(e, id, pid), before, "\(pers) \(pct)")
                XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
            }
        }
    }

    func testTheirAskAnsweredWithAnyFigureNeverEndsInARefusalOrALowerWage() throws {
        let (e0, id) = try shop()
        for pers in ["driven", "steady", "loyal", "arrogant", "lazy", "restless"] {
            for seed in 1...6 {
                var e = e0
                let pid = hire(&e, id, pers: pers)
                reseed(&e, seed)
                ask(&e, id, pid, .payRise)
                let talk = try XCTUnwrap(e.contractTalk(personID: pid))
                XCTAssertTrue(talk.isRequest)
                let before = wage(e, id, pid)
                var offer = talk.ask * 0.3, rounds = 0, settled = false
                while rounds < 20 {
                    rounds += 1
                    let r = e.contractRespond(companyID: id, personID: pid, decision: .counter(offer))
                    switch r {
                    case .counter(let amount, _, _):
                        XCTAssertGreaterThan(amount, offer, "\(pers): a counter only ever asks for MORE than was offered")
                        XCTAssertGreaterThanOrEqual(wage(e, id, pid), before)
                    case .agreed, .settled:
                        settled = true
                        XCTAssertGreaterThan(wage(e, id, pid), before, "\(pers): the rise is given")
                    default:
                        XCTFail("\(pers) seed \(seed): an employee cannot refuse, walk away or resign over a rise: \(r)")
                    }
                    if settled { break }
                }
                XCTAssertTrue(settled, "\(pers) seed \(seed): the rounds end with them taking what is offered")
                XCTAssertNil(e.contractTalk(personID: pid), "the talk is closed")
                XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
            }
        }
    }

    func testAnOfferAtOrAboveTheirAskIsAgreedAtOnce() throws {
        var (e, id) = try shop()
        let pid = hire(&e, id)
        ask(&e, id, pid, .payRise)
        let talk = try XCTUnwrap(e.contractTalk(personID: pid))
        let before = wage(e, id, pid)
        guard case .agreed = e.contractRespond(companyID: id, personID: pid, decision: .counter(talk.ask * 1.5)) else { return XCTFail("more than they asked is taken") }
        XCTAssertGreaterThan(wage(e, id, pid), before * (1 + talk.ask) - 100)
    }

    func testPatienceAndUnrealisticCountersOfTheDataApplyToTheirAsks() throws {
        let (e0, id) = try shop()
        var above = 0, counters = 0, roundsWorker = 0
        for seed in 1...120 {
            var e = e0
            let pid = hire(&e, id, pers: "arrogant")
            reseed(&e, seed)
            ask(&e, id, pid, .payRise)
            let talk = try XCTUnwrap(e.contractTalk(personID: pid))
            if case .counter(let amount, _, _) = e.contractRespond(companyID: id, personID: pid, decision: .counter(talk.ask * 0.8)) {
                counters += 1
                if amount > talk.ask + 1e-9 { above += 1 }
            }
        }
        XCTAssertGreaterThan(counters, 60)
        XCTAssertGreaterThan(above, 0, "some counters are unrealistic")
        XCTAssertLessThan(Double(above) / Double(counters), 0.6)
        var (e, id2) = try shop(seed: 9)
        let w = hire(&e, id2, pers: "steady")
        reseed(&e, 3); ask(&e, id2, w, .payRise)
        while roundsWorker < 30 {
            roundsWorker += 1
            let r = e.contractRespond(companyID: id2, personID: w, decision: .counter(0.005))
            if r.changedTerms { break }
        }
        let t = try XCTUnwrap(Negotiation.temperament(id: "steady"))
        XCTAssertLessThanOrEqual(roundsWorker, Negotiation.patience(rank: "worker", temperament: t) + 1)
        XCTAssertGreaterThan(Negotiation.patience(rank: "manager", temperament: t), Negotiation.patience(rank: "worker", temperament: t))
    }

    func testCandidatesAndEmployeesNeverRefuseAnOfferAtTheirAsk() throws {
        var (e, id) = try shop()
        for pers in ["driven", "steady", "loyal", "arrogant", "lazy", "restless"] {
            var pid = 0
            e.update { s, d, _ in
                var p = Hiring.generateCandidate(role: "barista", company: s.company(id), tier: "mid", state: &s, data: d)
                p.set("pers", pers); s.people[p.id] = p; pid = p.id
            }
            let ask = try XCTUnwrap(e.hearTheirAsk(post: .worker(role: "barista"), companyID: id, personID: pid))
            XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: ask), .ok, "\(pers): an offer at their ask is accepted")
        }
    }

    func testPromotionTheyAskForMoreButNeverRefuse() throws {
        var (e, id) = try shop()
        let pid = hire(&e, id)
        let post = try XCTUnwrap(ManagerModel.promotionPosts(e.state, companyID: id, personID: pid, data: e.data).first { $0.kind == "mgr" && $0.companyID == id })
        var outcome: ContractTalk.Reply = .notPossible("")
        var counters = 0
        for _ in 0..<20 {
            outcome = e.contractPropose(companyID: id, personID: pid, proposal: .init(.promotion, amount: post.ask * 0.6, choice: post.id))
            if case .counter(let ask, _, _) = outcome { counters += 1; XCTAssertGreaterThanOrEqual(ask, post.ask * 0.6) } else { break }
        }
        guard case .agreed(let text) = outcome else { return XCTFail("they end up taking the post: \(outcome)") }
        XCTAssertGreaterThan(counters, 0, "they asked for more first")
        XCTAssertEqual(e.state.company(id)?.managerID, pid, text)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testPromotionTermsAreCountedInTheirPrice() throws {
        var (e, id) = try shop()
        let pid = hire(&e, id)
        let post = try XCTUnwrap(ManagerModel.promotionPosts(e.state, companyID: id, personID: pid, data: e.data).first { $0.kind == "mgr" && $0.companyID == id })
        let full = ManagerModel.promotionNeed(post, terms: .init(authority: 2))
        let limited = ManagerModel.promotionNeed(post, terms: .init(authority: 1))
        XCTAssertLessThan(full, limited)
        let preview = e.contractPreview(companyID: id, personID: pid, proposal: .init(.promotion, amount: post.ask, choice: post.id, terms: .init(authority: 2)))
        XCTAssertTrue(preview.blocked.isEmpty)
        XCTAssertTrue(preview.lines.contains { $0.contains("New post") })
        XCTAssertTrue(preview.lines.contains { $0.contains("Budget free") && $0.contains("decides on their own") }, "the budget term is stated in the preview")
    }

    func testHoursSetFullTimeAndSeasons() throws {
        var (e, id) = try shop()
        let a = hire(&e, id, hours: 20, needsHours: 30)
        let before = wage(e, id, a)
        if e.state.people[a]!.num("maxH", 60) >= 30 || member(e, id, a)!.num("maxH", 60) >= 30 {
            guard case .agreed = e.contractPropose(companyID: id, personID: a, proposal: .init(.hours, amount: 30, choice: "hours")) else { return XCTFail("more hours") }
            XCTAssertEqual(wage(e, id, a), before * 30 / 20, accuracy: 1e-6, "pay follows the hours")
        }
        let f = e.contractPropose(companyID: id, personID: a, proposal: .init(.hours, choice: "full"))
        switch f { case .agreed, .unwilling, .notPossible: break; default: XCTFail("\(f)") }
        let b = hire(&e, id, hours: 25)
        e.update { s, _, _ in
            let k = s.companies[s.companyIndex(id)!].staff.firstIndex { $0.id == b }!
            var st = s.companies[s.companyIndex(id)!].staff; st[k].set("seas", .array([.number(6), .number(7)])); s.companies[s.companyIndex(id)!].staff = st
        }
        guard case .agreed = e.contractPropose(companyID: id, personID: b, proposal: .init(.hours, choice: "season:autumn")) else { return XCTFail("season") }
        XCTAssertTrue(member(e, id, b)!.value("seas").array.map { $0.int }.contains(9))
        let part = e.contractPropose(companyID: id, personID: b, proposal: .init(.hours, choice: "part"))
        switch part { case .agreed, .unwilling: break; default: XCTFail("\(part)") }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testTheirRequestForShorterHoursAndTheAnswers() throws {
        let (e0, id) = try shop()
        var e = e0
        let pid = hire(&e, id)
        e.update { s, _, _ in
            let ci = s.companyIndex(id)!
            let k = s.companies[ci].staff.firstIndex { $0.id == pid }!
            var st = s.companies[ci].staff; st[k].tiredness = 70; s.companies[ci].staff = st
        }
        let m = member(e, id, pid)!
        XCTAssertEqual(ContractTalk.requestTrigger(m, e.state.people[pid]!, company: e.state.company(id)!, week: e.state.week, salesRoles: e.salesRoles, tenure: 0), .hoursAsk(staffID: pid))
        ask(&e, id, pid, .hours)
        let talk = try XCTUnwrap(e.contractTalk(personID: pid))
        XCTAssertEqual(talk.proposal.topic, .hours)
        XCTAssertLessThan(talk.proposal.amount, StaffModel.fullWeekHours)
        guard case .agreed = e.contractRespond(companyID: id, personID: pid, decision: .accept) else { return XCTFail("agreed") }
        XCTAssertEqual(member(e, id, pid)?.weeklyHours, talk.proposal.amount)
        XCTAssertNil(e.contractTalk(personID: pid))
    }

    func testPayBasisFixedMixCommissionAndTheSalaryForAnHourlyWorker() throws {
        var (e, id) = try shop("estate")
        let pid = hire(&e, id, role: "estate")
        var mix = false
        for _ in 0..<12 where !mix {
            switch e.contractPropose(companyID: id, personID: pid, proposal: .init(.payBasis, amount: 0.05, choice: "mix")) {
            case .agreed: mix = true
            case .unwilling: e.update { s, _, _ in s.week += 8 }
            default: return XCTFail("mix")
            }
        }
        XCTAssertTrue(mix, "mix is agreed in some block")
        XCTAssertEqual(member(e, id, pid)?.commissionMode, "mix")
        XCTAssertEqual(member(e, id, pid)?.commissionRate ?? 0, 0.05, accuracy: 1e-9)
        XCTAssertGreaterThan(wage(e, id, pid), 0)
        var com = false
        for _ in 0..<12 where !com {
            switch e.contractPropose(companyID: id, personID: pid, proposal: .init(.payBasis, choice: "com")) {
            case .agreed: com = true
            case .unwilling: e.update { s, _, _ in s.week += 8 }
            default: return XCTFail("com")
            }
        }
        XCTAssertTrue(com, "com is agreed in some block")
        XCTAssertEqual(wage(e, id, pid), 0, "commission only: nothing in base")
        guard case .agreed = e.contractPropose(companyID: id, personID: pid, proposal: .init(.payBasis, choice: "fix")) else { return XCTFail("fix is a rise and is never refused") }
        XCTAssertGreaterThan(wage(e, id, pid), 0)
        let sec = hire(&e, id, role: "estate")
        e.update { s, _, _ in s.people[sec]!.set("sec", 0.9) }
        let pv = e.contractPreview(companyID: id, personID: sec, proposal: .init(.payBasis, choice: "com"))
        XCTAssertTrue(pv.risks.contains { $0.contains("security") })
        let (e2, id2) = try shop()
        var c = e2
        let w = hire(&c, id2)
        XCTAssertEqual(member(c, id2, w)?.payBasis, "hour")
        guard case .agreed = c.contractPropose(companyID: id2, personID: w, proposal: .init(.payBasis, choice: "salary")) else { return XCTFail("salary") }
        XCTAssertEqual(member(c, id2, w)?.payBasis, "fix")
    }

    func testBonusPlanForAManagerAndForASeller() throws {
        var (e, id) = try shop("estate")
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: id, monthlyWage: cands[0].askingMonthlyWage * 1.3), .ok)
        let mgr = cands[0].id
        guard case .agreed = e.contractPropose(companyID: id, personID: mgr, proposal: .init(.bonus, amount: 0.1)) else { return XCTFail("share") }
        XCTAssertEqual(e.state.company(id)?.managerProfitBonus ?? 0, 0.1, accuracy: 1e-9)
        guard case .notPossible = e.contractPropose(companyID: id, personID: mgr, proposal: .init(.bonus, amount: 0.05)) else { return XCTFail("no cut here") }
        let agent = hire(&e, id, role: "estate")
        guard case .notPossible = e.contractPropose(companyID: id, personID: agent, proposal: .init(.bonus, amount: 0.05)) else { return XCTFail("fixed pay has no plan") }
        e.update { s, _, _ in
            var p = s.people[agent]!; p.set("pers", "loyal"); s.people[agent] = p
            let ci = s.companyIndex(id)!, k = s.companies[ci].staff.firstIndex { $0.id == agent }!
            var st = s.companies[ci].staff; st[k].happyUntilWeek = s.week + 40; s.companies[ci].staff = st
        }
        _ = e.contractPropose(companyID: id, personID: agent, proposal: .init(.payBasis, choice: "mix"))
        guard case .agreed = e.contractPropose(companyID: id, personID: agent, proposal: .init(.bonus, amount: 0.08)) else { return XCTFail("rate") }
        XCTAssertEqual(member(e, id, agent)?.commissionRate ?? 0, 0.08, accuracy: 1e-9)
    }

    func testBenefitsAreCompanyWidePerksAndOwnCarWithMileage() throws {
        var (e, id) = try shop("estate")
        let a = hire(&e, id, role: "estate"), b = hire(&e, id, role: "estate")
        let pv = e.contractPreview(companyID: id, personID: a, proposal: .init(.benefits, amount: 1, choice: "perk:health"))
        let co = e.state.company(id)!
        let cur = World(state: e.state, data: e.data).currency(co)
        XCTAssertEqual(pv.costPerMonth, StaffPerks.monthlyCost(co, StaffPerks.perk("health")!, currency: cur), accuracy: 0.01)
        XCTAssertTrue(pv.peers.contains { $0.contains("everyone") }, "the peers are named: it covers all")
        guard case .agreed = e.contractPropose(companyID: id, personID: a, proposal: .init(.benefits, amount: 1, choice: "perk:health")) else { return XCTFail("on") }
        XCTAssertTrue(StaffPerks.isOn(e.state.company(id)!, "health"))
        guard case .agreed = e.contractPropose(companyID: id, personID: b, proposal: .init(.benefits, amount: 0, choice: "perk:health")) else { return XCTFail("off") }
        XCTAssertFalse(StaffPerks.isOn(e.state.company(id)!, "health"))
        let car = e.contractPreview(companyID: id, personID: a, proposal: .init(.benefits, amount: 1, choice: "ownCar"))
        XCTAssertEqual(car.costPerMonth, PersonalEquipment.mileagePerMonth(cur, country: World(state: e.state, data: e.data).country(co), e.data.catalog["estate"]!, tables: e.data.catalog.tables), accuracy: 0.01)
        guard case .agreed = e.contractPropose(companyID: id, personID: a, proposal: .init(.benefits, amount: 1, choice: "ownCar")) else { return XCTFail("car") }
        XCTAssertTrue(member(e, id, a)!.flag("ownCar"))
        let cafeHand = try shop()
        var c = cafeHand.0
        let w = hire(&c, cafeHand.1)
        guard case .notPossible = c.contractPropose(companyID: cafeHand.1, personID: w, proposal: .init(.benefits, amount: 1, choice: "ownCar")) else { return XCTFail("estate agents only") }
    }

    func testNoticeIsOwedBothWays() throws {
        var (e, id) = try shop()
        let pid = hire(&e, id)
        e.update { s, _, _ in
            let ci = s.companyIndex(id)!
            let k = s.companies[ci].staff.firstIndex { $0.id == pid }!
            var st = s.companies[ci].staff; st[k].hiredWeek = s.week - 200; s.companies[ci].staff = st
        }
        let q0 = try XCTUnwrap(Dismissal.quote(e.state, companyID: id, staffID: pid, reason: .unjustified, data: e.data))
        let pv = e.contractPreview(companyID: id, personID: pid, proposal: .init(.notice, amount: 8))
        XCTAssertTrue(pv.labour.contains { $0.contains("Notice by law") }, "the country's notice rule is shown")
        guard case .notPossible = e.contractPropose(companyID: id, personID: pid, proposal: .init(.notice, amount: 5)) else { return XCTFail("only the weeks the data offers") }
        guard case .agreed = e.contractPropose(companyID: id, personID: pid, proposal: .init(.notice, amount: 8)) else { return XCTFail("notice") }
        XCTAssertEqual(member(e, id, pid)?.int("nx"), 8)
        let q1 = try XCTUnwrap(Dismissal.quote(e.state, companyID: id, staffID: pid, reason: .unjustified, data: e.data))
        let w = World(state: e.state, data: e.data), co = e.state.company(id)!
        let extra = wage(e, id, pid) * 12 / 52 * 8 * (1 + w.country(co).employerOnCost(monthlyWage: wage(e, id, pid)))
        XCTAssertEqual(q1.notice - q0.notice, extra, accuracy: 0.01, "you pay the extra weeks when you let them go without cause")
        e.update { s, d, _ in StaffRoutine.handle(&s, companyIndex: s.companyIndex(id)!, .quit(staffID: pid), data: d) }
        XCTAssertEqual(member(e, id, pid)?.noticeWeeks, 8 + 8, "eight weeks for years of service, plus the eight agreed")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testMoveToAnotherStoreOfTheChainAndAManagerToACompanyWithoutOne() throws {
        for seed in 5..<45 { if try moveScenario(seed: seed) { return } }
        XCTFail("no seed in which both the worker and the manager agree to move")
    }

    private func moveScenario(seed: Int) throws -> Bool {
        var (e, a) = try shop(seed: seed)
        guard case .success(let b) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, fundWith: 20_000_000) else { XCTFail("second store"); return false }
        e.update { s, d, _ in
            for id in [a, b] { var docs = s.company(id)!.value("docs"); docs["chain"] = .object(["st": "ok", "done": 0, "ok": 0]); s.companies[s.companyIndex(id)!].set("docs", docs) }
            let chain = Chains.make(&s, companyID: a, name: "Beans") ?? 0
            Chains.join(&s, chainID: chain, companyID: b, rename: false, data: d)
        }
        let pid = hire(&e, a)
        let topics = e.contractTopics(companyID: a, personID: pid)
        XCTAssertTrue(topics.first { $0.topic == .move }?.available == true)
        XCTAssertEqual(e.contractChoices(companyID: a, personID: pid, topic: .move).map { $0.id }, ["\(b)"])
        let pv = e.contractPreview(companyID: a, personID: pid, proposal: .init(.move, choice: "\(b)"))
        XCTAssertTrue(pv.blocked.isEmpty)
        XCTAssertEqual(pv.costPerMonth, 0, accuracy: 0.01, "the move shifts the cost, it does not add any")
        guard case .agreed = e.contractPropose(companyID: a, personID: pid, proposal: .init(.move, choice: "\(b)")) else { return false }
        XCTAssertNil(member(e, a, pid)); XCTAssertNotNil(member(e, b, pid))
        XCTAssertEqual(e.state.people[pid]?.employerID, b)
        let cands = try XCTUnwrap(e.searchManagers(companyID: a))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: a, monthlyWage: cands[0].askingMonthlyWage * 1.3), .ok)
        guard case .agreed = e.contractPropose(companyID: a, personID: cands[0].id, proposal: .init(.move, choice: "\(b)")) else { return false }
        XCTAssertEqual(e.state.company(b)?.managerID, cands[0].id)
        XCTAssertNil(e.state.company(a)?.managerID)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        return true
    }

    func testTopicsListWhatCanReallyBeDiscussed() throws {
        var (e, id) = try shop()
        let pid = hire(&e, id)
        let t = Dictionary(uniqueKeysWithValues: e.contractTopics(companyID: id, personID: pid).map { ($0.topic, $0) })
        XCTAssertEqual(Set(t.keys), Set(ContractTalk.Topic.allCases))
        XCTAssertTrue(t[.payRise]!.available && t[.hours]!.available && t[.benefits]!.available && t[.notice]!.available)
        XCTAssertTrue(t[.bonus]!.available, "every worker can be put on a bonus plan (WorkerBonus)")
        XCTAssertFalse(t[.move]!.available, "no other store")
        XCTAssertFalse(t[.move]!.why.isEmpty)
    }

    func testPreviewIsADryRunWithCostRiskAndLabourRules() throws {
        var (e, id) = try shop()
        let pid = hire(&e, id)
        let state0 = e.state
        let pv = e.contractPreview(companyID: id, personID: pid, proposal: .init(.payRise, amount: 0.1))
        XCTAssertTrue(e.state == state0, "a preview changes nothing")
        let w = World(state: e.state, data: e.data), co = e.state.company(id)!
        let m = member(e, id, pid)!
        XCTAssertEqual(pv.costPerMonth, (wage(e, id, pid) * 0.1) * (1 + w.country(co).employerOnCost(monthlyWage: m.monthlyWage * 1.1)), accuracy: wage(e, id, pid) * 0.03)
        XCTAssertGreaterThan(pv.costPerMonth, 0)
        let before = try XCTUnwrap(pv.quitRiskBefore), after = try XCTUnwrap(pv.quitRiskAfter)
        XCTAssertTrue(after == before || after == .unlikely || (before == .likely && after == .possible), "pay that is closer to the market does not make leaving likelier")
        XCTAssertFalse(pv.lines.joined().contains("%") && pv.lines.joined().lowercased().contains("chance"), "no probabilities in the text")
        XCTAssertTrue(pv.labour.contains { $0.contains("minimum pay") }, "the UK data has a minimum wage")
        XCTAssertTrue(pv.lines.contains { $0.hasPrefix("Pay:") })
        let blocked = e.contractPreview(companyID: id, personID: 999_999, proposal: .init(.payRise, amount: 0.1))
        XCTAssertFalse(blocked.blocked.isEmpty)
    }

    func testPreviewShowsTheLabourRulesOfAnotherCountryFromItsData() throws {
        for code in ["US", "MX", "PL"] {
            var (e, id) = try shop(country: code)
            let pid = hire(&e, id)
            let pv = e.contractPreview(companyID: id, personID: pid, proposal: .init(.notice, amount: 4))
            let lab = World(state: e.state, data: e.data).labour(e.state.company(id)!)
            XCTAssertEqual(pv.labour.contains { $0.contains("minimum pay") }, lab.hasMinimum, code)
            XCTAssertTrue(pv.labour.contains { $0.contains("Notice by law") }, code)
        }
    }

    func testDecliningAFairRequestCostsMoraleAndRetentionAndIsShownFirst() throws {
        var (e, id) = try shop()
        let pid = hire(&e, id, pers: "restless")
        ask(&e, id, pid, .payRise)
        let talk = try XCTUnwrap(e.contractTalk(personID: pid))
        let pv = e.contractPreview(companyID: id, personID: pid, proposal: talk.proposal, asRequest: true)
        let declinedRisk = try XCTUnwrap(pv.quitRiskIfDeclined)
        let declined = try XCTUnwrap(ContractTalk.quitYear(e.state, companyID: id, personID: pid, data: e.data, declined: true))
        XCTAssertGreaterThan(declined, try XCTUnwrap(ContractTalk.quitYear(e.state, companyID: id, personID: pid, data: e.data)))
        XCTAssertEqual(declinedRisk, ContractTalk.QuitRisk.band(declined))
        XCTAssertTrue(pv.risks.contains { $0.contains("If you decline") })
        guard case .declined(let text) = e.contractRespond(companyID: id, personID: pid, decision: .decline) else { return XCTFail("declined") }
        XCTAssertFalse(text.isEmpty)
        let m = try XCTUnwrap(member(e, id, pid))
        XCTAssertEqual(m.int("denied"), e.state.week, "the old mark of a refused raise")
        XCTAssertEqual(m.happyUntilWeek, 0)
        XCTAssertTrue(StaffProfile.mood(e.state, companyID: id, staffID: pid, data: e.data)!.bad.contains { $0.contains("turned down") })
        let after = try XCTUnwrap(ContractTalk.quitYear(e.state, companyID: id, personID: pid, data: e.data))
        XCTAssertEqual(after, declined, accuracy: 1e-9, "the preview told the truth")
        XCTAssertNil(e.contractTalk(personID: pid))
        XCTAssertEqual(wage(e, id, pid), wage(e, id, pid))
    }

    func testDelayingIsRememberedAndAMissedAnswerCountsAsADecline() throws {
        var (e, id) = try shop()
        let pid = hire(&e, id)
        ask(&e, id, pid, .payRise)
        guard case .delayed(let until, _) = e.contractRespond(companyID: id, personID: pid, decision: .delay) else { return XCTFail("delayed") }
        XCTAssertEqual(until, e.state.week + ContractTalk.delayWeeks)
        XCTAssertEqual(e.contractTalk(personID: pid)?.delayUntil, until)
        XCTAssertEqual(member(e, id, pid)?.int("denied"), 0, "nothing yet")
        for _ in 0..<((ContractTalk.delayWeeks + 1) * 7) { e.nextDay() }
        if member(e, id, pid) != nil {
            XCTAssertNil(e.contractTalk(personID: pid))
            XCTAssertGreaterThan(member(e, id, pid)?.int("denied") ?? 0, 0, "the answer never came: they feel turned down")
        }
    }

    func testARequestNobodyTouchesIsForgottenWithoutPenalty() throws {
        var (e, id) = try shop()
        let pid = hire(&e, id)
        ask(&e, id, pid, .payRise)
        XCTAssertNotNil(e.contractTalk(personID: pid))
        let asked = e.state.week
        for _ in 0..<((Negotiation.memoryWeeks + 2) * 7) { e.nextDay() }
        if let again = e.contractTalk(personID: pid) { XCTAssertGreaterThan(again.week, asked, "the old request is gone") }
        XCTAssertEqual(member(e, id, pid)?.int("denied") ?? 0, 0)
    }

    func testInboxOptionsAreTheSameEnginePathAsTheDiscussion() throws {
        var (e, id) = try shop()
        let pid = hire(&e, id)
        ask(&e, id, pid, .payRise)
        let m = try XCTUnwrap(e.openDecisions.first { $0.actionID == "staffx" })
        XCTAssertEqual(m.value("opts").array.count, 3, "agree, delay, decline")
        let before = wage(e, id, pid)
        XCTAssertTrue(e.answer(messageID: m.id, option: 0))
        XCTAssertGreaterThan(wage(e, id, pid), before)
        XCTAssertGreaterThan(member(e, id, pid)?.happyUntilWeek ?? 0, e.state.week)
        XCTAssertNil(e.contractTalk(personID: pid))
    }

    func testPromotionRequestFromAnAmbitiousWorker() throws {
        var (e, id) = try shop()
        let pid = hire(&e, id, pers: "driven")
        e.update { s, _, _ in
            let ci = s.companyIndex(id)!
            let k = s.companies[ci].staff.firstIndex { $0.id == pid }!
            var st = s.companies[ci].staff; st[k].skillGain = 40; s.companies[ci].staff = st
            var n = s.people[pid]!; n.skill = max(n.skill, 70); s.people[pid] = n
        }
        let ev = ContractTalk.requestTrigger(member(e, id, pid)!, e.state.people[pid]!, company: e.state.company(id)!, week: e.state.week, salesRoles: e.salesRoles, tenure: 60)
        XCTAssertEqual(ev, .promotionAsk(staffID: pid))
        ask(&e, id, pid, .promotion)
        let talk = try XCTUnwrap(e.contractTalk(personID: pid), "a driven, skilled worker asks for the next role")
        XCTAssertEqual(talk.proposal.topic, .promotion)
        guard case .counter(let want, _, _) = e.contractRespond(companyID: id, personID: pid, decision: .counter(talk.proposal.amount * 0.5)) else { return XCTFail("they ask for more") }
        XCTAssertGreaterThanOrEqual(want, talk.proposal.amount * 0.5)
        guard case .agreed = e.contractRespond(companyID: id, personID: pid, decision: .accept) else { return XCTFail("accept") }
        XCTAssertNotEqual(member(e, id, pid)?.role, "barista")
    }

    func testAManagerHandlesRequestsInsideTheirBudgetOnly() throws {
        var (e, id) = try shop()
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: id, monthlyWage: cands[0].askingMonthlyWage * 1.3), .ok)
        let pid = hire(&e, id)
        ask(&e, id, pid, .payRise)
        e.setManagerAuthority(companyID: id, level: 0)
        XCTAssertNil(e.contractHandler(companyID: id))
        guard case .notPossible = e.contractLeaveToManager(companyID: id, personID: pid) else { return XCTFail("no authority") }
        e.setManagerBudget(companyID: id, budget: .normal)
        let h = try XCTUnwrap(e.contractHandler(companyID: id))
        XCTAssertEqual(h.level, 1)
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertFalse(ContractTalk.managerMayDecide(co, extraMonthly: h.payLimit * 2, e.state, data: e.data))
        XCTAssertTrue(ContractTalk.managerMayDecide(co, extraMonthly: h.payLimit / 2, e.state, data: e.data))
        let before = wage(e, id, pid)
        guard case .agreed = e.contractLeaveToManager(companyID: id, personID: pid) else { return XCTFail("inside the budget") }
        XCTAssertGreaterThan(wage(e, id, pid), before)
    }

    func testAnOpenTalkSurvivesASaveAndContinuesTheSame() throws {
        var (e, id) = try shop()
        let pid = hire(&e, id, pers: "arrogant")
        reseed(&e, 4)
        ask(&e, id, pid, .payRise)
        let talk0 = try XCTUnwrap(e.contractTalk(personID: pid))
        guard case .counter = e.contractRespond(companyID: id, personID: pid, decision: .counter(talk0.ask * 0.4)) else { return XCTFail("counter") }
        let open = try XCTUnwrap(e.contractTalk(personID: pid))
        XCTAssertTrue(open.neg.isOpen)
        let saved = try JSONEncoder().encode(e.state)
        var e2 = e
        e2.update { s, _, _ in s = (try? JSONDecoder().decode(GameState.self, from: saved)) ?? s }
        XCTAssertEqual(e2.contractTalk(personID: pid), open, "the open talk is in the save")
        XCTAssertEqual(e2.state.random, e.state.random)
        let r1 = e.contractRespond(companyID: id, personID: pid, decision: .counter(talk0.ask * 0.6))
        let r2 = e2.contractRespond(companyID: id, personID: pid, decision: .counter(talk0.ask * 0.6))
        XCTAssertEqual(r1, r2, "the same reply from the loaded game")
        XCTAssertEqual(e.contractTalk(personID: pid), e2.contractTalk(personID: pid))
    }

    func testAnOpenPromotionTalkSurvivesASave() throws {
        var (e, id) = try shop()
        let pid = hire(&e, id)
        let post = try XCTUnwrap(ManagerModel.promotionPosts(e.state, companyID: id, personID: pid, data: e.data).first { $0.kind == "mgr" && $0.companyID == id })
        guard case .counter = e.contractPropose(companyID: id, personID: pid, proposal: .init(.promotion, amount: post.ask * 0.6, choice: post.id, terms: .init(authority: 2))) else { return XCTFail("counter") }
        let open = try XCTUnwrap(e.contractTalk(personID: pid))
        let back = try JSONDecoder().decode(GameState.self, from: try JSONEncoder().encode(e.state))
        XCTAssertEqual(ContractTalk.openTalk(back, personID: pid), open)
        XCTAssertEqual(open.proposal.terms.authority, 2)
    }

    func testBooksStayBalancedThroughEveryTopic() throws {
        var (e, id) = try shop("estate")
        let pid = hire(&e, id, role: "estate")
        _ = e.contractPropose(companyID: id, personID: pid, proposal: .init(.payRise, amount: 0.05))
        _ = e.contractPropose(companyID: id, personID: pid, proposal: .init(.payBasis, amount: 0.04, choice: "mix"))
        _ = e.contractPropose(companyID: id, personID: pid, proposal: .init(.benefits, amount: 1, choice: "perk:gym"))
        _ = e.contractPropose(companyID: id, personID: pid, proposal: .init(.notice, amount: 4))
        _ = e.contractPropose(companyID: id, personID: pid, proposal: .init(.hours, amount: 30, choice: "hours"))
        for _ in 0..<(8 * 7) { e.nextDay() }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    private var engineRoot: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    private func swiftFiles(under dir: URL) -> [URL] {
        (FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []).filter { $0.pathExtension == "swift" }
    }

    func testTheSupersededButtonsAndPathsAreGone() throws {
        let sources = engineRoot.appendingPathComponent("Sources")
        let gone = ["func raise(personID", "func giveManagerRaise", "func offerPromotion(companyID", "func setPayModel(companyID", "func setCommissionRate(companyID", "func offerFullTime(companyID",
                    "func offerPartTime(companyID", "func setStaffHours(companyID", "func offerFixedSalary(companyID", "func toggleSeason(companyID", "func toggleOwnCar(companyID",
                    "func moveManager(", "func setManagerProfitBonus(companyID", "func promotionPosts(companyID", "func refusalReason(", "negotiateRaise", "declinedForGood", "func tooLow(",
                    "promoPat", "will not talk about pay any more"]
        for f in swiftFiles(under: sources) {
            let text = try String(contentsOf: f, encoding: .utf8)
            for g in gone { XCTAssertFalse(text.contains(g), "\(f.lastPathComponent) still has \(g)") }
        }
        let callers: [String: [String]] = ["StaffTalks.raise(": ["ContractTalk.swift", "ManagerWeek.swift", "StaffTalks.swift"], "ManagerModel.offerPromotion(": ["ContractTalk.swift"],
                                           "StaffProfile.setPayModel(": ["ContractTalk.swift"], "ManagerModel.raiseManager(": ["ContractTalk.swift"],
                                           "StaffTalks.setStaffHours(": ["ContractTalk.swift"], "StaffTalks.offerFullTime(": ["ContractTalk.swift"]]
        for f in swiftFiles(under: sources) {
            let text = try String(contentsOf: f, encoding: .utf8)
            for (call, allowed) in callers where text.contains(call) { XCTAssertTrue(allowed.contains(f.lastPathComponent), "\(f.lastPathComponent) calls \(call) outside the contract talk") }
        }
        let app = engineRoot.deletingLastPathComponent().appendingPathComponent("App")
        guard FileManager.default.fileExists(atPath: app.path) else { return }
        let appGone = ["raise(personID", "giveManagerRaise", "offerPromotion(", "setPayModel(", "setCommissionRate(", "offerFullTime(", "offerPartTime(", "setStaffHours(", "offerFixedSalary(",
                       "toggleSeason(", "toggleOwnCar(", "moveManager(", "setManagerProfitBonus(", "promotionPosts(", "PromotionSheet", "StaffContractMenu", "Give a raise", "Promote…"]
        var uses = 0
        for f in swiftFiles(under: app) {
            let text = try String(contentsOf: f, encoding: .utf8)
            for g in appGone { XCTAssertFalse(text.contains(g), "\(f.lastPathComponent) still has \(g)") }
            if text.contains("contractPropose(") || text.contains("contractRespond(") { uses += 1; XCTAssertEqual(f.lastPathComponent, "ContractDiscussionView.swift", "one surface") }
        }
        XCTAssertEqual(uses, 1, "exactly one screen talks to the contract engine")
    }

    func testNoEmployeeRefusalOfAPayRiseIsLeftInTheCode() throws {
        let b = engineRoot.appendingPathComponent("Sources/Businesses")
        let talks = try String(contentsOf: b.appendingPathComponent("StaffTalks.swift"), encoding: .utf8)
        XCTAssertFalse(talks.contains("took that offer as an insult"))
        let manager = try String(contentsOf: b.appendingPathComponent("ManagerWeek.swift"), encoding: .utf8)
        XCTAssertFalse(manager.contains("the rival's offer was too good to turn down"), "matching a rival's offer keeps the manager")
        let contract = try String(contentsOf: b.appendingPathComponent("ContractTalk.swift"), encoding: .utf8)
        XCTAssertTrue(contract.contains("case .walkAway: return take(true)"), "when their patience is gone they take the offer")
    }

    func testTheMessageRaisesNothingForAGoneEmployee() throws {
        var (e, id) = try shop()
        let pid = hire(&e, id)
        ask(&e, id, pid, .payRise)
        let m = try XCTUnwrap(e.openDecisions.first { $0.actionID == "staffx" })
        e.update { s, d, _ in _ = Dismissal.dismiss(&s, companyID: id, staffID: pid, data: d) }
        _ = e.answer(messageID: m.id, option: 0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testPayRequestsAreCappedPerCompanyAndWeek() throws {
        var (e, id) = try shop()
        var ids: [Int] = []
        for _ in 0..<5 { ids.append(hire(&e, id)) }
        e.update { s, d, _ in
            let i = s.companyIndex(id)!
            s.companies[i].managerID = nil
            for sid in ids { StaffRoutine.handle(&s, companyIndex: i, .payAsk(staffID: sid), data: d) }
        }
        let wk = e.state.week
        let asks = e.state.inbox.filter { $0.companyID == id && $0.actionID == "staffx" && $0.week == wk }
        XCTAssertEqual(asks.count, StaffTalks.maxAsksPerWeek)
        e.update { s, d, _ in
            s.week += 1
            let i = s.companyIndex(id)!
            for sid in ids { StaffRoutine.handle(&s, companyIndex: i, .payAsk(staffID: sid), data: d) }
        }
        XCTAssertEqual(e.state.inbox.filter { $0.companyID == id && $0.actionID == "staffx" && $0.week == wk + 1 }.count, StaffTalks.maxAsksPerWeek, "the next two ask the following week")
    }
}
