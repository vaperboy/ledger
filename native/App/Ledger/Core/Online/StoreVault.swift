import Foundation
import Simulation

actor GoldVault {
    static let meID = "me"

    private struct Saved: Codable {
        var wallet: GoldWallet
        var boxes: [String: Int]
        var pity: BoxPity
        var firstPurchaseDone: Bool
        var cabinet: Cabinet
        var opened: Int
        var book: AuctionBook
        var lastTick: Double
        var cashAuctions: Bool?
        var deliveries: DeliveryLedger?
    }

    private let defaults: UserDefaults
    private let key: String
    private var wallet = GoldWallet()
    private var boxes: [String: Int] = [:]
    private var pity = BoxPity()
    private var firstPurchaseDone = false
    private var cabinet = Cabinet()
    private var opened = 0
    private var book = AuctionBook(me: GoldVault.meID)
    private var lastTick: Double = 0
    private var deliveries = DeliveryLedger()
    private let players: [String]
    private let names: [String: String]

    init(suiteName: String? = nil, key: String = "ledger.store.mock.v1") {
        defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        self.key = key
        let roster: [PlayerProfile] = SampleRoster.players().prefix(24).map { $0 }
        players = roster.map(\.id)
        var map: [String: String] = [GoldVault.meID: "You"]
        for p in roster { map[p.id] = p.displayName }
        names = map
        if let data = defaults.data(forKey: key), let s = try? JSONDecoder().decode(Saved.self, from: data) {
            wallet = s.wallet; boxes = s.boxes; pity = s.pity; firstPurchaseDone = s.firstPurchaseDone
            cabinet = s.cabinet; opened = s.opened
            deliveries = s.deliveries ?? DeliveryLedger()
            if s.cashAuctions == true {
                book = s.book; lastTick = s.lastTick
            } else {
                for a in s.book.auctions where a.seller == GoldVault.meID && a.status == .live { cabinet.add(a.item) }
            }
        }
    }

    func state() -> StoreState {
        StoreState(wallet: wallet, boxes: boxes, pity: pity, firstPurchaseDone: firstPurchaseDone, cabinet: cabinet, boxesOpened: opened)
    }

    /// Empties the wallet, boxes and cabinet once they have moved to the server, so they cannot move twice.
    func wipeAfterImport() {
        wallet = GoldWallet()
        boxes = [:]
        pity = BoxPity()
        cabinet = Cabinet()
        opened = 0
        save()
    }

    private func save() {
        let s = Saved(wallet: wallet, boxes: boxes, pity: pity, firstPurchaseDone: firstPurchaseDone, cabinet: cabinet, opened: opened, book: book, lastTick: lastTick, cashAuctions: true, deliveries: deliveries)
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: key) }
    }

    func deliver(_ item: PurchaseItem, transactionID: String) throws -> PurchaseDeliveryResult {
        guard PurchaseCatalog.isConsumable(item) else { throw StoreError.unknownItem }
        guard !deliveries.has(transactionID) else { return PurchaseDeliveryResult(state: state(), delivered: false, gold: 0) }
        let gold: Int = PurchaseCatalog.goldGranted(item, firstPurchase: !firstPurchaseDone)
        switch item {
        case .goldPack(let id):
            guard GoldStore.packs.contains(where: { (p: GoldPack) -> Bool in p.id == id }) else { throw StoreError.unknownItem }
            firstPurchaseDone = true
        case .seasonBundle:
            for (kind, n) in GoldStore.seasonBundle.boxes { boxes[kind.rawValue, default: 0] += n }
        case .seasonLevels:
            for (kind, n) in GoldStore.seasonLevels.boxes { boxes[kind.rawValue, default: 0] += n }
        case .perk:
            break
        case .plan:
            throw StoreError.unknownItem
        }
        wallet.credit(gold)
        deliveries.record(PurchaseDelivery(transactionID: transactionID, productID: PurchaseCatalog.productID(item), gold: gold))
        save()
        return PurchaseDeliveryResult(state: state(), delivered: true, gold: gold)
    }

    func revoke(transactionID: String) -> StoreState {
        if let d = deliveries.revoke(transactionID) {
            wallet.spend(min(wallet.available, d.gold))
            save()
        }
        return state()
    }

    func buyBoxBundle(_ id: String, paidBoxesAllowed: Bool) throws -> StoreState {
        guard let b = GoldStore.boxBundles.first(where: { $0.id == id }) else { throw StoreError.unknownItem }
        guard paidBoxesAllowed else { throw StoreError.paidBoxesUnavailable }
        guard wallet.spend(b.price) else { throw StoreError.notEnoughGold(missing: b.price - wallet.available) }
        boxes[b.kind.rawValue, default: 0] += b.count
        save()
        return state()
    }

    func buyCosmetic(_ id: String, owned: Set<String>) throws -> StoreState {
        guard let c = GoldCosmetics.cosmetic(id), let price = c.price else { throw StoreError.unknownItem }
        guard !owned.contains(id) else { throw StoreError.alreadyOwned }
        guard wallet.spend(price) else { throw StoreError.notEnoughGold(missing: price - wallet.available) }
        save()
        return state()
    }

    func spendGold(_ amount: Int) throws -> StoreState {
        guard amount > 0 else { throw StoreError.unknownItem }
        guard wallet.spend(amount) else { throw StoreError.notEnoughGold(missing: amount - wallet.available) }
        save()
        return state()
    }

    func buyAvatar(_ id: String, owned: Set<String>) throws -> StoreState {
        guard let def = AvatarCatalog.def(id), let price = def.price else { throw StoreError.unknownItem }
        guard !owned.contains(id) else { throw StoreError.alreadyOwned }
        guard wallet.spend(price) else { throw StoreError.notEnoughGold(missing: price - wallet.available) }
        save()
        return state()
    }

    func openBoxes(_ kind: BoxKind, count: Int, owned: Set<String>, paidBoxesAllowed: Bool) throws -> BoxOpening {
        if kind.isPaid && !paidBoxesAllowed { throw StoreError.paidBoxesUnavailable }
        let n: Int = max(1, count)
        let stock: Int = boxes[kind.rawValue] ?? 0
        let fromStock: Int = min(stock, n)
        let toBuy: Int = n - fromStock
        if toBuy > 0 {
            guard kind.isPaid else { throw StoreError.noBox }
            let cost: Int = toBuy * kind.price
            guard wallet.spend(cost) else { throw StoreError.notEnoughGold(missing: cost - wallet.available) }
        }
        boxes[kind.rawValue] = stock - fromStock
        let out = BoxOdds.openMany(kind, count: n, pity: pity, ownedCosmetics: owned, seed: UUID().uuidString)
        pity = out.pity
        opened += n
        var completed: [ArtifactCollection] = []
        for r in out.results {
            switch r.content {
            case .gold(let g, _): wallet.credit(g)
            case .artifact(let item): completed += cabinet.add(item)
            case .cosmetic, .money: break
            }
        }
        save()
        return BoxOpening(kind: kind, results: out.results, state: state(), completed: completed)
    }

    func grantFromSeason(boxes n: Int, gold: Int) -> StoreState {
        if n > 0 { boxes[BoxKind.free.rawValue, default: 0] += n }
        wallet.credit(gold)
        save()
        return state()
    }

    func grantCard(_ defID: String, roll: Double) -> StoreState {
        var item: ArtifactItem
        let edition: Int
        if let d = CardCatalog.def(defID) {
            item = CardCatalog.item(d, roll: roll)
            edition = ArtifactCatalog.edition(d.rarity)
        } else if let a = ArtifactCatalog.defs.first(where: { (x: ArtifactDef) -> Bool in x.id == defID }) {
            item = ArtifactItem(defID: a.id, serial: ArtifactCatalog.serial(of: a, roll: roll))
            edition = a.edition
        } else { return state() }
        var tries = 0
        while cabinet.contains(item.id) && tries < edition {
            item = ArtifactItem(defID: item.defID, serial: item.serial % edition + 1)
            tries += 1
        }
        cabinet.add(item)
        save()
        return state()
    }

    func quickSell(_ ids: [String], priceLevel: Double) throws -> QuickSale {
        var cash = 0
        var sold: [ArtifactItem] = []
        for id in ids {
            guard let item = cabinet.items.first(where: { $0.id == id }), let price = cabinet.quickSell(id, priceLevel: priceLevel) else { continue }
            cash += price
            sold.append(item)
        }
        guard !sold.isEmpty else { throw AuctionError.notYours }
        save()
        return QuickSale(state: state(), cash: cash, sold: sold)
    }

    func giveAway(_ id: String) throws -> StoreState {
        guard cabinet.remove(id) != nil else { throw AuctionError.notYours }
        save()
        return state()
    }

    func receiveGift(_ item: ArtifactItem) -> (state: StoreState, completed: [ArtifactCollection]) {
        let done: [ArtifactCollection] = cabinet.addAcquired(item)
        save()
        return (state(), done)
    }

    private func now() -> Double { Date().timeIntervalSince1970 }

    private func snapshot(_ settled: [AuctionSettlement] = []) -> AuctionsSnapshot {
        let mine: [AuctionSettlement] = settled.filter { $0.seller == GoldVault.meID || $0.winner == GoldVault.meID }
        return AuctionsSnapshot(auctions: book.auctions, state: state(), now: now(), names: names, settled: mine)
    }

    func refresh(cash: Int, priceLevel: Double) -> AuctionsSnapshot {
        let t: Double = now()
        let done = AuctionMarket.advance(&book, cash: cash, cabinet: &cabinet, from: lastTick == 0 ? t - 1 : lastTick, to: t, players: players, priceLevel: priceLevel)
        lastTick = t
        book.auctions.removeAll { $0.status != .live && $0.endsAt < t - 86_400 }
        save()
        return snapshot(done)
    }

    func placeBid(_ id: String, amount: Int, cash: Int) throws -> AuctionsSnapshot {
        _ = try book.place(id, bidder: GoldVault.meID, amount: amount, now: now(), cash: cash)
        save()
        return snapshot()
    }

    func buyNow(_ id: String, cash: Int) throws -> AuctionsSnapshot {
        let t: Double = now()
        try book.buyNow(id, buyer: GoldVault.meID, now: t, cash: cash)
        let done = book.settleDue(now: t, cash: cash, cabinet: &cabinet)
        save()
        return snapshot(done)
    }

    func list(_ itemID: String, startPrice: Int, reserve: Int?, buyNow: Int?, duration: AuctionDuration) throws -> AuctionsSnapshot {
        _ = try book.list(itemID, startPrice: startPrice, reserve: reserve, buyNow: buyNow, duration: duration, now: now(), cabinet: &cabinet)
        save()
        return snapshot()
    }

    func cancel(_ id: String) throws -> AuctionsSnapshot {
        try book.cancel(id, cabinet: &cabinet)
        save()
        return snapshot()
    }
}
