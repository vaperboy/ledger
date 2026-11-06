import SwiftUI
import GameCore
import Countries
import Businesses
import Events
import Simulation

/// The Ventures phone app, drawn as a startup feed: your stakes in other founders' startups come as posts, with Help the team. The other kinds of
/// venture (your own startups, funds, group stakes, software) sit below the feed in the existing `VenturesContent`. Buying and selling stakes
/// is not done here: selling and ownership live in Group > Ownership.
/// Engine calls: `startupStakes`, `helpStartupOnBoard`.
struct VenturesFeedApp: View {
    private var P: OutsidePalette { .ventures }
    @EnvironmentObject var store: GameStore
    @State private var pending: PendingAction?
    /// Inside the merged Ventures screen (Projects tab): no header, back button or scroll view of its own.
    var embedded = false

    var body: some View {
        if let e = store.engine {
            let cur = e.homeCurrency
            if embedded {
                VStack(alignment: .leading, spacing: 14) {
                    stakes(e, cur)
                    feedLabel("More ventures", note: "")
                    VenturesContent(hidesBacking: true)
                }
                .environment(\.outsidePalette, P)
                .confirmAction($pending)
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(e, cur)
                    stakes(e, cur)
                    feedLabel("More ventures", note: "")
                    VenturesContent(hidesBacking: true)
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 20)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).noSidewaysDrag()
            .outsideScreen(P)
            .confirmAction($pending)
            .accessibilityIdentifier("ventures-app")
            }
        }
    }

    // MARK: Header

    private func header(_ e: GameEngine, _ cur: Currency) -> some View {
        let held: [Startups.Stake] = e.startupStakes.filter { $0.live }
        let value: Double = held.reduce(0) { $0 + $1.value }
        return HStack(alignment: .center, spacing: 12) {
            OutsideBack()
            VStack(alignment: .leading, spacing: 1) {
                Text("Ventures").font(.serifTitle(26)).foregroundStyle(P.ink).accessibilityAddTraits(.isHeader)
                Text(held.isEmpty ? "Founders looking for money" : "\(held.count) backed · " + cur.tidyShort(value) + " at paper value")
                    .font(.system(size: 12.5)).foregroundStyle(P.inkSoft)
            }
            Spacer(minLength: 0)
        }
    }

    private func feedLabel(_ title: String, note: String) -> some View {
        HStack {
            Text(title.uppercased()).capsLabel()
            Spacer()
            if !note.isEmpty { Text(note).font(.system(size: 11)).foregroundStyle(P.inkFaint) }
        }
        .padding(.top, 4)
    }

    // MARK: Logo

    private func logo(_ name: String, _ sector: String) -> some View {
        ThumbnailView(kind: .trade, key: sector, size: 46, shape: .square, glyph: Glyph.ventures, initials: name)
    }

    // MARK: Stakes as posts

    @ViewBuilder private func stakes(_ e: GameEngine, _ cur: Currency) -> some View {
        let list: [Startups.Stake] = e.startupStakes
        if !list.isEmpty {
            feedLabel("Your portfolio", note: "\(list.filter { $0.live }.count) live")
            ForEach(list) { (st: Startups.Stake) in stakePost(st, cur) }
        }
    }

    private func stakePost(_ st: Startups.Stake, _ cur: Currency) -> some View {
        let gain: Double = st.value - st.invested
        let status: String = st.live ? st.stageName : (st.failed ? "Failed" : "Sold")
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                logo(st.name, st.sector)
                VStack(alignment: .leading, spacing: 2) {
                    Text(st.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(P.ink)
                    Text("\(st.sector) · \(status) · \(String(format: "%.1f", st.ownership))%" + (st.boardSeat ? " · board seat" : ""))
                        .font(.system(size: 11.5)).foregroundStyle(P.inkFaint)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(cur.tidyShort(st.value)).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(P.ink)
                    Text((gain >= 0 ? "▲ +" : "▼ −") + cur.tidyShort(abs(gain))).font(.system(size: 11).monospacedDigit()).foregroundStyle(P.change(gain))
                }
            }
            if st.live { stakeActions(st, cur) }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(P.line, lineWidth: 1))
    }

    private func stakeActions(_ st: Startups.Stake, _ cur: Currency) -> some View {
        HStack(spacing: 8) {
            if st.boardSeat {
                Button("Help the team") {
                    let ok = store.act { $0.helpStartupOnBoard(stakeID: st.id) } ?? false
                    store.show(ok ? "You spent time with the team." : "You helped recently.", tone: ok ? "good" : "n")
                }.buttonStyle(GreyOutlineButtonStyle())
            }
        }
    }
}
