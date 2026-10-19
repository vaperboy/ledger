import SwiftUI
import GameCore
import Simulation

struct NewsView: View {
    @EnvironmentObject var store: GameStore
    var body: some View {
        if let e = store.engine {
            ScrollView {
                LazyVStack(spacing: Theme.Space.s) {
                    ForEach(e.news) { n in
                        Card(padding: Theme.Space.m) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Week \(n.week + 1)").font(.label).foregroundStyle(Theme.ivoryFaint)
                                Text(n.text).font(.bodyText).foregroundStyle(n.tone == "bad" ? Theme.loss : Theme.ivory)
                            }
                        }
                    }
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("News")
        }
    }
}
