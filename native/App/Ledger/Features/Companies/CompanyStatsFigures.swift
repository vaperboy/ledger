import SwiftUI
import Charts
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The company's own figures on Stats > Finances: where the money goes first (the total in the box, no title), the margins
/// box right under it (no title), and later the legal and ownership facts. Cash is not repeated here (it is on the Overview). All from
/// `companyOverviewStats`, so Overview and Stats read the same numbers.
struct CompanyStatsFigures: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    /// `spending` = where the money goes and the margins under it; `legal` = legal form and ownership.
    var block: Block = .spending
    @State private var period: StatsPeriod = .year

    enum Block { case spending, legal }

    enum StatsPeriod: String, CaseIterable, Hashable {
        case month = "This month", year = "This year"
        var kind: ReportPeriodKind { self == .month ? .month : .year }
    }

    private static let palette: [Color] = [Theme.slateBlue, Theme.caution, Theme.gain, Theme.gold, Theme.loss, Color(red: 0.36, green: 0.70, blue: 0.74), Color(red: 0.62, green: 0.50, blue: 0.80), Theme.goldDeep, Theme.ivoryFaint, Theme.ivoryMuted]

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
        let profitTint: Color = s.profit < 0 ? Theme.loss : Theme.ivory
        let marginText: String = s.margin.map { Currency.percent($0, decimals: 0) } ?? "\u{2013}"
        let marginTint: Color = (s.margin ?? 0) < 0 ? Theme.loss : Theme.ivory
        let cells: [StatStrip.Cell] = [
            .init(label: "Revenue", value: cur.tidyShort(s.revenue)),
            .init(label: "Costs", value: cur.tidyShort(s.operatingExpenses)),
            .init(label: "Profit", value: cur.tidyShort(s.profit), tint: profitTint),
            .init(label: "Margin", value: marginText, tint: marginTint),
        ]
        return Card(padding: 14, radius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                StatStrip(cells: cells, ruled: false)
                if s.taxBooked > 0.5 {
                    FlatRow(label: "Company tax booked", value: cur.tidyShort(s.taxBooked), sub: "shown apart: it is not in the profit above")
                }
                if s.loansOwed > 0.5 {
                    FlatRow(label: "Loans owed", value: cur.tidyShort(s.loansOwed), sub: s.guaranteedLoans > 0.5 ? cur.tidyShort(s.guaranteedLoans) + " guaranteed by you" : "")
                }
            }
        }
    }

    // MARK: Where the money goes (no title): the total, the period, the split from the books

    private func expensesCard(_ s: CompanyOverviewStats, _ cur: Currency) -> some View {
        Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .center) {
                    Text(cur.tidyDisplay(s.operatingExpenses)).font(.hero(28)).foregroundStyle(Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
                    Spacer(minLength: 8)
                    SegmentedPill(items: StatsPeriod.allCases, title: { $0.rawValue }, selection: $period, identifier: { "stats-period-" + $0.kindName })
                        .frame(width: 210)
                }
                spendingSplit(s, cur)
            }
        }
    }

    @ViewBuilder private func spendingSplit(_ s: CompanyOverviewStats, _ cur: Currency) -> some View {
        if s.expenses.isEmpty {
            Text("No costs booked in this period yet.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
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
                    VStack(spacing: 7) {
                        ForEach(Array(s.expenses.prefix(5).enumerated()), id: \.offset) { i, l in
                            HStack(spacing: 6) {
                                Circle().fill(Self.palette[i % Self.palette.count]).frame(width: 7, height: 7)
                                Text(l.label).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
                                Spacer(minLength: 4)
                                Text("\(Int((l.share * 100).rounded()))%").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
                            }
                        }
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(s.expenses.enumerated()), id: \.element.id) { n, l in
                        FlatRow(label: l.label, value: cur.tidyShort(l.amount), rule: n > 0)
                    }
                }
            }
        }
    }

    // MARK: Legal and ownership

    private func legalCard(_ s: CompanyOverviewStats, _ cur: Currency) -> some View {
        let holders: String = s.otherShareholders.isEmpty ? "None" : s.otherShareholders.joined(separator: ", ")
        return CardSection("Legal and ownership") {
            VStack(spacing: 0) {
                FlatRow(label: "Legal form", value: s.legalForm, rule: false)
                if let since = s.incorporatedSince { FlatRow(label: "Registered since", value: since) }
                FlatRow(label: "You own", value: Currency.percent(s.ownershipPercent / 100, decimals: 0), sub: s.otherShareholders.isEmpty ? "" : "Others: " + holders)
                if s.shareCapital > 0.5 { FlatRow(label: "Share capital", value: cur.tidyShort(s.shareCapital), sub: s.shareCount.map { String(Int($0)) + " shares" } ?? "") }
                if let acc = s.accountant { FlatRow(label: "Accountant", value: acc) }
                FlatRow(label: "Equity (assets less debts)", value: cur.tidyShort(s.equity), tint: s.equity < 0 ? Theme.loss : nil)
                FlatRow(label: "Estimated value", value: cur.tidyShort(s.estimatedValue), sub: "an estimate of the whole company, not cash")
            }
        }
    }
}

private extension CompanyStatsFigures.StatsPeriod {
    var kindName: String { self == .month ? "month" : "year" }
}
