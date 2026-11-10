import XCTest
@testable import Simulation

final class PurchaseCatalogTests: XCTestCase {
    private var storeKitFile: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Ledger.storekit")
    }

    private func root() throws -> [String: Any] {
        let data: Data = try Data(contentsOf: storeKitFile)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func configured() throws -> [String: String] {
        let file: [String: Any] = try root()
        var out: [String: String] = [:]
        for p in (file["products"] as? [[String: Any]] ?? []) { if let id = p["productID"] as? String, let t = p["type"] as? String { out[id] = t } }
        for g in (file["subscriptionGroups"] as? [[String: Any]] ?? []) {
            for s in (g["subscriptions"] as? [[String: Any]] ?? []) { if let id = s["productID"] as? String, let t = s["type"] as? String { out[id] = t } }
        }
        return out
    }

    func testEveryProductIDIsUniqueAndNamespaced() {
        let ids: [String] = PurchaseCatalog.allProductIDs
        XCTAssertEqual(Set(ids).count, ids.count)
        for id in ids { XCTAssertTrue(id.hasPrefix(PurchaseCatalog.productPrefix), id) }
        XCTAssertEqual(ids.count, LedgerProduct.allCases.count + GoldStore.packs.count + 1)
    }

    func testTheStoreKitFileHoldsExactlyTheProductsTheCodeSells() throws {
        let file: [String: String] = try configured()
        XCTAssertEqual(Set(file.keys), Set(PurchaseCatalog.allProductIDs))
        for item in PurchaseCatalog.items {
            let type: String = try XCTUnwrap(file[PurchaseCatalog.productID(item)])
            switch item {
            case .plan(let p): XCTAssertEqual(type, p.isPlus ? "RecurringSubscription" : "NonConsumable", p.rawValue)
            case .goldPack, .seasonBundle: XCTAssertEqual(type, "Consumable", PurchaseCatalog.productID(item))
            }
        }
    }

    func testStoreKitPricesMatchTheGoldPackPrices() throws {
        let products: [[String: Any]] = try XCTUnwrap(try root()["products"] as? [[String: Any]])
        func cents(_ id: String) throws -> Int {
            let row: [String: Any] = try XCTUnwrap(products.first { ($0["productID"] as? String) == id })
            let text: String = try XCTUnwrap(row["displayPrice"] as? String)
            let value: Double = try XCTUnwrap(Double(text))
            return Int((value * 100).rounded())
        }
        for pack in GoldStore.packs { XCTAssertEqual(try cents(PurchaseCatalog.productID(.goldPack(pack.id))), pack.priceCents, pack.id) }
        XCTAssertEqual(try cents(PurchaseCatalog.seasonBundleID), GoldStore.seasonBundle.priceCents)
    }

    func testOnlyPacksAndTheBundleAreConsumable() {
        XCTAssertFalse(PurchaseCatalog.isConsumable(.plan(.pro)))
        XCTAssertFalse(PurchaseCatalog.isConsumable(.plan(.plusMonthly)))
        XCTAssertTrue(PurchaseCatalog.isConsumable(.seasonBundle))
        for p in GoldStore.packs { XCTAssertTrue(PurchaseCatalog.isConsumable(.goldPack(p.id))) }
        XCTAssertEqual(PurchaseCatalog.consumableProductIDs.count, GoldStore.packs.count + 1)
    }

    func testProductIDsRoundTripToTheirItem() {
        for item in PurchaseCatalog.items { XCTAssertEqual(PurchaseCatalog.item(forProductID: PurchaseCatalog.productID(item)), item) }
        XCTAssertNil(PurchaseCatalog.item(forProductID: "com.ledger.free.gold"))
    }

    func testGoldGrantedIsThePackPlusTheFirstPurchaseBonusOnly() throws {
        let pack: GoldPack = try XCTUnwrap(GoldStore.packs.first)
        XCTAssertEqual(PurchaseCatalog.goldGranted(.goldPack(pack.id), firstPurchase: false), pack.gold)
        XCTAssertEqual(PurchaseCatalog.goldGranted(.goldPack(pack.id), firstPurchase: true), pack.gold + GoldStore.firstPurchaseBonus(pack))
        XCTAssertEqual(PurchaseCatalog.goldGranted(.seasonBundle, firstPurchase: true), GoldStore.seasonBundle.gold)
        XCTAssertEqual(PurchaseCatalog.goldGranted(.plan(.pro), firstPurchase: true), 0)
        XCTAssertEqual(PurchaseCatalog.goldGranted(.goldPack("gold.unknown"), firstPurchase: true), 0)
    }
}

final class PurchaseDeliveryTests: XCTestCase {
    private func delivery(_ id: String, gold: Int = 200) -> PurchaseDelivery {
        PurchaseDelivery(transactionID: id, productID: PurchaseCatalog.productID(.goldPack("gold.pouch")), gold: gold)
    }

    func testATransactionIsDeliveredOnceNoMatterHowOftenItArrives() {
        var ledger = DeliveryLedger()
        XCTAssertTrue(ledger.record(delivery("t1")))
        XCTAssertFalse(ledger.record(delivery("t1")))
        XCTAssertEqual(ledger.entries.count, 1)
        XCTAssertTrue(ledger.record(delivery("t2")))
    }

    func testVerdictsCoverEveryTransactionState() {
        var ledger = DeliveryLedger()
        let pack: String = PurchaseCatalog.productID(.goldPack("gold.pouch"))
        XCTAssertEqual(PurchaseRules.verdict(productID: pack, transactionID: "t1", revoked: false, ledger: ledger), .deliver)
        ledger.record(delivery("t1"))
        XCTAssertEqual(PurchaseRules.verdict(productID: pack, transactionID: "t1", revoked: false, ledger: ledger), .alreadyDelivered)
        XCTAssertEqual(PurchaseRules.verdict(productID: pack, transactionID: "t2", revoked: true, ledger: ledger), .revoked)
        XCTAssertEqual(PurchaseRules.verdict(productID: LedgerProduct.pro.rawValue, transactionID: "t3", revoked: false, ledger: ledger), .entitlement)
        XCTAssertEqual(PurchaseRules.verdict(productID: LedgerProduct.plusYearly.rawValue, transactionID: "t4", revoked: true, ledger: ledger), .entitlement)
        XCTAssertEqual(PurchaseRules.verdict(productID: "com.other.thing", transactionID: "t5", revoked: false, ledger: ledger), .unknown)
    }

    func testARefundIsTakenBackOnceAndOnlyForWhatWasDelivered() {
        var ledger = DeliveryLedger()
        XCTAssertNil(ledger.revoke("never"))
        ledger.record(delivery("t1", gold: 300))
        XCTAssertEqual(ledger.revoke("t1")?.gold, 300)
        XCTAssertNil(ledger.revoke("t1"))
        XCTAssertEqual(ledger.entry("t1")?.revoked, true)
        XCTAssertFalse(ledger.record(delivery("t1")), "a refunded transaction can never be delivered again")
    }

    func testTheLedgerKeepsOnlyTheNewestEntriesAndSurvivesEncoding() throws {
        var ledger = DeliveryLedger()
        for i in 0..<(DeliveryLedger.limit + 25) { ledger.record(delivery("t\(i)")) }
        XCTAssertEqual(ledger.entries.count, DeliveryLedger.limit)
        XCTAssertFalse(ledger.has("t0"))
        XCTAssertTrue(ledger.has("t\(DeliveryLedger.limit + 24)"))
        let back: DeliveryLedger = try JSONDecoder().decode(DeliveryLedger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(back, ledger)
    }
}
