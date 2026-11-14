import SwiftUI
import Simulation

/// Buying colours used inside the Store only; the rest of the app keeps its own palette.
enum StoreColors {
    static let purple = Color(hex: 0x8E3BF0)
    static let violet = Color(hex: 0x5B2BC9)
    static let blue = Color(hex: 0x2F6BF2)
    static let cyan = Color(hex: 0x1FB5E0)
    static let green = Color(hex: 0x22B45A)
    static let orange = Color(hex: 0xF27A1A)
    static let red = Color(hex: 0xE5304A)
    static let pink = Color(hex: 0xEC3D8C)
    static let yellow = Color(hex: 0xFFD23C)
    static let priceInk = Color(hex: 0x1B1530)
    static let night = Color(hex: 0x1B1530)

    static func gradient(_ c: Color) -> LinearGradient {
        LinearGradient(colors: [c, c.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension BoxRarity {
    /// The bright card colour of a rarity on the Store shelf.
    var storeTint: Color {
        switch self {
        case .common: return StoreColors.blue
        case .rare: return StoreColors.cyan
        case .epic: return StoreColors.purple
        case .legendary: return StoreColors.orange
        }
    }
}

/// One thing an offer gives, drawn as a coloured icon with its amount.
struct StoreReward: Identifiable {
    enum Kind { case gold, box, money, cosmetic, tier, card, premium, slot }
    var kind: Kind
    var amount: String
    var caption: String = ""
    var id: String { "\(kind)" + amount + caption }

    var tint: Color {
        switch kind {
        case .gold: return StoreColors.yellow
        case .box: return StoreColors.orange
        case .money: return StoreColors.green
        case .cosmetic: return StoreColors.purple
        case .tier: return StoreColors.cyan
        case .card: return StoreColors.blue
        case .premium: return StoreColors.pink
        case .slot: return StoreColors.violet
        }
    }

    var symbol: String {
        switch kind {
        case .gold: return "circle.circle.fill"
        case .box: return "shippingbox.fill"
        case .money: return "banknote.fill"
        case .cosmetic: return "tshirt.fill"
        case .tier: return "star.fill"
        case .card: return "rectangle.portrait.fill"
        case .premium: return "crown.fill"
        case .slot: return "square.stack.3d.up.fill"
        }
    }

    static func gold(_ n: Int) -> StoreReward { StoreReward(kind: .gold, amount: "+\(n.formatted())", caption: "gold") }
    static func boxes(_ n: Int, _ kind: BoxKind) -> StoreReward { StoreReward(kind: .box, amount: "+\(n)", caption: kind.title) }
}

/// A reward as the Store shows it everywhere: a big coloured icon, the amount in bold under it.
struct RewardIcon: View {
    var reward: StoreReward
    var size: CGFloat = 46

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(StoreColors.gradient(reward.tint))
                if reward.kind == .gold {
                    StoreCoin(size: size * 0.62)
                } else {
                    Image(systemName: reward.symbol).font(.system(size: size * 0.46, weight: .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            Text(reward.amount).font(.headline.weight(.heavy)).monospacedDigit().foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            if !reward.caption.isEmpty {
                Text(reward.caption).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(minWidth: size + 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reward.amount + " " + reward.caption)
    }
}

/// Just the coloured tile of a reward, for places that print the amount themselves.
struct RewardTile: View {
    var kind: StoreReward.Kind
    var size: CGFloat

    var body: some View {
        let r = StoreReward(kind: kind, amount: "")
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(StoreColors.gradient(r.tint))
            if kind == .gold { StoreCoin(size: size * 0.62) } else { Image(systemName: r.symbol).font(.system(size: size * 0.46, weight: .bold)).foregroundStyle(.white) }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "You get" and a row of reward icons.
struct RewardStrip: View {
    var rewards: [StoreReward]
    var size: CGFloat = 46

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOU GET").font(.caption.weight(.heavy)).foregroundStyle(.white.opacity(0.8))
            HStack(alignment: .top, spacing: 10) {
                ForEach(rewards) { (r: StoreReward) in RewardIcon(reward: r, size: size) }
                Spacer(minLength: 0)
            }
        }
    }
}

/// A big yellow price button: a gold price, or any label such as an App Store price.
struct StorePriceLabel: View {
    var text: String
    var gold: Bool = false
    var minHeight: CGFloat = 48

    var body: some View {
        HStack(spacing: 6) {
            if gold { StoreCoin(size: 20) }
            Text(text).font(.title3.weight(.heavy)).monospacedDigit().foregroundStyle(StoreColors.priceInk).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(StoreColors.yellow))
    }
}

/// The time left on a real deadline, as "Ends in 5h 12m".
struct StoreTimer: View {
    var ends: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tl in
            let s: Double = ends.timeIntervalSince(tl.date)
            HStack(spacing: 4) {
                Image(systemName: "timer").font(.caption.weight(.bold))
                Text("Ends in " + StoreTimer.text(s)).font(.caption.weight(.heavy)).monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.3)))
        }
    }

    static func text(_ seconds: Double) -> String {
        let m: Int = max(0, Int(seconds / 60))
        if m >= 1_440 { return "\(m / 1_440)d \((m % 1_440) / 60)h" }
        if m >= 60 { return "\(m / 60)h \(m % 60)m" }
        return "\(max(1, m))m"
    }

    /// The next server day starts at midnight UTC.
    static var nextServerDay: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let now: Date = TrustedClock.now()
        return cal.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
    }
}

/// A full-width offer card: a clear title on a bright band, what you get as big icons, a timer only when real,
/// and a big price button.
struct StoreOfferCard<Price: View>: View {
    var title: String
    var line: String = ""
    var tint: Color
    var tag: String? = nil
    var ends: Date? = nil
    var rewards: [StoreReward]
    @ViewBuilder var price: () -> Price

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased()).font(.title2.weight(.black)).italic().foregroundStyle(.white)
                        .lineLimit(2).minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
                    if !line.isEmpty { Text(line).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.9)).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: Theme.Space.s)
                if let tag { StoreTag(text: tag, tint: StoreColors.yellow) }
            }
            if let ends { StoreTimer(ends: ends) }
            if !rewards.isEmpty { RewardStrip(rewards: rewards) }
            price()
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(StoreColors.gradient(tint)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .padding(.horizontal, Theme.Space.m)
    }
}

/// The open Supporter badge on player cards.
enum SupporterBadge {
    static let name = "Supporter"
}

struct SupporterMark: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "heart.fill").font(.caption2.weight(.bold))
            Text(SupporterBadge.name).font(.caption2.weight(.heavy))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(StoreColors.pink))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SupporterBadge.name)
        .accessibilityIdentifier("supporter-mark")
    }
}
