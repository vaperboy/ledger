import SwiftUI
import Simulation

/// More > Goals: the first steps for a new player, today's goal and the chosen ambition (moved off the Company tab's home summary).
struct GoalsView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        ScrollView {
            if let e = store.engine {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    GoalsCard(engine: e)
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
        }
        .ledgerBackground()
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.inline)
    }
}
