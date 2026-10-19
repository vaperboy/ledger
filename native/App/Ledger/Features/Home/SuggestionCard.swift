import SwiftUI
import Simulation

/// The expandable quick-action card: the most important thing right now, and a list of the rest. Every row has a real action.
struct SuggestionCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var expanded = false

    var body: some View {
        let list = engine.suggestions(limit: 6)
        Card(padding: 0) {
            if list.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal").foregroundStyle(Theme.gain)
                    Text("Nothing needs you right now.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                    Spacer()
                }.padding(Theme.Space.l)
            } else {
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.snappy(duration: 0.28)) { expanded.toggle() }
                        Haptics.tap()
                    } label: {
                        HStack(spacing: 8) {
                            SectionLabel(list.count == 1 ? "1 thing to look at" : "\(list.count) things to look at")
                            Spacer()
                            Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Theme.ivoryFaint)
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                        }
                        .padding(.horizontal, Theme.Space.l).padding(.top, Theme.Space.m).padding(.bottom, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    SuggestionRow(item: list[0])
                    if expanded {
                        ForEach(list.dropFirst()) { item in
                            Divider().overlay(Theme.hairline).padding(.leading, Theme.Space.l)
                            SuggestionRow(item: item)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }
}

struct SuggestionRow: View {
    @EnvironmentObject var store: GameStore
    var item: Suggestion
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.symbol).font(.title3).foregroundStyle(color).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(.subheadline, design: .serif).weight(.semibold)).foregroundStyle(Theme.ivory)
                Text(item.detail).font(.caption).foregroundStyle(Theme.ivoryMuted).lineLimit(3)
            }
            Spacer(minLength: 8)
            Button(item.actionLabel) { store.go(item.action) }.buttonStyle(QuietButtonStyle(tint: color))
        }
        .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.m)
    }
    private var color: Color {
        switch item.tone { case .bad: return Theme.loss; case .warn: return Theme.caution; case .good: return Theme.gain; case .neutral: return Theme.gold }
    }
}
