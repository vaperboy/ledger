import XCTest
@testable import Simulation

final class AuctionRulesTests: XCTestCase {
    private let t0: Double = 1_000_000
    private let me = "me"

    private func book(with a: Auction? = nil) -> AuctionBook {
        var b = AuctionBook(me: me)
        if let a { b.auctions.append(a) }
        return b
    }

    private func auction(seller: String = "seller", start: Int = 100, reserve: Int? = nil, buyNow: Int? = nil, hours: AuctionDuration = .oneHour) -> Auction {
        Auction(id: "A1", item: ArtifactItem(defID: "abacus", serial: 14), seller: seller, startPrice: start, reserve: reserve, buyNow: buyNow,
                startsAt: t0, endsAt: t0 + hours.seconds, duration: hours)
    }

    func testIncrementsGrowWithThePriceAtAnyScale() {
        XCTAssertEqual(AuctionRules.increment(at: 20), 1)
        XCTAssertEqual(AuctionRules.increment(at: 100), 5)
        XCTAssertEqual(AuctionRules.increment(at: 500), 20)
        XCTAssertEqual(AuctionRules.increment(at: 1_000), 50)
        XCTAssertEqual(AuctionRules.increment(at: 5_000), 200)
        XCTAssertEqual(AuctionRules.increment(at: 50_000), 2_000)
        XCTAssertEqual(AuctionRules.increment(at: 2_000_000), 100_000)
        for price in [3, 40, 999, 12_345, 777_777] {
            let step = AuctionRules.increment(at: price)
            XCTAssertGreaterThanOrEqual(step, 1)
            XCTAssertLessThanOrEqual(step, max(1, price / 10), "a step stays a small share of the price")
        }
        var a = auction()
        XCTAssertEqual(AuctionRules.minimumBid(a), 100, "the first bid may be the start price")
        a.bids.append(AuctionBid(bidder: "x", amount: 100, at: t0 + 1))
        XCTAssertEqual(AuctionRules.minimumBid(a), 105)
    }

    func testFeeIsTenPercentWithAMinimumOfOne() {
        XCTAssertEqual(AuctionRules.fee(forSale: 1_000), 100)
        XCTAssertEqual(AuctionRules.fee(forSale: 15), 1)
        XCTAssertEqual(AuctionRules.fee(forSale: 5), 1)
        XCTAssertEqual(AuctionRules.proceeds(forSale: 1_000), 900)
        XCTAssertEqual(AuctionRules.fee(forSale: 0), 0)
    }

    func testAntiSnipeExtendsOnlyInTheLastTwoMinutes() {
        let end = t0 + 3_600
        XCTAssertFalse(AuctionRules.extendedEnd(endsAt: end, extensions: 0, bidAt: end - 121).extended)
        let e = AuctionRules.extendedEnd(endsAt: end, extensions: 0, bidAt: end - 30)
        XCTAssertTrue(e.extended)
        XCTAssertEqual(e.end, end + AuctionRules.bidExtension)
        XCTAssertFalse(AuctionRules.extendedEnd(endsAt: end, extensions: AuctionRules.maxExtensions, bidAt: end - 30).extended, "capped")
    }

    func testALeadingBidSetsCashAsideAndFreesItWhenBeaten() throws {
        var b = book(with: auction())
        _ = try b.place("A1", bidder: me, amount: 100, now: t0 + 10, cash: 500)
        XCTAssertEqual(b.held, 100)
        XCTAssertEqual(b.available(cash: 500), 400)
        _ = try b.place("A1", bidder: "rival", amount: 110, now: t0 + 20)
        XCTAssertEqual(b.held, 0, "free again as soon as the bid is beaten")
        XCTAssertEqual(b.available(cash: 500), 500)
        _ = try b.place("A1", bidder: me, amount: 120, now: t0 + 30, cash: 500)
        XCTAssertEqual(b.held, 120)
    }

