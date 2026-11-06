import SwiftUI
import Simulation
import Finance
import Businesses

/// The Home tab (route name `.company`) as one scrolling page: date and name, the net worth hero, what needs the owner right under it,
/// the companies (passed in by CompaniesView), then rank and shortcuts. Report sheets and reward popups appear on top of it.
struct HomeSummary<Companies: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    var engine: GameEngine
    var onNewCompany: () -> Void
    @ViewBuilder var companies: () -> Companies
    @State private var showInsights = false

    var body: some View {
        let e = engine
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                // The streak lives once on the page, in the rank row with the daily mission.
                HomeHeader(name: playerName, dateText: "\(e.homeCountry.flag) Week \(e.state.week + 1) · \(e.date)", streak: 0, onNewCompany: onNewCompany)
                if e.cashIsTight { cashTightBanner }
                if ent.plusEndedNotice {
                    Text("Plus has ended. Your saves are safe.").textStyle(.caption)
                        .accessibilityIdentifier("plus-ended-line")
                }
            }
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: Theme.Space.xl) {
                    NetWorthCard(engine: e).frame(maxWidth: .infinity)
                    TopPriorities(engine: e).frame(maxWidth: .infinity)
                }
            } else {
                NetWorthCard(engine: e)
                TopPriorities(engine: e)
            }
            companies()
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Hairline()
                HomeRankStrip(engine: e) { showInsights = true }
                HomeShortcutRow()
            }
        }
        .centerSheet(isPresented: $showInsights, title: "Insights", size: .tall) { InsightsView(engine: e) }
    }

    private var playerName: String {
        let n = engine.state.player.name
        return n.isEmpty ? "there" : n
    }

    /// New-player start: a bill the account cannot cover yet waits one day; nothing else happens.
    private var cashTightBanner: some View {
        Text("Cash is tight. A bill waits until tomorrow.")
            .textStyle(.body, tint: Theme.accentInk, weight: .medium)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.warn))
            .accessibilityIdentifier("cash-tight-banner")
    }
}

// MARK: Net worth

