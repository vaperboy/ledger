import SwiftUI
import Businesses
import Simulation

enum OnlineDirectoryCache {
    nonisolated(unsafe) static var players: [PlayerProfile] = []

    static func refresh(from service: any OnlineService) async {
        let mock: MockOnlineService = (service as? MockOnlineService) ?? OnlineBackend.standIn
        players = await mock.visibleDirectory()
        await StartupMarketStore.shared.attach(mock)
    }

    static func playerCompanies() -> [RealCompany] {
        players.flatMap { (p: PlayerProfile) -> [RealCompany] in
            (p.companies ?? []).map { (c: OnlineCompany) -> RealCompany in
                let size: Double
                switch c.health { case .thriving: size = 1.3; case .growing: size = 1.1; case .steady: size = 1; case .struggling: size = 0.7; case .new: size = 0.6 }
                return RealCompany(name: c.name, owner: p.displayName, trade: c.trade, city: c.city, countryCode: c.countryCode, size: size)
            }
        }
    }
}

extension GameStore {
    @MainActor func syncPlayerCompanies() {
        let list = OnlineDirectoryCache.playerCompanies()
        guard !list.isEmpty else { return }
        _ = act { $0.setPlayerCompanies(list) }
    }
}

struct OnlinePlayersAdapter: SupplyMarketPlayers {
    func players() -> [SupplyMarketPlayer] {
        OnlineDirectoryCache.players.map { p in
            let company: OnlineCompany? = p.companies?.first
            return SupplyMarketPlayer(ownerID: p.id, ownerName: p.displayName, profileCode: p.code,
                                      companyName: company?.name ?? "\(p.displayName) Supplies", tradeID: company?.trade ?? "",
                                      city: company?.city ?? "", region: p.countryCode, linkKey: p.id, isFriend: p.relation == .friend, country: p.countryCode)
        }
    }
}

struct PlayerProfileByCode: View {
    var code: String
    @Environment(OnlineSession.self) private var online
    @State private var id: String?

    var body: some View {
        Group {
            if let id { PlayerProfileView(playerID: id) } else { ProgressView().tint(Theme.inkSoft) }
        }
        .task { id = try? await online.service.profile(code: code).id }
    }
}

enum OnlineWiring {
    @MainActor static func install() {
        SupplyMarketPlayersSource.provider = OnlinePlayersAdapter()
        SupplierOwnerProfileHook.destination = { code in AnyView(PlayerProfileByCode(code: code)) }
        JointVentureCoordinator.shared.attach(OnlineBackend.shared)
    }
}
