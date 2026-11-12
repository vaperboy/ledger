import SwiftUI
import GameCore
import Businesses
import Simulation

struct StatsApp: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        Group {
            if store.engine != nil { StatsOverview() } else { Color.clear }
        }
        .appScreen(title: "Stats", subtitle: PhoneApp.stats.subtitle)
        .accessibilityIdentifier("stats-app")
    }
}

// The one place for statistics: you, your companies, your money and your records.
struct StatsOverview: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        if let e = store.engine {
            PhonePageScroll(spacing: Theme.Space.xl) {
                you(e)
                companies(e)
                money(e)
                records(e)
            }
            .accessibilityIdentifier("stats-overview")
        }
    }

    private func fact(_ glyph: String, _ title: String, _ value: String, subtitle: String = "", tint: Color? = nil) -> some View {
        LedgerRow(leading: .glyph(glyph), title: title, subtitle: subtitle, value: value, valueTint: tint, density: .compact)
    }

    private func rows(_ items: [AnyView]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { (i: Int, v: AnyView) in
                if i > 0 { Hairline() }
                v
            }
        }
    }

    private func you(_ e: GameEngine) -> some View {
        let s = e.state
        let nw: Double = (store.netWorthNow ?? e.netWorth).total
        let level: PlayerLevel.Info = e.playerLevel
        let hist: DayHistory = store.dayHistoryNow ?? e.dayHistory
        let month: Double? = DayHistory.change(hist.netWorth, days: 30)?.amount
        return LedgerSection("You") {
            rows([
                AnyView(LedgerRow(leading: .glyph(Glyph.bank), title: "Net worth", subtitle: month.map { (m: Double) -> String in (m < 0 ? "Down " : "Up ") + store.short(abs(m)) + " in 30 days" } ?? "",
                                  value: store.short(nw), valueTint: nw < 0 ? Theme.loss : nil, density: .compact)),
                AnyView(fact(Glyph.goals, "Level \(level.level)", e.careerStatus.rank.title)),
                AnyView(fact(Glyph.clock, "Days in business", "\(s.week * 7 + s.day)")),
            ])
        }
        .accessibilityIdentifier("stats-you")
    }

    private func companies(_ e: GameEngine) -> some View {
        let list: [Company] = e.state.companies.filter { (c: Company) -> Bool in c.isOpenOrClosed }
        return LedgerSection("Companies") {
            if list.isEmpty {
                Text("Your companies show here once you open one.").textStyle(.caption)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { (i: Int, co: Company) in
                        let h: CompanyHealth = store.memo("coHealth\(co.id)") { $0.companyHealth(co) } ?? e.companyHealth(co)
                        if i > 0 { Hairline() }
                        LedgerRow(leading: .glyph(Glyph.stats), title: co.name,
                                  subtitle: "Sales " + store.short(h.revenueTTM, in: co) + " over the last year",
                                  value: store.short(h.profitTTM, in: co), valueTint: h.profitTTM < 0 ? Theme.loss : nil, density: .compact,
                                  action: { store.openCompany(co.id, section: .finances) })
                    }
                }
            }
        }
        .accessibilityIdentifier("stats-profit")
    }

    private func money(_ e: GameEngine) -> some View {
        let s = e.state
        let week: PeriodReport? = e.reports(.week).last
        var items: [AnyView] = []
        if let r = week {
            let p: ReportPnL = r.group.pnl
            items.append(AnyView(fact(Glyph.arrowIn, "Sales", store.short(p.revenue), subtitle: r.title)))
            items.append(AnyView(fact(Glyph.list, "Costs", store.short(p.costs))))
            items.append(AnyView(fact(Glyph.stats, "Profit", store.short(p.netProfit), tint: p.netProfit < 0 ? Theme.loss : nil)))
        }
        if s.stats.taxPaid > 0 { items.append(AnyView(fact(Glyph.list, "Tax paid in all", store.short(s.stats.taxPaid)))) }
        if s.stats.wagesPaid > 0 { items.append(AnyView(fact(Glyph.list, "Wages paid in all", store.short(s.stats.wagesPaid)))) }
        if s.stats.dividendsReceived > 0 { items.append(AnyView(fact(Glyph.arrowIn, "Dividends you received", store.short(s.stats.dividendsReceived)))) }
        items.append(AnyView(
            NavigationLink {
                ReportsContent(engine: e).appScreen(title: "Reports")
            } label: {
                LedgerRow(leading: .glyph(Glyph.reports), title: "Reports", subtitle: "Week, month, quarter and year", chevron: true, density: .compact, identifier: "stats-reports")
            }
            .buttonStyle(AcctPressStyle())))
        items.append(AnyView(
            NavigationLink {
                ActivityView().appScreen(title: "Where the money went")
            } label: {
                LedgerRow(leading: .glyph(Glyph.list), title: "Where the money went", chevron: true, density: .compact, identifier: "stats-money")
            }
            .buttonStyle(AcctPressStyle())))
        if Gates.reviewOpen(e.state) {
            items.append(AnyView(
                NavigationLink {
                    AnnualReportsScreen()
                } label: {
                    LedgerRow(leading: .glyph(Glyph.reports), title: "Annual reports", chevron: true, density: .compact, identifier: "stats-annual")
                }
                .buttonStyle(AcctPressStyle())))
        }
        let shown: [AnyView] = items
        return LedgerSection("Money") { rows(shown) }
            .accessibilityIdentifier("stats-money-section")
    }

    private func records(_ e: GameEngine) -> some View {
        let s = e.state
        let m: MilestoneProgress = e.milestoneProgress
        var items: [AnyView] = []
        if m.bestWeek > 0 { items.append(AnyView(fact(Glyph.arrowIn, "Best single week", store.short(m.bestWeek)))) }
        if m.bestStreak > 1 { items.append(AnyView(fact(Glyph.check, "Longest run of growing weeks", "\(m.bestStreak)"))) }
        if s.stats.companiesSold > 0 { items.append(AnyView(fact(Glyph.bank, "Companies sold", "\(s.stats.companiesSold)"))) }
        let shown: [AnyView] = items
        return LedgerSection("Records") {
            if shown.isEmpty {
                Text("Your best weeks and biggest wins appear here as you play.").textStyle(.caption)
            } else {
                rows(shown)
            }
        }
        .accessibilityIdentifier("stats-records")
    }
}
