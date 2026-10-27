import SwiftUI
import Simulation
import Finance
import Businesses

/// Today's summary, the top of the Home tab (route name `.company`), built like native/design/new-look-2026-10/HomeMix.dc.html:
/// header, one slim net worth card, four boxes (Bank, Hire, Reports, Market), profit and due cards, "Needs you", a one-line report row.
/// The companies list follows below it (CompaniesView), then the Next day bar. First steps and goals live in Phone > Goals.
struct HomeSummary: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var onNewCompany: () -> Void

    var body: some View {
        let e = engine
        VStack(alignment: .leading, spacing: 8) {
            HomeHeader(name: playerName, dateText: "Week \(e.state.week + 1) · \(e.date)", onNewCompany: onNewCompany)
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: Theme.Space.l) {
                    NetWorthCard(engine: e)
                    VStack(spacing: 8) { HomeQuickBoxes(engine: e); HomeMoneyCards(engine: e) }
                }
                HStack(alignment: .top, spacing: Theme.Space.l) {
                    NeedsYouCard(engine: e)
                    ReportPromptSection(engine: e)
                }
            } else {
                NetWorthCard(engine: e)
                HomeQuickBoxes(engine: e)
                HomeMoneyCards(engine: e)
                NeedsYouCard(engine: e)
                ReportPromptSection(engine: e)
            }
        }
    }

    private var playerName: String {
        let n = engine.state.player.name
        return n.isEmpty ? "there" : n
    }
}

// MARK: Net worth

/// The one slim hero card: the figure, what it did this week and in 30 days, a thin chart, the period picker, and the three boxes it is made of.
struct NetWorthCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var days = 365

    var body: some View {
        let nw = engine.netWorth
        let hist = engine.dayHistory
        let week = DayHistory.change(hist.netWorth, days: 7)
        let month = DayHistory.change(hist.netWorth, days: 30)
        let owed = nw.debt + nw.pendingTax
        Card(padding: 0, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Net worth").font(.system(size: 10.5, weight: .semibold)).tracking(1.4).textCase(.uppercase).foregroundStyle(Theme.gold)
                    Spacer()
                    PeriodPicker(days: $days)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(store.money(nw.total))
                        .font(.hero(34)).foregroundStyle(nw.total < 0 ? Theme.loss : Theme.ivory)
                        .minimumScaleFactor(0.55).lineLimit(1)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 0) {
                        changeText(week, "week")
                        changeText(month, "30 days")
                    }
                    .font(.system(size: 11.5).monospacedDigit()).lineSpacing(1)
                }
                NetWorthChart(engine: engine, days: days, height: 30)
                HStack(spacing: 0) {
                    box("Private", store.short(nw.personal), Theme.ivory)
                    Rectangle().fill(Theme.divider).frame(width: 1)
                    box("Companies", store.short(nw.companies), Theme.ivory)
                    Rectangle().fill(Theme.divider).frame(width: 1)
                    box("Owed", owed > 0.5 ? "−" + store.short(owed) : store.short(0), owed > 0.5 ? Theme.loss : Theme.ivory)
                }
                .padding(.top, 7).overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 10)
        }
        .accessibilityElement(children: .contain)
    }

    private func box(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 0) {
            Text(label).font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
            Text(value).font(.system(size: 13.5, weight: .medium).monospacedDigit()).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity)
    }

    @ViewBuilder private func changeText(_ c: (amount: Double, share: Double?)?, _ unit: String) -> some View {
        if let c {
            HStack(spacing: 3) {
                Text((c.amount > 0.5 ? "▲ " : c.amount < -0.5 ? "▼ " : "") + store.short(abs(c.amount))).foregroundStyle(Theme.change(c.amount))
                Text(unit).foregroundStyle(Theme.ivoryMuted)
            }
        } else {
            Text("–  " + unit).foregroundStyle(Theme.ivoryFaint)
        }
    }
}