    func testHeldCashCountsEveryLeadingBidAndNoEndedOne() throws {
        var b = book(with: auction())
        b.auctions.append(Auction(id: "A2", item: ArtifactItem(defID: "map", serial: 2), seller: "s2", startPrice: 50, reserve: nil,
                                  startsAt: t0, endsAt: t0 + 7_200, duration: .sixHours))
        _ = try b.place("A1", bidder: me, amount: 100, now: t0 + 10, cash: 500)
        _ = try b.place("A2", bidder: me, amount: 50, now: t0 + 10, cash: 500)
        XCTAssertEqual(b.held, 150)
        XCTAssertThrowsError(try b.place("A1", bidder: "x", amount: 120, now: t0 + 4_000)) { XCTAssertEqual($0 as? AuctionError, .notLive) }
        var c = Cabinet()
        _ = b.settleDue(now: t0 + 3_601, cash: 500, cabinet: &c)
        XCTAssertEqual(b.held, 50, "the ended auction no longer holds anything")
    }

    func testBidRules() throws {
        var b = book(with: auction(reserve: 150))
        XCTAssertThrowsError(try b.place("A1", bidder: me, amount: 100, now: t0, cash: 50)) { XCTAssertEqual($0 as? AuctionError, .notEnoughCash(missing: 50)) }
        XCTAssertThrowsError(try b.place("A1", bidder: me, amount: 60, now: t0, cash: 500)) { XCTAssertEqual($0 as? AuctionError, .tooLow(minimum: 100)) }
        XCTAssertThrowsError(try b.place("A1", bidder: "seller", amount: 100, now: t0)) { XCTAssertEqual($0 as? AuctionError, .sellerCannotBid) }
        _ = try b.place("A1", bidder: "rival", amount: 100, now: t0)
        XCTAssertThrowsError(try b.place("A1", bidder: "rival", amount: 200, now: t0)) { XCTAssertEqual($0 as? AuctionError, .alreadyLeading) }
        XCTAssertThrowsError(try b.place("A1", bidder: "rival2", amount: 200, now: t0 + 4_000)) { XCTAssertEqual($0 as? AuctionError, .notLive) }
        XCTAssertEqual(b.held, 0)
    }

    func testABidWithOtherBidsHeldNeedsTheRest() throws {
        var b = book(with: auction())
        b.auctions.append(Auction(id: "A2", item: ArtifactItem(defID: "map", serial: 2), seller: "s2", startPrice: 300, reserve: nil,
                                  startsAt: t0, endsAt: t0 + 3_600, duration: .oneHour))
        _ = try b.place("A2", bidder: me, amount: 300, now: t0, cash: 400)
        XCTAssertThrowsError(try b.place("A1", bidder: me, amount: 150, now: t0, cash: 400)) { XCTAssertEqual($0 as? AuctionError, .notEnoughCash(missing: 50)) }
        _ = try b.place("A1", bidder: me, amount: 100, now: t0, cash: 400)
    }

    func testBidInTheLastMinutesExtendsTheAuction() throws {
        var b = book(with: auction())
        let end = t0 + 3_600
        let r = try b.place("A1", bidder: me, amount: 100, now: end - 60, cash: 1_000)
        XCTAssertTrue(r.extended)
        XCTAssertEqual(b.auctions[0].endsAt, end + AuctionRules.bidExtension, "a late bid adds a short fixed extension to the end")
        XCTAssertEqual(b.auctions[0].extensions, 1)
    }

    func testSaleTakesTheBuyersCashAndBurnsTheFee() throws {
        var b = book(with: auction())
        var c = Cabinet()
        _ = try b.place("A1", bidder: me, amount: 300, now: t0 + 100, cash: 1_000)
        XCTAssertTrue(b.settleDue(now: t0 + 100, cash: 1_000, cabinet: &c).isEmpty, "not over yet")
        let done = b.settleDue(now: t0 + 3_601, cash: 1_000, cabinet: &c)
        XCTAssertEqual(done.first?.status, .sold)
        XCTAssertEqual(done.first?.fee, 30)
        XCTAssertEqual(done.first?.cash, -300, "the buyer pays the whole price")
        XCTAssertTrue(c.contains("abacus#14"))
        XCTAssertEqual(b.feesBurned, 30)
        XCTAssertTrue(b.settleDue(now: t0 + 9_999, cash: 700, cabinet: &c).isEmpty, "settles once")
    }

