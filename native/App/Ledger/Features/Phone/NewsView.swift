import SwiftUI
import GameCore
import Simulation

struct NewsView: View {
    @EnvironmentObject var store: GameStore
    var body: some View {
        if let e = store.engine {
            ScrollView {
                Card {
                    LazyVStack(alignment: .leading, spacing: Theme.Space.m) {
                        if e.news.isEmpty { Text("No news yet.").font(.bodyText).foregroundStyle(Theme.ivoryMuted) }
                        ForEach(e.news) { n in
                            ListRow(symbol: n.tone == "bad" ? "exclamationmark.triangle.fill" : n.tone == "good" ? "arrow.up.right.circle.fill" : "newspaper.fill",
                                    tint: n.tone == "bad" ? Theme.loss : n.tone == "good" ? Theme.gain : Theme.ivoryMuted,
                                    title: n.text, subtitle: "Week \(n.week + 1)")
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("News")
        }
    }
}
