import SwiftUI
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
    @State private var chartKind = 0

    private func tint(_ label: String) -> Color {
        switch label { case "Thriving", "Healthy": return Theme.gain; case "Tight": return Theme.caution; case "Struggling": return Theme.loss; default: return Theme.ivoryMuted }
    }

    var body: some View {
        let co = company
        let h = engine.companyHealth(co)
        let wk = Books.profit(co.books.week), mo = Books.profit(co.books.month)
        VStack(spacing: Theme.Space.l) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack(alignment: .firstTextBaseline) {
                        SectionLabel("Company value")
                        Spacer()
                        Chip(text: h.label, tint: tint(h.label))
                    }
                    Text(store.money(h.value, in: co)).font(.figure(32))
                    if let g = h.revenueGrowth {
                        Chip(text: String(format: "Revenue %@%.0f%% over 3 months", g >= 0 ? "+" : "−", abs(g) * 100), tint: Theme.change(g))
                    }
                    HStack(alignment: .top, spacing: Theme.Space.l) {
                        Stat(label: "Revenue, 12 mo", value: store.short(h.revenueTTM, in: co))
                        Stat(label: "Profit, 12 mo", value: store.short(h.profitTTM, in: co), tint: Theme.change(h.profitTTM))
                    }
                    HStack(alignment: .top, spacing: Theme.Space.l) {
                        Stat(label: "Cash", value: store.short(co.cash, in: co), tint: co.cash < 0 ? Theme.loss : Theme.ivory)
                        Stat(label: "Debt", value: store.short(h.debt, in: co))
                        Stat(label: "Team", value: String(co.staff.count))
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Picker("", selection: $chartKind) {
                        Text("Revenue").tag(0); Text("Profit").tag(1); Text("Cash").tag(2)
                    }.pickerStyle(.segmented)
                    let series = chartKind == 0 ? h.revenueSeries : chartKind == 1 ? h.profitSeries : h.cashSeries
                    if chartKind == 1 { MiniBars(values: series).frame(height: 90) } else { Sparkline(values: series).frame(height: 90) }
                    HStack {
                        Text(series.count < 2 ? "History builds up month by month." : "Last \(series.count) months").font(.caption).foregroundStyle(Theme.ivoryFaint)
                        Spacer()
                        DeltaPill(title: "Week", amount: wk, share: nil, format: { store.short($0, in: co) })
                        DeltaPill(title: "Month", amount: mo, share: nil, format: { store.short($0, in: co) })
                    }
                }
            }
            if co.status == .open {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        SectionLabel("Operations")
                        HStack(alignment: .top) {
                            Ring(label: "Capacity used", fraction: h.capacityUse, centre: "\(Int((h.capacityUse * 100).rounded()))%", tint: h.capacityUse > 0.95 ? Theme.caution : Theme.gold)
                            Ring(label: "Demand met", fraction: h.demandCoverage > 0 ? min(1, 1 / h.demandCoverage) : 0, centre: h.demandCoverage > 0 ? "\(Int((min(1, 1 / h.demandCoverage) * 100).rounded()))%" : "–", tint: h.demandCoverage > 1.05 ? Theme.caution : Theme.gain)
                            Ring(label: "Rating", fraction: h.rating / 5, centre: String(format: "%.1f", h.rating), tint: Theme.roseGold)
                        }
                    }
                }
            }
            let insights = engine.insights(for: co, limit: 4)
            if !insights.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        SectionLabel("Key insights")
                        ForEach(insights) { i in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: i.symbol).foregroundStyle(Theme.tone(i.tone.rawValue)).frame(width: 22)
                                Text(i.text).font(.bodyText).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                            }
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
                Card { HStack { Label("Finance & taxes", systemImage: "chart.pie").foregroundStyle(Theme.ivory); Spacer(); Image(systemName: "chevron.right").foregroundStyle(Theme.ivoryFaint) } }
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
