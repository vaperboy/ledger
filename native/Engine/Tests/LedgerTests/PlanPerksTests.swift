import XCTest
import GameCore
import Businesses
@testable import Simulation

final class PlanPerksTests: XCTestCase {
    private static let native: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func avatars() throws -> [JSONValue] {
        let url: URL = Self.native.appendingPathComponent("App/Ledger/Resources/Content/avatars/avatars.json")
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))["avatars"].array
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testProBySubscriptionOrPurchaseOwnsProAndNeitherIsPlusOrFounder() {
        for p in [LedgerProduct.pro, .proYearly] {
            let e = EntitlementSnapshot(owned: [p])
            XCTAssertTrue(e.ownsPro(), p.rawValue)
            XCTAssertFalse(e.isPlus(now: now), p.rawValue)
            XCTAssertFalse(e.isFounder(), p.rawValue)
        }
        XCTAssertTrue(LedgerProduct.proYearly.isSubscription)
        XCTAssertFalse(LedgerProduct.proYearly.isPlus)
        XCTAssertFalse(LedgerProduct.pro.isSubscription)
        XCTAssertFalse(LedgerProduct.founder.isSubscription)
        XCTAssertTrue(EntitlementSnapshot(owned: [.founder]).ownsPro())
    }

    func testPlusRemovesAdsAndFounderAndProDoNotNeedItForTheirOwnPerks() {
        let plus = EntitlementSnapshot(owned: [.plusYearly], plusExpires: now.addingTimeInterval(1_000))
        XCTAssertTrue(plus.isAdFree(now: now))
        XCTAssertTrue(plus.isPlus(now: now))
        XCTAssertFalse(plus.ownsPro())
        XCTAssertFalse(EntitlementSnapshot.free.isAdFree(now: now))
    }

    func testEveryPlanProductIsPricedAndTheNewOnesAreInTheTable() {
        XCTAssertEqual(GoldPrices.planCents(LedgerProduct.proYearly.rawValue), 3_999)
        XCTAssertLessThan(GoldPrices.planCents(LedgerProduct.proYearly.rawValue) ?? 0, GoldPrices.planCents(LedgerProduct.pro.rawValue) ?? 0)
        XCTAssertGreaterThan(GoldStore.seasonLevels.priceCents, GoldStore.seasonBundle.priceCents)
        XCTAssertGreaterThan(GoldStore.seasonLevels.tiers, 0)
        XCTAssertEqual(GoldStore.seasonBundle.tiers, 0)
        XCTAssertTrue(GoldStore.seasonLevels.includesPlus)
        XCTAssertEqual(PurchaseCatalog.seasonLevelsID, "com.ledger.season.levels")
        XCTAssertNotEqual(PurchaseCatalog.seasonLevelsID, PurchaseCatalog.seasonBundleID)
    }

    func testTheProBundleIsAboutTenStandardBoxesAndFounderIsTheBiggestGold() {
        XCTAssertEqual(GoldPrices.proBundleGold, 10 * BoxKind.cabinet.price)
        XCTAssertGreaterThan(GoldPrices.founderBundleGold, GoldPrices.proBundleGold)
        let biggestPack: Int = GoldStore.packs.map { $0.gold }.max() ?? 0
        XCTAssertGreaterThan(GoldPrices.proBundleGold, biggestPack / 4)
        XCTAssertEqual(PurchaseCatalog.goldGranted(.perk(.pro), firstPurchase: true), GoldPrices.proBundleGold)
        XCTAssertEqual(PurchaseCatalog.goldGranted(.perk(.founder), firstPurchase: false), GoldPrices.founderBundleGold)
        XCTAssertEqual(PurchaseCatalog.goldGranted(.perk(.founderPass), firstPurchase: true), 0)
        XCTAssertEqual(PurchaseCatalog.goldGranted(.plan(.founder), firstPurchase: true), 0)
        XCTAssertEqual(PurchaseCatalog.goldGranted(.seasonLevels, firstPurchase: true), GoldStore.seasonLevels.gold)
    }

    func testBothProProductsShareOneGoldClaimSoSwitchingNeverPaysTwice() {
        XCTAssertEqual(PlanPerk.perk(for: .pro), .pro)
        XCTAssertEqual(PlanPerk.perk(for: .proYearly), .pro)
        XCTAssertEqual(PlanPerk.perk(for: .founder), .founder)
        XCTAssertNil(PlanPerk.perk(for: .plusMonthly))
        XCTAssertNil(PlanPerk.perk(for: .plusYearly))
        XCTAssertEqual(PlanPerk.pro.claimID(season: 1), PlanPerk.pro.claimID(season: 7))
        XCTAssertNotEqual(PlanPerk.founderPass.claimID(season: 1), PlanPerk.founderPass.claimID(season: 2))
        var ledger = DeliveryLedger()
        let id: String = PlanPerk.pro.claimID(season: 1)
        XCTAssertTrue(ledger.record(PurchaseDelivery(transactionID: id, productID: PurchaseCatalog.productID(.perk(.pro)), gold: GoldPrices.proBundleGold)))
        XCTAssertFalse(ledger.record(PurchaseDelivery(transactionID: id, productID: PurchaseCatalog.productID(.perk(.pro)), gold: GoldPrices.proBundleGold)))
    }

    func testPerksAreNeverStoreProducts() {
        for k in PlanPerk.allCases {
            let id: String = PurchaseCatalog.productID(.perk(k))
            XCTAssertNil(PurchaseCatalog.item(forProductID: id), id)
            XCTAssertFalse(PurchaseCatalog.allProductIDs.contains(id), id)
        }
    }

    func testFounderIsSoldOnlyInSeasonOne() {
        XCTAssertEqual(GoldPrices.founderLastSeason, 1)
        XCTAssertTrue(PlanPerks.founderOnSale(season: 1))
        XCTAssertFalse(PlanPerks.founderOnSale(season: 2))
        XCTAssertTrue(PlanPerks.founderPassOpen(season: 1))
        XCTAssertFalse(PlanPerks.founderPassOpen(season: 2))
        XCTAssertGreaterThan(GoldPrices.founderPassTiers, 0)
    }

    func testPlanFlairsExistAreBoundAndNeverSoldOrDropped() throws {
        for id in [PlanPerks.plusFlair, PlanPerks.founderFlair] {
            let c: GoldCosmetic = try XCTUnwrap(GoldCosmetics.cosmetic(id), id)
            XCTAssertEqual(c.source, .plan, id)
            XCTAssertEqual(c.item.kind, .richListFlair, id)
            XCTAssertTrue(c.item.accountBound, id)
            XCTAssertNil(c.price, id)
            XCTAssertTrue(TradeRules.isAccountBound(id), id)
            XCTAssertNotNil(SeasonRewards.item(id), id)
            for r in BoxRarity.allCases { XCTAssertFalse(GoldCosmetics.boxPool(r, owned: []).contains { $0.id == id }, id) }
            XCTAssertFalse(GoldCosmetics.storeItems.contains { $0.id == id }, id)
        }
        XCTAssertEqual(PlanPerks.cosmetics(for: .plusYearly), [PlanPerks.plusFlair])
        XCTAssertEqual(PlanPerks.cosmetics(for: .plusMonthly), [PlanPerks.plusFlair])
        XCTAssertEqual(PlanPerks.cosmetics(for: .founder), [PlanPerks.founderFlair])
        XCTAssertTrue(PlanPerks.cosmetics(for: .pro).isEmpty)
        var pass = SeasonPass(today: 100)
        pass.grantOwned(PlanPerks.plusFlair)
        XCTAssertTrue(pass.owned.contains(PlanPerks.plusFlair))
    }

    func testEachPlanHasItsProfileIconAndFounderHasAPack() throws {
        let list: [JSONValue] = try avatars()
        func unlock(_ id: String) -> String? { list.first { $0["id"].string == id }?["unlock"].string }
        XCTAssertEqual(unlock(PlanPerks.plusAvatar), "plus")
        XCTAssertEqual(list.first { $0["id"].string == PlanPerks.plusAvatar }?["tier"].string, "common")
        XCTAssertEqual(unlock(PlanPerks.proAvatar), "proOwner")
        let founder: [JSONValue] = list.filter { $0["unlock"].string == "founder" }
        XCTAssertGreaterThanOrEqual(founder.count, 3)
        for a in founder + list.filter { [PlanPerks.plusAvatar, PlanPerks.proAvatar].contains($0["id"].string) } {
            XCTAssertTrue(a["bound"].bool, "\(a["id"].string) cannot be traded")
        }
        for a in founder { XCTAssertTrue(a["founderEdition"].bool, a["id"].string) }
    }

    func testFounderLogosAreLockedUntilFounderAndUnlockedAfter() {
        let logos: [LogoCatalogue.Logo] = LogoCatalogue.all.filter { $0.source == .plan(PlanPerks.founderLogoPerk) }
        XCTAssertGreaterThanOrEqual(logos.count, 3)
        let none: Set<String> = PlanPerks.perks(owned: [.pro, .plusYearly])
        let founder: Set<String> = PlanPerks.perks(owned: [.founder])
        XCTAssertTrue(none.isEmpty)
        for l in logos {
            XCTAssertFalse(LogoCatalogue.isUnlocked(l, level: 100, ladderOn: false, owned: [l.id], perks: none), l.id)
            XCTAssertTrue(LogoCatalogue.isUnlocked(l, level: 1, ladderOn: true, owned: [], perks: founder), l.id)
            XCTAssertEqual(LogoCatalogue.how(l), "Founder's Edition")
        }
    }
}
