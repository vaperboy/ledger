import SwiftUI
import GameCore
import Countries
import Simulation

/// What the Reports screen shows for the chosen period: the report itself, the company bank movements, or payroll and bills.
enum ReportPage: String, CaseIterable, Hashable { case summary = "Summary", movements = "Transactions", bills = "Bills and payroll" }

/// Amounts in the currency of the company they belong to (the home currency for the group's own lines).
@MainActor private struct MoneyText {
    var store: GameStore
    var engine: GameEngine
    func short(_ v: Double, company id: Int) -> String {
        if id != 0, let co = engine.state.company(id) { return store.short(v, in: co) }
        return store.short(v)
    }
    func signed(_ v: Double, company id: Int) -> String { abs(v) < 0.5 ? short(0, company: id) : (v > 0 ? "+" : "−") + short(abs(v), company: id) }
}

/// The bank movements of the companies in a report's weeks, newest first, with a filter by kind. Each company keeps its
/// latest 40 movements, so an old period can be incomplete; the screen says so.
struct ReportMovements: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var report: PeriodReport
    var companyID: Int?
    @State private var kind: CompanyMovement.Kind? = nil
    @State private var limit = 60

    var body: some View {
        let fmt = MoneyText(store: store, engine: engine)
        let all = engine.companyMovements(companyID: companyID, weeks: report.firstWeek...report.lastWeek)
        let list = all.filter { kind == nil || $0.kind == kind }
        let incomplete = isIncomplete
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if companyID != nil || singleCurrency {
                let inflow = list.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }
                let outflow = list.filter { $0.amount < 0 }.reduce(0) { $0 - $1.amount }
                let id = companyID ?? 0
                KeyFigures(items: [
                    .init(label: "Money in", value: fmt.short(inflow, company: id), tint: inflow > 0 ? Theme.gain : Theme.ivory),
                    .init(label: "Money out", value: fmt.short(outflow, company: id)),
                    .init(label: "Movements", value: "\(list.count)"),
                ], columns: 3)
            }
            WrapRow {
                Group {
                    Button("All") { kind = nil; limit = 60 }.buttonStyle(QuietButtonStyle(tint: kind == nil ? Theme.gold : Theme.ivoryFaint))
                    ForEach(CompanyMovement.Kind.allCases, id: \.self) { k in
                        let n = all.filter { $0.kind == k }.count
                        if n > 0 {
                            Button("\(k.title) · \(n)") { kind = k; limit = 60 }.buttonStyle(QuietButtonStyle(tint: kind == k ? Theme.gold : Theme.ivoryFaint))
                        }
                    }
                }
            }
            LedgerSection(title: "Bank movements", trailing: { Text(report.range).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                if list.isEmpty {
                    Text(all.isEmpty ? "No company money moved in this period, or it is older than what the companies keep." : "Nothing of this kind in this period.")
                        .font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(list.prefix(limit).enumerated()), id: \.element.id) { i, m in
                            if i > 0 { Hairline() }
                            row(m, fmt)
                        }
                    }
                    if list.count > limit {
                        Button("Show \(min(60, list.count - limit)) more") { limit += 60 }.buttonStyle(QuietButtonStyle()).padding(.top, 6)
                    }
                }
            }
            Text(incomplete ? "Each company keeps only its latest \(GameEngine.movementsKept) movements, so this period may be incomplete. Sales and daily costs are booked in the profit and loss, not here."
                 : "Payroll, bills, tax, owner money and one-off payments. Sales and daily costs are booked in the profit and loss, not here.")
                .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Whether every company shown uses the home currency (totals can then be added up).
    private var singleCurrency: Bool {
        let home = engine.homeCurrency.country.currencyCode
        return engine.state.companies.filter { $0.isOpenOrClosed }.allSatisfy { engine.currency(for: $0).country.currencyCode == home }
    }

    /// A company that has its full 40 movements, the oldest after this period began, may have lost some of this period's.
    private var isIncomplete: Bool {
        engine.state.companies.contains { co in
            guard companyID == nil ? co.isOpenOrClosed : co.id == companyID else { return false }
            let tx = co.transactions
            return tx.count >= GameEngine.movementsKept && (tx.last?["w"].int ?? 0) > report.firstWeek
        }
    }

    private func row(_ m: CompanyMovement, _ fmt: MoneyText) -> some View {
        Button { store.openCompany(m.companyID, section: .finances) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.label).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineLimit(2).multilineTextAlignment(.leading)
                    Text((companyID == nil ? m.companyName + " · " : "") + GameCalendar.dateString(week: m.week))
                        .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(fmt.signed(m.amount, company: m.companyID)).font(.system(size: 13.5).monospacedDigit())
                    .foregroundStyle(m.amount > 0 ? Theme.gain : Theme.ivory)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.ivoryFaint)
            }
            .padding(.vertical, 8).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(engine.state.company(m.companyID) == nil)
        .accessibilityHint("Opens the company's finances")
    }
}

