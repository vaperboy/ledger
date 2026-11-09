import XCTest
@testable import Simulation

/// Auctions and artifacts: increments, anti-snipe, fee, holds returned when outbid, settlement, listing, collections, and the stand-in market.
final class AuctionRulesTests: XCTestCase {
    private let t0: Double = 1_000_000
    private let me = "me"

    private func book(with a: Auction? = nil) -> AuctionBook {
        var b = AuctionBook(me: me)
        if let a { b.auctions.append(a) }
        return b
    }

    private func auction(seller: String = "seller", start: Int = 100, reserve: Int? = nil, hours: AuctionDuration = .oneHour) -> Auction {
        Auction(id: "A1", item: ArtifactItem(defID: "abacus", serial: 14), seller: seller, startPrice: start, reserve: reserve,
                startsAt: t0, endsAt: t0 + hours.seconds, duration: hours)
    }

    func testIncrementsGrowWithThePrice() {
        XCTAssertEqual(AuctionRules.increment(at: 20), 5)
        XCTAssertEqual(AuctionRules.increment(at: 100), 10)
        XCTAssertEqual(AuctionRules.increment(at: 500), 25)
        XCTAssertEqual(AuctionRules.increment(at: 5_000), 100)
        XCTAssertEqual(AuctionRules.increment(at: 50_000), 500)
        var a = auction()
        XCTAssertEqual(AuctionRules.minimumBid(a), 100, "the first bid may be the start price")
        a.bids.append(AuctionBid(bidder: "x", amount: 100, at: t0 + 1))
        XCTAssertEqual(AuctionRules.minimumBid(a), 110)
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
        XCTAssertEqual(e.end, end - 30 + 120)
        XCTAssertFalse(AuctionRules.extendedEnd(endsAt: end, extensions: AuctionRules.maxExtensions, bidAt: end - 30).extended, "capped")
    }

    func testBidIsHeldWhileLeadingAndReturnedWhenOutbid() throws {
        var b = book(with: auction())
        var w = GoldWallet(balance: 500)
        _ = try b.place("A1", bidder: me, amount: 100, now: t0 + 10, wallet: &w)
        XCTAssertEqual(w.held, 100); XCTAssertEqual(w.available, 400); XCTAssertEqual(w.balance, 500)
        _ = try b.place("A1", bidder: "rival", amount: 110, now: t0 + 20, wallet: &w)
        XCTAssertEqual(w.held, 0, "returned in full when outbid")
        XCTAssertEqual(w.balance, 500)
        // Bidding again holds the new amount only.
        _ = try b.place("A1", bidder: me, amount: 120, now: t0 + 30, wallet: &w)
        XCTAssertEqual(w.held, 120)
    }

    func testBidRules() throws {
        var b = book(with: auction(reserve: 150))
        var w = GoldWallet(balance: 50)
        XCTAssertThrowsError(try b.place("A1", bidder: me, amount: 100, now: t0, wallet: &w)) { XCTAssertEqual($0 as? AuctionError, .notEnoughGold(missing: 50)) }
        XCTAssertThrowsError(try b.place("A1", bidder: me, amount: 60, now: t0, wallet: &w)) { XCTAssertEqual($0 as? AuctionError, .tooLow(minimum: 100)) }
        XCTAssertThrowsError(try b.place("A1", bidder: "seller", amount: 100, now: t0, wallet: &w)) { XCTAssertEqual($0 as? AuctionError, .sellerCannotBid) }
        _ = try b.place("A1", bidder: "rival", amount: 100, now: t0, wallet: &w)
        XCTAssertThrowsError(try b.place("A1", bidder: "rival", amount: 200, now: t0, wallet: &w)) { XCTAssertEqual($0 as? AuctionError, .alreadyLeading) }
        XCTAssertThrowsError(try b.place("A1", bidder: "rival2", amount: 200, now: t0 + 4_000, wallet: &w)) { XCTAssertEqual($0 as? AuctionError, .notLive) }
        XCTAssertEqual(w.balance, 50); XCTAssertEqual(w.held, 0)
    }

    func testBidInTheLastMinutesExtendsTheAuction() throws {
        var b = book(with: auction())
        var w = GoldWallet(balance: 1_000)
        let end = t0 + 3_600
        let r = try b.place("A1", bidder: me, amount: 100, now: end - 60, wallet: &w)
        XCTAssertTrue(r.extended)
        XCTAssertEqual(b.auctions[0].endsAt, end - 60 + 120)
        XCTAssertEqual(b.auctions[0].extensions, 1)
    }

