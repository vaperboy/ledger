import XCTest
import GameCore
@testable import Simulation

final class FounderEditionTradeTests: XCTestCase {
    private let t0: Double = 1_000_000
    private let me = "me"
    private let firstIcon = "badge.s1.first"

    private var seasonOne: SeasonDef { SeasonCatalog.def(1)! }

    private func avatar(_ id: String) -> JSONValue {
        let native: URL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url: URL = native.appendingPathComponent("App/Ledger/Resources/Content/avatars/avatars.json")
        guard let raw = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return .null }
        return json["avatars"].array.first { (a: JSONValue) -> Bool in a["id"].string == id } ?? .null
    }

    func testFirstStageIconIsBoundToTheAccount() throws {
        let r: SeasonReward = try XCTUnwrap(SeasonRewards.item(firstIcon))
        XCTAssertEqual(r.tier, 1)
        XCTAssertFalse(r.premium)
        XCTAssertTrue(r.accountBound)
        XCTAssertFalse(TradeRules.isSellable(reward: r))
        let item = ArtifactItem(defID: firstIcon, serial: 1)
        XCTAssertFalse(TradeRules.isSellable(item))

        var cabinet = Cabinet(); cabinet.add(item)
        var book = AuctionBook(me: me)
        XCTAssertThrowsError(try book.list(item.id, startPrice: 10, reserve: nil, duration: .oneHour, now: t0, cabinet: &cabinet)) { (e: Error) in
            XCTAssertEqual(e as? AuctionError, .accountBound)
        }
        XCTAssertTrue(cabinet.contains(item.id), "a refused listing leaves the piece in the cabinet")
        XCTAssertTrue(book.auctions.isEmpty)
        XCTAssertNil(cabinet.quickSell(item.id, priceLevel: 1))
        XCTAssertTrue(cabinet.contains(item.id), "a refused quick sale leaves the piece in the cabinet")
    }

    func testFirstStageIconNeverNamesTheFirstPass() {
        let r: SeasonReward? = SeasonRewards.item(firstIcon)
        let icon: JSONValue = avatar("av.s1.first")
        XCTAssertFalse(icon.isNull)
        XCTAssertTrue(icon["bound"].bool)
        let texts: [String] = [r?.title ?? "", r?.detail ?? "", icon["title"].string, ItemThemes.name(r?.theme ?? ""), ItemThemes.name(icon["theme"].string)].map { $0.lowercased() }
        for t in texts {
            for word in ["founder", "season 1", "first", "launch", "edition"] { XCTAssertFalse(t.contains(word), "\"\(t)\" must not say \"\(word)\"") }
        }
        XCTAssertEqual(r?.theme, ItemThemes.classicID)
        XCTAssertEqual(r?.founderEdition, false)
    }

    func testEveryOtherSeasonOneRewardIsSellable() {
        let others: [SeasonReward] = seasonOne.rewards.filter { $0.id != firstIcon }
        XCTAssertGreaterThan(others.count, 40)
        for r in others {
            let consumed: Bool = r.kind == .box || r.kind == .gold
            XCTAssertEqual(TradeRules.isSellable(reward: r), !consumed, "\(r.id) is sellable unless it is used up on claiming")
            XCTAssertFalse(r.accountBound, r.id)
            XCTAssertTrue(TradeRules.isSellable(ArtifactItem(defID: r.id, serial: 1)), r.id)
        }
        XCTAssertEqual(seasonOne.rewards.filter { $0.accountBound }.map { $0.id }, [firstIcon], "only the first-stage icon is bound")
    }

    func testOtherSeasonOneRewardsCanBeListedAtAuction() throws {
        for r in seasonOne.rewards where r.kind != .box && r.kind != .gold && r.id != firstIcon {
            var cabinet = Cabinet(); cabinet.add(ArtifactItem(defID: r.id, serial: 7))
            var book = AuctionBook(me: me)
            let a: Auction = try book.list("\(r.id)#7", startPrice: 50, reserve: nil, duration: .oneHour, now: t0, cabinet: &cabinet)
            XCTAssertEqual(a.item.defID, r.id)
            XCTAssertFalse(cabinet.contains("\(r.id)#7"), "on sale, out of the cabinet")
        }
    }

    func testFounderFlagSurvivesSaleAndPurchase() throws {
        let aurora: CardDef = try XCTUnwrap(CardCatalog.def("card.p.aurora"))
        XCTAssertTrue(aurora.founderEdition)
        let item: ArtifactItem = CardCatalog.item(aurora, roll: 0.5)
        XCTAssertTrue(TradeRules.isFounderEdition(item))

        var cabinet = Cabinet(); cabinet.add(item)
        var book = AuctionBook(me: me)
        let a: Auction = try book.list(item.id, startPrice: 100, reserve: nil, duration: .oneHour, now: t0, cabinet: &cabinet)
        XCTAssertTrue(TradeRules.isFounderEdition(a.item), "the flag is still there while listed")
        _ = try book.place(a.id, bidder: "rival", amount: 400, now: t0 + 100)
        let sold: [AuctionSettlement] = book.settleDue(now: t0 + 3_601, cash: 0, cabinet: &cabinet)
        XCTAssertEqual(sold.first?.status, .sold)
        XCTAssertEqual(sold.first?.winner, "rival")
        XCTAssertTrue(sold.first.map { TradeRules.isFounderEdition($0.item) } ?? false, "the flag travels with the sold piece")
        XCTAssertEqual(sold.first?.item, item, "the very same numbered piece changes hands")

        var buyer = Cabinet()
        var other = AuctionBook(me: me)
        let idx: Int = other.addOther(item: item, seller: "rival", startPrice: 100, reserve: nil, duration: .oneHour, startsAt: t0, endsAt: t0 + 3_600)
        _ = try other.place(other.auctions[idx].id, bidder: me, amount: 100, now: t0 + 10, cash: 1_000)
        _ = other.settleDue(now: t0 + 3_601, cash: 1_000, cabinet: &buyer)
        XCTAssertTrue(buyer.contains(item.id))
        XCTAssertTrue(buyer.items.allSatisfy { TradeRules.isFounderEdition($0) }, "a piece bought back is still founder edition")
        XCTAssertEqual(CardCatalog.def(forItem: item.id)?.founderEdition, true)
    }

    func testSeasonOneIsTheFounderEditionAndOrdinaryItemsAreNot() {
        XCTAssertTrue(seasonOne.founderEdition)
        XCTAssertEqual(seasonOne.theme, ItemThemes.founderID)
        for r in seasonOne.rewards where r.id != firstIcon && r.kind != .profileCard && r.kind != .companyCard {
            XCTAssertTrue(r.founderEdition, r.id)
            XCTAssertEqual(r.theme, ItemThemes.founderID, r.id)
        }
        for r in seasonOne.rewards where r.kind == .profileCard || r.kind == .companyCard {
            XCTAssertEqual(r.founderEdition, CardCatalog.def(r.id)?.founderEdition, "a card reward follows its card")
        }
        XCTAssertFalse(TradeRules.isFounderEdition("card.p.olive"))
        XCTAssertFalse(TradeRules.isFounderEdition("gold.coll.harbour"))
        XCTAssertEqual(GoldCosmetics.cosmetic("gold.coll.harbour")?.item.theme, "harbour")
    }

    func testRewardsOfLaterSeasonsFollowTheirOwnFile() {
        XCTAssertEqual(SeasonCatalog.active(1)?.number, 1)
        XCTAssertNotNil(SeasonCatalog.active(99), "a season without a file still shows a pass")
        XCTAssertEqual(SeasonPass(today: 0).seasonDef?.number, 1)
        XCTAssertEqual(SeasonPass(today: 0).reward(.free, tier: 1)?.id, firstIcon)
    }
}
