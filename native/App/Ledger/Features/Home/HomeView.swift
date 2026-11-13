import SwiftUI
import GameCore
import Simulation
import Finance
import Businesses

struct HomeSummary<Companies: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @ObservedObject private var streak = StreakModel.shared
    var engine: GameEngine
    var compact: Bool = false
    var fills: Bool = false
    var chart: Bool = true
    @ViewBuilder var companies: () -> Companies
    @State private var showInsights = false

    var body: some View {
        let e = engine
        VStack(alignment: .leading, spacing: compact ? Theme.Space.m : Theme.Space.l) {
            VStack(alignment: .leading, spacing: compact ? Theme.Space.s : Theme.Space.m) {
                HomeTopLine(name: playerName, dateText: "\(e.homeCountry.flag) \(e.date)", engine: e)
                if e.cashIsTight { cashTightLine }
                if ent.plusEndedNotice {
                    Text("Plus has ended. Your saves are safe.").textStyle(.caption)
                        .accessibilityIdentifier("plus-ended-line")
                }
                if sizeClass == .regular {
                    NetWorthCard(engine: e, chartHeight: 64) { showInsights = true }.frame(maxWidth: .infinity)
                } else {
                    NetWorthCard(engine: e, chartHeight: chart ? (compact ? 24 : 32) : 0) { showInsights = true }
                }
            }
            if fills { Self.gap }
            HomeGoalStrip(engine: e)
            HomePassCard()
            HomeRecapCard()
            HomeWorldStrip()
            if fills { Self.gap }
            companies()
            if fills { Self.gap }
        }
        .centerSheet(isPresented: $showInsights, title: "Insights", size: .tall, category: .detail, tone: .info) { InsightsView(engine: e) }
        .task {
            let reward: LoginReward? = await streak.openToday()
            if let reward { await MainActor.run { store.tell("Daily streak", reward.text, tone: "good") } }
        }
    }

    private static var gap: some View { Spacer(minLength: 0) }

    private var playerName: String {
        let n = engine.state.player.name
        return n.isEmpty ? "there" : n
    }

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
        }
    }
}

extension GameEngine {
    var canStartCompany: Bool {
        let none: Bool = !state.companies.contains { (c: Company) -> Bool in c.status.isLive }
        return none || Gates.isOpen(.newCompany, state, data: data)
    }
}

struct NetWorthCard: View {
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    var engine: GameEngine
    var chartHeight: CGFloat = 40
    var onInsights: () -> Void
    @State private var snap: NetWorthSnap?
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 42
    private static let days = 365

    struct NetWorthSnap {
        var series: [Double]
        var week: Double?
        var month: Double?
        var weekAgo: Double?
        var monthAgo: Double?
    }

    private func takeSnap() -> NetWorthSnap {
        let hist = store.dayHistoryNow ?? engine.dayHistory
        return NetWorthSnap(series: store.netWorthSeriesNow(days: Self.days), week: DayHistory.change(hist.netWorth, days: 7)?.amount,
                            month: DayHistory.change(hist.netWorth, days: 30)?.amount,
                            weekAgo: Self.past(hist.netWorth, days: 7), monthAgo: Self.past(hist.netWorth, days: 30))
    }

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
                balanceRow(personal: nw.personal, total: nw.total, weekAgo: weekAgo, monthAgo: monthAgo)
                if series.count >= 2 && chartHeight > 0 {
                    let rising: Bool = (series.last ?? 0) >= (series.first ?? 0)
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

    private func balanceRow(personal: Double, total: Double, weekAgo: Double?, monthAgo: Double?) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("Your account").textStyle(.caption, tint: Theme.inkFaint).lineLimit(1).minimumScaleFactor(0.8)
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
    func openHiring() {
        let posts = (engine?.teamOverview().vacancies ?? []).filter { $0.companyID != nil && $0.scope != "chain" }
        if let id = (posts.first(where: { $0.needed }) ?? posts.first)?.companyID {
            push(.companyAt(id, .staff))
        } else if let id = engine?.state.companies.first(where: { $0.status.isLive })?.id {
            push(.companyAt(id, .staff))
        }
    }
}

struct TopPriorities: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var engine: GameEngine
    var compact: Bool = false

    var body: some View {
        let first: Suggestion? = store.suggestionsNow.first { $0.tone != .neutral }
        let waiting: Int = store.openDecisionCount
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HomeGroupLabel(title: "Needs you") { inboxLink(waiting) }
            if let first {
                lead(first)
                    .id(first.id)
                    .transition(.opacity)
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
        .animation(Motion.quick(reduceMotion), value: first?.id)
    }

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

    private func inlineDecision(_ item: Suggestion) -> Message? {
        guard case .openMessage(let id) = item.action, let m = engine.state.inbox.first(where: { (x: Message) -> Bool in x.id == id }),
              HomeDecisionButtons.fits(engine, m) else { return nil }
        return m
    }

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