    func testSaleMovesGoldAndBurnsTheFee() throws {
        var b = book(with: auction())
        var w = GoldWallet(balance: 1_000)
        var c = Cabinet()
        _ = try b.place("A1", bidder: me, amount: 300, now: t0 + 100, wallet: &w)
        XCTAssertTrue(b.settleDue(now: t0 + 100, wallet: &w, cabinet: &c).isEmpty, "not over yet")
        let done = b.settleDue(now: t0 + 3_601, wallet: &w, cabinet: &c)
        XCTAssertEqual(done.first?.status, .sold)
        XCTAssertEqual(done.first?.fee, 30)
        XCTAssertEqual(w.balance, 700); XCTAssertEqual(w.held, 0)
        XCTAssertTrue(c.contains("abacus#14"))
        XCTAssertEqual(b.feesBurned, 30)
        XCTAssertTrue(b.settleDue(now: t0 + 9_999, wallet: &w, cabinet: &c).isEmpty, "settles once")
    }

    func testSellerIsPaidLessTheFeeAndGoldIsConserved() throws {
        var c = Cabinet(); c.add(ArtifactItem(defID: "map", serial: 3))
        var b = AuctionBook(me: me)
        var w = GoldWallet(balance: 0)
        let a = try b.list("map#3", startPrice: 50, reserve: nil, duration: .sixHours, now: t0, cabinet: &c)
        XCTAssertFalse(c.contains("map#3"), "on sale, out of the cabinet")
        _ = try b.place(a.id, bidder: "rival", amount: 400, now: t0 + 100, wallet: &w)
        let done = b.settleDue(now: t0 + 7 * 3_600, wallet: &w, cabinet: &c)
        XCTAssertEqual(done.first?.winner, "rival")
        XCTAssertEqual(w.balance, 360)
        XCTAssertEqual(b.feesBurned, 40)
        XCTAssertEqual(w.balance + b.feesBurned, 400, "the buyer's gold = seller proceeds + fee that left")
        XCTAssertFalse(c.contains("map#3"))
    }

    func testReserveNotMetReturnsHoldAndItem() throws {
        var c = Cabinet(); c.add(ArtifactItem(defID: "scales", serial: 9))
        var b = AuctionBook(me: me)
        var w = GoldWallet(balance: 0)
        let a = try b.list("scales#9", startPrice: 100, reserve: 500, duration: .oneHour, now: t0, cabinet: &c)
        _ = try b.place(a.id, bidder: "rival", amount: 200, now: t0 + 10, wallet: &w)
        XCTAssertFalse(b.auction(a.id)!.reserveMet)
        let done = b.settleDue(now: t0 + 4_000, wallet: &w, cabinet: &c)
        XCTAssertEqual(done.first?.status, .unsold)
        XCTAssertTrue(c.contains("scales#9"), "item returns")
        XCTAssertEqual(w.balance, 0); XCTAssertEqual(b.feesBurned, 0)

        var b2 = book(with: auction(reserve: 500))
        var w2 = GoldWallet(balance: 300)
        var c2 = Cabinet()
        _ = try b2.place("A1", bidder: me, amount: 200, now: t0 + 10, wallet: &w2)
        _ = b2.settleDue(now: t0 + 4_000, wallet: &w2, cabinet: &c2)
        XCTAssertEqual(w2.held, 0); XCTAssertEqual(w2.balance, 300); XCTAssertTrue(c2.items.isEmpty)
    }

    func testListingAndCancelRules() throws {
        var c = Cabinet(); c.add(ArtifactItem(defID: "stamp", serial: 1))
        var b = AuctionBook(me: me)
        var w = GoldWallet()
        XCTAssertThrowsError(try b.list("stamp#1", startPrice: 5, reserve: nil, duration: .oneHour, now: t0, cabinet: &c))
        XCTAssertThrowsError(try b.list("stamp#1", startPrice: 100, reserve: 50, duration: .oneHour, now: t0, cabinet: &c))
        XCTAssertThrowsError(try b.list("nothing#1", startPrice: 100, reserve: nil, duration: .oneHour, now: t0, cabinet: &c)) { XCTAssertEqual($0 as? AuctionError, .notYours) }
        let a = try b.list("stamp#1", startPrice: 100, reserve: nil, duration: .oneHour, now: t0, cabinet: &c)
        try b.cancel(a.id, cabinet: &c)
        XCTAssertTrue(c.contains("stamp#1"))
        let a2 = try b.list("stamp#1", startPrice: 100, reserve: nil, duration: .oneHour, now: t0, cabinet: &c)
        _ = try b.place(a2.id, bidder: "rival", amount: 100, now: t0 + 1, wallet: &w)
        XCTAssertThrowsError(try b.cancel(a2.id, cabinet: &c)) { XCTAssertEqual($0 as? AuctionError, .hasBids) }
    }

