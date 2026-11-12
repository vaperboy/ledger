import SwiftUI
import UIKit
import GameCore
import Businesses
import Simulation

struct CompaniesView: View {
    enum Sort: String, CaseIterable, Hashable { case attention = "Needs attention", profit = "Profit", revenue = "Revenue", cash = "Cash", name = "Name" }
    @EnvironmentObject var store: GameStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ownInsets: EdgeInsets?
    @State private var sort: Sort = .attention
    @State private var showAll = false

    var body: some View {
        NavigationStack(path: Binding(get: { store.path(for: .company) }, set: { store.setPath($0, for: .company) })) {
            Group {
                if let e = store.engine {
                    let healths: [(co: Company, h: CompanyHealth)] = store.memo("homeRows") { (g: GameEngine) -> [(co: Company, h: CompanyHealth)] in
                        g.state.companies.filter { $0.status.isLive }.map { (co: $0, h: g.companyHealth($0)) }
                    } ?? []
                    let rows = healths.sorted(by: order)
                    homeScreen(e, rows: rows)
                    .id(store.rootToken(.company))
                    .centerSheet(isPresented: $showAll, title: "All companies", size: .tall, category: .detail, tone: .info) {
                        AllCompaniesList(engine: e, rows: rows) { (id: Int) in
                            showAll = false
                            store.push(.company(id), on: .company)
                        }
                        .environmentObject(store)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: NextDayDock.reserve) }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let e = store.engine { NextDayDock(engine: e).padding(.bottom, NextDayDock.gap) }
            }
            .padding(.bottom, missingBottom)
            .ledgerBackground()
            .background(GeometryReader { (g: GeometryProxy) in
                Color.clear
                    .onAppear { ownInsets = g.safeAreaInsets }
                    .onChange(of: g.safeAreaInsets) { _, v in ownInsets = v }
            })
            .onAppear { store.refreshPending(); store.endVisits() }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .companyRouteDestinations()
            .returnBar(for: .company)
        }
    }

    private var missingTop: CGFloat {
        guard let own = ownInsets else { return 0 }
        return max(0, Theme.windowInsets.top - own.top)
    }
    private var missingBottom: CGFloat {
        guard let own = ownInsets else { return 0 }
        return max(0, Theme.windowInsets.bottom - own.bottom)
    }