/// 1W 1M 3M 1Y All, as text with an underline.
struct PeriodPicker: View {
    @Binding var days: Int
    static let periods: [(label: String, days: Int)] = [("1W", 8), ("1M", 31), ("3M", 92), ("1Y", 365), ("All", 3650)]
    var body: some View {
        HStack(spacing: 10) {
            ForEach(Self.periods, id: \.days) { p in
                Button { days = p.days; Haptics.choose() } label: {
                    Text(p.label).font(.system(size: 11)).foregroundStyle(days == p.days ? Theme.ivory : Theme.ivoryFaint)
                        .padding(.vertical, 3)
                        .overlay(alignment: .bottom) { if days == p.days { Rectangle().fill(Theme.gold).frame(height: 1) } }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }
}

// MARK: Four boxes

/// Bank, Hire, Reports, Market: each opens the matching Phone app or flow.
struct HomeQuickBoxes: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        let badges = store.phoneBadges
        HStack(spacing: 6) {
            box("Bank", Glyph.bank, badge: badges[.bank] ?? 0) { store.openApp(.bank) }
            box("Hire", Glyph.hire) { store.openHiring() }
            box("Reports", Glyph.reports) { store.openApp(.reports) }
            box("Market", Glyph.market) { store.openMarket() }
        }
    }

    private func box(_ title: String, _ glyph: String, badge: Int = 0, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        return Button { Haptics.tap(); action() } label: {
            VStack(spacing: 4) {
                GlyphView(glyph: glyph, size: 17, weight: 1.7)
                Text(title).font(.system(size: 11)).foregroundStyle(Theme.ivory)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(shape.fill(Theme.surface))
            .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
            .overlay(alignment: .topTrailing) { RedBubble(count: badge, size: .small).offset(x: 4, y: -5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("home-" + title.lowercased())
    }
}

extension GameStore {
    /// Hire: the Team section of the first company with an open post (posts that are needed now first), else the Team tab.
    func openHiring() {
        let posts = (engine?.teamOverview().vacancies ?? []).filter { $0.companyID != nil && $0.scope != "chain" }
        if let id = (posts.first(where: { $0.needed }) ?? posts.first)?.companyID {
            routeRequest = RouteRequest(tab: .team, route: .companyAt(id, .staff))
        }
        jump(to: .team)
    }

    /// Market: Group > Market, reviews and rivals when a company is open (that page exists then), else the World app.
    func openMarket() {
        let hasOpen = engine?.state.companies.contains { $0.type != "hold" && $0.status == .open } ?? false
        if hasOpen {
            routeRequest = RouteRequest(tab: .group, route: .market)
            jump(to: .group)
        } else {
            openApp(.world)
        }
    }
}

// MARK: Profit and due

/// Profit this month and what falls due in 30 days (covered or short). Both open the Bank app.
struct HomeMoneyCards: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        let o = engine.financeOverview(companyID: nil)
        let short = o.shortfall > 0
        let profitTint: Color = o.monthProfit < -0.5 ? Theme.loss : o.monthProfit > 0.5 ? Theme.gain : Theme.ivory
        HStack(spacing: 8) {
            card("Profit this month", signed(o.monthProfit), profitTint, "year so far " + signed(o.yearProfit), Theme.ivoryFaint, id: "home-profit")
            card("Due in 30 days", store.short(o.dueWithin30Days), short ? Theme.loss : Theme.ivory,
                 short ? "✗ short by " + store.short(o.shortfall) : (o.dueWithin30Days > 0.5 ? "✓ covered by " + store.short(o.cashAvailable) : "nothing due"),
                 short ? Theme.loss : (o.dueWithin30Days > 0.5 ? Theme.gain : Theme.ivoryFaint), id: "home-due")
        }
    }

    private func card(_ label: String, _ value: String, _ tint: Color, _ sub: String, _ subTint: Color, id: String) -> some View {
        Button { Haptics.tap(); store.openApp(.bank) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                Text(value).font(.system(size: 19, weight: .medium).monospacedDigit()).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
                Text(sub).font(.system(size: 11)).foregroundStyle(subTint).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityHint("Opens the Bank")
    }

    private func signed(_ v: Double) -> String { abs(v) < 0.5 ? store.short(0) : (v > 0 ? "+" : "−") + store.short(abs(v)) }
}

// MARK: Needs you

/// What needs the player, worst first: compact one-line rows from the engine's suggestions, each with its own action.
struct NeedsYouCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        let list = engine.suggestions(limit: 6)
        let shown = Array(list.prefix(3))
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(list.isEmpty ? "All clear" : "Needs you · \(list.count)")
                        .font(.system(size: 10.5, weight: .semibold)).tracking(1.2).textCase(.uppercase).foregroundStyle(Theme.gold)
                    Spacer()
                    Button { Haptics.tap(); store.openApp(.inbox) } label: {
                        Text("Open Inbox ›").font(.system(size: 11.5)).foregroundStyle(Theme.gold).frame(minHeight: 24).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("home-open-inbox")
                }
                .padding(.bottom, 3)
                if list.isEmpty {
                    Text("Nothing needs you right now.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).padding(.vertical, 6)
                }
                ForEach(shown) { item in
                    Rectangle().fill(Theme.divider).frame(height: 1)
                    row(item)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    private func row(_ item: Suggestion) -> some View {
        Button { store.go(item.action) } label: {
            HStack(spacing: 8) {
                GlyphView(glyph: Glyph.warning, size: 14, weight: 1.9, tint: tint(item.tone))
                Text(item.title.tidyMoney).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(item.actionLabel + " ›").font(.system(size: 11.5)).foregroundStyle(Theme.gold).lineLimit(1).fixedSize()
            }
            .padding(.vertical, 6).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier({ if case .openCompany = item.action { return "suggestion-open-company" } else { return "suggestion-row" } }())
    }

    private func tint(_ t: Suggestion.Tone) -> Color {
        switch t { case .bad: return Theme.loss; case .warn: return Theme.caution; case .good: return Theme.gain; case .neutral: return Theme.gold }
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
            Button { store.nextDay() } label: {
                Text(engine.state.isGameOver ? "Game over" : "Next day  ›")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(red: 0.09, green: 0.075, blue: 0.055))
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 24).frame(height: 44)
                    .background(Capsule().fill(Theme.gold))
            }
            .buttonStyle(.plain)
            .disabled(engine.state.isGameOver)
        }
        .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 4)
        .background(LinearGradient(colors: [Theme.page.opacity(0), Theme.page.opacity(0.94), Theme.page], startPoint: .top, endPoint: .center))
    }
}
