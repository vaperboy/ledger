import SwiftUI
import Simulation

struct CollectionView: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @AppStorage(AgeConfirmation.key) private var adult = false
    private let session = StoreSession.shared

    var body: some View {
        let cabinet: Cabinet = session.state.cabinet
        let auctionsOpen: Bool = adult && StoreGate.access(countryCode: online.profile?.countryCode) != .hidden
        PhonePageScroll(spacing: Theme.Space.l) {
            OnlineGroup(title: "", footer: auctionsOpen ? "Sell artifacts you own, or bid on other players' pieces, in gold." : "Auctions are for players aged 18 or older.") {
                NavigationLink { CabinetView() } label: {
                    OnlineLine(glyph: Glyph.luxury, title: "Artifacts", note: cabinet.items.count == 1 ? "1 piece and your collections" : "\(cabinet.items.count) pieces and your collections", chevron: true)
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("collection-artifacts")
                if auctionsOpen {
                    Hairline()
                    if store.levelOpen(.auctions) {
                        NavigationLink { AuctionsApp() } label: {
                            OnlineLine(glyph: Glyph.market, title: "Auctions", note: "Bid on artifacts or sell your own", chevron: true)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("collection-auctions")
                    } else {
                        LevelLockRow(feature: .auctions)
                    }
                }
            }
        }
        .appScreen(title: "Collection", subtitle: "Artifacts and auctions")
        .task { await session.load() }
    }
}
