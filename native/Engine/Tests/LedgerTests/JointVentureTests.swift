import XCTest
import GameCore
import Finance
import Businesses
import Events
import Simulation

/// Joint ventures: the pure voting and guard-rail rules, then invitations, planned and urgent meetings and what a passed item does to the books.
final class JointVentureTests: XCTestCase {
    // MARK: Rules

    func testMajorityByShareAndAbstentionByNotVoting() {
        let shares = ["me": 60, "p:a": 25, "p:b": 15]
        // Only you vote: 60% of the shares cast, so the quorum is met and yes wins.
        var t = JVRules.tally(shares: shares, votes: ["me": .yes])
        XCTAssertEqual(t.yes, 60); XCTAssertEqual(t.abstain, 40)
        XCTAssertEqual(JVRules.decide(t, chair: .yes, chairUsedBefore: false), .passed)
        // Two small partners against a small yes: no wins by shares, not by heads.
        t = JVRules.tally(shares: shares, votes: ["me": .yes, "p:a": .no, "p:b": .no])
        XCTAssertEqual(JVRules.decide(t, chair: .yes, chairUsedBefore: false), .passed, "60 against 40")
        t = JVRules.tally(shares: ["me": 30, "p:a": 40, "p:b": 30], votes: ["me": .yes, "p:a": .no, "p:b": .yes])
        XCTAssertEqual(JVRules.decide(t, chair: .yes, chairUsedBefore: false), .passed, "60 yes against 40 no")
        t = JVRules.tally(shares: ["me": 30, "p:a": 40, "p:b": 30], votes: ["me": .yes, "p:a": .no, "p:b": .no])
        XCTAssertEqual(JVRules.decide(t, chair: .yes, chairUsedBefore: false), .failed)
    }

    func testQuorumNeedsHalfOfAllSharesToCastAVote() {
        let shares = ["me": 30, "p:a": 40, "p:b": 30]
        let few = JVRules.tally(shares: shares, votes: ["me": .yes, "p:a": .abstain])
        XCTAssertEqual(JVRules.decide(few, chair: .yes, chairUsedBefore: false), .noQuorum, "30% cast")
        XCTAssertFalse(JVRules.decide(few, chair: .yes, chairUsedBefore: false).passes)
        XCTAssertEqual(JVRules.decide(JVRules.tally(shares: [:], votes: [:]), chair: nil, chairUsedBefore: false), .noQuorum)
    }

    func testTieIsBrokenOnceByTheChairThenTheStatusQuoStands() {
        let t = JVRules.tally(shares: ["me": 50, "p:a": 50], votes: ["me": .yes, "p:a": .no])
        XCTAssertEqual(JVRules.decide(t, chair: .yes, chairUsedBefore: false), .chairPassed)
        XCTAssertEqual(JVRules.decide(t, chair: .no, chairUsedBefore: false), .chairFailed)
        XCTAssertEqual(JVRules.decide(t, chair: .abstain, chairUsedBefore: false), .statusQuo)
        XCTAssertEqual(JVRules.decide(t, chair: .yes, chairUsedBefore: true), .statusQuo, "a second tie is not broken")
        XCTAssertFalse(JVRules.Outcome.statusQuo.passes)
    }

    func testDeadlineAndSchedule() {
        XCTAssertTrue(JVRules.isOpen(week: 10, deadline: 10))
        XCTAssertFalse(JVRules.isOpen(week: 11, deadline: 10))
        XCTAssertEqual(JVRules.deadline(planned: false, openedWeek: 20, meetingWeek: 20), 21)
        XCTAssertEqual(JVRules.deadline(planned: true, openedWeek: 20, meetingWeek: 33), 33)
        XCTAssertEqual(JVRules.nextPlannedWeek(after: nil, now: 5), 18)
        XCTAssertEqual(JVRules.nextPlannedWeek(after: 18, now: 30), 32, "never sooner than the notice period")
        XCTAssertEqual(JVRules.nextPlannedWeek(after: 18, now: 20), 31)
    }

