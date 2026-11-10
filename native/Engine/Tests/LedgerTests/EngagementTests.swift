import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

final class EngagementTests: XCTestCase {
    func game(seed: Int = 4242, weeks: Int = 6, open: Bool = true) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 80_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6 + 3_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        for _ in 0..<(weeks * 7) { e.nextDay() }
        if open { Self.openPages(&e, id) }
        return (e, id)
    }

    static func openPages(_ e: inout GameEngine, _ id: Int) {
        e.update { s, _, ctx in
            s.rest["ldr"] = nil
            if let i = s.companyIndex(id) { s.companies[i].openedWeek = s.week - 40 }
            Unlocks.weekly(&s, context: ctx)
        }
    }

    private func play(_ e: inout GameEngine, days: Int) {
        for _ in 0..<days {
            e.nextDay()
            for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
        }
    }

    private func play(_ e: inout GameEngine, until limit: Int, _ what: String, _ cond: (GameEngine) -> Bool) {
        for _ in 0..<limit { if cond(e) { return }; play(&e, days: 1) }
        XCTAssertTrue(cond(e), "never happened: \(what)")
    }

    func testPagesStayClosedInTheFirstSessionAndOpenLater() throws {
        var (e, id) = try game(open: false)
        XCTAssertFalse(e.deskOpen); XCTAssertFalse(e.weeklyPlanOpen)
        XCTAssertFalse(e.deskWaiting(realDay: 20_000))
        e.update { s, _, ctx in
            if let i = s.companyIndex(id) { s.companies[i].openedWeek = s.week - 40 }
            Unlocks.weekly(&s, context: ctx)
        }
        XCTAssertEqual(e.state.rest["ldr"] != nil, e.deskOpen == false, "the ladder holds the pages back")
        Self.openPages(&e, id)
        XCTAssertTrue(e.deskOpen); XCTAssertTrue(e.weeklyPlanOpen)
    }

    func testDeskDataIsWellFormedAndVariedByTrade() throws {
        let items = DeskStories.items, chapters = DeskStories.chapters
        XCTAssertGreaterThanOrEqual(items.count, 30)
        XCTAssertEqual(Set(items.map { $0.id }).count, items.count, "ids are unique")
        let allowed: Set<String> = ["dem", "cost", "rep", "aware", "mood", "pay", "gain"]
        for it in items {
            XCTAssertTrue(chapters.contains { $0.id == it.chapter }, it.id)
            XCTAssertTrue((2...3).contains(it.options.count), it.id)
            XCTAssertFalse(it.text.isEmpty); XCTAssertFalse(it.title.isEmpty)
            for o in it.options {
                XCTAssertTrue((1...3).contains(o.days), it.id)
                XCTAssertFalse(o.result.isEmpty); XCTAssertFalse(o.label.isEmpty)
                for fx in [o.fx, o.fxBad] {
                    XCTAssertTrue(Set(fx.object.keys).isSubset(of: allowed), "\(it.id): \(fx.object.keys)")
                    for k in ["dem", "cost"] where !fx[k].isNull {
                        XCTAssertTrue(DeskStories.demandRange.contains(fx[k][0].double), "\(it.id) \(k)")
                        XCTAssertTrue((1...4).contains(fx[k][1].int), "\(it.id) \(k) weeks")
                    }
                    XCTAssertLessThanOrEqual(fx["pay"].double, DeskStories.maxPay); XCTAssertLessThanOrEqual(fx["gain"].double, DeskStories.maxGain)
                    XCTAssertLessThanOrEqual(abs(fx["mood"].double), 4); XCTAssertLessThanOrEqual(abs(fx["rep"].double), 3); XCTAssertLessThanOrEqual(abs(fx["aware"].double), 3)
                }
                if o.chance != nil { XCTAssertFalse(o.resultBad.isEmpty, "\(it.id) needs a text for the bad branch") }
            }
        }
        func fitting(_ trade: String, _ family: String) -> Set<String> { Set(items.filter { $0.fits.contains("any") || $0.fits.contains(trade) || $0.fits.contains(family) }.map { $0.id }) }
        let gym = fitting("gym", "venue"), bank = fitting("bank", "fin")
        XCTAssertNotEqual(gym, bank)
        XCTAssertTrue(gym.contains("cus-gym")); XCTAssertFalse(bank.contains("cus-gym"))
        XCTAssertTrue(bank.contains("mon-bank")); XCTAssertFalse(gym.contains("mon-bank"))
        for set in [gym, bank, fitting("taxi", "logi"), fitting("grocery", "retail")] {
            for ch in chapters { XCTAssertGreaterThanOrEqual(items.filter { $0.chapter == ch.id && set.contains($0.id) }.count, ch.need, ch.id) }
        }
    }

    func testDeskItemIsStablePerDayDeterministicAndOutcomeArrivesNextMorning() throws {
        var (e, id) = try game()
        let day = 20_000
        XCTAssertTrue(e.deskWaiting(realDay: day))
        XCTAssertNil(e.deskToday(realDay: day))
        let t = try XCTUnwrap(e.deskOpenToday(realDay: day))
        XCTAssertEqual(t.companyID, id)
        XCTAssertEqual(try XCTUnwrap(e.deskOpenToday(realDay: day)).item.id, t.item.id, "same item all day")
        XCTAssertFalse(t.text.contains("{co}"))
        var (e2, _) = try game()
        XCTAssertEqual(try XCTUnwrap(e2.deskOpenToday(realDay: day)).item.id, t.item.id)

        let before = e.state.inbox.count
        let c = try XCTUnwrap(e.deskChoose(option: 0, realDay: day))
        XCTAssertFalse(e.deskWaiting(realDay: day), "the dot goes once decided")
        XCTAssertNil(e.deskChoose(option: 1, realDay: day), "one answer a day")
        XCTAssertEqual(e.deskPlayingOut, [t.item.title])
        XCTAssertEqual(e.state.inbox.count, before, "nothing yet")
        play(&e, days: c.days - 1)
        XCTAssertFalse(e.state.inbox.contains { $0.from == "Desk" && $0.title.hasPrefix(t.item.title) }, "not before its morning")
        play(&e, days: 1)
        let msg = try XCTUnwrap(e.state.inbox.first { $0.from == "Desk" && $0.title == "\(t.item.title): how it turned out" })
        XCTAssertEqual(msg.companyID, id)
        XCTAssertTrue(e.deskPlayingOut.isEmpty)
        let story = try XCTUnwrap(e.deskPages().flatMap { $0.stories }.first { $0.id == t.item.id })
        XCTAssertEqual(story.chosen, t.item.options[0].label)
        XCTAssertTrue(e.deskWaiting(realDay: day + 5))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testFinishingAChapterEarnsACoverAndAKnowledgeCardNotCash() throws {
        var (e, _) = try game()
        for d in 0..<14 {
            guard e.deskOpenToday(realDay: 30_000 + d) != nil else { XCTFail("an item every day"); return }
            e.deskChoose(option: 0, realDay: 30_000 + d)
            play(&e, days: 3)
            if !e.deskCovers().isEmpty { break }
        }
        XCTAssertFalse(e.deskCovers().isEmpty, "three finished stories in one chapter come within 13 days")
        let done = try XCTUnwrap(e.deskPages().first { $0.finished })
        XCTAssertNotNil(done.week)
        XCTAssertTrue(e.state.inbox.contains { $0.from == "Desk" && $0.title == "Notebook: \(done.chapter.name) is complete" })
        XCTAssertFalse(done.chapter.fact.isEmpty); XCTAssertFalse(done.chapter.cover.isEmpty)
    }

    func testDeskEffectsAreClampedAndSmall() throws {
        var (e, id) = try game()
        e.update { s, data, _ in
            let i = s.companyIndex(id)!
            let rep0 = s.companies[i].reputation, cash0 = s.companies[i].cash
            let wild: JSONValue = .object(["dem": .array([9.0, 40]), "cost": .array([0.1, 40]), "rep": 50, "aware": 50, "mood": 99, "pay": 5.0])
            DeskStories.apply(&s, i, wild, data: data)
            for m in s.companies[i].value("mods").array.suffix(2) {
                XCTAssertTrue(DeskStories.demandRange.contains(m["m"].double))
                XCTAssertLessThanOrEqual(m["w"].double, 5)
            }
            XCTAssertLessThanOrEqual(s.companies[i].reputation - rep0, 3.0001)
            let week = Engagement.lastWeekRevenue(s.companies[i])
            let cap = max(Engagement.spend(s, s.companies[i], share: 0, data: data), week * DeskStories.maxPay) + 1
            XCTAssertLessThanOrEqual(cash0 - s.companies[i].cash, cap)
        }
    }

    func testWeeklyPlanOffersOnePlanAnswerChangesBooksAndOutcomeIsToldNextWeek() throws {
        var (e, id) = try game()
        play(&e, until: 14, "a plan is offered") { $0.openDecisions.contains { $0.actionID == WeeklyFocus.action } }
        let ask = try XCTUnwrap(e.openDecisions.first { $0.actionID == WeeklyFocus.action })
        XCTAssertEqual(ask.companyID, id)
        XCTAssertGreaterThanOrEqual(ask.options.count, 3)
        XCTAssertEqual(e.openDecisions.filter { $0.actionID == WeeklyFocus.action }.count, 1)
        XCTAssertEqual(e.weeklyPlan.openMessageID, ask.id)
        var cash0 = 0.0, mods0 = 0
        e.update { s, _, _ in cash0 = s.company(id)!.cash; mods0 = s.company(id)!.value("mods").array.count }
        XCTAssertTrue(e.answer(messageID: ask.id, option: 0))
        e.update { s, _, _ in
            XCTAssertLessThan(s.company(id)!.cash, cash0, "the push costs a little marketing")
            let mods = s.company(id)!.value("mods").array
            XCTAssertEqual(mods.count, mods0 + 1)
            XCTAssertEqual(mods.last?["m"].double ?? 0, 1 + WeeklyFocus.effect, accuracy: 1e-9)
        }
        XCTAssertEqual(e.weeklyPlan.planned, 1)
        play(&e, until: 14, "the outcome is told") { $0.state.inbox.contains { $0.from == "Weekly plan" && $0.title.hasPrefix("Last week's plan") } }
        XCTAssertEqual(e.weeklyPlanResults.count, 1)
        play(&e, until: 14, "the next plan") { $0.openDecisions.contains { $0.actionID == WeeklyFocus.action && $0.id != ask.id } }
        let next = try XCTUnwrap(e.openDecisions.first { $0.actionID == WeeklyFocus.action })
        play(&e, until: 21, "a newer plan after skipping one") { $0.openDecisions.contains { $0.actionID == WeeklyFocus.action && $0.id != next.id } }
        XCTAssertEqual(e.weeklyPlan.planned, 1)
        XCTAssertNotEqual(e.state.inbox.first { $0.id == next.id }?.status, "open")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testPlannerPerkGrowsWithPlannedWeeksAndIsBounded() {
        XCTAssertEqual(WeeklyFocus.strength(0), WeeklyFocus.effect, accuracy: 1e-12)
        XCTAssertEqual(WeeklyFocus.strength(4), WeeklyFocus.effect * (1 + WeeklyFocus.perkStep), accuracy: 1e-12)
        XCTAssertEqual(WeeklyFocus.strength(400), WeeklyFocus.effect * (1 + WeeklyFocus.perkStep * Double(WeeklyFocus.perkTiers)), accuracy: 1e-12)
        XCTAssertLessThanOrEqual(WeeklyFocus.strength(400), 0.06)
    }

    func testDeskReminderIsTheExistingIdleReminderAndOnlyOnceTheDeskIsOpen() throws {
        var (e, _) = try game(open: false)
        XCTAssertFalse(SessionHooks.reminders(e.state).contains { $0.title == "The Desk" })
        Self.openPages(&e, e.state.companies[0].id)
        let r = SessionHooks.reminders(e.state)
        XCTAssertTrue(r.allSatisfy { ["ledger.expiry", "ledger.goal", "ledger.idle"].contains($0.id) })
    }
}
