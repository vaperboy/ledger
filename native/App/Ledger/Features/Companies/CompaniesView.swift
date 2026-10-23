import SwiftUI
import GameCore
import Businesses
import Simulation

enum CompanyRoute: Hashable {
    case company(Int), newCompany, market
    /// A company opened on one of its sections (from Team, Projects, Inbox or a deep link).
    case companyAt(Int, CompanySection)
}

/// The companies and the group as a whole: totals at the top, then every company in one comparable list (a table on iPad).
/// Replaces the former separate Group tab, which listed the same companies again.
struct CompaniesView: View {
    enum Sort: String, CaseIterable, Hashable { case profit = "Profit", revenue = "Revenue", cash = "Cash", name = "Name" }
    @EnvironmentObject var store: GameStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var path: [CompanyRoute] = []
    @State private var sort: Sort = .profit
    /// With many companies: a name search and a filter by chain ("all", "independent" or a chain id).
    @State private var query = ""
    @State private var chainFilter = "all"

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let e = store.engine {
                    let cos = e.state.companies.filter { $0.type != "hold" && $0.status != .sold }
                    let rows = cos.filter(matches).map { (co: $0, h: e.companyHealth($0)) }.sorted(by: order)
                    let chains = e.chainSummaries
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Space.l) {
                            HomeSummary(engine: e)
                            HStack(alignment: .lastTextBaseline) {
                                Text("Company").font(.serifTitle(28))
                                Spacer()
                                if !cos.isEmpty {
                                    Text("\(cos.count) \(cos.count == 1 ? "company" : "companies") · \(Set(cos.map { e.cityName($0) }).count) \(Set(cos.map { e.cityName($0) }).count == 1 ? "city" : "cities") · \(cos.reduce(0) { $0 + $1.staff.count }) staff")
                                        .font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                                }
                            }
                            if cos.isEmpty {
                                LedgerSection("No companies yet") {
                                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                                        Text("Pick a trade, see the full start-up cost, then decide.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                                        Button("Choose a trade") { path.append(.newCompany) }.buttonStyle(GoldButtonStyle())
                                    }
                                }
                            } else {
                                LedgerSection(title: "Companies", trailing: {
                                    Menu {
                                        Picker("Sort by", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                                    } label: {
                                        Text("Sorted by \(sort.rawValue.lowercased())  ⌄").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                                    }
                                }) {
                                    if cos.count >= 8 { filterBar(chains) }
                                    if rows.isEmpty { Text("No company matches.").font(.bodyText).foregroundStyle(Theme.ivoryMuted).padding(.vertical, 8) }
                                    if sizeClass == .regular {
                                        CompanyTable(engine: e, rows: rows) { path.append(.company($0)) }
                                    } else {
                                        VStack(spacing: 0) {
                                            HStack(spacing: 8) {
                                                Text("Company").frame(maxWidth: .infinity, alignment: .leading)
                                                Text("Value").frame(width: 62, alignment: .trailing)
                                                Text("Profit").frame(width: 62, alignment: .trailing)
                                                Text("Rev.").frame(width: 50, alignment: .trailing)
                                            }
                                            .font(.system(size: 9.5, weight: .semibold)).tracking(1).textCase(.uppercase).foregroundStyle(Theme.ivoryFaint).padding(.bottom, 6)
                                            ForEach(Array(rows.enumerated()), id: \.element.co.id) { i, r in
                                                Hairline()
                                                NavigationLink(value: CompanyRoute.company(r.co.id)) { CompanyRow(engine: e, company: r.co, health: r.h) }.buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 130)
                        .frame(maxWidth: 1100).frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                    .safeAreaInset(edge: .bottom, spacing: 0) { AdvanceBar(engine: e) }
                }
            }
            .ledgerBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .companyRouteDestinations()
            .toolbar { ToolbarItem(placement: .primaryAction) { Button { path.append(.newCompany) } label: { Label("New company", systemImage: "plus") } } }
            .phoneToolbar()
            .onAppear { openRequested() }
            .onChange(of: store.openCompanyID) { _, _ in openRequested() }
            .onChange(of: store.showNewCompany) { _, _ in openRequested() }
        }
    }

    private func matches(_ co: Company) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty && !co.name.lowercased().contains(q) && !(store.engine.map { $0.cityName(co).lowercased().contains(q) || $0.tradeName(co).lowercased().contains(q) } ?? false) { return false }
        switch chainFilter {
        case "all": return true
        case "independent": return co.value("chain").isNull
        default: return !co.value("chain").isNull && String(co.value("chain").int) == chainFilter
        }
    }

    /// Search and chain chips, shown once there are enough companies for a long list to need them.
    @ViewBuilder private func filterBar(_ chains: [Chains.Summary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                TextField("Name, city or trade", text: $query).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).textInputAutocapitalization(.never).autocorrectionDisabled()
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.ivoryFaint) }.buttonStyle(.plain) }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Color.white.opacity(0.05)))
            if !chains.isEmpty {
                SectionTabs(items: ["all"] + chains.map { String($0.id) } + ["independent"],
                            title: { k in k == "all" ? "All" : k == "independent" ? "Independent" : (chains.first { String($0.id) == k }?.name ?? "Chain") },
                            selection: $chainFilter).padding(.horizontal, -Theme.Space.margin)
            }
        }.padding(.bottom, 6)
    }

    private func order(_ a: (co: Company, h: CompanyHealth), _ b: (co: Company, h: CompanyHealth)) -> Bool {
        switch sort {
        case .profit: return a.h.profitTTM > b.h.profitTTM
        case .revenue: return a.h.revenueTTM > b.h.revenueTTM
        case .cash: return a.co.cash > b.co.cash
        case .name: return a.co.name < b.co.name
        }
    }

    private func openRequested() {
        if let id = store.openCompanyID {
            path = [store.companySection.map { .companyAt(id, $0) } ?? .company(id)]
            store.openCompanyID = nil
            store.companySection = nil
        }
        if store.showNewCompany { path = [.newCompany]; store.showNewCompany = false }
    }
}

