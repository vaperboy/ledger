import SwiftUI
import GameCore
import Simulation
import Finance
import Businesses

/// The Home tab (route name `.company`) as one calm screen that fits an iPhone without scrolling: the date, the owner and their rank,
/// the net worth hero (tap for Insights), the one thing that needs the owner, the top companies (passed in by CompaniesView). Next day
/// floats over the bottom right (`NextDayDock`). `compact` tightens the spacing for a shorter screen; `trim` drops the lower-priority
/// blocks one step at a time (1 milestone line, 2 insight strip, 3 balance row) so a short screen never needs a scroll.
struct HomeSummary<Companies: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    var engine: GameEngine
    var compact: Bool = false
    /// True when the page fills a fixed screen height: the free room is shared evenly between the groups instead of pooling at the end.
    var fills: Bool = false
    /// False drops the net worth line, for the shortest screens.
    var chart: Bool = true
    var trim: Int = 0
    var onNewCompany: () -> Void
    @ViewBuilder var companies: () -> Companies
    @State private var showInsights = false

    var body: some View {
        let e = engine
        VStack(alignment: .leading, spacing: compact ? Theme.Space.m : Theme.Space.l) {
            VStack(alignment: .leading, spacing: compact ? Theme.Space.s : Theme.Space.m) {
                HomeTopLine(name: playerName, dateText: "\(e.homeCountry.flag)  Week \(e.state.week + 1) · \(e.date)", engine: e, onNewCompany: onNewCompany)
                if e.cashIsTight { cashTightLine }
                if ent.plusEndedNotice {
                    Text("Plus has ended. Your saves are safe.").textStyle(.caption)
                        .accessibilityIdentifier("plus-ended-line")
                }
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: Theme.Space.xxl) {
                        NetWorthCard(engine: e, chartHeight: 64) { showInsights = true }.frame(maxWidth: .infinity)
                        TopPriorities(engine: e).frame(maxWidth: .infinity)
                    }
                } else {
                    NetWorthCard(engine: e, chartHeight: chart ? (compact ? 24 : 32) : 0, showBalances: trim < 3) { showInsights = true }
                    if trim < 1 { HomeMilestoneLine(engine: e) }
                }
            }
            if fills { Self.gap }
            if trim < 2 {
                HomeProgressStrip(engine: e)
                HomeLevelBar(engine: e)
                if trim < 1 { HomeMissionStrip(engine: e) }
                if fills { Self.gap }
            }
            if sizeClass != .regular { TopPriorities(engine: e, compact: compact).coachAnchor(.needsYou) }
            if fills { Self.gap }
            companies()
            if fills { Self.gap }
        }
        .centerSheet(isPresented: $showInsights, title: "Insights", size: .tall, category: .detail, tone: .info) { InsightsView(engine: e) }
    }

    /// Spare height between two groups: the free room is shared evenly by every gap and the one under the companies, so no single void forms.
    private static var gap: some View { Spacer(minLength: 0) }

    private var playerName: String {
        let n = engine.state.player.name
        return n.isEmpty ? "there" : n
    }

    /// New-player start: a bill the account cannot cover yet waits one day; nothing else happens.
    private var cashTightLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Circle().fill(Theme.warn).frame(width: 6, height: 6).accessibilityHidden(true)
            Text("Cash is tight. A bill waits until tomorrow.").textStyle(.caption, tint: Theme.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cash-tight-banner")
    }
}

struct HomeTopLine: View {
    @EnvironmentObject var store: GameStore
    var name: String
    var dateText: String
    var engine: GameEngine
    var onNewCompany: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            HomeProfileButton(engine: engine)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(dateText).textStyle(.label, tint: Theme.inkFaint).lineLimit(1).minimumScaleFactor(0.7)
                Text(name).textStyle(.title).lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: Theme.Space.xxs)
            HomeGoldChip()
            HomeRoundButton(glyph: Glyph.inbox, label: "Inbox", badge: store.appBadge(.inbox), identifier: "home-inbox") { store.openApp(.inbox) }
                .coachAnchor(.phoneInbox)
            HomeRoundButton(glyph: PhoneApp.apps.glyph, label: "Apps", badge: store.appsBadge, identifier: "home-apps") { store.openApp(.apps) }
            HomeRoundButton(glyph: Glyph.hire, label: "New company", identifier: "home-new-company", action: onNewCompany)
        }
    }
}

