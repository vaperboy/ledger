import SwiftUI
import Simulation

struct CollectionView: View {
    @ObservedObject private var season = SeasonModel.shared
    @ObservedObject private var avatars = AvatarModel.shared
    private let session = StoreSession.shared

    var body: some View {
        let cabinet: Cabinet = session.state.cabinet
        PhonePageScroll(spacing: Theme.Space.l) {
            equipped
            OnlineGroup(title: "", footer: "Sell artifacts and cards at once, or at auction in the Auctions app, in cash.") {
                NavigationLink { CabinetView() } label: {
                    OnlineLine(glyph: Glyph.luxury, title: "Artifacts and cards", note: cabinet.items.count == 1 ? "1 piece and your collections" : "\(cabinet.items.count) pieces and your collections", chevron: true)
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("collection-artifacts")
            }
        }
        .appScreen(title: "Collection", subtitle: "Cosmetics, artifacts and cards")
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
