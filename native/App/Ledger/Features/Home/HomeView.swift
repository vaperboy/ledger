import SwiftUI
import Simulation
import Finance
import Businesses

/// The Home tab (route name `.company`) as one calm scrolling page, private-bank style: the date and the owner, the net worth hero
/// (figure, change, chart, what it is made of), the one thing that needs the owner, the companies (passed in by CompaniesView), then
/// career and shortcuts. Report sheets and reward popups appear on top of it; Next day is pinned under it (`AdvanceBar`).
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
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                HomeTopLine(name: playerName, dateText: "\(e.homeCountry.flag)  Week \(e.state.week + 1) · \(e.date)", onNewCompany: onNewCompany)
                if e.cashIsTight { cashTightLine }
                if ent.plusEndedNotice {
                    Text("Plus has ended. Your saves are safe.").textStyle(.caption)
                        .accessibilityIdentifier("plus-ended-line")
                }
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: Theme.Space.xxl) {
                        NetWorthCard(engine: e).frame(maxWidth: .infinity)
                        TopPriorities(engine: e).frame(maxWidth: .infinity)
                    }
                } else {
                    NetWorthCard(engine: e)
                }
            }
            if sizeClass != .regular { TopPriorities(engine: e) }
            companies()
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HomeGroupLabel("Career")
                HomeRankStrip(engine: e) { showInsights = true }
            }
            HomeShortcutRow()
        }
        .centerSheet(isPresented: $showInsights, title: "Insights", size: .tall) { InsightsView(engine: e) }
    }

    private var playerName: String {
        let n = engine.state.player.name
        return n.isEmpty ? "there" : n
    }

    /// New-player start: a bill the account cannot cover yet waits one day; nothing else happens.
    private var cashTightLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Circle().fill(Theme.warn).frame(width: 6, height: 6).accessibilityHidden(true)
            Text("Cash is tight. A bill waits until tomorrow.").textStyle(.body, tint: Theme.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cash-tight-banner")
    }
}

/// The page's top line: the date over the owner's name, and a round New company button.
struct HomeTopLine: View {
    var name: String
    var dateText: String
    var onNewCompany: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
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

/// The hero: the label, the big serif figure, what it did this week and in 30 days, the chart with its periods under it, and the four
/// figures it is made of on one quiet line. No box around it.
struct NetWorthCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var days = 365
    @State private var snap: NetWorthSnap?
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 42

    /// What the chart and the two change texts showed before the day: kept while the daily report is waiting for its Continue.
    struct NetWorthSnap {
        var series: [Int: [Double]]
        var week: Double?
        var month: Double?
    }

    private func takeSnap() -> NetWorthSnap {
        var all: [Int: [Double]] = [:]
        for p in PeriodPicker.periods { all[p.days] = store.netWorthSeriesNow(days: p.days) }
        let hist = store.dayHistoryNow ?? engine.dayHistory
        return NetWorthSnap(series: all, week: DayHistory.change(hist.netWorth, days: 7)?.amount, month: DayHistory.change(hist.netWorth, days: 30)?.amount)
    }

