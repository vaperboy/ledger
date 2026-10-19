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
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Button { withAnimation(.snappy) { collapsed.toggle() } } label: {
                        HStack {
                            SectionLabel("First steps")
                            Spacer()
                            Text("\(done) of \(steps.count)").font(.label).foregroundStyle(Theme.ivoryMuted)
                            Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Theme.ivoryFaint).rotationEffect(.degrees(collapsed ? -90 : 0))
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    ProgressView(value: Double(done), total: Double(steps.count)).tint(Theme.gold)
                    if !collapsed {
                        ForEach(steps) { s in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: s.done ? "checkmark.circle.fill" : "circle").foregroundStyle(s.done ? Theme.gain : Theme.ivoryFaint)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.title).font(.bodyText.weight(.medium)).foregroundStyle(s.done ? Theme.ivoryMuted : Theme.ivory).strikethrough(s.done, color: Theme.ivoryFaint)
                                    if !s.done { Text(s.detail).font(.caption).foregroundStyle(Theme.ivoryFaint) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
