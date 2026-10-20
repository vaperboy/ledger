import SwiftUI
import GameCore
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
                    Card {
                        VStack(spacing: Theme.Space.m) {
                            row(.news, "newspaper.fill", "News", e.news.first?.text ?? "No news yet")
                            Hairline()
                            row(.stats, "chart.bar.fill", "Stats", "Best net worth " + store.short(max(e.state.stats.peakNetWorth, e.netWorth.total)) + " · week \(e.state.week + 1)")
                            Hairline()
                            row(.activity, "list.bullet.rectangle.fill", "Activity", e.state.statement.first.map { $0.label + " " + (($0.amount >= 0 ? "+" : "−") + store.short(abs($0.amount))) } ?? "Nothing has moved yet")
                            Hairline()
                            row(.luxury, "sparkles", "Luxury", e.luxuryPieces.isEmpty ? "Cars, watches, art, yachts, jets, homes and estates" : "\(e.luxuryPieces.count) pieces · worth " + store.short(e.luxuryValue))
                            Hairline()
                            row(.settings, "gearshape.fill", "Settings", "How much you decide, saving, haptics")
                        }
                    }
                    .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
                }
            }
            .ledgerBackground()
            .navigationTitle("Phone")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PhoneDestination.self) { dest in
                switch dest {
                case .news: NewsView()
                case .stats: StatsView()
                case .activity: ActivityView()
                case .luxury: LuxuryView()
                case .settings: SettingsView()
                }
            }
            .onAppear { openRequested() }
            .onChange(of: store.phoneDestination) { _, _ in openRequested() }
        }
    }

    private func row(_ dest: PhoneDestination, _ symbol: String, _ title: String, _ preview: String) -> some View {
        Button { Haptics.tap(); path.append(dest) } label: {
            ListRow(symbol: symbol, tint: Theme.ivoryMuted, title: title, subtitle: preview, chevron: true).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func openRequested() {
        if let d = store.phoneDestination { path = [d]; store.phoneDestination = nil }
    }
}
