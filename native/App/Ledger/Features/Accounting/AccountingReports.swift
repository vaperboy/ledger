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
                    HStack {
                        Text(current).font(.system(size: 15, weight: .medium)).foregroundStyle(P.ink).lineLimit(1)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(P.inkFaint)
                    }
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).fill(P.card))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).strokeBorder(P.lineStrong, lineWidth: 1))
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
                VStack(alignment: .leading, spacing: 14) {
                    AcctCompanyMenu(m: m)
                    content(e, co)
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 20)
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
            group("What the company has", b.assets, total: b.totalAssets, totalLabel: "Total assets", fmt)
            group("What the company owes", b.debts, total: b.totalDebts, totalLabel: "Total debts", fmt)
            equity(b, fmt)
        } else {
            AcctLocked(section: "Balance sheet")
        }
    }

    private func group(_ title: String, _ lines: [FinanceLine], total: Double, totalLabel: String, _ fmt: BankFmt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AcctLabel(text: title)
            AcctPanel(padding: 14) {
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

    private func equity(_ b: CompanyBalanceSheet, _ fmt: BankFmt) -> some View {
        let tint: Color = b.equity < 0 ? P.loss : P.ink
        return VStack(alignment: .leading, spacing: 8) {
            AcctLabel(text: "What is left for the owners")
            AcctPanel(padding: 14) {
                FlatRow(label: "Equity", value: fmt.full(b.equity), sub: "Assets minus debts", tint: tint, rule: false)
                if b.shareCapital > 0.5 { FlatRow(label: "Share capital paid in", value: fmt.full(b.shareCapital)) }
                if b.injected > 0.5 { FlatRow(label: "Put in by the owner", value: fmt.full(b.injected), sub: "over the years, share capital included") }
                if b.distributed > 0.5 { FlatRow(label: "Paid out as dividends", value: fmt.full(b.distributed)) }
            }
            if b.equity < 0 {
                Text("The company owes more than it has. Lenders and suppliers will notice.").font(.system(size: 12.5)).foregroundStyle(P.loss).padding(.horizontal, 2)
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
                VStack(alignment: .leading, spacing: 14) {
                    AcctCompanyMenu(m: m)
                    content(e, co)
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 20)
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
            } else {
                list(months.reversed(), BankFmt(store: store, company: co))
            }
        }
    }

    private func list(_ months: [CompanyCashMonth], _ fmt: BankFmt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AcctLabel(text: "Closed months, newest first")
            AcctPanel {
                ForEach(Array(months.enumerated()), id: \.element.id) { n, month in
                    VStack(spacing: 0) {
                        if n > 0 { AcctDivider() }
                        row(month, fmt)
                    }
                }
            }
            Text("Other moves are money that is not profit: you putting in or taking out, loans, equipment, stock and unpaid bills.")
                .font(.system(size: 11.5)).foregroundStyle(P.inkFaint).padding(.horizontal, 2)
        }
    }

    private func signed(_ v: Double, _ fmt: BankFmt) -> String { (v < 0 ? "-" : "+") + fmt.short(abs(v)) }

    private func row(_ month: CompanyCashMonth, _ fmt: BankFmt) -> some View {
        var sub: String = "Profit " + signed(month.profit, fmt)
        if let other = month.otherMovements { sub += " \u{00B7} other moves " + signed(other, fmt) }
        let note: String = month.cashChange.map { (c: Double) -> String in "cash " + signed(c, fmt) } ?? "first month on record"
        let tint: Color = (month.cashChange ?? 0) < 0 ? P.loss : P.gain
        return AcctRow(title: month.label, subtitle: sub, value: fmt.short(month.cashAtEnd), valueNote: note, valueNoteTint: tint, identifier: "acct-cashflow-row")
    }
}
