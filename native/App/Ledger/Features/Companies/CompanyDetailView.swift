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

    var body: some View {
        let co = company
        let wk = Books.profit(co.books.week), mo = Books.profit(co.books.month), yr = Books.profit(co.books.year)
        VStack(spacing: Theme.Space.l) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionLabel("Cash")
                    Text(store.money(co.cash, in: co)).font(.figure(32)).foregroundStyle(co.cash < 0 ? Theme.loss : Theme.ivory)
                    HStack(spacing: 8) {
                        DeltaPill(title: "Week", amount: wk, share: nil, format: { store.short($0, in: co) })
                        DeltaPill(title: "Month", amount: mo, share: nil, format: { store.short($0, in: co) })
                    }
                    SectionLabel("Profit by month")
                    MiniBars(values: engine.monthlyProfitSeries(co)).frame(height: 48)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionLabel("Books")
                    ValueRow(label: "Revenue last week", value: store.money(co.lastWeekRevenue, in: co))
                    ValueRow(label: "Customers served last week", value: String(Int(co.lastWeekUnits.rounded())))
                    ValueRow(label: "Profit this year", value: store.money(yr, in: co), tint: Theme.change(yr))
                    ValueRow(label: "Stock on hand", value: store.money(co.inventory, in: co))
                    if co.vatBalance != 0 { ValueRow(label: co.vatBalance > 0 ? "VAT to pay" : "VAT to reclaim", value: store.money(abs(co.vatBalance), in: co)) }
                    if co.taxAccrued > 0 { ValueRow(label: "Tax set aside", value: store.money(co.taxAccrued, in: co)) }
                }
            }
            Card {
                VStack(spacing: Theme.Space.m) {
                    Meter(label: "Reputation", value: co.reputation)
                    Meter(label: "Quality", value: co.quality)
                    Meter(label: "Awareness", value: co.awareness)
                }
            }
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
