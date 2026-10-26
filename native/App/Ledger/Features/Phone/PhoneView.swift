import SwiftUI
import GameCore
import Events
import Simulation

/// The rest of the game, used less often: news, your record, the account log and settings. Each row shows its latest line, so
/// most visits end here without opening anything.
struct PhoneView: View {
    @EnvironmentObject var store: GameStore
    @State private var path: [PhoneDestination] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if let e = store.engine {
                    let nw = e.netWorth.total
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        KeyFigures(items: [
                            .init(label: "Net worth", value: store.short(nw), tint: nw < 0 ? Theme.loss : Theme.ivory),
                            .init(label: "Best so far", value: store.short(max(e.state.stats.peakNetWorth, nw))),
                            .init(label: "Week", value: "\(e.state.week + 1)")
                        ])
                        LedgerSection("Play") {
                            VStack(spacing: 0) {
                                row(.goals, goalsLine(e), accent: goalsOpen(e))
                                Hairline()
                                row(.news, e.news.first?.text ?? "No news yet")
                                Hairline()
                                row(.worldAround, "Public image, people you know, favours and maps")
                            }
                        }
                        LedgerSection("Your record") {
                            VStack(spacing: 0) {
                                row(.stats, "Best net worth " + store.short(max(e.state.stats.peakNetWorth, nw)) + " · week \(e.state.week + 1)")
                                Hairline()
                                row(.achievements, achievementsLine(e))
                                Hairline()
                                row(.richList, richLine(e))
                                Hairline()
                                row(.ranking, rankingLine(e))
                                Hairline()
                                row(.activity, e.state.statement.first.map { $0.label + " " + (($0.amount >= 0 ? "+" : "−") + store.short(abs($0.amount))) } ?? "Nothing has moved yet")
                                Hairline()
                                row(.luxury, e.luxuryPieces.isEmpty ? "Cars, watches, art, yachts, jets, homes and estates" : "\(e.luxuryPieces.count) pieces · worth " + store.short(e.luxuryValue))
                            }
                        }
                        LedgerSection("This device") {
                            row(.settings, "How much you decide, saving, haptics")
                        }
                    }
                    .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
                } else {
                    Text("No game is open.").font(.bodyText).foregroundStyle(Theme.ivoryMuted).padding(Theme.Space.margin)
                }
            }
            .ledgerBackground()
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { store.showPhone = false } } }
            .navigationDestination(for: PhoneDestination.self) { dest in
                switch dest {
                case .goals: GoalsView()
                case .news: NewsView()
                case .stats: StatsView()
                case .activity: ActivityView()
                case .luxury: LuxuryView()
                case .settings: SettingsView()
                case .achievements: AchievementsView()
                case .richList: RichListView()
                case .ranking: RankingView()
                case .worldAround: WorldAroundView()
                }
            }
            .onAppear { openRequested() }
            .onChange(of: store.phoneDestination) { _, _ in openRequested() }
        }
    }

    /// A row that opens a page: the chevron says it can be tapped; champagne marks one with something waiting.
    private func row(_ dest: PhoneDestination, _ preview: String, accent: Bool = false) -> some View {
        Button { Haptics.tap(); path.append(dest) } label: {
            ListRow(symbol: dest.symbol, tint: accent ? Theme.gold : Theme.ivoryMuted, title: dest.title, subtitle: preview, chevron: true).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func goalsOpen(_ e: GameEngine) -> Bool {
        !e.firstStepRewardsHidden && (e.firstStepRewards ?? []).contains { !$0.done }
    }

    private func goalsLine(_ e: GameEngine) -> String {
        let left = e.firstStepRewardsHidden ? 0 : (e.firstStepRewards ?? []).filter { !$0.done }.count
        return left > 0 ? "\(left) first \(left == 1 ? "step" : "steps") to go" : (e.currentAmbition == nil ? "Choose what you want to build" : "Daily goal and your ambition")
    }
    private func achievementsLine(_ e: GameEngine) -> String {
        let all = Trophies.entries(e.state)
        return "\(all.filter { $0.reachedWeek != nil }.count) of \(all.count) trophies · \(Awards.wonCount(e.state)) awards"
    }
    private func richLine(_ e: GameEngine) -> String {
        let st = RichList.standing(e.state, data: e.data, context: e.context)
        return st.rank.map { "You are number \($0.formatted()) in \(e.homeCountry.name)" } ?? "Not on the list yet"
    }

    private func rankingLine(_ e: GameEngine) -> String {
        guard let r = e.yourRanking() else { return "Appears once you run a business" }
        return "You are number \(r.rank.formatted()) of \(r.of.formatted()) in \(e.homeCountry.name) by sales"
    }

    private func openRequested() {
        if let d = store.phoneDestination { path = [d]; store.phoneDestination = nil }
    }
}