// MARK: Net worth

/// The hero: the label (with the way to Insights at the right), the big serif figure, what it did this week and in 30 days, and a thin
/// line of the last year, with no box around it. The whole block opens Insights.
struct NetWorthCard: View {
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    var engine: GameEngine
    var chartHeight: CGFloat = 40
    /// False drops the personal account and past-value columns, for the shortest screens.
    var showBalances: Bool = true
    var onInsights: () -> Void
    @State private var snap: NetWorthSnap?
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 42
    private static let days = 365

    /// What the chart and the two change texts showed before the day: kept while the daily report is waiting for its Continue.
    struct NetWorthSnap {
        var series: [Double]
        var week: Double?
        var month: Double?
        /// Net worth a week and a month ago (nil until that much history exists).
        var weekAgo: Double?
        var monthAgo: Double?
    }

    private func takeSnap() -> NetWorthSnap {
        let hist = store.dayHistoryNow ?? engine.dayHistory
        return NetWorthSnap(series: store.netWorthSeriesNow(days: Self.days), week: DayHistory.change(hist.netWorth, days: 7)?.amount,
                            month: DayHistory.change(hist.netWorth, days: 30)?.amount,
                            weekAgo: Self.past(hist.netWorth, days: 7), monthAgo: Self.past(hist.netWorth, days: 30))
    }

    /// The value `days` entries before the latest one (or the oldest); nil with fewer than two entries.
    private static func past(_ series: [Double], days: Int) -> Double? {
        guard series.count >= 2 else { return nil }
        return series[max(0, series.count - 1 - days)]
    }

