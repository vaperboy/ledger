import SwiftUI
import Charts
import GameCore
import Countries
import Finance
import Businesses
import Simulation

enum CompanySection: String, CaseIterable, Hashable {
    case overview = "Overview", staff = "Staff", finances = "Finances", operations = "Operations", marketing = "Marketing", setup = "Setup"
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
                    HStack(spacing: 8) {
                        Text("\(e.tradeName(co)) · \(e.cityName(co)) · \(co.form == .limited ? "Limited" : "Sole trader")").font(.caption).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
                        Spacer()
                        StatusChip(company: co)
                    }
                    SectionTabs(items: sections(co), title: { $0.rawValue }, selection: $section).padding(.horizontal, -Theme.Space.l)
                    switch section {
                    case .overview: CompanyOverview(engine: e, company: co, section: $section)
                    case .staff: CompanyTeam(engine: e, company: co)
                    case .finances: CompanyMoney(engine: e, company: co)
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
        co.status == .setup ? [.setup, .overview, .finances] : CompanySection.allCases.filter { $0 != .setup }
    }
}

// MARK: Overview

struct CompanyOverview: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Binding var section: CompanySection
    @State private var months = 12

    private struct Point: Identifiable { var id: Int; var series: String; var value: Double }

    var body: some View {
        let co = company
        let h = engine.companyHealth(co)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            keyFigures(co, h)
            diagnosis(co)
            if co.status == .open { operations(co, h) }
            performance(co, h)
        }
    }

    // 1. How is it doing: the figures that decide what happens next, in one block
    private func keyFigures(_ co: Company, _ h: CompanyHealth) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Profit, last 12 months").font(.caption).foregroundStyle(Theme.ivoryMuted)
                        Text((h.profitTTM < 0 ? "−" : "") + store.money(abs(h.profitTTM), in: co)).font(.figure(28, weight: .bold))
                            .foregroundStyle(h.profitTTM < 0 ? Theme.loss : Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
                    }
                    Spacer()
                    HealthChip(label: h.label)
                }
                Grid(alignment: .leading, horizontalSpacing: Theme.Space.l, verticalSpacing: Theme.Space.m) {
                    GridRow {
                        figure("Revenue", store.short(h.revenueTTM, in: co), h.revenueGrowth.map { String(format: "%+.0f%% vs 3 mo before", $0 * 100) }, Theme.change(h.revenueGrowth ?? 0))
                        figure("Margin", h.marginTTM.map { String(format: "%.0f%%", $0 * 100) } ?? "–", nil)
                        figure("Value", store.short(h.value, in: co), nil)
                    }
                    GridRow {
                        figure("Cash", store.short(co.cash, in: co), h.runwayWeeks != nil ? "lasts \(RunwayText.of(h))" : String(format: "%.0f weeks of costs", h.weeksOfCash),
                               h.runwayWeeks.map { $0 < 8 ? Theme.loss : Theme.caution } ?? Theme.ivoryFaint, valueTint: co.cash < 0 ? Theme.loss : Theme.ivory)
                        figure("Debt", store.short(h.debt, in: co), nil)
                        figure("Costs a week", store.short(h.weeklyCost, in: co), "\(co.staff.count) staff")
                    }
                }
            }
        }
    }

    private func figure(_ label: String, _ value: String, _ sub: String?, _ subTint: Color = Theme.ivoryFaint, valueTint: Color = Theme.ivory) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(valueTint).lineLimit(1).minimumScaleFactor(0.7)
            Text(sub ?? " ").font(.caption2).foregroundStyle(subTint).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 2. Why, and where to act: findings from the company's own numbers, each with a way to the section that changes it
    private func diagnosis(_ co: Company) -> some View {
        let items = engine.insights(for: co, limit: 5)
        return Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("What is going on").font(.bodyText.weight(.semibold))
                ForEach(items) { i in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: i.symbol).font(.subheadline).foregroundStyle(Theme.tone(i.tone.rawValue) == Theme.ivoryMuted ? Theme.gold : Theme.tone(i.tone.rawValue)).frame(width: 22)
                        Text(i.text).font(.subheadline).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        if let target = i.section.flatMap({ CompanySection(rawValue: $0.capitalized) }) {
                            Button { withAnimation(.snappy(duration: 0.2)) { section = target }; Haptics.choose() } label: {
                                Text(target.rawValue).font(.caption.weight(.semibold)).foregroundStyle(Theme.gold)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Capsule().strokeBorder(Theme.gold.opacity(0.4), lineWidth: 0.75))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // 3. The operating picture: what limits sales, and how customers see the place
    private func operations(_ co: Company, _ h: CompanyHealth) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Last week").font(.bodyText.weight(.semibold))
                    Spacer()
                    Text("\(Int(h.servedLastWeek.rounded())) served of \(Int(h.capacityLastWeek.rounded())) possible").font(.caption).foregroundStyle(Theme.ivoryMuted)
                }
                bar("Capacity used", h.capacityUse, h.capacityUse > 0.95 ? Theme.caution : Theme.gold)
                bar("Demand met", h.demandCoverage > 0 ? min(1, 1 / h.demandCoverage) : 0, h.demandCoverage > 1.05 ? Theme.caution : Theme.gain)
                if let b = h.bottleneck {
                    Text(h.demandCoverage > 1.05 ? "Turning customers away. The limit is: \(b.lowercased())." : "Spare room: demand, not \(b.lowercased()), is what limits sales.")
                        .font(.caption).foregroundStyle(Theme.ivoryFaint)
                }
                Divider().overlay(Theme.hairline)
                HStack(spacing: Theme.Space.l) {
                    mini("Rating", String(format: "%.1f / 5", h.rating))
                    mini("Reputation", "\(Int(co.reputation.rounded()))")
                    mini("Quality", "\(Int(co.quality.rounded()))")
                    mini("Awareness", "\(Int(co.awareness.rounded()))%")
                }
            }
        }
    }

    private func bar(_ label: String, _ v: Double, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.caption).foregroundStyle(Theme.ivoryMuted).frame(width: 104, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule().fill(tint).frame(width: max(3, g.size.width * CGFloat(min(1, max(0, v)))))
                }
            }.frame(height: 6)
            Text("\(Int((v * 100).rounded()))%").font(.caption.monospacedDigit()).foregroundStyle(Theme.ivory).frame(width: 40, alignment: .trailing)
        }
    }

    private func mini(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
            Text(value).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.ivory).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 4. The trend behind the figures
    private func performance(_ co: Company, _ h: CompanyHealth) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack {
                    Text("Revenue and profit by month").font(.bodyText.weight(.semibold))
                    Spacer()
                    ForEach([6, 12, 24], id: \.self) { m in
                        Button { months = m; Haptics.choose() } label: {
                            Text(m == 6 ? "6M" : m == 12 ? "1Y" : "2Y").font(.caption2.weight(.semibold))
                                .foregroundStyle(months == m ? Theme.ivory : Theme.ivoryMuted)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(months == m ? Theme.pillOn : Color.clear))
                        }.buttonStyle(.plain)
                    }
                }
                let rev = Array(h.revenueSeries.suffix(months)), prof = Array(h.profitSeries.suffix(months))
                if rev.count < 2 {
                    Text("The chart starts after the first full month.").font(.caption).foregroundStyle(Theme.ivoryFaint).frame(maxWidth: .infinity, minHeight: 60)
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
                    .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel { Text(store.short(v.as(Double.self) ?? 0, in: co)).font(.caption2).foregroundStyle(Theme.ivoryFaint) }
                    } }
                    .frame(height: 110)
                    HStack(spacing: Theme.Space.l) {
                        HStack(spacing: 5) { Circle().fill(Theme.gold).frame(width: 7, height: 7); Text("Revenue").font(.caption).foregroundStyle(Theme.ivoryMuted) }
                        HStack(spacing: 5) { Circle().fill(Theme.gain).frame(width: 7, height: 7); Text("Profit").font(.caption).foregroundStyle(Theme.ivoryMuted) }
                        Spacer()
                        Text("Last \(rev.count) months").font(.caption2).foregroundStyle(Theme.ivoryFaint)
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