/// The hero: the serif figure, what it did this week and in 30 days, a thin chart, the period picker, and the four figures it is made of.
struct NetWorthCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var days = 365
    @State private var snap: NetWorthSnap?

    /// What the chart and the two change texts showed before the day: kept while the daily report is waiting for its Continue.
    struct NetWorthSnap {
        var series: [Int: [Double]]
        var week: Double?
        var month: Double?
    }

    private func takeSnap() -> NetWorthSnap {
        var all: [Int: [Double]] = [:]
        for p in PeriodPicker.periods { all[p.days] = engine.netWorthSeries(days: p.days) }
        let hist = engine.dayHistory
        return NetWorthSnap(series: all, week: DayHistory.change(hist.netWorth, days: 7)?.amount, month: DayHistory.change(hist.netWorth, days: 30)?.amount)
    }

    var body: some View {
        let nw = engine.netWorth
        let hist = engine.dayHistory
        let blocked: Bool = store.holdsHomeFigures
        let held: NetWorthSnap? = blocked ? snap : nil
        let week: Double? = held != nil ? held?.week : DayHistory.change(hist.netWorth, days: 7)?.amount
        let month: Double? = held != nil ? held?.month : DayHistory.change(hist.netWorth, days: 30)?.amount
        let frozenSeries: [Double]? = held?.series[days]
        let owed = nw.debt + nw.pendingTax
        let wealth: NetWorthBreakdown = engine.netWorthBreakdown()
        let otherAssets: Double = wealth.investments + wealth.luxury + wealth.otherEstimatedHoldings
        Card(padding: Theme.Space.l, radius: Theme.Radius.large) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .center) {
                    Text("Net worth").textStyle(.label)
                    Spacer(minLength: Theme.Space.s)
                    PeriodPicker(days: $days)
                }
                HStack(alignment: .firstTextBaseline) {
                    HeldValue(live: nw.total) { (v: Double) in
                        Text(store.money(v))
                            .textStyle(.display, tint: v < 0 ? Theme.loss : Theme.ink)
                            .minimumScaleFactor(0.55).lineLimit(1)
                            .moneyFlash(v)
                    }
                    Spacer(minLength: Theme.Space.s)
                    VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                        changeText(week, "week")
                        changeText(month, "30 days")
                    }
                }
                NetWorthChart(engine: engine, days: days, height: 30, frozen: frozenSeries)
                Hairline()
                // Four across when they fit, else two by two (larger text, small phones).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        cashBox(wealth.liquid)
                        divider
                        investedBox(otherAssets)
                        divider
                        companiesBox(wealth.estimatedCompanyEquity)
                        divider
                        debtBox(owed)
                    }
                    VStack(spacing: Theme.Space.s) {
                        HStack(spacing: 0) {
                            cashBox(wealth.liquid)
                            divider
                            investedBox(otherAssets)
                        }
                        Hairline()
                        HStack(spacing: 0) {
                            companiesBox(wealth.estimatedCompanyEquity)
                            divider
                            debtBox(owed)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .onAppear { if snap == nil { snap = takeSnap() } }
        .onChange(of: nw.total) { _, _ in if !store.holdsHomeFigures { snap = takeSnap() } }
        .onChange(of: blocked) { _, now in if !now { snap = takeSnap() } }
    }

    private var divider: some View { Rectangle().fill(Theme.line).frame(width: 0.5) }
    private func cashBox(_ v: Double) -> some View { box("Personal cash", v) { store.short($0) } }
    private func investedBox(_ v: Double) -> some View { box("Invested", v) { store.short($0) } }
    private func companiesBox(_ v: Double) -> some View { box("Companies", v) { store.short($0) } }
    private func debtBox(_ v: Double) -> some View { box("Debt", v, loss: true) { $0 > 0.5 ? "−" + store.short($0) : store.short(0) } }

    private func box(_ label: String, _ live: Double, loss: Bool = false, _ text: @escaping (Double) -> String) -> some View {
        VStack(spacing: Theme.Space.xxs) {
            Text(label).textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
            HeldValue(live: loss ? -live : live) { (v: Double) in
                let amount: Double = loss ? -v : v
                Text(text(amount)).textStyle(.headline, tint: loss && amount > 0.5 ? Theme.loss : Theme.ink, numeric: true)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .moneyFlash(v)
            }
        }
        .padding(.horizontal, Theme.Space.xs)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func changeText(_ c: Double?, _ unit: String) -> some View {
        if let c {
            HStack(spacing: Theme.Space.xs) {
                Text((c > 0.5 ? "▲ " : c < -0.5 ? "▼ " : "") + store.short(abs(c))).textStyle(.caption, tint: Theme.change(c), numeric: true)
                Text(unit).textStyle(.caption)
            }
        } else {
            Text("–  " + unit).textStyle(.caption, tint: Theme.inkFaint)
        }
    }
}

/// 1W 1M 3M 1Y All, as text with an underline under the chosen one; each label has a 44 pt hit area.
struct PeriodPicker: View {
    @Binding var days: Int
    static let periods: [(label: String, days: Int)] = [("1W", 8), ("1M", 31), ("3M", 92), ("1Y", 365), ("All", 3650)]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.periods, id: \.days) { p in
                Button { days = p.days; Haptics.choose() } label: {
                    Text(p.label).textStyle(.caption, tint: days == p.days ? Theme.ink : Theme.inkFaint, weight: days == p.days ? .semibold : nil)
                        .padding(.vertical, Theme.Space.xxs)
                        .overlay(alignment: .bottom) { if days == p.days { Rectangle().fill(Theme.accent).frame(height: 1) } }
                        .frame(minWidth: 36, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(days == p.days ? .isSelected : [])
            }
        }
        .padding(.vertical, -Theme.Space.s)
    }
}

// MARK: Shortcut boxes

/// The player's shortcuts (up to four, chosen with Edit or a long press). Each opens the matching Phone app or flow.
struct HomeShortcutRow: View {
    @EnvironmentObject var store: GameStore
    @State private var editing = false

    var body: some View {
        let badges = store.phoneBadges
        LedgerSection(title: "Shortcuts", rule: false, trailing: {
            Button("Edit") { Haptics.tap(); editing = true }
                .buttonStyle(TertiaryButtonStyle(size: .compact))
                .accessibilityIdentifier("edit-home-shortcuts")
        }) {
            HStack(spacing: Theme.Space.s) {
                ForEach(store.homeShortcuts) { item in
                    box(item, badge: item.badgeApp.map { badges[$0] ?? 0 } ?? 0)
                }
            }
            .contextMenu { Button("Edit shortcuts") { editing = true } }
        }
        .centerSheet(isPresented: $editing) { HomeShortcutEditor() }
    }

