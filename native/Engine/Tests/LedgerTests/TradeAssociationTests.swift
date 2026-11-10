import XCTest
import GameCore
import Finance
import Simulation
@testable import Businesses

final class TradeAssociationTests: XCTestCase {
    private let club = AssociationCatalogue.tradeClub(tradeName: "Bakery", region: "UK")
    private let good = AssociationStanding(reputation: 60, weeksNegative: 0, wageShortfall: 0, taxDue: false)

    func testDiscountGrowsWithMembersAndIsCapped() {
        XCTAssertEqual(GroupPurchasing.rate(members: 0, cap: 0.06), 0)
        XCTAssertEqual(GroupPurchasing.rate(members: 10, cap: 0.06), 0.02, accuracy: 1e-9)
        XCTAssertEqual(GroupPurchasing.rate(members: 500, cap: 0.06), 0.06, accuracy: 1e-9)
        XCTAssertEqual(GroupPurchasing.rate(members: 500, cap: 0.5), GroupPurchasing.hardCap, accuracy: 1e-9)
        XCTAssertEqual(GroupPurchasing.saving(spend: 1000, rate: 0.5), 80, accuracy: 0.001, "a rate above the hard cap is cut to it")
        XCTAssertEqual(GroupPurchasing.saving(spend: 0, rate: 0.05), 0)
        XCTAssertTrue(GroupPurchasing.words(members: 12, rate: 0.022, cap: 0.06).contains("2.2 percent"))
    }

    func testClubsPerTradeAndRegionAndAcrossTrades() {
        let list = AssociationCatalogue.clubs(tradeName: "Bakery", region: "UK")
        XCTAssertEqual(list.count, 1 + AssociationCatalogue.crossTrade.count)
        XCTAssertEqual(list.first?.id, "tr.bakery.uk")
        XCTAssertNotEqual(AssociationCatalogue.tradeClub(tradeName: "Bakery", region: "FR").id, club.id)
        XCTAssertTrue(AssociationCatalogue.crossTrade.allSatisfy { $0.tradeName == nil && $0.discountCap <= 0.04 })
    }

    func testStandardsCheckAndWarnFineRemoveLadder() {
        XCTAssertTrue(AssociationStandards.breaches(club, good).isEmpty)
        let bad = AssociationStanding(reputation: 30, weeksNegative: 6, wageShortfall: 10, taxDue: true)
        XCTAssertEqual(Set(AssociationStandards.breaches(club, bad)), Set(AssociationStandard.allCases))
        XCTAssertEqual(AssociationStandards.breaches(AssociationCatalogue.crossTrade[0], AssociationStanding(reputation: 10, weeksNegative: 9, wageShortfall: 0, taxDue: false)), [])
        let b = AssociationStandards.breaches(club, bad)
        XCTAssertEqual(AssociationEnforcement.next(strikes: 0, breaches: b).action, .warn)
        XCTAssertEqual(AssociationEnforcement.next(strikes: 1, breaches: b).action, .fine)
        XCTAssertEqual(AssociationEnforcement.next(strikes: 2, breaches: b).action, .remove)
        let clean = AssociationEnforcement.next(strikes: 2, breaches: [])
        XCTAssertEqual(clean.action, .clear)
        XCTAssertEqual(clean.strikes, 0)
        XCTAssertTrue(AssociationEnforcement.isDue(joined: 10, week: 14))
        XCTAssertFalse(AssociationEnforcement.isDue(joined: 10, week: 10))
        XCTAssertFalse(AssociationEnforcement.isDue(joined: 10, week: 13))
    }

    func testPreviewsSayWhatWillHappen() {
        let lines = TradeAssociations.joinPreview(club, members: 12, standing: good)
        XCTAssertTrue(lines.contains { $0.contains("fee") })
        XCTAssertTrue(lines.contains { $0.contains("warning, then a fine") })
        let bad = TradeAssociations.joinPreview(club, members: 12, standing: AssociationStanding(reputation: 20, weeksNegative: 0, wageShortfall: 0, taxDue: false))
        XCTAssertTrue(bad.contains { $0.hasPrefix("You do not meet these today") })
    }

