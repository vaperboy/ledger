import Foundation
import Observation
import Simulation

struct AuctionPurse {
    var cash: Int
    var priceLevel: Double
    var format: (Int) -> String
}

@MainActor @Observable
final class StoreSession {
    static let shared = StoreSession()

    private(set) var state = StoreState()
    private(set) var auctions: AuctionsSnapshot?
    private(set) var loaded = false
    var problem: String?
    private(set) var notes: [String] = []
    private(set) var pendingOpening: BoxOpening?
    @ObservationIgnored private var opening = false

    @ObservationIgnored var moneyPrizeHandler: ((Int, String) -> Void)?
    @ObservationIgnored var purse: (() -> AuctionPurse?)?
    @ObservationIgnored var cashHandler: ((Int, String, String) -> Void)?
    @ObservationIgnored private let store: any StoreService
    @ObservationIgnored private let market: any AuctionService

    init() {
        let backend = StoreBackend.make()
        store = backend.store
        market = backend.auctions
    }

    var gold: Int { state.wallet.balance }
    var available: Int { state.wallet.available }
    var cash: Int { purse?()?.cash ?? 0 }
    var heldCash: Int { AuctionRules.held(by: GoldVault.meID, in: auctions?.auctions ?? []) }
    var spendableCash: Int { max(0, cash - heldCash) }
    var priceLevel: Double { purse?()?.priceLevel ?? 1 }
    func money(_ n: Int) -> String { purse?()?.format(n) ?? n.formatted() }

    func load() async {
        state = await store.state()
        loaded = true
    }

    private func message(_ error: Error) -> String { (error as? LocalizedError)?.errorDescription ?? "That did not work. Try again." }

    func deliver(_ item: PurchaseItem, transactionID: String) async -> PurchaseDeliveryResult? {
        problem = nil
        do {
            let result: PurchaseDeliveryResult = try await store.deliver(item, transactionID: transactionID)
            state = result.state
            return result
        } catch { problem = message(error); return nil }
    }

    func revoke(transactionID: String) async { state = await store.revoke(transactionID: transactionID) }

    @discardableResult
    func buy(_ good: GoldGood, paidBoxesAllowed: Bool) async -> Bool {
        problem = nil
        guard available >= good.price else { problem = StoreError.notEnoughGold(missing: good.price - available).errorDescription; return false }
        do {
            switch good {
            case .boxBundle(let b):
                state = try await store.buyBoxBundle(b.id, paidBoxesAllowed: paidBoxesAllowed)
            case .cosmetic(let c):
                state = try await store.buyCosmetic(c.id, owned: SeasonModel.shared.pass.owned)
                SeasonModel.shared.grantOwned(c.id)
            case .avatar(let d):
                state = try await store.buyAvatar(d.id, owned: AvatarModel.shared.owned)
                AvatarModel.shared.grant(d.id)
            }
            return true
        } catch { problem = message(error); return false }
    }

    func openBoxes(_ kind: BoxKind, count: Int, paidBoxesAllowed: Bool) async -> BoxOpening? {
        guard !opening, pendingOpening == nil else { return nil }
        opening = true
        defer { opening = false }
        problem = nil
        do {
            let out = try await store.openBoxes(kind, count: count, owned: SeasonModel.shared.pass.owned, paidBoxesAllowed: paidBoxesAllowed)
            state = out.state
            for r in out.results {
                if case .cosmetic(let id) = r.content { SeasonModel.shared.grantOwned(id) }
                if case .money(let amount) = r.content { moneyPrizeHandler?(amount, UUID().uuidString) }
            }
            grantCollections(out.completed)
            pendingOpening = out
            return out
        } catch { problem = message(error); return nil }
    }

    var canSellForCash: Bool { purse?() != nil }

    func quickPrice(_ item: ArtifactItem) -> Int {
        AuctionRules.quickSalePrice(ArtifactCatalog.def(item.defID)?.rarity ?? .common, priceLevel: priceLevel)
    }

    @discardableResult
    func quickSell(_ items: [ArtifactItem]) async -> Int? {
        problem = nil
        guard canSellForCash else { problem = "Open a game to sell for cash."; return nil }
        do {
            let out = try await store.quickSell(itemIDs: items.map(\.id), priceLevel: priceLevel)
            state = out.state
            let what: String = out.sold.count == 1 ? (ArtifactCatalog.def(out.sold[0].defID)?.name ?? "artifact") : "\(out.sold.count) artifacts"
            cashHandler?(out.cash, "quick|" + UUID().uuidString, "Quick sale: " + what)
            return out.cash
        } catch { problem = message(error); return nil }
    }

    func acknowledgeOpening() { pendingOpening = nil }

    func receiveDaily(boxes: Int, gold: Int) {
        Task { state = await store.grantFromSeason(boxes: boxes, gold: gold) }
    }

    @discardableResult
    func giveAway(_ item: ArtifactItem) async -> Bool {
        problem = nil
        do { state = try await store.giveAway(itemID: item.id); return true } catch { problem = message(error); return false }
    }