/// The group as a portfolio: what it is worth, how that divides, what it earns and holds, and how it did month by month.
struct GroupSummary: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var rows: [CompanyHealth]
    var staff: Int
    var body: some View {
        let profit = rows.reduce(0) { $0 + $1.profitTTM }, revenue = rows.reduce(0) { $0 + $1.revenueTTM }
        let change = DayHistory.change(engine.dayHistory.companies, days: 30)
        let cash = engine.state.liveCompanies.reduce(0) { $0 + max(0, $1.cash) }
        VStack(alignment: .leading, spacing: 4) {
            Text("Value of holdings").capsLabel()
            HStack(alignment: .firstTextBaseline) {
                Text(store.money(engine.netWorth.companies)).font(.hero(36)).foregroundStyle(Theme.ivory).minimumScaleFactor(0.55).lineLimit(1)
                Spacer(minLength: 6)
                if let change, abs(change.amount) >= 1 {
                    Text((change.amount > 0 ? "+" : "−") + store.short(abs(change.amount)) + " · 30 d").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.change(change.amount))
                }
            }
            AllocationBar(parts: rows.map { $0.value }.sorted(by: >)).padding(.top, 8)
            KeyFigures(items: [
                .init(label: "Revenue 12 mo", value: store.short(revenue)),
                .init(label: "Profit 12 mo", value: store.short(profit), tint: profit < 0 ? Theme.loss : Theme.gain),
                .init(label: "Margin", value: revenue > 0 ? String(format: "%.1f%%", profit / revenue * 100) : "–", tint: revenue > 0 ? Theme.ivory : Theme.ivoryMuted),
                .init(label: "Cash in companies", value: store.short(cash)),
                .init(label: "Debt", value: store.short(rows.reduce(0) { $0 + $1.debt }), tint: rows.contains { $0.debt > 0 } ? Theme.loss : Theme.ivory),
                .init(label: "Staff", value: "\(staff)"),
            ]).padding(.top, 10)
            let rev = aligned(\.revenueSeries), prof = aligned(\.profitSeries)
            if rev.count >= 2 {
                HStack { Text("Revenue and profit by month").capsLabel(); Spacer(); ChartKey(items: [("Revenue", Theme.gold), ("Profit", Theme.gain)]) }.padding(.top, 8)
                RevenueProfitChart(revenue: rev, profit: prof, format: { store.short($0) }).padding(.top, 2)
            }
        }
    }

    /// The last twelve closed months of every company added together, newest at the right.
    private func aligned(_ key: KeyPath<CompanyHealth, [Double]>) -> [Double] {
        var out = [Double](repeating: 0, count: 12)
        for r in rows { let s = Array(r[keyPath: key].suffix(12)); for (i, v) in s.enumerated() { out[12 - s.count + i] += v } }
        let firstLive = rows.map { min(12, $0[keyPath: key].count) }.max() ?? 0
        return Array(out.suffix(max(firstLive, 0)))
    }
}

