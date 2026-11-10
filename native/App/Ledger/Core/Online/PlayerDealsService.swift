import Foundation
import GameCore
import Countries
import Businesses
import Events
import Simulation

enum PlayerDealsEvent: Equatable {
    case applicant(companyID: Int, PlayerDeals.PlayerApplicant)
    case buyerOffer(companyID: Int, buyer: CompanySale.PlayerBuyer, price: Double)
}

protocol PlayerDealsService: AnyObject {
    var onChange: (() -> Void)? { get set }
    var buyerLinkKeys: Set<String> { get }

    func franchiseOffers(today: Int) -> [PlayerDeals.FranchiseListing]
    func companyOffers(today: Int) -> [PlayerDeals.CompanyListing]
    func makeOffer(listingID: String, price: Double, round: Int, today: Int) -> PlayerDeals.Reply
    func soldToPlayer(listingID: String)

    func publish(franchise: PlayerDeals.FranchiseListing)
    func withdrawFranchise(companyID: Int)
    func publish(company: PlayerDeals.CompanyListing)
    func withdrawCompany(companyID: Int)

    func advance(today: Int) -> [PlayerDealsEvent]
}

@MainActor final class PlayerDealsStore: ObservableObject {
    static let shared = PlayerDealsStore()

    @Published private(set) var revision = 0
    var service: PlayerDealsService {
        didSet { service.onChange = { [weak self] in self?.touch() }; touch() }
    }

    init(service: PlayerDealsService = MockPlayerDealsService()) {
        self.service = service
        service.onChange = { [weak self] in self?.touch() }
    }

    private func touch() { DispatchQueue.main.async { [weak self] in self?.revision += 1 } }

    private struct Me { var id = "me"; var name: String; var code = "YOU"; var link = "me" }

    func sync(_ store: GameStore) {
        guard let e = store.engine else { return }
        let me = Me(name: e.state.player.name)
        let today: Int = PlayerDeals.today(e.state)
        for co in e.state.companies {
            if co.status.isLive, let l = e.franchiseListing(companyID: co.id, ownerID: me.id, ownerName: me.name, profileCode: me.code, linkKey: me.link) {
                service.publish(franchise: l)
            } else {
                service.withdrawFranchise(companyID: co.id)
            }
            if co.status.isLive, e.playerSaleUntil(companyID: co.id) != nil,
               let l = e.companyListing(companyID: co.id, ownerID: me.id, ownerName: me.name, profileCode: me.code, linkKey: me.link, askPrice: Self.asking(e, co.id)) {
                service.publish(company: l)
            } else {
                service.withdrawCompany(companyID: co.id)
            }
        }
        for ev in service.advance(today: today) {
            switch ev {
            case .applicant(let id, var a):
                if a.cityID.isEmpty, let co = e.state.company(id) {
                    let cities = e.data.countries.resolve(co.countryCode, orHome: e.state.homeCountryCode).cities
                    if !cities.isEmpty { a.cityID = cities[(Int(a.profileCode.dropFirst()) ?? 0) % cities.count].id }
                }
                _ = store.act { $0.addFranchiseApplicant(companyID: id, applicant: a) }
            case .buyerOffer(let id, let b, let price):
                _ = store.act { $0.addPlayerSaleOffer(companyID: id, buyer: b, price: price) }
            }
        }
    }

    static func asking(_ e: GameEngine, _ companyID: Int) -> Double {
        max(1000, (e.companyAskingValue(companyID: companyID) * 1.15 / 1000).rounded() * 1000)
    }

    func franchiseOffers(_ e: GameEngine) -> [PlayerDeals.FranchiseListing] {
        let today: Int = PlayerDeals.today(e.state)
        return service.franchiseOffers(today: today).filter { $0.isOpen(today: today) && FranchiseBrands.isFranchisable($0.tradeID) }
            .map { (l: PlayerDeals.FranchiseListing) -> PlayerDeals.FranchiseListing in
                var x = l
                if x.countryCode.isEmpty { x.countryCode = e.state.homeCountryCode }
                return x
            }
            .sorted { $0.strength != $1.strength ? $0.strength > $1.strength : $0.id < $1.id }
    }

    func companyOffers(_ e: GameEngine) -> [PlayerDeals.CompanyListing] {
        let today: Int = PlayerDeals.today(e.state)
        return service.companyOffers(today: today).filter { $0.isOpen(today: today) && e.data.catalog[$0.tradeID] != nil }.map { (l: PlayerDeals.CompanyListing) -> PlayerDeals.CompanyListing in
            var x = l
            if x.countryCode.isEmpty { x.countryCode = e.state.homeCountryCode }
            if x.cityID.isEmpty { x.cityID = e.state.player.cityID }
            return x
        }.sorted { $0.askPrice != $1.askPrice ? $0.askPrice < $1.askPrice : $0.id < $1.id }
    }
}
