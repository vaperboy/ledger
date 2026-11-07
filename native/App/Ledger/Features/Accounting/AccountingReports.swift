import SwiftUI
import GameCore
import Countries
import Simulation

// Accounting > Balance sheet and Cash flow: the company's statements as the engine's own figures (`companyBalanceSheet`, `companyCashFlow`).
// Assets, debts and equity are grouped and every figure is labelled; the cash flow lists the closed months with profit set against what cash did.

/// A compact company menu for the statement pages; hidden when there is one company.
struct AcctCompanyMenu: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @ObservedObject var m: AcctModel

    var body: some View {
        if let e = store.engine {
            let companies: [Company] = e.state.liveCompanies
            if companies.count > 1 {
                let current: String = companies.first { (c: Company) -> Bool in c.id == m.companyID }?.name ?? "Choose a business"
                Menu {
                    ForEach(companies) { (co: Company) in
                        Button {
                            m.companyID = co.id
                            Haptics.choose()
                        } label: {
                            if co.id == m.companyID { Label(co.name, systemImage: "checkmark") } else { Text(co.name) }
                        }
                    }
                } label: {
                    HStack(spacing: Theme.Space.s) {
                        Text(current.tidyText).textStyle(.headline).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").textStyle(.caption, tint: P.inkFaint, weight: .semibold)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("acct-report-company")
            }
        }
    }
}

// MARK: Balance sheet

struct AcctBalanceSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @ObservedObject var m: AcctModel

    var body: some View {
        if let e = store.engine, let co = e.state.company(m.companyID) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    AcctCompanyMenu(m: m)
                    content(e, co)
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.l).padding(.bottom, Theme.Space.xl)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company) -> some View {
        if !e.canAccess(.transactions, companyID: co.id, user: m.user) {
            AcctLocked(section: "Balance sheet")
        } else if let b = e.companyBalanceSheet(companyID: co.id) {
            let fmt = BankFmt(store: store, company: co)
            MoneyHero(label: "Equity", value: fmt.full(b.equity), tint: b.equity < 0 ? P.loss : nil,
                      context: "Assets \(fmt.short(b.totalAssets)) \u{00B7} debts \(fmt.short(b.totalDebts))" + (b.equity < 0 ? ": it owes more than it has" : ""),
                      contextTint: b.equity < 0 ? P.loss : nil)
            group("What the company has", b.assets, total: b.totalAssets, totalLabel: "Total assets", fmt)
            group("What the company owes", b.debts, total: b.totalDebts, totalLabel: "Total debts", fmt)
            equity(b, fmt)
        } else {
            AcctLocked(section: "Balance sheet")
        }
    }

    private func group(_ title: String, _ lines: [FinanceLine], total: Double, totalLabel: String, _ fmt: BankFmt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AcctCaps(text: title)
            AcctFlat(padding: 14) {
                if lines.isEmpty {
                    FlatRow(label: "Nothing", value: fmt.full(0), rule: false)
                }
                ForEach(Array(lines.enumerated()), id: \.element.id) { n, line in
                    FlatRow(label: line.label, value: fmt.full(line.amount), sub: line.detail, rule: n > 0)
                }
                FlatRow(label: totalLabel, value: fmt.full(total), tint: P.ink)
            }
        }
    }

    /// Where the equity came from (the figure itself leads the page).
    @ViewBuilder private func equity(_ b: CompanyBalanceSheet, _ fmt: BankFmt) -> some View {
        if b.shareCapital > 0.5 || b.injected > 0.5 || b.distributed > 0.5 {
            VStack(alignment: .leading, spacing: 8) {
                AcctCaps(text: "What is left for the owners")
                AcctFlat(padding: 14) {
                    if b.shareCapital > 0.5 { FlatRow(label: "Share capital paid in", value: fmt.full(b.shareCapital), rule: false) }
                    if b.injected > 0.5 { FlatRow(label: "Put in by the owner", value: fmt.full(b.injected), sub: "over the years, share capital included", rule: b.shareCapital > 0.5) }
                    if b.distributed > 0.5 { FlatRow(label: "Paid out as dividends", value: fmt.full(b.distributed), rule: b.shareCapital > 0.5 || b.injected > 0.5) }
                }
            }
        }
    }
}

// MARK: Cash flow

struct AcctCashFlow: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @ObservedObject var m: AcctModel

    var body: some View {
        if let e = store.engine, let co = e.state.company(m.companyID) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    AcctCompanyMenu(m: m)
                    content(e, co)
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.l).padding(.bottom, Theme.Space.xl)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company) -> some View {
        if !e.canAccess(.transactions, companyID: co.id, user: m.user) {
            AcctLocked(section: "Cash flow")
        } else {
            let months: [CompanyCashMonth] = e.companyCashFlow(companyID: co.id, months: 12)
            if months.isEmpty {
                AcctNotice(glyph: Glyph.reports, title: "No month has closed yet", message: "Each closed month appears here with its profit and what the cash did.")
            } else if let last = months.last {
                let fmt = BankFmt(store: store, company: co)
                MoneyHero(label: "Cash at the end of " + last.label, value: fmt.full(last.cashAtEnd), tint: last.cashAtEnd < 0 ? P.loss : nil,
                          context: "Profit " + signed(last.profit, fmt) + (last.cashChange.map { " \u{00B7} cash " + signed($0, fmt) } ?? ""),
                          contextTint: P.change(last.cashChange ?? last.profit), spark: months.map { $0.cashAtEnd })
                list(months.reversed(), fmt)
            }
        }
    }

    private func list(_ months: [CompanyCashMonth], _ fmt: BankFmt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AcctCaps(text: "Closed months, newest first")
            AcctFlat {
                ForEach(Array(months.enumerated()), id: \.element.id) { n, month in
                    VStack(spacing: 0) {
                        if n > 0 { AcctDivider() }
                        row(month, fmt)
                    }
                }
            }
            Text("Other moves are money that is not profit: you putting in or taking out, loans, equipment, stock and unpaid bills.")
                .textStyle(.caption, tint: P.inkFaint).padding(.horizontal, 2)
        }
    }

    private func signed(_ v: Double, _ fmt: BankFmt) -> String { (v < 0 ? "-" : "+") + fmt.short(abs(v)) }

    private func row(_ month: CompanyCashMonth, _ fmt: BankFmt) -> some View {
        var sub: String = "Profit " + signed(month.profit, fmt)
        if let other = month.otherMovements { sub += " \u{00B7} other moves " + signed(other, fmt) }
        let note: String = month.cashChange.map { (c: Double) -> String in "cash " + signed(c, fmt) } ?? "first month on record"
        let tint: Color = (month.cashChange ?? 0) < 0 ? P.loss : P.gain
        return AcctLine(title: month.label, subtitle: sub, value: fmt.short(month.cashAtEnd), valueNote: note, valueNoteTint: tint, identifier: "acct-cashflow-row")
    }
}
