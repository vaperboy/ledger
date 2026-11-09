import SwiftUI

/// The sample players the supply market reads, refreshed from the online service when the app starts.
enum OnlineDirectoryCache {
    nonisolated(unsafe) static var players: [PlayerProfile] = []

    static func refresh(from service: any OnlineService) async {
        guard let mock = service as? MockOnlineService else { return }
        players = await mock.visibleDirectory()
        await StartupMarketStore.shared.attach(mock)
    }
}

/// Maps online players to suppliers: the first visible company decides the trade, an owner with none visible gets a trade that supplies.
struct OnlinePlayersAdapter: SupplyMarketPlayers {
    func players() -> [SupplyMarketPlayer] {
        OnlineDirectoryCache.players.map { p in
            let company: OnlineCompany? = p.companies?.first
            return SupplyMarketPlayer(ownerID: p.id, ownerName: p.displayName, profileCode: p.code,
                                      companyName: company?.name ?? "\(p.displayName) Supplies", tradeID: company?.trade ?? "",
                                      city: company?.city ?? "", region: p.countryCode, linkKey: p.id, isFriend: p.relation == .friend)
        }
    }
}

/// Opens a supplier owner's profile from their profile code.
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
    }
}