    @ViewBuilder private func homeScreen(_ e: GameEngine, rows: [(co: Company, h: CompanyHealth)]) -> some View {
        if sizeClass == .regular {
            ScrollView(.vertical) { page(e, rows: rows, limit: nil, compact: false) }
                .scrollIndicators(.hidden)
        } else {
            if rows.count <= 1 {
                ViewThatFits(in: .vertical) {
                    page(e, rows: rows, limit: 1, compact: false, fills: true)
                    page(e, rows: rows, limit: 1, compact: true, fills: true)
                    page(e, rows: rows, limit: 1, compact: true, fills: true, trim: 1)
                    page(e, rows: rows, limit: 1, compact: true, fills: true, trim: 2)
                    page(e, rows: rows, limit: 1, compact: true, fills: true, trim: 3)
                    page(e, rows: rows, limit: 1, compact: true, fills: true, chart: false, trim: 3)
                }
            } else {
                ViewThatFits(in: .vertical) {
                    page(e, rows: rows, limit: 5, compact: false, fills: true)
                    page(e, rows: rows, limit: 4, compact: false, fills: true)
                    page(e, rows: rows, limit: 3, compact: false, fills: true)
                    page(e, rows: rows, limit: 4, compact: true, fills: true)
                    page(e, rows: rows, limit: 3, compact: true, fills: true)
                    page(e, rows: rows, limit: 2, compact: true, fills: true)
                    page(e, rows: rows, limit: 2, compact: true, fills: true, chart: false)
                    page(e, rows: rows, limit: 1, compact: true, fills: true, chart: false)
                    ScrollView(.vertical) { page(e, rows: rows, limit: 3, compact: false) }
                        .scrollIndicators(.hidden)
                        .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
    }

    private func page(_ e: GameEngine, rows: [(co: Company, h: CompanyHealth)], limit: Int?, compact: Bool, fills: Bool = false, chart: Bool = true, trim: Int = 0) -> some View {
        HomeSummary(engine: e, compact: compact, fills: fills, chart: chart, trim: trim) {
            companiesBlock(e, rows: rows, limit: limit, compact: compact)
        }
        .padding(.horizontal, Theme.Space.page).padding(.top, (compact ? Theme.Space.xs : Theme.Space.s) + missingTop).padding(.bottom, Theme.Space.m)
        .frame(maxWidth: 1100).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private func companiesBlock(_ e: GameEngine, rows: [(co: Company, h: CompanyHealth)], limit: Int?, compact: Bool) -> some View {
        if rows.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HomeGroupLabel("Companies")
                EmptyState(glyph: Glyph.group, title: "No companies yet", message: "Pick a trade, see the full start-up cost, then decide.",
                           actionTitle: "Choose a trade", action: { store.push(.newCompany, on: .company) }, centered: false)
                    .padding(.vertical, Theme.Space.s)
            }
        } else {
            let shown: [(co: Company, h: CompanyHealth)] = limit.map { Array(rows.prefix($0)) } ?? rows
            VStack(alignment: .leading, spacing: 0) {
                HomeGroupLabel(title: "Companies") {
                    HStack(spacing: Theme.Space.s) {
                        if e.canStartCompany {
                            Button("Start a company") { Haptics.tap(); store.push(.newCompany, on: .company) }
                                .buttonStyle(TertiaryButtonStyle(size: .compact))
                                .accessibilityIdentifier("home-new-company")
                        }
                        if sizeClass == .regular {
                            sortMenu
                        } else if shown.count < rows.count {
                            Button("All \(rows.count)") { Haptics.tap(); showAll = true }
                                .buttonStyle(TertiaryButtonStyle(size: .compact))
                                .accessibilityLabel("All \(rows.count) companies")
                                .accessibilityIdentifier("show-all-companies")
                        }
                    }
                }
                companyRows(e, rows: shown, compact: compact)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("home-companies-box")
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Text(sort.rawValue).textStyle(.caption, tint: Theme.inkSoft)
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(Theme.inkFaint).accessibilityHidden(true)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("Sorted by \(sort.rawValue.lowercased())")
    }

    @ViewBuilder private func companyRows(_ e: GameEngine, rows: [(co: Company, h: CompanyHealth)], compact: Bool) -> some View {
        if sizeClass == .regular {
            CompanyTable(engine: e, rows: rows) { store.push(.company($0), on: .company) }
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.co.id) { (i: Int, r: (co: Company, h: CompanyHealth)) in
                    if i > 0 { Hairline().padding(.leading, CompanyRow.textInset) }
                    Button { Haptics.tap(); store.push(.company(r.co.id), on: .company) } label: { CompanyRow(engine: e, company: r.co, health: r.h) }
                        .buttonStyle(PressableStyle())
                        .accessibilityHint("Opens the company")
                        .coachAnchor(.homeCompany, enabled: i == 0)
                        .transition(.opacity)
                }
            }
            .animation(Motion.quick(reduceMotion), value: rows.map { (r: (co: Company, h: CompanyHealth)) -> Int in r.co.id })
        }
    }

    private func order(_ a: (co: Company, h: CompanyHealth), _ b: (co: Company, h: CompanyHealth)) -> Bool {
        switch sort {
        case .attention:
            let ra = Self.urgency(a.co, a.h), rb = Self.urgency(b.co, b.h)
            return ra != rb ? ra < rb : a.h.profitTTM < b.h.profitTTM
        case .profit: return a.h.profitTTM > b.h.profitTTM
        case .revenue: return a.h.revenueTTM > b.h.revenueTTM
        case .cash: return a.co.cash > b.co.cash
        case .name: return a.co.name < b.co.name
        }
    }

    static func urgency(_ co: Company, _ h: CompanyHealth) -> Int {
        if co.status == .setup { return 2 }
        if co.status == .closed { return 3 }
        if co.cash < 0 || h.label == "Struggling" { return 0 }
        if let w = h.runwayWeeks, w < 8 { return 0 }
        if h.label == "Tight" { return 1 }
        return 4
    }

}

struct AllCompaniesList: View {
    var engine: GameEngine
    var rows: [(co: Company, h: CompanyHealth)]
    var open: (Int) -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.co.id) { (i: Int, r: (co: Company, h: CompanyHealth)) in
                    if i > 0 { Hairline().padding(.leading, CompanyRow.textInset) }
                    Button { Haptics.tap(); open(r.co.id) } label: { CompanyRow(engine: engine, company: r.co, health: r.h) }
                        .buttonStyle(PressableStyle())
                        .accessibilityHint("Opens the company")
                }
            }
            .padding(.horizontal, Theme.Space.page).padding(.bottom, Theme.Space.m)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("all-companies-list")
    }
}

