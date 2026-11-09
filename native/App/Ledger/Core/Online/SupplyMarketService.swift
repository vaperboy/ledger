import Foundation
import SwiftUI
import Businesses

/// The supply market between players, as the app sees it: listings of real players, contracts, orders and the delivery record. The screens
/// talk only to this protocol; `MockSupplyMarketService` stands in for the server until the online service is wired.

/// One player as the market needs to know them. The lead wires `SupplyMarketPlayersSource.provider` to the online player list.
struct SupplyMarketPlayer: Equatable {
    var ownerID: String
    var ownerName: String
    var profileCode: String
    var companyName: String
    /// A trade id of the catalogue; one that supplies nothing is replaced by a trade that does.
    var tradeID: String
    var city: String
    var region: String
    /// Accounts of one owner (or otherwise linked) share a key.
    var linkKey: String
    var isFriend: Bool
}

protocol SupplyMarketPlayers {
    func players() -> [SupplyMarketPlayer]
}

enum SupplyMarketPlayersSource {
    /// Nil until wired; the stand-in then seeds its own suppliers.
    nonisolated(unsafe) static var provider: SupplyMarketPlayers?
}

/// The hook for the owner's profile page, provided by the online profile screen. Takes the profile code; nil until wired.
enum SupplierOwnerProfileHook {
    nonisolated(unsafe) static var destination: ((String) -> AnyView)?
}

/// What a listing draft says before it is saved.
struct ListingDraft: Equatable {
    var listingID: String?
    var companyID: Int
    var companyName: String
    var tradeID: String
    var lineID: String
    var priceTier: Int = 1
    var qualityTier: Int = 1
    var capacityPerWeek: Int = 50
    var leadDays: Int = 3
    var minOrder: Int = 10
    var termsDays: Int = 14
    var durationDays: Int = 7
    /// What one unit is worth at the company's own prices (the engine's wholesale value); the price tier moves it.
    var unitValue: Double = 0
}

/// A buyer's order on one of the player's listings.
struct SupplyOrder: Identifiable, Equatable {
    var id: String
    var listingID: String
    var buyerName: String
    var units: Int
    var delivered: Int
    var late: Bool
    var day: Int
    var revenue: Double
}

/// What the market asks the app to do to the single-player books after a week.
enum SupplyMarketEvent: Equatable {
    case sale(companyID: Int, units: Int, unitPrice: Double, unitCost: Double)
    case purchaseDifference(buyerCompanyID: Int, amount: Double)
    case supplierEnded(SupplyFallback)
}

enum SupplySignResult: Equatable {
    case signed(SupplyContract)
    case refused(String)
}

enum ListingSaveResult: Equatable {
    case saved(SupplyListing)
    case refused(String)
}

struct SupplierProfile: Equatable {
    var ownerID: String
    var ownerName: String
    var profileCode: String
    var isFriend: Bool
    var listings: [SupplyListing]
}

protocol SupplyMarketService: AnyObject {
    /// Called after anything changed, so the screens redraw.
    var onChange: (() -> Void)? { get set }

    // Buying
    func listings(lineID: String) -> [SupplyListing]
    func listing(_ id: String) -> SupplyListing?
    func profile(ownerID: String) -> SupplierProfile?
    func knownSuppliers() -> Set<String>
    func setKnown(ownerID: String, _ known: Bool)
    func contract(buyerCompanyID: Int, lineID: String) -> SupplyContract?
    func sign(buyerCompanyID: Int, lineID: String, listingID: String, unitsPerWeek: Int, weeklyMarketSpend: Double, today: Int) -> SupplySignResult
    func endContract(buyerCompanyID: Int, lineID: String)
    /// Keys of the player's own accounts, which cannot supply one another.
    var buyerLinkKeys: Set<String> { get }
    func randomPick(lineID: String, units: Int, today: Int, seed: String, excluding: Set<String>) -> SupplyListing?
    func wellKnown(lineID: String, units: Int, today: Int) -> [SupplyListing]

    // Supplying
    func myListings(companyID: Int) -> [SupplyListing]
    func saveListing(_ draft: ListingDraft, today: Int) -> ListingSaveResult
    func setPaused(listingID: String, _ paused: Bool)
    func stopListing(listingID: String)
    func orders(listingID: String) -> [SupplyOrder]
    /// Contracts the owner is bound by as a supplier; the account screens use it with `SupplyGuards.accountDeletion`.
    func openContractsAsSupplier(ownerID: String) -> Int

    // Time and events
    /// Works the market forward to today (at most a few weeks at once) and returns what changed for the player's books and buyers.
    func advance(today: Int, liveCompanyIDs: Set<Int>) -> [SupplyMarketEvent]
    /// A supplier goes bankrupt, deletes the account or stops: its contracts end at once.
    func supplierStopped(ownerID: String, reason: SupplyEnd) -> [SupplyFallback]
}

/// Observable wrapper the screens watch, so they do not depend on which service stands behind it.
final class SupplyMarketStore: ObservableObject {
    static let shared = SupplyMarketStore()

    @Published private(set) var revision = 0
    var service: SupplyMarketService {
        didSet { service.onChange = { [weak self] in self?.touch() }; touch() }
    }

    init(service: SupplyMarketService = MockSupplyMarketService()) {
        self.service = service
        service.onChange = { [weak self] in self?.touch() }
    }

    private func touch() { DispatchQueue.main.async { [weak self] in self?.revision += 1 } }

    /// The day count the market works in.
    static func today(_ e: GameEngine) -> Int { e.state.week * 7 + e.state.day }

    /// Brings the market up to today and applies what it reports to the books, the Inbox and the popup.
    func sync(_ store: GameStore) {
        guard let e = store.engine else { return }
        let live = Set(e.state.companies.filter { $0.status == .open }.map { $0.id })
        let events = service.advance(today: Self.today(e), liveCompanyIDs: live)
        for ev in events {
            switch ev {
            case .sale(let id, let units, let price, let cost):
                _ = store.act { $0.update { s, _, _ in _ = SupplyMarketBooks.bookSaleToPlayer(&s, supplierCompanyID: id, units: units, unitPrice: price, unitCost: cost) } }
            case .purchaseDifference(let id, let amount):
                _ = store.act { $0.update { s, _, _ in SupplyMarketBooks.bookPurchaseDifference(&s, buyerCompanyID: id, saving: amount) } }
            case .supplierEnded(let f):
                fallBack(store, f)
            }
        }
    }

    /// The contract is gone: the line goes back to the House supplier at market price, the Inbox says so, and one popup states what changed.
    func fallBack(_ store: GameStore, _ f: SupplyFallback) {
        returnToHouse(store, companyID: f.contract.buyerCompanyID, lineID: f.contract.lineID)
        _ = store.act { $0.update { s, _, _ in SupplyMarketBooks.tellBuyer(&s, fallback: f) } }
        store.tell(f.title, f.body, tone: "bad")
    }

    /// Puts a line back on the House supplier (the market offer of the existing Suppliers screen) when it is not already there.
    func returnToHouse(_ store: GameStore, companyID: Int, lineID: String) {
        guard let e = store.engine,
              let row = e.supplyLines(companyID: companyID).flatMap({ $0.rows }).first(where: { $0.id == lineID }),
              let house = row.offers.first(where: { $0.detail == "Whoever the market offers" }), !house.isCurrent else { return }
        _ = store.act { $0.chooseSupply(companyID: companyID, change: house.change) }
    }
}