    func testSellerIsPaidLessTheFeeAndCashIsConserved() throws {
        var c = Cabinet(); c.add(ArtifactItem(defID: "map", serial: 3))
        var b = AuctionBook(me: me)
        let a = try b.list("map#3", startPrice: 50, reserve: nil, duration: .sixHours, now: t0, cabinet: &c)
        XCTAssertFalse(c.contains("map#3"), "on sale, out of the cabinet")
        _ = try b.place(a.id, bidder: "rival", amount: 400, now: t0 + 100)
        let done = b.settleDue(now: t0 + 7 * 3_600, cash: 0, cabinet: &c)
        XCTAssertEqual(done.first?.winner, "rival")
        XCTAssertEqual(done.first?.cash, 360)
        XCTAssertEqual(b.feesBurned, 40)
        XCTAssertEqual((done.first?.cash ?? 0) + b.feesBurned, 400, "the buyer's cash = seller proceeds + the fee that left")
        XCTAssertFalse(c.contains("map#3"))
    }

    func testAWinnerWhoCanNoLongerPayDoesNotBuy() throws {
        var b = book(with: auction())
        var c = Cabinet()
        _ = try b.place("A1", bidder: me, amount: 300, now: t0 + 100, cash: 400)
        let done = b.settleDue(now: t0 + 3_601, cash: 120, cabinet: &c)
        XCTAssertEqual(done.first?.status, .unsold)
        XCTAssertEqual(done.first?.cash, 0)
        XCTAssertTrue(c.items.isEmpty)
    }

    func testReserveNotMetReturnsTheItem() throws {
        var c = Cabinet(); c.add(ArtifactItem(defID: "scales", serial: 9))
        var b = AuctionBook(me: me)
        let a = try b.list("scales#9", startPrice: 100, reserve: 500, duration: .oneHour, now: t0, cabinet: &c)
        _ = try b.place(a.id, bidder: "rival", amount: 200, now: t0 + 10)
        XCTAssertFalse(b.auction(a.id)!.reserveMet)
        let done = b.settleDue(now: t0 + 4_000, cash: 0, cabinet: &c)
        XCTAssertEqual(done.first?.status, .unsold)
        XCTAssertTrue(c.contains("scales#9"), "item returns")
        XCTAssertEqual(done.first?.cash, 0); XCTAssertEqual(b.feesBurned, 0)

        var b2 = book(with: auction(reserve: 500))
        var c2 = Cabinet()
        _ = try b2.place("A1", bidder: me, amount: 200, now: t0 + 10, cash: 300)
        let none = b2.settleDue(now: t0 + 4_000, cash: 300, cabinet: &c2)
        XCTAssertEqual(none.first?.cash, 0); XCTAssertEqual(b2.held, 0); XCTAssertTrue(c2.items.isEmpty)
    }

    func testListingAndCancelRules() throws {
        var c = Cabinet(); c.add(ArtifactItem(defID: "stamp", serial: 1))
        var b = AuctionBook(me: me)
        XCTAssertThrowsError(try b.list("stamp#1", startPrice: 0, reserve: nil, duration: .oneHour, now: t0, cabinet: &c))
        XCTAssertThrowsError(try b.list("stamp#1", startPrice: 100, reserve: 50, duration: .oneHour, now: t0, cabinet: &c))
        XCTAssertThrowsError(try b.list("stamp#1", startPrice: 100, reserve: nil, buyNow: 100, duration: .oneHour, now: t0, cabinet: &c))
        XCTAssertThrowsError(try b.list("stamp#1", startPrice: 100, reserve: 300, buyNow: 200, duration: .oneHour, now: t0, cabinet: &c))
        XCTAssertThrowsError(try b.list("nothing#1", startPrice: 100, reserve: nil, duration: .oneHour, now: t0, cabinet: &c)) { XCTAssertEqual($0 as? AuctionError, .notYours) }
        let a = try b.list("stamp#1", startPrice: 100, reserve: nil, duration: .oneHour, now: t0, cabinet: &c)
        try b.cancel(a.id, cabinet: &c)
        XCTAssertTrue(c.contains("stamp#1"))
        let a2 = try b.list("stamp#1", startPrice: 100, reserve: nil, duration: .oneHour, now: t0, cabinet: &c)
        _ = try b.place(a2.id, bidder: "rival", amount: 100, now: t0 + 1)
        XCTAssertThrowsError(try b.cancel(a2.id, cabinet: &c)) { XCTAssertEqual($0 as? AuctionError, .hasBids) }
    }

