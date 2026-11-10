import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Simulation

final class SalesChannelTests: XCTestCase {
    private func openBakery(_ e: inout GameEngine, channel: SalesChannel?) throws -> Int {
        let id = ChainsTests.start(&e, "bakery")
        for _ in 0..<70 where e.state.company(id)?.status != .open { ChainsTests.play(&e, days: 1) }
        try XCTSkipUnless(e.state.company(id)?.status == .open, "the bakery did not open")
        if let channel { setChannel(&e, id, channel) }
        return id
    }

    private func setChannel(_ e: inout GameEngine, _ id: Int, _ channel: SalesChannel) {
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].set("chan", channel.rawValue) } }
    }

    private func firstOffer(_ e: inout GameEngine, _ id: Int, weeks: Int, decline: Bool = false, where match: (Message) -> Bool = { _ in true }) -> Message? {
        for _ in 0..<(weeks * 7) {
            ChainsTests.play(&e, days: 1)
            for m in e.openDecisions where m.actionID == VolumeContracts.action && m.companyID == id {
                if match(m) { return m }
                if decline { e.answer(messageID: m.id, option: 1) }
            }
        }
        return nil
    }

    func testAnOldCompanyReadsAsPrivateButNothingIsChosen() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "bakery")
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.channel, .consumers)
        XCTAssertNil(co.chosenChannel)
    }

    func testOnlyTradesThatCanSupplyOfferBusinessCustomers() {
        XCTAssertEqual(SalesChannel.options(tradeID: "cafe"), [.consumers])
        XCTAssertEqual(SalesChannel.options(tradeID: "bakery"), [.consumers, .business])
        for trade in SupplyMarketCatalogue.supplierTrades { XCTAssertTrue(SalesChannel.canChoose(.business, tradeID: trade), trade) }
    }

    func testTheChoiceIsMadeAtStartAndNeverChangedAfterwards() throws {
        var e = try ChainsTests.engine()
        guard case .success(let out) = e.startCompanyChoosingPremises(tradeID: "bakery", cityID: e.state.player.cityID, size: 1, name: nil, pick: nil, fundWith: 20_000_000,
                                                                      choices: SetupChoices(channel: .business)) else { return XCTFail("start") }
        XCTAssertEqual(e.state.company(out.companyID)?.chosenChannel, .business)
        guard case .refused = e.chooseSalesChannel(companyID: out.companyID, channel: .consumers) else { return XCTFail("a chosen channel cannot change") }
        guard case .refused = e.chooseSalesChannel(companyID: out.companyID, channel: .business) else { return XCTFail("a chosen channel cannot be chosen again") }
        XCTAssertEqual(e.state.company(out.companyID)?.chosenChannel, .business)
    }

    func testAStartWithoutAChoiceStaysUnchosenAndCannotChooseLater() throws {
        var e = try ChainsTests.engine()
        guard case .success(let out) = e.startCompanyChoosingPremises(tradeID: "bakery", cityID: e.state.player.cityID, size: 1, name: nil, pick: nil, fundWith: 20_000_000) else { return XCTFail("start") }
        XCTAssertNil(e.state.company(out.companyID)?.chosenChannel)
        e.update { s, _, _ in if let i = s.companyIndex(out.companyID) { s.companies[i].status = .open } }
        guard case .refused = e.chooseSalesChannel(companyID: out.companyID, channel: .business) else { return XCTFail("it is chosen once, at the start") }
    }

    func testABusinessChoiceIsRefusedForATradeWithNothingToSupply() throws {
        var e = try ChainsTests.engine()
        let before = e.state.companies.count
        guard case .failure = e.startCompanyChoosingPremises(tradeID: "cafe", cityID: e.state.player.cityID, size: 1, name: nil, pick: nil, fundWith: 20_000_000,
                                                             choices: SetupChoices(channel: .business)) else { return XCTFail("a cafe cannot sell to business customers") }
        XCTAssertEqual(e.state.companies.count, before)
        guard case .success(let out) = e.startCompanyChoosingPremises(tradeID: "cafe", cityID: e.state.player.cityID, size: 1, name: nil, pick: nil, fundWith: 20_000_000,
                                                                      choices: SetupChoices(channel: .consumers)) else { return XCTFail("start") }
        XCTAssertEqual(e.state.company(out.companyID)?.chosenChannel, .consumers)
    }

    func testANewGameCarriesTheChoiceOfItsFirstCompany() throws {
        let e = try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 7, story: .fresh, tradeID: "bakery", companyName: "C", channel: .business)
        XCTAssertEqual(e.state.companies.first?.chosenChannel, .business)
        let cafe = try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 7, story: .fresh, tradeID: "cafe", companyName: "C", channel: .business)
        XCTAssertNil(cafe.state.companies.first?.chosenChannel)
    }

    func testPrivateCustomersMeanMoreDemandAtLowerPricesAndBusinessTheOpposite() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "bakery")
        let bd = try XCTUnwrap(e.data.catalog["bakery"])
        func read(_ channel: SalesChannel?) throws -> (price: Double, demand: Double?) {
            var s = e.state
            if let i = s.companyIndex(id) {
                if let channel { s.companies[i].set("chan", channel.rawValue) } else { s.companies[i].raw["chan"] = nil }
            }
            let w = World(state: s, data: e.data)
            let co = try XCTUnwrap(s.company(id))
            return (Pricing.ticketMultiplier(co, bd, w), DemandModel.compute(co, bd, w).part("channel"))
        }
        let none = try read(nil), consumers = try read(.consumers), business = try read(.business)
        XCTAssertNil(none.demand)
        XCTAssertGreaterThan(try XCTUnwrap(consumers.demand), 1)
        XCTAssertLessThan(consumers.price, none.price)
        XCTAssertGreaterThan(consumers.price, none.price * 0.9)
        XCTAssertGreaterThan(business.price, none.price)
        XCTAssertLessThan(try XCTUnwrap(business.demand), 1)
    }

    func testBusinessDemandIsLumpyFromWeekToWeekAndRepeatable() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "bakery")
        setChannel(&e, id, .business)
        let bd = try XCTUnwrap(e.data.catalog["bakery"])
        func factor(week: Int) throws -> Double {
            var s = e.state
            s.week = week
            let co = try XCTUnwrap(s.company(id))
            return try XCTUnwrap(DemandModel.compute(co, bd, World(state: s, data: e.data)).part("channel"))
        }
        let weeks = (10..<30).map { try? factor(week: $0) }.compactMap { $0 }
        XCTAssertEqual(weeks.count, 20)
        XCTAssertGreaterThan(Set(weeks).count, 10)
        XCTAssertTrue(weeks.allSatisfy { $0 > 0.2 && $0 < 0.8 })
        XCTAssertEqual(try factor(week: 12), try factor(week: 12))
    }

    func testBusinessOffersArriveAsADecisionAndAnAcceptedOneRuns() throws {
        var e = try ChainsTests.engine()
        let id = try openBakery(&e, channel: .business)
        let offer = try XCTUnwrap(firstOffer(&e, id, weeks: 60, decline: true), "no contract offer in sixty weeks")
        XCTAssertEqual(offer.options.count, 2)
        XCTAssertTrue(offer.body.contains("units a week"), offer.body)
        XCTAssertFalse(offer.value("data")["pl"].bool)
        XCTAssertTrue(VolumeContracts.contracts(try XCTUnwrap(e.state.company(id))).isEmpty)
        e.answer(messageID: offer.id, option: 0)
        let list = VolumeContracts.contracts(try XCTUnwrap(e.state.company(id)))
        XCTAssertEqual(list.count, 1)
        XCTAssertGreaterThan(list[0].units, 0)
        XCTAssertFalse(list[0].buyerIsPlayer)
        let rev0 = try XCTUnwrap(e.state.company(id)).books.total["rev"] ?? 0
        ChainsTests.play(&e, days: 14)
        XCTAssertGreaterThan(try XCTUnwrap(e.state.company(id)).books.total["rev"] ?? 0, rev0)
    }

    func testADeclinedOfferSignsNothing() throws {
        var e = try ChainsTests.engine()
        let id = try openBakery(&e, channel: .business)
        let offer = try XCTUnwrap(firstOffer(&e, id, weeks: 60))
        e.answer(messageID: offer.id, option: 1)
        XCTAssertTrue(VolumeContracts.contracts(try XCTUnwrap(e.state.company(id))).isEmpty)
    }

    func testPrivateCompaniesNeverGetContractOffers() throws {
        var e = try ChainsTests.engine()
        let id = try openBakery(&e, channel: .consumers)
        XCTAssertNil(firstOffer(&e, id, weeks: 40, decline: true))
    }

    func testPlayersPostDemandAndItComesBackAsAnOfferFromAPlayer() throws {
        var e = try ChainsTests.engine()
        let id = try openBakery(&e, channel: .business)
        e.savePlayerDemand((0..<40).map { DemandPost(id: "P\($0)", ownerName: "Ann", companyName: "Ann Foods", lineID: "goods", units: 12, weeks: 8) })
        XCTAssertEqual(e.playerDemandPosts.count, 40)
        let offer = try XCTUnwrap(firstOffer(&e, id, weeks: 80, decline: true, where: { $0.value("data")["pl"].bool }), "no offer from a player")
        XCTAssertTrue(offer.title.contains("Ann Foods"), offer.title)
        XCTAssertTrue(offer.body.contains("player"), offer.body)
        e.answer(messageID: offer.id, option: 0)
        let signed = try XCTUnwrap(VolumeContracts.contracts(try XCTUnwrap(e.state.company(id))).first { $0.customer == "Ann Foods" })
        XCTAssertTrue(signed.buyerIsPlayer)
        XCTAssertGreaterThan(signed.units, 0)
        XCTAssertLessThanOrEqual(signed.units, 12)
    }

    func testAPostForSomethingTheCompanyDoesNotMakeIsNeverOffered() throws {
        var e = try ChainsTests.engine()
        let id = try openBakery(&e, channel: .business)
        e.savePlayerDemand((0..<40).map { DemandPost(id: "P\($0)", ownerName: "Ann", companyName: "Ann Fuel", lineID: "fuel", units: 12, weeks: 8) })
        XCTAssertNil(firstOffer(&e, id, weeks: 60, decline: true, where: { $0.value("data")["pl"].bool }))
    }

    func testShortWeeksWarnTheSupplierAndOnlyBusinessSellersLoseTheirName() throws {
        func shortWeeks(_ channel: SalesChannel) throws -> (warnings: Double, lost: Double) {
            var e = try ChainsTests.engine()
            let id = try openBakery(&e, channel: channel)
            let terms = VolumeContracts.Terms(name: "Supply contract", customer: "Big Buyer", units: 10, discount: 0, weeks: 30, paymentWeeks: 0, reliability: 0.9)
            XCTAssertNotNil(e.signContract(companyID: id, terms: terms))
            let bd = try XCTUnwrap(e.data.catalog["bakery"])
            let before = try XCTUnwrap(e.state.company(id)).reputation
            for _ in 0..<2 {
                e.update { s, d, _ in
                    guard let i = s.companyIndex(id) else { return }
                    var lw = s.companies[i].value("lastW")
                    lw["units"] = .number(1)
                    lw["D"] = .number(100)
                    s.companies[i].set("lastW", lw)
                    VolumeContracts.serviceAndRisk(&s, i, bd, data: d)
                }
            }
            let co = try XCTUnwrap(e.state.company(id))
            return (try XCTUnwrap(VolumeContracts.contracts(co).first).warnings, before - co.reputation)
        }
        let business = try shortWeeks(.business), consumers = try shortWeeks(.consumers)
        XCTAssertEqual(business.warnings, 2)
        XCTAssertEqual(consumers.warnings, 2)
        XCTAssertEqual(business.lost, 1, accuracy: 0.001)
        XCTAssertEqual(consumers.lost, 0, accuracy: 0.001)
    }

    func testAnIdleBusinessCompanyDoesNotBeatAPrivateOneByMuchAndPrivateStaysNearTheOldEconomy() throws {
        func revenue(_ channel: SalesChannel?) throws -> Double {
            var e = try ChainsTests.engine(seed: 23)
            let id = try openBakery(&e, channel: channel)
            for _ in 0..<(40 * 7) {
                ChainsTests.play(&e, days: 1)
                for m in e.openDecisions where m.actionID == VolumeContracts.action { e.answer(messageID: m.id, option: 1) }
            }
            return try XCTUnwrap(e.state.company(id)).books.total["rev"] ?? 0
        }
        let old = try revenue(nil), consumers = try revenue(.consumers), business = try revenue(.business)
        XCTAssertGreaterThan(old, 0)
        XCTAssertEqual(consumers / old, 1, accuracy: 0.12)
        XCTAssertLessThan(business, consumers * 1.25)
    }
}
