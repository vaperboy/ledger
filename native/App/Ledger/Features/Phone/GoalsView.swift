import SwiftUI
import Simulation

/// Goals app: the first-step rewards, today's goal and the chosen ambition. The claim buttons live in `GoalsCard` and report
/// the engine's result themselves.
struct GoalsView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        ScrollView {
            if let e = store.engine {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    GoalsCard(engine: e)
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            } else {
                Text("No game is open.").font(.bodyText).foregroundStyle(Theme.ivoryMuted).padding(Theme.Space.margin)
            }
        }
        .scrollIndicators(.hidden)
        .ledgerBackground()
    }
}
