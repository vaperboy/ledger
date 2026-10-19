import SwiftUI
import GameCore
import Simulation

enum CompanyRoute: Hashable { case company(Int), newCompany }

/// The companies and the group as a whole: totals at the top, then every company in one comparable list (a table on iPad).
/// Replaces the former separate Group tab, which listed the same companies again.
struct CompaniesView: View {
    enum Sort: String, CaseIterable, Hashable { case profit = "Profit", revenue = "Revenue", cash = "Cash", name = "Name" }
    @EnvironmentObject var store: GameStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var path: [CompanyRoute] = []
    @State private var sort: Sort = .profit

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let e = store.engine {
                    let cos = e.state.companies.filter { $0.type != "hold" && $0.status != .sold }
                    let rows = cos.map { (co: $0, h: e.companyHealth($0)) }.sorted(by: order)
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Space.l) {
                            if cos.isEmpty {
                                Card {
                                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                                        Text("No companies yet").font(.heading)
                                        Text("Pick a trade, see the full start-up cost, then decide.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                                        Button("Choose a trade") { path.append(.newCompany) }.buttonStyle(GoldButtonStyle())
                                    }
                                }
                            } else {
                                GroupSummary(engine: e, rows: rows.map { $0.h }, staff: cos.reduce(0) { $0 + $1.staff.count })
                                HStack {
                                    Text("Sort by").font(.caption).foregroundStyle(Theme.ivoryFaint)
                                    SectionTabs(items: Sort.allCases, title: { $0.rawValue }, selection: $sort).padding(.horizontal, -Theme.Space.l)
                                }
                                if sizeClass == .regular {
                                    CompanyTable(engine: e, rows: rows) { path.append(.company($0)) }
                                } else {
                                    Card(padding: 0) {
                                        VStack(spacing: 0) {
                                            ForEach(Array(rows.enumerated()), id: \.element.co.id) { i, r in
                                                if i > 0 { Divider().overlay(Theme.hairline).padding(.leading, Theme.Space.l) }
                                                NavigationLink(value: CompanyRoute.company(r.co.id)) { CompanyRow(engine: e, company: r.co, health: r.h) }.buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(Theme.Space.l)
                        .frame(maxWidth: 1100).frame(maxWidth: .infinity)
                    }
                }
            }
            .ledgerBackground()
            .navigationTitle("Companies")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: CompanyRoute.self) { route in
                switch route {
                case .company(let id): CompanyDetailView(companyID: id)
                case .newCompany: NewCompanyView()
                }
            }
            .toolbar { ToolbarItem(placement: .primaryAction) { Button { path.append(.newCompany) } label: { Label("New company", systemImage: "plus") } } }
            .onAppear { openRequested() }
            .onChange(of: store.openCompanyID) { _, _ in openRequested() }
            .onChange(of: store.showNewCompany) { _, _ in openRequested() }
        }
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
        if let id = store.openCompanyID { path = [.company(id)]; store.openCompanyID = nil }
        if store.showNewCompany { path = [.newCompany]; store.showNewCompany = false }
    }
}

/// The group in one line of figures: what it is worth, what it earns, what it holds.
struct GroupSummary: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var rows: [CompanyHealth]
    var staff: Int
    var body: some View {
        let profit = rows.reduce(0) { $0 + $1.profitTTM }, revenue = rows.reduce(0) { $0 + $1.revenueTTM }
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Group").font(.bodyText.weight(.semibold))
                    Spacer()
                    Text("\(rows.count) \(rows.count == 1 ? "company" : "companies") · \(staff) staff").font(.caption).foregroundStyle(Theme.ivoryFaint)
                }
                HStack(alignment: .top, spacing: Theme.Space.l) {
                    Stat(label: "Worth (your share)", value: store.short(engine.netWorth.companies))
                    Stat(label: "Profit, 12 mo", value: store.short(profit), tint: profit < 0 ? Theme.loss : Theme.ivory)
                    Stat(label: "Revenue, 12 mo", value: store.short(revenue))
                }
                HStack(alignment: .top, spacing: Theme.Space.l) {
                    Stat(label: "Cash in companies", value: store.short(engine.state.liveCompanies.reduce(0) { $0 + max(0, $1.cash) }))
                    Stat(label: "Debt", value: store.short(rows.reduce(0) { $0 + $1.debt }))
                    Stat(label: "Margin", value: revenue > 0 ? String(format: "%.0f%%", profit / revenue * 100) : "–", tint: Theme.change(profit))
                }
            }
        }
    }
}

/// iPad: every company side by side, one row each.
struct CompanyTable: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var rows: [(co: Company, h: CompanyHealth)]
    var open: (Int) -> Void
    var body: some View {
        Card(padding: 0) {
            Grid(alignment: .leading, horizontalSpacing: Theme.Space.l, verticalSpacing: 0) {
                GridRow {
                    ForEach(["Company", "Status", "Revenue 12 mo", "Profit 12 mo", "Margin", "Cash", "Cash lasts", "Staff", "Limited by"], id: \.self) { h in
                        Text(h).font(.caption).foregroundStyle(Theme.ivoryFaint)
                    }
                }
                .padding(.vertical, Theme.Space.m)
                ForEach(rows, id: \.co.id) { r in
                    Divider().overlay(Theme.hairline).gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.co.name).font(.bodyText.weight(.semibold)).foregroundStyle(Theme.ivory).lineLimit(1)
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
                    .padding(.vertical, Theme.Space.m)
                    .contentShape(Rectangle())
                    .onTapGesture { open(r.co.id) }
                }
            }
            .padding(.horizontal, Theme.Space.l)
        }
    }
    private func num(_ s: String, _ c: Color = Theme.ivory) -> some View {
        Text(s).font(.subheadline.monospacedDigit()).foregroundStyle(c).lineLimit(1)
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

/// One company in the list: what it earns, what it holds, and what to watch, without opening it.
struct CompanyRow: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var health: CompanyHealth

    var body: some View {
        let co = company, h = health
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(co.name).font(.bodyText.weight(.semibold)).foregroundStyle(Theme.ivory).lineLimit(1)
                    Text("\(engine.tradeName(co)) · \(engine.cityName(co))").font(.caption).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text((h.profitTTM >= 0 ? "" : "−") + store.short(abs(h.profitTTM), in: co)).font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(h.profitTTM < 0 ? Theme.loss : Theme.ivory)
                    Text("profit, 12 mo").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
            }
            HStack(spacing: 10) {
                if co.status == .open { HealthChip(label: h.label) } else { StatusChip(company: co) }
                fact("Revenue", store.short(h.revenueTTM, in: co))
                fact("Cash", store.short(co.cash, in: co), co.cash < 0 ? Theme.loss : Theme.ivoryMuted)
                if let w = h.runwayWeeks { fact("Lasts", w >= 104 ? "2+ yr" : "\(Int(w)) wk", w < 8 ? Theme.loss : Theme.caution) }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Theme.ivoryFaint)
            }
        }
        .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.m)
        .contentShape(Rectangle())
    }

    private func fact(_ label: String, _ value: String, _ tint: Color = Theme.ivoryMuted) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(Theme.ivoryFaint)
            Text(value).font(.caption.monospacedDigit()).foregroundStyle(tint)
        }
    }
}