    func testBuyNowEndsTheAuctionAtOnceAndPaysTheSeller() throws {
        var b = book(with: auction(start: 100, buyNow: 400))
        var c = Cabinet()
        XCTAssertThrowsError(try b.buyNow("A1", buyer: me, now: t0 + 10, cash: 399)) { XCTAssertEqual($0 as? AuctionError, .notEnoughCash(missing: 1)) }
        XCTAssertThrowsError(try b.buyNow("A1", buyer: "seller", now: t0 + 10)) { XCTAssertEqual($0 as? AuctionError, .sellerCannotBid) }
        try b.buyNow("A1", buyer: me, now: t0 + 10, cash: 1_000)
        XCTAssertEqual(b.auctions[0].endsAt, t0 + 10)
        XCTAssertFalse(b.auctions[0].isLive(at: t0 + 10))
        let done = b.settleDue(now: t0 + 10, cash: 1_000, cabinet: &c)
        XCTAssertEqual(done.first?.status, .sold)
        XCTAssertEqual(done.first?.price, 400)
        XCTAssertEqual(done.first?.cash, -400)
        XCTAssertTrue(c.contains("abacus#14"))
    }

    func testBuyNowGoesOnceABidReachesIt() throws {
        var b = book(with: auction(start: 100, buyNow: 400))
        XCTAssertTrue(b.auctions[0].canBuyNow(at: t0))
        _ = try b.place("A1", bidder: "rival", amount: 400, now: t0 + 5)
        XCTAssertFalse(b.auctions[0].canBuyNow(at: t0 + 6))
        XCTAssertThrowsError(try b.buyNow("A1", buyer: me, now: t0 + 6, cash: 10_000)) { XCTAssertEqual($0 as? AuctionError, .noBuyNow) }
        var plain = book(with: auction())
        XCTAssertThrowsError(try plain.buyNow("A1", buyer: me, now: t0 + 6, cash: 10_000)) { XCTAssertEqual($0 as? AuctionError, .noBuyNow) }
    }

    func testPreviewExplainsTheBid() {
        var a = auction()
        a.bids.append(AuctionBid(bidder: "rival", amount: 100, at: t0))
        let ok = AuctionRules.preview(a, amount: 150, bidder: me, cash: 300, held: 0, now: t0 + 3_500)
        XCTAssertTrue(ok.allowed)
        XCTAssertEqual(ok.heldAfter, 150); XCTAssertEqual(ok.availableAfter, 150)
        XCTAssertTrue(ok.extendsAuction)
        let short = AuctionRules.preview(a, amount: 400, bidder: me, cash: 300, held: 0, now: t0 + 100)
        XCTAssertFalse(short.allowed)
        XCTAssertEqual(short.shortBy, 100)
        XCTAssertEqual(short.problem, "You do not have enough cash for that bid.")
        XCTAssertFalse(AuctionRules.preview(a, amount: 102, bidder: me, cash: 300, held: 0, now: t0 + 100).allowed, "below the minimum")
        let tied = AuctionRules.preview(a, amount: 150, bidder: me, cash: 300, held: 200, now: t0 + 100)
        XCTAssertFalse(tied.allowed, "cash set aside for other leading bids is not free")
        XCTAssertEqual(tied.shortBy, 50)
    }

    func testListingPreviewShowsWhatTheSellerKeeps() {
        let p = AuctionRules.listingPreview(startPrice: 1_000, reserve: 2_000, buyNow: 5_000, duration: .sixHours)
        XCTAssertNil(p.problem)
        XCTAssertEqual(p.proceedsAtStart, 900)
        XCTAssertEqual(p.proceedsAtReserve, 1_800)
        XCTAssertEqual(p.proceedsAtBuyNow, 4_500)
        XCTAssertTrue(p.lines.contains { $0.contains("buy-now") })
        XCTAssertFalse(p.lines.contains { $0.lowercased().contains("gold") }, "auctions are in cash")
        XCTAssertNotNil(AuctionRules.listingPreview(startPrice: 1_000, reserve: 500, duration: .oneHour).problem)
    }

