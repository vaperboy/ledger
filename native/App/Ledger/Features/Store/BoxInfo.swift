import SwiftUI
import Simulation

struct LootInfoButton: View {
    var action: () -> Void

    var body: some View {
        Button { Haptics.tap(); action() } label: {
            Image(systemName: "info.circle").font(.system(size: 20, weight: .regular)).foregroundStyle(Theme.inkSoft)
                .frame(width: 44, height: 44).contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Odds and rules")
        .accessibilityIdentifier("box-info")
    }
}

struct LootBoxInfoSheet: View {
    var kind: BoxKind
    var others: [BoxKind] = []

    var body: some View {
        ScrollView {
            LootBoxInfoContent(kind: kind, others: others)
                .padding(.horizontal, PopupLayout.inset).padding(.bottom, PopupLayout.inset)
        }
    }
}

struct LootBoxInfoContent: View {
    var kind: BoxKind
    var others: [BoxKind] = []
    private let session = StoreSession.shared

    static let rules: [String] = [
        "Boxes are opened with gold. Gold is bought with real money through the App Store: the price is shown and you confirm before anything is charged.",
        "Gold has no cash value, cannot be cashed out and never turns into in-game money. A box can also hold a cash prize in the game's money, paid into your personal account, and numbered artifacts you can sell at once or at auction for cash.",
        "These are the exact odds used for every opening. They do not change with how much you spend or how often you open.",
        "A cosmetic you already own is replaced by an artifact of the same rarity, so no opening is wasted.",
        "Card packs hold only profile cards and company cards. Cards are numbered like artifacts, can be sold at auction, and a company card is used by one company at a time. A pricier pack has a better chance of rare, epic and animated cards. The odds above are exact and do not change with how much you spend.",
        "Loot boxes are for players aged 18 or older, which you confirmed when you accepted the terms. They are not offered where the law restricts them.",
        "Refunds for gold purchases follow Apple's refund policy and the consumer law where you live.",
        "Spend only what you are comfortable with.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Odds, \(kind.title)").capsLabel(Theme.inkFaint)
                BoxOddsTable(kind: kind)
            }
            ForEach(others, id: \.self) { (other: BoxKind) in
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Odds, \(other.title)").capsLabel(Theme.inkFaint)
                    BoxOddsTable(kind: other)
                }
            }
            if kind.isPaid {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Guaranteed rare").capsLabel(Theme.inkFaint)
                    Text(session.state.pity.text).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Rules").capsLabel(Theme.inkFaint)
                ForEach(Array(Self.rules.enumerated()), id: \.offset) { (_: Int, line: String) in
                    Text(line).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
