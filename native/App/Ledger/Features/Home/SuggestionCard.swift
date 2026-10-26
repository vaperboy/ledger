import SwiftUI
import Simulation

/// What needs the player, worst first: a ruled section with a row per finding. Every row has a real action.
struct SuggestionCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var expanded = false

    var body: some View {
        let list = engine.suggestions(limit: 6)
        let shown = expanded ? list : Array(list.prefix(3))
        LedgerSection(title: list.isEmpty ? "All clear" : "Priorities", trailing: {
            if list.count > 3 {
                Button { withAnimation(.snappy(duration: 0.28)) { expanded.toggle() }; Haptics.tap() } label: {
                    Text(expanded ? "Show fewer" : "\(list.count) findings").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }.buttonStyle(.plain)
            }
        }) {
            if list.isEmpty {
                Text("Nothing needs you right now.").font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, item in
                        SuggestionRow(item: item)
                        if i < shown.count - 1 { Hairline() }
                    }
                    Button { Haptics.tap(); store.jump(to: .inbox) } label: {
                        HStack(spacing: 4) {
                            Text("See all in Inbox").font(.system(size: 13, weight: .medium))
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Theme.gold).padding(.top, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain)
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
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.symbol).font(.system(size: 14)).foregroundStyle(color).frame(width: 18).padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title.tidyMoney).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).multilineTextAlignment(.leading)
                    Text(item.detail.tidyMoney).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).lineLimit(3).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.actionLabel).font(.system(size: 11.5)).foregroundStyle(Theme.gold)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ivoryFaint)
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityIdentifier({ if case .openCompany = item.action { return "suggestion-open-company" } else { return "suggestion-row" } }())
    }
    private var color: Color {
        switch item.tone { case .bad: return Theme.loss; case .warn: return Theme.caution; case .good: return Theme.gain; case .neutral: return Theme.gold }
    }
}
