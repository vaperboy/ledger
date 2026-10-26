import SwiftUI
import Simulation

/// More > Goals: the first-step rewards, today's goal and the chosen ambition. The claim buttons live in `GoalsCard` and report
/// the engine's result themselves.
struct GoalsView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        ScrollView {
            if let e = store.engine {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Text("What to aim for").font(.serifTitle(26)).foregroundStyle(Theme.ivory)
                    GoalsCard(engine: e)
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            } else {
                Text("No game is open.").font(.bodyText).foregroundStyle(Theme.ivoryMuted).padding(Theme.Space.margin)
            }
        }
        .ledgerBackground()
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.inline)
    }
}
