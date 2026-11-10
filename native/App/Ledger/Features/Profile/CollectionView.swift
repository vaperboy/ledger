import SwiftUI
import Simulation

struct CollectionView: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @ObservedObject private var season = SeasonModel.shared
    @ObservedObject private var avatars = AvatarModel.shared
    private let session = StoreSession.shared

    var body: some View {
        let cabinet: Cabinet = session.state.cabinet
        let auctionsOpen: Bool = StoreGate.access(countryCode: online.profile?.countryCode) != .hidden
        PhonePageScroll(spacing: Theme.Space.l) {
            equipped
            OnlineGroup(title: "", footer: auctionsOpen ? "Sell artifacts you own at once, or at auction, or bid on other players' pieces, in cash." : "Auctions are not offered where you are.") {
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
        .appScreen(title: "Collection", subtitle: "Cosmetics, artifacts and auctions")
        .task { await session.load() }
    }

    private var equipped: some View {
        OnlineGroup(title: "Equipped", footer: "Equip the cosmetics you own, with a preview, in Your look.") {
            NavigationLink { LookView() } label: {
                VStack(spacing: 0) {
                    EquippedSummary(look: season.pass.equipped, avatar: avatars.equipped)
                    Hairline()
                    HStack {
                        Text("Change look").textStyle(.body, tint: Theme.accent, weight: .semibold)
                        Spacer()
                        LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
                    }
                    .frame(minHeight: 48)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("collection-look")
        }
    }
}
