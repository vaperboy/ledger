import XCTest
import GameCore
import Countries
import Employees
import Finance
@testable import Businesses
import Simulation

/// Roadmap A1 and A2: one engine function (`Dismissal`) decides and books a dismissal; every caller delegates to it.
final class DismissalEngineTests: XCTestCase {
    private func cafe(_ code: String = "UK", seed: Int = 9) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: code, playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 30_000_000) else { throw XCTSkip("no company") }
        return (e, id)
    }

    @discardableResult
    private func addStaff(_ e: inout GameEngine, _ id: Int, years: Double, wage: Double = 300_000, warnings: Int = 0) -> Int {
        var sid = 0
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var m = StaffMember(raw: [:])
            m.id = s.makeID(); m.role = "waiter"; m.monthlyWage = wage; m.hiredWeek = s.week - Int(years * 52)
            if warnings > 0 { m.set("warn", warnings) }
            s.companies[i].staff.append(m)
            sid = m.id
        }
        return sid
    }

    private func cash(_ e: GameEngine, _ id: Int) -> Double { e.state.company(id)?.cash ?? 0 }
    private func labels(_ e: GameEngine, _ id: Int) -> [String] { (e.state.company(id)?.transactions ?? []).map { $0["l"].string } }

    // MARK: Every caller's cash change is the single function's quote

    func testEveryStaffCallerMatchesTheQuote() throws {
        enum Way: CaseIterable { case profile, rosterFire, layoff, proposalCut, direct }
        for way in Way.allCases {
            var (e, id) = try cafe()
            let sid = addStaff(&e, id, years: 5)
            let quote = try XCTUnwrap(Dismissal.quote(e.state, companyID: id, staffID: sid, reason: way == .profile ? nil : .redundancy, data: e.data))
            XCTAssertGreaterThan(quote.severance, 0, "\(way)")
            // layoff and proposals take the weakest, so make the target the only one
            e.update { s, _, _ in let i = s.companyIndex(id)!; s.companies[i].staff = s.companies[i].staff.filter { $0.id == sid } }
            let before = cash(e, id)
            var extra = 0.0
            switch way {
            case .profile: extra = try XCTUnwrap(e.dismissStaff(companyID: id, staffID: sid)).compensation
            case .rosterFire: XCTAssertEqual(e.fire(personID: sid, companyID: id), quote.total, accuracy: 1)
            case .layoff: XCTAssertEqual(e.layOffStaff(companyID: id, count: 1), [sid])
            case .proposalCut: e.update { s, d, _ in Dismissal.dismiss(&s, companyID: id, staffID: sid, reason: .redundancy, data: d) }
            case .direct: e.update { s, d, _ in Dismissal.dismiss(&s, companyID: id, staffID: sid, reason: .redundancy, data: d) }
            }
            XCTAssertEqual(before - cash(e, id), quote.total + extra, accuracy: 2, "\(way): cash change equals the quote")
            XCTAssertNil(e.state.company(id)?.staff.first { $0.id == sid })
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(way)")
        }
    }

    func testManagerCallerMatchesTheQuote() throws {
        var (e, id) = try cafe()
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: id, monthlyWage: cands[0].askingMonthlyWage * 1.2), .ok)
        e.update { s, _, _ in s.companies[s.companyIndex(id)!].set("mgrW0", s.week - 300) }
        let co = try XCTUnwrap(e.state.company(id))
        let q = Dismissal.quote(World(state: e.state, data: e.data), co, monthlyWage: co.managerMonthlyWage, tenureWeeks: 300, reason: .redundancy,
                                age: e.state.people[cands[0].id].map { Double($0.age) })
        XCTAssertGreaterThan(q.severance, 0)
        let before = cash(e, id)
        XCTAssertEqual(e.dismissManager(companyID: id), q.total, accuracy: 1)
        XCTAssertEqual(before - cash(e, id), q.total, accuracy: 2)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testWorkedNoticeResignationOwesNothingAndManagerNoticeToo() throws {
        var (e, id) = try cafe()
        let sid = addStaff(&e, id, years: 5)
        let before = cash(e, id)
        e.update { s, d, _ in Dismissal.dismiss(&s, companyID: id, staffID: sid, reason: .resignation, noticeServed: true, data: d) }
        XCTAssertEqual(cash(e, id), before, accuracy: 0.5)
        // a manager who has worked their notice
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        XCTAssertEqual(e.hireManager(personID: cands[1].id, companyID: id, monthlyWage: cands[1].askingMonthlyWage * 1.2), .ok)
        let b2 = cash(e, id)
        e.update { s, d, _ in Dismissal.dismissManager(&s, companyID: id, reason: .resignation, noticeServed: true, data: d) }
        XCTAssertEqual(cash(e, id), b2, accuracy: 0.5)
        XCTAssertNil(e.state.company(id)?.managerID)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    // MARK: Rules

    func testForCauseWithWarningsPaysNoSeveranceInEveryCountry() throws {
        let book = try CountryBook.bundled()
        for c in book.countries {
            let code = c.code
            let rules = LabourRules(country: c)
            let t = rules.termination(tenureWeeks: 260, reason: .forCause)
            XCTAssertEqual(t.severanceWeeks, 0, "\(code): for cause owes no severance")
            // the player-facing reasons agree on what they owe
            XCTAssertEqual(rules.termination(tenureWeeks: 260, reason: .unjustified), rules.termination(tenureWeeks: 260, reason: .redundancy), code)
            XCTAssertEqual(rules.termination(tenureWeeks: 260, reason: .resignation), rules.termination(tenureWeeks: 260, withCause: true), "\(code): resignation = the old for-cause path")
        }
    }

    func testDocumentedDismissalBooksNoSeveranceAndNoClaim() throws {
        var (e, id) = try cafe()
        let sid = addStaff(&e, id, years: 5, warnings: 2)
        let q = try XCTUnwrap(Dismissal.quote(e.state, companyID: id, staffID: sid, data: e.data))
        XCTAssertEqual(q.reason, .forCause)
        XCTAssertEqual(q.severance, 0)
        let r = try XCTUnwrap(e.dismissStaff(companyID: id, staffID: sid))
        XCTAssertFalse(r.claimedUnfairDismissal)
        XCTAssertFalse(labels(e, id).contains("Severance"))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testProfileShowsTheSumTheDismissalWillCost() throws {
        var (e, id) = try cafe()
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))   // real people for the profile screen
        let warned = cands[0].id, plain = cands[1].id
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            for (pid, warn) in [(warned, 2), (plain, 0)] {
                var m = StaffMember(raw: [:])
                m.id = pid; m.role = "waiter"; m.monthlyWage = 300_000; m.hiredWeek = s.week - 260
                if warn > 0 { m.set("warn", warn) }
                s.companies[i].staff.append(m)
            }
        }
        let a = try XCTUnwrap(StaffProfile.profile(e.state, companyID: id, staffID: warned, data: e.data))
        let b = try XCTUnwrap(StaffProfile.profile(e.state, companyID: id, staffID: plain, data: e.data))
        XCTAssertEqual(a.severance, Dismissal.quote(e.state, companyID: id, staffID: warned, data: e.data)?.total)
        XCTAssertEqual(b.severance, Dismissal.quote(e.state, companyID: id, staffID: plain, data: e.data)?.total)
        XCTAssertGreaterThan(b.severance, a.severance, "a documented dismissal is cheaper")
    }

    func testRedundancyPaysByTenure() throws {
        var (e, id) = try cafe()
        let junior = addStaff(&e, id, years: 1), senior = addStaff(&e, id, years: 8)
        let qj = try XCTUnwrap(Dismissal.quote(e.state, companyID: id, staffID: junior, reason: .redundancy, data: e.data))
        let qs = try XCTUnwrap(Dismissal.quote(e.state, companyID: id, staffID: senior, reason: .redundancy, data: e.data))
        XCTAssertGreaterThan(qs.severance, qj.severance)
        XCTAssertGreaterThan(qs.total, qj.total)
        let before = cash(e, id)
        e.update { s, d, _ in Dismissal.dismiss(&s, companyID: id, staffID: senior, reason: .redundancy, data: d) }
        XCTAssertEqual(before - cash(e, id), qs.total, accuracy: 2)
    }

    func testThreePaymentsStayApartAndNoticeCarriesTheEmployerCharge() throws {
        var (e, id) = try cafe("BR")   // notice, severance fund fine
        let sid = addStaff(&e, id, years: 4)
        let co = try XCTUnwrap(e.state.company(id))
        let q = try XCTUnwrap(Dismissal.quote(e.state, companyID: id, staffID: sid, reason: .redundancy, data: e.data))
        let social = World(state: e.state, data: e.data).country(co).employerSocialRate(monthlyWage: 300_000)
        XCTAssertGreaterThan(q.notice, 0)
        XCTAssertEqual(q.notice, 300_000 * 12 / 52 * LabourRules(country: World(state: e.state, data: e.data).country(co)).termination(tenureWeeks: 208, reason: .redundancy).noticeWeeks * (1 + social), accuracy: 1)
        e.update { s, d, _ in Dismissal.dismiss(&s, companyID: id, staffID: sid, reason: .redundancy, data: d) }
        let l = labels(e, id)
        XCTAssertTrue(l.contains("Notice pay"))
        if q.severance > 0 { XCTAssertTrue(l.contains("Severance")) }
        if q.fine > 0 { XCTAssertTrue(l.contains("Termination fund fine")) }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testUnfairDismissalClaimNeedsNoWarningsAndNotAtWillOrProbation() throws {
        var claims = 0
        for seed in 1...40 {
            var (e, id) = try cafe("UK", seed: seed)
            let sid = addStaff(&e, id, years: 5)
            if try XCTUnwrap(e.dismissStaff(companyID: id, staffID: sid)).claimedUnfairDismissal { claims += 1; XCTAssertTrue(labels(e, id).contains("Unfair dismissal settlement")) }
        }
        XCTAssertGreaterThan(claims, 0, "unwarned long-serving staff sometimes claim")
        var (e, id) = try cafe("US")
        let sid = addStaff(&e, id, years: 5)
        XCTAssertFalse(try XCTUnwrap(e.dismissStaff(companyID: id, staffID: sid)).claimedUnfairDismissal, "at will: no claim")
    }

    // MARK: One copy only

    func testOnlyDismissalPostsTheSeverancePayments() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var offenders: [String] = [], bookCalls = 0
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let name = url.lastPathComponent
            for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let posts = line.contains("Payments.companyPays") || line.contains("Payments.playerPays") || line.contains("Ledger.move")
                if posts && line.range(of: "(label|why): *\"[^\"]*(severance|notice pay|fund fine)", options: [.regularExpression, .caseInsensitive]) != nil && name != "Dismissal.swift" {
                    offenders.append("\(name):\(n + 1)")
                }
                if name == "Dismissal.swift" && line.contains("Payments.companyPays(&s, companyID: id, amount: amount, category: \"wages\", label: label)") { bookCalls += 1 }
            }
            if name != "Dismissal.swift" && text.contains("\"Severance\"") && !text.contains("(\"Severance\", ") { offenders.append("\(name): severance label") }
        }
        XCTAssertEqual(offenders, [])
        XCTAssertEqual(bookCalls, 1, "one booking loop")
        let own = try String(contentsOf: sources.appendingPathComponent("Businesses/Dismissal.swift"), encoding: .utf8)
        XCTAssertEqual(own.components(separatedBy: "label: \"Unfair").count, 2)
        XCTAssertFalse(try String(contentsOf: sources.appendingPathComponent("Businesses/Hiring.swift"), encoding: .utf8).contains("static func fire"), "Hiring.fire is gone")
    }
}
