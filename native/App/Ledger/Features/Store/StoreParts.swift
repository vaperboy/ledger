import SwiftUI
import Simulation

// Small pieces shared by the Store, Box, Cabinet and Auction screens.

extension BoxRarity {
    /// Muted colours; the word always stays beside the colour.
    var tint: Color {
        switch self {
        case .common: return Theme.inkSoft
        case .rare: return Color(hex: 0x7F9BC4)
        case .epic: return Color(hex: 0xB59AD6)
        case .legendary: return Color(hex: 0xE0BC5E)
        }
    }
}

extension StoreError {
    /// A calm line for the "not enough gold" popup.
    var isShortOfGold: Bool { if case .notEnoughGold = self { return true }; return false }
}

enum StoreText {
    static func gold(_ n: Int) -> String { n == 1 ? "1 gold" : "\(n.formatted()) gold" }

    /// "1h 05m", "4m 12s", "Ended". Plain text, no urgency colours.
    static func timeLeft(_ seconds: Double) -> String {
        let s: Int = Int(seconds.rounded(.down))
        if s <= 0 { return "Ended" }
        if s >= 3_600 { return "\(s / 3_600)h \(String(format: "%02d", (s % 3_600) / 60))m" }
        if s >= 60 { return "\(s / 60)m \(String(format: "%02d", s % 60))s" }
        return "\(s)s"
    }

    static let goldRule = "Gold buys cosmetics, boxes and extra slots. It never buys in-game money and cannot be cashed out. Players pass gold to each other only through auctions, which take a \(AuctionRules.feePercent)% fee out of the economy."
}

/// A small tag: the rarity in its colour, always as a word.
struct RarityTag: View {
    var rarity: BoxRarity
    var body: some View { Text(rarity.title).textStyle(.caption, tint: rarity.tint, weight: .semibold) }
}

/// An amount of gold: a coin mark and the number.
struct GoldAmount: View {
    var amount: Int
    var style: TextStep = .headline
    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Circle().fill(Theme.gold).frame(width: 10, height: 10).accessibilityHidden(true)
            Text(amount.formatted()).textStyle(style, tint: Theme.ink, numeric: true)
            Text("gold").textStyle(.caption)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StoreText.gold(amount))
    }
}

/// One numbered piece: name, rarity, "14 of 500" and the collection it belongs to.
struct ArtifactRow: View {
    var item: ArtifactItem
    var trailing: String = ""

    var body: some View {
        let def: ArtifactDef? = ArtifactCatalog.def(item.defID)
        HStack(spacing: Theme.Space.m) {
            if let def { ItemArt(artifact: def, size: 40) }
            else { RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.inset).frame(width: 40, height: 40) }
            VStack(alignment: .leading, spacing: 2) {
                Text(def?.name ?? "Artifact").textStyle(.headline).lineLimit(2)
                HStack(spacing: Theme.Space.xs) {
                    if let r = def?.rarity { RarityTag(rarity: r) }
                    Text(ArtifactCatalog.label(item)).textStyle(.caption)
                }
            }
            Spacer(minLength: Theme.Space.s)
            if !trailing.isEmpty { Text(trailing).textStyle(.body, tint: Theme.inkSoft, numeric: true) }
        }
        .padding(.vertical, Theme.Space.s).frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }
}

/// The published odds of a box: every row with its exact percentage, the rarity totals, what gold the box holds on average, and the guarantee.
/// Shown on the store page and the box page, before anything is bought.
struct BoxOddsTable: View {
    var kind: BoxKind
    var showRows = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            let rarities: [(rarity: BoxRarity, percent: Double)] = BoxOdds.rarityPercent(kind)
            ForEach(0..<rarities.count, id: \.self) { (i: Int) in
                HStack {
                    RarityTag(rarity: rarities[i].rarity)
                    Spacer()
                    Text(String(format: "%.2f%%", rarities[i].percent)).textStyle(.body, numeric: true)
                }
                .accessibilityElement(children: .combine)
            }
            if showRows {
                Hairline()
                Text("Every prize").capsLabel(Theme.inkFaint)
                let lines: [(title: String, percent: Double)] = BoxOdds.disclosure(kind)
                ForEach(0..<lines.count, id: \.self) { (i: Int) in
                    HStack {
                        Text(lines[i].title).textStyle(.caption)
                        Spacer()
                        Text(String(format: "%.2f%%", lines[i].percent)).textStyle(.caption, numeric: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Hairline()
            Text(valueNote).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            if kind.isPaid {
                Text("A rare or better item is guaranteed at least once in every \(BoxPity.threshold) paid boxes.").textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var valueNote: String {
        let avg: Double = BoxOdds.expectedGold(kind)
        let avgText: String = String(format: "%.1f", avg)
        if kind.isPaid {
            return "Gold prizes are small: the most a gold prize holds is \(StoreText.gold(BoxOdds.largestGold(kind))), and on average a box returns \(avgText) gold for a price of \(StoreText.gold(kind.price)). Most of the value is in the cosmetics and artifacts."
        }
        let money: String = BoxOdds.moneyPercent(kind) > 0
            ? " Once in a while (\(String(format: "%.2f", BoxOdds.moneyPercent(kind)))% of boxes) it holds a small cash prize for your game account, never more than \(BoxOdds.largestMoney(kind)) in the reference economy; gold itself never turns into game money."
            : ""
        return "A free box holds a cosmetic, an artifact or a little gold, on average \(avgText) gold. About 1 in \(BoxOdds.totalWeight / BoxOdds.doubleGoldChance) gold prizes is doubled." + money
    }
}