    func testASuggestedStartScalesWithTheRarityAndThePriceLevel() {
        XCTAssertEqual(AuctionMarket.suggestedStart(.common, priceLevel: 1), 300)
        XCTAssertGreaterThan(AuctionMarket.suggestedStart(.legendary, priceLevel: 1), AuctionMarket.suggestedStart(.epic, priceLevel: 1))
        XCTAssertEqual(AuctionMarket.suggestedStart(.rare, priceLevel: 0.1), 120)
        XCTAssertGreaterThanOrEqual(AuctionMarket.suggestedStart(.common, priceLevel: 0.0001), 1)
    }

    func testAQuickSalePaysBelowTheMarketValueAndIsRepeatable() {
        for rarity in BoxRarity.allCases {
            let market: Int = AuctionMarket.suggestedStart(rarity, priceLevel: 1)
            let quick: Int = AuctionRules.quickSalePrice(rarity, priceLevel: 1)
            XCTAssertLessThan(quick, market)
            XCTAssertGreaterThanOrEqual(quick * 100, market * 85)
            XCTAssertLessThanOrEqual(quick * 100, market * 90)
            XCTAssertEqual(quick, AuctionRules.quickSalePrice(rarity, priceLevel: 1))
        }
        XCTAssertEqual(AuctionRules.quickSalePrice(.common, priceLevel: 1), 264)
        XCTAssertGreaterThanOrEqual(AuctionRules.quickSalePrice(.common, priceLevel: 0.0001), 1)
    }

    func testQuickSellTakesThePieceOutAndSellsItOnlyOnce() {
        var c = Cabinet()
        c.add(ArtifactItem(defID: "scales", serial: 7))
        XCTAssertNil(c.quickSell("scales#8", priceLevel: 1))
        XCTAssertEqual(c.quickSell("scales#7", priceLevel: 1), AuctionRules.quickSalePrice(.rare, priceLevel: 1))
        XCTAssertFalse(c.contains("scales#7"))
        XCTAssertNil(c.quickSell("scales#7", priceLevel: 1))
    }

    func testDuplicatesKeepTheLowestNumberOfEachPiece() {
        var c = Cabinet()
        let first = ArtifactItem(defID: "abacus", serial: 9)
        let second = ArtifactItem(defID: "abacus", serial: 3)
        let third = ArtifactItem(defID: "abacus", serial: 40)
        let single = ArtifactItem(defID: "stamp", serial: 1)
        for i in [first, second, third, single] { c.add(i) }
        let dup = c.duplicates(among: [first, second, third, single])
        XCTAssertEqual(Set(dup.map(\.id)), [first.id, third.id])
        XCTAssertTrue(c.duplicates(among: [second, single]).isEmpty)
        XCTAssertTrue(c.duplicates(among: [ArtifactItem(defID: "abacus", serial: 99)]).isEmpty)
    }

    func testEveryCosmeticABoxCanDropCanBeWorn() {
        let kinds: Set<SeasonReward.Kind> = Set(BoxRarity.allCases.flatMap { GoldCosmetics.boxPool($0, owned: []).map(\.item.kind) })
        XCTAssertFalse(kinds.isEmpty)
        XCTAssertTrue(kinds.allSatisfy(\.isEquippable))
    }

    func testWalletNeverSpendsMoreThanItHas() {
        var w = GoldWallet(balance: 100)
        XCTAssertFalse(w.spend(120))
        XCTAssertTrue(w.spend(20))
        XCTAssertEqual(w.available, 80)
        XCTAssertEqual(w.shortfall(for: 150, purpose: .box)?.missing, 70)
    }

