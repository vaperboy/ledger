import SwiftUI
import Charts
import GameCore
import Finance
import Simulation

/// The Money tab: what is owed and coming, the bank, investments, taxes, where the money goes, and the books.
struct MoneyView: View {
    var body: some View { NavigationStack { FinanceView() } }
}

/// Finance & taxes: what is owed, what is coming, where the money goes, and the books. Everything comes from `FinanceOverview`.
/// For the whole empire (the Money tab) it also holds the bank and investments; for one company only that company's money.
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
                VStack(spacing: Theme.Space.l) {
                    SectionTabs(items: companyID == nil ? Section.allCases : [.overview, .taxes, .costs, .reports], title: { $0.rawValue }, selection: $section)
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

    private func overview(_ e: GameEngine, _ o: FinanceOverview) -> some View {
        VStack(spacing: Theme.Space.l) {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionLabel("Next 30 days")
                    HStack(alignment: .firstTextBaseline) {
                        Text(store.money(o.dueWithin30Days)).font(.hero(34))
                        Spacer()
                        Chip(text: o.shortfall > 0 ? "Short by \(store.short(o.shortfall))" : "Covered", tint: o.shortfall > 0 ? Theme.loss : Theme.gain)
                    }
                    ValueRow(label: CashWording.available(companyID: companyID), value: store.money(o.cashAvailable))
                    if companyID == nil { ValueRow(label: CashWording.personalNote, value: store.money(e.netWorth.personal), tint: Theme.ivoryMuted) }
                    ValueRow(label: "Tax and VAT owed now", value: store.money(o.taxesOwed), tint: o.taxesOwed > 0 ? Theme.caution : Theme.ivory)
                    ForEach(o.notes, id: \.self) { n in Text(n).font(.caption).foregroundStyle(Theme.ivoryMuted) }
                }
            }
            if !o.taxes.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        HStack { SectionLabel("Tax summary"); Spacer(); Text("Owed now").font(.caption).foregroundStyle(Theme.ivoryFaint) }
                        ForEach(o.taxes.prefix(4)) { l in
                            ListRow(symbol: l.label.contains("VAT") || l.label.lowercased().contains("sales") ? "percent" : "building.columns", tint: Theme.ivoryMuted,
                                    title: l.label, subtitle: l.detail, trailing: store.short(l.amount))
                        }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionLabel("Upcoming payments")
                    if o.upcoming.isEmpty { Text("Nothing is due.").font(.bodyText).foregroundStyle(Theme.ivoryMuted) }
                    ForEach(o.upcoming.prefix(8)) { u in
                        ListRow(symbol: u.essential ? "lock.fill" : "calendar", tint: Theme.ivoryMuted,
                                title: u.title, subtitle: u.detail, trailing: store.short(u.amount), trailingSub: u.dateText)
                    }
                }
            }
            if !o.costsThisMonth.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        SectionLabel("Business costs · this month")
                        costDonut(o.costsThisMonth, o.costTotalThisMonth)
                    }
                }
            }
            Text("The lock marks payments that cannot be skipped without consequences: wages, tax, rent and loans.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
        }
    }

    // MARK: Taxes

    private func taxes(_ o: FinanceOverview) -> some View {
        VStack(spacing: Theme.Space.l) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionLabel("Owed now")
                    Text(store.money(o.taxesOwed)).font(.hero(34))
                    Text("Corporate tax is worked out on taxable profit, after losses carried forward. VAT is collected for the state and is not income.").font(.caption).foregroundStyle(Theme.ivoryMuted)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionLabel("By tax")
                    if o.taxes.isEmpty { Text("No tax is owed.").font(.bodyText).foregroundStyle(Theme.ivoryMuted) }
                    ForEach(o.taxes) { l in
                        VStack(alignment: .leading, spacing: 2) {
                            ValueRow(label: l.label, value: store.money(l.amount))
                            if !l.detail.isEmpty { Text(l.detail).font(.caption2).foregroundStyle(Theme.ivoryFaint) }
                        }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack { SectionLabel("Rules in \(o.countryName)"); Spacer(); Chip(text: o.basis.hasPrefix("Estimate") ? "Estimate" : "Checked", tint: o.basis.hasPrefix("Estimate") ? Theme.caution : Theme.gain) }
                    ForEach(o.rules) { r in ValueRow(label: r.label, value: r.value) }
                    Text(o.basis).font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
            }
            if !o.licences.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        SectionLabel("Licences and registrations")
                        ForEach(o.licences) { l in
                            VStack(alignment: .leading, spacing: 2) {
                                ValueRow(label: l.label, value: l.amount > 0 ? store.money(l.amount) : "free")
                                if !l.detail.isEmpty { Text(l.detail).font(.caption2).foregroundStyle(Theme.ivoryFaint) }
                            }
                        }
                        Text("Fees are the game's estimate of typical official fees.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    }
                }
            }
            Text("Game estimates, not legal advice.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
        }
    }

    // MARK: Expenses

    private func expenses(_ o: FinanceOverview) -> some View {
        let lines = yearly ? o.costsThisYear : o.costsThisMonth
        let total = yearly ? o.costTotalThisYear : o.costTotalThisMonth
        return VStack(spacing: Theme.Space.l) {
            Picker("Period", selection: $yearly) { Text("This month").tag(false); Text("This year").tag(true) }.pickerStyle(.segmented)
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionLabel("Where the money goes")
                    if lines.isEmpty { Text("No costs booked yet.").font(.bodyText).foregroundStyle(Theme.ivoryMuted) }
                    else { costDonut(lines, total) }
                }
            }
        }
    }

    private static let palette: [Color] = [Theme.slateBlue, Theme.caution, Theme.gain, Theme.gold, Theme.loss, Color(red: 0.36, green: 0.70, blue: 0.74), Color(red: 0.62, green: 0.50, blue: 0.80), Theme.goldDeep, Theme.ivoryFaint, Theme.ivoryMuted, Theme.glass, Theme.goldLight]

    /// A donut with the total in the middle and a coloured legend: label, share, amount.
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
            ForEach(lines) { l in ValueRow(label: l.label, value: store.short(l.amount)) }
        }
    }

    // MARK: Reports

    private func reports(_ e: GameEngine, _ o: FinanceOverview) -> some View {
        VStack(spacing: Theme.Space.l) {
            ReportsContent(engine: e, companyID: companyID)
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionLabel("So far, live")
                    ValueRow(label: "Revenue this month", value: store.money(o.monthRevenue))
                    ValueRow(label: "Profit this month", value: store.money(o.monthProfit), tint: Theme.change(o.monthProfit) == Theme.ivoryMuted ? Theme.ivory : Theme.change(o.monthProfit))
                    Hairline()
                    ValueRow(label: "Revenue this year", value: store.money(o.yearRevenue))
                    ValueRow(label: "Profit this year", value: store.money(o.yearProfit), tint: Theme.change(o.yearProfit) == Theme.ivoryMuted ? Theme.ivory : Theme.change(o.yearProfit))
                    ValueRow(label: "Profit last year", value: store.money(o.lastYearProfit))
                }
            }
            if companyID == nil {
                Card(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel("By company").padding(Theme.Space.l)
                        ForEach(e.state.liveCompanies.filter { $0.type != "hold" }) { co in
                            Hairline()
                            let p = Books.profit(co.books.year)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) { Text(co.name).font(.bodyText.weight(.medium)); Text("Revenue \(store.short(co.books.year["rev"] ?? 0, in: co))").font(.caption).foregroundStyle(Theme.ivoryMuted) }
                                Spacer()
                                Text((p >= 0 ? "+" : "−") + store.short(abs(p), in: co)).font(.system(.subheadline, design: .default).monospacedDigit()).foregroundStyle(Theme.change(p))
                            }.padding(Theme.Space.l)
                        }
                    }
                }
                NavigationLink { ActivityView() } label: {
                    Card { HStack { Text("Every movement on your account").font(.bodyText); Spacer(); Image(systemName: "chevron.right").foregroundStyle(Theme.ivoryFaint) } }
                }.buttonStyle(.plain)
            }
        }
    }
}
