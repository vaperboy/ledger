import SwiftUI
import Simulation
import Finance
import Businesses

/// Today's summary, the top of the Company tab: net worth, the report prompt, the suggestion, what is coming up, first steps and goals.
/// (The company list that used to be a card here is the Company tab's own list below it.)
struct HomeSummary: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    var engine: GameEngine

    var body: some View {
        let e = engine
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HomeHeader(engine: e)
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: Theme.Space.xl) {
                    VStack(spacing: Theme.Space.l) { NetWorthSection(engine: e) }
                    VStack(spacing: Theme.Space.l) { ReportPromptSection(engine: e); SuggestionCard(engine: e); ComingUpCard(engine: e); FirstStepsCard(engine: e); GoalsCard(engine: e) }
                }
            } else {
                NetWorthSection(engine: e)
                ReportPromptSection(engine: e)
                SuggestionCard(engine: e)
                ComingUpCard(engine: e)
                FirstStepsCard(engine: e)
                GoalsCard(engine: e)
            }
        }
    }
}

// MARK: Header

struct HomeHeader: View {
    var engine: GameEngine
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Week \(engine.state.week + 1) · \(engine.date)").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                Spacer()
                Text("\(engine.homeCountry.flag) \(engine.homeCountry.name)").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
            }
            Text(title).font(.serifTitle(25)).foregroundStyle(Theme.ivory)
        }
        .padding(.top, Theme.Space.s)
    }
    private var title: String {
        let name = engine.state.player.name
        return name.isEmpty ? "You" : name
    }
}

// MARK: Net worth

/// The hero of the home screen: the figure, what it did this week and this month, the chart, and what it is made of.
struct NetWorthSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var days = 365

    var body: some View {
        let nw = engine.netWorth
        let hist = engine.dayHistory
        let week = DayHistory.change(hist.netWorth, days: 7)
        let month = DayHistory.change(hist.netWorth, days: 30)
        let owed = nw.debt + nw.pendingTax
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Net worth").capsLabel()
                Spacer()
                PeriodPicker(days: $days)
            }
            Text(store.money(nw.total))
                .font(.hero(40))
                .foregroundStyle(nw.total < 0 ? Theme.loss : Theme.ivory)
                .minimumScaleFactor(0.55).lineLimit(1)
            changeLine(week: week, month: month)
            NetWorthChart(engine: engine, days: days).padding(.top, 6)
            KeyFigures(items: [
                .init(label: "Cash", value: store.short(nw.personal)),
                .init(label: "Invested", value: store.short(nw.investments)),
                .init(label: "Companies", value: store.short(nw.companies)),
                .init(label: "Debt", value: owed > 0 ? "−" + store.short(owed) : store.short(0), tint: owed > 0 ? Theme.loss : Theme.ivory),
            ], columns: 4).padding(.top, 10)
        }
    }

    @ViewBuilder private func changeLine(week: (amount: Double, share: Double?)?, month: (amount: Double, share: Double?)?) -> some View {
        HStack(spacing: 4) {
            if let week {
                Text(signed(week.amount)).foregroundStyle(Theme.change(week.amount))
                Text("this week").foregroundStyle(Theme.ivoryMuted)
            }
            if let month {
                Text("·").foregroundStyle(Theme.ivoryFaint)
                Text(signed(month.amount)).foregroundStyle(Theme.change(month.amount))
                Text("in 30 days").foregroundStyle(Theme.ivoryMuted)
            }
            if week == nil && month == nil { Text("The history fills in day by day.").foregroundStyle(Theme.ivoryFaint) }
        }
        .font(.system(size: 12.5).monospacedDigit())
    }
    private func signed(_ v: Double) -> String { abs(v) < 0.5 ? store.short(0) : (v > 0 ? "+" : "−") + store.short(abs(v)) }
}

