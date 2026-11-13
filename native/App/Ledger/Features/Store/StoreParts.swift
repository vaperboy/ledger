import SwiftUI
import Simulation

extension BoxRarity {
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
    var isShortOfGold: Bool { if case .notEnoughGold = self { return true }; return false }
}

enum StoreText {
    static func gold(_ n: Int) -> String { n == 1 ? "1 gold" : "\(n.formatted()) gold" }

    static func timeLeft(_ seconds: Double) -> String {
        let s: Int = Int(saturating: seconds.rounded(.down))
        if s <= 0 { return "Ended" }
        if s >= 3_600 { return "\(s / 3_600)h \(String(format: "%02d", (s % 3_600) / 60))m" }
        if s >= 60 { return "\(s / 60)m \(String(format: "%02d", s % 60))s" }
        return "\(s)s"
    }

    static let goldRule = "Gold buys cosmetics, boxes, extra slots and in-game money. It cannot be cashed out, and money bought with gold stays in the game. Artifacts are traded for cash in auctions, which take a \(AuctionRules.feePercent)% fee out of the economy."
}

struct RarityTag: View {
    var rarity: BoxRarity
    var body: some View { Text(rarity.title).textStyle(.caption, tint: rarity.tint, weight: .semibold) }
}

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

struct LockNote: View {
    var text: String

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "lock.fill").font(.caption.weight(.semibold))
            Text(text).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.inkSoft)
        .accessibilityElement(children: .combine)
    }
}

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
                    if item.isFirstOwner { Text("First owner").textStyle(.caption, tint: Theme.gold, weight: .semibold) }
                    if item.isBound { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Theme.inkFaint).accessibilityLabel("Bound to your account") }
                }
            }
            Spacer(minLength: Theme.Space.s)
            if !trailing.isEmpty { Text(trailing).textStyle(.body, tint: Theme.inkSoft, numeric: true) }
        }
        .padding(.vertical, Theme.Space.s).frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }
}

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
        if kind.isCardPack {
            return "A card pack holds one card and no gold or cash. About \(String(format: "%.1f", BoxOdds.animatedPercent(kind)))% of these packs hold an animated card. The pack costs \(StoreText.gold(kind.price)); the cards are numbered and can be sold at auction for cash."
        }
        let avg: Double = BoxOdds.expectedGold(kind)
        let avgText: String = String(format: "%.1f", avg)
        let money: String = BoxOdds.moneyPercent(kind) > 0
            ? " About \(String(format: "%.2f", BoxOdds.moneyPercent(kind)))% of boxes hold a cash prize for your game account, never more than \(BoxOdds.largestMoney(kind)) in the reference economy (scaled to your country's money). Gold can also buy game money in the Store, but a prize is never turned into gold."
            : ""
        if kind.isPaid {
            return "Gold prizes are small: the most a gold prize holds is \(StoreText.gold(BoxOdds.largestGold(kind))), and on average a box returns \(avgText) gold for a price of \(StoreText.gold(kind.price)). The value is in the cosmetics, the artifacts you can sell at auction for cash, and now and then a cash prize." + money
        }
        return "A free box holds a cosmetic, an artifact, a little gold or, rarely, cash. On average it holds \(avgText) gold, and about 1 in \(BoxOdds.totalWeight / BoxOdds.doubleGoldChance) gold prizes is doubled." + money
    }
}
