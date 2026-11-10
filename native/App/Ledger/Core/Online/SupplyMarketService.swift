import Foundation
import SwiftUI
import Businesses
import Events
import Simulation

struct SupplyMarketPlayer: Equatable {
    var ownerID: String
    var ownerName: String
    var profileCode: String
    var companyName: String
    var tradeID: String
    var city: String
    var region: String
    var linkKey: String
    var isFriend: Bool
    var country: String = ""
}

protocol SupplyMarketPlayers {
    func players() -> [SupplyMarketPlayer]
}

enum SupplyMarketPlayersSource {
    nonisolated(unsafe) static var provider: SupplyMarketPlayers?
}

enum SupplierOwnerProfileHook {
    nonisolated(unsafe) static var destination: ((String) -> AnyView)?
}

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
    var unitValue: Double = 0
    var country: String = ""
}

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

enum SupplyMarketEvent: Equatable {
    case sale(companyID: Int, units: Int, unitPrice: Double, unitCost: Double)
    case shortDelivery(listingID: String)
    case delivery(listingID: String, promised: Int, delivered: Int, orders: Int, late: Int)
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
    var onChange: (() -> Void)? { get set }

    func listings(lineID: String) -> [SupplyListing]
    func listing(_ id: String) -> SupplyListing?
    func profile(ownerID: String) -> SupplierProfile?
    func knownSuppliers() -> Set<String>
    func setKnown(ownerID: String, _ known: Bool)
    func contract(buyerCompanyID: Int, lineID: String) -> SupplyContract?
    func sign(buyerCompanyID: Int, lineID: String, listingID: String, unitsPerWeek: Int, today: Int) -> SupplySignResult
    func endContract(buyerCompanyID: Int, lineID: String)
    func reserve(listingID: String, units: Int, today: Int) -> String?
    var buyerLinkKeys: Set<String> { get }
    func randomPick(lineID: String, units: Int, today: Int, seed: String, excluding: Set<String>) -> SupplyListing?
    func wellKnown(lineID: String, units: Int, today: Int) -> [SupplyListing]

    var ownerID: String { get }
    func restore(contracts: [SupplyContract], listings: [SupplyListing], orders: [String: [SupplyOrder]], unitValues: [String: Double])
    func ownSnapshot() -> (listings: [SupplyListing], orders: [String: [SupplyOrder]])

    func myListings(companyID: Int) -> [SupplyListing]
    func saveListing(_ draft: ListingDraft, today: Int) -> ListingSaveResult
    func setPaused(listingID: String, _ paused: Bool)
    func stopListing(listingID: String)
    func orders(listingID: String) -> [SupplyOrder]
    func openContractsAsSupplier(ownerID: String) -> Int

    func advance(today: Int, liveCompanyIDs: Set<Int>) -> [SupplyMarketEvent]
    func supplierStopped(ownerID: String, reason: SupplyEnd) -> [SupplyFallback]
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

    static func today(_ e: GameEngine) -> Int { e.state.week * 7 + e.state.day }

    private func hydrate(_ e: GameEngine) {
        guard hydratedFor != e.state.seed else { return }
        hydratedFor = e.state.seed
        let listings: [SupplyListing] = e.playerSupplyListings
        var values: [String: Double] = [:]
        for l in listings { if let co = l.companyID.flatMap({ e.state.company($0) }) { values[l.id] = SupplyMarketBooks.unitValue(co) } }
        service.restore(contracts: e.playerSupplyContracts, listings: listings, orders: e.playerSupplyOrders.mapValues { $0.map { SupplyOrder($0) } }, unitValues: values)
    }

    private func persist(_ g: GameStore) {
        guard let e = g.engine, hydratedFor == e.state.seed else { return }
        let snap = service.ownSnapshot()
        let orders: [String: [SupplyOrderRecord]] = snap.orders.mapValues { $0.map { $0.record } }
        if snap.listings == e.playerSupplyListings && orders == e.playerSupplyOrders { return }
        _ = g.act { $0.savePlayerListings(snap.listings, orders: orders) }
    }

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
            case .delivery(let listingID, let promised, let delivered, let orders, let late):
                _ = store.act { $0.reportSupplyDelivery(listingID: listingID, promised: promised, delivered: delivered, orders: orders, late: late) }
            case .shortDelivery(let listingID):
                _ = store.act { $0.reportShortDelivery(listingID: listingID) }
            case .supplierEnded(let f):
                fallBack(store, f)
            }
        }
        persist(store)
    }

    private func stopGoneCompanies(_ store: GameStore, _ e: GameEngine) {
        let ids = Set(service.ownSnapshot().listings.compactMap { $0.companyID })
        for id in ids.sorted() where e.state.company(id)?.status != .open {
            let reason: SupplyEnd = e.state.company(id)?.status == .bust ? .bankrupt : .stopped
            for f in service.companyStopped(companyID: id, reason: reason) { fallBack(store, f) }
        }
    }

    func accountDeleted(_ store: GameStore) {
        for f in service.supplierStopped(ownerID: service.ownerID, reason: .accountDeleted) { fallBack(store, f) }
        persist(store)
    }

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

    func end(_ store: GameStore, companyID: Int, lineID: String) {
        service.endContract(buyerCompanyID: companyID, lineID: lineID)
        _ = store.act { $0.endPlayerSupplier(companyID: companyID, lineID: lineID) }
        returnToHouse(store, companyID: companyID, lineID: lineID)
    }

    func fallBack(_ store: GameStore, _ f: SupplyFallback) {
        _ = store.act { $0.applySupplierFallback(f) }
        returnToHouse(store, companyID: f.contract.buyerCompanyID, lineID: f.contract.lineID)
        store.tell(f.title, f.body, tone: "bad")
    }

    func returnToHouse(_ store: GameStore, companyID: Int, lineID: String) {
        guard let e = store.engine,
              let row = e.supplyLines(companyID: companyID).flatMap({ $0.rows }).first(where: { $0.id == lineID }),
              let house = row.offers.first(where: { $0.detail == "Whoever the market offers" }), !house.isCurrent else { return }
        _ = store.act { $0.chooseSupply(companyID: companyID, change: house.change) }
    }

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
