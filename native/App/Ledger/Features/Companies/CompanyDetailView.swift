import SwiftUI
import Charts
import GameCore
import Countries
import Finance
import Businesses
import Simulation

enum CompanySection: String, CaseIterable, Hashable {
    case overview = "Overview", team = "Team", money = "Money", operations = "Operations", marketing = "Marketing", setup = "Setup"
}

struct CompanyDetailView: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    @State private var section: CompanySection = .overview

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    header(e, co)
                    SectionTabs(items: sections(co), title: { $0.rawValue }, selection: $section).padding(.horizontal, -Theme.Space.l)
                    switch section {
                    case .overview: CompanyOverview(engine: e, company: co)
                    case .team: CompanyTeam(engine: e, company: co)
                    case .money: CompanyMoney(engine: e, company: co)
                    case .operations: CompanyOperations(engine: e, company: co)
                    case .marketing: CompanyMarketing(engine: e, company: co)
                    case .setup: CompanySetupSection(engine: e, company: co)
                    }
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .ledgerBackground()
            .navigationTitle(co.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if co.status == .setup { section = .setup } }
        } else {
            Text("This company no longer exists.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    private func sections(_ co: Company) -> [CompanySection] {
        co.status == .setup ? [.setup, .overview, .money] : CompanySection.allCases.filter { $0 != .setup || co.status == .setup }
    }

    private func header(_ e: GameEngine, _ co: Company) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(e.tradeName(co)) · \(e.cityName(co))").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                Text(co.form == .limited ? "Limited company" : "Sole trader").font(.caption).foregroundStyle(Theme.ivoryFaint)
            }
            Spacer()
            StatusChip(company: co)
        }
    }
}

// MARK: Overview

struct CompanyOverview: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var months = 12

    private func tint(_ label: String) -> Color {
        switch label { case "Thriving", "Healthy": return Theme.gain; case "Tight": return Theme.caution; case "Struggling": return Theme.loss; default: return Theme.ivoryMuted }
    }

    private struct Point: Identifiable { var id: Int; var series: String; var value: Double }

    var body: some View {
        let co = company
        let h = engine.companyHealth(co)
        VStack(spacing: Theme.Space.l) {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Company value").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                        Spacer()
                        Chip(text: h.label, tint: tint(h.label), symbol: h.label == "Struggling" ? "exclamationmark.triangle.fill" : "leaf.fill")
                    }
                    Text(store.money(h.value, in: co)).font(.figure(32, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
                    if let g = h.revenueGrowth {
                        Chip(text: String(format: "%@%.1f%% revenue, 3 months", g >= 0 ? "+" : "−", abs(g) * 100), tint: Theme.change(g), symbol: g >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    }
                }
            }
            HStack(spacing: Theme.Space.m) {
                tile("Revenue (12 mo)", store.short(h.revenueTTM, in: co), sub: h.revenueGrowth.map { String(format: "%+.1f%%", $0 * 100) }, subTint: Theme.change(h.revenueGrowth ?? 0))
                tile("Net profit (12 mo)", store.short(h.profitTTM, in: co), sub: h.revenueTTM > 0 ? String(format: "%.0f%% margin", h.profitTTM / h.revenueTTM * 100) : nil, subTint: Theme.change(h.profitTTM), tint: h.profitTTM < 0 ? Theme.loss : Theme.ivory)
            }
            HStack(spacing: Theme.Space.m) {
                tile("Cash", store.short(co.cash, in: co), tint: co.cash < 0 ? Theme.loss : Theme.ivory)
                tile("Debt", store.short(h.debt, in: co))
                tile("Employees", String(co.staff.count))
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack {
                        Text("Performance").font(.bodyText.weight(.semibold))
                        Spacer()
                        ForEach([6, 12, 24], id: \.self) { m in
                            Button { months = m; Haptics.choose() } label: {
                                Text(m == 6 ? "6M" : m == 12 ? "1Y" : "2Y").font(.caption2.weight(.semibold))
                                    .foregroundStyle(months == m ? Color(red: 0.14, green: 0.10, blue: 0.05) : Theme.ivoryMuted)
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .background(Capsule().fill(months == m ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Color.clear)))
                            }.buttonStyle(.plain)
                        }
                    }
                    let rev = Array(h.revenueSeries.suffix(months)), prof = Array(h.profitSeries.suffix(months))
                    if rev.count < 2 {
                        Text("History builds up month by month.").font(.caption).foregroundStyle(Theme.ivoryFaint).frame(maxWidth: .infinity, minHeight: 90)
                    } else {
                        let revPoints: [Point] = rev.enumerated().map { (i, v) in Point(id: i, series: "Revenue", value: v) }
                        let profPoints: [Point] = prof.enumerated().map { (i, v) in Point(id: 1000 + i, series: "Profit", value: v) }
                        let points: [Point] = revPoints + profPoints
                        Chart(points) { p in
                            LineMark(x: .value("Month", p.id % 1000), y: .value("Amount", p.value), series: .value("Series", p.series))
                                .foregroundStyle(by: .value("Series", p.series))
                                .interpolationMethod(.monotone)
                        }
                        .chartForegroundStyleScale(["Revenue": Theme.gold, "Profit": Theme.gain])
                        .chartLegend(.hidden)
                        .chartXAxis(.hidden)
                        .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Theme.hairline) } }
                        .frame(height: 130)
                        HStack(spacing: Theme.Space.l) {
                            HStack(spacing: 5) { Circle().fill(Theme.gold).frame(width: 7, height: 7); Text("Revenue").font(.caption).foregroundStyle(Theme.ivoryMuted) }
                            HStack(spacing: 5) { Circle().fill(Theme.gain).frame(width: 7, height: 7); Text("Profit").font(.caption).foregroundStyle(Theme.ivoryMuted) }
                            Spacer()
                            Text("Last \(rev.count) months").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        }
                    }
                }
            }
            if co.status == .open {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        Text("Operations").font(.bodyText.weight(.semibold))
                        HStack(alignment: .top) {
                            Ring(label: "Capacity", fraction: h.capacityUse, centre: "\(Int((h.capacityUse * 100).rounded()))%", tint: h.capacityUse > 0.95 ? Theme.caution : Theme.gold)
                            Ring(label: "Demand met", fraction: h.demandCoverage > 0 ? min(1, 1 / h.demandCoverage) : 0, centre: h.demandCoverage > 0 ? "\(Int((min(1, 1 / h.demandCoverage) * 100).rounded()))%" : "–", tint: Theme.roseGold)
                            Ring(label: "Rating", fraction: h.rating / 5, centre: String(format: "%.1f", h.rating), tint: Theme.gain)
                        }
                    }
                }
            }
            let insights = engine.insights(for: co, limit: 4)
            if !insights.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        Text("Key insights").font(.bodyText.weight(.semibold))
                        ForEach(insights) { i in
                            ListRow(symbol: i.symbol, tint: Theme.tone(i.tone.rawValue) == Theme.ivoryMuted ? Theme.gold : Theme.tone(i.tone.rawValue), title: i.text)
                        }
                    }
                }
            }
            Card {
                VStack(spacing: Theme.Space.m) {
                    Meter(label: "Reputation", value: co.reputation)
                    Meter(label: "Quality", value: co.quality)
                    Meter(label: "Awareness", value: co.awareness)
                }
            }
            NavigationLink { FinanceView(companyID: co.id) } label: {
                Card { ListRow(symbol: "chart.pie", title: "Finance & taxes", subtitle: "Payments, taxes, costs and reports", chevron: true) }
            }.buttonStyle(.plain)
            if co.cash < 0 || co.weeksNegative > 0 || co.unpaidMonths > 0 {
                Card {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Warning", systemImage: "exclamationmark.triangle").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.loss)
                        if co.cash < 0 { Text("The account is overdrawn. Put money in before bills fall due.").font(.caption).foregroundStyle(Theme.ivoryMuted) }
                        if co.weeksNegative > 0 { Text("Negative for \(co.weeksNegative) week\(co.weeksNegative == 1 ? "" : "s"). Long spells can end in bankruptcy.").font(.caption).foregroundStyle(Theme.ivoryMuted) }
                        if co.unpaidMonths > 0 { Text("\(co.unpaidMonths) month\(co.unpaidMonths == 1 ? "" : "s") of wages unpaid. Staff will start leaving.").font(.caption).foregroundStyle(Theme.ivoryMuted) }
                    }
                }
            }
        }
    }

    private func tile(_ title: String, _ value: String, sub: String? = nil, subTint: Color = Theme.ivoryMuted, tint: Color = Theme.ivory) -> some View {
        Card(padding: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(Theme.ivoryMuted).lineLimit(1).minimumScaleFactor(0.8)
                Text(value).font(.figure(18, weight: .bold)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
                if let sub { Text(sub).font(.caption2.weight(.semibold)).foregroundStyle(subTint) }
            }
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
        }
    }
}

