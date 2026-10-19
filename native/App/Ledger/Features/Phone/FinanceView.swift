import SwiftUI
import Charts
import GameCore
import Finance
import Simulation

/// Finance & taxes: what is owed, what is coming, where the money goes, and the books. Everything comes from `FinanceOverview`.
struct FinanceView: View {
    enum Section: String, CaseIterable, Hashable { case overview = "Overview", taxes = "Taxes", expenses = "Expenses", reports = "Reports" }
    @EnvironmentObject var store: GameStore
    var companyID: Int? = nil
    @State private var section: Section = .overview
    @State private var yearly = false

    var body: some View {
        if let e = store.engine {
            let o = e.financeOverview(companyID: companyID)
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    SectionTabs(items: Section.allCases, title: { $0.rawValue }, selection: $section).padding(.horizontal, -Theme.Space.l)
                    switch section {
                    case .overview: overview(e, o)
                    case .taxes: taxes(o)
                    case .expenses: expenses(o)
                    case .reports: reports(e, o)
                    }
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("Finance & taxes")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Overview

    private func overview(_ e: GameEngine, _ o: FinanceOverview) -> some View {
        VStack(spacing: Theme.Space.l) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionLabel("Next 30 days")
                    HStack(alignment: .firstTextBaseline) {
                        Text(store.money(o.dueWithin30Days)).font(.figure(30))
                        Spacer()
                        Chip(text: o.shortfall > 0 ? "Short by \(store.short(o.shortfall))" : "Covered", tint: o.shortfall > 0 ? Theme.loss : Theme.gain)
                    }
                    ValueRow(label: "Cash available", value: store.money(o.cashAvailable))
                    ValueRow(label: "Tax and VAT owed now", value: store.money(o.taxesOwed), tint: o.taxesOwed > 0 ? Theme.caution : Theme.ivory)
                    ForEach(o.notes, id: \.self) { n in Text(n).font(.caption).foregroundStyle(Theme.ivoryMuted) }
                }
            }
            Card(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("Upcoming payments").padding(Theme.Space.l)
                    if o.upcoming.isEmpty { Text("Nothing is due.").font(.bodyText).foregroundStyle(Theme.ivoryMuted).padding(.horizontal, Theme.Space.l).padding(.bottom, Theme.Space.l) }
                    ForEach(o.upcoming.prefix(8)) { u in
                        Divider().overlay(Theme.hairline)
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: u.essential ? "lock.fill" : "calendar").font(.caption).foregroundStyle(u.essential ? Theme.roseGold : Theme.ivoryFaint).frame(width: 18).padding(.top, 3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(u.title).font(.bodyText.weight(.medium)).foregroundStyle(Theme.ivory)
                                Text("\(u.dateText) · \(u.detail)").font(.caption).foregroundStyle(Theme.ivoryMuted)
                            }
                            Spacer(minLength: 8)
                            Text(store.short(u.amount)).font(.system(.subheadline, design: .serif).monospacedDigit()).foregroundStyle(Theme.ivory)
                        }
                        .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.m)
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
                    Text(store.money(o.taxesOwed)).font(.figure(30))
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
                    else {
                        ZStack {
                            Chart(lines) { l in
                                SectorMark(angle: .value("Amount", l.amount), innerRadius: .ratio(0.62), angularInset: 1.5)
                                    .foregroundStyle(by: .value("Cost", l.label))
                                    .cornerRadius(3)
                            }
                            .chartLegend(.hidden)
                            .chartForegroundStyleScale(range: [Theme.gold, Theme.roseGold, Theme.gain, Theme.caution, Color(red: 0.55, green: 0.65, blue: 0.80), Theme.ivoryMuted, Theme.goldDeep, Theme.loss, Theme.ivoryFaint, Color(red: 0.70, green: 0.55, blue: 0.75), Theme.leather, Theme.glass])
                            .frame(height: 190)
                            VStack(spacing: 2) { Text(store.short(total)).font(.figure(22)); Text("total").font(.caption2).foregroundStyle(Theme.ivoryFaint) }
                        }
                        ForEach(lines) { l in
                            HStack {
                                Text(l.label).font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                                Spacer()
                                Text("\(Int((l.share * 100).rounded()))%").font(.caption.monospacedDigit()).foregroundStyle(Theme.ivoryFaint).frame(width: 44, alignment: .trailing)
                                Text(store.short(l.amount)).font(.system(.subheadline, design: .serif).monospacedDigit()).foregroundStyle(Theme.ivory).frame(width: 90, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Reports

    private func reports(_ e: GameEngine, _ o: FinanceOverview) -> some View {
        VStack(spacing: Theme.Space.l) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionLabel("Profit and loss")
                    ValueRow(label: "Revenue this month", value: store.money(o.monthRevenue))
                    ValueRow(label: "Profit this month", value: store.money(o.monthProfit), tint: Theme.change(o.monthProfit) == Theme.ivoryMuted ? Theme.ivory : Theme.change(o.monthProfit))
                    Divider().overlay(Theme.hairline)
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
                            Divider().overlay(Theme.hairline)
                            let p = Books.profit(co.books.year)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) { Text(co.name).font(.bodyText.weight(.medium)); Text("Revenue \(store.short(co.books.year["rev"] ?? 0, in: co))").font(.caption).foregroundStyle(Theme.ivoryMuted) }
                                Spacer()
                                Text((p >= 0 ? "+" : "−") + store.short(abs(p), in: co)).font(.system(.subheadline, design: .serif).monospacedDigit()).foregroundStyle(Theme.change(p))
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
