import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

/// Manager voice: role wording, no repeats, authority limits, scorecard, poaching and the move up.
final class ManagerVoiceTests: XCTestCase {
    private func managedCafe(seed: Int, extraCafe: Bool = false) throws -> (GameEngine, Int, Int?) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 90_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 30_000_000) else { throw XCTSkip("no company") }
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: id, monthlyWage: cands[0].askingMonthlyWage * 1.2), .ok)
        var other: Int?
        if extraCafe, case .success(let o) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 20_000_000) { other = o }
        return (e, id, other)
    }

    func testEveryRoleHasAtLeastThreeVariantsPerSituation() {
        for f in ManagerVoice.Family.allCases {
            for sit in ManagerVoice.Situation.allCases where sit != .digest {
                let v = ManagerVoice.variants(sit, family: f)
                XCTAssertGreaterThanOrEqual(Set(v).count, 3, "\(f) \(sit)")
            }
        }
        // Roles really sound different: no two families share a wording for the same situation.
        for sit in [ManagerVoice.Situation.hire, .equip, .cash, .cut, .ad] {
            var seen = Set<String>()
            for f in ManagerVoice.Family.allCases { for l in ManagerVoice.variants(sit, family: f) { XCTAssertTrue(seen.insert(l).inserted, l) } }
        }
        XCTAssertEqual(ManagerVoice.family(type: "host"), .kitchen)
        XCTAssertEqual(ManagerVoice.family(title: "Chief financial officer"), .fin)
    }

    func testPickNeverRepeatsWithinTheLastTwoUses() throws {
        var (e, id, _) = try managedCafe(seed: 3)
        let v = ManagerVoice.variants(.hire, family: .general)
        var s = e.state
        let ci = try XCTUnwrap(s.companyIndex(id))
        var picks: [String] = []
        for w in 0..<30 {
            s.week = 100 + w
            picks.append(ManagerVoice.pick(&s, companyIndex: ci, situation: "hire", seed: 7, variants: v))
        }
        for i in 2..<picks.count { XCTAssertNotEqual(picks[i], picks[i - 1]); XCTAssertNotEqual(picks[i], picks[i - 2]) }
        XCTAssertGreaterThan(Set(picks).count, 2)
        e.update { st, _, _ in st = s }
    }

    func testScorecardIsWordsAndVoiced() throws {
        let (e, id, _) = try managedCafe(seed: 4)
        let card = try XCTUnwrap(e.managerVoiceCard(companyID: id))
        XCTAssertGreaterThanOrEqual(card.rows.count, 8)
        XCTAssertTrue(card.rows.allSatisfy { Double($0.word) == nil && !$0.word.isEmpty })
        XCTAssertFalse(card.verdict.isEmpty)
        XCTAssertTrue(["Bold", "Cautious"].contains { card.traits.hasPrefix($0) })
    }

    func testAuthorityLimitsAreRespected() throws {
        // A cautious manager never uses more than the limit; a bold one exactly the limit.
        var uses = Set<Double>()
        for id in 1...60 { var p = Person(raw: [:]); p.set("id", id); p.set("stats", .object([:])); uses.insert(ManagerVoice.budgetUse(p)) }
        XCTAssertTrue(uses.allSatisfy { $0 <= 1 && $0 > 0 })
        XCTAssertEqual(uses, [0.75, 1])
    }

    func testLevelZeroManagerAsksAndNeverReportsDoneWork() throws {
        var (e, id, _) = try managedCafe(seed: 5)
        e.setManagerAuthority(companyID: id, level: 0)
        for _ in 0..<(20 * 7) { e.nextDay() }
        XCTAssertFalse(e.state.inbox.contains { $0.companyID == id && $0.title.hasSuffix(": what I did") })
        XCTAssertTrue((e.state.company(id)?.value("mgrLog").array ?? []).isEmpty)
    }

    func testDigestSpeaksOnlyAboutWhatWasDoneAndIsNotSpam() throws {
        var (e, id, _) = try managedCafe(seed: 6)
        e.setManagerAuthority(companyID: id, level: 2)
        e.update { s, _, _ in
            let ci = s.companyIndex(id)!
            ManagerVoice.record(&s, companyIndex: ci, "raised prices one step: load is at 98%")
        }
        var perWeek: [Int: Int] = [:]
        for _ in 0..<(40 * 7) {
            e.nextDay()
            for m in e.openDecisions where ["prop", "mgrraise", "mgrpoach", "staffx"].contains(m.actionID) { e.answer(messageID: m.id, option: 0) }
        }
        for m in e.state.inbox where m.companyID == id && m.from == e.state.people[e.state.company(id)?.managerID ?? 0]?.name { perWeek[m.week, default: 0] += 1 }
        XCTAssertLessThanOrEqual(perWeek.values.max() ?? 0, 3, "manager messages per week: \(perWeek)")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testUnderpaidManagerIsPoachedAndMatchingKeepsThem() throws {
        var (e, id, _) = try managedCafe(seed: 7)
        var got: Message?
        e.update { s, d, _ in
            let ci = s.companyIndex(id)!
            s.companies[ci].managerMonthlyWage = 1000   // far under the going rate
            s.companies[ci].set("mgrW0", -100)
            for k in 0..<6000 where got == nil {
                s.week = 60 + k
                ManagerModel.rivalOffer(&s, companyIndex: ci, data: d)
                got = s.inbox.last { $0.actionID == "mgrpoach" && $0.status == "open" }
            }
        }
        let m = try XCTUnwrap(got, "an underpaid manager gets an offer")
        XCTAssertFalse(m.body.isEmpty)
        let before = e.state.company(id)!.managerMonthlyWage
        e.update { s, d, _ in ManagerModel.answer(&s, message: m, option: 0, data: d) }
        XCTAssertGreaterThan(e.state.company(id)!.managerMonthlyWage, before)
        e.update { s, d, _ in ManagerModel.answer(&s, message: m, option: 1, data: d) }
        XCTAssertFalse(e.state.company(id)!.value("mgrNotice").isNull, "letting them go starts a notice")
        let resign = e.state.inbox.last { $0.title.contains("has resigned") }
        XCTAssertNotNil(resign)
        XCTAssertTrue(ManagerVoice.variants(.resign, family: .general).contains { resign!.body.hasPrefix($0.replacingOccurrences(of: " {why}", with: "")) })
    }

    func testPromotionMovesTheManagerUpToAnotherCompany() throws {
        var (e, id, other) = try managedCafe(seed: 8, extraCafe: true)
        let to = try XCTUnwrap(other)
        let mid = e.state.company(id)?.managerID
        var ok = false
        e.update { s, d, _ in ok = ManagerModel.move(&s, fromCompanyID: id, toCompanyID: to, data: d) }
        XCTAssertTrue(ok)
        XCTAssertEqual(e.state.company(to)?.managerID, mid)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
