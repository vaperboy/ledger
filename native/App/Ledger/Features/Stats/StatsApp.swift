import SwiftUI
import GameCore
import Businesses
import Simulation

struct StatsApp: View {
    @EnvironmentObject var store: GameStore
    enum Tab: String, CaseIterable, Hashable { case overview = "Overview", reports = "Reports", money = "Money" }
    @State private var tab: Tab = .overview

    var body: some View {
        Group {
            if let e = store.engine {
                VStack(spacing: 0) {
                    SegmentedPill(items: Tab.allCases, title: { (t: Tab) -> String in t.rawValue }, selection: $tab,
                                  identifier: { (t: Tab) -> String in "stats-tab-\(t.rawValue)" })
                        .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.xs)
                        .frame(maxWidth: 760).frame(maxWidth: .infinity)
                    switch tab {
                    case .overview: StatsOverview()
                    case .reports:
                        ReportsContent(engine: e)
                            .safeAreaInset(edge: .bottom, spacing: 0) { AnnualReportsLink().background(Theme.page) }
                    case .money: ActivityView()
                    }
                }
            } else {
                Color.clear
            }
        }
        .appScreen(title: "Stats", subtitle: PhoneApp.stats.subtitle)
        .accessibilityIdentifier("stats-app")
    }
}

struct StatsOverview: View {
    @EnvironmentObject var store: GameStore
    @State private var companyID = 0
    @State private var months = 12

    private struct Fact: Identifiable {
        var id: String
        var glyph: String
        var title: String
        var value: String
    }

    var body: some View {
        if let e = store.engine {
            let companies: [Company] = e.state.companies.filter { (c: Company) -> Bool in c.isOpenOrClosed }
            PhonePageScroll(spacing: Theme.Space.xl) {
                facts(e)
                if !companies.isEmpty {
                    profits(e, companies)
                    overTime(e, companies)
                }
            }
            .accessibilityIdentifier("stats-overview")
        }
    }

    private func factList(_ e: GameEngine) -> [Fact] {
        let s = e.state
        let m: MilestoneProgress = e.milestoneProgress
        var out: [Fact] = [Fact(id: "days", glyph: Glyph.clock, title: "Days in business", value: "\(s.week * 7 + s.day)")]
        if m.bestWeek > 0 { out.append(Fact(id: "week", glyph: Glyph.arrowIn, title: "Best single week", value: store.short(m.bestWeek))) }
        if m.bestStreak > 1 { out.append(Fact(id: "run", glyph: Glyph.check, title: "Longest run of growing weeks", value: "\(m.bestStreak)")) }
        if s.stats.companiesSold > 0 { out.append(Fact(id: "sold", glyph: Glyph.bank, title: "Companies sold", value: "\(s.stats.companiesSold)")) }
        if s.stats.dividendsReceived > 0 { out.append(Fact(id: "div", glyph: Glyph.arrowIn, title: "Dividends you received", value: store.short(s.stats.dividendsReceived))) }
        if s.stats.taxPaid > 0 { out.append(Fact(id: "tax", glyph: Glyph.list, title: "Tax paid in all", value: store.short(s.stats.taxPaid))) }
        if s.stats.wagesPaid > 0 { out.append(Fact(id: "wages", glyph: Glyph.list, title: "Wages paid in all", value: store.short(s.stats.wagesPaid))) }
        return out
    }

    private func facts(_ e: GameEngine) -> some View {
        let list: [Fact] = factList(e)
        return LedgerSection("Your run") {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { (i: Int, f: Fact) in
                    if i > 0 { Hairline() }
                    LedgerRow(leading: .glyph(f.glyph), title: f.title, value: f.value, density: .compact)
                }
            }
        }
    }

    private func profits(_ e: GameEngine, _ companies: [Company]) -> some View {
        LedgerSection("Profit by company") {
            VStack(spacing: 0) {
                ForEach(Array(companies.enumerated()), id: \.element.id) { (i: Int, co: Company) in
                    let h: CompanyHealth = store.memo("coHealth\(co.id)") { $0.companyHealth(co) } ?? e.companyHealth(co)
                    if i > 0 { Hairline() }
                    LedgerRow(leading: .glyph(Glyph.stats), title: co.name,
                              subtitle: "Sales " + store.short(h.revenueTTM, in: co) + " over the last year",
                              value: store.short(h.profitTTM, in: co),
                              valueTint: h.profitTTM < 0 ? Theme.loss : nil, density: .compact)
                }
            }
        }
        .accessibilityIdentifier("stats-profit")
    }

    private func overTime(_ e: GameEngine, _ companies: [Company]) -> some View {
        let co: Company = companies.first(where: { (c: Company) -> Bool in c.id == companyID }) ?? companies[0]
        let h: CompanyHealth = store.memo("coHealth\(co.id)") { $0.companyHealth(co) } ?? e.companyHealth(co)
        let rev: [Double] = Array(h.revenueSeries.suffix(months))
        let prof: [Double] = Array(h.profitSeries.suffix(months))
        return LedgerSection(title: "By month", trailing: {
            HStack(spacing: Theme.Space.m) {
                if companies.count > 1 {
                    Menu {
                        ForEach(companies) { (c: Company) in
                            Button(c.name) { Haptics.choose(); companyID = c.id }
                        }
                    } label: { Text(co.name).textStyle(.caption, tint: Theme.accent).lineLimit(1).frame(minHeight: 44) }
                        .accessibilityIdentifier("stats-chart-company")
                }
                Menu {
                    ForEach([6, 12, 24], id: \.self) { (m: Int) in
                        Button(m == 6 ? "6 months" : (m == 12 ? "1 year" : "2 years")) { Haptics.choose(); months = m }
                    }
                } label: { Text(months == 6 ? "6 months" : (months == 12 ? "1 year" : "2 years")).textStyle(.caption, tint: Theme.accent).frame(minHeight: 44) }
                    .accessibilityIdentifier("stats-chart-span")
            }
        }, content: {
            ChartFrame(key: [("Revenue", Theme.accent), ("Profit", Theme.gain)], height: 120, isEmpty: rev.count < 2,
                       emptyText: "The chart starts after the first full month.") {
                RevenueProfitChart(revenue: rev, profit: prof, format: { (v: Double) -> String in store.short(v, in: co) }, height: 120)
            }
        })
        .accessibilityIdentifier("stats-by-month")
    }
}