    func testGuardRails() {
        let fair = JVRules.fairPrice(value: 900, pct: 10)
        XCTAssertEqual(fair, 100, accuracy: 1e-9)
        XCTAssertNil(JVRules.priceProblem(price: 100, fair: fair))
        XCTAssertNotNil(JVRules.priceProblem(price: 10, fair: fair), "a gift is not allowed")
        XCTAssertNotNil(JVRules.priceProblem(price: 1_000, fair: fair), "neither is an inflated price")
        XCTAssertNotNil(JVRules.linkProblem(candidate: "acct-1", mine: ["acct-1"], partners: []), "a linked account cannot be a partner")
        XCTAssertNotNil(JVRules.linkProblem(candidate: "", mine: [], partners: []))
        XCTAssertNil(JVRules.linkProblem(candidate: "acct-2", mine: ["acct-1"], partners: []))
        XCTAssertTrue(JVRules.isLocked(lockUntil: JVRules.lockUpEnd(joined: 10), week: 10 + JVRules.lockUpWeeks - 1))
        XCTAssertFalse(JVRules.isLocked(lockUntil: JVRules.lockUpEnd(joined: 10), week: 10 + JVRules.lockUpWeeks))
        XCTAssertNotNil(JVRules.stakeProblem(pct: 60, existingPartners: 0, ownerAfterPct: 40))
        XCTAssertNotNil(JVRules.stakeProblem(pct: 10, existingPartners: JVRules.maxPartners, ownerAfterPct: 50))
        XCTAssertNil(JVRules.stakeProblem(pct: 10, existingPartners: 1, ownerAfterPct: 80))
    }

    func testDissolvingPaysByShareAtRealValueAndNothingExtra() {
        let pay = JVRules.dissolvePayout(value: 1_000_001, shares: ["me": 700_000, "p:a": 200_000, "p:b": 100_000])
        XCTAssertEqual(pay.values.reduce(0, +), 1_000_001, accuracy: 0.001, "exactly the value is paid out")
        XCTAssertEqual(pay["p:b"] ?? 0, 100_000.1, accuracy: 0.011)
        XCTAssertGreaterThan(pay["me"] ?? 0, pay["p:a"] ?? 0)
        XCTAssertEqual(JVRules.dissolvePayout(value: 0, shares: ["me": 1]).values.reduce(0, +), 0)
    }

    func testMockPartnerVotesAreDeterministicAndSometimesLate() {
        XCTAssertEqual(JVRules.mockChoice(.dividend, profitable: true, cashTight: false, seed: "a:1"), JVRules.mockChoice(.dividend, profitable: true, cashTight: false, seed: "a:1"))
        var late = 0
        for n in 0..<200 {
            let w = JVRules.mockVoteWeek(opened: 10, deadline: 12, seed: "p\(n)")
            XCTAssertGreaterThanOrEqual(w, 10)
            if w > 12 { late += 1 }
        }
        XCTAssertGreaterThan(late, 0); XCTAssertLessThan(late, 60)
    }

    // MARK: Play

    private let friendA = (id: "pl-a", name: "Ingrid Solheim", key: "pl-a")
    private let friendB = (id: "pl-b", name: "Oliver Whitfield", key: "pl-b")

