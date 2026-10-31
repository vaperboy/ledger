import SwiftUI
import GameCore
import Countries
import Simulation

/// The content of the ivory total panel on the Bank's account list (reads the ivory palette its `IvoryPanel` sets).
struct BankTotalPanel: View {
    @Environment(\.outsidePalette) private var P
    var totalText: String
    var negative: Bool
    var dueText: String
    var covered: Bool

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total balance").font(.system(size: 12.5)).foregroundStyle(P.inkSoft)
                Text(totalText).font(.hero(32)).foregroundStyle(negative ? P.loss : P.ink).minimumScaleFactor(0.6).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Due in 30 days").foregroundStyle(P.inkSoft)
                    Text(dueText).foregroundStyle(P.ink)
                }
                .font(.system(size: 12))
                Text(covered ? "\u{2713} covered" : "Short: not covered").font(.system(size: 12)).foregroundStyle(covered ? P.gain : P.loss)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Your wealth (Master spec 2E): the money you can spend, investments, the ESTIMATED value of your companies (kept apart, never spendable) and what you
/// owe. From `netWorthBreakdown`, so a company's value is counted once and never shown as cash.
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
                    Text(store.money(b.total)).font(.hero(28)).foregroundStyle(b.total < 0 ? P.loss : P.ink).minimumScaleFactor(0.6).lineLimit(1)
                    Spacer(minLength: 8)
                    Text("net worth").font(.system(size: 12)).foregroundStyle(P.inkFaint)
                }
                FlatRow(label: "Money you can spend", value: store.short(b.liquid), sub: "current account and savings", rule: false)
                if others > 0.5 { FlatRow(label: "Investments and valuables", value: store.short(others)) }
                FlatRow(label: "Companies (estimated value)", value: store.short(b.estimatedCompanyEquity), sub: "your share, not cash")
                if owed > 0.5 { FlatRow(label: "Debts and tax owed", value: "\u{2212}" + store.short(owed), tint: P.loss) }
                if !b.stakes.isEmpty {
                    toggle
                    if open { stakes(b) }
                }
                Text(b.note).font(.system(size: 11)).foregroundStyle(P.inkFaint).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
        }
    }

    private var toggle: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { open.toggle() }
            Haptics.choose()
        } label: {
            HStack {
                Text(open ? "Hide companies" : "Show companies").font(.system(size: 13)).foregroundStyle(P.accent)
                Spacer()
            }
            .frame(minHeight: 40).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("bank-wealth-toggle")
    }

    @ViewBuilder private func stakes(_ b: NetWorthBreakdown) -> some View {
        ForEach(b.stakes) { (st: CompanyStake) in
            let share: String = Currency.percent(st.ownershipPercent / 100, decimals: 0)
            let sub: String = st.heldThrough.map { "held through " + $0 } ?? ("you own " + share)
            FlatRow(label: st.name, value: store.short(st.attributableEquity), sub: sub)
        }
    }
}

/// A company account's reserves, display only (owner decision, Oct 2026): what payroll and tax will need, and what is free. The money stays in the one
/// account; there are no sub-accounts to move between.
struct BankReservesCard: View {
    @Environment(\.outsidePalette) private var P
    var reserves: CompanyReserves
    var fmt: BankFmt

    var body: some View {
        BankCard(title: "Reserves", trailing: "display only") {
            VStack(alignment: .leading, spacing: 0) {
                FlatRow(label: "Payroll", value: fmt.short(reserves.payroll), sub: "wages owed and building up", rule: false)
                FlatRow(label: "Tax", value: fmt.short(reserves.tax), sub: "tax and VAT owed")
                FlatRow(label: "Free to use", value: fmt.short(reserves.free), sub: "cash after the two reserves", tint: reserves.free < 0 ? P.loss : nil)
                Text("These are not separate accounts: they show what part of the company's cash is already spoken for.").font(.system(size: 11)).foregroundStyle(P.inkFaint)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
        }
    }
}
