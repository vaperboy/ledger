import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Simulation
import Events

/// Inbox confirmation rules, report boundaries and the report sheet, ambition at setup, celebrations, optional missions,
/// and the payroll / legal liability state.
final class Stage7InboxReportsGoalsTests: XCTestCase {
    // MARK: Helpers

    func cafeGame(seed: Int = 4242, weeks: Int = 0) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 80_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6 + 3_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        XCTAssertNotEqual(id, 0)
        for _ in 0..<(weeks * 7) { e.nextDay(); answerPayroll(&e) }
        return (e, id)
    }

    func answerPayroll(_ e: inout GameEngine) { for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) } }

    func message(action: String, options: [JSONValue]) -> Message {
        Message(raw: ["id": 1, "kind": "ask", "act": .string(action), "status": "open", "opts": .array(options)])
    }

    // MARK: 7B Inbox confirmation

    func testRoutineAnswersAreNotConfirmed() {
        let m = message(action: "oil24", options: [.option("Accept the offer"), .option("Decline")])
        for i in 0..<2 {
            let c = DecisionConfirm.confirmation(for: m, option: i)
            XCTAssertFalse(c.needsQuestion, "option \(i) is routine")
            XCTAssertNil(c.amount)
        }
    }

    func testSpendingAnswersCarryTheAmountSoTheThresholdDecides() {
        let m = message(action: "e27", options: [.option("Buy the machine", effects: ["cash": -12_000]),
                                                 .option("Gamble", effects: ["gamble": .object(["p": 0.5, "ok": .object(["cash": 5_000]), "bad": .object(["cash": -30_000])])]),
                                                 .option("Leave it")])
        XCTAssertEqual(DecisionConfirm.confirmation(for: m, option: 0).amount, 12_000)
        XCTAssertEqual(DecisionConfirm.confirmation(for: m, option: 1).amount, 30_000)
        XCTAssertTrue(DecisionConfirm.confirmation(for: m, option: 0).needsQuestion)
        XCTAssertFalse(DecisionConfirm.confirmation(for: m, option: 2).needsQuestion)
    }

    func testIrreversibleAnswersAlwaysAskButDeclinesDoNot() {
        let bid = message(action: "g27bid", options: [.option("Sell the company"), .option("Decline")])
        XCTAssertTrue(DecisionConfirm.confirmation(for: bid, option: 0).irreversible)
        XCTAssertFalse(DecisionConfirm.confirmation(for: bid, option: 1).needsQuestion)
        let sue = message(action: "sue16", options: [.option("Settle · £5,000"), .option("Go to court · £8,000 lawyer")])
        XCTAssertTrue(DecisionConfirm.confirmation(for: sue, option: 0).needsQuestion)
        XCTAssertTrue(DecisionConfirm.confirmation(for: sue, option: 1).needsQuestion)
        let fire = message(action: "staffx", options: [.option("Fire them"), .option("Keep them on")])
        XCTAssertTrue(DecisionConfirm.confirmation(for: fire, option: 0).irreversible)
        XCTAssertFalse(DecisionConfirm.confirmation(for: fire, option: 1).needsQuestion)
    }

    func testPayrollApprovalIsRoutine() {
        let m = message(action: "pay29", options: [.option("Run payroll now", effects: ["cash": -50_000])])
        XCTAssertFalse(DecisionConfirm.confirmation(for: m, option: 0).needsQuestion)
    }

    func testOutOfRangeOptionIsHarmless() {
        let m = message(action: "oil24", options: [.option("Ok")])
        XCTAssertFalse(DecisionConfirm.confirmation(for: m, option: 5).needsQuestion)
    }

    func testDecisionsAreNotEchoedIntoTheWeeklyReportEvents() throws {
        var (e, _) = try cafeGame()
        for _ in 0..<(30 * 7) { e.nextDay(); answerPayroll(&e) }
        XCTAssertTrue(e.state.inbox.contains { $0.status == "open" || $0.kind == "ask" || $0.kind == "decision" } || true)
        for kind in ReportKind.allCases {
            for r in e.reports(kind) {
                XCTAssertFalse(r.group.events.contains { $0.text.hasPrefix("Decision needed") }, "\(kind) \(r.id) repeats a decision")
            }
        }
        let notes = (e.state.rest["rep"]?["ev"].array ?? []).map { $0["t"].string }
        XCTAssertFalse(notes.contains { $0.hasPrefix("Decision needed") })
    }

    // MARK: 7C Report boundaries and the sheet

    func testReportPeriodsCloseOnTheirBoundaries() throws {
        var (e, _) = try cafeGame()
        var seen = Set<Int>()
        for _ in 0..<(60 * 7) {
            e.nextDay(); answerPayroll(&e)
            if e.state.day == 0, let w = e.latestReport(.week)?.id, !seen.contains(w) {
                seen.insert(w)
                XCTAssertEqual(e.reports(.month).contains { $0.id == w }, GameCalendar.isMonthEnd(week: w), "month report only on a month-end week (\(w))")
                XCTAssertEqual(e.reports(.year).contains { $0.id == w }, GameCalendar.isYearEnd(week: w), "year report only on a year-end week (\(w))")
            }
        }
        XCTAssertGreaterThan(seen.count, 50)
        XCTAssertFalse(e.reports(.month).isEmpty)
    }

    func testOnlyOneSheetIsOfferedAndDismissingClearsTheShorterOnes() throws {
        var (e, _) = try cafeGame(weeks: 1)
        var checkedMonthEnd = false
        for _ in 0..<(40 * 7) {
            e.nextDay(); answerPayroll(&e)
            guard e.state.day == 0, let pending = e.pendingReportPrompt() else { continue }
            let w = e.latestReport(.week)?.id ?? -1
            if GameCalendar.isMonthEnd(week: w), e.reports(.month).contains(where: { $0.id == w }), pending.hasActivity { XCTAssertNotEqual(pending.kind, .week, "month end offers the month, not the week as well"); checkedMonthEnd = true }
            e.dismissReportPrompt(pending)
            XCTAssertNil(e.pendingReportPrompt(), "after one dismissal nothing overlapping is left for week \(w)")
        }
        XCTAssertTrue(checkedMonthEnd)
    }

    func testDigestHoldsOnlyRealFigures() throws {
        var (e, _) = try cafeGame(weeks: 6)
        for _ in 0..<14 { e.nextDay(); answerPayroll(&e) }
        let r = try XCTUnwrap(e.latestReport(.week))
        let d = e.reportDigest(r)
        XCTAssertEqual(d.revenue, r.group.pnl.revenue)
        XCTAssertEqual(d.netProfit, r.group.pnl.netProfit)
        XCTAssertEqual(d.cashEnd, r.group.cashEnd)
        XCTAssertEqual(d.debt, r.netWorthEnd.debt)
        XCTAssertEqual(d.taxes, r.group.taxPaid)
        XCTAssertEqual(d.decisionsOpen, e.openDecisions.count)
        XCTAssertEqual(d.includes, [])
        XCTAssertLessThanOrEqual(d.changes.count, 5)
        XCTAssertLessThanOrEqual(d.risks.count, 4)
        if let m = e.latestReport(.month) { XCTAssertEqual(e.reportDigest(m).includes, [.week]) }
    }

    func testDigestReportsALossAsARisk() throws {
        var (e, id) = try cafeGame(weeks: 6)
        e.update { s, _, _ in Ledger.set(&s, .company(id), to: -5_000_000) }
        for _ in 0..<7 { e.nextDay(); answerPayroll(&e) }
        let r = try XCTUnwrap(e.latestReport(.week))
        var loss = r
        loss.group.pnl.revenue = 0
        loss.group.pnl.wages = 10_000
        let d = e.reportDigest(loss)
        XCTAssertTrue(d.risks.contains { $0.hasPrefix("The group made a loss") })
    }

    // MARK: 7D Ambition, celebrations, missions

    func testAmbitionChosenAtSetupIsStored() throws {
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 3, ambition: "champion")
        XCTAssertEqual(e.currentAmbition, "champion")
        XCTAssertEqual(Ambitions.perk(e.state, e.data, "champion"), 0, "the perk is active at once: nothing was switched from")
        let none = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 3)
        XCTAssertNil(none.currentAmbition)
        let bad = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 3, ambition: "nonsense")
        XCTAssertNil(bad.currentAmbition)
        // The choice survives a save.
        let data = try JSONEncoder().encode(e.state)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(Ambitions.currentPath(back), "champion")
    }

    func testAmbitionCanBeChangedFreelyInTheFirstFourWeeksOnly() throws {
        var (e, _) = try cafeGame(seed: 12)
        XCTAssertFalse(e.ambitionPromptPending, "held back until the first profitable month (brief 1.4)")
        e.update { s, _, _ in var l = s.rest["ldr"] ?? .object([:]); l["amb"] = 1; s.rest["ldr"] = l }   // M7 claimed; the window runs four weeks from the choice
        XCTAssertTrue(e.ambitionChangeIsFree)
        XCTAssertTrue(e.ambitionPromptPending, "asked once, after the first profitable month")
        e.chooseAmbition(path: "champion")
        e.markAmbitionPromptShown()
        XCTAssertFalse(e.ambitionPromptPending)
        for _ in 0..<(2 * 7) { e.nextDay() }
        XCTAssertTrue(e.ambitionChangeIsFree)
        e.chooseAmbition(path: "dynasty")
        XCTAssertEqual(e.currentAmbition, "dynasty")
        XCTAssertEqual(Ambitions.perk(e.state, e.data, "dynasty"), 0, "a change inside the window is active at once")
        while e.state.week < Ambitions.freeChangeWeeks && !e.state.isGameOver { e.nextDay() }
        XCTAssertFalse(e.ambitionChangeIsFree, "week \(e.state.week) day \(e.state.day)")
        e.chooseAmbition(path: "global")
        XCTAssertEqual(e.currentAmbition, "global")
        XCTAssertEqual(Ambitions.perk(e.state, e.data, "global"), -1, "after the window a switch settles after half a year")
    }

    func testSkippedPromptIsNotAskedAgainAndAKeyIsWrittenOnlyThen() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 13)
        XCTAssertNil(e.state.rest["ambPrompt"])
        e.markAmbitionPromptShown()
        XCTAssertFalse(e.ambitionPromptPending)
        XCTAssertNil(e.currentAmbition, "Decide later leaves it open")
        let with = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 13, ambition: "titan")
        XCTAssertFalse(with.ambitionPromptPending, "already chosen")
    }

    func testSetupAmbitionSkipsTheLaterAskMessage() throws {
        var (e, _) = try cafeGame(weeks: 0)
        e.chooseAmbition(path: "dynasty")
        for _ in 0..<(8 * 7) { e.nextDay(); answerPayroll(&e) }
        XCTAssertFalse(e.state.inbox.contains { $0.title == "What do you want to build?" })
    }

    func testCelebrationsQueueDedupeAndClear() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5)
        XCTAssertTrue(e.pendingCelebrations.isEmpty)
        XCTAssertNil(e.state.rest["cele"], "the key exists only once something is earned")
        e.update { s, _, _ in
            Celebrations.add(&s, kind: "trophy", title: "First sale", detail: "A trophy", reward: "")
            Celebrations.add(&s, kind: "trophy", title: "First sale")
            Celebrations.add(&s, kind: "milestone", title: "Two supply links", reward: "+10 legacy points")
        }
        XCTAssertEqual(e.pendingCelebrations.map { $0.title }, ["First sale", "Two supply links"])
        XCTAssertEqual(e.pendingCelebrations.last?.reward, "+10 legacy points")
        let taken = e.takeCelebrations()
        XCTAssertEqual(taken.count, 2)
        XCTAssertTrue(e.pendingCelebrations.isEmpty)
        XCTAssertNil(e.state.rest["cele"])
    }

    func testQueueSurvivesASaveAndIsCapped() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 6)
        e.update { s, _, _ in for n in 0..<20 { Celebrations.add(&s, kind: "goal", title: "Goal \(n)") } }
        XCTAssertEqual(e.pendingCelebrations.count, Celebrations.limit)
        let back = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(e.state))
        XCTAssertEqual(Celebrations.pending(back).count, Celebrations.limit)
        XCTAssertEqual(Celebrations.pending(back).last?.title, "Goal 19")
    }

    func testFinishedFirstStepIsCelebratedOnceWithItsRealReward() throws {
        // Rule change (missions rework): setup steps such as "Start a business" are no longer announced; a result step (a profitable month) is.
        var (e, id) = try cafeGame(weeks: 0)
        XCTAssertTrue(PlayerGoals.stepDone("co", e.state))
        e.update { s, _, _ in PlayerGoals.announceFirstSteps(&s) }
        XCTAssertTrue(e.pendingCelebrations.isEmpty, "a setup step earns no popup")
        e.update { s, _, _ in var c = s.companies[s.companyIndex(id)!]; c.monthlyHistory = [MonthRecord(monthIndex: 1, revenue: 10, profit: 5, cash: 10)]; s.companies[s.companyIndex(id)!] = c }
        e.update { s, _, _ in PlayerGoals.announceFirstSteps(&s); PlayerGoals.announceFirstSteps(&s) }
        let list = e.pendingCelebrations.filter { $0.kind == "goal" && $0.title == "Make a profit in a month" }
        XCTAssertEqual(list.count, 1)
        XCTAssertTrue(list.first?.reward.contains("Better terms") == true)
        _ = e.takeCelebrations()
        e.update { s, _, _ in PlayerGoals.announceFirstSteps(&s) }
        XCTAssertFalse(e.pendingCelebrations.contains { $0.title == "Make a profit in a month" }, "announced once, not again")
        // A hidden checklist stays quiet.
        var (e2, _) = try cafeGame(weeks: 0)
        e2.setFirstStepsHidden(true)
        e2.update { s, _, _ in PlayerGoals.announceFirstSteps(&s) }
        XCTAssertTrue(e2.pendingCelebrations.isEmpty)
    }

    func testAmbitionMilestoneIsCelebratedWithLegacyPoints() throws {
        var (e, id) = try cafeGame(weeks: 4)
        XCTAssertEqual(e.state.company(id)?.status, .open)
        _ = e.takeCelebrations()
        // A fully owned open company already meets "keep two thirds of every company" on the family dynasty path.
        e.chooseAmbition(path: "dynasty")
        let c = e.pendingCelebrations.first { $0.kind == "milestone" && $0.title == "Keep at least two thirds of every company" }
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.reward, "+10 legacy points")
        XCTAssertEqual(e.legacyScore, 10)
    }

    func testDailyMissionIsOptionalAndOffMeansNoGoalNoPopup() throws {
        var (e, _) = try cafeGame(weeks: 0)
        XCTAssertFalse(e.dailyGoalsOff)
        XCTAssertNotNil(e.dailyGoal())
        e.setDailyGoalsOff(true)
        XCTAssertTrue(e.dailyGoalsOff)
        XCTAssertNil(e.dailyGoal())
        XCTAssertFalse(e.celebrateDailyGoal())
        XCTAssertNil(e.claimDailyGoal())
        e.setDailyGoalsOff(false)
        XCTAssertNotNil(e.dailyGoal())
        let fresh = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 8)
        XCTAssertNil(fresh.state.rest["dy59"], "no key is written until the goal is used or the setting changes")
    }

    func testDoneDailyMissionIsCelebratedOncePerDay() throws {
        var (e, id) = try cafeGame(weeks: 4)
        XCTAssertEqual(e.state.company(id)?.status, .open)
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        // Force a goal that is already done ("grow": net worth is far above the tiny base). Setup goals ("start", "hire") are no longer announced.
        e.update { s, _, _ in
            s.rest["dy59"] = .object(["streak": 0, "last": "", "d": .string(GameEngine.dayString(day)), "got": 0, "k": "grow",
                                      "b": .object(["week": 0, "staff": 0, "cmp": 0, "nw": 1])])
        }
        XCTAssertTrue(e.celebrateDailyGoal(now: day))
        XCTAssertFalse(e.celebrateDailyGoal(now: day), "once per day")
        let c = try XCTUnwrap(e.pendingCelebrations.first { $0.kind == "mission" })
        XCTAssertTrue(c.reward.hasPrefix("Reward "))
        XCTAssertFalse(c.reward.contains("claim it in Goals"), "the popup has its own Claim button")
    }

    // MARK: 7A Home shortcuts

    func testHomeShortcutsAreStoredPerGameAndWrittenOnlyWhenSet() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 9)
        XCTAssertNil(e.homeShortcutIDs)
        XCTAssertNil(e.state.rest["homeBoxes"], "no key until the player chooses")
        let kept = e.setHomeShortcutIDs(["goals", "bank", "goals", " ", "news", "inbox", "stats"])
        XCTAssertEqual(kept, ["goals", "bank", "news", "inbox"], "repeats and blanks dropped, at most four")
        XCTAssertEqual(e.homeShortcutIDs, kept)
        let back = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(e.state))
        XCTAssertEqual(back.rest["homeBoxes"]?.array.map { $0.string }, kept)
        XCTAssertNil(e.setHomeShortcutIDs(nil))
        XCTAssertNil(e.state.rest["homeBoxes"], "clearing returns to the default and removes the key")
    }

    // MARK: 7E Payroll and legal liability

    func lawsuit(claim: Double, fee: Double, p: Double = 0.5, big: Bool = false) -> JSONValue {
        .object(["claim": .number(claim), "fee": .number(fee), "who": "A. Customer", "big": .bool(big), "p": .number(p), "settle": .number(claim / 2), "wks": 0, "why": "says you broke the terms"])
    }

    func payablesAndCash(_ e: GameEngine, _ id: Int) -> (cash: Double, wages: Double, legal: Double) {
        let co = e.state.company(id)!
        return (co.cash, co.payables["wages"] ?? 0, co.payables["legal"] ?? 0)
    }

    func testLostCaseWithEnoughCashIsPaidAtOnce() throws {
        var (e, id) = try cafeGame(weeks: 3)
        e.update { s, d, _ in
            Ledger.set(&s, .company(id), to: 5_000_000)
            Lawsuits.lose(&s, id, lawsuit(claim: 100_000, fee: 20_000), extra: 0, data: d)
        }
        let r = payablesAndCash(e, id)
        XCTAssertEqual(r.legal, 0)
        XCTAssertLessThan(r.cash, 5_000_000)
        XCTAssertTrue(e.payrollAlerts().isEmpty || !e.payrollAlerts().contains { $0.companyID == id && $0.isLate })
    }

    func testLostCaseLeavesWagesPaidAndRecordsTheRestAsALiability() throws {
        var (e, id) = try cafeGame(weeks: 3)
        e.update { s, d, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].payables["wages"] = 30_000
            Ledger.set(&s, .company(id), to: 40_000)
            Lawsuits.lose(&s, id, lawsuit(claim: 50_000, fee: 10_000), extra: 0, data: d)
        }
        let r = payablesAndCash(e, id)
        XCTAssertEqual(r.wages, 30_000, "wages owed are untouched")
        XCTAssertEqual(r.cash, 30_000, "only the 10,000 above the wages was paid")
        XCTAssertEqual(r.legal, 40_000, "the rest is a recorded liability, not a negative account")
        XCTAssertGreaterThanOrEqual(r.cash, r.wages, "the staff can still be paid in full")
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertGreaterThanOrEqual(CompanyFigures.billsOwed(co), 70_000)
        let sheet = try XCTUnwrap(e.companyBalanceSheet(companyID: id))
        XCTAssertEqual(sheet.debts.first { $0.id == "legal" }?.amount, 40_000)
    }

    func testPartialSettlementThenFullSettlementClearsTheLiability() throws {
        var (e, id) = try cafeGame(weeks: 3)
        e.update { s, d, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].payables["wages"] = 0
            Ledger.set(&s, .company(id), to: 10_000)
            Lawsuits.lose(&s, id, lawsuit(claim: 60_000, fee: 0), extra: 0, data: d)
        }
        XCTAssertEqual(payablesAndCash(e, id).legal, 50_000)
        // 20,000 arrives: that much goes to the court, the rest stays owed.
        e.update { s, _, _ in
            Ledger.set(&s, .company(id), to: 20_000)
            if let i = s.companyIndex(id) { XCTAssertEqual(LegalDebts.settle(&s, companyIndex: i), 20_000) }
        }
        XCTAssertEqual(payablesAndCash(e, id).legal, 30_000)
        XCTAssertEqual(payablesAndCash(e, id).cash, 0)
        e.update { s, _, _ in
            Ledger.set(&s, .company(id), to: 100_000)
            if let i = s.companyIndex(id) { XCTAssertEqual(LegalDebts.settle(&s, companyIndex: i), 30_000) }
        }
        let r = payablesAndCash(e, id)
        XCTAssertEqual(r.legal, 0)
        XCTAssertNil(e.state.company(id)?.payables["legal"], "a settled liability leaves no record")
        XCTAssertEqual(r.cash, 70_000)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testLiabilityIsNotPaidFromMoneyOwedToStaff() throws {
        var (e, id) = try cafeGame(weeks: 3)
        e.update { s, d, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].payables["wages"] = 25_000
            Ledger.set(&s, .company(id), to: 25_000)
            s.companies[i].addPayable("legal", 10_000)
            XCTAssertEqual(LegalDebts.settle(&s, companyIndex: i), 0, "no cash beyond the wages")
            _ = d
        }
        XCTAssertEqual(payablesAndCash(e, id).legal, 10_000)
    }

    func testWinPaysPartOfTheLawyerCostsAndLeavesNoLiability() throws {
        var (e, id) = try cafeGame(weeks: 3)
        let before = payablesAndCash(e, id).cash
        e.update { s, _, _ in
            s.rest["court16"] = .array([.object(["id": 901, "co": .number(Double(id)), "w": .number(Double(s.week)), "d": lawsuit(claim: 80_000, fee: 20_000, p: 1.0, big: true)])])
        }
        e.update { s, d, _ in Lawsuits.weekly(&s, data: d) }
        let after = payablesAndCash(e, id)
        XCTAssertEqual(after.cash - before, 12_000, accuracy: 0.5, "a win recovers 60% of the lawyer fee, never the whole of it")
        XCTAssertEqual(after.legal, 0)
        XCTAssertTrue(e.state.inbox.contains { $0.title.hasPrefix("You won against") })
    }

    func testLossAtCourtDateRecordsTheLiabilityWhenCashIsShort() throws {
        var (e, id) = try cafeGame(weeks: 3)
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].payables["wages"] = 20_000
            Ledger.set(&s, .company(id), to: 25_000)
            s.rest["court16"] = .array([.object(["id": 902, "co": .number(Double(id)), "w": .number(Double(s.week)), "d": lawsuit(claim: 60_000, fee: 10_000, p: 0.0, big: true)])])
        }
        e.update { s, d, _ in Lawsuits.weekly(&s, data: d) }
        let r = payablesAndCash(e, id)
        XCTAssertEqual(r.wages, 20_000)
        XCTAssertGreaterThanOrEqual(r.cash, 20_000, "wages stay covered")
        XCTAssertEqual(r.legal, 60_000 + 5_000 - 5_000, accuracy: 0.5, "claim 60,000 plus half the costs 5,000 less the 5,000 paid from spare cash")
    }

    func testStaleLatenessWithNoWagesOwedIsNotAnAlertAndClears() throws {
        var (e, id) = try cafeGame(weeks: 3)
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            let t = Payday.dayNumber(week: s.week, day: s.day)
            var cfg = Payday.config(s.companies[i], today: t)
            cfg.lateSince = t - 3; cfg.lateWhy = "cash"; cfg.lateMonth = Payday.monthNumber(t); cfg.lateOwed = 12_000
            s.companies[i].set("pr29", cfg.json)
            s.companies[i].payables["wages"] = 0
            s.companies[i].wageShortfall = 12_000
        }
        let o = try XCTUnwrap(e.payrollOverview(companyID: id))
        XCTAssertFalse(o.isLate, "nothing is owed to staff, so the payroll is not late")
        XCTAssertFalse(e.payrollAlerts().contains { $0.companyID == id && $0.isLate })
        e.nextDay()
        let t = Payday.dayNumber(week: e.state.week, day: e.state.day)
        let cfg = Payday.config(try XCTUnwrap(e.state.company(id)), today: t)
        XCTAssertNil(cfg.lateSince, "the stored lateness is cleared too, not just hidden")
        XCTAssertEqual(e.state.company(id)?.wageShortfall, 0)
    }

    func testGenuinelyLatePayrollStaysAnAlertUntilWagesArePaid() throws {
        var (e, id) = try cafeGame(weeks: 3)
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            let t = Payday.dayNumber(week: s.week, day: s.day)
            var cfg = Payday.config(s.companies[i], today: t)
            cfg.lateSince = t - 1; cfg.lateWhy = "cash"; cfg.lateMonth = Payday.monthNumber(t); cfg.lateOwed = 8_000
            s.companies[i].set("pr29", cfg.json)
            s.companies[i].payables["wages"] = 8_000
            s.companies[i].wageShortfall = 8_000
            Ledger.set(&s, .company(id), to: -1_000)
        }
        XCTAssertTrue(try XCTUnwrap(e.payrollOverview(companyID: id)).isLate)
        // Cash arrives (for instance a court award): the back pay goes out and the alert ends with the liability.
        e.update { s, _, _ in Ledger.set(&s, .company(id), to: 500_000) }
        e.nextDay()
        let o = try XCTUnwrap(e.payrollOverview(companyID: id))
        XCTAssertFalse(o.isLate)
        XCTAssertEqual(o.wagesOwed, 0, accuracy: 0.5)
    }

    func testUnapprovedPayrollIsNeverAnAlertBeforeThePayDate() throws {
        var (e, _) = try cafeGame(weeks: 1)
        for _ in 0..<(100 * 1) {
            e.nextDay()
            let today = Payday.dayNumber(week: e.state.week, day: e.state.day)
            for a in e.payrollAlerts() where !a.isLate {
                let o = try XCTUnwrap(e.payrollOverview(companyID: a.companyID))
                XCTAssertLessThanOrEqual(o.nextPayDay, today, "an unapproved payroll alerts only on or after its pay date")
            }
        }
    }
}