    func testPreviewExplainsTheBid() {
        var a = auction()
        a.bids.append(AuctionBid(bidder: "rival", amount: 100, at: t0))
        let w = GoldWallet(balance: 300)
        let ok = AuctionRules.preview(a, amount: 150, bidder: me, wallet: w, now: t0 + 3_500)
        XCTAssertTrue(ok.allowed)
        XCTAssertEqual(ok.heldAfter, 150); XCTAssertEqual(ok.availableAfter, 150)
        XCTAssertTrue(ok.extendsAuction)
        let short = AuctionRules.preview(a, amount: 400, bidder: me, wallet: w, now: t0 + 100)
        XCTAssertFalse(short.allowed)
        XCTAssertEqual(short.problem, "You are 100 gold short.")
        XCTAssertFalse(AuctionRules.preview(a, amount: 105, bidder: me, wallet: w, now: t0 + 100).allowed, "below the minimum")
    }

    func testWalletNeverSpendsHeldGold() {
        var w = GoldWallet(balance: 100)
        XCTAssertTrue(w.hold(80))
        XCTAssertFalse(w.spend(30))
        XCTAssertFalse(w.hold(30))
        XCTAssertTrue(w.spend(20))
        w.release(80)
        XCTAssertEqual(w.available, 80)
    }

    func testCollectionsPayOnceAndNumbersRead() {
        var c = Cabinet()
        let col = ArtifactCatalog.collections[0]
        var done: [ArtifactCollection] = []
        for (i, m) in col.members.enumerated() { done += c.add(ArtifactItem(defID: m, serial: i + 1)) }
        XCTAssertEqual(done.map(\.id), [col.id])
        XCTAssertNotNil(GoldCosmetics.cosmetic(col.rewardID))
        // Selling a piece and getting another copy back does not pay twice.
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

    func testMarketFillsUpBidsAndSettlesWithConservedGold() {
        let players = (1...8).map { "p\($0)" }
        var b = AuctionBook(me: me)
        var w = GoldWallet(balance: 5_000)
        var c = Cabinet()
        let total0 = w.balance
        var now: Double = 50_000_000
        AuctionMarket.advance(&b, wallet: &w, cabinet: &c, from: now - 1, to: now, players: players)
        XCTAssertEqual(b.auctions.filter { $0.status == .live }.count, AuctionMarket.targetListings)
        XCTAssertTrue(b.auctions.contains { !$0.bids.isEmpty }, "some are already in progress")
        // Take the lead on one auction, then let two days pass.
        if let a = b.auctions.first(where: { $0.status == .live }) {
            _ = try? b.place(a.id, bidder: me, amount: AuctionRules.minimumBid(a), now: now, wallet: &w)
        }
        for _ in 0..<48 {
            let next = now + 3_600
            AuctionMarket.advance(&b, wallet: &w, cabinet: &c, from: now, to: next, players: players)
            now = next
            XCTAssertGreaterThanOrEqual(w.available, 0)
            XCTAssertEqual(b.auctions.filter { $0.status == .live && $0.seller != me }.count, AuctionMarket.targetListings)
        }
        XCTAssertTrue(b.auctions.contains { $0.status == .sold }, "auctions end")
        XCTAssertTrue(b.auctions.contains { $0.status == .unsold } || b.auctions.filter { $0.status == .sold }.count > 3)
        let lead = b.auctions.filter { $0.status == .live && $0.leader == me }.reduce(0) { $0 + $1.currentPrice }
        XCTAssertEqual(w.held, lead, "holds equal the bids that still lead")
        let spent = c.items.count
        XCTAssertEqual(total0 - w.balance, b.auctions.filter { $0.status == .sold && $0.winner(is: me) }.reduce(0) { $0 + ($1.soldFor ?? 0) })
        XCTAssertEqual(spent, b.auctions.filter { $0.status == .sold && $0.winner(is: me) }.count)
    }

    func testMarketIsRepeatable() {
        let players = (1...6).map { "p\($0)" }
        func run() -> [Auction] {
            var b = AuctionBook(me: "me"); var w = GoldWallet(balance: 100); var c = Cabinet()
            AuctionMarket.advance(&b, wallet: &w, cabinet: &c, from: 0, to: 9_000_000, players: players)
            AuctionMarket.advance(&b, wallet: &w, cabinet: &c, from: 9_000_000, to: 9_020_000, players: players)
            return b.auctions
        }
        XCTAssertEqual(run(), run())
    }
}

private extension Auction {
    func winner(is id: String) -> Bool { leader == id }
}
