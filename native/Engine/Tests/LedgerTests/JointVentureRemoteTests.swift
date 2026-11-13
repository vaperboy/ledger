import XCTest
import GameCore
import Finance
import Businesses
import Events
import Simulation

final class JointVentureRemoteTests: XCTestCase {
    private let friend = (id: "0b4c7a52-1111-4222-8333-444455556666", name: "Ingrid Solheim")
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeCompany(seed: Int) throws -> (engine: GameEngine, id: Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 300_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID) else { throw XCTSkip("could not start a company") }
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
        return (e, id)
    }

    private func withRealPartner(seed: Int, pct: Double = 20) throws -> (engine: GameEngine, id: Int) {
        var (e, id) = try makeCompany(seed: seed)
        let price = e.jvFairPrice(companyID: id, pct: pct)
        XCTAssertNil(e.jvRemoteJoin(companyID: id, playerID: friend.id, name: friend.name, pct: pct, price: price, lockAt: t0.timeIntervalSince1970 + 26 * 86400))
        return (e, id)
    }

    func testARealPartnerJoinsOnceAndThePriceGoesToTheCompany() throws {
        var (e, id) = try makeCompany(seed: 801)
        let before = try XCTUnwrap(e.state.company(id)).cash
        let price = e.jvFairPrice(companyID: id, pct: 20)
        XCTAssertNil(e.jvRemoteJoin(companyID: id, playerID: friend.id, name: friend.name, pct: 20, price: price))
        let after = try XCTUnwrap(e.state.company(id)).cash
        XCTAssertGreaterThan(after, before, "the partner's price is in the company")
        XCTAssertNil(e.jvRemoteJoin(companyID: id, playerID: friend.id, name: friend.name, pct: 20, price: price), "a second report of the same join changes nothing")
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).cash, after)
        XCTAssertEqual(e.jvStakes(companyID: id).count, 2)
        XCTAssertTrue(e.jvIsRemote(companyID: id))
        XCTAssertEqual(e.jointVenture(companyID: id)?.members.last?.mock, false)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testTheLockUpOfARealPartnerFollowsTheServerClock() throws {
        let (e, id) = try withRealPartner(seed: 802)
        let member = "p:" + friend.id
        let early = JointVenture.exitTerms(e.state, companyID: id, memberID: member, data: e.data, context: e.context, now: t0.timeIntervalSince1970)
        XCTAssertEqual(early?.locked, true)
        let late = JointVenture.exitTerms(e.state, companyID: id, memberID: member, data: e.data, context: e.context, now: t0.timeIntervalSince1970 + 27 * 86400)
        XCTAssertEqual(late?.locked, false)
    }

    func testABoardWithRealPlayersWaitsForTheServerCount() throws {
        var (e, id) = try withRealPartner(seed: 803)
        let level = try XCTUnwrap(e.state.company(id)).priceLevel
        let made = e.jvMakeItem(companyID: id, kind: .price, steps: -1)
        let item = try XCTUnwrap(made.item)
        guard case .called(let mid) = e.jvCallUrgent(companyID: id, reason: "Prices", items: [item], now: t0) else { return XCTFail("not called") }
        var m = try XCTUnwrap(e.jointVenture(companyID: id)?.meetings.first { $0.id == mid })
        XCTAssertFalse(m.closed, "80% said yes here, but the server counts this board")
        e.jvSettle(now: t0.addingTimeInterval(48 * 3600))
        m = try XCTUnwrap(e.jointVenture(companyID: id)?.meetings.first { $0.id == mid })
        XCTAssertFalse(m.closed, "the deadline alone does not close it either")
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).priceLevel, level)

        e.jvLinkItem(companyID: id, meetingID: mid, itemID: item.id, remoteID: "item-1", remoteMeeting: "meeting-1", closesAt: t0.timeIntervalSince1970 + 3600)
        XCTAssertTrue(e.jvRemoteStanding(companyID: id, meetingID: mid, itemID: item.id, yes: 8000, no: 2000, total: 10_000))
        XCTAssertFalse(e.jvRemoteStanding(companyID: id, meetingID: mid, itemID: item.id, yes: 8000, no: 2000, total: 10_000), "an unchanged count writes nothing")
        XCTAssertEqual(e.jvTally(companyID: id, meetingID: mid, itemID: item.id)?.yesPercent ?? 0, 80, accuracy: 0.01)

        XCTAssertTrue(e.jvRemoteResult(companyID: id, meetingID: mid, itemID: item.id, passed: true, votes: ["p:" + friend.id: .no]))
        m = try XCTUnwrap(e.jointVenture(companyID: id)?.meetings.first { $0.id == mid })
        XCTAssertTrue(m.closed)
        XCTAssertEqual(m.items.first?.outcome, .passed)
        XCTAssertEqual(m.items.first?.votes["p:" + friend.id], .no)
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).priceLevel, level - 1, "what the server passed is carried out")
        XCTAssertFalse(e.jvRemoteResult(companyID: id, meetingID: mid, itemID: item.id, passed: true), "a result is taken once")
    }

    func testAnItemTheServerRefusedLeavesTheAgenda() throws {
        var (e, id) = try withRealPartner(seed: 804)
        let item = try XCTUnwrap(e.jvMakeItem(companyID: id, kind: .price, steps: 1).item)
        XCTAssertTrue(e.jvQueue(companyID: id, item: item, now: t0))
        let mid = try XCTUnwrap(e.jointVenture(companyID: id)?.meetings.first { !$0.closed }?.id)
        XCTAssertTrue(e.jvDropItem(companyID: id, meetingID: mid, itemID: item.id, why: "The board is busy."))
        XCTAssertNil(e.jointVenture(companyID: id)?.meetings.first { $0.id == mid }, "an emptied meeting goes too")
        XCTAssertTrue(e.state.inbox.contains { $0.title.contains("Not put to the board") })
    }

    func testACompanyWithRealPartnersIsNotSoldThroughABroker() throws {
        var (e, id) = try withRealPartner(seed: 805)
        let made = e.jvMakeItem(companyID: id, kind: .sell)
        XCTAssertNil(made.item)
        XCTAssertNotNil(made.problem)
        XCTAssertNotNil(e.jvMakeItem(companyID: id, kind: .dissolve).item, "dissolving pays everyone through the server")
    }

    func testSampleAndRealPartnersDoNotMix() throws {
        var (e, id) = try withRealPartner(seed: 806)
        let fair = e.jvFairPrice(companyID: id, pct: 10)
        guard case .refused = e.jvInvite(companyID: id, playerID: "pl-x", name: "Sample Sam", linkKey: "pl-x", mock: true, pct: 10, price: fair, myLinkKeys: []) else {
            return XCTFail("a sample partner cannot sit on a board the server counts")
        }
    }

    func testAPartnerWhoSoldOnTheServerIsPaidAndLeavesTheBoard() throws {
        var (e, id) = try withRealPartner(seed: 807)
        let cash = e.state.cash
        let mine = try XCTUnwrap(e.state.company(id)).ownership
        let price = try XCTUnwrap(e.jvExitTerms(companyID: id, memberID: "p:" + friend.id)).price
        XCTAssertNil(e.jvPartnerLeft(companyID: id, memberID: "p:" + friend.id, price: price))
        XCTAssertEqual(e.jvStakes(companyID: id).count, 1)
        XCTAssertGreaterThan(try XCTUnwrap(e.state.company(id)).ownership, mine)
        XCTAssertEqual(cash - e.state.cash, price, accuracy: 1)
        XCTAssertFalse(e.jvIsRemote(companyID: id))
        XCTAssertNotNil(e.jvPartnerLeft(companyID: id, memberID: "p:" + friend.id, price: price), "they are gone, so nothing is paid twice")
        XCTAssertEqual(cash - e.state.cash, price, accuracy: 1)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testAnOfferTheServerClosedWithoutASaleMovesNothing() throws {
        var (e, id) = try makeCompany(seed: 808)
        XCTAssertNil(e.jvRemoteJoin(companyID: id, playerID: friend.id, name: friend.name, pct: 20, price: e.jvFairPrice(companyID: id, pct: 20), lockAt: 1), "a lock-up that ended long ago")
        let member = "p:" + friend.id
        let fair = try XCTUnwrap(e.jvExitTerms(companyID: id, memberID: member)).price
        XCTAssertNil(e.jvOfferBuyBack(companyID: id, memberID: member, price: fair, now: t0))
        let offer = try XCTUnwrap(e.jvBuyBackOffers(companyID: id).first)
        XCTAssertFalse(offer.mock)
        e.jvSettle(now: t0.addingTimeInterval(30 * 86400))
        XCTAssertEqual(e.jvBuyBackOffers(companyID: id).count, 1, "the server, not the local clock, ends an offer to a real player")
        let cash = e.state.cash
        XCTAssertTrue(e.jvCloseBuyBack(companyID: id, offerID: offer.id, declined: true))
        XCTAssertTrue(e.jvBuyBackOffers(companyID: id).isEmpty)
        XCTAssertEqual(e.state.cash, cash)
        XCTAssertEqual(e.jvStakes(companyID: id).count, 2)
    }

    func testMoneyForSharesInAnotherPlayersCompanyGoesThroughTheLedger() throws {
        var (e, _) = try makeCompany(seed: 809)
        let cur = e.homeCurrencyCode
        let cash0 = e.state.cash
        let stake = OnlineSettlement(id: "v1", amount: -50_000, currency: cur, kind: "venture_stake", label: "Joined Fjord Bakery", meta: .object(["ventureID": "ven-1", "percent": 20]))
        XCTAssertEqual(e.bookOnlineSettlements([stake]), ["v1"])
        XCTAssertEqual(e.bookOnlineSettlements([stake]), ["v1"])
        let paid = cash0 - e.state.cash
        XCTAssertGreaterThan(paid, 0, "the price left the player's cash once")
        XCTAssertEqual(e.jvHoldings.count, 1)
        XCTAssertEqual(e.jvHoldings.first?.name, "Fjord Bakery")
        XCTAssertEqual(e.jvHoldings.first?.paid ?? 0, paid, accuracy: 0.01)

        let dividend = OnlineSettlement(id: "v2", amount: 4_000, currency: cur, kind: "venture_dividend", label: "Dividend: Fjord Bakery", meta: .object(["ventureID": "ven-1"]))
        let taxed0 = e.state.tax.dividends
        e.bookOnlineSettlements([dividend])
        XCTAssertGreaterThan(e.state.cash, cash0 - paid)
        XCTAssertGreaterThan(e.state.tax.dividends, taxed0)
        XCTAssertGreaterThan(e.jvHoldings.first?.received ?? 0, 0)

        let cash1 = e.state.cash
        let gains0 = e.state.tax.gains
        let exit = OnlineSettlement(id: "v3", amount: 80_000, currency: cur, kind: "venture_exit", label: "Sold your shares in Fjord Bakery", meta: .object(["ventureID": "ven-1"]))
        e.bookOnlineSettlements([exit])
        XCTAssertGreaterThan(e.state.cash, cash1)
        XCTAssertGreaterThan(e.state.tax.gains, gains0, "selling above the price paid is a gain")
        XCTAssertTrue(e.jvHoldings.isEmpty)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testACapitalCallLargerThanTheStakeAllowsIsNotBooked() throws {
        var (e, _) = try makeCompany(seed: 812)
        let cur = e.homeCurrencyCode
        let stake = OnlineSettlement(id: "k1", amount: -50_000, currency: cur, kind: "venture_stake", label: "Joined Fjord Bakery", meta: .object(["ventureID": "ven-9", "percent": 20]))
        e.bookOnlineSettlements([stake])
        let paid = try XCTUnwrap(e.jvHoldings.first).paid
        XCTAssertGreaterThan(paid, 0)

        let cash0 = e.state.cash
        let small = OnlineSettlement(id: "k2", amount: -20_000, currency: cur, kind: "venture_capital_call", label: "Capital call: Fjord Bakery",
                                     meta: .object(["ventureID": "ven-9"]))
        XCTAssertEqual(e.bookOnlineSettlements([small]), ["k2"])
        XCTAssertLessThan(e.state.cash, cash0, "a call within the stake is paid")
        XCTAssertTrue(JointVentureSettlements.skipped(e.state).isEmpty)

        let cash1 = e.state.cash
        let paid1 = try XCTUnwrap(e.jvHoldings.first).paid
        let huge = OnlineSettlement(id: "k3", amount: -350_000, currency: cur, kind: "venture_capital_call", label: "Capital call: Fjord Bakery",
                                    meta: .object(["ventureID": "ven-9"]))
        let stranger = OnlineSettlement(id: "k4", amount: -100, currency: cur, kind: "venture_capital_call", label: "Capital call: Other Co",
                                        meta: .object(["ventureID": "ven-unknown"]))
        XCTAssertEqual(e.bookOnlineSettlements([huge, stranger]), ["k3", "k4"], "out-of-bounds calls are acknowledged, not retried")
        XCTAssertEqual(e.state.cash, cash1, "nothing is taken for a call above the limit or for a stake never paid for")
        XCTAssertEqual(try XCTUnwrap(e.jvHoldings.first { $0.id == "ven-9" }).paid, paid1)
        XCTAssertEqual(JointVentureSettlements.skipped(e.state).count, 2)
        XCTAssertTrue(e.state.inbox.contains { $0.title.hasPrefix("Capital call not paid") })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testTheOwnersSideOfABoardSettlementMovesNoMoneyTwice() throws {
        var (e, id) = try withRealPartner(seed: 810)
        let cur = e.homeCurrencyCode
        let cash = e.state.cash
        let company = try XCTUnwrap(e.state.company(id)).cash
        let meta: JSONValue = .object(["ventureID": "ven-1", "companyKey": .string("own.\(id)")])
        let rows = [
            OnlineSettlement(id: "c1", amount: 90_000, currency: cur, kind: "venture_capital", label: "New partner in Cafe", companyKey: "own.\(id)", meta: meta),
            OnlineSettlement(id: "c2", amount: -7_000, currency: cur, kind: "venture_company_payout", label: "Dividend paid to partners", companyKey: "own.\(id)", meta: meta),
            OnlineSettlement(id: "c3", amount: -60_000, currency: cur, kind: "venture_buyback", label: "Bought back shares", companyKey: "own.\(id)", meta: meta),
        ]
        XCTAssertEqual(e.bookOnlineSettlements(rows).count, 3)
        XCTAssertEqual(e.state.cash, cash, "the board itself books these when it follows the server")
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).cash, company)
    }

    func testAPartnerHearsWhatTheBoardDecided() throws {
        var (e, _) = try makeCompany(seed: 811)
        let row = OnlineSettlement(id: "d1", amount: 0, currency: e.homeCurrencyCode, kind: "venture_decision", label: "Passed: Pay a dividend (Fjord Bakery)",
                                   meta: .object(["ventureID": "ven-1", "passed": true]))
        e.bookOnlineSettlements([row])
        XCTAssertTrue(e.state.inbox.contains { $0.body.contains("Pay a dividend") })
    }
}
