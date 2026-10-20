import SwiftUI
import Charts
import GameCore
import Countries
import Finance
import Businesses
import Simulation

enum CompanySection: String, CaseIterable, Hashable {
    case overview = "Overview", projects = "Projects", staff = "Staff", finances = "Finances", operations = "Operations", marketing = "Marketing", setup = "Setup"
    /// Only for rental companies (CompanyProperties) and for insurers, banks and funds (CompanyFinanceBook).
    case properties = "Properties", book = "Book"
    // Shown only for the trades that have them (energy, salmon farm, holding company, football club)
    case energy = "Plant", salmon = "Fish", holding = "Holding", club = "Club"
    /// Chain, franchise and supply between your own companies (CompanyChain.swift)
    case chain = "Chain"
}

/// One company. Overview answers "how is it doing, why, and what to change"; the other sections are where the changes are made.
struct CompanyDetailView: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    @State private var section: CompanySection = .overview

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(co.name).font(.serifTitle(26)).foregroundStyle(Theme.ivory).lineLimit(2).minimumScaleFactor(0.7)
                        HStack(spacing: 6) {
                            Text("\(e.tradeName(co)) · \(e.cityName(co)) · \(co.form == .limited ? "Ltd" : "Sole trader")").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
                            if co.status == .open { HealthChip(label: e.companyHealth(co).label) } else { StatusChip(company: co) }
                        }
                    }
                    SectionTabs(items: sections(co, e), title: { $0.rawValue }, selection: $section).padding(.horizontal, -Theme.Space.margin)
                    switch section {
                    case .overview: CompanyOverview(engine: e, company: co, section: $section)
                    case .projects: CompanyProjects(engine: e, company: co)
                    case .staff: CompanyTeam(engine: e, company: co)
                    case .finances: CompanyMoney(engine: e, company: co)
                    case .operations: CompanyOperations(engine: e, company: co)
                    case .marketing: CompanyMarketing(engine: e, company: co)
                    case .setup: CompanySetupSection(engine: e, company: co)
                    case .properties: CompanyProperties(engine: e, company: co)
                    case .book: CompanyFinanceBook(engine: e, company: co)
                    case .energy: CompanyEnergy(engine: e, company: co)
                    case .salmon: CompanySalmon(engine: e, company: co)
                    case .holding: CompanyHolding(engine: e, company: co)
                    case .club: CompanyClub(engine: e, company: co)
                    case .chain: CompanyChain(engine: e, company: co)
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .ledgerBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if co.status == .setup { section = .setup } }
        } else {
            Text("This company no longer exists.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    private func sections(_ co: Company, _ e: GameEngine) -> [CompanySection] {
        let family = e.tradeInfo(companyID: co.id)?.family
        // Each family with a model of its own has a section of its own.
        var own: [CompanySection] = family == "rent" ? [.properties] : family == "fin" ? [.book] : family == "project" ? [.projects] : []
        switch co.type {
        case "power", "oilgas": own = [.energy]
        case "salmon": own = [.salmon]
        case "hold": own = [.holding]
        case "club": own = [.club]
        default: break
        }
        if co.status == .setup { return own + [.setup, .overview, .finances] }
        // A holding and a football club have no shop floor: no staff list, price, marketing or opening hours.
        if co.type == "hold" || co.type == "club" { return [.overview] + own + [.finances] }
        let extra: Set<CompanySection> = [.projects, .properties, .book, .energy, .salmon, .holding, .club, .chain]
        var list = CompanySection.allCases.filter { $0 != .setup && !extra.contains($0) }
        if !own.isEmpty { list.insert(contentsOf: own, at: 1) }
        if CompanyChain.isRelevant(co, e) { list.append(.chain) }
        return list
    }
}

// MARK: Overview

