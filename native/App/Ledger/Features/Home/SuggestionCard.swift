import SwiftUI
import Simulation

/// The most important thing right now as an alert card, with the rest behind a tap. Every row has a real action.
struct SuggestionCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var expanded = false

    var body: some View {
        let list = engine.suggestions(limit: 6)
        Card(padding: 0) {
            if list.isEmpty {
                HStack(spacing: 12) {
                    IconBadge(symbol: "checkmark.seal", tint: Theme.gain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("All clear").font(.bodyText.weight(.semibold)).foregroundStyle(Theme.ivory)
                        Text("Nothing needs you right now.").font(.caption).foregroundStyle(Theme.ivoryMuted)
                    }
                    Spacer()
                }.padding(Theme.Space.l)
            } else {
                VStack(spacing: 0) {
                    SuggestionRow(item: list[0])
                    if list.count > 1 {
                        Button {
                            withAnimation(.snappy(duration: 0.28)) { expanded.toggle() }
                            Haptics.tap()
                        } label: {
                            HStack(spacing: 6) {
                                Text(expanded ? "Show less" : "\(list.count - 1) more to look at").font(.caption.weight(.semibold))
                                Image(systemName: "chevron.down").font(.caption2.weight(.bold)).rotationEffect(.degrees(expanded ? 180 : 0))
                            }
                            .foregroundStyle(Theme.ivoryMuted)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .overlay(alignment: .top) { Divider().overlay(Theme.hairline) }
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if expanded {
                        ForEach(list.dropFirst()) { item in
                            Divider().overlay(Theme.hairline)
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
        Button { Haptics.tap(); store.go(item.action) } label: {
            HStack(alignment: .center, spacing: 12) {
                IconBadge(symbol: item.symbol, tint: color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.bodyText.weight(.semibold)).foregroundStyle(Theme.ivory).multilineTextAlignment(.leading)
                    Text(item.detail).font(.caption).foregroundStyle(Theme.ivoryMuted).lineLimit(3).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                VStack(spacing: 2) {
                    Text(item.actionLabel).font(.caption2.weight(.semibold)).foregroundStyle(color)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.ivoryFaint)
                }
            }
            .padding(Theme.Space.l)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private var color: Color {
        switch item.tone { case .bad: return Theme.loss; case .warn: return Theme.caution; case .good: return Theme.gain; case .neutral: return Theme.gold }
    }
}
