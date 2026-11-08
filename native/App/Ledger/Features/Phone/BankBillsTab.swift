import SwiftUI
import GameCore
import Countries
import Finance
import Simulation

/// A list of coming payments, each with Pay now: payroll is run by a manager or accountant, or answered in the Inbox; a loan
/// instalment is paid now with `payLoanInstalmentNow`; rent, supplier bills, invoices, corporate tax and VAT are settled by the engine's
/// `payObligationNow`, the same payment the due date makes, so nothing is charged again on the date.
struct BankBillsList: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var account: BankAccountID
    var upcoming: [Obligation]
    var cash: Double

    var body: some View {
        if let e = store.engine {
            VStack(alignment: .leading, spacing: 0) {
                if upcoming.isEmpty { EmptyState(glyph: BankGlyph.bill, title: "Nothing is due.", centered: false) }
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { n, u in
                    if n > 0 { Hairline() }
                    row(u, e)
                }
            }
        }
    }

    private func row(_ u: Obligation, _ e: GameEngine) -> some View {
        let co: Company? = u.companyID == 0 ? nil : e.state.company(u.companyID)
        let fmt = BankFmt(store: store, company: co)
        let short: Bool = cash < u.amount
        return VStack(alignment: .leading, spacing: 4) {
            BankObligationRow(obligation: u, fmt: fmt)
            HStack(spacing: 8) {
                Text(u.detail.tidyText).textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                action(u, e)
            }
            if short && u.daysAway <= 30 && account != .investments {
                Text("The account does not hold this much yet. Move money in first.").textStyle(.caption, tint: P.caution)
            }
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder private func action(_ u: Obligation, _ e: GameEngine) -> some View {
        switch u.kind {
        case .payroll:
            Text("Run by a manager or accountant").textStyle(.caption, tint: P.inkFaint)
        case .loan:
            if let loanID = Int(u.id.dropFirst(4)) {
                Button("Pay now") { BankPay.instalment(store, loanID: loanID) }.buttonStyle(SecondaryButtonStyle(size: .compact))
            }
        case .bills, .tax, .invoice:
            Button("Pay now") { BankPay.early(store, u) }.buttonStyle(SecondaryButtonStyle(size: .compact))
        }
    }
}

/// Bills: what is due in 30 days and whether it is covered, every coming payment, tax and VAT owed, the tax rules and licences, and (for a
/// company) the pay day and payroll run. The old Group > Money Overview, Taxes and Costs, and the company payroll desk, in one place.
struct BankBillsTab: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var account: BankAccountID
    var detail: BankAccountDetail
    @State private var showRules = false

    var body: some View {
        if let e = store.engine {
            let o = e.financeOverview(companyID: account.companyID)
            let fmt = BankFmt.make(store, account)
            VStack(alignment: .leading, spacing: 12) {
                dueCard(detail, fmt)
                BankCard(title: "Coming up", trailing: "\(detail.upcoming.count) payment\(detail.upcoming.count == 1 ? "" : "s")") {
                    BankBillsList(account: account, upcoming: detail.upcoming, cash: detail.balance)
                }
                taxCard(o, fmt)
                rulesCard(o)
            }
        }
    }

    /// The one figure of the tab: what falls due in 30 days, with whether the account covers it.
    private func dueCard(_ d: BankAccountDetail, _ fmt: BankFmt) -> some View {
        let due: Double = d.upcoming.filter { $0.daysAway <= 30 }.reduce(0) { $0 + $1.amount }
        let short: Double = max(0, due - max(0, d.available))
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .top, spacing: Theme.Space.s) {
                Figure(label: "Due in the next 30 days", value: fmt.full(due), tint: short > 0 ? P.loss : P.ink, size: .display)
                Spacer(minLength: Theme.Space.s)
                AcctPill(text: short > 0 ? "Short by \(fmt.short(short))" : "Covered", tone: short > 0 ? .bad : .good)
            }
            if short > 0 {
                Text("This account will not cover what is due. Move money in, sell something or borrow before the dates below.")
                    .textStyle(.caption, tint: P.loss).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func taxCard(_ o: FinanceOverview, _ fmt: BankFmt) -> some View {
        BankCard(title: "Tax and VAT", trailing: fmt.short(o.taxesOwed) + " owed") {
            VStack(spacing: 0) {
                if o.taxes.isEmpty { EmptyState(title: "No tax is owed.", centered: false) }
                ForEach(Array(o.taxes.enumerated()), id: \.element.id) { n, l in
                    FlatRow(label: l.label, value: fmt.full(l.amount), sub: l.detail.tidyMoney, rule: n > 0)
                }
                Text("VAT is collected for the state and is not income.")
                    .font(.caption2).foregroundStyle(P.inkFaint).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
        }
    }

    @ViewBuilder private func rulesCard(_ o: FinanceOverview) -> some View {
        let estimate: Bool = o.basis.hasPrefix("Estimate")
        BankCard(title: "Rules in \(o.countryName)", trailing: estimate ? "Estimate" : "Checked") {
            VStack(alignment: .leading, spacing: 0) {
                Button { showRules.toggle(); Haptics.choose() } label: {
                    HStack {
                        Text(showRules ? "Hide the tax rules and licences" : "Show the tax rules and licences").textStyle(.body, tint: P.accent)
                        Spacer()
                        LedgerGlyph(glyph: showRules ? Glyph.chevronUp : Glyph.chevronDown, size: 12, tint: P.accent)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(PressableStyle())
                if showRules {
                    ForEach(Array(o.rules.enumerated()), id: \.element.id) { n, r in FlatRow(label: r.label, value: r.value, rule: true) }
                    Text(o.basis).font(.caption2).foregroundStyle(P.inkFaint).padding(.top, 6)
                    if !o.licences.isEmpty {
                        Text("Licences and registrations").capsLabel().padding(.top, 12)
                        ForEach(Array(o.licences.enumerated()), id: \.element.id) { n, l in
                            FlatRow(label: l.label, value: l.amount > 0 ? store.money(l.amount) : "free", sub: l.detail.tidyMoney, rule: n > 0)
                        }
                        Text("Fees are the game's estimate of typical official fees. Game estimates, not legal advice.").font(.caption2).foregroundStyle(P.inkFaint).padding(.top, 6)
                    }
                }
            }
        }
    }
}
