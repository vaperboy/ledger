import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Events
import Simulation

final class WorldAliveTests: XCTestCase {
    private func listing(_ id: String, trade: String = "farm", price: Int = 1, friend: Bool = false, companyID: Int? = nil) -> SupplyListing {
        SupplyListing(id: id, ownerID: "owner-\(id)", ownerName: "Name \(id)", profileCode: "P-\(id)", companyName: "Co \(id)", companyID: companyID, tradeID: trade, tradeName: trade.capitalized,
                      city: "Leeds", region: "North", lineID: "goods", lineName: "Stock", priceTier: price, qualityTier: 1, capacityPerWeek: 300, leadDays: 2, minOrder: 10, termsDays: 14,
                      linkKey: "key-\(id)", record: DeliveryRecord(weeksTrading: 20, ordersTotal: 40, ordersOnTime: 39, unitsPromised: 800, unitsDelivered: 790, cleanWeeks: 12, lifetimeUnits: 790),
                      isFriend: friend, country: "UK")
    }

    private func engine(trade: String = "grocery") throws -> (GameEngine, Int) {
        var e = try ChainsTests.engine("UK", seed: 777)
        let id = ChainsTests.start(&e, trade)
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].status = .open
            s.companies[i].openedWeek = s.week - 50
            s.companies[i].set("lastW", .object(["cogs": .number(4000), "units": .number(100), "cap": .number(200)]))
        }
        return (e, id)
    }

    private func contract(_ id: String, buyer: Int, listing l: String) -> SupplyContract {
        SupplyContract(id: id, buyerCompanyID: buyer, lineID: "goods", listingID: l, supplierOwnerID: "owner-\(l)", supplierName: "Name \(l)", unitsPerWeek: 20, startDay: 0)
    }

    private func messages(_ e: GameEngine, _ id: Int, containing text: String) -> [Message] {
        e.state.inbox.filter { $0.companyID == id && $0.title.contains(text) }
    }

    func testAFriendListingIsCheaperAndComesFirst() {
        let plain = listing("a"), friend = listing("b", friend: true)
        XCTAssertEqual(friend.priceFactor, plain.priceFactor * (1 - FriendTies.discount), accuracy: 1e-12)
        XCTAssertEqual(FriendTies.tag(friend: true), "Friend, 3% off")
        XCTAssertNil(FriendTies.tag(friend: false))
        var proven = plain
        proven.record.cleanWeeks = 30
        var unproven = friend
        unproven.record = DeliveryRecord()
        let known = SupplyChoice.wellKnown([proven, unproven], units: 20, buyerLinkKeys: [], today: 0)
        XCTAssertEqual(known.first?.id, "b", "a friend leads the well-known list")
    }

    func testFriendsAreDrawnMoreOftenAndTheDrawIsRepeatable() {
        let pool = [listing("a"), listing("b", friend: true)]
        func run() -> [String] { (0..<400).compactMap { SupplyChoice.draw(pool, seed: "k\($0)")?.id } }
        let first = run()
        XCTAssertEqual(first, run())
        let friends = first.filter { $0 == "b" }.count
        XCTAssertGreaterThan(friends, first.count - friends)
        XCTAssertGreaterThan(friends, first.count / 2 + 20)
    }

    func testASignedFriendContractKeepsTheDiscount() throws {
        var (e, id) = try engine()
        XCTAssertTrue(e.signPlayerSupplier(contract: contract("C1", buyer: id, listing: "a"), listing: listing("a", price: 1), weeklyMarketSpend: 100_000))
        let plain = try XCTUnwrap(e.goodsCostFactor(companyID: id))
        XCTAssertEqual(PlayerSupply.contracts(e.state).first?.friend, false)
        XCTAssertTrue(e.signPlayerSupplier(contract: contract("C2", buyer: id, listing: "b"), listing: listing("b", price: 1, friend: true), weeklyMarketSpend: 100_000))
        let friend = try XCTUnwrap(e.goodsCostFactor(companyID: id))
        XCTAssertLessThan(friend, plain)
        XCTAssertEqual(PlayerSupply.contracts(e.state).first?.friend, true)
        let saved = PlayerSupply.contracts(e.state)
        XCTAssertEqual(saved.first?.friend, true, "the flag survives the save")
        XCTAssertEqual(e.playerSupplyContracts.count, 1)
    }

    func testSettlingWithAFriendTakesTheLoyaltyDiscountOnBothSides() throws {
        var e = try ChainsTests.engine("UK", seed: 31)
        let seller = ChainsTests.start(&e, "bakery"), buyer = ChainsTests.start(&e, "grocery")
        var plain: Double?, friend: Double?
        e.update { s, _, _ in
            for id in [seller, buyer] { if let i = s.companyIndex(id) { s.companies[i].status = .open } }
            plain = SupplyMarketBooks.settleSupply(&s, supplierCompanyID: seller, buyerCompanyID: buyer, units: 10, unitPrice: 100, unitCost: 40)
            friend = SupplyMarketBooks.settleSupply(&s, supplierCompanyID: seller, buyerCompanyID: buyer, units: 10, unitPrice: 100, unitCost: 40, friend: true)
        }
        XCTAssertEqual(plain ?? 0, 1000, accuracy: 1e-6)
        XCTAssertEqual(friend ?? 0, 970, accuracy: 1e-6)
    }

    func testSupplierNewsRollIsSeededAndBounded() throws {
        let (e, id) = try engine()
        let s = e.state, co = try XCTUnwrap(s.company(id)), bd = try XCTUnwrap(e.data.catalog[co.type])
        let sources = SupplyNews.sources(s, co, bd, data: e.data)
        let goods = try XCTUnwrap(sources.first { $0.goods })
        XCTAssertTrue(SupplyPlayers.isSupplierID(goods.vendorID), "the goods supplier is a player company")
        XCTAssertNil(SupplyNews.roll(s, co, sources: sources, chance: 0))
        XCTAssertNil(SupplyNews.roll(s, co, sources: [], chance: 1))
        let a = try XCTUnwrap(SupplyNews.roll(s, co, sources: sources, chance: 1))
        XCTAssertEqual(a, SupplyNews.roll(s, co, sources: sources, chance: 1))
        for week in 100..<160 {
            var t = s
            t.week = week
            guard let r = SupplyNews.roll(t, co, sources: sources, chance: 1) else { return XCTFail("a certain roll always lands") }
            XCTAssertTrue((0.03...0.081).contains(r.rise), "\(r.kind) \(r.rise)")
            XCTAssertTrue((2...10).contains(r.weeks), "\(r.kind) \(r.weeks)")
        }
    }

    func testAPriceRiseTellsTheOwnerAndMovesTheCost() throws {
        var (e, id) = try engine()
        e.update { s, d, _ in
            guard let i = s.companyIndex(id), let bd = d.catalog[s.companies[i].type],
                  let src = SupplyNews.sources(s, s.companies[i], bd, data: d).first else { return XCTFail("no supplier") }
            SupplyNews.apply(&s, companyIndex: i, SupplyNews.Roll(source: src, kind: .price, rise: 0.05, weeks: 8), data: d)
        }
        let co = try XCTUnwrap(e.state.company(id))
        let mod = co.value("mods").array.first { $0["k"].string == "cogsup" }
        XCTAssertEqual(mod?["m"].double ?? 0, 1.05, accuracy: 1e-9)
        XCTAssertEqual(mod?["w"].double, 8)
        let note = messages(e, id, containing: "raised its prices")
        XCTAssertEqual(note.count, 1)
        XCTAssertTrue(note.first?.body.contains("5%") == true)
    }

    func testRunningOutOfCapacityIsAShortLivedCostRise() throws {
        var (e, id) = try engine()
        e.update { s, d, _ in
            guard let i = s.companyIndex(id), let bd = d.catalog[s.companies[i].type],
                  let src = SupplyNews.sources(s, s.companies[i], bd, data: d).first else { return XCTFail("no supplier") }
            SupplyNews.apply(&s, companyIndex: i, SupplyNews.Roll(source: src, kind: .capacity, rise: 0.06, weeks: 2), data: d)
        }
        XCTAssertEqual(messages(e, id, containing: "ran out of capacity").count, 1)
        let mod = try XCTUnwrap(e.state.company(id)).value("mods").array.first { $0["k"].string == "cogsup" }
        XCTAssertEqual(mod?["w"].double, 2)
    }

    func testAnEndedDealDropsTheSupplierForGoodAndTheCostFollows() throws {
        var (e, id) = try engine()
        var gone = ""
        e.update { s, d, _ in
            guard let i = s.companyIndex(id), let bd = d.catalog[s.companies[i].type],
                  let src = SupplyNews.sources(s, s.companies[i], bd, data: d).first(where: { $0.goods }) else { return XCTFail("no supplier") }
            gone = src.vendorID
            Suppliers.chooseGoodsVendor(&s, companyID: id, vendorID: src.vendorID)
            XCTAssertEqual(Suppliers.goodsVendor(s, company: s.companies[i], data: d)?.id, gone)
            SupplyNews.apply(&s, companyIndex: i, SupplyNews.Roll(source: src, kind: .ended, rise: 0.04, weeks: 5), data: d)
        }
        e.update { s, d, _ in
            guard let i = s.companyIndex(id) else { return }
            XCTAssertEqual(s.companies[i].value("src")["v"].string, "auto")
            XCTAssertTrue(Sourcing.lapsed(s.companies[i], vendorID: gone, week: s.week))
            XCTAssertFalse(Sourcing.lapsed(s.companies[i], vendorID: gone, week: s.week + 40))
            XCTAssertNotEqual(Suppliers.goodsVendor(s, company: s.companies[i], data: d)?.id, gone, "the supplier that ended is not picked again")
            XCTAssertNotNil(s.companies[i].value("mods").array.first { $0["k"].string == "cogsup" })
        }
        XCTAssertEqual(messages(e, id, containing: "ended your supply deal").count, 1)
    }

    func testTheWeeklyHookIsQuietAndRepeatable() throws {
        func run() throws -> [String] {
            var (e, id) = try engine()
            e.update { s, d, _ in
                guard let i = s.companyIndex(id) else { return }
                for week in 100..<400 {
                    s.week = week
                    SupplyNews.spawn(&s, companyIndex: i, data: d)
                }
            }
            return e.state.inbox.filter { $0.companyID == id }.map { "\($0.week):\($0.title)" }
        }
        let first = try run()
        XCTAssertEqual(first, try run())
        XCTAssertLessThan(first.count, 40, "supplier news is an occasional event, not weekly noise")
    }

    func testASupplierHearsWhenItsListingFillsAndWhenBuyersLeave() throws {
        var (e, id) = try engine(trade: "bakery")
        var l = listing("M1", trade: "bakery", companyID: id)
        l.committedUnits = 100
        e.savePlayerListings([l], orders: [:])
        let before = e.state.inbox.count
        e.update { s, _, _ in if let i = s.companyIndex(id) { SupplyNews.supplierSide(&s, companyIndex: i) } }
        XCTAssertEqual(e.state.inbox.count, before, "the first look only sets the baseline")
        l.committedUnits = 300
        e.savePlayerListings([l], orders: [:])
        e.update { s, _, _ in if let i = s.companyIndex(id) { SupplyNews.supplierSide(&s, companyIndex: i) } }
        XCTAssertEqual(messages(e, id, containing: "fully booked").count, 1)
        e.update { s, _, _ in if let i = s.companyIndex(id) { SupplyNews.supplierSide(&s, companyIndex: i) } }
        XCTAssertEqual(messages(e, id, containing: "fully booked").count, 1, "once, not every week")
        l.committedUnits = 120
        e.savePlayerListings([l], orders: [:])
        e.update { s, _, _ in if let i = s.companyIndex(id) { SupplyNews.supplierSide(&s, companyIndex: i) } }
        XCTAssertEqual(messages(e, id, containing: "Buyers cut back").count, 1)
    }

    private func market(_ e: inout GameEngine, _ id: Int, rivals: Int, strength: Double = 1, mine: (inout Company) -> Void = { _ in }) {
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].quality = 45
            s.companies[i].awareness = 25
            s.companies[i].priceLevel = 0
            mine(&s.companies[i])
            let key = s.companies[i].type + "|" + s.companies[i].cityID
            let riv: [JSONValue] = (0..<rivals).map { n -> JSONValue in
                .object(["id": .number(Double(9_100_000 + n)), "name": .string("Rival \(n)"), "owner": .string("Owner \(n)"), "size": 1, "rel": 40,
                         "pm16": .number(strength), "ig16": 1, "st": "cheap", "fort": 1])
            }
            s.rest["mk"] = .object([key: .object(["n": .number(Double(max(1, rivals))), "pi": 1, "str": 0.5, "riv": .array(riv)])])
        }
    }

    private func share(_ e: GameEngine, _ id: Int) throws -> CityShare.Pool? {
        let s = e.state, co = try XCTUnwrap(s.company(id))
        return CityShare.pool(co, World(state: s, data: e.data))
    }

    func testACityWithoutRivalsLeavesDemandAlone() throws {
        var (e, id) = try engine(trade: "cafe")
        market(&e, id, rivals: 0)
        XCTAssertNil(try share(e, id))
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(CityShare.factor(co, World(state: e.state, data: e.data)), 1)
    }

    func testMoreCompetitorsLowerTheShareAndAFairFieldIsNeutral() throws {
        var (e, id) = try engine(trade: "cafe")
        market(&e, id, rivals: 1)
        let few = try XCTUnwrap(try share(e, id))
        market(&e, id, rivals: 5)
        let many = try XCTUnwrap(try share(e, id))
        XCTAssertEqual(few.rivals, 1)
        XCTAssertEqual(many.rivals, 5)
        XCTAssertGreaterThan(few.share, many.share)
        XCTAssertGreaterThan(few.factor, many.factor)
        market(&e, id, rivals: 3)
        XCTAssertEqual(try XCTUnwrap(try share(e, id)).factor, 1, accuracy: 0.03, "an average business in an average field is left alone")
    }

    func testBetterPriceQualityAndMarketingWinCustomers() throws {
        var (e, id) = try engine(trade: "cafe")
        market(&e, id, rivals: 3)
        let base = try XCTUnwrap(try share(e, id)).factor
        market(&e, id, rivals: 3) { $0.priceLevel = -2 }
        let cheap = try XCTUnwrap(try share(e, id)).factor
        market(&e, id, rivals: 3) { $0.priceLevel = 2 }
        let dear = try XCTUnwrap(try share(e, id)).factor
        market(&e, id, rivals: 3) { $0.quality = 90 }
        let good = try XCTUnwrap(try share(e, id)).factor
        market(&e, id, rivals: 3) { $0.awareness = 90 }
        let known = try XCTUnwrap(try share(e, id)).factor
        XCTAssertGreaterThan(cheap, base)
        XCTAssertLessThan(dear, base)
        XCTAssertGreaterThan(good, base)
        XCTAssertGreaterThan(known, base)
    }

    func testTheEffectIsCappedSoNoBusinessIsWipedOutOrRunsAway() throws {
        var (e, id) = try engine(trade: "cafe")
        let cap = e.data.balance.cityMarket.shareCap
        XCTAssertLessThan(cap, 0.2)
        market(&e, id, rivals: 1, strength: 1.5) { $0.priceLevel = -3; $0.quality = 100; $0.awareness = 100 }
        XCTAssertLessThanOrEqual(try XCTUnwrap(try share(e, id)).factor, 1 + cap + 1e-12)
        market(&e, id, rivals: 6, strength: 0.6) { $0.priceLevel = 3; $0.quality = 0; $0.awareness = 0 }
        let worst = try XCTUnwrap(try share(e, id)).factor
        XCTAssertGreaterThanOrEqual(worst, 1 - cap - 1e-12)
        XCTAssertLessThan(worst, 1)
    }

    func testTheCityShareReachesTheDemandModelAndCountsOwnOutlets() throws {
        var e = try ChainsTests.engine("UK", seed: 777)
        let first = ChainsTests.start(&e, "cafe"), second = ChainsTests.start(&e, "cafe")
        e.update { s, _, _ in for id in [first, second] { if let i = s.companyIndex(id) { s.companies[i].status = .open } } }
        market(&e, first, rivals: 2)
        e.update { s, _, _ in
            guard let i = s.companyIndex(second), let j = s.companyIndex(first) else { return }
            s.companies[i].cityID = s.companies[j].cityID
            s.companies[i].countryCode = s.companies[j].countryCode
        }
        let pool = try XCTUnwrap(try share(e, first))
        XCTAssertEqual(pool.rivals, 2)
        XCTAssertEqual(pool.ownOutlets, 1, "the player's other outlet in the city shares the same customers")
        let co = try XCTUnwrap(e.state.company(first)), bd = try XCTUnwrap(e.data.catalog[co.type])
        let r = DemandModel.compute(co, bd, World(state: e.state, data: e.data))
        XCTAssertEqual(r.part("city share") ?? 1, pool.factor, accuracy: 1e-12)
    }

    private func newState() throws -> GameEngine { try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5) }

    func testTheRecapIsEmptyUntilSomethingHappens() throws {
        let e = try newState()
        XCTAssertNil(e.worldRecap(friends: []))
    }

    func testTheRecapPicksTheBiggestPriceMoveARivalAndAFriend() throws {
        var e = try newState()
        e.update { s, _, _ in
            s.rest["xch"] = .object(["i": .object([
                "A": .object(["n": "Alpha", "k": "srv", "c": 110, "pc": 100]),
                "B": .object(["n": "Beta", "k": "com", "c": 97, "pc": 100]),
                "C": .object(["n": "Gamma", "k": "srv", "c": 101, "pc": 100]),
            ])])
            MarketEvents.log(&s, .competitorLaunch, title: "Brook Cafe opens a new store", detail: "Next to My Cafe in Leeds.", companyID: nil, tone: "bad")
        }
        let now = Date().timeIntervalSince1970
        let friends = [WorldRecapFriend(id: "f1", kind: "joined", text: "Ana joined Ledger.", at: now - 3600),
                       WorldRecapFriend(id: "f2", kind: "levelUp", text: "Ben reached level 7.", at: now - 86_400 * 2),
                       WorldRecapFriend(id: "f3", kind: "levelUp", text: "Old news.", at: now - 86_400 * 30)]
        let card = try XCTUnwrap(e.worldRecap(friends: friends, now: Date(timeIntervalSince1970: now)))
        XCTAssertEqual(card.lines.map { $0.id }, ["price", "rival", "friend"])
        XCTAssertEqual(card.lines[0].text, "Alpha rose 10% on the exchange.")
        XCTAssertEqual(card.lines[1].text, "A rival opened a new store. Next to My Cafe in Leeds.")
        XCTAssertFalse(card.lines.contains { $0.text.contains("Brook") }, "a rival's name is never shown, it can be another player")
        XCTAssertEqual(card.lines[2].text, "Ben reached level 7.", "a level-up beats a newer join, and old news is left out")
        XCTAssertEqual(card.home, .news)
    }

    func testTheRecapIsOneDismissableCardPerWeekAndOnlyRivalsPointToStats() throws {
        var e = try newState()
        e.update { s, _, _ in
            MarketEvents.log(&s, .competitorLaunch, title: "Brook Cafe opens a new store", detail: "Next to My Cafe in Leeds.", companyID: nil, tone: "bad")
        }
        let card = try XCTUnwrap(e.worldRecap(friends: []))
        XCTAssertEqual(card.lines.count, 1)
        XCTAssertEqual(card.home, .stats)
        e.dismissWorldRecap()
        XCTAssertNil(e.worldRecap(friends: []), "dismissed for this week")
        XCTAssertEqual(WorldRecap.dismissedWeek(e.state), e.state.week)
        e.update { s, _, _ in
            s.week += 1
            MarketEvents.log(&s, .competitorLaunch, title: "Dale Cafe opens a new store", detail: "Next to My Cafe in Leeds.", companyID: nil, tone: "bad")
        }
        XCTAssertNotNil(e.worldRecap(friends: []), "a new week brings a new card")
    }

    func testFriendNewsOutsideTheWindowOrEmptyIsIgnored() {
        let now = 1_000_000.0
        XCTAssertNil(WorldRecap.friendLine([], now: now))
        XCTAssertNil(WorldRecap.friendLine([WorldRecapFriend(id: "a", kind: "levelUp", text: "Late.", at: now - 86_400 * 8)], now: now))
        XCTAssertNil(WorldRecap.friendLine([WorldRecapFriend(id: "a", kind: "levelUp", text: "", at: now)], now: now))
        XCTAssertEqual(WorldRecap.friendLine([WorldRecapFriend(id: "a", kind: "tradeMilestone", text: "A.", at: now - 10),
                                              WorldRecapFriend(id: "b", kind: "tradeMilestone", text: "B.", at: now - 5)], now: now)?.text, "B.")
    }
}
