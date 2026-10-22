import XCTest
@testable import Events
@testable import Simulation
import GameCore
import Countries
import Finance
import Businesses

/// Misconduct and political influence as decisions: real gain now, delayed and bounded consequences, books that balance.
final class MisconductTests: XCTestCase {
    func engine(weeks: Int = 6) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4242)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 50_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data, faithfulHiring: false)
        }
        for _ in 0..<(weeks * 7) { e.nextDay() }
        return (e, id)
    }

    func ask(_ e: inout GameEngine, _ defID: String, _ id: Int, given: JSONValue, option: Int) -> Bool {
        var asked: Message? = nil
        e.update { s, data, ctx in
            guard let i = s.companyIndex(id), let def = StrategicDecisions.byID[defID] else { return }
            _ = StrategicDecisions.fire(&s, def, companyIndex: i, data: data, context: ctx, given: given)
            asked = s.inbox.first { $0.actionID == StrategicDecisions.action && $0.status == "open" }
        }
        guard let m = asked else { return false }
        return e.answer(messageID: m.id, option: option)
    }

    func taxDecision() -> JSONValue {
        .object(["conc": 300_000, "save": 66_000, "rate": 0.22, "legal": 120_000, "lsave": 26_400, "fee": 9_240, "risk": 0.1, "fine": 60_000])
    }

    // MARK: Country strictness comes from data

    func testStrictnessIsDataAndDiffersByCountry() {
        XCTAssertGreaterThan(Misconduct.enforcement("NO"), Misconduct.enforcement("MX"))
        XCTAssertGreaterThan(Misconduct.openness("US"), Misconduct.openness("SG"))
        XCTAssertEqual(Misconduct.enforcement("ZZ"), 1, "a country without an entry is average")
    }

    // MARK: Tax

    func testHiddenTakingsLowerTheTaxAccrualAndAreRecordedAsACase() throws {
        var (e, id) = try engine()
        XCTAssertTrue(ask(&e, "m_tax", id, given: taxDecision(), option: 0))
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(Misconduct.cases(co).count, 1)
        XCTAssertEqual(Misconduct.cases(co)[0]["k"].string, "tax")
        // The same year's accrual: concealed profit is out of the base, the tax is lower, and it is booked through MonthEnd.
        e.update { s, data, _ in
            let i = s.companyIndex(id)!
            let bd = data.catalog[s.companies[i].type]!
            s.companies[i].yearProfitSoFar = 1_000_000
            s.companies[i].lossCarryAtYearStart = 0
            s.companies[i].taxAccrued = 0
            var ev = s.companies[i].value("evade"); ev["c"] = 0; s.companies[i].set("evade", ev)
            MonthEnd.accrueTax(&s, companyIndex: i, bd, data: data)
            let honest = s.companies[i].taxAccrued
            s.companies[i].taxAccrued = 0
            ev["c"] = 300_000; s.companies[i].set("evade", ev)
            MonthEnd.accrueTax(&s, companyIndex: i, bd, data: data)
            let rate = honest / 1_000_000
            XCTAssertEqual(honest - s.companies[i].taxAccrued, 300_000 * rate, accuracy: 1)
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testTheLegalRouteCostsAFeeAndCreatesNoCase() throws {
        var (e, id) = try engine()
        let cash0 = try XCTUnwrap(e.state.company(id)).cash
        XCTAssertTrue(ask(&e, "m_tax", id, given: taxDecision(), option: 1))
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertTrue(Misconduct.cases(co).isEmpty)
        XCTAssertEqual(co.value("evade")["l"].double, 120_000)
        XCTAssertLessThan(co.cash, cash0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testDecliningChangesNothing() throws {
        var (e, id) = try engine()
        let before = try XCTUnwrap(e.state.company(id)).cash
        XCTAssertTrue(ask(&e, "m_tax", id, given: taxDecision(), option: 2))
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.cash, before)
        XCTAssertTrue(Misconduct.cases(co).isEmpty)
        XCTAssertTrue(co.value("evade").isNull)
    }

    func testBeingFoundPaysBackTaxInterestAndAScaledPenaltyOnce() throws {
        var (e, id) = try engine()
        XCTAssertTrue(ask(&e, "m_tax", id, given: taxDecision(), option: 0))
        var paid = 0.0, cashBefore = 0.0, repBefore = 0.0, personalBefore = 0.0
        e.update { s, data, ctx in
            let i = s.companyIndex(id)!
            // The tax year has closed: the case is from last year, so back taxes are due as well.
            var st = s.companies[i].value("mis")
            var list = st["cases"].array; list[0]["y"] = .number(Double(GameCalendar.year(week: s.week) - 1)); list[0]["w"] = .number(Double(s.week - 40))
            st["cases"] = .array(list); s.companies[i].set("mis", st)
            cashBefore = s.companies[i].cash; repBefore = s.companies[i].reputation; personalBefore = s.cash
            paid = Misconduct.investigate(&s, i, data: data, context: ctx, cause: "Test")
            let again = Misconduct.investigate(&s, i, data: data, context: ctx, cause: "Test")
            XCTAssertEqual(again, 0, "a case is settled once")
        }
        let co = try XCTUnwrap(e.state.company(id))
        let back = 300_000 * 0.22
        XCTAssertGreaterThan(paid, back + 66_000 * 0.5, "back taxes plus a penalty above half the gain")
        XCTAssertLessThan(co.cash, cashBefore - back, "the company paid back tax, interest and penalty")
        XCTAssertLessThan(co.reputation, repBefore)
        XCTAssertLessThan(e.state.cash, personalBefore, "the owner is personally liable for part of it")
        XCTAssertTrue(Misconduct.cases(co).isEmpty)
        XCTAssertTrue(e.state.inbox.contains { $0.title.hasPrefix("Investigation at") })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testFoundInTheSameYearRemovesTheConcealmentSoTaxIsNotPaidTwice() throws {
        var (e, id) = try engine()
        XCTAssertTrue(ask(&e, "m_tax", id, given: taxDecision(), option: 0))
        e.update { s, data, ctx in
            let i = s.companyIndex(id)!
            Misconduct.investigate(&s, i, data: data, context: ctx, cause: "Test")
            XCTAssertEqual(s.companies[i].value("evade")["c"].double, 0, "the ordinary accrual now covers that profit")
        }
        // Back taxes are only charged for closed years: the fine rows here are interest and penalty.
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertFalse(e.state.inbox.contains { $0.title.hasPrefix("Investigation at") && $0.body.contains("Back taxes") })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    // MARK: Risk

    func testRiskRisesWithRepeatsAndSizeAndIsBounded() throws {
        var (e, id) = try engine()
        e.update { s, data, ctx in
            let i = s.companyIndex(id)!
            s.companies[i].monthlyHistory = []
            s.companies[i].set("lastW", .object(["rev": 1000]))
            let r0 = Misconduct.weeklyRisk(s, i, data: data, context: ctx, extraActs: 1)
            let r1 = Misconduct.weeklyRisk(s, i, data: data, context: ctx, extraActs: 2)
            let r2 = Misconduct.weeklyRisk(s, i, data: data, context: ctx, extraActs: 4)
            XCTAssertLessThan(r0, r1)
            XCTAssertLessThan(r1, r2)
            XCTAssertLessThanOrEqual(r2, 0.04)
            XCTAssertGreaterThan(Misconduct.yearlyRisk(s, i, data: data, context: ctx, extraActs: 1), 0)
            s.companies[i].set("lastW", .object(["rev": 500_000_000]))
            let big = Misconduct.weeklyRisk(s, i, data: data, context: ctx, extraActs: 1)
            XCTAssertGreaterThan(big, r0, "a bigger business is looked at harder")
        }
    }

    // MARK: Quality shortcut and the bank

    func testQualityShortcutSavesCostNowAndCostsReputationWhenFound() throws {
        var (e, id) = try engine()
        let q0 = try XCTUnwrap(e.state.company(id)).quality
        XCTAssertTrue(ask(&e, "m_quality", id, given: .object(["save": 40_000, "risk": 0.1, "lsave": 8_000, "fee": 3_000, "fine": 60_000]), option: 0))
        var co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.quality, q0 - 4)
        XCTAssertTrue(co.value("mods").array.contains { $0["k"].string == "cogsup" && $0["m"].double == 0.93 })
        XCTAssertEqual(Misconduct.cases(co)[0]["k"].string, "quality")
        let rep0 = co.reputation
        e.update { s, data, ctx in _ = Misconduct.investigate(&s, s.companyIndex(id)!, data: data, context: ctx, cause: "Inspection", kinds: ["quality"]) }
        co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.reputation, rep0 - 8, accuracy: 0.001)
        XCTAssertTrue(co.value("mods").array.contains { $0["k"].string == "dem" && $0["m"].double == 0.9 })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testFlatteringAccountsHurtCreditWhenFound() throws {
        var (e, id) = try engine()
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            Misconduct.register(&s, i, kind: "bank", gain: 12_000)
        }
        let credit0 = e.state.credit
        e.update { s, data, ctx in _ = Misconduct.investigate(&s, s.companyIndex(id)!, data: data, context: ctx, cause: "Review") }
        XCTAssertLessThan(e.state.credit, credit0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testABribeCostsMoneyEvenIfNothingComesOfIt() throws {
        var (e, id) = try engine()
        let cash0 = try XCTUnwrap(e.state.company(id)).cash
        XCTAssertTrue(ask(&e, "m_bribe", id, given: .object(["cost": 25_000, "gain": 90_000, "p": 0.2, "risk": 0.1, "fine": 150_000]), option: 0))
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertLessThanOrEqual(co.cash, cash0 - 25_000 + 1, "the fee is gone whatever happens")
        XCTAssertEqual(Misconduct.cases(co)[0]["k"].string, "bribe")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    // MARK: Political influence

    func politicalDecision(ps: Double, pw: Double) -> JSONValue {
        .object(["spent": 40_000, "p": 0.4, "pw": pw, "ps": ps, "m": 0.985, "weeks": 78, "scandal": 0.1, "fineMult": 2,
                 "what": "party donation", "kind": "donate", "fine": 80_000])
    }

    func testADonationCostsRealMoneyNowAndQueuesAnUncertainResult() throws {
        var (e, id) = try engine()
        let cash0 = try XCTUnwrap(e.state.company(id)).cash
        XCTAssertTrue(ask(&e, "m_pol_donate", id, given: politicalDecision(ps: 0, pw: 1), option: 0))
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).cash, cash0 - 40_000, accuracy: 1)
        let queued = e.state.rest["e27"]?["q"].array.filter { $0["id"].string == "pol_result" } ?? []
        XCTAssertEqual(queued.count, 1)
        XCTAssertGreaterThanOrEqual(queued[0]["w"].int, e.state.week + 8)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testStayingOutCostsNothing() throws {
        var (e, id) = try engine()
        let cash0 = try XCTUnwrap(e.state.company(id)).cash
        XCTAssertTrue(ask(&e, "m_pol_lobby", id, given: politicalDecision(ps: 0, pw: 1), option: 1))
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).cash, cash0)
        XCTAssertNil(e.state.rest["e27"]?["q"].array.first { $0["id"].string == "pol_result" })
    }

    func testASuccessfulEffortGivesASmallBoundedTimedCostCut() throws {
        var (e, id) = try engine()
        e.update { s, data, ctx in
            StrategicDecisions.followUp(&s, id: "pol_result", companyID: id, d: politicalDecision(ps: 0, pw: 1), data: data, context: ctx)
        }
        let mods = try XCTUnwrap(e.state.company(id)).value("mods").array.filter { $0["k"].string == "cogsup" }
        XCTAssertEqual(mods.count, 1)
        XCTAssertGreaterThanOrEqual(mods[0]["m"].double, 0.98, "at most a couple of percent")
        XCTAssertEqual(mods[0]["w"].double, 78)
    }

    func testAFailedEffortChangesNothingAndABackfireIsFinedAndHurtsReputation() throws {
        var (e, id) = try engine()
        let c0 = try XCTUnwrap(e.state.company(id))
        e.update { s, data, ctx in
            StrategicDecisions.followUp(&s, id: "pol_result", companyID: id, d: politicalDecision(ps: 0, pw: 0), data: data, context: ctx)
        }
        var co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.cash, c0.cash)
        XCTAssertFalse(co.value("mods").array.contains { $0["k"].string == "cogsup" })
        e.update { s, data, ctx in
            StrategicDecisions.followUp(&s, id: "pol_result", companyID: id, d: politicalDecision(ps: 1, pw: 1), data: data, context: ctx)
        }
        co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.cash, c0.cash - 80_000, accuracy: 1)
        XCTAssertEqual(co.reputation, c0.reputation - 6, accuracy: 0.001)
        XCTAssertFalse(co.value("mods").array.contains { $0["k"].string == "cogsup" }, "a scandal gains nothing")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    // MARK: The decisions state cost, benefit, risk and timing

    func testMessagesShowCostBenefitRiskAndTiming() throws {
        var (e, id) = try engine()
        e.update { s, data, ctx in
            let i = s.companyIndex(id)!
            for (defID, d) in [("m_tax", self.taxDecision()), ("m_pol_donate", self.politicalDecision(ps: 0.1, pw: 0.4))] {
                _ = StrategicDecisions.fire(&s, StrategicDecisions.byID[defID]!, companyIndex: i, data: data, context: ctx, given: d)
            }
        }
        let bodies = e.state.inbox.filter { $0.actionID == StrategicDecisions.action }.map { $0.body.lowercased() }
        XCTAssertEqual(bodies.count, 2)
        for b in bodies {
            XCTAssertTrue(b.contains("cost") || b.contains("fee"), b)
            XCTAssertTrue(b.contains("benefit"), b)
            XCTAssertTrue(b.contains("risk"), b)
            XCTAssertTrue(b.contains("week") || b.contains("month end") || b.contains("year"), b)
        }
    }

    func testEveryNewDecisionIsRegisteredWithASafeDefault() {
        for id in ["m_tax", "m_quality", "m_bank", "m_bribe", "m_pol_donate", "m_pol_lobby"] {
            let def = StrategicDecisions.byID[id]
            XCTAssertNotNil(def, id)
            XCTAssertEqual(def?.opts.last?.label.isEmpty, false)
            XCTAssertEqual(def?.def, (def?.opts.count ?? 1) - 1, "\(id): an unanswered decision takes the last, safe answer")
        }
    }

    func testAllOptionsKeepTheBooksBalanced() throws {
        let (base, id) = try engine()
        let gives: [String: JSONValue] = [
            "m_tax": taxDecision(),
            "m_quality": .object(["save": 40_000, "risk": 0.1, "lsave": 8_000, "fee": 3_000, "fine": 60_000]),
            "m_bribe": .object(["cost": 25_000, "gain": 90_000, "p": 0.5, "risk": 0.1, "fine": 150_000]),
            "m_pol_donate": politicalDecision(ps: 0.1, pw: 0.4), "m_pol_lobby": politicalDecision(ps: 0.1, pw: 0.4)]
        for (defID, d) in gives {
            for option in 0..<(StrategicDecisions.byID[defID]?.opts.count ?? 0) {
                var e = base
                XCTAssertTrue(ask(&e, defID, id, given: d, option: option), "\(defID) \(option)")
                e.update { s, data, ctx in StrategicDecisions.weekly(&s, data: data, context: ctx) }
                XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(defID) option \(option)")
            }
        }
    }
}
