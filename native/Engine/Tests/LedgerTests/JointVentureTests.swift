import XCTest
import GameCore
import Finance
import Businesses
import Events
import Simulation

final class JointVentureTests: XCTestCase {

    func testAProposalNeedsMoreThanHalfOfAllSharesInFavour() {
        let shares = ["me": 60, "p:a": 25, "p:b": 15]
        var t = JVRules.tally(shares: shares, votes: ["me": .yes])
        XCTAssertEqual(t.yes, 60); XCTAssertEqual(t.abstain, 40)
        XCTAssertEqual(JVRules.decide(t), .passed, "60% of all shares said yes")
        t = JVRules.tally(shares: ["me": 30, "p:a": 40, "p:b": 30], votes: ["me": .yes, "p:a": .no, "p:b": .yes])
        XCTAssertEqual(JVRules.decide(t), .passed, "60 yes against 40 no")
        t = JVRules.tally(shares: ["me": 30, "p:a": 40, "p:b": 30], votes: ["me": .yes, "p:a": .no, "p:b": .no])
        XCTAssertEqual(JVRules.decide(t), .failed)
        t = JVRules.tally(shares: ["me": 50, "p:a": 50], votes: ["me": .yes])
        XCTAssertEqual(JVRules.decide(t), .failed, "exactly half is not more than half")
        XCTAssertEqual(JVRules.decide(JVRules.tally(shares: [:], votes: [:])), .failed)
    }

    func testOwnersWhoDoNotVoteCountAsAbstaining() {
        let shares = ["me": 40, "p:a": 35, "p:b": 25]
        let silent = JVRules.tally(shares: shares, votes: ["me": .yes])
        XCTAssertEqual(silent.abstain, 60)
        XCTAssertEqual(JVRules.decide(silent), .failed, "40% yes and nobody against still fails")
        XCTAssertEqual(JVRules.decide(JVRules.tally(shares: shares, votes: ["me": .yes, "p:a": .abstain, "p:b": .abstain])), .failed)
        XCTAssertEqual(JVRules.decide(JVRules.tally(shares: shares, votes: ["me": .yes, "p:b": .yes])), .passed, "65% of all shares")
    }

    func testTheWeeklyMeetingIsMondayWithADayOfNotice() {
        let day: Double = 86400
        for n in 0..<28 {
            let now: Double = 1_800_000_000 + Double(n) * 21_600
            let at = JVRules.nextMeeting(after: now)
            XCTAssertEqual((at - 4 * day).truncatingRemainder(dividingBy: 7 * day), 0, accuracy: 0.001, "Monday 00:00 UTC")
            XCTAssertGreaterThanOrEqual(at - now, day - 1, "at least a day of notice")
            XCTAssertLessThanOrEqual(at - now, 8 * day)
        }
        let sundayNoon: Double = 4 * day + 6 * day + 43_200
        XCTAssertEqual(JVRules.nextMeeting(after: sundayNoon), 4 * day + 14 * day, accuracy: 0.001, "too late for tomorrow, so the Monday after")
        XCTAssertEqual(JVRules.emergencySeconds, 24 * 3600)
    }

    func testGuardRails() {
        let fair = JVRules.fairPrice(value: 900, pct: 10)
        XCTAssertEqual(fair, 100, accuracy: 1e-9)
        XCTAssertNil(JVRules.priceProblem(price: 100, fair: fair))
        XCTAssertNotNil(JVRules.priceProblem(price: 10, fair: fair), "a gift is not allowed")
        XCTAssertNotNil(JVRules.priceProblem(price: 1_000, fair: fair), "neither is an inflated price")
        XCTAssertNil(JVRules.buyBackProblem(price: 100, fair: 100))
        XCTAssertNotNil(JVRules.buyBackProblem(price: 10, fair: 100), "a buyback cannot strip a partner")
        XCTAssertNotNil(JVRules.buyBackProblem(price: 1_000, fair: 100), "or hand them a gift")
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

    func testSamplePartnersVoteLikePeople() {
        XCTAssertEqual(JVRules.mockChoice(.dividend, profitable: true, cashTight: false, seed: "a:1"), JVRules.mockChoice(.dividend, profitable: true, cashTight: false, seed: "a:1"))
        let opened: Double = 1_800_000_000
        let closes: Double = opened + JVRules.emergencySeconds
        var silent = 0, forIt = 0, againstIt = 0
        for n in 0..<300 {
            let seed = "7:9:\(n):p:pl-\(n)"
            if let at = JVRules.mockVoteTime(opened: opened, closes: closes, memberID: "p:pl-\(n)", countryCode: "NO", seed: seed) {
                XCTAssertGreaterThanOrEqual(at - opened, 10 * 60 - 1, "nobody answers within the same minute")
                XCTAssertLessThan(at, closes)
            } else {
                silent += 1
            }
            switch JVRules.mockChoice(.policy, profitable: true, cashTight: false, seed: seed, raises: true) {
            case .yes: forIt += 1
            case .no: againstIt += 1
            case .abstain: break
            }
        }
        XCTAssertGreaterThan(silent, 0, "now and then a partner does not vote")
        XCTAssertLessThan(silent, 120)
        XCTAssertGreaterThan(forIt, againstIt, "a profitable company with cash can pay more")
        XCTAssertGreaterThan(againstIt, 0, "but not everyone agrees")
        var lowYes = 0, highYes = 0
        for n in 0..<300 {
            if JVRules.mockSells(price: 75, fair: 100, seed: "s\(n)") { lowYes += 1 }
            if JVRules.mockSells(price: 130, fair: 100, seed: "s\(n)") { highYes += 1 }
        }
        XCTAssertGreaterThan(highYes, lowYes, "a better price is accepted more often")
        XCTAssertLessThan(highYes, 300, "even a good offer can be declined")
    }

    private let friendA = (id: "pl-a", name: "Ingrid Solheim", key: "pl-a")
    private let friendB = (id: "pl-b", name: "Oliver Whitfield", key: "pl-b")
    private let friendC = (id: "pl-c", name: "Camille Laurent", key: "pl-c")
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func hours(_ h: Double) -> Date { t0.addingTimeInterval(h * 3600) }

    private func makeCompany(seed: Int) throws -> (engine: GameEngine, id: Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 300_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID) else { throw XCTSkip("could not start a company") }
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
        return (e, id)
    }

