import SwiftUI
import Charts
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The company's own figures on Stats (Master spec 2H): CASH first (one cash figure, with what payroll and tax will already need), then the result of
/// the period with the costs from the real books, then the legal and ownership facts. All from `companyOverviewStats`, so Overview and Stats read the
/// same numbers and cash is not repeated further down the page.
struct CompanyStatsFigures: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var period: StatsPeriod = .year

    enum StatsPeriod: String, CaseIterable, Hashable {
        case month = "This month", year = "This year"
        var kind: ReportPeriodKind { self == .month ? .month : .year }
    }

    private static let palette: [Color] = [Theme.slateBlue, Theme.caution, Theme.gain, Theme.gold, Theme.loss, Color(red: 0.36, green: 0.70, blue: 0.74), Color(red: 0.62, green: 0.50, blue: 0.80), Theme.goldDeep, Theme.ivoryFaint, Theme.ivoryMuted]

    var body: some View {
        let cur: Currency = engine.currency(for: company)
        if let s = engine.companyOverviewStats(companyID: company.id, period: period.kind) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                cashCard(s, cur)
                resultCard(s, cur)
                expensesCard(s, cur)
                legalCard(s, cur)
            }
        }
    }

    // MARK: Cash first

    private func cashCard(_ s: CompanyOverviewStats, _ cur: Currency) -> some View {
        let h = engine.companyHealth(company)
        let runway: String = h.runwayWeeks != nil ? "At the current rate of loss the cash lasts \(RunwayText.of(h))." : (s.runwayWeeks.map { String(format: "About %.0f weeks of costs in the bank.", $0) } ?? "")
        let runwayTint: Color = h.runwayWeeks.map { $0 < 8 ? Theme.loss : Theme.caution } ?? Theme.ivoryFaint
        let cashTint: Color = s.cash < 0 ? Theme.loss : Theme.ivory
        let freeTint: Color = s.reserves.free < 0 ? Theme.loss : Theme.ivory
        let cells: [StatStrip.Cell] = [
            .init(label: "Payroll reserve", value: cur.tidyShort(s.reserves.payroll)),
            .init(label: "Tax reserve", value: cur.tidyShort(s.reserves.tax)),
            .init(label: "Free to use", value: cur.tidyShort(s.reserves.free), tint: freeTint),
        ]
        return Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Company cash").capsLabel()
                Text(cur.tidyDisplay(s.cash)).font(.hero(34)).foregroundStyle(cashTint).minimumScaleFactor(0.6).lineLimit(1)
                if !runway.isEmpty { Text(runway).font(.system(size: 12)).foregroundStyle(runwayTint).fixedSize(horizontal: false, vertical: true) }
                StatStrip(cells: cells)
            }
        }
        .accessibilityIdentifier("stats-cash")
    }

    // MARK: Result of the period

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
        return CardSection(title: "Result", trailing: {
            SegmentedPill(items: StatsPeriod.allCases, title: { $0.rawValue }, selection: $period, identifier: { "stats-period-" + $0.kindName })
                .frame(width: 210)
        }) {
            StatStrip(cells: cells, ruled: false)
            if s.taxBooked > 0.5 {
                FlatRow(label: "Company tax booked", value: cur.tidyShort(s.taxBooked), sub: "shown apart: it is not in the profit above")
            }
            if s.loansOwed > 0.5 {
                FlatRow(label: "Loans owed", value: cur.tidyShort(s.loansOwed), sub: s.guaranteedLoans > 0.5 ? cur.tidyShort(s.guaranteedLoans) + " guaranteed by you" : "")
            }
        }
    }

    // MARK: Costs from the books

    @ViewBuilder private func expensesCard(_ s: CompanyOverviewStats, _ cur: Currency) -> some View {
        CardSection(title: "Where the money goes", trailing: {
            Text(s.period + " " + cur.tidyShort(s.operatingExpenses)).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
        }) {
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