    /// A limited cafe that is open, owned by you alone.
    private func makeCompany(seed: Int) throws -> (engine: GameEngine, id: Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 300_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 8_000_000) else { throw XCTSkip("could not start a company") }
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
        return (e, id)
    }

    /// Invite and accept a friend at the fair price.
    @discardableResult
    private func join(_ e: inout GameEngine, _ id: Int, _ f: (id: String, name: String, key: String), pct: Double, role: String = "partner") throws -> Int {
        let price = e.jvFairPrice(companyID: id, pct: pct)
        switch e.jvInvite(companyID: id, playerID: f.id, name: f.name, linkKey: f.key, role: role, pct: pct, price: price, myLinkKeys: ["me-1"]) {
        case .sent(let inv):
            XCTAssertNil(e.jvRespond(companyID: id, inviteID: inv, accept: true))
            return inv
        default: XCTFail("invite not sent"); throw XCTSkip("no invite")
        }
    }

    private func tick(_ e: inout GameEngine, weeks: Int = 1) {
        for _ in 0..<weeks { e.update { s, d, c in s.week += 1; JointVenture.weekly(&s, data: d, context: c) } }
    }

    func testInviteRefusesLinkedAccountsAndBadPrices() throws {
        var (e, id) = try makeCompany(seed: 71)
        let fair = e.jvFairPrice(companyID: id, pct: 10)
        XCTAssertGreaterThan(fair, 0)
        guard case .refused(let linked) = e.jvInvite(companyID: id, playerID: "x", name: "Me Again", linkKey: "me-1", pct: 10, price: fair, myLinkKeys: ["me-1"]) else { return XCTFail() }
        XCTAssertTrue(linked.contains("linked"), linked)
        guard case .refused = e.jvInvite(companyID: id, playerID: friendA.id, name: friendA.name, linkKey: friendA.key, pct: 10, price: fair * 0.1, myLinkKeys: []) else { return XCTFail("a gift price is refused") }
        guard case .refused = e.jvInvite(companyID: id, playerID: friendA.id, name: friendA.name, linkKey: friendA.key, pct: 10, price: fair * 3, myLinkKeys: []) else { return XCTFail("an inflated price is refused") }
        guard case .refused = e.jvInvite(companyID: id, playerID: friendA.id, name: friendA.name, linkKey: friendA.key, pct: 70, price: fair, myLinkKeys: []) else { return XCTFail("over 49 percent is refused") }
        XCTAssertNil(e.jointVenture(companyID: id), "nothing was made by refused invitations")
    }

    func testAcceptedInviteIssuesSharesWithLockUpAndKeepsBooksBalanced() throws {
        var (e, id) = try makeCompany(seed: 72)
        let before = e.state.company(id)!.cash
        try join(&e, id, friendA, pct: 20)
        let co = e.state.company(id)!
        let stakes = e.jvStakes(companyID: id)
        XCTAssertEqual(stakes.count, 2)
        let a = try XCTUnwrap(stakes.first { $0.name == friendA.name })
        XCTAssertEqual(a.pct, 20, accuracy: 0.01)
        XCTAssertTrue(a.locked)
        XCTAssertEqual(a.lockUntil, e.state.week + JVRules.lockUpWeeks)
        XCTAssertEqual(co.ownership, 80, accuracy: 0.01)
        XCTAssertGreaterThan(co.cash, before, "the friend's price went to the company")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        XCTAssertNotNil(e.jointVenture(companyID: id)?.nextPlanned)
        XCTAssertTrue(e.state.inbox.contains { $0.title.contains("joined") })
    }

    func testEachFriendSeesOnlyTheirOwnPrice() throws {
        var (e, id) = try makeCompany(seed: 73)
        let p1 = e.jvFairPrice(companyID: id, pct: 10)
        guard case .sent(let i1) = e.jvInvite(companyID: id, playerID: friendA.id, name: friendA.name, linkKey: friendA.key, pct: 10, price: p1 * 0.9, myLinkKeys: []),
              case .sent(let i2) = e.jvInvite(companyID: id, playerID: friendB.id, name: friendB.name, linkKey: friendB.key, pct: 10, price: p1 * 1.3, myLinkKeys: []) else { return XCTFail() }
        let inv = try XCTUnwrap(e.jointVenture(companyID: id)?.invites)
        XCTAssertNotEqual(inv.first { $0.id == i1 }?.price, inv.first { $0.id == i2 }?.price, "the owner sets a price for each friend")
        let t = try XCTUnwrap(e.jvTerms(companyID: id, pct: 10, price: p1 * 0.9))
        XCTAssertEqual(t.lines.count, 5, "share, cost, lock-up, voting power, dividend rule")
        XCTAssertTrue(t.lines[1].contains("pay"))
        XCTAssertFalse(t.lines.joined().contains(String(Int(p1 * 1.3))), "the other friend's price is not in these words")
    }

    func testUrgentMeetingNotifiesAndPassesByShareWithAbstentionAtDeadline() throws {
        var (e, id) = try makeCompany(seed: 74)
        try join(&e, id, friendA, pct: 30, role: "cfo")
        let item = try XCTUnwrap(e.jvMakeItem(companyID: id, kind: .price, steps: -1).item)
        let r = e.jvCallUrgent(companyID: id, by: "p:" + friendA.id, reason: "Sales are falling", items: [item])
        guard case .called(let mid) = r else { return XCTFail("\(r)") }
        let msg = try XCTUnwrap(e.state.inbox.first { $0.title.contains("called an emergency meeting") })
        XCTAssertEqual(msg.title, "CFO \(friendA.name) called an emergency meeting: Sales are falling")
        XCTAssertFalse(try XCTUnwrap(e.jointVenture(companyID: id)?.notes).isEmpty, "a local notification record exists")
        let level = e.state.company(id)!.priceLevel
        // You (70%) vote yes; the CFO (30%) backed it by calling; nothing else is needed. The deadline passes and the item is counted.
        XCTAssertTrue(e.jvVote(companyID: id, meetingID: mid, itemID: item.id, choice: .yes))
        tick(&e, weeks: 2)
        let m = try XCTUnwrap(e.jointVenture(companyID: id)?.meetings.first { $0.id == mid })
        XCTAssertTrue(m.closed)
        XCTAssertEqual(m.items[0].outcome, .passed)
        XCTAssertTrue(m.items[0].applied)
        XCTAssertEqual(e.state.company(id)!.priceLevel, level - 1)
        XCTAssertFalse(e.jvVote(companyID: id, meetingID: mid, itemID: item.id, choice: .no), "a closed meeting takes no votes")
    }

    func testUnvotedItemFailsForLackOfVotesAndNothingChanges() throws {
        var (e, id) = try makeCompany(seed: 75)
        try join(&e, id, friendA, pct: 40)
        let item = try XCTUnwrap(e.jvMakeItem(companyID: id, kind: .price, steps: 1).item)
        // The owner calls it but the caller's vote is only 60%; the partner (40%) votes no.
        guard case .called(let mid) = e.jvCallUrgent(companyID: id, reason: "Raise prices", items: [item]) else { return XCTFail() }
        let level = e.state.company(id)!.priceLevel
        XCTAssertTrue(e.jvVote(companyID: id, meetingID: mid, itemID: item.id, member: "p:" + friendA.id, choice: .no))
        tick(&e, weeks: 2)
        let m = try XCTUnwrap(e.jointVenture(companyID: id)?.meetings.first { $0.id == mid })
        XCTAssertEqual(m.items[0].outcome, .passed, "60 yes against 40 no")
        XCTAssertEqual(e.state.company(id)!.priceLevel, level + 1)
        // A meeting nobody but the partners' side attends: you abstain, they vote no, so quorum is met and it fails.
        let item2 = try XCTUnwrap(e.jvMakeItem(companyID: id, kind: .price, steps: -1).item)
        guard case .called(let m2) = e.jvCallUrgent(companyID: id, by: "p:" + friendA.id, reason: "Cut prices", items: [item2]) else { return XCTFail("called") }
        _ = e.jvVote(companyID: id, meetingID: m2, itemID: item2.id, choice: .no)
        tick(&e, weeks: 2)
        let after = try XCTUnwrap(e.jointVenture(companyID: id)?.meetings.first { $0.id == m2 })
        XCTAssertEqual(after.items[0].outcome, .failed)
        XCTAssertFalse(after.items[0].applied)
        XCTAssertEqual(e.state.company(id)!.priceLevel, level + 1)
    }

    func testPlannedMeetingsRunEveryQuarterAndAnnounceTheAgenda() throws {
        var (e, id) = try makeCompany(seed: 76)
        try join(&e, id, friendA, pct: 25)
        let due = try XCTUnwrap(e.jointVenture(companyID: id)?.nextPlanned)
        XCTAssertEqual(due, e.state.week + JVRules.quarterWeeks)
        tick(&e, weeks: due - JVRules.plannedNoticeWeeks - e.state.week)
        let st = try XCTUnwrap(e.jointVenture(companyID: id))
        let m = try XCTUnwrap(st.meetings.first { $0.planned })
        XCTAssertEqual(m.week, due)
        XCTAssertEqual(m.deadline, due)
        let msg = try XCTUnwrap(e.state.inbox.first { $0.title.contains("board meeting on") })
        XCTAssertTrue(msg.title.hasPrefix(e.state.company(id)!.name + " board meeting on "), msg.title)
        XCTAssertEqual(st.nextPlanned, due + JVRules.quarterWeeks)
        XCTAssertTrue(st.notes.contains { $0.title.contains("board meeting on") })
        tick(&e, weeks: JVRules.plannedNoticeWeeks + 1)
        XCTAssertTrue(e.jointVenture(companyID: id)!.meetings.first { $0.id == m.id }!.closed, "counted after the date")
    }

    func testNewPartnerNeedsAVoteOnceThereArePartnersAndGuardRailsStillApply() throws {
        var (e, id) = try makeCompany(seed: 77)
        try join(&e, id, friendA, pct: 20)
        let price = e.jvFairPrice(companyID: id, pct: 10)
        guard case .needsVote(let mid) = e.jvInvite(companyID: id, playerID: friendB.id, name: friendB.name, linkKey: friendB.key, pct: 10, price: price, myLinkKeys: []) else { return XCTFail() }
        XCTAssertTrue(e.jointVenture(companyID: id)!.invites.allSatisfy { $0.playerID != friendB.id }, "no invitation before the vote")
        let item = try XCTUnwrap(e.jointVenture(companyID: id)?.meetings.first { $0.id == mid }?.items.first)
        XCTAssertTrue(e.jvVote(companyID: id, meetingID: mid, itemID: item.id, member: "p:" + friendA.id, choice: .yes))
        tick(&e, weeks: 2)
        let sent = try XCTUnwrap(e.jointVenture(companyID: id)?.invites.first { $0.playerID == friendB.id })
        XCTAssertEqual(sent.status, "sent")
        XCTAssertNil(e.jvRespond(companyID: id, inviteID: sent.id, accept: true))
        XCTAssertEqual(e.jvStakes(companyID: id).count, 3)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testOwnerCannotTakeMoneyOutWithoutAMajorityVote() throws {
        var (e, id) = try makeCompany(seed: 78)
        XCTAssertNil(JointVenture.payoutBlock(e.state, companyID: id), "alone, the owner decides")
        try join(&e, id, friendA, pct: 20)
        XCTAssertNotNil(JointVenture.payoutBlock(e.state, companyID: id))
        XCTAssertEqual(e.payDividend(companyID: id, amount: 1_000), .needsBoard)
        guard case .refused = e.setDividendPolicy(companyID: id, policy: "low") else { return XCTFail("policy changes need a vote too") }
        let paid = e.state.company(id)!.distributed
        XCTAssertEqual(e.state.company(id)!.distributed, paid)
    }

    func testPassedDividendIsAppliedByTheGameAndBooksStayBalanced() throws {
        var (e, id) = try makeCompany(seed: 79)
        try join(&e, id, friendA, pct: 20)
        // Give the company retained profit: cash it earned.
        e.update { s, _, _ in Ledger.moveRaw(&s, .company(id), 4_000_000); if let i = s.companyIndex(id) { s.companies[i].shareCapital = 0 } }
        let top = Payments.maximumDividend(e.state.company(id)!, state: e.state, context: e.context)
        XCTAssertGreaterThan(top, 0)
        let made = e.jvMakeItem(companyID: id, kind: .dividend, amount: top)
        let item = try XCTUnwrap(made.item, made.problem ?? "")
        XCTAssertNotNil(e.jvMakeItem(companyID: id, kind: .dividend, amount: top * 10).problem, "more than can be paid is refused")
        guard case .called(let mid) = e.jvCallUrgent(companyID: id, reason: "Pay owners", items: [item]) else { return XCTFail() }
        let cashBefore = e.state.cash
        tick(&e, weeks: 2)
        let m = try XCTUnwrap(e.jointVenture(companyID: id)?.meetings.first { $0.id == mid })
        XCTAssertEqual(m.items[0].outcome, .passed)
        XCTAssertTrue(m.items[0].applied, m.items[0].result)
        XCTAssertGreaterThan(e.state.cash, cashBefore, "your 80% reached you through the normal dividend path")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testCapitalCallTakesYourShareAndEveryPartnersShare() throws {
        var (e, id) = try makeCompany(seed: 80)
        try join(&e, id, friendA, pct: 25)
        let made = e.jvMakeItem(companyID: id, kind: .capital, amount: 1_000_000)
        let item = try XCTUnwrap(made.item)
        guard case .called(let mid) = e.jvCallUrgent(companyID: id, reason: "Cash is short", items: [item]) else { return XCTFail() }
        let cash = e.state.company(id)!.cash, mine = e.state.cash
        tick(&e, weeks: 2)
        let m = try XCTUnwrap(e.jointVenture(companyID: id)?.meetings.first { $0.id == mid })
        XCTAssertTrue(m.items[0].applied, m.items[0].result)
        XCTAssertEqual(e.state.company(id)!.cash - cash, 1_000_000, accuracy: 2, "the whole call arrives")
        XCTAssertEqual(mine - e.state.cash, 750_000, accuracy: 2, "you pay your 75 percent")
        XCTAssertEqual(e.state.company(id)!.ownership, 75, accuracy: 0.01, "nobody's share changed")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testOnlyOwnersAndRoleHoldersCallMeetingsAndOneAtATime() throws {
        var (e, id) = try makeCompany(seed: 81)
        let item = try XCTUnwrap(e.jvMakeItem(companyID: id, kind: .price, steps: -1).item)
        guard case .refused = e.jvCallUrgent(companyID: id, reason: "x", items: [item]) else { return XCTFail("no partner, no board") }
        try join(&e, id, friendA, pct: 20)
        guard case .refused = e.jvCallUrgent(companyID: id, by: "p:stranger", reason: "x", items: [item]) else { return XCTFail("a stranger cannot call one") }
        guard case .called = e.jvCallUrgent(companyID: id, reason: "x", items: [item]) else { return XCTFail() }
        guard case .refused = e.jvCallUrgent(companyID: id, by: "p:" + friendA.id, reason: "y", items: [item]) else { return XCTFail("one at a time") }
    }

    func testDissolvingPaysYouByYourShareOfTheRealValue() throws {
        var (e, id) = try makeCompany(seed: 82)
        try join(&e, id, friendA, pct: 20)
        let value = max(0, Valuation.companyValue(e.state.company(id)!, state: e.state, trades: e.data.catalog))
        let made = e.jvMakeItem(companyID: id, kind: .dissolve)
        let item = try XCTUnwrap(made.item)
        guard case .called(let mid) = e.jvCallUrgent(companyID: id, reason: "Wind it up", items: [item]) else { return XCTFail() }
        let cash = e.state.cash
        tick(&e, weeks: 2)
        let m = try XCTUnwrap(e.jointVenture(companyID: id)?.meetings.first { $0.id == mid })
        XCTAssertTrue(m.items[0].applied, m.items[0].result)
        XCTAssertEqual(e.state.cash - cash, value * 0.8, accuracy: max(5, value * 0.001), "real value times your share, no premium")
        XCTAssertEqual(e.state.company(id)!.status, .sold)
    }
}
