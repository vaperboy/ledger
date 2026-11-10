import SwiftUI
import GameCore
import Countries
import Simulation

struct BankTotalPanel: View {
    @Environment(\.outsidePalette) private var P
    var totalText: String
    var negative: Bool
    var dueText: String
    var covered: Bool

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total balance").textStyle(.caption)
                Text(totalText).textStyle(.display, tint: negative ? P.loss : P.ink).minimumScaleFactor(0.8).lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Due in 30 days").foregroundStyle(P.inkSoft)
                    Text(dueText).foregroundStyle(P.ink)
                }
                .font(.system(size: 12))
                Text(covered ? "\u{2713} covered" : "Short: not covered").textStyle(.caption, tint: covered ? P.gain : P.loss)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct BankWealthCard: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var open: Bool = false

    var body: some View {
        let b: NetWorthBreakdown = engine.netWorthBreakdown()
        let owed: Double = b.personalDebt + b.pendingTax
        let others: Double = b.investments + b.luxury + b.otherEstimatedHoldings
        BankCard(title: "Your wealth", trailing: "estimate") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(store.money(b.total)).textStyle(.display, tint: b.total < 0 ? P.loss : P.ink).minimumScaleFactor(0.8).lineLimit(2)
                    Spacer(minLength: 8)
                    Text("net worth").textStyle(.caption, tint: P.inkFaint)
                }
                FlatRow(label: "Money you can spend", value: store.short(b.liquid), sub: "your account", rule: false)
                if others > 0.5 { FlatRow(label: "Investments and valuables", value: store.short(others)) }
                FlatRow(label: "Companies (estimated value)", value: store.short(b.estimatedCompanyEquity), sub: "your share, not cash")
                if owed > 0.5 { FlatRow(label: "Debts and tax owed", value: "\u{2212}" + store.short(owed), tint: P.loss) }
                if !b.stakes.isEmpty {
                    toggle
                    if open { stakes(b) }
                }
                Text(b.note).textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
        }
    }

    private var toggle: some View {
        Button {
            Motion.animate(Motion.quickAnimation) { open.toggle() }
            Haptics.choose()
        } label: {
            HStack {
                Text(open ? "Hide companies" : "Show companies").textStyle(.body, tint: P.accent)
                Spacer()
            }
            .frame(minHeight: 40).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("bank-wealth-toggle")
    }

    @ViewBuilder private func stakes(_ b: NetWorthBreakdown) -> some View {
        ForEach(b.stakes) { (st: CompanyStake) in
            let share: String = Currency.percent(st.ownershipPercent / 100, decimals: 0)
            let sub: String = "you own " + share
            FlatRow(label: st.name, value: store.short(st.attributableEquity), sub: sub)
        }
    }
}
