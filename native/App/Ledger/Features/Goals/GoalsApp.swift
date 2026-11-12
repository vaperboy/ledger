import SwiftUI
import GameCore
import Simulation
import Businesses

// The one place for every goal: battle pass on top, then Daily, Weekly, Season and Long-term.
struct GoalsApp: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        Group {
            if let e = store.engine { GoalsContent(engine: e) } else { Color.clear }
        }
        .appScreen(title: "Goals", subtitle: PhoneApp.season.subtitle)
        .accessibilityIdentifier("goals-app")
    }
}

enum GoalsTab: String, CaseIterable, Hashable {
    case daily = "Daily", weekly = "Weekly", season = "Season", long = "Long-term"
}

struct GoalsContent: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var season = SeasonModel.shared
    @State private var tab: GoalsTab = .daily
    @State private var daily: PlayerGoals.DailyGoal?
    var engine: GameEngine

    var body: some View {
        let e = engine
        let claims: [GoalClaims.Claimable] = store.claimableGoals
        let tick: Int = e.state.week * 7 + e.state.day
        VStack(spacing: 0) {
            GoalsPassStrip()
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.xs).padding(.bottom, Theme.Space.s)
            SectionTabs(items: GoalsTab.allCases, title: { (t: GoalsTab) -> String in t.rawValue }, selection: $tab,
                        badge: { (t: GoalsTab) -> Int in badge(t, claims) })
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    switch tab {
                    case .daily: GoalsDailyTab(engine: e, daily: daily, claims: claims, claim: claim)
                    case .weekly: GoalsWeeklyTab()
                    case .season: GoalsSeasonTab()
                    case .long: GoalsLongTab(engine: e, claims: claims, claim: claim)
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.m).padding(.bottom, 40)
                .frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .ledgerBackground()
        .onAppear { season.refreshSeason(); daily = store.dailyGoal() }
        .onChange(of: tick) { _, _ in daily = store.dailyGoal() }
    }

    private func badge(_ t: GoalsTab, _ claims: [GoalClaims.Claimable]) -> Int {
        switch t {
        case .daily: return claims.filter { (c: GoalClaims.Claimable) -> Bool in c.kind == .daily }.count
        case .long: return claims.filter { (c: GoalClaims.Claimable) -> Bool in c.kind != .daily }.count
        default: return 0
        }
    }

    private func claim(_ c: GoalClaims.Claimable) {
        store.claimGoal(c.kind, id: c.goalID)
        daily = store.dailyGoal()
    }
}

// MARK: Battle pass summary

struct GoalsPassStrip: View {
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @ObservedObject private var season = SeasonModel.shared

    private func next(_ pass: SeasonPass, _ track: SeasonPass.Track) -> SeasonReward? {
        guard pass.tier < SeasonPass.tierCount else { return nil }
        return ((pass.tier + 1)...SeasonPass.tierCount).lazy.compactMap { (t: Int) -> SeasonReward? in pass.reward(track, tier: t) }.first
    }

    var body: some View {
        let pass: SeasonPass = season.pass
        let premium: Bool = season.premiumOpen(plus: ent.isPlus, founder: ent.isFounder)
        let open: Int = pass.claimableCount(isPlus: premium)
        let left: Int = pass.daysLeft(today: season.today)
        let free: SeasonReward? = next(pass, .free)
        let paid: SeasonReward? = premium ? next(pass, .premium) : nil
        let upcoming: SeasonReward? = [free, paid].compactMap { (r: SeasonReward?) -> SeasonReward? in r }.min { (a: SeasonReward, b: SeasonReward) -> Bool in a.tier < b.tier }
        NavigationLink {
            SeasonView().appScreen(title: "Season Pass", subtitle: "Tiers and rewards")
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text("Battle pass").textStyle(.label, tint: Theme.gold)
                    Text("Season \(pass.seasonNumber)").textStyle(.caption)
                    Spacer(minLength: Theme.Space.s)
                    if open > 0 { StoreTag(text: open == 1 ? "1 reward ready" : "\(open) rewards ready", tint: Theme.gain) }
                    else { Text(left == 1 ? "Ends tomorrow" : "\(left) days left").textStyle(.caption) }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(pass.isComplete ? "All \(SeasonPass.tierCount) levels reached" : "Level \(pass.tier) of \(SeasonPass.tierCount)").textStyle(.headline, numeric: true)
                    Spacer(minLength: Theme.Space.s)
                    if !pass.isComplete { Text("\(pass.xpIntoTier) / \(SeasonPass.xpPerTier) XP").textStyle(.caption, numeric: true) }
                    LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
                }
                ProgressLine(fraction: pass.tierProgress, tint: Theme.gold, height: 5)
                if let upcoming {
                    HStack(spacing: Theme.Space.s) {
                        ItemArt(reward: upcoming, size: 28)
                        Text("Next reward, level \(upcoming.tier): \(upcoming.title)").textStyle(.caption, tint: Theme.ink).lineLimit(1)
                    }
                }
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(StoreSurface(tint: Theme.gold, radius: Theme.Radius.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the full battle pass")
        .accessibilityIdentifier("goals-pass")
    }
}

// MARK: Shared pieces

struct GoalsCard<Content: View>: View {
    var highlight: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(highlight ? Theme.accent : Theme.line, lineWidth: highlight ? 1.5 : 1))
    }
}

