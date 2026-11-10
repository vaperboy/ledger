import SwiftUI
import Simulation

@MainActor
enum StorePurchase {
    private static var session: StoreSession { StoreSession.shared }

    static func pack(_ pack: GoldPack) -> PendingAction {
        let first: Bool = !session.state.firstPurchaseDone
        let gold: Int = GoldStore.totalGold(pack, firstPurchase: first)
        let price: String = GoldStore.priceText(cents: pack.priceCents)
        var get: String = "If you buy this, you get \(StoreText.gold(gold))"
        if first { get += ", which includes \(GoldStore.firstPurchaseBonus(pack).formatted()) one-time bonus gold" }
        let note: String = session.isVisualOnly ? " Preview build: nothing is charged." : ""
        return PendingAction(title: "Get the \(pack.name)?", message: "\(get). You pay \(price).\(note)", button: "Get gold for \(price)",
                             alwaysAsk: true, tone: .investment, icon: "plus.circle") {
            Task { if await StoreSession.shared.buyPack(pack) { Haptics.success() } }
        }
    }

    static func seasonBundle() -> PendingAction {
        let b: SeasonBundle = GoldStore.seasonBundle
        let price: String = GoldStore.priceText(cents: b.priceCents)
        let boxes: String = boxText(b)
        let note: String = session.isVisualOnly ? " Preview build: nothing is charged and Ledger Plus is not added." : ""
        return PendingAction(title: "Get the season bundle?", message: "If you buy this, you get \(StoreText.gold(b.gold)), \(boxes) and Ledger Plus for this season. You pay \(price).\(note)",
                             button: "Get bundle for \(price)", alwaysAsk: true, tone: .investment, icon: "gift") {
            Task { if await StoreSession.shared.buySeasonBundle() { Haptics.success() } }
        }
    }

    static func boxText(_ b: SeasonBundle) -> String {
        b.boxes.map { "\($0.count) \($0.kind.title)\($0.count == 1 ? "" : "es")" }.joined(separator: " and ")
    }

    static func boxBundle(_ b: BoxBundle) -> PendingAction {
        PendingAction(title: "Buy \(b.count) \(b.kind.title)es?",
                      message: "If you buy this, you get \(b.count) \(b.kind.title)es in your stock, nothing opened yet. You pay \(StoreText.gold(b.price)), \(b.savingPercent)% less than \(StoreText.gold(b.singlesPrice)) for single boxes.",
                      button: "Buy for \(StoreText.gold(b.price))", alwaysAsk: true, tone: .investment, icon: "shippingbox") {
            Task { if await StoreSession.shared.buyBoxBundle(b, paidBoxesAllowed: true) { Haptics.success() } }
        }
    }

    static func cosmetic(_ c: GoldCosmetic, price: Int) -> PendingAction {
        PendingAction(title: "Buy \(c.item.title)?", message: "If you buy this, you get \(c.item.title) (\(c.rarity.title)). \(c.item.detail) You pay \(StoreText.gold(price)).",
                      button: "Buy for \(StoreText.gold(price))", alwaysAsk: true, tone: .investment, icon: "paintpalette") {
            Task { if await StoreSession.shared.buyCosmetic(c) { Haptics.success() } }
        }
    }

    static func afterPopup(_ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Motion.sheetLeaveSeconds * 1_000_000_000))
            work()
        }
    }

    static var bestPack: GoldPack? { GoldStore.packs.max { GoldStore.goldPerUnit($0) < GoldStore.goldPerUnit($1) } }

    static var bestBundle: BoxBundle? { GoldStore.boxBundles.max { $0.savingPercent < $1.savingPercent } }
}

extension BoxKind {
    var blurb: String {
        switch self {
        case .free: return "A small gift: usually a cosmetic or an artifact, sometimes a little gold or cash."
        case .cabinet: return "Cosmetics, numbered artifacts you can sell for cash, and now and then a cash prize."
        case .grand: return "Better odds of rare and epic pieces, with bigger cash prizes. Gold prizes stay small."
        }
    }
}