/// 1W 1M 3M 1Y All, as text with an underline.
struct PeriodPicker: View {
    @Binding var days: Int
    static let periods: [(label: String, days: Int)] = [("1W", 8), ("1M", 31), ("3M", 92), ("1Y", 365), ("All", 3650)]
    var body: some View {
        HStack(spacing: 11) {
            ForEach(Self.periods, id: \.days) { p in
                Button { days = p.days; Haptics.choose() } label: {
                    Text(p.label.uppercased()).font(.system(size: 11, weight: .medium)).tracking(0.4)
                        .foregroundStyle(days == p.days ? Theme.ivory : Theme.ivoryFaint)
                        .padding(.bottom, 2)
                        .overlay(alignment: .bottom) { if days == p.days { Rectangle().fill(Theme.gold).frame(height: 1) } }
                }.buttonStyle(.plain)
            }
        }
    }
}

// MARK: Your companies

/// The companies at a glance, best earners first: a dot for health, profit and cash on one line each; a tap opens the company.
struct EmpireCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var body: some View {
        let cos = engine.state.liveCompanies.filter { $0.type != "hold" }
        if !cos.isEmpty {
            let rows = cos.map { (co: $0, h: engine.companyHealth($0)) }.sorted { $0.h.profitTTM > $1.h.profitTTM }
            LedgerSection(title: "Companies", trailing: {
                Text("Profit 12 mo  ·  Cash").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
            }) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.prefix(5).enumerated()), id: \.element.co.id) { i, r in
                        Button { store.go(.openCompany(r.co.id)) } label: {
                            HStack(spacing: 10) {
                                Circle().fill(HealthChip.tint(r.h.label)).frame(width: 6, height: 6)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.co.name).font(.system(size: 14)).foregroundStyle(Theme.ivory).lineLimit(1)
                                    Text(engine.tradeName(r.co) + (r.h.bottleneck.map { " · limited by " + $0.lowercased() } ?? "")).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(store.short(r.h.profitTTM, in: r.co)).font(.system(size: 14).monospacedDigit()).foregroundStyle(r.h.profitTTM < 0 ? Theme.loss : Theme.ivory)
                                    .frame(minWidth: 62, alignment: .trailing)
                                Text(store.short(r.co.cash, in: r.co)).font(.system(size: 13).monospacedDigit()).foregroundStyle(r.co.cash < 0 ? Theme.loss : Theme.ivoryMuted).frame(minWidth: 60, alignment: .trailing)
                            }
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if i < min(rows.count, 5) - 1 { Hairline() }
                    }
                    if rows.count > 5 {
                        Button { store.tab = .company } label: { Text("All \(rows.count) companies  →").font(.system(size: 12)).foregroundStyle(Theme.gold) }
                            .buttonStyle(.plain).padding(.top, 6).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

// MARK: Next day

/// The one filled control on the screen: a champagne pill at the bottom right, the week's progress at the left.
struct AdvanceBar: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Day \(engine.state.day + 1) of 7").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { d in
                        Capsule().fill(d <= engine.state.day ? Theme.gold : Theme.hairline).frame(width: 22, height: 3)
                    }
                }
            }
            Spacer(minLength: 8)
            Button { store.untilNeeded() } label: {
                Image(systemName: "forward.fill").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                    .frame(width: 40, height: 40).overlay(Circle().strokeBorder(Theme.ivory.opacity(0.18), lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .disabled(store.isAdvancing || engine.state.isGameOver)
            .accessibilityLabel("Skip ahead until something needs you")
            Button { store.isAdvancing ? store.stopAdvancing() : store.nextDay() } label: {
                Text(store.isAdvancing ? "Stop" : engine.state.isGameOver ? "Game over" : "Next day  ›")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(red: 0.09, green: 0.075, blue: 0.055))
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 24).frame(height: 44)
                    .background(Capsule().fill(Theme.gold))
            }
            .buttonStyle(.plain)
            .disabled(engine.state.isGameOver)
        }
        .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.l).padding(.bottom, Theme.Space.s)
        .background(LinearGradient(colors: [Theme.page.opacity(0), Theme.page.opacity(0.94), Theme.page], startPoint: .top, endPoint: .center))
    }
}