    var body: some View {
        let nw = store.netWorthNow ?? engine.netWorth
        let hist = store.dayHistoryNow ?? engine.dayHistory
        let blocked: Bool = store.holdsHomeFigures
        let held: NetWorthSnap? = blocked ? snap : nil
        let week: Double? = held != nil ? held?.week : DayHistory.change(hist.netWorth, days: 7)?.amount
        let month: Double? = held != nil ? held?.month : DayHistory.change(hist.netWorth, days: 30)?.amount
        let frozenSeries: [Double]? = held?.series[days]
        let owed = nw.debt + nw.pendingTax
        let wealth: NetWorthBreakdown = store.netWorthBreakdownNow ?? engine.netWorthBreakdown()
        let otherAssets: Double = wealth.investments + wealth.luxury + wealth.otherEstimatedHoldings
        let series: [Double] = frozenSeries ?? store.netWorthSeriesNow(days: days)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Net worth").textStyle(.label, tint: Theme.inkFaint)
                HeldValue(live: nw.total) { (v: Double) in
                    Text(store.money(v))
                        .font(.hero(heroSize))
                        .foregroundStyle(v < 0 ? Theme.loss : Theme.ink)
                        .minimumScaleFactor(0.5).lineLimit(1)
                        .moneyFlash(v)
                }
                changeLine(week: week, month: month)
            }
            if series.count >= 2 {
                VStack(spacing: Theme.Space.s) {
                    NetWorthChart(engine: engine, days: days, height: 64, frozen: series)
                    PeriodPicker(days: $days)
                }
            }
            breakdown(cash: wealth.liquid, invested: otherAssets, companies: wealth.estimatedCompanyEquity, debt: owed)
        }
        .accessibilityElement(children: .contain)
        .onAppear { if snap == nil { snap = takeSnap() } }
        .onChange(of: nw.total) { _, _ in if !store.holdsHomeFigures { snap = takeSnap() } }
        .onChange(of: blocked) { _, now in if !now { snap = takeSnap() } }
    }

    /// "▲ 12.3k this week · ▲ 40k in 30 days" on one line, or two lines when it does not fit.
    @ViewBuilder private func changeLine(week: Double?, month: Double?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.s) {
                changeText(week, "this week")
                Text("·").textStyle(.caption, tint: Theme.inkFaint)
                changeText(month, "in 30 days")
            }
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                changeText(week, "this week")
                changeText(month, "in 30 days")
            }
        }
    }

    @ViewBuilder private func changeText(_ c: Double?, _ unit: String) -> some View {
        if let c {
            HStack(spacing: Theme.Space.xs) {
                Text((c > 0.5 ? "▲ " : c < -0.5 ? "▼ " : "") + store.short(abs(c))).textStyle(.body, tint: Theme.change(c), numeric: true, weight: .medium)
                Text(unit).textStyle(.body, tint: Theme.inkSoft)
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
        } else {
            Text("No change yet " + unit).textStyle(.body, tint: Theme.inkFaint).lineLimit(1)
        }
    }

    /// Cash, invested, companies and debt: four across when they fit, else two by two (larger text, small phones).
    private func breakdown(cash: Double, invested: Double, companies: Double, debt: Double) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                box("Cash", cash)
                box("Invested", invested)
                box("Companies", companies)
                box("Debt", debt, loss: true)
            }
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: 0) {
                    box("Cash", cash)
                    box("Invested", invested)
                }
                HStack(spacing: 0) {
                    box("Companies", companies)
                    box("Debt", debt, loss: true)
                }
            }
        }
        .padding(.top, Theme.Space.m)
        .overlay(alignment: .top) { Hairline() }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func box(_ label: String, _ live: Double, loss: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(label).textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
            HeldValue(live: loss ? -live : live) { (v: Double) in
                let amount: Double = loss ? -v : v
                Text(loss && amount > 0.5 ? "−" + store.short(amount) : store.short(loss ? 0 : amount))
                    .textStyle(.headline, tint: loss && amount > 0.5 ? Theme.loss : Theme.ink, numeric: true)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .moneyFlash(v)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 1W 1M 3M 1Y All spread under the chart; the chosen one sits on a quiet pill. Each label has a 44 pt hit area.
struct PeriodPicker: View {
    @Binding var days: Int
    static let periods: [(label: String, days: Int)] = [("1W", 8), ("1M", 31), ("3M", 92), ("1Y", 365), ("All", 3650)]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.periods, id: \.days) { p in
                let on: Bool = days == p.days
                Button { days = p.days; Haptics.choose() } label: {
                    Text(p.label).textStyle(.caption, tint: on ? Theme.ink : Theme.inkFaint, weight: on ? .semibold : .medium)
                        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.xs)
                        .background(Capsule().fill(on ? Theme.inset : Color.clear))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, -Theme.Space.s)
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

// MARK: Shortcut tiles

/// The player's shortcuts (up to four, chosen with Edit or a long press), as tappable tiles. Each opens the matching Phone app or flow.
struct HomeShortcutRow: View {
    @EnvironmentObject var store: GameStore
    @State private var editing = false

    var body: some View {
        let badges = store.phoneBadges
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HomeGroupLabel(title: "Shortcuts") {
                Button("Edit") { Haptics.tap(); editing = true }
                    .buttonStyle(TertiaryButtonStyle(size: .compact))
                    .accessibilityIdentifier("edit-home-shortcuts")
            }
            HStack(spacing: Theme.Space.s) {
                ForEach(store.homeShortcuts) { item in
                    tile(item, badge: item.badgeApp.map { badges[$0] ?? 0 } ?? 0)
                }
            }
            .contextMenu { Button("Edit shortcuts") { editing = true } }
        }
        .centerSheet(isPresented: $editing) { HomeShortcutEditor() }
    }

    private func tile(_ item: HomeShortcut, badge: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        return Button { Haptics.tap(); item.open(store) } label: {
            VStack(spacing: Theme.Space.s) {
                LedgerGlyph(glyph: item.glyph, size: Theme.Icon.medium, tint: Theme.ink)
                Text(item.title).textStyle(.caption, tint: Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 64).padding(.vertical, Theme.Space.xs)
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

// MARK: Needs you

/// "Needs you", right under net worth: the one most important thing as a raised card (what it is, why, and the action), then at most
/// two more as quiet lines; the rest wait in the Inbox. Each opens the exact object (a decision opens in a popup right here). Decisions a
/// manager already handled never reach this list (the engine settles them), and neutral information is not a priority.
struct TopPriorities: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var engine: GameEngine
    var limit: Int = 3

    var body: some View {
        let list: [Suggestion] = store.suggestionsNow.filter { $0.tone != .neutral }
        let shown: [Suggestion] = Array(list.prefix(limit))
        let waiting: Int = store.openDecisionCount
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HomeGroupLabel(title: "Needs you") { inboxLink(waiting) }
            if let first = shown.first {
                lead(first)
                    .id(first.id)
                    .transition(.opacity)
                ForEach(shown.dropFirst(), id: \.id) { (item: Suggestion) in
                    row(item).transition(.opacity)
                }
            } else if waiting > 0 {
                waitingCard(waiting)
            } else {
                HStack(spacing: Theme.Space.s) {
                    LedgerGlyph(glyph: Glyph.check, size: Theme.Icon.small, tint: Theme.inkFaint)
                    Text("Nothing needs you right now.").textStyle(.body, tint: Theme.inkSoft)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            }
        }
        .animation(Motion.quick(reduceMotion), value: shown.map { (s: Suggestion) -> String in s.id })
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
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Capsule().fill(tint(item.tone)).frame(width: 3).frame(maxHeight: .infinity).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(item.title.tidyMoney).textStyle(.headline).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !detail.isEmpty {
                        Text(detail).textStyle(.caption).lineLimit(2).multilineTextAlignment(.leading)
                    }
                    HStack(spacing: Theme.Space.xs) {
                        Text(item.actionLabel).textStyle(.body, tint: Theme.accent, weight: .semibold).lineLimit(1)
                        LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.accent)
                    }
                    .padding(.top, Theme.Space.xxs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(Theme.Space.l)
            .background(shape.fill(Theme.surfaceRaised))
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier(item))
    }

    /// A further item: a tone dot, the title and a chevron, 44 pt high.
    private func row(_ item: Suggestion) -> some View {
        Button { Haptics.tap(); store.go(popup: item.action) } label: {
            HStack(spacing: Theme.Space.m) {
                Circle().fill(tint(item.tone)).frame(width: 6, height: 6).accessibilityHidden(true)
                Text(item.title.tidyMoney).textStyle(.body).lineLimit(2).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(item.actionLabel).textStyle(.caption, tint: Theme.inkSoft).lineLimit(1).fixedSize()
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
            }
            .padding(.horizontal, Theme.Space.l)
            .frame(minHeight: 44).contentShape(Rectangle())
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

/// Pinned under Home: one line with the week's progress (seven short segments), the day and what the last day did to net worth, and
/// "End of week" at the right; under it the full-width champagne Next day. While a day runs the button shows progress.
struct AdvanceBar: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var engine: GameEngine
    @Environment(Entitlements.self) private var ent

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    caption
                    HStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            Capsule().fill(d <= engine.state.day ? Theme.ink.opacity(0.85) : Theme.line).frame(width: 14, height: 3)
                        }
                    }
                    .accessibilityHidden(true)
                    .animation(Motion.quick(reduceMotion), value: engine.state.day)
                }
                Spacer(minLength: Theme.Space.s)
                weekButton
            }
            nextButton
        }
        .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.m).padding(.bottom, Theme.Space.s)
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

    /// A free player in weeks 9 to 12 sees "Pro after week 12" by the fast-forward, which becomes a Pro feature after week 12.
    private var proTeaser: Bool {
        let w: Int = engine.state.week + 1
        return !ent.isPro && w >= 9 && w <= 12
    }

    /// "Play to end of week": a text button from week 2; off while a blocking Inbox item is open.
    @ViewBuilder private var weekButton: some View {
        if store.canPlayWeek {
            Button { if ent.effective.canPlayToEndOfWeek(week: engine.state.week + 1, now: Date()) { store.playToEndOfWeek() } else { ent.run(.playToEndOfWeek, "Play to end of week") {} } } label: {
                HStack(spacing: Theme.Space.xs) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("End of week").textStyle(.caption, tint: Theme.ink, weight: .medium).lineLimit(1)
                        if proTeaser { Text("Pro after week 12").textStyle(.caption, tint: Theme.inkFaint).lineLimit(1) }
                    }
                    if !engine.state.isGameOver && !ent.effective.canPlayToEndOfWeek(week: engine.state.week + 1, now: Date()) { ProMark(feature: .playToEndOfWeek) }
                    Image(systemName: "forward.end").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft).accessibilityHidden(true)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .disabled(store.isAdvancing || store.blockingMessageID != nil || store.reportSheet != nil)
            .accessibilityLabel(proTeaser ? "Play to end of week, Pro after week 12" : "Play to end of week")
            .accessibilityIdentifier("play-week")
        }
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
