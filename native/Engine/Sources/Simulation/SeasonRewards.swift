import Foundation
import GameCore

public struct SeasonReward: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case badge, theme, namePlate, backdrop, saveSlot, advisorLine, richListFlair, tradePlate
        case box, gold
        case profileCard, companyCard
        public var isEquippable: Bool { self == .theme || self == .namePlate || self == .backdrop || self == .richListFlair || self == .tradePlate }
        public var label: String {
            switch self {
            case .badge: return "Badge"
            case .theme: return "App theme"
            case .namePlate: return "Name plate"
            case .backdrop: return "Backdrop"
            case .saveSlot: return "Save slot"
            case .advisorLine: return "Advisor line"
            case .richListFlair: return "Rich-list flair"
            case .tradePlate: return "Trade-name plate"
            case .box: return "Box"
            case .gold: return "Gold"
            case .profileCard: return "Profile card"
            case .companyCard: return "Company card"
            }
        }
    }
    public var id: String
    public var tier: Int
    public var premium: Bool
    public var kind: Kind
    public var title: String
    public var detail: String
    public var colors: [UInt32] = []
    public var amount: Int = 0
}

public enum SeasonRewards {
    public static let all: [SeasonReward] = ContentFile.load("season", "season_1")["rewards"].array.map { (e: JSONValue) -> SeasonReward in SeasonRewards.entry(e) }

    private static func entry(_ e: JSONValue) -> SeasonReward {
        let id: String = e["id"].string
        let tier: Int = e["tier"].int
        let prem: Bool = e["premium"].bool
        switch e["kind"].string {
        case "card": return k(e["card"].string, tier, prem)
        case "box": return b(id, tier, prem, e["amount"].int)
        case "gold": return g(id, tier, prem, e["amount"].int)
        default:
            return SeasonReward(id: id, tier: tier, premium: prem, kind: SeasonReward.Kind(rawValue: e["kind"].string) ?? .badge,
                                title: e["title"].string, detail: e["detail"].string, colors: ContentFile.colors(e["colors"]))
        }
    }

    public static func reward(_ track: SeasonPass.Track, tier: Int) -> SeasonReward? {
        all.first { $0.tier == tier && $0.premium == (track == .premium) }
    }

    private static func b(_ id: String, _ tier: Int, _ prem: Bool, _ count: Int) -> SeasonReward {
        SeasonReward(id: id, tier: tier, premium: prem, kind: .box, title: count == 1 ? "Season box" : "\(count) Season boxes",
                     detail: "Free to open in the Store; it holds a cosmetic, an artifact, a little gold or, rarely, cash. Odds are shown before you open it.", amount: count)
    }

    private static func k(_ defID: String, _ tier: Int, _ prem: Bool) -> SeasonReward {
        let d: CardDef? = CardCatalog.def(defID)
        let company: Bool = d?.kind == .company
        return SeasonReward(id: defID, tier: tier, premium: prem, kind: company ? .companyCard : .profileCard, title: d?.name ?? "Card",
                            detail: (company ? "A numbered company card with its own colours and logo. " : "A numbered profile card for your profile page. ") + "It joins your cabinet, can be sold at auction, and is set in Your look.",
                            colors: d?.colors ?? [])
    }

    private static func g(_ id: String, _ tier: Int, _ prem: Bool, _ gold: Int) -> SeasonReward {
        SeasonReward(id: id, tier: tier, premium: prem, kind: .gold, title: "\(gold) gold",
                     detail: "Gold buys cosmetics, boxes and comfort in the Store. It never buys in-game money.", amount: gold)
    }
}
