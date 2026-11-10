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

enum SupplyMarketEvent: Equatable {
    case shortDelivery(listingID: String)
    case delivery(listingID: String, promised: Int, delivered: Int, orders: Int, late: Int)
    case supplierEnded(SupplyFallback)
}

enum SupplySignResult: Equatable {
    case signed(SupplyContract)
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
    func restore(contracts: [SupplyContract])
    func openContractsAsSupplier(ownerID: String) -> Int
    func demandPosts(today: Int) -> [DemandPost]

    func advance(today: Int) -> [SupplyMarketEvent]
    func supplierStopped(ownerID: String, reason: SupplyEnd) -> [SupplyFallback]
}

@MainActor final class SupplyMarketStore: ObservableObject {
    static let shared = SupplyMarketStore()

    @Published private(set) var revision = 0
    var service: SupplyMarketService {
        didSet { service.onChange = { [weak self] in self?.touch() }; hydratedFor = nil; touch() }
    }
    private var hydratedFor: Int?

    init(service: SupplyMarketService = MockSupplyMarketService()) {
        self.service = service
        service.onChange = { [weak self] in self?.touch() }
    }

    private func touch() {
        DispatchQueue.main.async { [weak self] in self?.revision += 1 }
    }

    static func today(_ e: GameEngine) -> Int { e.state.week * 7 + e.state.day }

    private func hydrate(_ e: GameEngine) {
        guard hydratedFor != e.state.seed else { return }
        hydratedFor = e.state.seed
        service.restore(contracts: e.playerSupplyContracts)
    }

    func sync(_ store: GameStore) {
        guard let e = store.engine else { return }
        hydrate(e)
        let today: Int = Self.today(e)
        for ev in service.advance(today: today) {
            switch ev {
            case .delivery(let listingID, let promised, let delivered, let orders, let late):
                _ = store.act { $0.reportSupplyDelivery(listingID: listingID, promised: promised, delivered: delivered, orders: orders, late: late) }
            case .shortDelivery(let listingID):
                _ = store.act { $0.reportShortDelivery(listingID: listingID) }
            case .supplierEnded(let f):
                fallBack(store, f)
            }
        }
        let posts: [DemandPost] = service.demandPosts(today: today)
        if posts != e.playerDemandPosts { _ = store.act { $0.savePlayerDemand(posts) } }
        let real: Int = realSuppliers()
        if Suppliers.realSuppliers(e.state) != real { _ = store.act { $0.setRealSuppliers(count: real) } }
        if FakePlayers.removed && !e.fakePlayersRemoved { _ = store.act { $0.removeFakePlayers() } }
    }

    func realSuppliers() -> Int {
        let lines: [String] = Array(Set(SupplyMarketCatalogue.supplies.values.flatMap { (l: [String]) -> [String] in l })).sorted()
        var owners: Set<String> = []
        for line in lines {
            for l in service.listings(lineID: line) where !FakePlayers.isFake(ownerID: l.ownerID) { owners.insert(l.ownerID) }
        }
        return owners.count
    }

    func accountDeleted(_ store: GameStore) {
        for f in service.supplierStopped(ownerID: service.ownerID, reason: .accountDeleted) { fallBack(store, f) }
    }

    func sign(_ store: GameStore, companyID: Int, lineID: String, listing: SupplyListing, units: Int, weeklyMarketSpend: Double) -> SupplySignResult {
        guard let e = store.engine else { return .refused("There is no game open.") }
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

    func end(_ store: GameStore, companyID: Int, lineID: String) -> String? {
        let r: SettingResult? = store.act { $0.cancelPlayerSupplier(companyID: companyID, lineID: lineID) }
        if case .refused(let why)? = r { return why }
        service.endContract(buyerCompanyID: companyID, lineID: lineID)
        returnToHouse(store, companyID: companyID, lineID: lineID)
        return nil
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