    func receiveGift(_ item: ArtifactItem) async {
        let out = await store.receiveGift(item)
        state = out.state
        grantCollections(out.completed)
    }

    func receiveSeason(_ r: SeasonReward) {
        if r.kind == .profileCard || r.kind == .companyCard || r.kind == .artifact {
            let roll: Double = CardCatalog.roll("season|\(SeasonModel.shared.pass.season)|" + r.id)
            Task { state = await store.grantCard(defID: r.id, roll: roll) }
            return
        }
        guard r.kind == .box || r.kind == .gold else { return }
        Task { state = await store.grantFromSeason(boxes: r.kind == .box ? r.amount : 0, gold: r.kind == .gold ? r.amount : 0) }
    }

    private static let levelCardsKey = "ledger.cards.levelGranted"

    private static let levelGoldKey = "ledger.level.goldPaid"

    private func receiveLevelGold(_ level: Int) {
        let paid: Int = UserDefaults.standard.integer(forKey: Self.levelGoldKey)
        guard level > paid else { return }
        let gold: Int = LevelRewards.due(from: paid, to: level).reduce(0) { (sum: Int, r: LevelRewards.Reward) -> Int in sum + r.gold }
        UserDefaults.standard.set(level, forKey: Self.levelGoldKey)
        guard gold > 0 else { return }
        Task { state = await store.grantFromSeason(boxes: 0, gold: gold) }
    }

    func receiveLevel(_ level: Int) {
        receiveLevelGold(level)
        let done: Set<String> = Set(UserDefaults.standard.stringArray(forKey: Self.levelCardsKey) ?? [])
        let due: [CardCatalog.LevelReward] = CardCatalog.levelRewards(upTo: level).filter { (r: CardCatalog.LevelReward) -> Bool in !done.contains(r.defID) }
        guard !due.isEmpty else { return }
        UserDefaults.standard.set(Array(done.union(due.map(\.defID))), forKey: Self.levelCardsKey)
        Task {
            for r in due { state = await store.grantCard(defID: r.defID, roll: CardCatalog.roll("level|" + r.defID)) }
        }
    }

    private func grantCollections(_ done: [ArtifactCollection]) {
        for c in done { SeasonModel.shared.grantOwned(c.rewardID) }
    }

    func refreshAuctions() async {
        guard let p = purse?() else { return }
        apply(await market.refresh(cash: p.cash, priceLevel: p.priceLevel))
    }

    private func apply(_ snap: AuctionsSnapshot) {
        auctions = snap
        state = snap.state
        for s in snap.settled {
            grantCollections(s.completed)
            if s.cash != 0 { cashHandler?(s.cash, s.auctionID + "|" + s.status.rawValue, cashLabel(for: s)) }
            notes.append(note(for: s))
        }
    }

    private func pieceName(_ s: AuctionSettlement) -> String {
        (ArtifactCatalog.def(s.item.defID)?.name ?? "Piece") + ", " + ArtifactCatalog.label(s.item)
    }

    private func cashLabel(for s: AuctionSettlement) -> String {
        (s.seller == GoldVault.meID ? "Auction sale: " : "Auction purchase: ") + (ArtifactCatalog.def(s.item.defID)?.name ?? "artifact")
    }

    private func note(for s: AuctionSettlement) -> String {
        let piece: String = pieceName(s)
        let youSold: Bool = s.seller == GoldVault.meID
        switch s.status {
        case .sold where youSold:
            return "Sold: \(piece) for \(money(s.price)). After the \(money(s.fee)) fee you received \(money(s.price - s.fee))."
        case .sold:
            return "Won: \(piece) for \(money(s.price)). It is in your cabinet."
        case .unsold where youSold:
            return "Not sold: \(piece). It is back in your cabinet."
        default:
            return "Ended: \(piece)."
        }
    }

    func clearNotes() { notes = [] }

    @discardableResult
    func bid(_ auctionID: String, amount: Int) async -> Bool {
        problem = nil
        guard let p = purse?() else { problem = "Open a game to bid."; return false }
        do { apply(try await market.placeBid(auctionID: auctionID, amount: amount, cash: p.cash)); return true } catch { problem = message(error); return false }
    }

    @discardableResult
    func buyNow(_ auctionID: String) async -> Bool {
        problem = nil
        guard let p = purse?() else { problem = "Open a game to buy."; return false }
        do { apply(try await market.buyNow(auctionID: auctionID, cash: p.cash)); return true } catch { problem = message(error); return false }
    }

    @discardableResult
    func list(itemID: String, startPrice: Int, reserve: Int?, buyNow: Int?, duration: AuctionDuration) async -> Bool {
        problem = nil
        do { apply(try await market.list(itemID: itemID, startPrice: startPrice, reserve: reserve, buyNow: buyNow, duration: duration)); return true } catch { problem = message(error); return false }
    }

    @discardableResult
    func cancel(_ auctionID: String) async -> Bool {
        problem = nil
        do { apply(try await market.cancel(auctionID: auctionID)); return true } catch { problem = message(error); return false }
    }

    func name(of playerID: String) -> String { auctions?.names[playerID] ?? "A player" }
}