    var body: some View {
        let nw = store.netWorthNow ?? engine.netWorth
        let hist = store.dayHistoryNow ?? engine.dayHistory
        let blocked: Bool = store.holdsHomeFigures
        let held: NetWorthSnap? = blocked ? snap : nil
        let week: Double? = held != nil ? held?.week : DayHistory.change(hist.netWorth, days: 7)?.amount
        let month: Double? = held != nil ? held?.month : DayHistory.change(hist.netWorth, days: 30)?.amount
        let series: [Double] = held?.series ?? store.netWorthSeriesNow(days: Self.days)
        let weekAgo: Double? = held != nil ? held?.weekAgo : Self.past(hist.netWorth, days: 7)
        let monthAgo: Double? = held != nil ? held?.monthAgo : Self.past(hist.netWorth, days: 30)
        Button { Haptics.tap(); onInsights() } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text("Net worth").textStyle(.label, tint: Theme.inkFaint)
                    Spacer(minLength: Theme.Space.s)
                    HStack(spacing: Theme.Space.xxs) {
                        if !ent.isPro { LedgerGlyph(glyph: Glyph.lock, size: 12, tint: Theme.inkFaint) }
                        Text("Insights").textStyle(.caption, tint: Theme.inkSoft)
                        LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
                    }
                }
                HeldValue(live: nw.total) { (v: Double) in
                    RollingMoney(value: v) { (x: Double) -> String in store.money(x) }
                        .font(.hero(heroSize))
                        .foregroundStyle(v < 0 ? Theme.loss : Theme.ink)
                        .minimumScaleFactor(0.8).lineLimit(2)
                }
                changeLine(today: store.dayChip?.profit, week: week, month: month)
                if showBalances { balanceRow(personal: nw.personal, total: nw.total, weekAgo: weekAgo, monthAgo: monthAgo) }
                if series.count >= 2 && chartHeight > 0 {
                    // Scaled to the series' own range, so a year's real shape shows instead of a flat line on a band.
                    let rising: Bool = (series.last ?? 0) >= (series.first ?? 0)
                    // Drawn left to right once; each new day only extends the line (see LiveSparkline).
                    LiveSparkline(values: series, tint: rising ? Theme.gain : Theme.loss, filled: true)
                        .frame(height: chartHeight)
                        .drawsItself()
                        .accessibilityHidden(true)
                        .padding(.top, Theme.Space.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(ent.isPro ? "Opens Insights" : "Opens Insights, part of Ledger Pro")
        .accessibilityIdentifier("home-insights")
        .coachAnchor(.happened)
        .onAppear { if snap == nil { snap = takeSnap() } }
        .onChange(of: nw.total) { _, _ in if !store.holdsHomeFigures { snap = takeSnap() } }
        .onChange(of: blocked) { _, now in if !now { snap = takeSnap() } }
    }

    /// "▲ 1.2k profit today · ▲ 12.3k this week" (30 days instead of today until a day has been played), on one line or two.
    @ViewBuilder private func changeLine(today: Double?, week: Double?, month: Double?) -> some View {
        let first: (Double?, String) = today != nil ? (today, "profit today") : (month, "in 30 days")
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.s) {
                changeText(first.0, first.1)
                Text("·").textStyle(.caption, tint: Theme.inkFaint)
                changeText(week, "this week")
            }
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                changeText(first.0, first.1)
                changeText(week, "this week")
            }
        }
        .accessibilityIdentifier("home-today")
    }

    /// Three columns under the figure: the personal account (cash and savings) and net worth a week and a month ago, each past one with its change.
    private func balanceRow(personal: Double, total: Double, weekAgo: Double?, monthAgo: Double?) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("Personal account").textStyle(.caption, tint: Theme.inkFaint).lineLimit(1).minimumScaleFactor(0.8)
                HeldValue(live: personal) { (v: Double) in
                    RollingMoney(value: v) { (x: Double) -> String in store.short(x) }
                        .textStyle(.body, tint: v < 0 ? Theme.loss : Theme.ink, numeric: true, weight: .medium).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            pastColumn("A week ago", then: weekAgo, now: total)
            pastColumn("A month ago", then: monthAgo, now: total)
        }
        .padding(.top, Theme.Space.xxs)
        .accessibilityIdentifier("home-balances")
    }

    private func pastColumn(_ title: String, then: Double?, now: Double) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(title).textStyle(.caption, tint: Theme.inkFaint).lineLimit(1).minimumScaleFactor(0.8)
            if let then {
                let d: Double = now - then
                Text(store.short(then)).textStyle(.body, numeric: true, weight: .medium).lineLimit(1)
                // Nothing under the figure when it has not moved (a "0 kr" line reads like a bug).
                if abs(d) > 0.5 {
                    Text((d > 0 ? "▲ " : "▼ ") + store.short(abs(d))).textStyle(.caption, tint: Theme.change(d), numeric: true).lineLimit(1)
                }
            } else {
                Text("–").textStyle(.body, tint: Theme.inkFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func changeText(_ c: Double?, _ unit: String) -> some View {
        if let c {
            HStack(spacing: Theme.Space.xs) {
                ArrowAmount(gain: c, format: { (v: Double) -> String in store.short(v) }, live: true, roll: true, step: .body, weight: .medium)
                Text(unit).textStyle(.body, tint: Theme.inkSoft)
            }
            .lineLimit(1)
        } else {
            Text("No change yet " + unit).textStyle(.body, tint: Theme.inkFaint).lineLimit(1)
        }
    }
}

/// A group label in small caps (faint ink) with an optional action on the right; no rule, no box.
struct HomeGroupLabel<Trailing: View>: View {
    var title: String
    /// Set: the label is a button (with a small chevron) that runs this.
    var onTap: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            if let onTap {
                Button { Haptics.tap(); onTap() } label: {
                    HStack(spacing: Theme.Space.xxs) {
                        Text(title).textStyle(.label, tint: Theme.inkFaint).lineLimit(1)
                        LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
                    }
                    .frame(minHeight: 28).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityHint("Lists every goal you are working on")
                .accessibilityIdentifier("home-goals-label")
            } else {
                Text(title).textStyle(.label, tint: Theme.inkFaint).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            trailing()
        }
        .frame(minHeight: 28)
    }
}

extension HomeGroupLabel where Trailing == EmptyView {
    init(_ title: String) { self.init(title: title, trailing: { EmptyView() }) }
}

extension GameStore {
    /// Hire: the Team section of the first company with an open post (posts that are needed now first), else the Team of the first live company,
    /// pushed on the open tab.
    func openHiring() {
        let posts = (engine?.teamOverview().vacancies ?? []).filter { $0.companyID != nil && $0.scope != "chain" }
        if let id = (posts.first(where: { $0.needed }) ?? posts.first)?.companyID {
            push(.companyAt(id, .staff))
        } else if let id = engine?.state.companies.first(where: { $0.status.isLive && $0.type != "hold" })?.id {
            push(.companyAt(id, .staff))
        }
    }
}

// MARK: Needs you

/// "Needs you", right under net worth: the one most important thing as a raised card (what it is, why, and the action); the rest wait
/// in the Inbox ("Inbox · 3" beside the label). It opens the exact object (a decision opens in a popup right here). Decisions a manager
/// already handled never reach this list (the engine settles them), and neutral information is not a priority.
struct TopPriorities: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var engine: GameEngine
    var compact: Bool = false

    @State private var daily: PlayerGoals.DailyGoal?

    /// With nothing to answer, the player's next goal fills the slot: the ladder goal, else today's goal while it is open.
    private struct Goal {
        var title: String
        var line: String
        var action: String
        var link: String
    }

    private var goal: Goal? {
        if let g = PlayerGoals.currentLadderGoal(engine.state) {
            return Goal(title: g.title, line: g.body, action: g.button, link: g.link)
        }
        if let d = daily, !d.done {
            return Goal(title: d.title, line: d.progress, action: d.link.isEmpty ? "" : "Go", link: d.link)
        }
        return nil
    }

    var body: some View {
        let first: Suggestion? = store.suggestionsNow.first { $0.tone != .neutral }
        let waiting: Int = store.openDecisionCount
        let offerAmbition: Bool = first == nil && waiting == 0 && engine.ambitionCardPending
        let next: Goal? = first == nil && waiting == 0 && !offerAmbition ? goal : nil
        let tick: Int = engine.state.week * 7 + engine.state.day
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HomeGroupLabel(title: next != nil || offerAmbition ? "Your next goal" : "Needs you",
                           onTap: next != nil || offerAmbition ? { store.openGoals() } : nil) { inboxLink(waiting) }
            if let first {
                lead(first)
                    .id(first.id)
                    .transition(.opacity)
            } else if waiting > 0 {
                waitingCard(waiting)
            } else if offerAmbition {
                AmbitionCard(compact: compact)
            } else if let next {
                goalCard(next)
            } else {
                HStack(spacing: Theme.Space.s) {
                    LedgerGlyph(glyph: Glyph.check, size: Theme.Icon.small, tint: Theme.inkFaint)
                    Text("Nothing needs you right now.").textStyle(.body, tint: Theme.inkSoft)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            }
        }
        .animation(Motion.quick(reduceMotion), value: first?.id)
        .centerSheet(isPresented: $store.showGoals, title: "Your goals", category: .detail, tone: .info) {
            GoalsPopup(engine: engine, daily: daily, close: { store.showGoals = false }).environmentObject(store)
        }
        .onAppear { daily = store.dailyGoal() }
        .onChange(of: tick) { _, _ in daily = store.dailyGoal() }
    }

    /// The goal as a raised card: title, one line of how, and the action that opens where it is done (none when it has no screen).
    private func goalCard(_ g: Goal) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        let opens: Bool = !g.link.isEmpty && !g.action.isEmpty
        let card = HStack(alignment: .center, spacing: Theme.Space.m) {
            LedgerGlyph(glyph: Glyph.goals, size: Theme.Icon.medium, tint: Theme.inkSoft)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(g.title.tidyMoney).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
                if !g.line.isEmpty {
                    Text(g.line.tidyMoney).textStyle(.caption).lineLimit(compact ? 1 : 2).multilineTextAlignment(.leading)
                }
                if opens {
                    Text(g.action).textStyle(.body, tint: Theme.accent, weight: .semibold).lineLimit(1)
                        .padding(.top, Theme.Space.xxs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if opens { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, compact ? Theme.Space.m : Theme.Space.l).padding(.horizontal, Theme.Space.l)
        .glassSurface(raised: true)
        .contentShape(shape)
        return Button {
            guard opens else { return }
            Haptics.tap()
            if g.link == "goals" { store.openGoals() } else { _ = store.openLadderLink(g.link) }
        } label: { card }
        .buttonStyle(PressableStyle())
        .disabled(!opens)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home-goal")
    }

    /// "Inbox · 3": every open decision, with the count, beside the label.
    @ViewBuilder private func inboxLink(_ waiting: Int) -> some View {
        if waiting > 0 {
            Button { Haptics.tap(); store.openApp(.inbox) } label: { Text("Inbox · \(waiting)") }
                .buttonStyle(TertiaryButtonStyle(size: .compact))
                .accessibilityLabel("Open the Inbox, \(waiting) waiting")
                .accessibilityIdentifier("home-open-inbox")
                .pulseOnce(when: waiting)
        }
    }

    private func identifier(_ item: Suggestion) -> String {
        if case .openCompany = item.action { return "suggestion-open-company" } else { return "suggestion-row" }
    }

    /// The open two-answer decision a card stands for, which Home answers in place; nil for every other card.
    private func inlineDecision(_ item: Suggestion) -> Message? {
        guard case .openMessage(let id) = item.action, let m = engine.state.inbox.first(where: { (x: Message) -> Bool in x.id == id }),
              HomeDecisionButtons.fits(engine, m) else { return nil }
        return m
    }

    /// The raised card: a tone mark, the title, one line of why, and the action in accent. A two-answer decision shows its answers as buttons.
    private func lead(_ item: Suggestion) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        let detail: String = item.detail.tidyMoney
        let inline: Message? = inlineDecision(item)
        let card = Button { Haptics.tap(); store.go(popup: item.action) } label: {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                Capsule().fill(tint(item.tone)).frame(width: 3).frame(maxHeight: .infinity).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(item.title.tidyMoney).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    if !detail.isEmpty && !compact {
                        Text(detail).textStyle(.caption).lineLimit(1)
                    }
                    if inline == nil {
                        Text(item.actionLabel).textStyle(.body, tint: Theme.accent, weight: .semibold).lineLimit(1)
                            .padding(.top, Theme.Space.xxs)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, compact ? Theme.Space.m : Theme.Space.l).padding(.horizontal, Theme.Space.l)
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier(item))
        return VStack(spacing: 0) {
            card
            if let inline {
                HomeDecisionButtons(engine: engine, message: inline)
                    .padding(.horizontal, Theme.Space.l).padding(.bottom, compact ? Theme.Space.m : Theme.Space.l)
            }
        }
        .glassSurface(raised: true)
        .contentShape(shape)
    }

    private func waitingCard(_ waiting: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        return Button { Haptics.tap(); store.openApp(.inbox) } label: {
            HStack(spacing: Theme.Space.m) {
                LedgerGlyph(glyph: Glyph.inbox, size: Theme.Icon.medium, tint: Theme.accent)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(waiting == 1 ? "1 decision waiting" : "\(waiting) decisions waiting").textStyle(.headline)
                    Text("Answer in the Inbox").textStyle(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
            }
            .padding(Theme.Space.l)
            .glassSurface(raised: true)
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("suggestion-row")
    }

    private func tint(_ t: Suggestion.Tone) -> Color {
        switch t { case .bad: return Theme.loss; case .warn: return Theme.warn; case .good: return Theme.gain; case .neutral: return Theme.inkFaint }
    }
}
