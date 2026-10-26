import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The company's accounts, from the engine's books: profit and loss by period, the balance sheet, cash flow by month, tax and the
/// latest transactions. Original: R6FIN.books (P&L, Balance, Cash flow, Tax) and R6FIN.tx.
struct CompanyAccounts: View {
    enum Page: String, CaseIterable, Hashable { case pnl = "Profit and loss", balance = "Balance sheet", cash = "Cash flow", tax = "Tax", tx = "Transactions" }
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var page: Page = .pnl

    var body: some View {
        let cur = engine.currency(for: company)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            SectionTabs(items: Page.allCases, title: { $0.rawValue }, selection: $page).padding(.horizontal, -Theme.Space.margin)
            switch page {
            case .pnl: pnl(cur)
            case .balance: balance(cur)
            case .cash: cashFlow(cur)
            case .tax: tax(cur)
            case .tx: transactions(cur)
            }
        }
    }

    // MARK: Profit and loss

    private func pnl(_ cur: Currency) -> some View {
        let b = company.books
        let periods: [Period] = [.init(name: "Week", books: b.week), .init(name: "Month", books: b.month), .init(name: "Year", books: b.year), .init(name: "Last yr", books: b.lastYear)]
        let lines = [Line(key: "rev", label: "Revenue")] + GameEngine.costLabels.filter { $0.key != "tax" }.map { Line(key: $0.key, label: $0.label) }
        let shown = lines.filter { l in periods.contains { abs($0.books[l.key] ?? 0) >= 0.5 } }
        return LedgerSection(title: "Profit and loss", trailing: {
            NavigationLink { ReportsScreen(companyID: company.id) } label: { Text("Monthly reports  →").font(.system(size: 12)).foregroundStyle(Theme.gold) }.buttonStyle(.plain)
        }) {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Text("").frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(periods) { Text($0.name).frame(width: 58, alignment: .trailing) }
                }.font(.system(size: 9.5, weight: .semibold)).tracking(0.8).textCase(.uppercase).foregroundStyle(Theme.ivoryFaint).padding(.bottom, 6)
                if shown.isEmpty { Text("Nothing booked yet.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8) }
                ForEach(shown) { l in
                    Hairline()
                    HStack(spacing: 4) {
                        Text(l.label).font(.system(size: 12.5)).foregroundStyle(l.key == "rev" ? Theme.ivory : Theme.ivoryMuted).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(periods) { p in
                            let v = p.books[l.key] ?? 0
                            Text(l.key == "rev" ? cur.tidyShort(v) : (v == 0 ? "–" : "−" + cur.tidyShort(v))).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.ivory).frame(width: 58, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }.padding(.vertical, 6)
                }
                Hairline()
                HStack(spacing: 4) {
                    Text("Profit before tax").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.ivory).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(periods) { p in
                        let v = Books.profit(p.books)
                        Text(cur.tidyShort(v)).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(v < 0 ? Theme.loss : Theme.ivory).frame(width: 58, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }.padding(.vertical, 7)
                Text("Week, month and year so far. Corporate tax is settled after the year and shown under Tax.").font(.caption2).foregroundStyle(Theme.ivoryFaint).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
            }
        }
    }

    // MARK: Balance sheet

    @ViewBuilder private func balance(_ cur: Currency) -> some View {
        if let b = engine.companyBalanceSheet(companyID: company.id) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if b.equity < 0 {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.loss).padding(.top, 2)
                        Text("The company owes more than it owns. Banks lend less, and a limited company in this state should be recapitalised or wound up.")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                    }
                }
                KeyFigures(items: [
                    .init(label: "Owns", value: cur.tidyShort(b.totalAssets)),
                    .init(label: "Owes", value: cur.tidyShort(b.totalDebts), tint: b.totalDebts > 0 ? Theme.loss : Theme.ivory),
                    .init(label: "Equity", value: cur.tidyShort(b.equity), tint: b.equity < 0 ? Theme.loss : Theme.gain, sub: "owns minus owes"),
                ])
                LedgerSection(title: "What it owns", trailing: { Text(cur.tidyShort(b.totalAssets)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.ivoryMuted) }) {
                    VStack(spacing: 0) { ForEach(Array(b.assets.enumerated()), id: \.element.id) { n, l in FlatRow(label: l.label, value: cur.tidyShort(l.amount), sub: l.detail, tint: l.amount < 0 ? Theme.loss : Theme.ivory, rule: n > 0) } }
                }
                LedgerSection(title: "What it owes", trailing: { Text(cur.tidyShort(b.totalDebts)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.ivoryMuted) }) {
                    if b.debts.isEmpty { Text("No debts.").font(.bodyText).foregroundStyle(Theme.ivoryMuted) }
                    VStack(spacing: 0) { ForEach(Array(b.debts.enumerated()), id: \.element.id) { n, l in FlatRow(label: l.label, value: cur.tidyShort(l.amount), rule: n > 0) } }
                }
                LedgerSection("Equity") {
                    VStack(spacing: 0) {
                        if company.form == .limited { FlatRow(label: "Share capital", value: cur.tidyShort(b.shareCapital), rule: false) }
                        FlatRow(label: "Put in by owners over time", value: cur.tidyShort(b.injected), rule: company.form == .limited)
                        if b.distributed > 0 { FlatRow(label: "Paid out as dividends", value: cur.tidyShort(b.distributed)) }
                        FlatRow(label: "Equity (owns minus owes)", value: cur.tidyShort(b.equity), tint: b.equity < 0 ? Theme.loss : Theme.ivory)
                    }
                }
            }
        }
    }

    // MARK: Cash flow

    @ViewBuilder private func cashFlow(_ cur: Currency) -> some View {
        let months = engine.companyCashFlow(companyID: company.id, months: 12)
        LedgerSection(title: "Cash flow by month", trailing: { Text("closed months").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
            if months.isEmpty {
                Text("Cash flow starts after the first full month.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        Text("Month").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Profit").frame(width: 64, alignment: .trailing)
                        Text("Other").frame(width: 64, alignment: .trailing)
                        Text("Cash end").frame(width: 70, alignment: .trailing)
                    }.font(.system(size: 9.5, weight: .semibold)).tracking(0.8).textCase(.uppercase).foregroundStyle(Theme.ivoryFaint).padding(.bottom, 6)
                    ForEach(months.reversed()) { m in
                        Hairline()
                        HStack(spacing: 4) {
                            Text(m.label).font(.system(size: 12.5)).foregroundStyle(Theme.ivory).frame(maxWidth: .infinity, alignment: .leading)
                            num(cur.tidyShort(m.profit), m.profit < 0 ? Theme.loss : Theme.ivory, 64)
                            num(m.otherMovements.map { cur.tidyShort($0) } ?? "–", (m.otherMovements ?? 0) < 0 ? Theme.caution : Theme.ivoryMuted, 64)
                            num(cur.tidyShort(m.cashAtEnd), m.cashAtEnd < 0 ? Theme.loss : Theme.ivory, 70)
                        }.padding(.vertical, 6)
                    }
                    Text("Other is cash that moved without being profit: money you put in or took out, loans drawn or repaid, equipment bought, stock and bills paid later or earlier.")
                        .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
            }
        }
    }

    // MARK: Tax

    private func tax(_ cur: Currency) -> some View {
        let o = engine.financeOverview(companyID: company.id)
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            LedgerSection(title: "Tax and VAT", trailing: { Text("owed now " + cur.tidyShort(o.taxesOwed)).font(.system(size: 11.5)).foregroundStyle(o.taxesOwed > 0 ? Theme.caution : Theme.ivoryFaint) }) {
                VStack(spacing: 0) {
                    if company.form == .limited {
                        FlatRow(label: "Profit so far this year", value: cur.tidyShort(company.yearProfitSoFar), rule: false)
                        FlatRow(label: "Tax set aside for this year", value: cur.tidyShort(company.taxAccrued))
                        if company.taxDue { FlatRow(label: "Last year's tax, due week \(company.taxDueWeek + 1)", value: cur.tidyShort(company.taxPrevYear), tint: Theme.caution) }
                        if company.lossCarryForward > 0 { FlatRow(label: "Losses to set against future profit", value: cur.tidyShort(company.lossCarryForward)) }
                    } else {
                        Text("A sole trader pays no company tax: the profit is taxed on your personal return each year (see Group › Money › Taxes).")
                            .font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(o.taxes) { t in FlatRow(label: t.label.replacingOccurrences(of: " · " + company.name, with: ""), value: cur.tidyShort(t.amount), sub: t.detail) }
                }
            }
            if !o.rules.isEmpty {
                LedgerSection("Rules in \(o.countryName)") {
                    VStack(spacing: 0) { ForEach(Array(o.rules.enumerated()), id: \.element.id) { n, r in FlatRow(label: r.label, value: r.value, rule: n > 0) } }
                    if !o.basis.isEmpty { Text(o.basis).font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true) }
                }
            }
        }
    }

    // MARK: Transactions

    private func transactions(_ cur: Currency) -> some View {
        let tx = company.transactions
        return LedgerSection(title: "Latest transactions", trailing: { Text("newest first · up to 40").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
            if tx.isEmpty { Text("No transactions recorded yet. Sales, bills and transfers appear here once the company has traded.").font(.bodyText).foregroundStyle(Theme.ivoryMuted) }
            VStack(spacing: 0) {
                ForEach(Array(tx.enumerated()), id: \.offset) { n, t in
                    FlatRow(label: t["l"].string, value: (t["a"].double < 0 ? "−" : "+") + cur.tidyShort(abs(t["a"].double)), sub: "Week \(t["w"].int + 1)",
                            tint: t["a"].double < 0 ? Theme.ivory : Theme.gain, rule: n > 0)
                }
            }
        }
    }

    private struct Period: Identifiable { var id: String { name }; var name: String; var books: [String: Double] }
    private struct Line: Identifiable { var id: String { key }; var key: String; var label: String }

    private func num(_ s: String, _ c: Color, _ w: CGFloat) -> some View {
        Text(s).font(.system(size: 12).monospacedDigit()).foregroundStyle(c).frame(width: w, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.7)
    }
}