/// iPad: every company side by side, one row each.
struct CompanyTable: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var rows: [(co: Company, h: CompanyHealth)]
    var open: (Int) -> Void
    var body: some View {
        Card(padding: 0, rule: false) {
            Grid(alignment: .leading, horizontalSpacing: Theme.Space.l, verticalSpacing: 0) {
                GridRow {
                    ForEach(["Company", "Status", "Revenue 12 mo", "Profit 12 mo", "Margin", "Cash", "Cash lasts", "Staff", "Limited by"], id: \.self) { h in
                        Text(h).font(.system(size: 9.5, weight: .semibold)).tracking(1).textCase(.uppercase).foregroundStyle(Theme.ivoryFaint)
                    }
                }
                .padding(.vertical, Theme.Space.m)
                ForEach(rows, id: \.co.id) { r in
                    Hairline().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.co.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                            Text("\(engine.tradeName(r.co)) · \(engine.cityName(r.co))").font(.caption2).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                        }
                        HealthChip(label: r.h.label)
                        num(store.short(r.h.revenueTTM, in: r.co))
                        num(store.short(r.h.profitTTM, in: r.co), Theme.change(r.h.profitTTM) == Theme.ivoryMuted ? Theme.ivory : Theme.change(r.h.profitTTM))
                        num(r.h.marginTTM.map { String(format: "%.0f%%", $0 * 100) } ?? "–")
                        num(store.short(r.co.cash, in: r.co), r.co.cash < 0 ? Theme.loss : Theme.ivory)
                        num(RunwayText.of(r.h), r.h.runwayWeeks.map { $0 < 8 ? Theme.loss : Theme.caution } ?? Theme.ivoryMuted)
                        num("\(r.co.staff.count)")
                        Text(r.h.bottleneck ?? "–").font(.caption).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .onTapGesture { open(r.co.id) }
                }
            }
        }
    }
    private func num(_ s: String, _ c: Color = Theme.ivory) -> some View {
        Text(s).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(c).lineLimit(1)
    }
}

/// "Self-funding", or how many weeks the cash lasts at the current rate of loss.
enum RunwayText {
    static func of(_ h: CompanyHealth) -> String {
        guard let w = h.runwayWeeks else { return h.profitTTM > 0 || h.label == "New" ? "Self-funding" : "–" }
        return w >= 104 ? "2+ years" : "\(Int(w)) weeks"
    }
}

struct HealthChip: View {
    var label: String
    var body: some View {
        Chip(text: label, tint: HealthChip.tint(label))
    }
    static func tint(_ label: String) -> Color {
        switch label { case "Thriving", "Healthy": return Theme.gain; case "Tight": return Theme.caution; case "Struggling": return Theme.loss; default: return Theme.ivoryMuted }
    }
}

struct StatusChip: View {
    var company: Company
    var body: some View {
        switch company.status {
        case .setup: Chip(text: "Setting up", tint: Theme.caution)
        case .open: Chip(text: company.cash < 0 ? "Out of cash" : "Open", tint: company.cash < 0 ? Theme.loss : Theme.gain)
        case .closed: Chip(text: "Closed", tint: Theme.ivoryMuted)
        case .sold: Chip(text: "Sold", tint: Theme.ivoryMuted)
        case .bust: Chip(text: "Bankrupt", tint: Theme.loss)
        default: Chip(text: company.status.rawValue.capitalized)
        }
    }
}

/// One company in the list: name with trade and health, value, profit and a revenue trend, without opening it.
struct CompanyRow: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var health: CompanyHealth

    var body: some View {
        let co = company, h = health
        let growing = (h.revenueGrowth ?? 0) >= 0
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(co.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineLimit(1)
                HStack(spacing: 0) {
                    Text(engine.tradeName(co) + " · ").foregroundStyle(Theme.ivoryFaint)
                    if co.status == .open { Text(h.label).foregroundStyle(HealthChip.tint(h.label)) } else { Text(co.status == .setup ? "Setting up" : co.status.rawValue.capitalized).foregroundStyle(Theme.ivoryMuted) }
                }
                .font(.system(size: 11)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(store.short(h.value, in: co)).font(.system(size: 13.5).monospacedDigit()).frame(width: 62, alignment: .trailing)
            Text((h.profitTTM < 0 ? "−" : "") + store.short(abs(h.profitTTM), in: co)).font(.system(size: 13.5).monospacedDigit())
                .foregroundStyle(h.profitTTM < 0 ? Theme.loss : Theme.ivory).frame(width: 62, alignment: .trailing)
            Sparkline(values: Array(h.revenueSeries.suffix(12)), tint: growing ? Theme.gain : Theme.loss, filled: false).frame(width: 46, height: 20)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}