struct CompanyTable: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var rows: [(co: Company, h: CompanyHealth)]
    var open: (Int) -> Void
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Space.l, verticalSpacing: 0) {
            GridRow {
                ForEach(["Company", "Status", "Revenue 12 mo", "Profit 12 mo", "Margin", "Cash", "Cash lasts", "Run by", "Staff", "Limited by"], id: \.self) { h in
                    Text(h).textStyle(.label, tint: Theme.inkFaint).lineLimit(1)
                }
            }
            .padding(.vertical, Theme.Space.s)
            ForEach(rows, id: \.co.id) { r in
                Hairline().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    Button { Haptics.tap(); open(r.co.id) } label: {
                        HStack(spacing: Theme.Space.s) {
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text(r.co.name).textStyle(.headline, tint: Theme.accent).lineLimit(1)
                                Text("\(engine.tradeName(r.co)) · \(engine.cityName(r.co))").textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
                            }
                            LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(PressableStyle())
                    .accessibilityHint("Opens the company")
                    HealthChip(label: r.h.label)
                    num(store.short(r.h.revenueTTM, in: r.co))
                    num(store.short(r.h.profitTTM, in: r.co), Theme.change(r.h.profitTTM) == Theme.inkSoft ? Theme.ink : Theme.change(r.h.profitTTM))
                    num(r.h.marginTTM.map { String(format: "%.0f%%", $0 * 100) } ?? "–")
                    num(store.short(r.co.cash, in: r.co), r.co.cash < 0 ? Theme.loss : Theme.ink)
                    num(RunwayText.of(r.h), r.h.runwayWeeks.map { $0 < 8 ? Theme.loss : Theme.warn } ?? Theme.inkSoft)
                    Text(RunBy.name(engine, r.co)).textStyle(.caption).lineLimit(1)
                    num("\(r.co.staff.count)")
                    Text(r.h.limitedBy ?? "–").textStyle(.caption).lineLimit(1)
                }
                .padding(.vertical, Theme.Space.xs)
            }
        }
    }
    private func num(_ s: String, _ c: Color = Theme.ink) -> some View {
        Text(s).textStyle(.body, tint: c, numeric: true).lineLimit(1)
    }
}

enum RunwayText {
    static func of(_ h: CompanyHealth) -> String {
        guard let w = h.runwayWeeks else { return h.profitTTM > 0 || h.label == "New" ? "Self-funding" : "–" }
        return w >= 104 ? "2+ years" : "\(Int(saturating: w)) weeks"
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

struct CompanyRow: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var health: CompanyHealth
    @Environment(Entitlements.self) private var ent
    @AppStorage(CosmeticKeys.badge) private var badgeID: String = Cosmetics.defaultBadgeID
    @AppStorage(CosmeticKeys.theme) private var themeID: String = Cosmetics.defaultThemeID
    static let textInset: CGFloat = 28 + Theme.Space.m

    var body: some View {
        let co = company, h = health
        let style: (theme: String, badge: String) = engine.companyStyle(companyID: co.id)
        let badge: Cosmetics.Badge = Cosmetics.resolvedBadge(style.badge.isEmpty ? badgeID : style.badge, earned: engine.careerCosmetics, pro: ent.isPro)
        let accent: Color = Cosmetics.resolvedTheme(style.theme.isEmpty ? themeID : style.theme, pro: ent.isPro).accent
        let urgent = CompaniesView.urgency(co, h) == 0
        let month: Double = h.profitTTM / 12
        let profitTint: Color = month < -0.5 ? Theme.loss : month > 0.5 ? Theme.gain : Theme.inkSoft
        HStack(spacing: Theme.Space.s) {
            if engine.companyLogoID(companyID: co.id).isEmpty { ThumbnailView(kind: .trade, key: co.type, size: 28) } else { LogoBadge(logoID: engine.companyLogoID(companyID: co.id), size: 28) }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Theme.Space.xs) {
                    if urgent { LedgerGlyph(glyph: Glyph.warning, size: Theme.Icon.small, tint: Theme.loss).accessibilityLabel("Needs attention") }
                    Text(co.name).textStyle(.headline).lineLimit(1)
                    CosmeticBadgeView(badge: badge, tint: accent, size: 14)
                }
                HStack(spacing: Theme.Space.xs) {
                    Circle().fill(statusTint(co, h)).frame(width: 6, height: 6).accessibilityHidden(true)
                    Text(status(co, h)).textStyle(.caption, tint: statusTint(co, h)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                Text((month < -0.5 ? "\u{2212}" : month > 0.5 ? "+" : "") + store.short(abs(month), in: co) + " a month")
                    .textStyle(.body, tint: profitTint, numeric: true, weight: .medium)
                Text("Cash " + store.short(co.cash, in: co)).textStyle(.caption, tint: co.cash < 0 ? Theme.loss : Theme.inkFaint, numeric: true)
            }
            .lineLimit(1)
            .layoutPriority(1)
            LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
        }
        .padding(.vertical, Theme.Space.xs)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .zoomSource(.company(co.id))
        .accessibilityElement(children: .combine)
    }

    private func status(_ co: Company, _ h: CompanyHealth) -> String {
        switch co.status {
        case .open: return co.cash < 0 ? "Out of cash" : h.label
        case .setup: return "Setting up"
        default: return co.status.rawValue.capitalized
        }
    }

    private func statusTint(_ co: Company, _ h: CompanyHealth) -> Color {
        co.status == .open ? (co.cash < 0 ? Theme.loss : HealthChip.tint(h.label)) : Theme.inkFaint
    }
}

enum RunBy {
    static func name(_ e: GameEngine, _ co: Company) -> String {
        guard co.status.isLive else { return "–" }
        if let b = e.decisionChain(companyID: co.id).first { return b.name }
        if let mid = co.managerID, let p = e.state.people[mid] { return p.name }
        if OwnerHours.crewRuns(co) { return "Its team" }
        return OwnerHours.works(co) ? "You" : (co.status == .open ? "No one" : "–")
    }
}
