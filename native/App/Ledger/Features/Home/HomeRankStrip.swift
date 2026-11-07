import SwiftUI
import GameCore
import Events
import Simulation

/// The progress strip on Home, two tiles side by side. Career: the worn badge in a ring that fills towards the next rank, the share
/// done and the next rank's name (opens Goals). Today: the daily mission with its reward and the streak, a Claim when it is ready
/// (a small "+reward" rises on claim), else a tap opens where it is done.
struct HomeProgressStrip: View {
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CosmeticKeys.badge) private var badgeID: String = Cosmetics.defaultBadgeID
    @AppStorage(CosmeticKeys.theme) private var themeID: String = Cosmetics.defaultThemeID
    var engine: GameEngine

    @State private var daily: PlayerGoals.DailyGoal?
    @State private var shownProgress: Double = 0
    @State private var burst = false
    @State private var claimedText: String?
    @State private var claimRise = false

    var body: some View {
        let st: Career.RankStatus = store.memo("careerStatus") { $0.careerStatus } ?? engine.careerStatus
        let tick: Int = engine.state.week * 7 + engine.state.day
        HStack(alignment: .top, spacing: Theme.Space.s) {
            careerTile(st)
            missionTile
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { daily = store.dailyGoal(); fill(to: st.progress) }
        .onChange(of: st.progress) { _, v in fill(to: v) }
        .onChange(of: tick) { _, _ in daily = store.dailyGoal() }
        .onChange(of: st.rank.index) { old, new in rankChanged(from: old, to: new) }
    }

    private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.surface))
            .contentShape(Rectangle())
    }

    // MARK: Career

    private func careerTile(_ st: Career.RankStatus) -> some View {
        let accent: Color = Cosmetics.resolvedTheme(themeID, pro: ent.isPro).accent
        let badge: Cosmetics.Badge = Cosmetics.resolvedBadge(badgeID, earned: engine.careerCosmetics, pro: ent.isPro)
        return Button { Haptics.tap(); store.openApp(.goals) } label: {
            tile {
                HStack(spacing: Theme.Space.s) {
                    ZStack {
                        AccentRing(progress: shownProgress, tint: accent, size: 40)
                        CosmeticBadgeView(badge: badge, tint: accent, size: 24)
                    }
                    .scaleEffect(burst ? 1.18 : 1)
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        if st.next != nil {
                            CountUpPercent(value: shownProgress * 100).textStyle(.headline, numeric: true)
                        } else {
                            Text(st.rank.title).textStyle(.headline).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Text(st.next.map { (n: Career.Rank) -> String in "to " + n.title } ?? "Top rank").textStyle(.caption).lineLimit(2)
                    }
                }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(st.rank.title)" + (st.next.map { (n: Career.Rank) -> String in ", \(Int((st.progress * 100).rounded())) percent to " + n.title } ?? ""))
        .accessibilityIdentifier("home-rank-ring")
    }

    // MARK: Today's mission

    @ViewBuilder private var missionTile: some View {
        let streak: Int = PlayStreak.current(engine.state, today: GameStore.calendarDay())
        let ready: Bool = (daily?.done ?? false) && !(daily?.claimed ?? false)
        let claimed: Bool = daily?.claimed ?? false
        Button { missionTapped(ready: ready) } label: {
            tile {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    HStack(spacing: Theme.Space.xs) {
                        Text("Today").textStyle(.label, tint: Theme.inkFaint)
                        Spacer(minLength: Theme.Space.xs)
                        Image(systemName: "flame.fill").font(.caption).foregroundStyle(streak > 0 ? Theme.warn : Theme.inkFaint).accessibilityHidden(true)
                        Text("\(streak)").textStyle(.caption, tint: streak > 0 ? Theme.ink : Theme.inkFaint, numeric: true, weight: .semibold)
                    }
                    Text(daily?.title ?? "No mission today").textStyle(.body, tint: Theme.ink).lineLimit(2).multilineTextAlignment(.leading)
                    if let d = daily {
                        if ready {
                            Text("Claim " + store.short(d.reward)).textStyle(.caption, weight: .semibold)
                                .containerInk(Theme.accentInk)
                                .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.xxs)
                                .background(Capsule().fill(Theme.accent))
                                .accessibilityIdentifier("home-claim")
                        } else if claimed {
                            Text("Claimed").textStyle(.caption, tint: Theme.gain)
                        } else {
                            Text(d.progress.isEmpty ? "+" + store.short(d.reward) : d.progress + " · +" + store.short(d.reward))
                                .textStyle(.caption, numeric: true).lineLimit(1)
                        }
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if let t = claimedText {
                    Text(t).textStyle(.headline, tint: Theme.gain, numeric: true)
                        .offset(x: -Theme.Space.m, y: claimRise ? -22 : 6)
                        .opacity(claimRise ? 0 : 1)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel((daily?.title ?? "No mission today") + (ready ? ", ready to claim" : "") + ". Streak \(streak) days")
        .accessibilityIdentifier("home-mission")
    }

    private func missionTapped(ready: Bool) {
        if ready { claim(); return }
        Haptics.tap()
        if let link = daily?.link, !link.isEmpty, store.openLadderLink(link) { return }
        store.openApp(.goals)
    }

    /// Claims today's mission: a success haptic, and the reward rises and fades once over the tile.
    private func claim() {
        if let r = store.act({ (e: inout GameEngine) in e.claimDailyGoal() }) ?? nil {
            Haptics.success()
            daily = store.dailyGoal()
            claimedText = "+" + store.short(r)
            claimRise = false
            if reduceMotion {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { claimedText = nil }
            } else {
                Motion.animate(Motion.revealAnimation.delay(0.1)) { claimRise = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { claimedText = nil; claimRise = false }
            }
        } else {
            Haptics.warning()
            store.show("That mission cannot be claimed yet.", tone: "warn")
        }
    }

    private func fill(to target: Double) {
        let t: Double = HomeProgress.clamp(target)
        Motion.animate(Motion.reveal(reduceMotion)) { shownProgress = t }
    }

    /// A rank-up: the ring swells once (the celebration popup itself comes from the engine's queue).
    private func rankChanged(from old: Int, to new: Int) {
        guard new > old, !reduceMotion else { return }
        Motion.animate(Motion.moveAnimation) { burst = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            Motion.animate(Motion.moveAnimation) { burst = false }
        }
    }
}

/// The career goal closest to done, as one tappable line under net worth: its title, the share done and a thin bar.
struct HomeMilestoneLine: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        let goals: [Career.Goal] = store.memo("careerGoals") { $0.careerNextGoals } ?? engine.careerNextGoals
        if let g = goals.filter({ !$0.done }).max(by: { $0.progress < $1.progress }) {
            let f: Double = HomeProgress.clamp(g.progress)
            Button {
                Haptics.tap()
                if g.link.isEmpty || !store.openLadderLink(g.link) { store.openApp(.goals) }
            } label: {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    HStack(spacing: Theme.Space.s) {
                        Text(g.title.tidyMoney).textStyle(.caption, tint: Theme.ink).lineLimit(1)
                        Spacer(minLength: Theme.Space.s)
                        Text("\(Int((f * 100).rounded()))%").textStyle(.caption, tint: Theme.inkSoft, numeric: true)
                    }
                    ProgressLine(fraction: f, tint: Theme.gain, height: 3)
                }
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home-milestone")
        }
    }
}