    private func box(_ item: HomeShortcut, badge: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        return Button { Haptics.tap(); item.open(store) } label: {
            VStack(spacing: Theme.Space.xs) {
                LedgerGlyph(glyph: item.glyph, size: Theme.Icon.medium)
                Text(item.title).textStyle(.caption, tint: Theme.ink).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 56).padding(.vertical, Theme.Space.xs)
            .background(shape.fill(Theme.surface))
            .overlay(alignment: .topTrailing) { RedBubble(count: badge, size: .small).offset(x: Theme.Space.xs, y: -Theme.Space.xs) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(item.title)
        .accessibilityIdentifier("home-" + item.rawValue)
        .accessibilityAction(named: "Edit shortcuts") { editing = true }
    }
}

extension GameStore {
    /// Hire: the Team section of the first company with an open post (posts that are needed now first), else the Group tab (its entity pages hold the vacancies under Management).
    func openHiring() {
        let posts = (engine?.teamOverview().vacancies ?? []).filter { $0.companyID != nil && $0.scope != "chain" }
        if let id = (posts.first(where: { $0.needed }) ?? posts.first)?.companyID {
            open(.companyAt(id, .staff), on: .company)
        } else {
            jump(to: .group)
        }
    }
}

// MARK: Top priorities

/// "Needs you", right under net worth: what needs the owner, worst first, at most three rows, each opening the exact object (a decision
/// opens in a popup right here, answered with one more tap); the rest wait in the Inbox. Decisions a manager already handled never
/// reach this list (the engine settles them), and neutral information (a tax estimate, idle cash) is not a priority.
struct TopPriorities: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var engine: GameEngine
    var limit: Int = 3

    var body: some View {
        let list: [Suggestion] = engine.suggestions(limit: 8).filter { $0.tone != .neutral }
        let shown: [Suggestion] = Array(list.prefix(limit))
        let waiting: Int = store.openDecisionCount
        LedgerSection(title: "Needs you", rule: false, trailing: { inboxLink(waiting) }) {
            if shown.isEmpty && waiting > 0 {
                LedgerRow(leading: .glyph(Glyph.inbox), title: waiting == 1 ? "1 decision waiting" : "\(waiting) decisions waiting",
                          subtitle: "Answer in the Inbox", action: { store.openApp(.inbox) })
            } else if shown.isEmpty {
                EmptyState(glyph: Glyph.check, title: "Nothing needs you right now", message: "Play the next day when you are ready.", centered: false)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { (i: Int, item: Suggestion) in
                        if i > 0 { Hairline() }
                        row(item).transition(.opacity)
                    }
                }
                .animation(Motion.quick(reduceMotion), value: shown.map { (s: Suggestion) -> String in s.id })
            }
        }
    }

    /// "Inbox · 3 ›": every open decision, with the count, beside the section title.
    @ViewBuilder private func inboxLink(_ waiting: Int) -> some View {
        if waiting > 0 {
            Button { Haptics.tap(); store.openApp(.inbox) } label: { Text("Inbox · \(waiting) ›") }
                .buttonStyle(TertiaryButtonStyle(size: .compact))
                .accessibilityLabel("Open the Inbox, \(waiting) waiting")
                .accessibilityIdentifier("home-open-inbox")
                .pulseOnce(when: waiting)
        }
    }

