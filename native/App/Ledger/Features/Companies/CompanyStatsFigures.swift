import SwiftUI
import Charts
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The company's own figures on Stats > Finances: where the money goes first (the total in the box, no title), the margins
/// box right under it (no title), and later the company record (registration, capital, equity). Cash is not repeated here (it is on the Overview). All from
/// `companyOverviewStats`, so Overview and Stats read the same numbers.
struct CompanyStatsFigures: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    /// `spending` = where the money goes and the margins under it; `legal` = the company record not already in the settings rows.
    var block: Block = .spending
    @State private var period: StatsPeriod = .year

    enum Block { case spending, legal }

    enum StatsPeriod: String, CaseIterable, Hashable {
        case month = "This month", year = "This year"
        var kind: ReportPeriodKind { self == .month ? .month : .year }
    }

    private static let palette: [Color] = (0..<10).map { (i: Int) -> Color in ChartPalette.color(i).opacity(i < ChartPalette.series.count ? 1 : 0.5) }

    var body: some View {
        let cur: Currency = engine.currency(for: company)
        if let s = engine.companyOverviewStats(companyID: company.id, period: period.kind) {
            switch block {
            case .spending:
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    expensesCard(s, cur)
                    resultCard(s, cur)
                }
            case .legal:
                legalCard(s, cur)
            }
        }
    }

    // MARK: Margins (no title)

    private func resultCard(_ s: CompanyOverviewStats, _ cur: Currency) -> some View {
        let marginText: String = s.margin.map { Currency.percent($0, decimals: 0) } ?? "\u{2013}"
        let marginTint: Color = (s.margin ?? 0) < 0 ? Theme.loss : Theme.ink
        let money: (Double) -> String = { (v: Double) -> String in cur.tidyShort(v) }
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                resultCell("Revenue") { ArrowAmount(gain: s.revenue, format: money, live: true, step: .headline) }
                resultCell("Profit") { ArrowAmount(gain: s.profit, format: money, live: true, step: .headline) }
                resultCell("Margin") { Text(marginText).textStyle(.headline, tint: marginTint, numeric: true) }
            }
            .accessibilityElement(children: .combine)
            if s.taxBooked > 0.5 {
                FlatRow(label: "Company tax booked", value: cur.tidyShort(s.taxBooked), sub: "shown apart: it is not in the profit above")
            }
            // Loans owed are under Owed on this page; only the part you guarantee personally is added here.
            if s.guaranteedLoans > 0.5 {
                FlatRow(label: "Loans you guarantee", value: cur.tidyShort(s.guaranteedLoans), sub: "you pay these if the company cannot")
            }
        }
    }

    private func resultCell<V: View>(_ label: String, @ViewBuilder _ value: () -> V) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(label).textStyle(.label, tint: Theme.inkFaint).lineLimit(1)
            value().lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Where the money goes (no title): the total, the period, the split from the books

    private func expensesCard(_ s: CompanyOverviewStats, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SegmentedPill(items: StatsPeriod.allCases, title: { $0.rawValue }, selection: $period, identifier: { "stats-period-" + $0.kindName })
            Figure(label: "Costs", value: cur.tidyDisplay(s.operatingExpenses), size: .display)
            spendingSplit(s, cur)
        }
    }

    @ViewBuilder private func spendingSplit(_ s: CompanyOverviewStats, _ cur: Currency) -> some View {
        if s.expenses.isEmpty {
            EmptyState(glyph: Glyph.cost, title: "No costs booked in this period yet", centered: false)
        } else {
            VStack(spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.l) {
                    Chart(s.expenses) { l in
                        SectorMark(angle: .value("Amount", l.amount), innerRadius: .ratio(0.64), angularInset: 1.5)
                            .foregroundStyle(by: .value("Cost", l.label))
                            .cornerRadius(3)
                    }
                    .chartLegend(.hidden)
                    .chartForegroundStyleScale(range: Self.palette)
                    .frame(width: 112, height: 112)
                    .accessibilityHidden(true)
                    VStack(spacing: Theme.Space.s) {
                        ForEach(Array(s.expenses.prefix(5).enumerated()), id: \.offset) { i, l in
                            HStack(spacing: Theme.Space.xs) {
                                Circle().fill(Self.palette[i % Self.palette.count]).frame(width: 7, height: 7)
                                Text(l.label).textStyle(.caption).lineLimit(1)
                                Spacer(minLength: Theme.Space.xs)
                                Text("\(Int((l.share * 100).rounded()))%").textStyle(.caption, tint: Theme.inkFaint, numeric: true)
                            }
                        }
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(s.expenses.enumerated()), id: \.element.id) { n, l in
                        if n > 0 { CardLine() }
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                            Text(l.label).textStyle(.body).lineLimit(2)
                            Spacer(minLength: Theme.Space.s)
                            ArrowAmount(gain: -l.amount, amount: l.amount, format: { (v: Double) -> String in cur.tidyShort(v) }, live: true)
                        }
                        .padding(.vertical, Theme.Space.s)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    // MARK: Company record

    private struct RecordLine {
        var label: String
        var value: String
        var sub: String = ""
        var tint: Color? = nil
    }

    private func legalCard(_ s: CompanyOverviewStats, _ cur: Currency) -> some View {
        // The legal form, your share and (when you own it all) its worth are the Legal form and Ownership rows above: only the rest here.
        let ownsAll: Bool = company.ownership >= 99.5 && SaleListings.canSell(engine.state, companyID: company.id)
        var rows: [RecordLine] = []
        if !s.otherShareholders.isEmpty { rows.append(RecordLine(label: "Other shareholders", value: s.otherShareholders.joined(separator: ", "))) }
        if let since = s.incorporatedSince { rows.append(RecordLine(label: "Registered since", value: since)) }
        if s.shareCapital > 0.5 {
            rows.append(RecordLine(label: "Share capital", value: cur.tidyShort(s.shareCapital), sub: s.shareCount.map { String(Int($0)) + " shares" } ?? ""))
        }
        if let acc = s.accountant { rows.append(RecordLine(label: "Accountant", value: acc)) }
        rows.append(RecordLine(label: "Equity (assets less debts)", value: cur.tidyShort(s.equity), tint: s.equity < 0 ? Theme.loss : nil))
        if !ownsAll { rows.append(RecordLine(label: "Estimated value", value: cur.tidyShort(s.estimatedValue), sub: "an estimate of the whole company, not cash")) }
        return LedgerSection("Company record") {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { n, r in
                    FlatRow(label: r.label, value: r.value, sub: r.sub, tint: r.tint, rule: n > 0)
                }
            }
        }
    }
}

private extension CompanyStatsFigures.StatsPeriod {
    var kindName: String { self == .month ? "month" : "year" }
}