// MARK: Setup

struct CompanySetupSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        let items = engine.openingChecklist(companyID: company.id)
        VStack(spacing: Theme.Space.l) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionLabel("Before opening")
                    if items.isEmpty { Text("Nothing left to do.").font(.bodyText).foregroundStyle(Theme.ivoryMuted) }
                    ForEach(items) { it in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: it.isDone ? "checkmark.circle.fill" : "circle").foregroundStyle(it.isDone ? Theme.gain : Theme.ivoryFaint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(it.title).font(.bodyText.weight(.medium)).foregroundStyle(it.isDone ? Theme.ivoryMuted : Theme.ivory)
                                if !it.detail.isEmpty { Text(it.detail).font(.caption).foregroundStyle(Theme.ivoryFaint) }
                            }
                        }
                    }
                }
            }
            if company.status == .setup {
                Button("Fill in what is missing") {
                    let bought = store.act { $0.quickSetup(companyID: company.id) } ?? []
                    store.show(bought.isEmpty ? "Nothing to add." : "Added: \(bought.prefix(3).joined(separator: ", "))\(bought.count > 3 ? "…" : "")", tone: "good")
                    Haptics.success()
                }.buttonStyle(QuietButtonStyle())
                Button("Open for business") {
                    let r = store.act { $0.openCompany(companyID: company.id) }
                    switch r {
                    case .ok?: Haptics.success(); store.show("\(company.name) is open.", tone: "good")
                    case .needsStockCash(let need)?: Haptics.warning(); store.show("Needs \(store.money(need, in: company)) for opening stock.", tone: "warn")
                    default: Haptics.warning(); store.show("Something is still missing.", tone: "warn")
                    }
                }.buttonStyle(GoldButtonStyle())
            }
        }
    }
}
