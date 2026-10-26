import SwiftUI
import Charts
import GameCore
import Finance
import Simulation

/// Finance & taxes: what is owed, what is coming, where the money goes, and the books. Everything comes from `FinanceOverview`.
/// For the whole empire (Group > Money) it also holds the bank and investments; for one company only that company's money.
struct FinanceView: View {
    typealias Section = MoneySection
    @EnvironmentObject var store: GameStore
    var companyID: Int? = nil
    @State private var section: Section = .overview
    @State private var yearly = false

    var body: some View {
        if let e = store.engine {
            let o = e.financeOverview(companyID: companyID)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    SectionTabs(items: companyID == nil ? Section.allCases : [.overview, .taxes, .costs, .reports], primary: companyID == nil ? [.overview, .bank, .invest, .taxes] : nil, title: { $0.rawValue }, selection: $section)
                        .padding(.horizontal, -Theme.Space.margin)
                    switch section {
                    case .overview: overview(e, o)
                    case .bank: BankContent()
                    case .invest: InvestContent()
                    case .taxes: taxes(o)
                    case .costs: expenses(o)
                    case .reports: reports(e, o)
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .ledgerBackground()
            .navigationTitle(companyID == nil ? "Group money" : "Finance & taxes")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { takeRequestedSection() }
            .onChange(of: store.moneySection) { _, _ in takeRequestedSection() }
        }
    }

    private func takeRequestedSection() {
        if companyID == nil, let s = store.moneySection { section = s; store.moneySection = nil }
    }

    // MARK: Overview

    /// Engine notes by weight: real warnings with an icon and amber, the plain figure as a quiet line, the disclaimer as a footnote.
    @ViewBuilder private func overviewNotes(_ notes: [String]) -> some View {
        let warnings: [String] = notes.filter { $0.hasPrefix("The next 30 days") || $0.hasPrefix("This month costs more") }
        let footnotes: [String] = notes.filter { $0.contains("game estimates") }
        let plain: [String] = notes.filter { n in !warnings.contains(n) && !footnotes.contains(n) }
        ForEach(warnings, id: \.self) { n in
            Label { Text(n.tidyMoney).font(.caption).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                .foregroundStyle(Theme.caution)
        }
        ForEach(plain, id: \.self) { n in
            Text(n.tidyMoney).font(.caption).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
        }
        ForEach(footnotes, id: \.self) { n in
            Text(n).font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The answer first: can the next 30 days be paid? Then what is owed, what is due, and where the money goes.
    private func overview(_ e: GameEngine, _ o: FinanceOverview) -> some View {
        let short = o.shortfall > 0
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Due in the next 30 days").capsLabel()
                    Spacer()
                    Chip(text: short ? "Short by \(store.short(o.shortfall))" : "Covered", tint: short ? Theme.loss : Theme.gain)
                }
                Text(store.money(o.dueWithin30Days)).font(.hero(36)).foregroundStyle(short ? Theme.loss : Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
                if short { Text("Cash will not cover what is due. Move money in, sell something or ask the bank before the dates below.").font(.caption).foregroundStyle(Theme.loss).fixedSize(horizontal: false, vertical: true) }
            }
            KeyFigures(items: [
                .init(label: CashWording.available(companyID: companyID), value: store.short(o.cashAvailable), tint: o.cashAvailable < 0 ? Theme.loss : Theme.ivory),
                .init(label: "Tax and VAT owed", value: store.short(o.taxesOwed), tint: o.taxesOwed > 0 ? Theme.caution : Theme.ivory),
                companyID == nil ? .init(label: "Private", value: store.short(e.netWorth.personal), tint: Theme.ivoryMuted, sub: "cash and savings")
                                 : .init(label: "Profit, month", value: store.short(o.monthProfit), tint: Theme.change(o.monthProfit) == Theme.ivoryMuted ? Theme.ivory : Theme.change(o.monthProfit)),
            ])
            overviewNotes(o.notes)

            LedgerSection("Upcoming payments") {
                VStack(spacing: 0) {
                    if o.upcoming.isEmpty { Text("Nothing is due.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted) }
                    ForEach(Array(o.upcoming.prefix(8).enumerated()), id: \.element.id) { n, u in
                        FlatRow(label: u.title, value: store.short(u.amount),
                                sub: ([u.dateText, u.essential ? "cannot be skipped" : ""] + [u.detail]).filter { !$0.isEmpty }.joined(separator: " · "),
                                tint: u.essential ? Theme.ivory : Theme.ivoryMuted, rule: n > 0)
                    }
                }
            }
            if !o.taxes.isEmpty {
                LedgerSection(title: "Tax owed now", trailing: { moreLink("All taxes", .taxes) }) {
                    VStack(spacing: 0) {
                        ForEach(Array(o.taxes.prefix(4).enumerated()), id: \.element.id) { n, l in
                            FlatRow(label: l.label, value: store.short(l.amount), sub: l.detail, rule: n > 0)
                        }
                    }
                }
            }
            if !o.costsThisMonth.isEmpty {
                LedgerSection(title: "Business costs this month", trailing: { moreLink("Details", .costs) }) {
                    costDonut(o.costsThisMonth, o.costTotalThisMonth)
                }
            }
        }
    }

    /// A champagne text link with a chevron that switches to another part of this screen.
    private func moreLink(_ text: String, _ target: Section) -> some View {
        Button { section = target; Haptics.tap() } label: {
            HStack(spacing: 3) { Text(text); Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)) }
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.gold)
        }.buttonStyle(.plain)
    }

    // MARK: Taxes

    private func taxes(_ o: FinanceOverview) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tax and VAT owed now").capsLabel()
                Text(store.money(o.taxesOwed)).font(.hero(36)).foregroundStyle(o.taxesOwed > 0 ? Theme.caution : Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
                Text("Corporate tax is worked out on taxable profit, after losses carried forward. VAT is collected for the state and is not income.").font(.caption).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            }
            LedgerSection("By tax") {
                VStack(spacing: 0) {
                    if o.taxes.isEmpty { Text("No tax is owed.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted) }
                    ForEach(Array(o.taxes.enumerated()), id: \.element.id) { n, l in
                        FlatRow(label: l.label, value: store.money(l.amount), sub: l.detail.tidyMoney, rule: n > 0)
                    }
                }
            }
            LedgerSection(title: "Rules in \(o.countryName)", trailing: { Chip(text: o.basis.hasPrefix("Estimate") ? "Estimate" : "Checked", tint: o.basis.hasPrefix("Estimate") ? Theme.caution : Theme.gain) }) {
                VStack(spacing: 0) {
                    ForEach(Array(o.rules.enumerated()), id: \.element.id) { n, r in FlatRow(label: r.label, value: r.value, rule: n > 0) }
                    Text(o.basis).font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 6)
                }
            }
            if !o.licences.isEmpty {
                LedgerSection("Licences and registrations") {
                    VStack(spacing: 0) {
                        ForEach(Array(o.licences.enumerated()), id: \.element.id) { n, l in
                            FlatRow(label: l.label, value: l.amount > 0 ? store.money(l.amount) : "free", sub: l.detail.tidyMoney, rule: n > 0)
                        }
                        Text("Fees are the game's estimate of typical official fees. Game estimates, not legal advice.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 6)
                    }
                }
            }
        }
    }

    // MARK: Expenses

    private func expenses(_ o: FinanceOverview) -> some View {
        let lines = yearly ? o.costsThisYear : o.costsThisMonth
        let total = yearly ? o.costTotalThisYear : o.costTotalThisMonth
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            SegmentedChoice(items: [false, true], title: { $0 ? "This year" : "This month" }, selection: $yearly)
            VStack(alignment: .leading, spacing: 4) {
                Text(yearly ? "Business costs this year" : "Business costs this month").capsLabel()
                Text(store.money(total)).font(.hero(36)).minimumScaleFactor(0.6).lineLimit(1)
            }
            LedgerSection("Where the money goes") {
                if lines.isEmpty { Text("No costs booked yet.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted) }
                else { costDonut(lines, total) }
            }
        }
    }

    private static let palette: [Color] = [Theme.slateBlue, Theme.caution, Theme.gain, Theme.gold, Theme.loss, Color(red: 0.36, green: 0.70, blue: 0.74), Color(red: 0.62, green: 0.50, blue: 0.80), Theme.goldDeep, Theme.ivoryFaint, Theme.ivoryMuted, Theme.glass, Theme.goldLight]

    /// A donut with the total in the middle and a coloured legend, then every line with its amount.
    private func costDonut(_ lines: [FinanceLine], _ total: Double) -> some View {
        VStack(spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.l) {
                ZStack {
                    Chart(lines) { l in
                        SectorMark(angle: .value("Amount", l.amount), innerRadius: .ratio(0.64), angularInset: 1.5)
                            .foregroundStyle(by: .value("Cost", l.label))
                            .cornerRadius(3)
                    }
                    .chartLegend(.hidden)
                    .chartForegroundStyleScale(range: Self.palette)
                    VStack(spacing: 1) { Text(store.short(total)).font(.figure(16, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1); Text("Total").font(.caption2).foregroundStyle(Theme.ivoryFaint) }.padding(18)
                }
                .frame(width: 132, height: 132)
                VStack(spacing: 7) {
                    ForEach(Array(lines.prefix(6).enumerated()), id: \.offset) { i, l in
                        HStack(spacing: 6) {
                            Circle().fill(Self.palette[i % Self.palette.count]).frame(width: 7, height: 7)
                            Text(l.label).font(.caption).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(Int((l.share * 100).rounded()))%").font(.caption2.monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
                        }
                    }
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.element.id) { n, l in FlatRow(label: l.label, value: store.short(l.amount), rule: n > 0) }
            }
        }
    }

    // MARK: Reports

    private func gainTint(_ v: Double) -> Color { Theme.change(v) == Theme.ivoryMuted ? Theme.ivory : Theme.change(v) }

    private func reports(_ e: GameEngine, _ o: FinanceOverview) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profit this year, so far").capsLabel()
                Text(store.money(o.yearProfit)).font(.hero(36)).foregroundStyle(gainTint(o.yearProfit)).minimumScaleFactor(0.6).lineLimit(1)
            }
            KeyFigures(items: [
                .init(label: "Revenue, month", value: store.short(o.monthRevenue)),
                .init(label: "Profit, month", value: store.short(o.monthProfit), tint: gainTint(o.monthProfit)),
                .init(label: "Revenue, year", value: store.short(o.yearRevenue)),
                .init(label: "Profit last year", value: store.short(o.lastYearProfit), tint: gainTint(o.lastYearProfit)),
            ], columns: 2)
            ReportsContent(engine: e, companyID: companyID)
            if companyID == nil {
                LedgerSection("By company, this year") {
                    VStack(spacing: 0) {
                        ForEach(Array(e.state.liveCompanies.filter { $0.type != "hold" }.enumerated()), id: \.element.id) { n, co in
                            let p = Books.profit(co.books.year)
                            Button { store.openCompany(co.id, section: .finances) } label: {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(co.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineLimit(1)
                                        Text("Revenue \(store.short(co.books.year["rev"] ?? 0, in: co))").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                                    }
                                    Spacer(minLength: 8)
                                    Text((p >= 0 ? "+" : "−") + store.short(abs(p), in: co)).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.change(p))
                                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                                }.padding(.vertical, 9).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            .overlay(alignment: .top) { if n > 0 { Hairline() } }
                        }
                    }
                }
                NavigationLink { ActivityView() } label: {
                    HStack { Text("Every movement on your account").font(.system(size: 13.5)).foregroundStyle(Theme.gold); Spacer(); Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.gold) }
                        .padding(.vertical, 10).contentShape(Rectangle())
                        .overlay(alignment: .top) { Hairline() }
                }.buttonStyle(.plain)
            }
        }
    }
}
