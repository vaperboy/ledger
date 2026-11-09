import Foundation
import Observation
import Simulation

/// The player's store state for the views: gold, box stock, cabinet and the auctions, kept up to date from the services.
/// Shared, because the Season Pass hands out boxes and gold from outside the store screens. Cosmetics won or bought go to the
/// wardrobe (`SeasonModel`), where the player picks what to wear.
@MainActor @Observable
final class StoreSession {
    static let shared = StoreSession()

    private(set) var state = StoreState()
    private(set) var auctions: AuctionsSnapshot?
    private(set) var loaded = false
    /// One plain line for the screen that started the last call.
    var problem: String?
    /// What happened to the player's auctions since they last looked, one line each.
    private(set) var notes: [String] = []

    /// Set by the game store: pays a box's cash prize (reference-economy amount, the opening's id) into the running game.
    @ObservationIgnored var moneyPrizeHandler: ((Int, String) -> Void)?
    @ObservationIgnored private let store: any StoreService
    @ObservationIgnored private let market: any AuctionService

    init() {
        let backend = StoreBackend.make()
        store = backend.store
        market = backend.auctions
    }

    var isVisualOnly: Bool { store.isVisualOnly }
    var gold: Int { state.wallet.balance }
    var available: Int { state.wallet.available }

    func load() async {
        state = await store.state()
        loaded = true
    }

    private func message(_ error: Error) -> String { (error as? LocalizedError)?.errorDescription ?? "That did not work. Try again." }

    // MARK: Gold and the store

    @discardableResult
    func buyPack(_ pack: GoldPack) async -> Bool {
        problem = nil
        do { state = try await store.buyPack(pack.id); return true } catch { problem = message(error); return false }
    }

    @discardableResult
    func buySeasonBundle() async -> Bool {
        problem = nil
        do { state = try await store.buySeasonBundle(); return true } catch { problem = message(error); return false }
    }

    @discardableResult
    func buyBoxBundle(_ bundle: BoxBundle, paidBoxesAllowed: Bool) async -> Bool {
        problem = nil
        do { state = try await store.buyBoxBundle(bundle.id, paidBoxesAllowed: paidBoxesAllowed); return true } catch { problem = message(error); return false }
    }

    @discardableResult
    func buyCosmetic(_ c: GoldCosmetic) async -> Bool {
        problem = nil
        do {
            state = try await store.buyCosmetic(c.id, owned: SeasonModel.shared.pass.owned)
            SeasonModel.shared.grantOwned(c.id)
            return true
        } catch { problem = message(error); return false }
    }

    @discardableResult
    func buyAvatar(_ d: AvatarDef) async -> Bool {
        problem = nil
        do {
            state = try await store.buyAvatar(d.id, owned: AvatarModel.shared.owned)
            AvatarModel.shared.grant(d.id)
            return true
        } catch { problem = message(error); return false }
    }

    /// Opens a box (from the stock, else paid for in gold) and puts its prizes where they belong. Nil with `problem` set on failure.
    func openBox(_ kind: BoxKind, paidBoxesAllowed: Bool) async -> BoxOpening? {
        problem = nil
        do {
            let out = try await store.openBox(kind, owned: SeasonModel.shared.pass.owned, paidBoxesAllowed: paidBoxesAllowed)
            state = out.state
            if case .cosmetic(let id) = out.result.content { SeasonModel.shared.grantOwned(id) }
            if case .money(let amount) = out.result.content { moneyPrizeHandler?(amount, UUID().uuidString) }
            grantCollections(out.completed)
            return out
        } catch { problem = message(error); return nil }
    }

    /// Boxes and gold from a claimed Season Pass reward.
    func receiveSeason(_ r: SeasonReward) {
        guard r.kind == .box || r.kind == .gold else { return }
        Task { state = await store.grantFromSeason(boxes: r.kind == .box ? r.amount : 0, gold: r.kind == .gold ? r.amount : 0) }
    }

    private func grantCollections(_ done: [ArtifactCollection]) {
        for c in done { SeasonModel.shared.grantOwned(c.rewardID) }
    }

    // MARK: Auctions

    func refreshAuctions() async {
        let snap = await market.refresh()
        apply(snap)
    }

    private func apply(_ snap: AuctionsSnapshot) {
        auctions = snap
        state = snap.state
        for s in snap.settled {
            grantCollections(s.completed)
            notes.append(note(for: s, names: snap.names))
        }
    }

    private func note(for s: AuctionSettlement, names: [String: String]) -> String {
        let piece: String = (ArtifactCatalog.def(s.item.defID)?.name ?? "Piece") + ", " + ArtifactCatalog.label(s.item)
        let youSold: Bool = s.seller == GoldVault.meID
        switch s.status {
        case .sold where youSold:
            return "Sold: \(piece) for \(s.price) gold. After the \(s.fee) gold fee you received \(s.price - s.fee)."
        case .sold:
            return "Won: \(piece) for \(s.price) gold. It is in your cabinet."
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
        do { apply(try await market.placeBid(auctionID: auctionID, amount: amount)); return true } catch { problem = message(error); return false }
    }

    @discardableResult
    func list(itemID: String, startPrice: Int, reserve: Int?, duration: AuctionDuration) async -> Bool {
        problem = nil
        do { apply(try await market.list(itemID: itemID, startPrice: startPrice, reserve: reserve, duration: duration)); return true } catch { problem = message(error); return false }
    }

    @discardableResult
    func cancel(_ auctionID: String) async -> Bool {
        problem = nil
        do { apply(try await market.cancel(auctionID: auctionID)); return true } catch { problem = message(error); return false }
    }

    func name(of playerID: String) -> String { auctions?.names[playerID] ?? "A player" }
}
