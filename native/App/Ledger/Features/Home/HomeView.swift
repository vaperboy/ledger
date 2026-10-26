import SwiftUI
import Simulation
import Finance
import Businesses

/// Today's summary, the top of the Company tab, in the order a business owner reads it: what I am worth and where it is heading,
/// whether the money holds this month (profit, cash, what falls due), what needs me, then a quiet line for a finished report.
/// The companies list follows below it, then the Next day bar. First steps and goals live in More > Goals.
struct HomeSummary: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    var engine: GameEngine

    var body: some View {
        let e = engine
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HomeHeader(engine: e)
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: Theme.Space.xl) {
                    VStack(spacing: Theme.Space.l) { NetWorthSection(engine: e); MoneyPulseSection(engine: e) }
                    VStack(spacing: Theme.Space.l) { SuggestionCard(engine: e); ReportPromptSection(engine: e) }
                }
            } else {
                NetWorthSection(engine: e)
                MoneyPulseSection(engine: e)
                SuggestionCard(engine: e)
                ReportPromptSection(engine: e)
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
            NetWorthMix(nw: nw, owed: owed).padding(.top, 8)
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

/// What the net worth is made of: one flat bar (neutral shades, no decorative colour) and a single legend line. Secondary to
/// the figure itself, so it stays small; what is owed shows in red only when there is something owed.
struct NetWorthMix: View {
    @EnvironmentObject var store: GameStore
    var nw: NetWorth
    var owed: Double

    var body: some View {
        let parts: [(label: String, value: Double, shade: Double)] = [
            ("Private", nw.personal, 0.85), ("Companies", nw.companies, 0.55), ("Invested", nw.investments, 0.35), ("Luxury", nw.luxury, 0.2),
        ].filter { $0.value > 0.5 }
        let sum = max(1, parts.reduce(0) { $0 + $1.value })
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                HStack(spacing: 1.5) {
                    ForEach(parts, id: \.label) { p in
                        Rectangle().fill(Theme.ivory.opacity(p.shade)).frame(width: max(2, (g.size.width - 1.5 * Double(parts.count - 1)) * p.value / sum))
                    }
                }
            }
            .frame(height: 4)
            WrapRow(spacing: 10) {
                ForEach(parts, id: \.label) { p in
                    HStack(spacing: 4) {
                        Rectangle().fill(Theme.ivory.opacity(p.shade)).frame(width: 7, height: 7)
                        Text(p.label).foregroundStyle(Theme.ivoryFaint)
                        Text(store.short(p.value)).foregroundStyle(Theme.ivoryMuted)
                    }
                }
                if owed > 0.5 {
                    HStack(spacing: 4) {
                        Text("Owed").foregroundStyle(Theme.ivoryFaint)
                        Text("−" + store.short(owed)).foregroundStyle(Theme.loss)
                    }
                }
            }
            .font(.system(size: 11.5).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: This month

/// The second thing an owner asks after "what am I worth": does the money hold? Profit this month across every company, the cash
/// that can pay, and what falls due in the next 30 days, with a clear covered/short answer. Tapping it opens Group > Money.
struct MoneyPulseSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        let o = engine.financeOverview(companyID: nil)
        let short = o.shortfall > 0
        let profitTint: Color = o.monthProfit < -0.5 ? Theme.loss : o.monthProfit > 0.5 ? Theme.gain : Theme.ivory
        let dueSub: String = short ? "short by " + store.short(o.shortfall) : (o.dueWithin30Days > 0.5 ? "covered" : "nothing due")
        Button {
            Haptics.tap(); store.moneySection = .overview; store.jump(to: .group)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("This month").capsLabel()
                    Spacer()
                    HStack(spacing: 3) {
                        Text("Money").font(.system(size: 11.5))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }.foregroundStyle(Theme.gold)
                }
                KeyFigures(items: [
                    .init(label: "Profit", value: signed(o.monthProfit), tint: profitTint, sub: "year " + signed(o.yearProfit)),
                    .init(label: CashWording.group, value: store.short(o.cashAvailable), tint: o.cashAvailable < 0 ? Theme.loss : Theme.ivory, sub: "incl. private"),
                    .init(label: "Due in 30 days", value: store.short(o.dueWithin30Days), tint: short ? Theme.loss : Theme.ivory, sub: dueSub),
                ])
                if short {
                    Label("Cash will not cover what falls due. Open Money to see the dates.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(Theme.loss).fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Group money")
    }

    private func signed(_ v: Double) -> String { abs(v) < 0.5 ? store.short(0) : (v > 0 ? "+" : "−") + store.short(abs(v)) }
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