    @discardableResult
    private func join(_ e: inout GameEngine, _ id: Int, _ f: (id: String, name: String, key: String), pct: Double, role: String = "partner") throws -> Int {
        let price = e.jvFairPrice(companyID: id, pct: pct)
        switch e.jvInvite(companyID: id, playerID: f.id, name: f.name, linkKey: f.key, role: role, pct: pct, price: price, myLinkKeys: ["me-1"], now: t0) {
        case .sent(let inv):
            XCTAssertNil(e.jvRespond(companyID: id, inviteID: inv, accept: true))
            return inv
        default: XCTFail("invite not sent"); throw XCTSkip("no invite")
        }
    }

    private func member(_ f: (id: String, name: String, key: String)) -> String { "p:" + f.id }

    private func myShare(_ e: GameEngine, _ id: Int) -> Double { e.jvStakes(companyID: id).first { $0.isYou }?.pct ?? 0 }

    private func threeOwners(seed: Int) throws -> (engine: GameEngine, id: Int) {
        var (e, id) = try makeCompany(seed: seed)
        try join(&e, id, friendA, pct: 49)
        let price = e.jvFairPrice(companyID: id, pct: 10)
        guard case .needsVote = e.jvInvite(companyID: id, playerID: friendB.id, name: friendB.name, linkKey: friendB.key, pct: 10, price: price, myLinkKeys: ["me-1"], now: t0) else {
            XCTFail("a second partner goes to a vote"); throw XCTSkip("no vote")
        }
        let inv = try XCTUnwrap(e.jointVenture(companyID: id)?.invites.first { $0.playerID == friendB.id && $0.status == "sent" }, "with 51% the owner carries the vote at once")
        XCTAssertNil(e.jvRespond(companyID: id, inviteID: inv.id, accept: true))
        XCTAssertEqual(e.jvStakes(companyID: id).count, 3)
        XCTAssertLessThan(myShare(e, id), 50, "nobody holds a majority")
        XCTAssertGreaterThan(myShare(e, id), 40)
        return (e, id)
    }

    private func tick(_ e: inout GameEngine, weeks: Int = 1) {
        for _ in 0..<weeks { e.update { s, d, c in s.week += 1; JointVenture.weekly(&s, data: d, context: c) } }
    }

