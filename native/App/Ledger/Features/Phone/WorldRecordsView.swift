import SwiftUI
import GameCore
import Businesses
import Simulation

/// Read-only records of the world around you: your rival, the Top 50, monthly results per company, the crisis centre and the
/// retirement hall. Nothing is decided here; the crisis centre links to the Inbox, where each decision is answered.
struct WorldRecordsView: View {
    enum Page: String, CaseIterable, Hashable, Identifiable {
        var id: String { rawValue }
        case rival = "Your rival", topFifty = "Top 50", months = "Monthly results", crisis = "Crisis centre", hall = "Retirement hall"
        var glyph: String {
            switch self {
            case .rival: return Glyph.people
            case .topFifty: return Glyph.list
            case .months: return Glyph.calendar
            case .crisis: return Glyph.warning
            case .hall: return Glyph.person
            }
        }
    }
    @EnvironmentObject var store: GameStore
    /// The record to show on its own; without one the screen is the table of all records, each row opening its page.
    var page: Page?
    @State private var opened: Page?
    @State private var companyID: Int?


    private func monthName(_ index: Int) -> String { GameCalendar.monthNames[index % 12] + " " + String(index / 12) }

    var body: some View {
        if let e = store.engine {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    if let page {
                        record(page, e)
                    } else {
                        recordsTable(e)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ledgerBackground()
        }
    }

    @ViewBuilder private func record(_ page: Page, _ e: GameEngine) -> some View {
        switch page {
        case .rival: rival(e)
        case .topFifty: topFifty(e)
        case .months: months(e)
        case .crisis: crisis(e)
        case .hall: hall(e)
        }
    }

    /// Five records in one table: the rival, the Top 50, monthly results, the crisis centre and the retirement hall.
    private func recordsTable(_ e: GameEngine) -> some View {
        OverviewSettingsCard(heading: "Records") {
            ForEach(Page.allCases) { (p: Page) in
                SettingsTableRow(title: p.rawValue, note: note(p), value: value(p, e), glyph: p.glyph) { opened = p }
            }
        }
        .navigationDestination(item: $opened) { (p: Page) in
            WorldRecordsView(page: p).appScreen(title: p.rawValue, subtitle: "Records of the world around you")
        }
    }

    private func note(_ p: Page) -> String {
        switch p {
        case .rival: return "The owner who keeps beating you, or loses to you"
        case .topFifty: return "The fifty biggest groups"
        case .months: return "Results per company, month by month"
        case .crisis: return "Open crises and what answers them"
        case .hall: return "Owners who retired"
        }
    }

    private func value(_ p: Page, _ e: GameEngine) -> String {
        switch p {
        case .rival: return e.nemesis?.owner ?? "None yet"
        default: return ""
        }
    }

    @ViewBuilder private func rival(_ e: GameEngine) -> some View {
        if let n = e.nemesis {
            HeroFigure(label: "Your rival", value: n.owner, note: n.groupName + (n.bankrupt ? " · gone" : "") + " · since " + GameCalendar.dateString(week: n.since))
            FigureCard(items: [
                .init(label: "You won", value: "\(n.wins)", tint: Theme.gain),
                .init(label: "They won", value: "\(n.losses)", tint: n.losses > n.wins ? Theme.loss : Theme.ivory)
            ], columns: 2)
            CardSection("The rivalry") {
                if n.log.isEmpty { Text("Nothing has happened between you yet.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted) }
                VStack(spacing: 0) {
                    ForEach(Array(n.log.reversed().prefix(30).enumerated()), id: \.offset) { i, l in
                        FlatRow(label: e.displayText(l.text.tidyMoney), value: GameCalendar.dateString(week: l.week), rule: i > 0)
                    }
                }
            }
        } else {
            NoteCard(text: "No rival has picked you out yet. When a rival group makes you its target, the rivalry and its score are kept here.", glyph: Glyph.people)
        }
    }

    @ViewBuilder private func topFifty(_ e: GameEngine) -> some View {
        if let t = e.topFifty {
            FigureCard(items: [
                .init(label: "Year", value: "\(t.year)"),
                .init(label: "Your place", value: t.yourRank.map { "#\($0)" } ?? "Not on it", tint: t.yourRank == nil ? Theme.ivoryMuted : Theme.gold),
                .init(label: "Listed", value: "\(t.of)")
            ])
            Card(padding: 14) {
                VStack(spacing: 0) {
                    ForEach(Array(t.rows.enumerated()), id: \.offset) { i, r in
                        FlatRow(label: "\(i + 1)  " + r.name + (r.isYou ? " (you)" : ""), value: store.short(r.revenue), sub: r.trades, tint: r.isYou ? Theme.gold : Theme.ivory, rule: i > 0)
                    }
                }
            }
        } else {
            NoteCard(text: "The paper prints the 50 biggest companies by sales every January. The first list has not been printed yet.", glyph: Glyph.list)
        }
    }

    @ViewBuilder private func months(_ e: GameEngine) -> some View {
        let open = e.state.companies.filter { $0.status.isLive && $0.type != "hold" }
        if open.isEmpty {
            NoteCard(text: "Monthly results appear once you run a company.", glyph: Glyph.calendar)
        } else {
            let chosen = open.first { $0.id == companyID } ?? open[0]
            let cur = e.currency(for: chosen)
            if open.count > 1 {
                Picker("Company", selection: Binding(get: { chosen.id }, set: { companyID = $0 })) {
                    ForEach(open) { Text($0.name).tag($0.id) }
                }.pickerStyle(.menu).tint(Theme.gold)
                .padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).fill(Theme.surfaceTable))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            }
            if let m = e.monthlyResults(companyID: chosen.id) {
                FigureCard(items: [
                    .init(label: "This month so far", value: cur.tidyShort(m.thisMonth.profit), tint: Theme.change(m.thisMonth.profit)),
                    .init(label: "Last month", value: m.lastMonth.map { cur.tidyShort($0) } ?? "–", tint: m.lastMonth.map { Theme.change($0) } ?? Theme.ivoryMuted),
                    .init(label: "This year", value: cur.tidyShort(m.thisYear), tint: Theme.change(m.thisYear))
                ])
                CardSection("This month so far") {
                    VStack(spacing: 0) {
                        FlatRow(label: "Income", value: cur.tidyShort(m.thisMonth.income), rule: false)
                        ForEach(Array(m.thisMonth.costs.enumerated()), id: \.offset) { _, c in FlatRow(label: c.name, value: "−" + cur.tidyShort(c.amount)) }
                    }
                }
                CardSection("Earlier months") {
                    if m.months.isEmpty { Text("The first month is not closed yet.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted) }
                    VStack(spacing: 0) {
                        ForEach(Array(m.months.enumerated()), id: \.offset) { i, mo in
                            FlatRow(label: monthName(mo.monthIndex), value: cur.tidyShort(mo.profit), sub: "Income " + cur.tidyShort(mo.income) + " · costs " + cur.tidyShort(mo.expenses), tint: Theme.change(mo.profit), rule: i > 0)
                        }
                    }
                }
            }
            Button { store.openCompany(chosen.id) } label: {
                LinkLabel(text: "Open \(chosen.name)")
            }.buttonStyle(.plain)
        }
    }

    @ViewBuilder private func crisis(_ e: GameEngine) -> some View {
        let list = e.crisisCentre
        if list.isEmpty {
            NoteCard(text: "No crisis is waiting. Warnings and decisions that need you quickly collect here.", glyph: Glyph.check)
        } else {
            Text("\(list.count) waiting, soonest deadline first. Tap one to answer it in the Inbox.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
            Card(padding: 14) {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, m in
                        if i > 0 { CardLine() }
                        Button { store.go(.openMessage(m.id)) } label: {
                            RowLine(glyph: m.tone == "bad" ? Glyph.warning : Glyph.inbox, tint: m.tone == "bad" ? Theme.loss : Theme.gold,
                                    title: e.displayText(m.title, companyID: m.companyID),
                                    subtitle: m.expiresWeek.map { w in let left = w - e.state.week; return left > 0 ? "Expires in \(left) week\(left == 1 ? "" : "s")" : "Expires this week" } ?? "No deadline",
                                    chevron: true)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private func hall(_ e: GameEngine) -> some View {
        let list = e.retirementHall
        if list.isEmpty {
            NoteCard(text: "Nobody has retired from your companies yet. Long-serving staff are remembered here when they do.", glyph: Glyph.person)
        } else {
            Card(padding: 14) {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.offset) { i, p in
                        FlatRow(label: p.name, value: GameCalendar.dateString(week: p.week), sub: e.displayText(p.text.tidyMoney), rule: i > 0)
                    }
                }
            }
        }
    }
}
