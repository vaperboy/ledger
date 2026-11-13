import SwiftUI
import Simulation

enum GoldGood {
    case boxBundle(BoxBundle)
    case cosmetic(GoldCosmetic)
    case avatar(AvatarDef)
    case service(String, Int)
    case username(Int)
    case moneyPack(MoneyPack)

    var price: Int {
        switch self {
        case .boxBundle(let b): return b.price
        case .cosmetic(let c): return c.price ?? 0
        case .avatar(let d): return d.price ?? 0
        case .service(_, let price): return price
        case .username(let price): return price
        case .moneyPack(let pack): return MoneyPacks.price(pack)
        }
    }
}

struct GoldOffer {
    var title: String
    var effect: String
    var price: Int
    var icon: String
}

@MainActor
enum StorePurchase {
    private static var session: StoreSession { StoreSession.shared }

    static func offer(_ good: GoldGood) -> GoldOffer {
        switch good {
        case .boxBundle(let b):
            return GoldOffer(title: "Buy \(b.count) \(b.kind.title)es?",
                             effect: "you get \(b.count) \(b.kind.title)es in your stock, nothing opened yet. That is \(b.savingPercent)% less than \(StoreText.gold(b.singlesPrice)) for single boxes.",
                             price: b.price, icon: "shippingbox")
        case .cosmetic(let c):
            return GoldOffer(title: "Buy \(c.item.title)?", effect: "you get \(c.item.title) (\(c.rarity.title)). \(c.item.detail)", price: c.price ?? 0, icon: "paintpalette")
        case .avatar(let d):
            return GoldOffer(title: "Buy \(d.title)?", effect: "you get the \(d.title) profile icon. You can wear it straight away.", price: d.price ?? 0, icon: "person.crop.circle")
        case .service(let title, let price):
            return GoldOffer(title: title + "?", effect: "the wait is skipped.", price: price, icon: "forward.end")
        case .username(let price):
            return GoldOffer(title: "Change your username?", effect: "your username changes. The old one is never given to anyone else.", price: price, icon: "pencil")
        case .moneyPack(let pack):
            return GoldOffer(title: "Buy the \(pack.name) pack?", effect: "\(moneyText(pack)) is paid into your personal account in the game" + (pack.bonusPercent > 0 ? ", \(pack.bonusPercent)% more than the gold rate." : "."),
                             price: MoneyPacks.price(pack), icon: "banknote")
        }
    }

    /// A pack's money in the open game's currency.
    static func moneyText(_ pack: MoneyPack) -> String {
        session.money(Int((MoneyPacks.gameMoney(pack) * session.priceLevel).rounded()))
    }

    static func ask(offer: GoldOffer, pending: Binding<PendingAction?>, onShort: @escaping (Int) -> Void, run: @escaping () -> Void) {
        guard offer.price > 0 else { return }
        if session.available < offer.price { onShort(offer.price); return }
        pending.wrappedValue = PendingAction(title: offer.title, message: "If you buy this, \(offer.effect) You pay \(StoreText.gold(offer.price)).", button: "Buy",
                                             alwaysAsk: true, tone: .investment, icon: offer.icon, run: run)
    }

    static func ask(_ good: GoldGood, pending: Binding<PendingAction?>, onShort: @escaping (Int) -> Void, then: @escaping (Bool) -> Void = { _ in }) {
        ask(offer: offer(good), pending: pending, onShort: onShort) {
            Task {
                let done: Bool = await session.buy(good, paidBoxesAllowed: true)
                if done { Haptics.success() }
                then(done)
            }
        }
    }

    static func boxText(_ b: SeasonBundle) -> String {
        b.boxes.map { "\($0.count) \($0.kind.title)\($0.count == 1 ? "" : "es")" }.joined(separator: " and ")
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
        case .cardBasic: return "Profile cards and company cards, mostly plain colours. A rare animated card is possible but unlikely."
        case .cardPremium: return "A fair chance of rare and epic cards, and a real chance of an animated one."
        case .cardElite: return "The best odds of epic and legendary animated cards. Every card is numbered and can be sold at auction."
        }
    }
}
