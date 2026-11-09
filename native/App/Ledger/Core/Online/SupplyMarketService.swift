import Foundation
import SwiftUI
import Businesses
import Events
import Simulation

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
    /// The country code of the player's company; empty when unknown (treated as the buyer's own country).
    var country: String = ""
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
    /// The company's country code, so buyers abroad see freight and customs.
    var country: String = ""
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
    /// A supplier the player buys from delivered less than promised this week.
    case shortDelivery(listingID: String)
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
    func sign(buyerCompanyID: Int, lineID: String, listingID: String, unitsPerWeek: Int, today: Int) -> SupplySignResult
    func endContract(buyerCompanyID: Int, lineID: String)
    /// Takes `units` of the listing's capacity for a one-off order; nil when taken, else why not.
    func reserve(listingID: String, units: Int, today: Int) -> String?
    /// Keys of the player's own accounts, which cannot supply one another.
    var buyerLinkKeys: Set<String> { get }
    func randomPick(lineID: String, units: Int, today: Int, seed: String, excluding: Set<String>) -> SupplyListing?
    func wellKnown(lineID: String, units: Int, today: Int) -> [SupplyListing]

    /// The key the player's own listings carry as their owner.
    var ownerID: String { get }
    /// Puts back what the save holds: the player's contracts, their own listings and the recent orders on them.
    func restore(contracts: [SupplyContract], listings: [SupplyListing], orders: [String: [SupplyOrder]], unitValues: [String: Double])
    /// The player's own listings that still stand and their recent orders, for the save.
    func ownSnapshot() -> (listings: [SupplyListing], orders: [String: [SupplyOrder]])

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
    /// One of the player's companies goes bankrupt, is sold or closes: its listings stop and the contracts on them end at once.
    func companyStopped(companyID: Int, reason: SupplyEnd) -> [SupplyFallback]
}

extension SupplyOrder {
    init(_ r: SupplyOrderRecord) {
        self.init(id: r.id, listingID: r.listingID, buyerName: r.buyerName, units: r.units, delivered: r.delivered, late: r.late, day: r.day, revenue: r.revenue)
    }

    var record: SupplyOrderRecord {
        SupplyOrderRecord(id: id, listingID: listingID, buyerName: buyerName, units: units, delivered: delivered, late: late, day: day, revenue: revenue)
    }
}

/// Observable wrapper the screens watch, so they do not depend on which service stands behind it. It also keeps the service and the saved game in step:
/// the contracts and the player's own listings come from the save, every change goes back into it, and what the market reports reaches the books.
@MainActor final class SupplyMarketStore: ObservableObject {
    static let shared = SupplyMarketStore()

    @Published private(set) var revision = 0
    var service: SupplyMarketService {
        didSet { service.onChange = { [weak self] in self?.touch() }; hydratedFor = nil; touch() }
    }
    private weak var game: GameStore?
    private var hydratedFor: Int?

    init(service: SupplyMarketService = MockSupplyMarketService()) {
        self.service = service
        service.onChange = { [weak self] in self?.touch() }
    }