    private func openBakery(_ e: inout GameEngine) throws -> Int {
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 160_000_000, why: "Test funds")
            guard case .success(let i) = CompanySetup.create(&s, tradeID: "bakery", cityID: s.player.cityID, data: data, context: ctx) else { return }
            let est = CompanySetup.estimate(tradeID: "bakery", cityID: s.player.cityID, size: 1, state: s, data: data)
            _ = Payments.injectCash(&s, companyID: i, amount: (est?.total ?? 1_000_000) * 1.6 + 3_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: i, data: data)
            id = i
        }
        for _ in 0..<(8 * 7) { e.nextDay() }
        return id
    }

    func testJoinBooksFeeBalancedSavesAndChecksStandards() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4242)
        let id = try openBakery(&e)
        let co = try XCTUnwrap(e.state.company(id))
        let trade = e.tradeName(co)
        let region = co.countryCode
        let c = AssociationCatalogue.tradeClub(tradeName: trade, region: region)
        let cash0 = co.cash
        var result: JoinResult = .joined
        e.update { s, _, _ in result = TradeAssociations.join(&s, companyID: id, club: c, members: 20, tradeName: trade) }
        XCTAssertEqual(result, .joined)
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).cash, cash0 - c.monthlyFee, accuracy: 1.01)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        e.update { s, _, _ in result = TradeAssociations.join(&s, companyID: id, club: c, members: 20, tradeName: trade) }
        XCTAssertEqual(result, .refused("This company already belongs to a club. Leave it first."))
        e.update { s, _, _ in
            TradeAssociations.leave(&s, companyID: id)
            result = TradeAssociations.join(&s, companyID: id, club: AssociationCatalogue.tradeClub(tradeName: "Dental clinic", region: region), members: 5, tradeName: trade)
        }
        XCTAssertEqual(result, .refused("This club is for Dental clinic."))

        e.update { s, _, _ in _ = TradeAssociations.join(&s, companyID: id, club: c, members: 20, tradeName: trade) }
        let joined = e.state.week
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].reputation = 20
        }
        let before = try XCTUnwrap(TradeAssociations.membership(e.state, companyID: id))
        e.update { s, data, _ in
            s.week = joined + 1
            TradeAssociations.weekly(&s, data: data)
        }
        let m1 = try XCTUnwrap(TradeAssociations.membership(e.state, companyID: id))
        XCTAssertGreaterThanOrEqual(m1.saved, before.saved)
        XCTAssertEqual(m1.strikes, 0, "no check before the fourth week")
        e.update { s, data, _ in s.week = joined + 4; TradeAssociations.weekly(&s, data: data) }
        let m4 = try XCTUnwrap(TradeAssociations.membership(e.state, companyID: id))
        XCTAssertEqual(m4.strikes, 1)
        XCTAssertEqual(m4.feesPaid, before.feesPaid + c.monthlyFee, accuracy: 0.001)
        XCTAssertEqual(e.state.inbox.first?.title, "Warning from \(c.name)")
        e.update { s, data, _ in s.week = joined + 8; TradeAssociations.weekly(&s, data: data) }
        XCTAssertEqual(TradeAssociations.membership(e.state, companyID: id)?.strikes, 2)
        XCTAssertEqual(e.state.inbox.first?.title, "Fine from \(c.name)")
        e.update { s, data, _ in s.week = joined + 12; TradeAssociations.weekly(&s, data: data) }
        XCTAssertNil(TradeAssociations.membership(e.state, companyID: id), "third failed check removes the member")
        XCTAssertEqual(e.state.inbox.first?.title, "Removed from \(c.name)")
        e.update { s, _, _ in result = TradeAssociations.join(&s, companyID: id, club: c, members: 20, tradeName: trade) }
        if case .refused = result {} else { XCTFail("a removed company waits before rejoining") }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testGroupSavingBooksBalanced() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4242)
        let id = try openBakery(&e)
        let cash0 = try XCTUnwrap(e.state.company(id)).cash
        let saving = GroupPurchasing.saving(spend: 2000, rate: GroupPurchasing.rate(members: 20, cap: 0.06))
        XCTAssertEqual(saving, 60, accuracy: 0.001)
        e.update { s, _, _ in SupplyMarketBooks.bookPurchaseDifference(&s, buyerCompanyID: id, saving: saving) }
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).cash, cash0 + 60, accuracy: 1.01)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testASoldCompanyLeavesItsClubAndTheMemberCountNeverDropsBelowOne() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4243)
        let id = try openBakery(&e)
        let co = try XCTUnwrap(e.state.company(id))
        let trade = e.tradeName(co)
        let c = AssociationCatalogue.tradeClub(tradeName: trade, region: co.countryCode)
        e.update { s, _, _ in _ = TradeAssociations.join(&s, companyID: id, club: c, members: 20, tradeName: trade) }
        e.update { s, _, _ in TradeAssociations.setMembers(&s, companyID: id, members: 0) }
        XCTAssertEqual(TradeAssociations.membership(e.state, companyID: id)?.members, 1, "the company counts as a member itself")
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .sold } }
        e.update { s, d, _ in TradeAssociations.weekly(&s, data: d) }
        XCTAssertNil(TradeAssociations.membership(e.state, companyID: id), "no ghost member is left in the club")
    }

    private func ev(_ kind: PlayerEventKind, audience: PlayerEventAudience = .everyone, count: Int? = nil, other: String? = nil, club: String? = nil,
                    company: String? = "Lund Bakery", trade: String? = "Bakery", city: String? = "Leeds") -> PlayerEvent {
        PlayerEvent(id: "e", kind: kind, playerID: "p1", playerName: "Sofie Lund", countryCode: "NO", audience: audience, day: 100, trade: trade, city: city,
                    company: company, count: count, otherName: other, club: club)
    }

    func testSentencesUseOnlyTheEventsOwnFacts() {
        XCTAssertEqual(PlayerNewsRules.sentence(ev(.branchMilestone, count: 10), namesVisible: true), "Sofie Lund opened the tenth branch of Lund Bakery.")
        XCTAssertEqual(PlayerNewsRules.sentence(ev(.branchMilestone, count: 10), namesVisible: false), "Sofie Lund opened the tenth branch of a bakery in Leeds.")
        XCTAssertNil(PlayerNewsRules.sentence(ev(.branchMilestone), namesVisible: true), "no count, no sentence")
        XCTAssertNil(PlayerNewsRules.sentence(ev(.branchMilestone, count: 1), namesVisible: true), "a first branch is not a milestone")
        XCTAssertEqual(PlayerNewsRules.sentence(ev(.wentViral), namesVisible: false), "A bakery in Leeds, a startup run by Sofie Lund, went viral.")
        XCTAssertEqual(PlayerNewsRules.sentence(ev(.supplierMilestone, count: 5000), namesVisible: true), "Sofie Lund's supplier, Lund Bakery, has now delivered 5000 units to other players' companies.")
        XCTAssertEqual(PlayerNewsRules.sentence(ev(.acquisition, other: "Dahl Print"), namesVisible: true), "Sofie Lund's Lund Bakery acquired Dahl Print.")
        XCTAssertNil(PlayerNewsRules.sentence(ev(.acquisition), namesVisible: true))
        XCTAssertEqual(PlayerNewsRules.sentence(ev(.newAssociation, club: "NO Bakery Association"), namesVisible: false), "Sofie Lund joined NO Bakery Association.")
        XCTAssertEqual(PlayerNewsRules.sentence(ev(.seasonMilestone, count: 3), namesVisible: false), "Sofie Lund finished season 3.")
        for n in [3, 12, 5000] {
            for k in [PlayerEventKind.supplierMilestone, .seasonMilestone] {
                XCTAssertEqual(PlayerNewsRules.numbersIn(PlayerNewsRules.sentence(ev(k, count: n), namesVisible: false) ?? ""), [n])
            }
        }
        XCTAssertEqual(PlayerNewsRules.numbersIn(PlayerNewsRules.sentence(ev(.branchMilestone, count: 42), namesVisible: false) ?? ""), [42])
        XCTAssertTrue(PlayerNewsRules.sentence(ev(.branchMilestone, count: 42), namesVisible: false)?.contains("42nd") == true)
        XCTAssertEqual(PlayerNewsRules.ordinal(21), "21st")
        XCTAssertEqual(PlayerNewsRules.ordinal(112), "112th")
    }

    func testPrivacyAndFilters() {
        let open = ev(.wentViral, audience: .everyone), friendsOnly = ev(.wentViral, audience: .friends)
        XCTAssertTrue(PlayerNewsRules.canSee(open, viewerIsFriend: false))
        XCTAssertFalse(PlayerNewsRules.canSee(friendsOnly, viewerIsFriend: false))
        XCTAssertTrue(PlayerNewsRules.canSee(friendsOnly, viewerIsFriend: true))
        XCTAssertTrue(PlayerNewsRules.matches(open, filter: .everyone, viewerIsFriend: false, viewerTrades: [], viewerCountry: "UK"))
        XCTAssertFalse(PlayerNewsRules.matches(open, filter: .friends, viewerIsFriend: false, viewerTrades: [], viewerCountry: "UK"))
        XCTAssertTrue(PlayerNewsRules.matches(open, filter: .myTrade, viewerIsFriend: false, viewerTrades: ["bakery"], viewerCountry: "UK"))
        XCTAssertFalse(PlayerNewsRules.matches(open, filter: .myTrade, viewerIsFriend: false, viewerTrades: ["Florist"], viewerCountry: "UK"))
        XCTAssertTrue(PlayerNewsRules.matches(open, filter: .myCountry, viewerIsFriend: false, viewerTrades: [], viewerCountry: "NO"))
        XCTAssertFalse(PlayerNewsRules.matches(open, filter: .myCountry, viewerIsFriend: false, viewerTrades: [], viewerCountry: "UK"))
    }
}
