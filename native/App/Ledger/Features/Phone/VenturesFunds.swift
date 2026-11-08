import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Events
import Simulation

/// Funds: the private equity funds you committed to (value, multiple, what is still to be called, sell on the secondary market) and the funds
/// open to commitments this year. An open fund opens `FundCommitSheet`.
struct VenturesFundsSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @Binding var open: String?
    @Binding var sheet: VentureSheet?
    @Binding var pending: PendingAction?

    var body: some View {
        let cur: Currency = engine.homeCurrency
        let funds: [PrivateEquity.Fund] = engine.privateEquityFunds
        let offers: [PrivateEquity.Offer] = engine.privateEquityOffersOnTable
        let liveCount: Int = funds.filter { (f: PrivateEquity.Fund) -> Bool in f.live }.count
        return LedgerSection(title: "Funds", trailing: { if liveCount > 0 { Text("\(liveCount) held").textStyle(.caption, tint: Theme.inkFaint) } }) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(funds.enumerated()), id: \.element.id) { item in
                    if item.offset > 0 { Hairline() }
                    fundRow(item.element, cur)
                }
                Text("Open to commitments this year").capsLabel(Theme.inkFaint).padding(.top, funds.isEmpty ? 0 : Theme.Space.m).padding(.bottom, Theme.Space.xs)
                if offers.isEmpty {
                    EmptyState(glyph: Glyph.ventures, title: "No fund is open", message: "A new set of funds opens every calendar year.", centered: false)
                        .padding(.vertical, Theme.Space.s)
                }
                ForEach(Array(offers.enumerated()), id: \.element.id) { item in
                    if item.offset > 0 { Hairline() }
                    offerRow(item.element, cur)
                }
            }
        }
    }

    private func offerRow(_ o: PrivateEquity.Offer, _ cur: Currency) -> some View {
        LedgerRow(title: o.name,
                  subtitle: "\(PrivateEquity.styles[o.style]?.name ?? o.style) \u{00B7} \(o.trackRecord)",
                  value: cur.tidyShort(o.minimum), valueNote: "smallest commitment",
                  pill: "Commit", pillTone: .good,
                  identifier: "ventures-fund-offer-\(o.id)") { sheet = .fund(o.id) }
    }

    private func fundRow(_ f: PrivateEquity.Fund, _ cur: Currency) -> some View {
        let year: Int = (engine.state.week - f.startWeek) / 52 + 1
        let multiple: Double = f.live ? f.multiple : f.finalMultiple
        let key: String = "f\(f.id)"
        let isOpen: Bool = open == key
        let toggle: (() -> Void)? = f.live ? { open = isOpen ? nil : key } : nil
        return VStack(alignment: .leading, spacing: 0) {
            LedgerRow(title: f.name,
                      subtitle: "\(PrivateEquity.styles[f.style]?.name ?? f.style) \u{00B7} " + (f.live ? "year \(year) of 10" : f.sold ? "sold" : "wound up"),
                      value: f.live ? cur.tidyShort(f.nav) : cur.tidyShort(f.distributed),
                      valueNote: String(format: "%.2f\u{00D7}", multiple), valueNoteTint: Theme.change(multiple - 1),
                      chevron: false, identifier: "ventures-fund-\(f.id)", action: toggle)
            if f.live && isOpen {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    FigureCard(items: [
                        .init(label: "Committed", value: cur.tidyShort(f.committed), sub: f.toBeCalled > 0 ? "\(cur.tidyShort(f.toBeCalled)) still to call" : "all called"),
                        .init(label: "Value now", value: cur.tidyShort(f.nav)),
                        .init(label: "Paid back", value: cur.tidyShort(f.distributed)),
                    ])
                    Button("Sell on the secondary market") { sheet = .sellFund(f.id) }.buttonStyle(SecondaryButtonStyle(size: .compact))
                }
                .padding(.bottom, Theme.Space.m)
            }
        }
    }
}
