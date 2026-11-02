import SwiftUI
import Simulation
import Finance
import Businesses

/// The top of the Home tab (route name `.company`), the compact command centre of "Home variation 1" (native/design/MOCKUP_DECISIONS.md):
/// date and name, the net worth hero with its four figures, the player's shortcut boxes, the top priorities (at most three, the rest
/// in the Inbox), then the companies list below (CompaniesView) and the Next day bar. Report sheets and reward popups appear on top of it.
struct HomeSummary: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var onNewCompany: () -> Void

    var body: some View {
        let e = engine
        VStack(alignment: .leading, spacing: 8) {
            HomeHeader(name: playerName, dateText: "\(e.homeCountry.flag) Week \(e.state.week + 1) · \(e.date)", onNewCompany: onNewCompany)
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: Theme.Space.l) {
                    NetWorthCard(engine: e)
                    VStack(spacing: 8) { HomeShortcutRow(); TopPriorities(engine: e) }
                }
            } else {
                NetWorthCard(engine: e)
                HomeShortcutRow()
                TopPriorities(engine: e)
            }
        }
    }

    private var playerName: String {
        let n = engine.state.player.name
        return n.isEmpty ? "there" : n
    }
}

// MARK: Net worth

/// The hero: the serif figure, what it did this week and in 30 days, a thin chart, the period picker, and the four figures it is made of.
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
        let wealth: NetWorthBreakdown = engine.netWorthBreakdown()
        let otherAssets: Double = wealth.investments + wealth.luxury + wealth.otherEstimatedHoldings
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
                    box("Personal cash", store.short(wealth.liquid), Theme.ivory)
                    Rectangle().fill(Theme.divider).frame(width: 1)
                    box("Invested", store.short(otherAssets), Theme.ivory)
                    Rectangle().fill(Theme.divider).frame(width: 1)
                    box("Companies", store.short(wealth.estimatedCompanyEquity), Theme.ivory)
                    Rectangle().fill(Theme.divider).frame(width: 1)
                    box("Debt", owed > 0.5 ? "−" + store.short(owed) : store.short(0), owed > 0.5 ? Theme.loss : Theme.ivory)
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
            Text(label).font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(1).minimumScaleFactor(0.8)
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
                }.buttonStyle(PressableStyle())
            }
        }
    }
}

// MARK: Shortcut boxes

/// The player's boxes (up to four, chosen with a long press or "Edit"). Each opens the matching Phone app or flow.
struct HomeShortcutRow: View {
    @EnvironmentObject var store: GameStore
    @State private var editing = false

    var body: some View {
        let badges = store.phoneBadges
        HStack(spacing: 6) {
            ForEach(store.homeShortcuts) { item in
                box(item, badge: item.badgeApp.map { badges[$0] ?? 0 } ?? 0)
            }
        }
        .contextMenu { Button("Edit shortcuts") { editing = true } }
        .sheet(isPresented: $editing) { HomeShortcutEditor() }
    }