struct GoalsGroup<Content: View>: View {
    var title: String
    var note: String = ""
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title).textStyle(.label, tint: Theme.inkFaint)
            if !note.isEmpty { Text(note).textStyle(.caption).fixedSize(horizontal: false, vertical: true) }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GoalRowView: View {
    @EnvironmentObject var store: GameStore
    var line: GoalLine
    var claim: (GoalClaims.Claimable) -> Void

    var body: some View {
        let opens: Bool = !line.link.isEmpty
        GoalsCard(highlight: line.current) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                Button {
                    guard opens else { return }
                    Haptics.tap()
                    _ = store.openLadderLink(line.link)
                } label: {
                    HStack(alignment: .center, spacing: Theme.Space.m) {
                        mark
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(line.title.tidyMoney).textStyle(.headline, tint: line.done && line.claim == nil ? Theme.inkSoft : nil).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            if !line.detail.isEmpty {
                                Text(line.detail.tidyMoney).textStyle(.caption).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            }
                            if let words = rewardWords {
                                Text(words).textStyle(.caption, tint: Theme.accent).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if opens && line.claim == nil { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint) }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .disabled(!opens)
                .accessibilityElement(children: .combine)
                .accessibilityHint(opens ? "Goes to where it is done" : "")
                if let c = line.claim {
                    Button { claim(c) } label: {
                        Text("Claim").textStyle(.body, tint: Theme.accentInk, weight: .semibold)
                            .padding(.horizontal, Theme.Space.l).frame(minHeight: 44)
                            .background(Capsule().fill(Theme.accent))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Claim " + line.title)
                    .accessibilityIdentifier("claim-" + c.id)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var mark: some View {
        if let p = line.progress {
            GoalRing(progress: p, done: line.done)
        } else if line.done {
            GoalRing(progress: 1, done: true)
        } else {
            Circle().strokeBorder(line.current ? Theme.gold : Theme.border, lineWidth: 3).frame(width: 38, height: 38).accessibilityHidden(true)
        }
    }

    private var rewardWords: String? {
        var parts: [String] = []
        if !line.reward.isEmpty { parts.append(line.reward) }
        if let c = line.claim, c.cash > 0 { parts.append("+" + store.short(c.cash)) }
        if parts.isEmpty { return nil }
        return (line.done && line.claim == nil ? "" : "Reward: ") + parts.joined(separator: ". ")
    }
}

struct PassMissionCard: View {
    var row: SeasonPass.MissionRow

    var body: some View {
        GoalsCard {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    LedgerGlyph(glyph: row.done ? Glyph.check : Glyph.chevron, size: 12, tint: row.done ? Theme.gain : Theme.inkFaint)
                    Text(row.mission.title).textStyle(.body, tint: row.done ? Theme.inkSoft : Theme.ink).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Space.s)
                    Text("+\(row.mission.xp) XP").textStyle(.caption, tint: Theme.gain, numeric: true)
                }
                ProgressLine(fraction: Double(row.progress) / Double(max(1, row.mission.target)), tint: Theme.gold, height: 4)
                Text("\(row.progress) of \(row.mission.target)").textStyle(.caption, numeric: true)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: Daily

struct GoalsDailyTab: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var season = SeasonModel.shared
    @ObservedObject private var login = StreakModel.shared
    var engine: GameEngine
    var daily: PlayerGoals.DailyGoal?
    var claims: [GoalClaims.Claimable]
    var claim: (GoalClaims.Claimable) -> Void

    var body: some View {
        let off: Bool = engine.dailyGoalsOff
        let today: Int = season.today
        let rows: [SeasonPass.MissionRow] = season.pass.missionRows(.day, today: today)
        GoalsGroup(title: "Today's goal") {
            if let line = GoalsFeed.daily(daily, claims: claims) {
                GoalRowView(line: line, claim: claim)
            } else {
                GoalsCard { Text(off ? "The daily goal is off." : "No goal today.").textStyle(.body, tint: Theme.inkSoft).frame(minHeight: 44, alignment: .leading) }
            }
            Button(off ? "Turn the daily goal on" : "Turn the daily goal off") {
                Haptics.tap()
                store.act { $0.setDailyGoalsOff(!off) }
            }
            .textStyle(.caption, tint: Theme.inkFaint, weight: .medium)
            .buttonStyle(PressableStyle())
            .frame(minHeight: 44)
        }
        GoalsGroup(title: "Pass missions today", note: "Each one adds XP to the battle pass.") {
            GoalsCard {
                HStack(spacing: Theme.Space.s) {
                    LedgerGlyph(glyph: season.pass.loginDay == today ? Glyph.check : Glyph.lock, size: 14, tint: season.pass.loginDay == today ? Theme.gain : Theme.inkFaint)
                    Text("Open the game today").textStyle(.body)
                    Spacer(minLength: Theme.Space.s)
                    Text("+\(PassMissions.loginXP) XP").textStyle(.caption, tint: Theme.gain, numeric: true)
                }
                .frame(minHeight: 28)
                .accessibilityElement(children: .combine)
            }
            ForEach(rows) { (r: SeasonPass.MissionRow) in PassMissionCard(row: r) }
        }
        GoalsGroup(title: "Streaks") { streaks }
    }

    private var streaks: some View {
        let info: PlayerGoals.StreakInfo = PlayerGoals.streakInfo(engine.state)
        let play: Int = PlayStreak.current(engine.state, today: GameStore.calendarDay())
        var goalNote: String = "Best " + days(info.best)
        if let m = info.nextMilestone { goalNote += ". Next reward at " + days(m) }
        if info.protectionTokens > 0 { goalNote += ". A missed day is covered once" }
        return GoalsCard {
            VStack(spacing: 0) {
                LedgerRow(leading: .symbol("flame.fill"), leadingTint: info.count > 0 ? Theme.warn : Theme.inkFaint, title: "Daily goal streak",
                          subtitle: goalNote, value: days(info.count), density: .compact)
                Hairline()
                LedgerRow(leading: .symbol("calendar"), leadingTint: login.streak.count > 0 ? Theme.warn : Theme.inkFaint, title: "Login streak",
                          subtitle: login.line.isEmpty ? "Open the game each day for a season box." : login.line, value: days(login.streak.count), density: .compact)
                Hairline()
                LedgerRow(leading: .symbol("play.fill"), leadingTint: play > 0 ? Theme.warn : Theme.inkFaint, title: "Play streak",
                          subtitle: "Days in a row you played.", value: days(play), density: .compact)
            }
        }
    }

    private func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }
}

// MARK: Weekly

struct GoalsWeeklyTab: View {
    @ObservedObject private var season = SeasonModel.shared

    var body: some View {
        let rows: [SeasonPass.MissionRow] = season.pass.missionRows(.week, today: season.today)
        GoalsGroup(title: "Pass missions this week", note: "Bigger tasks that add XP to the battle pass.") {
            if rows.isEmpty {
                GoalsCard { Text("No weekly missions right now.").textStyle(.body, tint: Theme.inkSoft).frame(minHeight: 44, alignment: .leading) }
            }
            ForEach(rows) { (r: SeasonPass.MissionRow) in PassMissionCard(row: r) }
        }
    }
}

// MARK: Season

struct GoalsSeasonTab: View {
    @Environment(Entitlements.self) private var ent
    @ObservedObject private var season = SeasonModel.shared

    var body: some View {
        let pass: SeasonPass = season.pass
        let premium: Bool = season.premiumOpen(plus: ent.isPlus, founder: ent.isFounder)
        let left: Int = pass.daysLeft(today: season.today)
        let rows: [SeasonPass.MissionRow] = pass.missionRows(.month, today: season.today)
        GoalsGroup(title: "This season") {
            GoalsCard {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(pass.progressText).textStyle(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(left == 1 ? "Season \(pass.seasonNumber) ends tomorrow" : "Season \(pass.seasonNumber) ends in \(left) days").textStyle(.caption)
                    if let ending = pass.endingNote(today: season.today, isPlus: premium) {
                        Text(ending).textStyle(.caption, tint: Theme.warn).fixedSize(horizontal: false, vertical: true)
                    } else if let missed = pass.missedNote, left > SeasonPass.seasonDays - 7 {
                        Text(missed).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        GoalsGroup(title: "Pass missions this month", note: "Bigger tasks that add XP to the battle pass.") {
            ForEach(rows) { (r: SeasonPass.MissionRow) in PassMissionCard(row: r) }
        }
        GoalsGroup(title: "Other ways to earn XP", note: "These add up to at most \(SeasonPass.dailyXPCap) XP a day. The pass fills at the pace of steady play, not in a week.") {
            GoalsCard {
                VStack(spacing: 0) {
                    ForEach(Array(SeasonPass.Source.allCases.enumerated()), id: \.offset) { (i: Int, s: SeasonPass.Source) in
                        if i > 0 { Hairline() }
                        HStack {
                            Text(s.title).textStyle(.body)
                            Spacer(minLength: Theme.Space.s)
                            Text("+\(s.xp) XP").textStyle(.body, tint: Theme.gain, numeric: true)
                        }
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

// MARK: Long-term

struct GoalsLongTab: View {
    @EnvironmentObject var store: GameStore
    @State private var showLadder = false
    var engine: GameEngine
    var claims: [GoalClaims.Claimable]
    var claim: (GoalClaims.Claimable) -> Void

    var body: some View {
        let e = engine
        let missions: [GoalLine] = GoalsFeed.missions(e, claims: claims)
        let career = GoalsFeed.career(e, claims: claims)
        level(e)
        if !missions.isEmpty {
            GoalsGroup(title: "Missions", note: "The first steps of running a company.") {
                ForEach(missions) { (l: GoalLine) in GoalRowView(line: l, claim: claim) }
            }
        }
        GoalsGroup(title: "Career") {
            rank(e)
            ForEach(career.open) { (l: GoalLine) in GoalRowView(line: l, claim: claim) }
            if career.finished > 0 {
                Text(career.finished == 1 ? "1 career goal finished." : "\(career.finished) career goals finished.").textStyle(.caption)
            }
        }
        if e.ambitionVisible { ambition(e) }
    }

    private func level(_ e: GameEngine) -> some View {
        let info: PlayerLevel.Info = e.playerLevel
        return GoalsGroup(title: "Your level") {
            Button { Haptics.tap(); showLadder = true } label: {
                GoalsCard {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        HStack(spacing: Theme.Space.s) {
                            Text("Level \(info.level)").textStyle(.headline, numeric: true)
                            Spacer(minLength: Theme.Space.s)
                            Text(info.xpForNext == 0 ? "Max level" : "\(info.xpIntoLevel) / \(info.xpForNext) XP").textStyle(.caption, numeric: true)
                            LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
                        }
                        ProgressLine(fraction: info.progress, tint: Theme.gold, height: 5)
                        HomeNextUnlock(engine: e)
                    }
                    .frame(minHeight: 44)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Shows every level and what it unlocks")
            .accessibilityIdentifier("goals-level")
        }
        .levelLadderPopup(isPresented: $showLadder, engine: e)
    }

    private func rank(_ e: GameEngine) -> some View {
        let st: Career.RankStatus = e.careerStatus
        let line: String = st.next.map { "Next: \($0.title). \(st.missing)" } ?? "You are at the top of the ladder."
        return GoalsCard {
            HStack(spacing: Theme.Space.m) {
                GoalRing(progress: st.progress, done: st.next == nil, size: 52, label: "\(Int(saturating: (st.progress * 100).rounded()))%")
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(st.rank.title).textStyle(.headline)
                    Text(line).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
        }
    }

    private func ambition(_ e: GameEngine) -> some View {
        GoalsGroup(title: "Ambition", note: e.currentAmbition == nil ? "Choose what you want to build. Each path has its own milestones and a perk." : "") {
            if let path = e.currentAmbition, let name = e.ambitionPaths.first(where: { (p: Ambitions.Path) -> Bool in p.id == path })?.name {
                let ms: [Ambitions.Milestone] = e.ambitionMilestones(path: path)
                let count: Int = ms.filter { (m: Ambitions.Milestone) -> Bool in m.done != nil }.count
                let perk: String = e.ambitionPerk(path: path)
                GoalsCard {
                    HStack(spacing: Theme.Space.m) {
                        GoalRing(progress: ms.isEmpty ? 0 : Double(count) / Double(ms.count), done: !ms.isEmpty && count == ms.count)
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(name).textStyle(.headline)
                            Text("\(count) of \(ms.count) milestones").textStyle(.caption)
                            if !perk.isEmpty { Text("Perk: " + perk).textStyle(.caption, tint: Theme.accent).fixedSize(horizontal: false, vertical: true) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
                ForEach(ms, id: \.id) { (m: Ambitions.Milestone) in
                    let done: Bool = m.done != nil
                    GoalRowView(line: GoalLine(id: "amb-" + m.id, title: m.text, progress: done ? 1 : (m.target > 0 ? min(1, max(0, m.now / m.target)) : 0), done: done), claim: claim)
                }
            }
            Menu {
                ForEach(e.ambitionPaths, id: \.id) { (p: Ambitions.Path) in
                    Button(p.name + ": " + p.detail) {
                        let ok: Bool = store.act { $0.chooseAmbition(path: p.id) } ?? false
                        Haptics.tap(); store.show(ok ? "Your ambition: \(p.name)." : "You cannot switch ambition yet.", tone: ok ? "good" : "warn")
                    }
                }
            } label: {
                Text(e.currentAmbition == nil ? "Choose your ambition" : "Switch ambition").textStyle(.body, tint: Theme.accent, weight: .medium).frame(minHeight: 44)
            }
            .accessibilityIdentifier("ambition-choose")
        }
    }
}