    func testCollectionsPayOnceAndNumbersRead() {
        var c = Cabinet()
        let col = ArtifactCatalog.collections[0]
        var done: [ArtifactCollection] = []
        for (i, m) in col.members.enumerated() { done += c.add(ArtifactItem(defID: m, serial: i + 1)) }
        XCTAssertEqual(done.map(\.id), [col.id])
        XCTAssertNotNil(GoldCosmetics.cosmetic(col.rewardID))
        let sold = c.remove("abacus#1")
        XCTAssertNotNil(sold)
        XCTAssertTrue(c.add(ArtifactItem(defID: "abacus", serial: 99)).isEmpty)
        XCTAssertEqual(ArtifactCatalog.label(ArtifactItem(defID: "strongbox", serial: 14)), "14 of 500")
        XCTAssertTrue(ArtifactCatalog.collections.allSatisfy { GoldCosmetics.cosmetic($0.rewardID) != nil })
        XCTAssertEqual(Set(ArtifactCatalog.collections.flatMap(\.members)), Set(ArtifactCatalog.defs.map(\.id)))
        for rarity in BoxRarity.allCases { XCTAssertFalse(ArtifactCatalog.defs(of: rarity).isEmpty) }
        XCTAssertEqual(ArtifactCatalog.serial(of: ArtifactCatalog.defs[3], roll: 0.9999), 100)
        XCTAssertEqual(ArtifactCatalog.serial(of: ArtifactCatalog.defs[3], roll: 0), 1)
    }

    func testMarketFillsUpBidsAndSettlesWithConservedCash() {
        let players = (1...8).map { "p\($0)" }
        var b = AuctionBook(me: me)
        var c = Cabinet()
        var cash = 50_000
        let cash0 = cash
        var now: Double = 50_000_000
        AuctionMarket.advance(&b, cash: cash, cabinet: &c, from: now - 1, to: now, players: players)
        XCTAssertEqual(b.auctions.filter { $0.status == .live }.count, AuctionMarket.targetListings)
        XCTAssertTrue(b.auctions.contains { !$0.bids.isEmpty }, "some are already in progress")
        if let a = b.auctions.first(where: { $0.status == .live }) {
            _ = try? b.place(a.id, bidder: me, amount: AuctionRules.minimumBid(a), now: now, cash: cash)
        }
        for _ in 0..<48 {
            let next = now + 3_600
            let done = AuctionMarket.advance(&b, cash: cash, cabinet: &c, from: now, to: next, players: players)
            cash += done.reduce(0) { $0 + $1.cash }
            now = next
            XCTAssertGreaterThanOrEqual(cash, 0)
            XCTAssertEqual(b.auctions.filter { $0.status == .live && $0.seller != me }.count, AuctionMarket.targetListings)
        }
        XCTAssertTrue(b.auctions.contains { $0.status == .sold }, "auctions end")
        XCTAssertTrue(b.auctions.contains { $0.status == .unsold } || b.auctions.filter { $0.status == .sold }.count > 3)
        let won = b.auctions.filter { $0.status == .sold && $0.leader == me }
        XCTAssertEqual(cash0 - cash, won.reduce(0) { $0 + ($1.soldFor ?? 0) })
        XCTAssertEqual(c.items.count, won.count)
    }

    func testMarketIsRepeatable() {
        let players = (1...6).map { "p\($0)" }
        func run() -> [Auction] {
            var b = AuctionBook(me: "me"); var c = Cabinet()
            AuctionMarket.advance(&b, cash: 100, cabinet: &c, from: 0, to: 9_000_000, players: players)
            AuctionMarket.advance(&b, cash: 100, cabinet: &c, from: 9_000_000, to: 9_020_000, players: players)
            return b.auctions
        }
        XCTAssertEqual(run(), run())
    }

    func testMarketPricesFollowThePlayersPriceLevel() {
        let players = (1...6).map { "p\($0)" }
        func starts(_ level: Double) -> Int {
            var b = AuctionBook(me: "me"); var c = Cabinet()
            AuctionMarket.advance(&b, cash: 0, cabinet: &c, from: 0, to: 1, players: players, priceLevel: level)
            return b.auctions.reduce(0) { $0 + $1.startPrice }
        }
        XCTAssertGreaterThan(starts(10), starts(1) * 8)
        XCTAssertLessThan(starts(10), starts(1) * 12)
        var b = AuctionBook(me: "me"); var c = Cabinet()
        var t: Double = 0
        for _ in 0..<30 {
            AuctionMarket.advance(&b, cash: 0, cabinet: &c, from: t, to: t + 21_600, players: players)
            t += 21_600
        }
        XCTAssertTrue(b.auctions.contains { $0.buyNow != nil }, "some listings carry a buy-now price")
        XCTAssertTrue(b.auctions.allSatisfy { a in a.buyNow.map { $0 > a.startPrice && $0 >= (a.reserve ?? 0) } ?? true })
    }
}