    private func box(_ item: HomeShortcut, badge: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        return Button { Haptics.tap(); item.open(store) } label: {
            VStack(spacing: 4) {
                GlyphView(glyph: item.glyph, size: 17, weight: 1.7)
                Text(item.title).font(.system(size: 11)).foregroundStyle(Theme.ivory).lineLimit(1)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(shape.fill(Theme.surface))
            .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
            .overlay(alignment: .topTrailing) { RedBubble(count: badge, size: .small).offset(x: 4, y: -5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(item.title)
        .accessibilityIdentifier("home-" + item.rawValue)
        .accessibilityAction(named: "Edit shortcuts") { editing = true }
    }
}

extension GameStore {
    /// Hire: the Team section of the first company with an open post (posts that are needed now first), else the Team tab.
    func openHiring() {
        let posts = (engine?.teamOverview().vacancies ?? []).filter { $0.companyID != nil && $0.scope != "chain" }
        if let id = (posts.first(where: { $0.needed }) ?? posts.first)?.companyID {
            open(.companyAt(id, .staff), on: .team)
        } else {
            jump(to: .team)
        }
    }
}

// MARK: Top priorities

/// What needs the owner, worst first: at most three rows, each opening the exact object; the rest wait in the Inbox. Decisions that a
/// manager already handled never reach this list (the engine settles them), and neutral information (a tax estimate, idle cash) is
/// not a priority.
struct TopPriorities: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        let list: [Suggestion] = engine.suggestions(limit: 8).filter { $0.tone != .neutral }
        let shown: [Suggestion] = Array(list.prefix(3))
        let waiting: Int = store.openDecisionCount
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(shown.isEmpty ? "All clear" : "Top priorities")
                    .font(.system(size: 10.5, weight: .semibold)).tracking(1.2).textCase(.uppercase).foregroundStyle(Theme.gold)
                    .padding(.bottom, 3)
                if shown.isEmpty {
                    Text("Nothing needs you right now.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).padding(.vertical, 6)
                }
                ForEach(shown) { item in
                    Rectangle().fill(Theme.divider).frame(height: 1)
                    row(item)
                }
                if waiting > 0 {
                    Rectangle().fill(Theme.divider).frame(height: 1)
                    Button { Haptics.tap(); store.openApp(.inbox) } label: {
                        HStack {
                            Spacer()
                            Text("See all \(waiting) in Inbox ›").font(.system(size: 11.5)).foregroundStyle(Theme.gold)
                        }
                        .frame(minHeight: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle()).accessibilityIdentifier("home-open-inbox")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    private func row(_ item: Suggestion) -> some View {
        Button { store.go(popup: item.action) } label: {
            HStack(spacing: 8) {
                Circle().fill(tint(item.tone)).frame(width: 7, height: 7)
                Text(item.title.tidyMoney).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(item.actionLabel)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.gold).lineLimit(1).fixedSize()
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.6), lineWidth: 1))
            }
            .padding(.vertical, 6).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier({ if case .openCompany = item.action { return "suggestion-open-company" } else { return "suggestion-row" } }())
    }

    private func tint(_ t: Suggestion.Tone) -> Color {
        switch t { case .bad: return Theme.loss; case .warn: return Theme.caution; case .good: return Theme.gain; case .neutral: return Theme.gold }
    }
}

// MARK: Next day

/// The one filled control on the screen: a champagne pill at the bottom right, the week's progress (seven segments) at the left with
/// what the last day did to net worth. While a day runs the button shows progress and ignores taps.
struct AdvanceBar: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var engine: GameEngine

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 6) {
                caption
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { d in
                        Capsule().fill(d <= engine.state.day ? Theme.gold : Theme.hairline).frame(width: 22, height: 3)
                    }
                }
            }
            Spacer(minLength: 8)
            nextButton
        }
        .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 4)
        .background(LinearGradient(colors: [Theme.page.opacity(0), Theme.page.opacity(0.94), Theme.page], startPoint: .top, endPoint: .center))
    }

    /// "Day 3 of 7", and after a day the real change in net worth (an arrow and the amount). The line keeps its height, so nothing jumps.
    private var caption: some View {
        HStack(spacing: 6) {
            Text("Day \(engine.state.day + 1) of 7").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
            if let chip = store.dayChip {
                let c: Double = chip.netWorthChange
                Text((c > 0.5 ? "▲ " : c < -0.5 ? "▼ " : "") + store.short(abs(c)) + " net worth")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.change(c))
                    .id(chip.id)
                    .transition(.opacity)
            }
        }
        .frame(height: 14, alignment: .leading)
        .animation(Motion.standard(reduceMotion), value: store.dayChip?.id)
        .accessibilityElement(children: .combine)
    }

    private var nextButton: some View {
        let busy: Bool = store.isAdvancing
        let over: Bool = engine.state.isGameOver
        return Button { store.nextDay() } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().controlSize(.small).tint(Color(red: 0.09, green: 0.075, blue: 0.055)) }
                Text(over ? "Game over" : busy ? "Running" : "Next day  ›")
            }
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(red: 0.09, green: 0.075, blue: 0.055))
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 24).frame(height: 44)
            .background(Capsule().fill(Theme.gold))
            .opacity(busy ? 0.75 : 1)
        }
        .buttonStyle(PressableStyle())
        .disabled(over || busy || store.reportSheet != nil)
        .accessibilityIdentifier("next-day")
    }
}
