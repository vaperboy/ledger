import SwiftUI
import Charts
import GameCore
import Countries
import Finance
import Simulation

/// The Statements tab: the account's week, month or year statement (opening and closing balance, money in and out, the movements), where
/// the business money went (the old Costs page), and the full Reports. A statement exists once a period has closed.
struct BankStatementsTab: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var account: BankAccountID
    var detail: BankAccountDetail
    @State private var kind: ReportKind = .week
    @State private var back = 0
    @State private var yearlyCosts = false

    var body: some View {
        if let e = store.engine {
            let fmt = BankFmt.make(store, account)
            let all: [PeriodReport] = e.reports(kind)
            let index: Int = max(0, all.count - 1 - back)
            let reportID: Int? = all.indices.contains(index) ? all[index].id : nil
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                SegmentedPill(items: ReportKind.allCases, title: { $0.title }, selection: $kind)
                    .onChange(of: kind) { _, _ in back = 0 }
                if let s = e.bankStatement(account, kind: kind, reportID: reportID) {
                    statement(s, fmt, count: all.count)
                } else {
                    EmptyState(glyph: Glyph.reports, title: "No statement yet", message: "It appears when the first \(kind.rawValue) closes.")
                }
                costs(e, fmt)
                NavigationLink { ReportsScreen(companyID: account.companyID).environment(\.outsidePalette, OutsidePalette.game) } label: {
                    LedgerRow(leading: .glyph(Glyph.reports), title: "Full reports", subtitle: "Profit, costs and people", chevron: true)
                }.buttonStyle(AcctPressStyle())
            }
        }
    }

    /// The statement: the closing balance leads, money in and out under it, then the period stepper and the movements.
    private func statement(_ s: BankStatement, _ fmt: BankFmt, count: Int) -> some View {
        let net: Double = s.closing - s.opening
        let context: String = "+\(fmt.short(s.moneyIn)) in \u{00B7} \u{2212}\(fmt.short(s.moneyOut)) out \u{00B7} opened at \(fmt.short(s.opening))"
        return VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                MoneyHero(label: "Closing balance \u{00B7} " + s.title, value: fmt.full(s.closing), tint: s.closing < 0 ? P.loss : nil,
                          context: context, contextTint: P.change(net))
                HStack(spacing: Theme.Space.s) {
                    Button { back = min(back + 1, count - 1); Haptics.choose() } label: { Text("\u{2039} Earlier") }
                        .buttonStyle(TertiaryButtonStyle(size: .compact)).disabled(back >= count - 1)
                    Spacer(minLength: Theme.Space.s)
                    Text(s.range.tidyText).textStyle(.caption, tint: P.inkFaint).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: Theme.Space.s)
                    Button { back = max(back - 1, 0); Haptics.choose() } label: { Text("Later \u{203A}") }
                        .buttonStyle(TertiaryButtonStyle(size: .compact)).disabled(back == 0)
                }
            }
            MoneyGroup("Movements") {
                if s.lines.isEmpty {
                    EmptyState(glyph: BankGlyph.transfer, title: "No movements kept for this period.", centered: false).padding(.vertical, Theme.Space.s)
                }
                ForEach(Array(s.lines.prefix(60).enumerated()), id: \.element.id) { n, t in
                    if n > 0 { MoneyRule(inset: 0) }
                    BankTransactionRow(transaction: t, fmt: fmt)
                }
                if s.lines.count > 60 { Text("The latest 60 of \(s.lines.count) movements.").textStyle(.caption, tint: P.inkFaint).padding(.top, Theme.Space.s) }
            }
        }
    }

    // MARK: Where the money goes

    private var palette: [Color] { [Theme.slateBlue, P.caution, P.gain, P.accent, P.loss, Color(red: 0.36, green: 0.70, blue: 0.74), Color(red: 0.62, green: 0.50, blue: 0.80), Theme.goldDeep, P.inkFaint, P.inkSoft, Theme.glass, Theme.goldLight] }

    @ViewBuilder private func costs(_ e: GameEngine, _ fmt: BankFmt) -> some View {
        if account != .investments {
            let o = e.financeOverview(companyID: account.companyID)
            let lines: [FinanceLine] = yearlyCosts ? o.costsThisYear : o.costsThisMonth
            let total: Double = yearlyCosts ? o.costTotalThisYear : o.costTotalThisMonth
            BankCard(title: "Where the money goes", trailing: yearlyCosts ? "This year" : "This month") {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SegmentedChoice(items: [false, true], title: { $0 ? "This year" : "This month" }, selection: $yearlyCosts)
                    if lines.isEmpty { EmptyState(glyph: BankGlyph.bill, title: "No costs booked yet.", centered: false) }
                    else { donut(lines, total, fmt) }
                }
            }
        }
    }

    private func donut(_ lines: [FinanceLine], _ total: Double, _ fmt: BankFmt) -> some View {
        VStack(spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.l) {
                ZStack {
                    Chart(lines) { l in
                        SectorMark(angle: .value("Amount", l.amount), innerRadius: .ratio(0.64), angularInset: 1.5)
                            .foregroundStyle(by: .value("Cost", l.label))
                            .cornerRadius(3)
                    }
                    .chartLegend(.hidden)
                    .chartForegroundStyleScale(range: palette)
                    VStack(spacing: 1) {
                        Text(fmt.short(total)).font(.figure(16, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
                        Text("Total").font(.caption2).foregroundStyle(P.inkFaint)
                    }.padding(18)
                }
                .frame(width: 132, height: 132)
                VStack(spacing: 7) {
                    ForEach(Array(lines.prefix(6).enumerated()), id: \.offset) { i, l in
                        HStack(spacing: 6) {
                            Circle().fill(palette[i % palette.count]).frame(width: 7, height: 7)
                            Text(l.label).font(.caption).foregroundStyle(P.inkSoft).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(Int((l.share * 100).rounded()))%").font(.caption2.monospacedDigit()).foregroundStyle(P.inkFaint)
                        }
                    }
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.element.id) { n, l in FlatRow(label: l.label, value: fmt.short(l.amount), rule: n > 0) }
            }
        }
    }
}
