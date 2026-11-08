import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Events
import Simulation

/// Backing others: the stakes you hold in other founders' startups (help the team, sell part) and the pitches open to you now. A pitch opens
/// `BackStartupSheet`, which quotes the stake and asks before any money leaves.
struct VenturesBackingSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @Binding var open: String?
    @Binding var sheet: VentureSheet?
    @Binding var pending: PendingAction?

    var body: some View {
        let cur: Currency = engine.homeCurrency
        let stakes: [Startups.Stake] = engine.startupStakes
        let pitches: [Startups.Pitch] = engine.startupPitchesOnOffer
        let liveCount: Int = stakes.filter { (s: Startups.Stake) -> Bool in s.live }.count
        return LedgerSection(title: "Backing others", trailing: { if liveCount > 0 { Text("\(liveCount) live").textStyle(.caption, tint: Theme.inkFaint) } }) {
            VStack(alignment: .leading, spacing: 0) {
                if !stakes.isEmpty {
                    ForEach(Array(stakes.enumerated()), id: \.element.id) { item in
                        if item.offset > 0 { Hairline() }
                        stakeRow(item.element, cur)
                    }
                }
                Text("Pitches open now").capsLabel(Theme.inkFaint).padding(.top, stakes.isEmpty ? 0 : Theme.Space.m).padding(.bottom, Theme.Space.xs)
                if pitches.isEmpty {
                    EmptyState(glyph: Glyph.ventures, title: "No pitch is open", message: "Founders bring new pitches every few weeks. Back one with money for a share of it.", centered: false)
                        .padding(.vertical, Theme.Space.s)
                }
                ForEach(Array(pitches.enumerated()), id: \.element.id) { item in
                    if item.offset > 0 { Hairline() }
                    pitchRow(item.element, cur)
                }
            }
        }
    }

    private func pitchRow(_ p: Startups.Pitch, _ cur: Currency) -> some View {
        LedgerRow(leading: .thumb(ThumbSpec(kind: .trade, key: p.sector, glyph: Glyph.ventures, initials: p.name, shape: .square)),
                  title: p.name,
                  subtitle: "\(p.sector) \u{00B7} \(p.blurb)",
                  value: cur.tidyShort(p.raise),
                  valueNote: "at \(cur.tidyShort(p.postMoney))",
                  pill: "Back it", pillTone: .good,
                  identifier: "ventures-pitch-\(p.id)") { sheet = .back(p.id) }
    }

    private func stakeRow(_ st: Startups.Stake, _ cur: Currency) -> some View {
        let gain: Double = st.value - st.invested
        let key: String = "k\(st.id)"
        let isOpen: Bool = open == key
        let status: String = st.live ? st.stageName : (st.failed ? "Failed" : "Sold")
        let toggle: (() -> Void)? = st.live ? { open = isOpen ? nil : key } : nil
        return VStack(alignment: .leading, spacing: 0) {
            LedgerRow(leading: .thumb(ThumbSpec(kind: .trade, key: st.sector, glyph: Glyph.ventures, initials: st.name, shape: .square)),
                      title: st.name,
                      subtitle: "\(st.sector) \u{00B7} \(status) \u{00B7} \(String(format: "%.1f", st.ownership))%" + (st.boardSeat ? " \u{00B7} board seat" : ""),
                      value: cur.tidyShort(st.value),
                      valueNote: (gain >= 0 ? "+" : "\u{2212}") + cur.tidyShort(abs(gain)) + " on \(cur.tidyShort(st.invested))",
                      valueNoteTint: Theme.change(gain),
                      chevron: false, identifier: "ventures-stake-\(st.id)",
                      action: toggle)
            if st.live && isOpen {
                WrapRow {
                    Group {
                        if st.boardSeat {
                            Button("Help the team") {
                                let ok = store.act { $0.helpStartupOnBoard(stakeID: st.id) } ?? false
                                store.show(ok ? "You spent time with the team." : "You helped recently.", tone: ok ? "good" : "n")
                            }.buttonStyle(SecondaryButtonStyle(size: .compact))
                        }
                        Button("Sell part") { sheet = .sellStake(st.id) }.buttonStyle(SecondaryButtonStyle(size: .compact))
                    }
                }
                .padding(.bottom, Theme.Space.m)
            }
        }
    }
}
