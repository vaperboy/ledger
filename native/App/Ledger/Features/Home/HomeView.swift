import SwiftUI
import Simulation
import Finance
import Businesses

/// The Home tab (route name `.company`) as one calm screen that fits an iPhone without scrolling: the date, the owner and their rank,
/// the net worth hero (tap for Insights), the one thing that needs the owner, the top companies (passed in by CompaniesView). Next day
/// is pinned under it (`AdvanceBar`). `compact` tightens the spacing for a shorter screen.
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
    var onNewCompany: () -> Void
    @ViewBuilder var companies: () -> Companies
    @State private var showInsights = false

    var body: some View {
        let e = engine
        VStack(alignment: .leading, spacing: compact ? Theme.Space.m : Theme.Space.l) {
            VStack(alignment: .leading, spacing: compact ? Theme.Space.s : Theme.Space.m) {
                HomeTopLine(name: playerName, dateText: "\(e.homeCountry.flag)  Week \(e.state.week + 1) · \(e.date)", engine: e, onNewCompany: onNewCompany)
                if fills { Spacer(minLength: 0).frame(maxHeight: Theme.Space.s) }
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
                    NetWorthCard(engine: e, chartHeight: chart ? (compact ? 24 : 32) : 0) { showInsights = true }
                    HomeMilestoneLine(engine: e)
                }
            }
            if fills { Self.gap }
            HomeProgressStrip(engine: e)
            if fills { Self.gap }
            if sizeClass != .regular { TopPriorities(engine: e, compact: compact) }
            if fills { Self.gap }
            companies()
            if fills { Spacer(minLength: 0) }
        }
        .centerSheet(isPresented: $showInsights, title: "Insights", size: .tall, category: .detail, tone: .info) { InsightsView(engine: e) }
    }

    /// Spare height between two groups, at most 16 pt over the stack's own spacing; whatever is left over gathers under the companies, above the day bar.
    private static var gap: some View { Spacer(minLength: 0).frame(maxHeight: Theme.Space.l) }

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

/// The page's top line: the date over the owner's name; at the right the rank button (opens Goals) and a round New company button.
struct HomeTopLine: View {
    var name: String
    var dateText: String
    var engine: GameEngine
    var onNewCompany: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(dateText).textStyle(.label, tint: Theme.inkFaint).lineLimit(1).minimumScaleFactor(0.8)
                Text(name).textStyle(.title).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Theme.Space.s)
            Button { Haptics.tap(); onNewCompany() } label: {
                LedgerGlyph(glyph: Glyph.hire, size: Theme.Icon.medium, tint: Theme.ink)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().strokeBorder(Theme.lineStrong, lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("New company")
        }
    }
}

// MARK: Net worth

