import SwiftUI
import Charts
import GameCore
import Countries
import Finance
import Businesses
import Simulation

struct CompanyStatsFigures: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
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
            if let f = s.localName {
                FlatRow(label: "Name in \(f.city)", value: f.word, sub: f.note)
            }
            if s.taxBooked > 0.5 {
                FlatRow(label: "Company tax booked", value: cur.tidyShort(s.taxBooked), sub: "not in the profit above")
            }
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
                                Text("\(Int(saturating: (l.share * 100).rounded()))%").textStyle(.caption, tint: Theme.inkFaint, numeric: true)
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

    private struct RecordLine {
        var label: String
        var value: String
        var sub: String = ""
        var tint: Color? = nil
    }

    private func legalCard(_ s: CompanyOverviewStats, _ cur: Currency) -> some View {
        let ownsAll: Bool = company.ownership >= 99.5 && SaleListings.canSell(engine.state, companyID: company.id)
        var rows: [RecordLine] = []
        if !s.otherShareholders.isEmpty { rows.append(RecordLine(label: "Other shareholders", value: s.otherShareholders.joined(separator: ", "))) }
        if let since = s.incorporatedSince { rows.append(RecordLine(label: "Registered since", value: since)) }
        if s.shareCapital > 0.5 {
            rows.append(RecordLine(label: "Share capital", value: cur.tidyShort(s.shareCapital), sub: s.shareCount.map { String(Int($0)) + " shares" } ?? ""))
        }
        rows.append(RecordLine(label: "Equity (assets less debts)", value: cur.tidyShort(s.equity), tint: s.equity < 0 ? Theme.loss : nil))
        if !ownsAll { rows.append(RecordLine(label: "Estimated value", value: cur.tidyShort(s.estimatedValue), sub: "not cash")) }
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
