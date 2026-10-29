import SwiftUI
import Simulation

/// A guide for new players. Steps tick off from what really happened in the game; there are no rewards.
struct FirstStepsCard: View {
    var engine: GameEngine
    @State private var collapsed = false

    var body: some View {
        let steps = engine.firstSteps()
        let done = steps.filter { $0.done }.count
        if done < steps.count {
            LedgerSection(title: "First steps", trailing: {
                Button { withAnimation(.snappy) { collapsed.toggle() } } label: {
                    Text("\(done) of \(steps.count)  \(collapsed ? "›" : "⌄")").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }.buttonStyle(.plain)
            }) {
                if !collapsed {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(steps) { s in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: s.done ? "checkmark" : "circle").font(.system(size: 11, weight: .semibold)).foregroundStyle(s.done ? Theme.gain : Theme.ivoryFaint).frame(width: 16).padding(.top, 3)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.title).font(.system(size: 13.5)).foregroundStyle(s.done ? Theme.ivoryMuted : Theme.ivory).strikethrough(s.done, color: Theme.ivoryFaint)
                                    if !s.done { Text(s.detail).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