    private func row(_ item: Suggestion) -> some View {
        Button { store.go(popup: item.action) } label: {
            HStack(spacing: Theme.Space.m) {
                Circle().fill(tint(item.tone)).frame(width: Theme.Space.s, height: Theme.Space.s).accessibilityHidden(true)
                Text(item.title.tidyMoney).textStyle(.body).lineLimit(2).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(item.actionLabel).textStyle(.caption, tint: Theme.accent, weight: .medium).lineLimit(1).fixedSize()
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
            }
            .padding(.vertical, Theme.Space.s).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier({ if case .openCompany = item.action { return "suggestion-open-company" } else { return "suggestion-row" } }())
    }

    private func tint(_ t: Suggestion.Tone) -> Color {
        switch t { case .bad: return Theme.loss; case .warn: return Theme.warn; case .good: return Theme.gain; case .neutral: return Theme.accent }
    }
}

// MARK: Next day

/// The one filled control on the screen: the champagne Next day button at the right; at the left the week's progress (seven segments)
/// with what the last day did to net worth, and "Play to end of week" under it. While a day runs the button shows progress and ignores taps.
struct AdvanceBar: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var engine: GameEngine
    @Environment(Entitlements.self) private var ent
    @State private var pulseDim = false

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                caption
                HStack(spacing: Theme.Space.xs) {
                    ForEach(0..<7, id: \.self) { d in
                        Capsule().fill(d <= engine.state.day ? Theme.accent : Theme.line).frame(width: 22, height: 3)
                    }
                }
                .accessibilityHidden(true)
                .animation(Motion.quick(reduceMotion), value: engine.state.day)
                weekButton
            }
            Spacer(minLength: Theme.Space.s)
            nextButton
        }
        .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.xs)
        .background(Theme.page)
        .overlay(alignment: .top) { Hairline() }
    }

    /// "Day 3 of 7", and after a day the real change in net worth (an arrow and the amount). The line keeps its height, so nothing jumps.
    private var caption: some View {
        HStack(spacing: Theme.Space.s) {
            Text("Day \(engine.state.day + 1) of 7").textStyle(.caption, tint: Theme.inkFaint)
            if let chip = store.dayChip {
                let c: Double = chip.netWorthChange
                Text((c > 0.5 ? "▲ " : c < -0.5 ? "▼ " : "") + store.short(abs(c)) + " net worth")
                    .textStyle(.caption, tint: Theme.change(c), numeric: true, weight: .medium)
                    .id(chip.id)
                    .transition(.opacity)
            }
        }
        .lineLimit(1)
        .animation(Motion.quick(reduceMotion), value: store.dayChip?.id)
        .accessibilityElement(children: .combine)
    }

    /// Week 1, day 1 of a game with the ladder: nothing has been played yet.
    private var firstDay: Bool { engine.state.week == 0 && engine.state.day == 0 && Gates.ladderOn(engine.state) }

    /// A free player in weeks 9 to 12 gets one quiet line: the fast-forward becomes a Pro feature after week 12.
    private var proTeaser: Bool {
        let w: Int = engine.state.week + 1
        return !ent.isPro && w >= 9 && w <= 12
    }

    /// "Play to end of week": a text button under the week's progress from week 2; off while a blocking Inbox item is open.
    @ViewBuilder private var weekButton: some View {
        if store.canPlayWeek {
            Button { if ent.effective.canPlayToEndOfWeek(week: engine.state.week + 1, now: Date()) { store.playToEndOfWeek() } else { ent.run(.playToEndOfWeek, "Play to end of week") {} } } label: {
                HStack(spacing: Theme.Space.s) {
                    Text(proTeaser ? "Play to end of week · Pro after week 12" : "Play to end of week")
                        .textStyle(.caption, tint: Theme.inkSoft, weight: .medium).lineLimit(1).minimumScaleFactor(0.85)
                    if !engine.state.isGameOver && !ent.effective.canPlayToEndOfWeek(week: engine.state.week + 1, now: Date()) { ProMark(feature: .playToEndOfWeek) }
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .padding(.vertical, -Theme.Space.s)
            .disabled(store.isAdvancing || store.blockingMessageID != nil || store.reportSheet != nil)
            .accessibilityIdentifier("play-week")
        }
    }

    private var nextButton: some View {
        let busy: Bool = store.isAdvancing
        let over: Bool = engine.state.isGameOver
        let blockID: Int? = store.blockingMessageID
        let label: String = over ? "Game over" : busy ? "Running" : blockID != nil ? "Answer first  ›" : "Next day  ›"
        return Button {
            if let id = blockID { store.openApp(.inbox, request: .message(id)) } else { store.nextDay() }
        } label: {
            HStack(spacing: Theme.Space.s) {
                if busy { ProgressView().controlSize(.small).tint(Theme.inkSoft) }
                Text(label)
            }
            .fixedSize()
        }
        .buttonStyle(PrimaryButtonStyle())
        .opacity(firstDay && pulseDim ? 0.6 : 1)
        .onAppear {
            // Until the first day has been played the button breathes (opacity 1.0 to 0.6, 1.2 s a cycle).
            guard firstDay, !reduceMotion else { return }
            Motion.animate(Motion.pulseAnimation) { pulseDim = true }
        }
        .disabled(over || busy || (blockID == nil && store.reportSheet != nil))
        .accessibilityIdentifier("next-day")
    }
}