/// Payroll and bills: what falls due next (the same list the money overview uses) and what was paid in the chosen period.
struct ReportBills: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var report: PeriodReport
    var companyID: Int?

    var body: some View {
        let fmt = MoneyText(store: store, engine: engine)
        let o = engine.financeOverview(companyID: companyID)
        let paid = engine.companyMovements(companyID: companyID, weeks: report.firstWeek...report.lastWeek).filter { [CompanyMovement.Kind.payroll, .bills, .tax].contains($0.kind) }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            KeyFigures(items: [
                .init(label: "Due in 30 days", value: fmt.short(o.dueWithin30Days, company: companyID ?? 0)),
                .init(label: CashWording.available(companyID: companyID), value: fmt.short(o.cashAvailable, company: companyID ?? 0)),
                .init(label: "Short by", value: o.shortfall > 0 ? fmt.short(o.shortfall, company: companyID ?? 0) : "–", tint: o.shortfall > 0 ? Theme.loss : Theme.ivory),
            ], columns: 3)
            LedgerSection(title: "Coming due", trailing: { Text("\(o.upcoming.count)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                if o.upcoming.isEmpty {
                    Text("Nothing is due: no payroll, bills, tax or loan instalments are waiting.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(o.upcoming.enumerated()), id: \.element.id) { i, u in
                            if i > 0 { Hairline() }
                            Button { if u.companyID != 0 { store.openCompany(u.companyID, section: .finances) } } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(u.title.tidyMoney).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineLimit(2).multilineTextAlignment(.leading)
                                        Text(u.detail.tidyMoney).font(.system(size: 11)).foregroundStyle(u.detail == "Needs your approval" ? Theme.caution : Theme.ivoryFaint).lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(fmt.short(u.amount, company: u.companyID)).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.ivory)
                                        Text(u.daysAway <= 0 ? "Due now" : u.daysAway == 1 ? "Tomorrow" : "\(u.dateText) · \(u.daysAway) days")
                                            .font(.system(size: 10.5)).foregroundStyle(u.daysAway <= 7 ? Theme.caution : Theme.ivoryFaint)
                                    }
                                    if u.companyID != 0 { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.ivoryFaint) }
                                }
                                .padding(.vertical, 8).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(u.companyID == 0 || engine.state.company(u.companyID) == nil)
                        }
                    }
                }
            }
            LedgerSection(title: "Paid in this " + report.kind.noun, trailing: { Text(report.range).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                if paid.isEmpty {
                    Text("No payroll, rent, bills or tax were paid by the companies in this period.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(paid.enumerated()), id: \.element.id) { i, m in
                            if i > 0 { Hairline() }
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.label).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineLimit(2)
                                    Text((companyID == nil ? m.companyName + " · " : "") + m.kind.title + " · " + GameCalendar.dateString(week: m.week))
                                        .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(fmt.signed(m.amount, company: m.companyID)).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.ivory)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            Text("Payroll that needs your approval arrives in the Inbox. Each line is in its company's own currency.")
                .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
        }
    }
}