    private func meeting(_ e: GameEngine, _ id: Int, _ mid: Int) throws -> JointVenture.Meeting {
        try XCTUnwrap(e.jointVenture(companyID: id)?.meetings.first { $0.id == mid })
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

    func testASamplePartnerNeverPaysMoreThanTheSharesAreWorth() throws {
        var (e, id) = try makeCompany(seed: 75)
        let fair = e.jvFairPrice(companyID: id, pct: 10)
        guard case .refused = e.jvInvite(companyID: id, playerID: friendA.id, name: friendA.name, linkKey: friendA.key, pct: 10, price: fair * 1.3, myLinkKeys: []) else { return XCTFail("an imaginary partner cannot overpay") }
        guard case .sent = e.jvInvite(companyID: id, playerID: friendA.id, name: friendA.name, linkKey: friendA.key, pct: 10, price: fair, myLinkKeys: []) else { return XCTFail("a sample partner pays the fair price") }
        guard case .refused(let mixed) = e.jvInvite(companyID: id, playerID: friendB.id, name: friendB.name, linkKey: friendB.key, mock: false, pct: 10, price: fair, myLinkKeys: []) else {
            return XCTFail("a real player cannot join a board of sample partners")
        }
        XCTAssertTrue(mixed.contains("practice"), mixed)
        var (real, rid) = try makeCompany(seed: 76)
        let realFair = real.jvFairPrice(companyID: rid, pct: 10)
        guard case .sent = real.jvInvite(companyID: rid, playerID: friendB.id, name: friendB.name, linkKey: friendB.key, mock: false, pct: 10, price: realFair * 1.3, myLinkKeys: []) else { return XCTFail("a real partner may pay up to the band") }
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
        XCTAssertTrue(e.state.inbox.contains { $0.title.contains("joined") })
    }

    func testTheInviterChoosesShareAndPriceAndTheInviteeDecides() throws {
        var (e, id) = try makeCompany(seed: 73)
        let fair = e.jvFairPrice(companyID: id, pct: 15)
        let asked = (fair * 0.9).rounded()
        guard case .sent(let i1) = e.jvInvite(companyID: id, playerID: friendA.id, name: friendA.name, linkKey: friendA.key, pct: 15, price: asked, myLinkKeys: []) else { return XCTFail() }
        let inv = try XCTUnwrap(e.jointVenture(companyID: id)?.invites.first { $0.id == i1 })
        XCTAssertEqual(inv.pct, 15); XCTAssertEqual(inv.price, asked)
        let t = try XCTUnwrap(e.jvTerms(companyID: id, pct: inv.pct, price: inv.price))
        XCTAssertEqual(t.lines.count, 5, "share, cost, lock-up, voting power, dividend rule")
        XCTAssertTrue(t.lines[0].contains("15.0%"), "the invitee reads the share: \(t.lines[0])")
        XCTAssertTrue(t.lines[1].contains("pay"), "and the price: \(t.lines[1])")
        XCTAssertEqual(t.price, asked)
        let cash = e.state.company(id)!.cash
        XCTAssertNil(e.jvRespond(companyID: id, inviteID: i1, accept: false))
        XCTAssertEqual(e.jvStakes(companyID: id).filter { !$0.isYou }.count, 0, "declined: nobody joined")
        XCTAssertEqual(e.state.company(id)!.cash, cash, "and nothing was paid")
        XCTAssertEqual(e.state.company(id)!.ownership, 100, accuracy: 0.01)
        guard case .sent(let i2) = e.jvInvite(companyID: id, playerID: friendA.id, name: friendA.name, linkKey: friendA.key, pct: 15, price: asked, myLinkKeys: []) else { return XCTFail("a new offer can follow a no") }
        XCTAssertNil(e.jvRespond(companyID: id, inviteID: i2, accept: true))
        XCTAssertEqual(e.state.company(id)!.cash - cash, asked, accuracy: 1, "accepted: exactly the price the inviter set")
        XCTAssertEqual(e.state.company(id)!.ownership, 85, accuracy: 0.01)
    }

    func testEmergencyMeetingPassesAsSoonAsOverHalfOfAllSharesSayYes() throws {
        var (e, id) = try threeOwners(seed: 74)
        let item = try XCTUnwrap(e.jvMakeItem(companyID: id, kind: .price, steps: -1).item)
        guard case .called(let mid) = e.jvCallUrgent(companyID: id, reason: "Sales are falling", items: [item], now: t0) else { return XCTFail("not called") }
        var m = try meeting(e, id, mid)
        XCTAssertFalse(m.closed, "under half of all shares: the vote is open")
        XCTAssertEqual(try XCTUnwrap(m.closesAt), t0.timeIntervalSince1970 + 24 * 3600, accuracy: 0.001, "the others have 24 hours")
        XCTAssertEqual(m.items[0].votes[JointVenture.Member.me], .yes, "the caller is counted for their own proposal")
        let level = e.state.company(id)!.priceLevel
        e.jvSettle(now: hours(2))
        XCTAssertFalse(try meeting(e, id, mid).closed)
        XCTAssertEqual(e.state.company(id)!.priceLevel, level, "nothing changes while the vote is open")
        XCTAssertTrue(e.jvVote(companyID: id, meetingID: mid, itemID: item.id, member: member(friendA), choice: .yes, now: hours(3)))
        m = try meeting(e, id, mid)
        XCTAssertTrue(m.closed, "over half of all shares said yes")
        XCTAssertEqual(m.items[0].outcome, .passed)
        XCTAssertTrue(m.items[0].applied)
        XCTAssertEqual(e.state.company(id)!.priceLevel, level - 1)
        XCTAssertFalse(e.jvVote(companyID: id, meetingID: mid, itemID: item.id, member: member(friendB), choice: .no, now: hours(4)), "a closed meeting takes no votes")
    }

    func testEmergencyMeetingFailsAtTheDeadlineWhenOwnersStaySilent() throws {
        var (e, id) = try threeOwners(seed: 75)
        let item = try XCTUnwrap(e.jvMakeItem(companyID: id, kind: .price, steps: 1).item)
        guard case .called(let mid) = e.jvCallUrgent(companyID: id, reason: "Raise prices", items: [item], now: t0) else { return XCTFail("not called") }
        let level = e.state.company(id)!.priceLevel
        XCTAssertTrue(e.jvVote(companyID: id, meetingID: mid, itemID: item.id, member: member(friendB), choice: .no, now: hours(1)))
        e.jvSettle(now: hours(23.9))
        XCTAssertFalse(try meeting(e, id, mid).closed, "open for the full 24 hours")
        XCTAssertFalse(e.jvVote(companyID: id, meetingID: mid, itemID: item.id, member: member(friendA), choice: .yes, now: hours(24.1)), "too late")
        e.jvSettle(now: hours(24.1))
        let m = try meeting(e, id, mid)
        XCTAssertTrue(m.closed)
        XCTAssertEqual(m.items[0].outcome, .failed, "a silent owner abstains, so it never had half of all shares")
        XCTAssertFalse(m.items[0].applied)
        XCTAssertEqual(e.state.company(id)!.priceLevel, level)
        XCTAssertTrue(try XCTUnwrap(e.jointVenture(companyID: id)).notes.contains { $0.title.contains("meeting result") })
    }

    func testAPartnersEmergencyMeetingReachesThePlayerWithTheTimeLeft() throws {
        var (e, id) = try makeCompany(seed: 93)
        try join(&e, id, friendA, pct: 30, role: "cfo")
        XCTAssertNil(JointVenture.pendingVote(e.state, now: t0.timeIntervalSince1970))
        let item = try XCTUnwrap(e.jvMakeItem(companyID: id, kind: .price, steps: -1).item)
        guard case .called(let mid) = e.jvCallUrgent(companyID: id, by: member(friendA), reason: "Sales are falling", items: [item], now: t0) else { return XCTFail() }
        let msg = try XCTUnwrap(e.state.inbox.first { $0.title.contains("called an emergency meeting") })
        XCTAssertEqual(msg.title, "CFO \(friendA.name) called an emergency meeting: Sales are falling")
        XCTAssertFalse(try XCTUnwrap(e.jointVenture(companyID: id)?.notes).isEmpty, "a local notification record exists")
        let pending = try XCTUnwrap(JointVenture.pendingVote(e.state, now: hours(1).timeIntervalSince1970))
        XCTAssertTrue(pending.urgent)
        XCTAssertEqual(pending.hoursLeft, 23)
        let reminder = try XCTUnwrap(SessionHooks.reminders(e.state, now: hours(1)).first { $0.id == "ledger.jv.urgent" })
        XCTAssertTrue(reminder.body.contains("Sales are falling") && reminder.body.contains("23 hours left"), reminder.body)
        XCTAssertNil(JointVenture.pendingVote(e.state, now: hours(25).timeIntervalSince1970), "nothing to vote on after the deadline")
        XCTAssertTrue(e.jvVote(companyID: id, meetingID: mid, itemID: item.id, choice: .yes, now: hours(2)))
        XCTAssertNil(JointVenture.pendingVote(e.state, now: hours(2).timeIntervalSince1970), "nothing waits once you have voted")
        XCTAssertTrue(try meeting(e, id, mid).closed, "your 70% carried it")
        XCTAssertTrue(try XCTUnwrap(e.jointVenture(companyID: id)).notes.contains { $0.title.contains("meeting result") }, "the result is announced too")
    }

    func testASoleOwnerChangesTheDividendPolicyDirectly() throws {
        var (e, id) = try makeCompany(seed: 60)
        XCTAssertNil(e.jvBoardCompany(companyID: id))
        XCTAssertEqual(e.jvPropose(companyID: id, change: .policy("low"), urgent: false, now: t0), .applied)
        XCTAssertEqual(e.dividendPolicy(companyID: id), "low")
        XCTAssertEqual(e.jvPropose(companyID: id, change: .policy("mid"), urgent: true, now: t0), .applied)
        XCTAssertEqual(e.dividendPolicy(companyID: id), "mid")
        XCTAssertNil(e.jointVenture(companyID: id), "no board was made for a sole owner")
        XCTAssertEqual(e.setDividendPolicy(companyID: id, policy: "none"), .applied)
        guard case .refused = e.jvPropose(companyID: id, change: .policy("none"), urgent: false, now: t0) else { return XCTFail("the same policy is not a change") }
    }

    func testDividendPolicyGoesToTheWeeklyMeetingOnceThereAreCoOwners() throws {
        var (e, id) = try threeOwners(seed: 61)
        XCTAssertNotNil(JointVenture.payoutBlock(e.state, companyID: id))
        guard case .refused = e.setDividendPolicy(companyID: id, policy: "low") else { return XCTFail("nobody sets the policy alone") }
        guard case .added(let mid) = e.jvPropose(companyID: id, change: .policy("high"), urgent: false, now: t0) else { return XCTFail("not added to the agenda") }
        XCTAssertEqual(e.dividendPolicy(companyID: id), "none", "nothing changes before the vote")
        var m = try meeting(e, id, mid)
        XCTAssertTrue(m.planned)
        let slot = JVRules.nextMeeting(after: t0.timeIntervalSince1970)
        XCTAssertEqual(try XCTUnwrap(m.closesAt), slot, accuracy: 0.001, "voted at the next weekly meeting")
        guard case .added(let again) = e.jvPropose(companyID: id, change: .policy("low"), urgent: false, now: hours(5)) else { return XCTFail("second item") }
        XCTAssertEqual(again, mid, "one weekly meeting holds every item")
        m = try meeting(e, id, mid)
        XCTAssertEqual(m.items.count, 2)
        XCTAssertTrue(e.jvVote(companyID: id, meetingID: mid, itemID: m.items[0].id, member: member(friendA), choice: .yes, now: hours(6)))
        XCTAssertFalse(try meeting(e, id, mid).closed, "the weekly meeting is counted on its day, not before")
        e.jvSettle(now: Date(timeIntervalSince1970: slot - 60))
        XCTAssertFalse(try meeting(e, id, mid).closed)
        XCTAssertEqual(e.dividendPolicy(companyID: id), "none")
        e.jvSettle(now: Date(timeIntervalSince1970: slot + 1))
        m = try meeting(e, id, mid)
        XCTAssertTrue(m.closed)
        XCTAssertEqual(m.items[0].outcome, .passed, "two owners with over half of all shares")
        XCTAssertEqual(m.items[1].outcome, .failed, "only the proposer voted for it; the silent owners abstained")
        XCTAssertEqual(e.dividendPolicy(companyID: id), "high")
    }

    func testDecideNowOnTheDividendPolicyCallsAnEmergencyMeeting() throws {
        var (e, id) = try threeOwners(seed: 62)
        guard case .called(let mid) = e.jvPropose(companyID: id, change: .policy("mid"), urgent: true, now: t0) else { return XCTFail("no emergency meeting") }
        var m = try meeting(e, id, mid)
        XCTAssertTrue(m.urgent)
        XCTAssertEqual(try XCTUnwrap(m.closesAt) - t0.timeIntervalSince1970, 24 * 3600, accuracy: 0.001)
        XCTAssertEqual(e.dividendPolicy(companyID: id), "none")
        guard case .refused = e.jvPropose(companyID: id, change: .policy("high"), urgent: true, now: hours(1)) else { return XCTFail("one emergency meeting at a time") }
        XCTAssertTrue(e.jvVote(companyID: id, meetingID: mid, itemID: m.items[0].id, member: member(friendB), choice: .yes, now: hours(2)))
        m = try meeting(e, id, mid)
        XCTAssertTrue(m.closed, "45.9% and 10% are over half")
        XCTAssertEqual(e.dividendPolicy(companyID: id), "mid")
    }

    func testGroupRulesNeedTheBoardWhenAStoreHasCoOwners() throws {
        var (e, id) = try threeOwners(seed: 63)
        guard let chain = e.makeChain(companyID: id, name: "Test Cafe") else { throw XCTSkip("chain not made") }
        XCTAssertNotNil(e.jvBoardCompany(chainID: chain))
        let before = e.chainRules(chainID: chain)["price"].double
        guard case .refused = e.setChainRule(chainID: chain, rule: .price(before + 1)) else { return XCTFail("nobody changes a group rule alone") }
        let change = JointVenture.Change.setting(JointVenture.Setting(chainID: chain, rule: "price", number: before + 1, label: "Chain price rule: one step up"))
        guard case .called(let mid) = e.jvPropose(companyID: id, change: change, urgent: true, now: t0) else { return XCTFail("no emergency meeting") }
        XCTAssertEqual(e.chainRules(chainID: chain)["price"].double, before)
        let m = try meeting(e, id, mid)
        XCTAssertEqual(m.items[0].title, "Chain price rule: one step up")
        XCTAssertTrue(e.jvVote(companyID: id, meetingID: mid, itemID: m.items[0].id, member: member(friendA), choice: .yes, now: hours(1)))
        XCTAssertEqual(e.chainRules(chainID: chain)["price"].double, before + 1, "carried out once it passed")
    }

    func testASoleOwnersGroupRuleAppliesDirectly() throws {
        var (e, id) = try makeCompany(seed: 64)
        guard let chain = e.makeChain(companyID: id, name: "Test Cafe") else { throw XCTSkip("chain not made") }
        XCTAssertNil(e.jvBoardCompany(chainID: chain))
        XCTAssertEqual(e.setChainRule(chainID: chain, rule: .stockPolicy(2)), .applied)
        let change = JointVenture.Change.setting(JointVenture.Setting(chainID: chain, rule: "stock", number: 0, label: "Chain ordering rule: lean"))
        XCTAssertEqual(e.jvPropose(companyID: id, change: change, urgent: true, now: t0), .applied)
        XCTAssertEqual(e.chainRules(chainID: chain)["stockPol"].int, 0)
    }

    func testNewPartnerNeedsAVoteOnceThereArePartnersAndGuardRailsStillApply() throws {
        var (e, id) = try threeOwners(seed: 77)
        let price = e.jvFairPrice(companyID: id, pct: 5)
        guard case .needsVote(let mid) = e.jvInvite(companyID: id, playerID: friendC.id, name: friendC.name, linkKey: friendC.key, pct: 5, price: price, myLinkKeys: [], now: t0) else { return XCTFail() }
        XCTAssertTrue(e.jointVenture(companyID: id)!.invites.allSatisfy { $0.playerID != friendC.id }, "no invitation before the vote")
        let item = try XCTUnwrap(try meeting(e, id, mid).items.first)
        XCTAssertTrue(e.jvVote(companyID: id, meetingID: mid, itemID: item.id, member: member(friendA), choice: .yes, now: hours(1)))
        let sent = try XCTUnwrap(e.jointVenture(companyID: id)?.invites.first { $0.playerID == friendC.id })
        XCTAssertEqual(sent.status, "sent")
        XCTAssertNil(e.jvRespond(companyID: id, inviteID: sent.id, accept: true))
        XCTAssertEqual(e.jvStakes(companyID: id).count, 4)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testOwnerCannotTakeMoneyOutWithoutAMajorityVote() throws {
        var (e, id) = try makeCompany(seed: 78)
        XCTAssertNil(JointVenture.payoutBlock(e.state, companyID: id), "alone, the owner decides")
        try join(&e, id, friendA, pct: 20)
        XCTAssertNotNil(JointVenture.payoutBlock(e.state, companyID: id))
        guard case .refused = e.setDividendPolicy(companyID: id, policy: "low") else { return XCTFail("policy changes need a vote too") }
    }

    func testPassedDividendIsAppliedByTheGameAndBooksStayBalanced() throws {
        var (e, id) = try makeCompany(seed: 79)
        try join(&e, id, friendA, pct: 20)
        e.update { s, _, _ in Ledger.moveRaw(&s, .company(id), 4_000_000); if let i = s.companyIndex(id) { s.companies[i].shareCapital = 0 } }
        let top = e.maximumDividend(companyID: id)
        XCTAssertGreaterThan(top, 0)
        let made = e.jvMakeItem(companyID: id, kind: .dividend, amount: top)
        let item = try XCTUnwrap(made.item, made.problem ?? "")
        XCTAssertNotNil(e.jvMakeItem(companyID: id, kind: .dividend, amount: top * 10).problem, "more than can be paid is refused")
        let cashBefore = e.state.cash
        guard case .called(let mid) = e.jvCallUrgent(companyID: id, reason: "Pay owners", items: [item], now: t0) else { return XCTFail() }
        let m = try meeting(e, id, mid)
        XCTAssertEqual(m.items[0].outcome, .passed, "the owner's 80% is over half of all shares")
        XCTAssertTrue(m.items[0].applied, m.items[0].result)
        XCTAssertLessThan(e.state.cash, cashBefore, "the partner's 20% leaves the account")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testOnlyOwnersAndRoleHoldersCallMeetingsAndOneAtATime() throws {
        var (e, id) = try makeCompany(seed: 81)
        let item = try XCTUnwrap(e.jvMakeItem(companyID: id, kind: .price, steps: -1).item)
        guard case .refused = e.jvCallUrgent(companyID: id, reason: "x", items: [item], now: t0) else { return XCTFail("no partner, no board") }
        try join(&e, id, friendA, pct: 20)
        guard case .refused = e.jvCallUrgent(companyID: id, by: "p:stranger", reason: "x", items: [item], now: t0) else { return XCTFail("a stranger cannot call one") }
        guard case .called = e.jvCallUrgent(companyID: id, by: member(friendA), reason: "x", items: [item], now: t0) else { return XCTFail() }
        guard case .refused = e.jvCallUrgent(companyID: id, reason: "y", items: [item], now: hours(1)) else { return XCTFail("one at a time") }
    }

    func testDissolvingPaysYouByYourShareOfTheRealValue() throws {
        var (e, id) = try makeCompany(seed: 82)
        try join(&e, id, friendA, pct: 20)
        let value = max(0, Valuation.companyValue(e.state.company(id)!, state: e.state, trades: e.data.catalog))
        let made = e.jvMakeItem(companyID: id, kind: .dissolve)
        let item = try XCTUnwrap(made.item)
        let cash = e.state.cash
        guard case .called(let mid) = e.jvCallUrgent(companyID: id, reason: "Wind it up", items: [item], now: t0) else { return XCTFail() }
        let m = try meeting(e, id, mid)
        XCTAssertTrue(m.items[0].applied, m.items[0].result)
        XCTAssertEqual(e.state.cash - cash, value * 0.8, accuracy: max(5, value * 0.001), "real value times your share, no premium")
        XCTAssertEqual(e.state.company(id)!.status, .sold)
    }

    private func putOffer(_ e: inout GameEngine, _ id: Int, price: Double) {
        e.update { s, _, _ in
            var list = s.rest["sales"]?.array ?? []
            guard let k = list.firstIndex(where: { $0["co"].int == id }) else { return }
            list[k]["offers"] = .array([.object(["id": 901, "k": "private", "name": "Acme Buyers", "price": .number(price), "note": "", "exp": .number(Double(s.week + 6)), "ctr": 0])])
            s.rest["sales"] = .array(list)
        }
    }

    func testOwnerCannotSellACompanyWithPartnersWithoutTheBoard() throws {
        var (e, id) = try makeCompany(seed: 90)
        XCTAssertNil(SaleListings.routeProblem(e.state, companyID: id, route: "broker", pct: 100), "alone, the owner sells as before")
        try join(&e, id, friendA, pct: 20)
        XCTAssertNotNil(SaleListings.routeProblem(e.state, companyID: id, route: "broker", pct: 100))
        guard case .refused = e.startSale(companyID: id, percent: 100, method: .offers) else { return XCTFail("the board decides") }
        guard case .refused = e.startSale(companyID: id, percent: 100, method: .auction, reserve: 1_000) else { return XCTFail("the board decides") }
        XCTAssertEqual(e.state.company(id)!.status, .open)
    }

    func testPassedSellItemListsTheCompanyAndOnlyAFairOfferClosesIt() throws {
        var (e, id) = try makeCompany(seed: 91)
        try join(&e, id, friendA, pct: 20)
        let item = try XCTUnwrap(e.jvMakeItem(companyID: id, kind: .sell).item)
        guard case .called(let mid) = e.jvCallUrgent(companyID: id, reason: "Time to sell", items: [item], now: t0) else { return XCTFail() }
        let m = try meeting(e, id, mid)
        XCTAssertTrue(m.items[0].applied, m.items[0].result)
        XCTAssertTrue(SaleListings.isBoardListing(e.state, companyID: id))
        let value = CompanySale.estimatedValue(e.state, companyID: id, data: e.data)
        putOffer(&e, id, price: value * 0.5)
        var low: Double?
        e.update { s, d, c in low = CompanySale.accept(&s, companyID: id, offerID: 901, data: d, context: c) }
        XCTAssertNil(low, "a lowball offer is not taken for the other owners")
        XCTAssertEqual(e.state.company(id)!.status, .open)
        putOffer(&e, id, price: value * 0.95)
        let cash = e.state.cash
        var got: Double?
        e.update { s, d, c in got = CompanySale.accept(&s, companyID: id, offerID: 901, data: d, context: c) }
        XCTAssertNotNil(got)
        XCTAssertEqual(e.state.company(id)!.status, .sold)
        XCTAssertGreaterThan(e.state.cash, cash)
        XCTAssertTrue(e.state.inbox.contains { $0.title.contains("was sold to Acme Buyers") }, "every owner's payout is recorded")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testBuyingAPartnerOutIsAnOfferTheyMustAccept() throws {
        var (e, id) = try makeCompany(seed: 92)
        try join(&e, id, friendA, pct: 20)
        let who = member(friendA)
        let early = try XCTUnwrap(e.jvExitTerms(companyID: id, memberID: who))
        XCTAssertTrue(early.locked)
        XCTAssertTrue(early.problem?.contains("cannot sell or leave until") == true, early.problem ?? "")
        XCTAssertNotNil(e.jvOfferBuyBack(companyID: id, memberID: who, price: early.price, now: t0), "no offer inside the lock-up")
        XCTAssertNil(e.buyBackPrice(companyID: id, holder: friendA.name), "a partner's stake has no take-it price")
        XCTAssertFalse(e.buyBackStake(companyID: id, holder: friendA.name), "and cannot be bought without their yes")
        let inbox = e.state.inbox.count
        XCTAssertNotNil(e.jvPartnerWantsOut(companyID: id, memberID: who))
        XCTAssertEqual(e.state.inbox.count, inbox, "inside the lock-up nothing is sent")
        tick(&e, weeks: JVRules.lockUpWeeks + 1)
        XCTAssertNil(e.jvPartnerWantsOut(companyID: id, memberID: who))
        XCTAssertTrue(e.state.inbox.contains { $0.title.contains("wants to sell") })
        let terms = try XCTUnwrap(e.jvExitTerms(companyID: id, memberID: who))
        XCTAssertNil(terms.problem, terms.problem ?? "")
        XCTAssertNotNil(e.jvOfferBuyBack(companyID: id, memberID: who, price: terms.price * 3, now: t0), "an inflated offer is refused")
        let cash = e.state.cash
        XCTAssertNil(e.jvOfferBuyBack(companyID: id, memberID: who, price: terms.price, now: t0))
        let first = try XCTUnwrap(e.jvBuyBackOffers(companyID: id).first)
        XCTAssertEqual(first.price, terms.price, accuracy: 1)
        XCTAssertEqual(e.state.cash, cash, "an offer moves no money")
        XCTAssertEqual(e.state.company(id)!.ownership, 80, accuracy: 0.01, "and no shares")
        XCTAssertEqual(e.jvStakes(companyID: id).count, 2)
        XCTAssertNotNil(e.jvOfferBuyBack(companyID: id, memberID: who, price: terms.price, now: t0), "one open offer at a time")
        XCTAssertNil(e.jvAnswerBuyBack(companyID: id, offerID: first.id, accept: false))
        XCTAssertEqual(e.state.cash, cash, "declined: nothing moved")
        XCTAssertEqual(e.state.company(id)!.ownership, 80, accuracy: 0.01)
        XCTAssertTrue(e.state.inbox.contains { $0.title.contains("said no") })
        XCTAssertTrue(e.jvBuyBackOffers(companyID: id).isEmpty)
        XCTAssertNotNil(e.jvAnswerBuyBack(companyID: id, offerID: first.id, accept: true), "a declined offer cannot be accepted later")

        XCTAssertNil(e.jvOfferBuyBack(companyID: id, memberID: who, price: terms.price, now: t0))
        let second = try XCTUnwrap(e.jvBuyBackOffers(companyID: id).first)
        XCTAssertNil(e.jvAnswerBuyBack(companyID: id, offerID: second.id, accept: true))
        XCTAssertEqual(cash - e.state.cash, terms.price, accuracy: 2, "accepted: the agreed price is paid")
        XCTAssertEqual(e.state.company(id)!.ownership, 100, accuracy: 0.01)
        XCTAssertEqual(e.jvStakes(companyID: id).count, 1)
        XCTAssertNil(JointVenture.payoutBlock(e.state, companyID: id), "alone again, the owner decides")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testABuybackOfferCanBeWithdrawnAndLapsesAfterAWeek() throws {
        var (e, id) = try makeCompany(seed: 94)
        try join(&e, id, friendA, pct: 20)
        let who = member(friendA)
        tick(&e, weeks: JVRules.lockUpWeeks + 1)
        let terms = try XCTUnwrap(e.jvExitTerms(companyID: id, memberID: who))
        XCTAssertNil(e.jvOfferBuyBack(companyID: id, memberID: who, price: terms.price, now: t0))
        let first = try XCTUnwrap(e.jvBuyBackOffers(companyID: id).first)
        XCTAssertTrue(e.jvWithdrawBuyBack(companyID: id, offerID: first.id))
        XCTAssertNotNil(e.jvAnswerBuyBack(companyID: id, offerID: first.id, accept: true), "a withdrawn offer cannot be accepted")
        XCTAssertNil(e.jvOfferBuyBack(companyID: id, memberID: who, price: terms.price, now: t0))
        let second = try XCTUnwrap(e.jvBuyBackOffers(companyID: id).first)
        e.jvSettle(now: hours(24 * 6))
        XCTAssertEqual(e.jvBuyBackOffers(companyID: id).count, 1, "open for a week")
        e.jvSettle(now: hours(24 * 7 + 1))
        XCTAssertTrue(e.jvBuyBackOffers(companyID: id).isEmpty)
        XCTAssertNotNil(e.jvAnswerBuyBack(companyID: id, offerID: second.id, accept: true), "a lapsed offer cannot be accepted")
        XCTAssertEqual(e.state.company(id)!.ownership, 80, accuracy: 0.01)
    }

    func testAPartnerWhoSoldNoLongerCountsInOpenVotes() throws {
        var (e, id) = try threeOwners(seed: 95)
        tick(&e, weeks: JVRules.lockUpWeeks + 1)
        guard case .called(let mid) = e.jvPropose(companyID: id, change: .policy("low"), urgent: true, now: t0) else { return XCTFail("no emergency meeting") }
        let item = try XCTUnwrap(try meeting(e, id, mid).items.first)
        XCTAssertTrue(e.jvVote(companyID: id, meetingID: mid, itemID: item.id, member: member(friendB), choice: .no, now: hours(1)))
        let terms = try XCTUnwrap(e.jvExitTerms(companyID: id, memberID: member(friendB)))
        XCTAssertNil(e.jvOfferBuyBack(companyID: id, memberID: member(friendB), price: terms.price, now: hours(2)))
        let offer = try XCTUnwrap(e.jvBuyBackOffers(companyID: id).first)
        XCTAssertNil(e.jvAnswerBuyBack(companyID: id, offerID: offer.id, accept: true))
        XCTAssertNil(try meeting(e, id, mid).items[0].votes[member(friendB)], "their vote left with their shares")
        e.jvSettle(now: hours(3))
        XCTAssertTrue(try meeting(e, id, mid).closed, "with their shares the owner now holds over half")
        XCTAssertEqual(e.dividendPolicy(companyID: id), "low")
    }
}
