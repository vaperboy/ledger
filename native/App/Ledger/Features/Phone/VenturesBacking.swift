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

/// Back a startup from a pitch: pick the amount, read the quote (share, valuation, board seat, cash left), then confirm. The engine sells the
/// stake at the pitch's post-money valuation, rounds the amount to 10,000 and takes at most what the founders raise.
struct BackStartupSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var pitchID: Int
    @State private var amount = 0.0
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let p = e.startupPitchesOnOffer.first(where: { (x: Startups.Pitch) -> Bool in x.id == pitchID }) {
                content(e, p)
            } else {
                Text("This pitch is no longer open.").popupText(.body)
            }
        }
        .confirmAction($pending)
        .centerSheetTitle("Back a startup")
    }

    private func content(_ e: GameEngine, _ p: Startups.Pitch) -> some View {
        let cur: Currency = e.homeCurrency
        let lo: Double = cur.scaledPrice(Startups.minimumInvestment)
        let hi: Double = p.raise
        let canChoose: Bool = hi > lo
        let shown = Binding<Double>(get: { min(max(amount, lo), max(lo, hi)) }, set: { (v: Double) in amount = v })
        let rounded: Double = (shown.wrappedValue / 10000).rounded() * 10000
        let put: Double = min(rounded, hi)
        let pct: Double = put / max(1, p.postMoney) * 100
        let cash: Double = Payments.liquid(e.state)
        let tooSmall: Bool = put < lo
        let enough: Bool = cash >= put
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(p.name).popupText(.figure)
            Text("\(p.sector). \(p.blurb)").popupText(.caption).fixedSize(horizontal: false, vertical: true)
            PopupRow(label: "Raising", value: cur.tidyShort(p.raise))
            PopupRow(label: "Valued at", value: cur.tidyShort(p.postMoney) + " after the money")
            PopupRow(label: "Team \u{00B7} market \u{00B7} traction", value: "\(p.team) \u{00B7} \(p.market) \u{00B7} \(p.traction)")
            if canChoose {
                LedgerSlider(value: shown, in: lo...hi, step: 10000, valueText: "Put in " + cur.tidyShort(put))
                    .accessibilityIdentifier("ventures-back-amount")
            } else {
                Text("This round is smaller than the smallest cheque, \(cur.tidyShort(lo)).").popupText(.risk)
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                PopupRow(label: "Price", value: cur.tidyShort(put))
                PopupRow(label: "You get", value: String(format: "%.1f%%", pct))
                PopupRow(label: "Board seat", value: pct >= 20 ? "Yes" : "No, from 20%")
                PopupRow(label: "Your cash after", value: enough ? cur.tidyShort(cash - put) : "Not enough")
                Text("Most startups fail and the money is lost. Later rounds make your share smaller. You can sell part of a stake later at a discount to its value.")
                    .popupText(.caption).fixedSize(horizontal: false, vertical: true)
                if !enough { Text("You need \(cur.tidyShort(put - cash)) more in cash.").popupText(.risk) }
                Button("Invest \(cur.tidyShort(put)) for \(String(format: "%.1f%%", pct))") { ask(p, put, pct, cur) }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(!enough || tooSmall)
                    .accessibilityIdentifier("ventures-back-go")
            }
        }
    }

    private func ask(_ p: Startups.Pitch, _ put: Double, _ pct: Double, _ cur: Currency) {
        let seat: String = pct >= 20 ? " You get a board seat." : ""
        pending = PendingAction(title: "Back \(p.name)?",
                                message: "\(cur.tidyDisplay(put)) leaves your cash now for \(String(format: "%.1f%%", pct)) at a valuation of \(cur.tidyShort(p.postMoney)).\(seat)",
                                button: "Invest \(cur.tidyShort(put))", amount: put, currency: cur,
                                risk: "Most startups fail and the money is lost.", tone: .investment, icon: "chart.pie") {
            switch store.act({ $0.investInStartup(pitchID: p.id, amount: put) }) {
            case .ok?: Haptics.success(); store.show("You now hold \(String(format: "%.1f%%", pct)) of \(p.name).", tone: "good"); dismiss()
            case .tooSmall?: store.show("That is below the smallest cheque.", tone: "warn")
            case .notEnoughMoney?: Haptics.warning(); store.show("You need \(cur.tidyShort(put)) in cash.", tone: "warn")
            default: store.show("That pitch has gone.", tone: "warn"); dismiss()
            }
        }
    }
}

/// Sell part or all of a stake in someone else's startup. The engine pays 72% of the shares' fair value and taxes the gain.
struct SellStakeSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var stakeID: Int
    @State private var fraction = 0.5
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let st = e.startupStakes.first(where: { (x: Startups.Stake) -> Bool in x.id == stakeID && x.live }) {
                content(e, st)
            } else {
                Text("This stake is no longer held.").popupText(.body)
            }
        }
        .confirmAction($pending)
        .centerSheetTitle("Sell shares")
    }

    private func content(_ e: GameEngine, _ st: Startups.Stake) -> some View {
        let cur: Currency = e.homeCurrency
        let fair: Double = st.value * fraction
        let get: Double = fair * 0.72
        let cost: Double = st.invested * fraction
        let left: Double = st.ownership * (1 - fraction)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(st.name).popupText(.figure)
            PopupRow(label: "You hold", value: String(format: "%.1f%% worth ", st.ownership) + cur.tidyShort(st.value))
            SegmentedPill(items: [0.25, 0.5, 0.75, 1.0], title: { (f: Double) -> String in "\(Int((f * 100).rounded()))%" }, selection: $fraction)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                PopupRow(label: "Fair value of these shares", value: cur.tidyShort(fair))
                PopupRow(label: "You receive", value: cur.tidyShort(get))
                PopupRow(label: "Against what you put in", value: (get >= cost ? "+" : "\u{2212}") + cur.tidyShort(abs(get - cost)))
                PopupRow(label: "You hold after", value: fraction >= 1 ? "Nothing" : String(format: "%.1f%%", left))
                Text("Shares sold early go for 28% under their fair value. A gain is taxed." + (st.boardSeat && left < 20 ? " Under 20% you lose the board seat." : ""))
                    .popupText(.caption).fixedSize(horizontal: false, vertical: true)
                Button("Sell for \(cur.tidyShort(get))") { ask(st, get, cur) }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("ventures-sell-go")
            }
        }
    }

    private func ask(_ st: Startups.Stake, _ get: Double, _ cur: Currency) {
        let f: Double = fraction
        pending = PendingAction(title: "Sell \(Int((f * 100).rounded()))% of your stake in \(st.name)?",
                                message: "You receive about \(cur.tidyShort(get)). It cannot be undone.",
                                button: "Sell", destructive: true, tone: .investment, icon: "arrow.up.right") {
            let v: Double = store.act { $0.sellStartupStake(stakeID: st.id, fraction: f) } ?? 0
            if v > 0 { Haptics.success(); store.show("Sold for \(cur.tidyShort(v)).", tone: "good"); dismiss() } else { store.show("That stake could not be sold.", tone: "warn") }
        }
    }
}
