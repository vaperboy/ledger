import XCTest
import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Simulation
import Investments

/// LEDGER_MOCKDATA=<path>: plays a richer demo game (six companies, about fourteen months) and writes the figures the design
/// mockups use, in pounds, so mockups show real game output instead of invented numbers. Not part of the regular suite.
final class MockDataExport: XCTestCase {
    func testExportMockData() throws {
        guard let path = ProcessInfo.processInfo.environment["LEDGER_MOCKDATA"] else { return }
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Alex Carter", seed: 2027)
        e.update { s, _, _ in Ledger.move(&s, .me, 45_000_000, why: "Demo funds") }
        func start(_ t: String, _ city: String, _ fund: Double) { _ = e.startCompany(tradeID: t, cityID: city, form: .limited, fundWith: fund) }
        func play(_ days: Int) { for _ in 0..<days { e.nextDay(); for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }; if e.state.isGameOver { break } } }
        start("acctfirm", "lon", 2_500_000); start("cafe", "lon", 4_000_000); start("gym", "man", 14_000_000)
        for (k, n) in [("google", 1), ("seo", 1)] { if let ch = e.marketing.channels[k], let id = e.state.liveCompanies.first?.id { _ = e.setCampaign(companyID: id, channel: k, weeklyBudget: ch.budgetOptions[n]) } }
        play(150)
        start("carrental", "bir", 6_000_000); start("bakery", "man", 12_000_000)
        play(120)
        start("webdev", "lon", 2_500_000)
        for q in e.quotes(.stock).prefix(4) { _ = e.buyInvestment(.stock, symbol: q.symbol, amount: 2_000_000) }
        for q in e.quotes(.fund).prefix(1) { _ = e.buyInvestment(.fund, symbol: q.symbol, amount: 3_000_000) }
        play(160)

        let r = e.homeCurrency.rate
        func p(_ v: Double) -> Double { (v / r).rounded() }
        let nw = e.netWorth, h = e.dayHistory
        var cos: [[String: Any]] = []
        for co in e.state.companies where co.type != "hold" {
            let hh = e.companyHealth(co)
            let cr = e.currency(for: co).rate
            func c(_ v: Double) -> Double { (v / cr).rounded() }
            cos.append([
                "name": co.name, "trade": e.tradeName(co), "city": e.cityName(co), "form": co.form == .limited ? "Ltd" : "Sole trader",
                "status": co.status.rawValue, "health": hh.label, "value": c(hh.value), "revenueTTM": c(hh.revenueTTM), "profitTTM": c(hh.profitTTM),
                "margin": hh.marginTTM ?? 0, "growth": hh.revenueGrowth ?? NSNull(), "cash": c(co.cash), "debt": c(hh.debt), "staff": co.staff.count,
                "weeklyCost": c(hh.weeklyCost), "weeksOfCash": hh.weeksOfCash, "runway": hh.runwayWeeks ?? NSNull(),
                "capacityUse": hh.capacityUse, "demandCoverage": hh.demandCoverage, "rating": hh.rating, "reputation": co.reputation, "quality": co.quality,
                "awareness": co.awareness, "bottleneck": hh.bottleneck ?? NSNull(), "served": hh.servedLastWeek, "capacity": hh.capacityLastWeek,
                "revenueSeries": hh.revenueSeries.map(c), "profitSeries": hh.profitSeries.map(c), "cashSeries": hh.cashSeries.map(c),
                "monthRevenue": c(co.books.month["rev"] ?? 0), "monthProfit": c(Books.profit(co.books.month)),
                "insights": e.insights(for: co, limit: 5).map { ["text": $0.text, "tone": $0.tone.rawValue, "section": $0.section ?? ""] },
                "staffList": co.staff.prefix(8).map { ["name": e.state.people[$0.id]?.name ?? $0.role, "role": e.data.catalog.tables.roles[$0.role]?.name ?? $0.role, "wage": c($0.monthlyWage)] },
                "upcoming": e.financeOverview(companyID: co.id).upcoming.prefix(4).map { ["title": $0.title, "amount": p($0.amount), "date": $0.dateText, "days": $0.daysAway] },
            ])
        }
        let fo = e.financeOverview()
        let out: [String: Any] = [
            "player": e.state.player.name, "date": e.date, "week": e.state.week + 1, "country": e.homeCountry.name, "flag": e.homeCountry.flag,
            "netWorth": p(nw.total), "personal": p(nw.personal), "investments": p(nw.investments), "companies": p(nw.companies), "debt": p(nw.debt), "pendingTax": p(nw.pendingTax),
            "assets": p(nw.totalAssets),
            "nwDaily": h.netWorth.map(p), "nwWeekly": h.weeklyNetWorth.map(p), "cashDaily": h.cash.map(p), "invDaily": h.invested.map(p), "coDaily": h.companies.map(p),
            "companyList": cos,
            "upcoming": fo.upcoming.prefix(6).map { ["title": $0.title, "amount": p($0.amount), "date": $0.dateText, "days": $0.daysAway, "essential": $0.essential] },
            "due30": p(fo.dueWithin30Days), "cashAvailable": p(fo.cashAvailable), "taxesOwed": p(fo.taxesOwed),
            "decisions": e.openDecisions.prefix(4).map { ["title": e.localized($0.title, companyID: $0.companyID), "from": $0.from, "body": e.localized($0.body, companyID: $0.companyID)] },
            "suggestions": e.suggestions(limit: 4).map { ["title": $0.title, "detail": $0.detail, "tone": $0.tone.rawValue] },
            "economy": e.state.economy.phase, "policyRate": e.state.economy.policyRate, "inflation": e.state.economy.inflation,
            "savings": p(e.state.savings), "cashAccount": p(e.state.cash), "credit": Banking.creditWord(e.state.credit),
            "loans": e.state.loans.filter { $0.companyID == 0 }.map { ["name": $0.name, "balance": p($0.balance), "payment": p($0.monthlyPayment)] },
            "statement": e.state.statement.prefix(8).map { ["label": $0.label, "amount": p($0.amount)] },
            "holdings": e.quotes(.stock).filter { $0.value > 0 }.map { ["symbol": $0.symbol, "name": $0.name, "value": p($0.value), "week": $0.weekChange ?? 0] },
        ]
        let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }
}