/// The hero: the label (with the way to Insights at the right), the big serif figure, what it did this week and in 30 days, and a thin
/// line of the last year. The whole block opens Insights. No box around it.
struct NetWorthCard: View {
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    var engine: GameEngine
    var chartHeight: CGFloat = 40
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
                        if !ent.isPro { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Theme.inkFaint).accessibilityHidden(true) }
                        Text("Insights").textStyle(.caption, tint: Theme.inkSoft)
                        LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
                    }
                }
                HeldValue(live: nw.total) { (v: Double) in
                    RollingMoney(value: v) { (x: Double) -> String in store.money(x) }
                        .font(.hero(heroSize))
                        .foregroundStyle(v < 0 ? Theme.loss : Theme.ink)
                        .minimumScaleFactor(0.5).lineLimit(1)
                }
                changeLine(today: store.dayChip?.profit, week: week, month: month)
                balanceRow(personal: nw.personal, total: nw.total, weekAgo: weekAgo, monthAgo: monthAgo)
                if series.count >= 2 && chartHeight > 0 {
                    // Scaled to the series' own range, so a year's real shape shows instead of a flat line on a band.
                    let rising: Bool = (series.last ?? 0) >= (series.first ?? 0)
                    Sparkline(values: series, tint: rising ? Theme.gain : Theme.loss, filled: true)
                        .frame(height: chartHeight)
                        .revealOnChange(of: series.last)
                        .accessibilityHidden(true)
                        .padding(.top, Theme.Space.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(ent.isPro ? "Opens Insights" : "Opens Insights, part of Ledger Pro")
        .accessibilityIdentifier("home-insights")
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
                Text((d > 0.5 ? "▲ " : d < -0.5 ? "▼ " : "") + store.short(abs(d))).textStyle(.caption, tint: Theme.change(d), numeric: true).lineLimit(1)
            } else {
                Text("–").textStyle(.body, tint: Theme.inkFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func changeText(_ c: Double?, _ unit: String) -> some View {
        if let c {
            HStack(spacing: Theme.Space.xs) {
                Text((c > 0.5 ? "▲ " : c < -0.5 ? "▼ " : "") + store.short(abs(c))).textStyle(.body, tint: Theme.change(c), numeric: true, weight: .medium)
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
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            Text(title).textStyle(.label, tint: Theme.inkFaint).lineLimit(1)
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

    /// With nothing to answer, the player's next goal fills the slot: the ladder goal, else today's mission while it is open.
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
        if let d = daily, !d.claimed {
            if d.done { return Goal(title: d.title, line: "Done. Claim the reward in Goals.", action: "Claim", link: "goals") }
            return Goal(title: d.title, line: d.progress, action: d.link.isEmpty ? "" : "Go", link: d.link)
        }
        return nil
    }

    var body: some View {
        let first: Suggestion? = store.suggestionsNow.first { $0.tone != .neutral }
        let waiting: Int = store.openDecisionCount
        let next: Goal? = first == nil && waiting == 0 ? goal : nil
        let tick: Int = engine.state.week * 7 + engine.state.day
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HomeGroupLabel(title: next != nil ? "Your next goal" : "Needs you") { inboxLink(waiting) }
            if let first {
                lead(first)
                    .id(first.id)
                    .transition(.opacity)
            } else if waiting > 0 {
                waitingCard(waiting)
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
        .background(shape.fill(Theme.surfaceRaised))
        .contentShape(shape)
        return Button {
            guard opens else { return }
            Haptics.tap()
            if g.link == "goals" { store.openApp(.goals) } else { _ = store.openLadderLink(g.link) }
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

    /// The raised card: a tone mark, the title, one line of why, and the action in accent.
    private func lead(_ item: Suggestion) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        let detail: String = item.detail.tidyMoney
        return Button { Haptics.tap(); store.go(popup: item.action) } label: {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                Capsule().fill(tint(item.tone)).frame(width: 3).frame(maxHeight: .infinity).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(item.title.tidyMoney).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    if !detail.isEmpty && !compact {
                        Text(detail).textStyle(.caption).lineLimit(1)
                    }
                    Text(item.actionLabel).textStyle(.body, tint: Theme.accent, weight: .semibold).lineLimit(1)
                        .padding(.top, Theme.Space.xxs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, compact ? Theme.Space.m : Theme.Space.l).padding(.horizontal, Theme.Space.l)
            .background(shape.fill(Theme.surfaceRaised))
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier(item))
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
            .background(shape.fill(Theme.surfaceRaised))
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

// MARK: Next day

/// Pinned under Home: the day line (day, what the last day did to net worth, the week's seven segments), then Next day with a labelled
/// "Skip week" beside it. Skip week is free in the first 12 weeks, then Pro (a lock on it, the paywall when tapped). While the week plays
/// the two buttons give way to its progress (day n of 7) and a Stop.
struct AdvanceBar: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var engine: GameEngine
    @Environment(Entitlements.self) private var ent

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                caption
                Spacer(minLength: Theme.Space.s)
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { d in
                        Capsule().fill(d <= engine.state.day ? Theme.ink.opacity(0.85) : Theme.line).frame(width: 12, height: 3)
                    }
                }
                .accessibilityHidden(true)
                .animation(Motion.quick(reduceMotion), value: engine.state.day)
            }
            if store.playingWeek {
                playingRow
            } else {
                HStack(spacing: Theme.Space.s) {
                    nextButton
                    skipButton
                }
            }
        }
        .animation(Motion.quick(reduceMotion), value: store.playingWeek)
        .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.s)
        .background(Theme.page)
        .overlay(alignment: .top) { Hairline() }
    }

    /// "Day 3 of 7", and after a day the real change in net worth. The line keeps its height, so nothing jumps.
    private var caption: some View {
        HStack(spacing: Theme.Space.s) {
            Text("Day \(engine.state.day + 1) of 7").textStyle(.caption, tint: Theme.inkSoft)
            if let chip = store.dayChip {
                let c: Double = chip.netWorthChange
                Text((c > 0.5 ? "▲ " : c < -0.5 ? "▼ " : "") + store.short(abs(c)))
                    .textStyle(.caption, tint: Theme.change(c), numeric: true, weight: .medium)
                    .id(chip.id)
                    .transition(.opacity)
            }
        }
        .lineLimit(1)
        .animation(Motion.quick(reduceMotion), value: store.dayChip?.id)
        .accessibilityElement(children: .combine)
    }

    private var locked: Bool { !engine.state.isGameOver && !ent.effective.canPlayToEndOfWeek(week: engine.state.week + 1, now: Date()) }

    /// "Skip week ▸▸": plays the rest of the week; with a lock (and the paywall on tap) once it needs Pro. Shown from week 2.
    @ViewBuilder private var skipButton: some View {
        if store.canPlayWeek {
            let isLocked: Bool = locked
            Button {
                if isLocked { ent.run(.playToEndOfWeek, "Skip week") {} } else { store.playToEndOfWeek() }
            } label: {
                HStack(spacing: Theme.Space.xs) {
                    if isLocked { Image(systemName: "lock.fill").font(.caption.weight(.bold)).accessibilityHidden(true) }
                    Text("Skip week")
                    Image(systemName: "forward.fill").font(.caption.weight(.semibold)).accessibilityHidden(true)
                }
                .fixedSize()
            }
            .buttonStyle(SecondaryButtonStyle(tint: isLocked ? Theme.inkSoft : Theme.ink))
            .disabled(store.isAdvancing || store.blockingMessageID != nil || store.reportSheet != nil)
            .accessibilityLabel(isLocked ? "Skip week, needs Ledger Pro" : "Skip week")
            .accessibilityIdentifier("play-week")
        }
    }

    /// The week playing: which day it is on, a bar of the seven days, and Stop (the day already running finishes first).
    private var playingRow: some View {
        let day: Int = min(7, engine.state.day + 1)
        return HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: Theme.Space.s) {
                    ProgressView().controlSize(.small).tint(Theme.ink)
                    Text("Skipping the week · day \(day) of 7").textStyle(.body, tint: Theme.ink, numeric: true).lineLimit(1).minimumScaleFactor(0.8)
                }
                ProgressLine(fraction: Double(day) / 7, tint: Theme.accent, height: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Stop") { Haptics.tap(); store.stopPlayingWeek() }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("stop-week")
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("week-playing")
    }

    private var nextButton: some View {
        let busy: Bool = store.isAdvancing
        let over: Bool = engine.state.isGameOver
        let blockID: Int? = store.blockingMessageID
        let label: String = over ? "Game over" : busy ? "Running" : blockID != nil ? "Answer first" : "Next day"
        return Button {
            Haptics.tap()
            if let id = blockID { store.openApp(.inbox, request: .message(id)) } else { store.nextDay() }
        } label: {
            HStack(spacing: Theme.Space.s) {
                if busy { ProgressView().controlSize(.small).tint(Theme.accentInk) }
                Text(label)
            }
        }
        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
        .disabled(over || busy || (blockID == nil && store.reportSheet != nil))
        .accessibilityIdentifier("next-day")
    }
}