struct CompanyOverview: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Binding var section: CompanySection
    @State private var months = 12
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Energy, fish, holding and club have their own section instead of the customers-and-capacity picture.
    private var isSpecial: Bool { engine.tradeInfo(companyID: company.id).map { SpecialFamilies.handles($0) } ?? false }

    var body: some View {
        let co = company
        let h = engine.companyHealth(co)
        if sizeClass == .regular {
            // iPad: what and why on the left, how it runs and the trend on the right, all on one screen
            HStack(alignment: .top, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.l) { keyFigures(co, h); diagnosis(co) }
                VStack(alignment: .leading, spacing: Theme.Space.l) { if co.status == .open && !isSpecial { operations(co, h) }; performance(co, h) }
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                keyFigures(co, h)
                diagnosis(co)
                if co.status == .open && !isSpecial { operations(co, h) }
                performance(co, h)
            }
        }
    }

    // 1. How is it doing: the figures that decide what happens next, in one block
    private func keyFigures(_ co: Company, _ h: CompanyHealth) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Profit · 12 months").capsLabel()
                    Text((h.profitTTM < 0 ? "−" : "") + store.money(abs(h.profitTTM), in: co)).font(.hero(34))
                        .foregroundStyle(h.profitTTM < 0 ? Theme.loss : Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    if let m = h.marginTTM { Text("Margin \(String(format: "%.1f%%", m * 100))").foregroundStyle(Theme.ivoryMuted) }
                    if let g = h.revenueGrowth { Text(String(format: "Revenue %+.0f%% vs 3 mo", g * 100)).foregroundStyle(Theme.change(g)) }
                }.font(.system(size: 11.5).monospacedDigit())
            }
            KeyFigures(items: [
                .init(label: "Revenue", value: store.short(h.revenueTTM, in: co), sub: "12 months"),
                .init(label: "Value", value: store.short(h.value, in: co), sub: "book + goodwill"),
                .init(label: "Costs a week", value: store.short(h.weeklyCost, in: co), sub: "\(co.staff.count) staff"),
                .init(label: "Cash", value: store.short(co.cash, in: co), tint: co.cash < 0 ? Theme.loss : Theme.ivory,
                      sub: h.runwayWeeks != nil ? "lasts \(RunwayText.of(h))" : String(format: "%.0f weeks of costs", h.weeksOfCash)),
                .init(label: "Debt", value: store.short(h.debt, in: co), tint: h.debt > 0 ? Theme.loss : Theme.ivory),
                .init(label: "Margin", value: h.marginTTM.map { String(format: "%.1f%%", $0 * 100) } ?? "–"),
            ]).padding(.top, 12)
        }
    }

    // 2. Why, and where to act: findings from the company's own numbers, each with a way to the section that changes it
    private func diagnosis(_ co: Company) -> some View {
        let items = engine.insights(for: co, limit: 5)
        return LedgerSection("What is going on") {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { n, i in
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: i.symbol).font(.system(size: 13)).foregroundStyle(Theme.tone(i.tone.rawValue) == Theme.ivoryMuted ? Theme.gold : Theme.tone(i.tone.rawValue)).frame(width: 18).padding(.top, 2)
                        Text(i.text.tidyMoney).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        if let target = i.section.flatMap({ CompanySection(rawValue: $0.capitalized) }) {
                            Button { withAnimation(.snappy(duration: 0.2)) { section = target }; Haptics.choose() } label: {
                                Text("\(target.rawValue) →").font(.system(size: 11.5)).foregroundStyle(Theme.gold).fixedSize()
                            }.buttonStyle(.plain).padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 8)
                    if n < items.count - 1 { Hairline() }
                }
            }
        }
    }

    // 3. The operating picture: what limits sales, and how customers see the place
    private func operations(_ co: Company, _ h: CompanyHealth) -> some View {
        LedgerSection(title: "Last week", trailing: {
            Text("\(Int(h.servedLastWeek.rounded())) served of \(Int(h.capacityLastWeek.rounded())) possible").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }) {
            VStack(alignment: .leading, spacing: 9) {
                RateBar(label: "Capacity used", fraction: h.capacityUse, tint: h.capacityUse > 0.95 ? Theme.caution : Theme.gold)
                RateBar(label: "Demand met", fraction: h.demandCoverage > 0 ? min(1, 1 / h.demandCoverage) : 0, tint: h.demandCoverage > 1.05 ? Theme.caution : Theme.gain)
                RateBar(label: "Awareness", fraction: co.awareness / 100, tint: Theme.gold)
                if let b = h.bottleneck {
                    Text(h.demandCoverage > 1.05 ? "Limited by \(b.lowercased()) · turning customers away." : "Spare room: demand, not \(b.lowercased()), limits sales.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                }
                KeyFigures(items: [
                    .init(label: "Rating", value: String(format: "%.1f / 5", h.rating)),
                    .init(label: "Reputation", value: "\(Int(co.reputation.rounded()))"),
                    .init(label: "Quality", value: "\(Int(co.quality.rounded()))"),
                ])
            }
        }
    }

    // 4. The trend behind the figures
    private func performance(_ co: Company, _ h: CompanyHealth) -> some View {
        let rev = Array(h.revenueSeries.suffix(months)), prof = Array(h.profitSeries.suffix(months))
        return LedgerSection(title: "Revenue and profit by month", trailing: {
            HStack(spacing: 10) {
                ForEach([6, 12, 24], id: \.self) { m in
                    Button { months = m; Haptics.choose() } label: {
                        Text(m == 6 ? "6M" : m == 12 ? "1Y" : "2Y").font(.system(size: 11, weight: .medium)).foregroundStyle(months == m ? Theme.ivory : Theme.ivoryFaint)
                            .padding(.bottom, 2).overlay(alignment: .bottom) { if months == m { Rectangle().fill(Theme.gold).frame(height: 1) } }
                    }.buttonStyle(.plain)
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 6) {
                if rev.count < 2 {
                    Text("The chart starts after the first full month.").font(.caption).foregroundStyle(Theme.ivoryFaint).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                } else {
                    ChartKey(items: [("Revenue", Theme.gold), ("Profit", Theme.gain)])
                    RevenueProfitChart(revenue: rev, profit: prof, format: { store.short($0, in: co) }, height: 104)
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
