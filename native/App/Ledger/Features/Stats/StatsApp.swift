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

struct StatsOverview: View {
    @EnvironmentObject var store: GameStore

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
                if !companies.isEmpty { profits(e, companies) }
                more(e)
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

    private func more(_ e: GameEngine) -> some View {
        LedgerSection("More") {
            VStack(spacing: 0) {
                NavigationLink {
                    ReportsContent(engine: e).appScreen(title: "Reports")
                } label: {
                    LedgerRow(leading: .glyph(Glyph.reports), title: "Reports", chevron: true, density: .compact, identifier: "stats-reports")
                }
                .buttonStyle(AcctPressStyle())
                Hairline()
                NavigationLink {
                    ActivityView().appScreen(title: "Where the money went")
                } label: {
                    LedgerRow(leading: .glyph(Glyph.list), title: "Where the money went", chevron: true, density: .compact, identifier: "stats-money")
                }
                .buttonStyle(AcctPressStyle())
                if Gates.reviewOpen(e.state) {
                    Hairline()
                    NavigationLink {
                        AnnualReportsScreen()
                    } label: {
                        LedgerRow(leading: .glyph(Glyph.reports), title: "Annual reports", chevron: true, density: .compact, identifier: "stats-annual")
                    }
                    .buttonStyle(AcctPressStyle())
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
}
