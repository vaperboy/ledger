import XCTest
import GameCore
import Countries
import Employees
import Finance
@testable import Businesses
import Simulation

/// Fixed-term contracts: a topic of the contract discussion and a term of the hire offer; renewal asked in the Inbox before the end date; the job ends on
/// the date at the cost the country's labour data gives for it (nothing where it lists none).
final class FixedTermTests: XCTestCase {
    private func shop(seed: Int = 5) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 30_000_000) else { throw XCTSkip("no company") }
        var days = 0
        while e.state.company(id)?.status != .open, days < 60 * 7 { e.nextDay(); days += 1 }
        return (e, id)
    }

    private func hire(_ e: inout GameEngine, _ id: Int, sec: Double = 0.1, terms: Hiring.Terms = Hiring.Terms()) -> (Int, Hiring.HireResult) {
        var pid = 0
        e.update { s, d, _ in
            var p = Hiring.generateCandidate(role: "barista", company: s.company(id), tier: "mid", state: &s, data: d)
            p.set("pers", "steady"); p.set("sec", sec)
            s.people[p.id] = p; pid = p.id
        }
        let r = e.hire(personID: pid, companyID: id, monthlyWage: e.state.people[pid]!.askingMonthlyWage * 1.5, terms: terms)
        e.update { s, _, _ in var f = s.company(id)!.value("flags"); f["noquit"] = 1; s.companies[s.companyIndex(id)!].set("flags", f) }
        return (pid, r)
    }
    private func member(_ e: GameEngine, _ id: Int, _ pid: Int) -> StaffMember? { e.state.company(id)?.staff.first { $0.id == pid } }

    func testTheTermIsATopicForWorkersOnlyAndNothingIsStoredForPermanent() throws {
        var (e, id) = try shop()
        let (pid, r) = hire(&e, id)
        XCTAssertEqual(r, .ok)
        XCTAssertNil(member(e, id, pid)?.raw["ft"])
        let t = Dictionary(uniqueKeysWithValues: e.contractTopics(companyID: id, personID: pid).map { ($0.topic, $0) })
        XCTAssertEqual(t[.term]?.available, true)
        XCTAssertEqual(e.contractChoices(companyID: id, personID: pid, topic: .term).map { $0.id }, ["perm", "fixed:26", "fixed:52", "fixed:104"])
        let pv = e.contractPreview(companyID: id, personID: pid, proposal: .init(.term, choice: "fixed:52"))
        XCTAssertTrue(pv.lines.contains { $0.contains("Fixed term until week") })
        XCTAssertTrue(pv.labour.contains { $0.contains("nothing is owed") }, "\(pv.labour)")
        guard case .agreed = e.contractPropose(companyID: id, personID: pid, proposal: .init(.term, choice: "fixed:52")) else { return XCTFail("fixed") }
        XCTAssertEqual(member(e, id, pid)?.raw["ft"].map { $0.int }, e.state.week + 52)
        // a renewal adds to the end date
        guard case .agreed = e.contractPropose(companyID: id, personID: pid, proposal: .init(.term, choice: "fixed:26")) else { return XCTFail("renew") }
        XCTAssertEqual(member(e, id, pid)?.raw["ft"].map { $0.int }, e.state.week + 78)
        guard case .agreed = e.contractPropose(companyID: id, personID: pid, proposal: .init(.term, choice: "perm")) else { return XCTFail("perm") }
        XCTAssertNil(member(e, id, pid)?.raw["ft"]); XCTAssertNil(member(e, id, pid)?.raw["ftl"])
    }

    func testSomeoneWhoWantsSecurityIsUnwillingAboutAFixedTerm() throws {
        var (e, id) = try shop()
        let (pid, _) = hire(&e, id, sec: 0.9)
        guard case .unwilling = e.contractPropose(companyID: id, personID: pid, proposal: .init(.term, choice: "fixed:52")) else { return XCTFail("unwilling") }
        XCTAssertNil(member(e, id, pid)?.raw["ft"])
        let (p2, r2) = hire(&e, id, sec: 0.9, terms: Hiring.Terms(fixedTermWeeks: 52))
        XCTAssertEqual(r2, .planRefused); XCTAssertEqual(e.state.people[p2]?.employerID, 0)
    }

    func testTheTermIsPartOfTheHireOffer() throws {
        var (e, id) = try shop()
        let (pid, r) = hire(&e, id, terms: Hiring.Terms(fixedTermWeeks: 26))
        XCTAssertEqual(r, .ok)
        XCTAssertEqual(member(e, id, pid)?.raw["ft"].map { $0.int }, e.state.week + 26)
        XCTAssertEqual(member(e, id, pid)?.int("ftl"), 26)
    }

    func testRenewalIsAskedBeforeTheEndAndAnAnswerIsApplied() throws {
        var (e, id) = try shop()
        let (pid, _) = hire(&e, id)
        _ = e.contractPropose(companyID: id, personID: pid, proposal: .init(.term, choice: "fixed:26"))
        e.update { s, _, _ in
            let ci = s.companyIndex(id)!
            var st = s.companies[ci].staff; let k = st.firstIndex { $0.id == pid }!; st[k].set("ft", s.week + 3); s.companies[ci].staff = st
            FixedTerm.weekly(&s, data: GameData.bundledForTests)
        }
        let msg = try XCTUnwrap(e.openDecisions.first { $0.actionID == FixedTerm.action })
        XCTAssertEqual(msg.value("opts").array.count, 2)
        e.update { s, d, _ in FixedTerm.weekly(&s, data: d) }
        XCTAssertEqual(e.openDecisions.filter { $0.actionID == FixedTerm.action }.count, 1, "asked once")
        let end0 = member(e, id, pid)!.int("ft")
        XCTAssertTrue(e.answer(messageID: msg.id, option: 0))
        XCTAssertEqual(member(e, id, pid)?.int("ft"), end0 + 26, "renewed")
    }

    func testTheJobEndsOnTheDateAtNoCostWhereTheDataOwesNothing() throws {
        var (e, id) = try shop()
        let (pid, _) = hire(&e, id)
        _ = e.contractPropose(companyID: id, personID: pid, proposal: .init(.term, choice: "fixed:26"))
        e.update { s, _, _ in
            let ci = s.companyIndex(id)!
            var st = s.companies[ci].staff; let k = st.firstIndex { $0.id == pid }!; st[k].set("ft", s.week + 2); s.companies[ci].staff = st
        }
        let msgs = e.openDecisions.count
        e.update { s, d, _ in FixedTerm.weekly(&s, data: d) }
        let msg = try XCTUnwrap(e.openDecisions.first { $0.actionID == FixedTerm.action })
        XCTAssertGreaterThan(e.openDecisions.count, msgs)
        XCTAssertTrue(e.answer(messageID: msg.id, option: 1))
        let cash0 = e.state.company(id)!.cash, paid0 = e.state.company(id)!.books.week["wages"] ?? 0
        e.update { s, d, _ in s.week += 3; FixedTerm.weekly(&s, data: d) }
        XCTAssertNil(member(e, id, pid), "gone on the date")
        XCTAssertEqual(e.state.people[pid]?.employerID, 0)
        XCTAssertEqual(e.state.company(id)!.cash, cash0, accuracy: 1e-9, "nothing owed")
        XCTAssertEqual(e.state.company(id)!.books.week["wages"] ?? 0, paid0, accuracy: 1e-9)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testExpiryOwesWhatTheCountryDataListsForItAndNothingByDefault() {
        var lab = LabourRules()
        lab.noticeWeeks = 4; lab.severancePerYear = 1
        XCTAssertEqual(lab.termination(tenureWeeks: 104, reason: .expiry).weeks, 0, "neutral default: nothing for the end of a fixed term")
        XCTAssertGreaterThan(lab.termination(tenureWeeks: 104, reason: .unjustified).weeks, 0)
        lab.severanceReasons.insert(LabourRules.TerminationReason.expiry.rawValue)
        lab.noticeReasons.insert(LabourRules.TerminationReason.expiry.rawValue)
        let t = lab.termination(tenureWeeks: 104, reason: .expiry)
        XCTAssertGreaterThan(t.severanceWeeks, 0); XCTAssertGreaterThan(t.noticeWeeks, 0)
    }

    // MARK: Maximum duration (optional labour data; empty = nothing is limited or converted)

    private func limited(weeks: Double = 0, renewals: Double = 0) -> (GameState, GameData, Company) -> LabourRules {
        { _, _, _ in var l = LabourRules(); l.fixedTermMaxWeeks = weeks; l.fixedTermMaxRenewals = renewals; return l }
    }

    func testNoLimitInTheDataMeansNothingIsBlockedOrConverted() throws {
        let lab = LabourRules()
        XCTAssertEqual(lab.fixedTermMaxWeeks, 0); XCTAssertEqual(lab.fixedTermMaxRenewals, 0)
        var (e, id) = try shop()
        let (pid, _) = hire(&e, id)
        _ = e.contractPropose(companyID: id, personID: pid, proposal: .init(.term, choice: "fixed:104"))
        for _ in 0..<5 { guard case .agreed = e.contractPropose(companyID: id, personID: pid, proposal: .init(.term, choice: "fixed:104")) else { return XCTFail("renewals are unlimited by default") } }
        XCTAssertNil(FixedTerm.renewalBlock(lab, try XCTUnwrap(member(e, id, pid)), weeks: 104, now: e.state.week))
        // and at the end date the job simply ends
        e.update { s, d, _ in
            let ci = s.companyIndex(id)!
            var st = s.companies[ci].staff; let k = st.firstIndex { $0.id == pid }!; st[k].set("ft", s.week); s.companies[ci].staff = st
            FixedTerm.weekly(&s, data: d)
        }
        XCTAssertNil(member(e, id, pid))
    }

    func testRenewalsPastTheMaximumDurationAreRefusedAndTheContractBecomesPermanent() throws {
        var (e, id) = try shop()
        let (pid, _) = hire(&e, id, terms: Hiring.Terms(fixedTermWeeks: 52))
        let lab = limited(weeks: 104)(e.state, e.data, e.state.company(id)!)
        var m = try XCTUnwrap(member(e, id, pid))
        XCTAssertNil(FixedTerm.renewalBlock(lab, m, weeks: 26, now: e.state.week), "52 + 26 is inside 104")
        XCTAssertNil(FixedTerm.renewalBlock(lab, m, weeks: 52, now: e.state.week), "52 + 52 is exactly the maximum")
        XCTAssertNotNil(FixedTerm.renewalBlock(lab, m, weeks: 104, now: e.state.week), "52 + 104 is over")
        // a first term longer than the maximum is not allowed either
        e.update { s, _, _ in
            let ci = s.companyIndex(id)!
            var st = s.companies[ci].staff; let k = st.firstIndex { $0.id == pid }!; st[k].raw.removeValue(forKey: "ft"); st[k].raw.removeValue(forKey: "ftl"); st[k].raw.removeValue(forKey: "fts"); s.companies[ci].staff = st
        }
        m = try XCTUnwrap(member(e, id, pid))
        XCTAssertNotNil(FixedTerm.renewalBlock(limited(weeks: 26)(e.state, e.data, e.state.company(id)!), m, weeks: 52, now: e.state.week))
        XCTAssertNil(FixedTerm.renewalBlock(limited(weeks: 26)(e.state, e.data, e.state.company(id)!), m, weeks: 26, now: e.state.week))
    }

    func testAtTheMaximumTheOwnerMustDecideAndNoAnswerMakesItPermanent() throws {
        var (e, id) = try shop()
        let (pid, _) = hire(&e, id, terms: Hiring.Terms(fixedTermWeeks: 52))
        // Two terms of 52 weeks make the 104-week maximum: the second one is the last.
        _ = e.contractPropose(companyID: id, personID: pid, proposal: .init(.term, choice: "fixed:52"))
        let lab = limited(weeks: 104)
        e.update { s, d, _ in
            let ci = s.companyIndex(id)!
            var st = s.companies[ci].staff; let k = st.firstIndex { $0.id == pid }!
            st[k].set("fts", s.week - 100); st[k].set("ft", s.week + 4); st[k].set("ftl", 52); s.companies[ci].staff = st
            FixedTerm.weekly(&s, data: d, labour: lab)
        }
        let msg = try XCTUnwrap(e.openDecisions.first { $0.actionID == FixedTerm.action })
        XCTAssertEqual(msg.options.count, 2)
        XCTAssertTrue(msg.options[0]["l"].string.lowercased().contains("permanent"), "\(msg.options)")
        // Unanswered: on the end date the contract turns permanent instead of ending.
        e.update { s, d, _ in s.week += 5; FixedTerm.weekly(&s, data: d, labour: lab) }
        let after = try XCTUnwrap(member(e, id, pid), "still employed")
        XCTAssertFalse(FixedTerm.isFixed(after)); XCTAssertNil(after.raw["fts"]); XCTAssertNil(after.raw["ftr"])
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testAnsweringLetItEndAtTheMaximumStillEndsTheJobAndPermanentAnswerConverts() throws {
        for pick in [0, 1] {
            var (e, id) = try shop()
            let (pid, _) = hire(&e, id, terms: Hiring.Terms(fixedTermWeeks: 52))
            let lab = limited(renewals: 1)
            e.update { s, d, _ in
                let ci = s.companyIndex(id)!
                var st = s.companies[ci].staff; let k = st.firstIndex { $0.id == pid }!
                st[k].set("ftr", 1); st[k].set("ft", s.week + 3); s.companies[ci].staff = st
                FixedTerm.weekly(&s, data: d, labour: lab)
            }
            let msg = try XCTUnwrap(e.openDecisions.first { $0.actionID == FixedTerm.action })
            XCTAssertTrue(e.answer(messageID: msg.id, option: pick))
            e.update { s, d, _ in s.week += 4; FixedTerm.weekly(&s, data: d, labour: lab) }
            if pick == 0 { XCTAssertEqual(member(e, id, pid).map { FixedTerm.isFixed($0) }, false, "made permanent") }
            else { XCTAssertNil(member(e, id, pid), "let go on the date") }
        }
    }

    func testTheTermSurvivesASave() throws {
        var (e, id) = try shop()
        let (pid, _) = hire(&e, id, terms: Hiring.Terms(fixedTermWeeks: 52))
        let back = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(e.state))
        XCTAssertEqual(back.company(id)?.staff.first { $0.id == pid }.flatMap { FixedTerm.endWeek($0) }, e.state.week + 52)
    }
}

extension GameData {
    static var bundledForTests: GameData { try! GameData.bundled() }
}
