import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Events
import Simulation

/// Deals between players: franchising to players for a chosen time, selling a company to players, and buying another player's company.
final class PlayerDealsTests: XCTestCase {
    private func franchisor() throws -> (GameEngine, Int) {
        var e = try ChainsTests.engine("UK", seed: 4242)
        let id = ChainsTests.start(&e, "cafe", name: "Corner Cafe")
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].status = .open
            s.companies[i].set("fr", .object(["on": .bool(true), "fee": .number(50_000), "roy": .number(0.05), "supp": .number(1), "units": .array([]), "app": .array([]), "brand": .number(40)]))
        }
        return (e, id)
    }

    private func applicant(_ code: String) -> PlayerDeals.PlayerApplicant {
        PlayerDeals.PlayerApplicant(name: "Player \(code)", profileCode: code, cityID: "", capital: 80_000, skill: 60)
    }

    private func forSale(_ e: GameEngine, expires: Int? = nil, link: String = "key-seller") -> PlayerDeals.CompanyListing {
        PlayerDeals.CompanyListing(id: "C900", ownerID: "owner-seller", ownerName: "Sam Seller", profileCode: "P9", linkKey: link, companyName: "Marsh Cafe", tradeID: "cafe",
                                   cityID: e.state.player.cityID, countryCode: e.state.homeCountryCode, size: 1, yearlyRevenue: 400_000, yearlyProfit: 60_000, staff: 3, reputation: 55,
                                   weeksTrading: 80, askPrice: 0, expiresDay: expires ?? PlayerDeals.today(e.state) + 5)
    }

    private func asked(_ l: PlayerDeals.CompanyListing) -> PlayerDeals.CompanyListing {
        var x = l
        x.askPrice = (PlayerDeals.value(l) * 1.2 / 1000).rounded(.up) * 1000
        return x
    }

    // MARK: Franchising to players

    func testOpeningTheFranchiseToPlayersForAChosenTime() throws {
        var (e, id) = try franchisor()
        let today = PlayerDeals.today(e.state)
        XCTAssertNil(e.franchiseOpenUntil(companyID: id))
        XCTAssertEqual(e.openFranchiseToPlayers(companyID: id, days: 5), .badDays, "only the offered lengths")
        XCTAssertEqual(e.openFranchiseToPlayers(companyID: id, days: 14), .ok(untilDay: today + 14))
        XCTAssertEqual(e.franchiseOpenUntil(companyID: id), today + 14)
        let listing = try XCTUnwrap(e.franchiseListing(companyID: id, ownerID: "me", ownerName: "Me", profileCode: "P1", linkKey: "me"))
        XCTAssertEqual(listing.brandName, "Corner Cafe")
        XCTAssertEqual(listing.tradeID, "cafe")
        XCTAssertEqual(listing.expiresDay, today + 14)
        e.closeFranchiseToPlayers(companyID: id)
        XCTAssertNil(e.franchiseOpenUntil(companyID: id))
        XCTAssertNil(e.franchiseListing(companyID: id, ownerID: "me", ownerName: "Me", profileCode: "P1", linkKey: "me"))
    }

    func testAnUnlaunchedFranchiseCannotBeOpened() throws {
        var e = try ChainsTests.engine("UK", seed: 4243)
        let id = ChainsTests.start(&e, "cafe")
        XCTAssertEqual(e.openFranchiseToPlayers(companyID: id, days: 7), .notFranchising)
    }

    func testPlayersApplyOnlyWhileOpenAndOnce() throws {
        var (e, id) = try franchisor()
        XCTAssertFalse(e.addFranchiseApplicant(companyID: id, applicant: applicant("A1")), "not open yet")
        e.openFranchiseToPlayers(companyID: id, days: 7)
        XCTAssertTrue(e.addFranchiseApplicant(companyID: id, applicant: applicant("A1")))
        XCTAssertFalse(e.addFranchiseApplicant(companyID: id, applicant: applicant("A1")), "once per player")
        XCTAssertTrue(e.addFranchiseApplicant(companyID: id, applicant: applicant("A2")))
        XCTAssertEqual(e.state.company(id)?.value("fr")["app"].array.count, 2)
        XCTAssertTrue(e.state.inbox.contains { $0.companyID == id && $0.title.contains("A player wants a unit") })
        e.closeFranchiseToPlayers(companyID: id)
        XCTAssertEqual(e.state.company(id)?.value("fr")["app"].array.count, 0, "players who did not sign leave")
    }

    func testTheOfferEndsOnItsDay() throws {
        var (e, id) = try franchisor()
        e.openFranchiseToPlayers(companyID: id, days: 1)
        XCTAssertTrue(e.addFranchiseApplicant(companyID: id, applicant: applicant("A1")))
        for _ in 0..<10 { e.nextDay() }
        e.update { s, _, _ in PlayerDeals.weekly(&s) }
        XCTAssertNil(e.franchiseOpenUntil(companyID: id))
        XCTAssertEqual(e.state.company(id)?.value("fr")["app"].array.count, 0)
        XCTAssertTrue(e.state.inbox.contains { $0.companyID == id && $0.title == "Your franchise offer to players ended" })
    }

    func testAnotherPlayersFranchiseBecomesABrandUntilItEnds() throws {
        var (e, id) = try franchisor()
        e.openFranchiseToPlayers(companyID: id, days: 3)
        let listing = try XCTUnwrap(e.franchiseListing(companyID: id, ownerID: "owner-x", ownerName: "Xavi", profileCode: "PX", linkKey: "key-x"))
        let brandID = try XCTUnwrap(e.importPlayerFranchise(listing))
        XCTAssertEqual(brandID, "P:" + listing.id)
        var late = listing
        late.expiresDay = PlayerDeals.today(e.state) - 1
        XCTAssertNil(e.importPlayerFranchise(late), "an ended offer cannot be taken up")
    }

    // MARK: Selling a company to players

    func testShowingACompanyToPlayersForAChosenTime() throws {
        var (e, id) = try franchisor()
        XCTAssertNil(e.playerSaleUntil(companyID: id))
        XCTAssertFalse(e.startSaleToPlayers(companyID: id, days: 5), "only the offered lengths")
        XCTAssertTrue(e.startSaleToPlayers(companyID: id, days: 7))
        XCTAssertEqual(e.playerSaleUntil(companyID: id), PlayerDeals.today(e.state) + 7)
        let ask = e.companyAskingValue(companyID: id)
        XCTAssertGreaterThanOrEqual(ask, 0)
        let l = e.companyListing(companyID: id, ownerID: "me", ownerName: "Me", profileCode: "P1", linkKey: "me", askPrice: max(1000, ask))
        XCTAssertEqual(l?.companyName, "Corner Cafe")
        // An offer arrives, once per player, and lands beside the others.
        XCTAssertTrue(e.addPlayerSaleOffer(companyID: id, buyer: CompanySale.PlayerBuyer(name: "Bea", profileCode: "PB"), price: 123_456))
        XCTAssertFalse(e.addPlayerSaleOffer(companyID: id, buyer: CompanySale.PlayerBuyer(name: "Bea", profileCode: "PB"), price: 200_000))
        XCTAssertTrue(e.state.inbox.contains { $0.companyID == id && $0.title.hasPrefix("Offer for") })
        let offers = e.state.rest["sales"]?.array.first { $0["co"].int == id }?["offers"].array ?? []
        XCTAssertTrue(offers.contains { $0["k"].string == "player" })
    }

    func testNoOfferWhenTheCompanyIsNotShownToPlayers() throws {
        var (e, id) = try franchisor()
        XCTAssertFalse(e.addPlayerSaleOffer(companyID: id, buyer: CompanySale.PlayerBuyer(name: "Bea", profileCode: "PB"), price: 100_000))
        XCTAssertFalse(e.addPlayerSaleOffer(companyID: id, buyer: CompanySale.PlayerBuyer(name: "", profileCode: "PB"), price: 100_000))
    }

    // MARK: The seller's answer

    func testTheSellerAcceptsCountersOrRefuses() throws {
        let e = try ChainsTests.engine("UK", seed: 1)
        let l = asked(forSale(e))
        let v = PlayerDeals.value(l)
        XCTAssertGreaterThan(v, 0)
        XCTAssertEqual(PlayerDeals.reply(to: l.askPrice, on: l, round: 0), .accept)
        XCTAssertEqual(PlayerDeals.reply(to: v * 1.5, on: l, round: 0), .accept)
        XCTAssertEqual(PlayerDeals.reply(to: v * 0.1, on: l, round: 0), .refuse)
        XCTAssertEqual(PlayerDeals.reply(to: -5, on: l, round: 0), .refuse)
        XCTAssertEqual(PlayerDeals.reply(to: .nan, on: l, round: 0), .refuse)
        guard case .counter(let c) = PlayerDeals.reply(to: v * 0.9, on: l, round: 0) else { return XCTFail("a bid a little low gets a counter") }
        XCTAssertLessThanOrEqual(c, l.askPrice)
        XCTAssertGreaterThan(c, v * 0.9)
        XCTAssertEqual(PlayerDeals.reply(to: c, on: l, round: 1), .accept, "the counter itself is always accepted")
        XCTAssertEqual(PlayerDeals.reply(to: v * 0.9, on: l, round: 3), .refuse, "no bargaining after three offers")
    }

    // MARK: Buying

    func testBuyingACompanyOpensItAndPaysTheSeller() throws {
        var e = try ChainsTests.engine("UK", seed: 7)
        let l = asked(forSale(e))
        let before = e.state.companies.count
        let cash = Payments.liquid(e.state)
        let plan = try XCTUnwrap(e.playerCompanyBuyPlan(l, price: l.askPrice))
        XCTAssertTrue(plan.affordable)
        XCTAssertGreaterThan(plan.cashNeeded, l.askPrice)
        guard case .ok(let id) = e.buyPlayerCompany(l, price: l.askPrice, buyerLinkKeys: ["me"]) else { return XCTFail("could not buy") }
        XCTAssertEqual(e.state.companies.count, before + 1)
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.name, "Marsh Cafe")
        XCTAssertEqual(co.type, "cafe")
        XCTAssertTrue(co.status.isLive)
        XCTAssertLessThanOrEqual(Payments.liquid(e.state), cash - l.askPrice + 1, "the price left the player's money")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testBuyingIsRefusedForLinkedAccountsEndedListingsAndLowOffers() throws {
        var e = try ChainsTests.engine("UK", seed: 8)
        let l = asked(forSale(e))
        let before = e.state.companies.count
        XCTAssertEqual(e.buyPlayerCompany(l, price: l.askPrice, buyerLinkKeys: ["key-seller"]), .notAllowed("Not available: linked account"))
        var ended = l
        ended.expiresDay = PlayerDeals.today(e.state) - 1
        XCTAssertEqual(e.buyPlayerCompany(ended, price: l.askPrice, buyerLinkKeys: ["me"]), .notAllowed("This listing has ended."))
        XCTAssertEqual(e.buyPlayerCompany(l, price: PlayerDeals.value(l) * 0.1, buyerLinkKeys: ["me"]), .notAllowed("The seller would not take that."))
        XCTAssertEqual(e.state.companies.count, before, "nothing was bought")
    }

    func testBuyingNeedsTheMoney() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Poor", seed: 9)
        var big = forSale(e)
        big.yearlyRevenue = 40_000_000_000
        let l = asked(big)
        XCTAssertEqual(e.buyPlayerCompany(l, price: l.askPrice, buyerLinkKeys: ["me"]), .notEnoughCash)
    }
}
