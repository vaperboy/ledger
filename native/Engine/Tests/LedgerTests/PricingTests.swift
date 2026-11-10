import XCTest
@testable import Simulation
import Countries

final class PricingTests: XCTestCase {
    private var storeKitFile: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Ledger.storekit")
    }

    private func storeKitCents() throws -> [String: Int] {
        let data: Data = try Data(contentsOf: storeKitFile)
        let root: [String: Any] = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var out: [String: Int] = [:]
        var rows: [[String: Any]] = (root["products"] as? [[String: Any]]) ?? []
        for g in (root["subscriptionGroups"] as? [[String: Any]] ?? []) { rows += (g["subscriptions"] as? [[String: Any]] ?? []) }
        for r in rows {
            guard let id = r["productID"] as? String, let text = r["displayPrice"] as? String, let v = Double(text) else { continue }
            out[id] = Int((v * 100).rounded())
        }
        return out
    }

    func testTheTableLoads() {
        XCTAssertEqual(Pricing.goldPerNok, 1)
        XCTAssertEqual(Pricing.goldPacks.count, 5)
        XCTAssertEqual(Pricing.boxBundles.count, 3)
        XCTAssertFalse(Pricing.seasonBundle.boxes.isEmpty)
    }

    func testEveryBoxHasItsPriceInTheTable() {
        for kind in BoxKind.allCases {
            XCTAssertEqual(kind.price, Pricing.box(kind.rawValue))
            XCTAssertEqual(kind.isPaid, kind != .free, "\(kind)")
        }
    }

    func testABoxIsAboutTwoDollarsOfGold() throws {
        let us: Pricing.Local = try XCTUnwrap(Pricing.local("USD"))
        let nok: Pricing.Local = try XCTUnwrap(Pricing.local("NOK"))
        XCTAssertEqual(us.box, 2)
        XCTAssertGreaterThanOrEqual(Double(BoxKind.cabinet.price), nok.box, "gold price rounds the 2 USD up, in gold that is about NOK")
        XCTAssertLessThanOrEqual(Double(BoxKind.cabinet.price), nok.box * 1.25)
    }

    func testTheBattlePassIsAboutAHundredGoldAndTheNineNinetyNineTier() {
        XCTAssertEqual(Pricing.battlePassPremiumGold, 100)
        XCTAssertEqual(Pricing.seasonBundle.priceCents, 999)
        for code in ["USD", "EUR", "GBP"] { XCTAssertEqual(Pricing.local(code)?.battlePass, 9.99, code) }
    }

    func testTheOneTimeUnlocksSitOnTheNinetyNineTier() {
        XCTAssertEqual(Pricing.planCents(LedgerProduct.pro.rawValue), 9_999)
        XCTAssertGreaterThanOrEqual(Pricing.planCents(LedgerProduct.founder.rawValue) ?? 0, 9_999)
        for code in ["USD", "EUR", "GBP"] { XCTAssertEqual(Pricing.local(code)?.oneTime, 99.99, code) }
    }

    func testEveryPlanAndPackIsPricedAndMatchesStoreKit() throws {
        let kit: [String: Int] = try storeKitCents()
        for p in LedgerProduct.allCases { XCTAssertEqual(kit[p.rawValue], Pricing.planCents(p.rawValue), p.rawValue) }
        XCTAssertEqual(Set(Pricing.planProductIDs), Set(LedgerProduct.allCases.map { $0.rawValue }))
        for pack in GoldStore.packs { XCTAssertEqual(kit[PurchaseCatalog.productID(.goldPack(pack.id))], pack.priceCents, pack.id) }
        XCTAssertEqual(kit[PurchaseCatalog.seasonBundleID], GoldStore.seasonBundle.priceCents)
    }

    func testGoldPacksStayNearOneGoldPerNokAndNeverBeatTheBestPackRate() {
        for pack in GoldStore.packs {
            let perDollar: Double = GoldStore.goldPerUnit(pack)
            XCTAssertGreaterThanOrEqual(perDollar, 9, pack.id)
            XCTAssertLessThanOrEqual(perDollar, 15, pack.id)
        }
        XCTAssertEqual(GoldStore.packs.map { $0.priceCents }, GoldStore.packs.map { $0.priceCents }.sorted())
    }

    func testCosmeticAndServicePricesAreSane() throws {
        for r in BoxRarity.allCases where r != .legendary {
            let price: Int = try XCTUnwrap(Pricing.cosmetic(rarity: r))
            XCTAssertGreaterThan(price, 0)
            XCTAssertLessThan(price, BoxKind.grand.price * 2)
        }
        XCTAssertNil(Pricing.cosmetic(rarity: .legendary))
        XCTAssertEqual(Pricing.service("usernameChange"), 20)
        XCTAssertGreaterThan(Pricing.service("companyNameSkip"), 0)
        for slot in GoldCosmetics.all where slot.item.kind == .saveSlot { XCTAssertEqual(slot.price, Pricing.item(slot.id), slot.id) }
        for c in GoldCosmetics.storeItems { XCTAssertGreaterThan(c.price ?? 0, 0, c.id) }
    }

    func testEveryCurrencyInTheGameHasLocalPrices() throws {
        let codes: Set<String> = Set(try CountryBook.bundled().countries.map { $0.currencyCode })
        XCTAssertEqual(Set(Pricing.localCurrencies), codes)
        for code in codes {
            let l: Pricing.Local = try XCTUnwrap(Pricing.local(code))
            XCTAssertGreaterThan(l.box, 0, code)
            XCTAssertLessThan(l.box, l.battlePass, code)
            XCTAssertLessThan(l.battlePass, l.oneTime, code)
        }
    }

    func testBundlesAndPacksNeverPayMoreGoldThanTheirPriceInNok() {
        for b in GoldStore.boxBundles { XCTAssertLessThan(b.price, b.singlesPrice) }
        XCTAssertLessThan(GoldStore.seasonBundle.gold, Pricing.battlePassPremiumGold)
    }
}
