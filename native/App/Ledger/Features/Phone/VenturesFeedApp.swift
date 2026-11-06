import SwiftUI
import GameCore
import Countries
import Businesses
import Events
import Simulation

/// Ventures, portfolio first: what your ventures are worth, the stakes you hold in other founders' startups (with Help the team), then the
/// kinds of venture to start or manage (your own startups, funds, group stakes, software) in `VenturesContent`. Inside the Ventures tab it
/// takes the game's own colours; as a standalone phone app it keeps the Ventures palette. Buying and selling stakes is not done here:
/// selling and ownership live in Group > Ownership.
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
                content(e, cur)
                    .confirmAction($pending)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.xl) {
                        header(e, cur)
                        content(e, cur)
                    }
                    .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.xl)
                    .frame(maxWidth: 640).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden).noSidewaysDrag()
                .outsideScreen(P)
                .confirmAction($pending)
                .accessibilityIdentifier("ventures-app")
            }
        }
    }

    /// Portfolio (value, then the stakes held), then the ventures to start or manage.
    private func content(_ e: GameEngine, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VenturesSummary(engine: e)
            stakes(e, cur)
            VenturesContent(hidesBacking: true)
        }
    }

    // MARK: Header

    private func header(_ e: GameEngine, _ cur: Currency) -> some View {
        let held: [Startups.Stake] = e.startupStakes.filter { $0.live }
        let value: Double = held.reduce(0) { $0 + $1.value }
        return HStack(alignment: .center, spacing: Theme.Space.s) {
            OutsideBack()
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("Ventures").textStyle(.title).accessibilityAddTraits(.isHeader)
                Text(held.isEmpty ? "Founders looking for money" : "\(held.count) backed · " + cur.tidyShort(value) + " at paper value")
                    .textStyle(.caption)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Stakes held

    @ViewBuilder private func stakes(_ e: GameEngine, _ cur: Currency) -> some View {
        let list: [Startups.Stake] = e.startupStakes
        if !list.isEmpty {
            LedgerSection(title: "Startups you back", trailing: { Text("\(list.filter { $0.live }.count) live").textStyle(.caption) }) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { (n: Int, st: Startups.Stake) in
                        if n > 0 { Hairline() }
                        stakeRow(st, cur)
                    }
                }
            }
        }
    }

    private func stakeRow(_ st: Startups.Stake, _ cur: Currency) -> some View {
        let gain: Double = st.value - st.invested
        let status: String = st.live ? st.stageName : (st.failed ? "Failed" : "Sold")
        return VStack(alignment: .leading, spacing: 0) {
            LedgerRow(leading: .thumb(ThumbSpec(kind: .trade, key: st.sector, glyph: Glyph.ventures, initials: st.name, shape: .square)),
                      title: st.name,
                      subtitle: "\(st.sector) · \(status) · \(String(format: "%.1f", st.ownership))%" + (st.boardSeat ? " · board seat" : ""),
                      value: cur.tidyShort(st.value),
                      valueNote: (gain >= 0 ? "+" : "−") + cur.tidyShort(abs(gain)) + " on \(cur.tidyShort(st.invested))",
                      valueNoteTint: Theme.change(gain))
            if st.live && st.boardSeat {
                Button("Help the team") {
                    let ok = store.act { $0.helpStartupOnBoard(stakeID: st.id) } ?? false
                    store.show(ok ? "You spent time with the team." : "You helped recently.", tone: ok ? "good" : "n")
                }
                .buttonStyle(SecondaryButtonStyle(size: .compact))
                .padding(.bottom, Theme.Space.s)
            }
        }
    }
}