    private func touch() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.revision += 1
            if let g = self.game { self.persist(g) }
        }
    }

    /// The day count the market works in.
    static func today(_ e: GameEngine) -> Int { e.state.week * 7 + e.state.day }

    /// Loads the saved contracts and listings into the service once per game.
    private func hydrate(_ e: GameEngine) {
        guard hydratedFor != e.state.seed else { return }
        hydratedFor = e.state.seed
        let listings: [SupplyListing] = e.playerSupplyListings
        var values: [String: Double] = [:]
        for l in listings { if let co = l.companyID.flatMap({ e.state.company($0) }) { values[l.id] = SupplyMarketBooks.unitValue(co) } }
        service.restore(contracts: e.playerSupplyContracts, listings: listings, orders: e.playerSupplyOrders.mapValues { $0.map { SupplyOrder($0) } }, unitValues: values)
    }

    /// Writes the player's own listings and orders into the save when they differ from it.
    private func persist(_ g: GameStore) {
        guard let e = g.engine, hydratedFor == e.state.seed else { return }
        let snap = service.ownSnapshot()
        let orders: [String: [SupplyOrderRecord]] = snap.orders.mapValues { $0.map { $0.record } }
        if snap.listings == e.playerSupplyListings && orders == e.playerSupplyOrders { return }
        _ = g.act { $0.savePlayerListings(snap.listings, orders: orders) }
    }

    /// Brings the market up to today and applies what it reports to the books, the Inbox and the popup.
    func sync(_ store: GameStore) {
        guard let e = store.engine else { return }
        game = store
        hydrate(e)
        stopGoneCompanies(store, e)
        let live = Set(e.state.companies.filter { $0.status == .open }.map { $0.id })
        let events = service.advance(today: Self.today(e), liveCompanyIDs: live)
        for ev in events {
            switch ev {
            case .sale(let id, let units, let price, let cost):
                _ = store.act { $0.update { s, _, _ in _ = SupplyMarketBooks.settleSupply(&s, supplierCompanyID: id, buyerCompanyID: nil, units: units, unitPrice: price, unitCost: cost) } }
            case .shortDelivery(let listingID):
                _ = store.act { $0.reportShortDelivery(listingID: listingID) }
            case .supplierEnded(let f):
                fallBack(store, f)
            }
        }
        persist(store)
    }

    /// A company of the player's that went bankrupt, was sold or closed stops supplying: its listings end and so do the contracts on them.
    private func stopGoneCompanies(_ store: GameStore, _ e: GameEngine) {
        let ids = Set(service.ownSnapshot().listings.compactMap { $0.companyID })
        for id in ids.sorted() where e.state.company(id)?.status != .open {
            let reason: SupplyEnd = e.state.company(id)?.status == .bust ? .bankrupt : .stopped
            for f in service.companyStopped(companyID: id, reason: reason) { fallBack(store, f) }
        }
    }

    /// The player deleted the online account: their listings stop and any contract with them ends at once.
    func accountDeleted(_ store: GameStore) {
        for f in service.supplierStopped(ownerID: service.ownerID, reason: .accountDeleted) { fallBack(store, f) }
        persist(store)
    }

    // MARK: Contracts

    /// Signs the contract with the market and puts it into the company's books. When the books refuse (the trade has no use for it) the contract is undone.
    func sign(_ store: GameStore, companyID: Int, lineID: String, listing: SupplyListing, units: Int, weeklyMarketSpend: Double) -> SupplySignResult {
        guard let e = store.engine else { return .refused("There is no game open.") }
        game = store
        hydrate(e)
        let r = service.sign(buyerCompanyID: companyID, lineID: lineID, listingID: listing.id, unitsPerWeek: units, today: Self.today(e))
        guard case .signed(let c) = r else { return r }
        let current: SupplyListing = service.listing(listing.id) ?? listing
        let booked: Bool = store.act { $0.signPlayerSupplier(contract: c, listing: current, weeklyMarketSpend: weeklyMarketSpend) } ?? false
        guard booked else {
            service.endContract(buyerCompanyID: companyID, lineID: lineID)
            return .refused("This company cannot buy that from them.")
        }
        return r
    }

    /// Ends the contract on both sides; the line goes back to the House supplier.
    func end(_ store: GameStore, companyID: Int, lineID: String) {
        service.endContract(buyerCompanyID: companyID, lineID: lineID)
        _ = store.act { $0.endPlayerSupplier(companyID: companyID, lineID: lineID) }
        returnToHouse(store, companyID: companyID, lineID: lineID)
    }

    /// The contract is gone: the line goes back to a market supplier at market price, the Inbox says so, and one popup states what changed.
    func fallBack(_ store: GameStore, _ f: SupplyFallback) {
        _ = store.act { $0.endPlayerSupplier(companyID: f.contract.buyerCompanyID, lineID: f.contract.lineID) }
        returnToHouse(store, companyID: f.contract.buyerCompanyID, lineID: f.contract.lineID)
        _ = store.act { $0.update { s, _, _ in SupplyMarketBooks.tellBuyer(&s, fallback: f) } }
        store.tell(f.title, f.body, tone: "bad")
    }

    /// Puts a line back on a market supplier (the market offer of the existing Suppliers screen) when it is not already there.
    func returnToHouse(_ store: GameStore, companyID: Int, lineID: String) {
        guard let e = store.engine,
              let row = e.supplyLines(companyID: companyID).flatMap({ $0.rows }).first(where: { $0.id == lineID }),
              let house = row.offers.first(where: { $0.detail == "Whoever the market offers" }), !house.isCurrent else { return }
        _ = store.act { $0.chooseSupply(companyID: companyID, change: house.change) }
    }

    // MARK: One-off orders

    /// Orders stock from a player: the market takes the capacity, the books pay and the goods travel. Returns why it did not work, or nil.
    func order(_ store: GameStore, companyID: Int, listing: SupplyListing, units: Int) -> String? {
        guard let e = store.engine else { return "There is no game open." }
        if let why = service.reserve(listingID: listing.id, units: units, today: Self.today(e)) { return why }
        let r: Shipments.OrderResult = store.act { $0.orderFromSupplier(companyID: companyID, listing: listing, units: units) } ?? .badOrder
        switch r {
        case .ok: return nil
        case .noCash: return "The company cannot pay for it now."
        case .notOpen: return "The company is not open."
        default: return "This company cannot order that from them."
        }
    }
}
