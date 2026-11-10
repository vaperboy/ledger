import Foundation
import GameCore

public struct SeasonReward: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case badge, theme, namePlate, backdrop, saveSlot, advisorLine, richListFlair, tradePlate
        case box, gold
        case profileCard, companyCard
        case artifact, xp
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
            case .artifact: return "Artifact"
            case .xp: return "XP boost"
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
    public var season: Int = 1
    public var theme: String = ItemThemes.classicID
    public var founderEdition: Bool = false
    public var accountBound: Bool = false
    public var rarity: BoxRarity?
}

public enum SeasonRewards {
    public static let all: [SeasonReward] = SeasonCatalog.all.flatMap { (s: SeasonDef) -> [SeasonReward] in s.rewards }

    static func parse(_ e: JSONValue, season: Int, theme: String, founder: Bool) -> SeasonReward {
        var r: SeasonReward = entry(e)
        r.season = season
        if r.kind == .profileCard || r.kind == .companyCard, let d = CardCatalog.def(r.id) {
            r.theme = d.theme
            r.founderEdition = d.founderEdition
        } else {
            r.theme = ItemThemes.id(e, fallback: theme)
            r.founderEdition = e["founderEdition"].isNull ? founder : e["founderEdition"].bool
        }
        r.accountBound = e["bound"].bool
        if r.kind == .profileCard || r.kind == .companyCard || r.kind == .artifact {
            r.rarity = CardCatalog.def(r.id)?.rarity ?? ArtifactCatalog.defs.first(where: { (d: ArtifactDef) -> Bool in d.id == r.id })?.rarity
        } else if !e["rarity"].isNull {
            r.rarity = ContentFile.rarity(e["rarity"].string)
        }
        return r
    }

    private static func entry(_ e: JSONValue) -> SeasonReward {
        let id: String = e["id"].string
        let tier: Int = e["tier"].int
        let prem: Bool = e["premium"].bool
        switch e["kind"].string {
        case "card": return k(e["card"].string, tier, prem)
        case "box": return b(id, tier, prem, e["amount"].int)
        case "gold": return g(id, tier, prem, e["amount"].int)
        case "artifact": return a(e["artifact"].string, tier, prem)
        case "xp": return x(id, tier, prem, e["amount"].int)
        default:
            return SeasonReward(id: id, tier: tier, premium: prem, kind: SeasonReward.Kind(rawValue: e["kind"].string) ?? .badge,
                                title: e["title"].string, detail: e["detail"].string, colors: ContentFile.colors(e["colors"]))
        }
    }

    public static func reward(_ track: SeasonPass.Track, tier: Int, season: Int = 1) -> SeasonReward? {
        SeasonCatalog.active(season)?.rewards.first { $0.tier == tier && $0.premium == (track == .premium) }
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

    private static func a(_ defID: String, _ tier: Int, _ prem: Bool) -> SeasonReward {
        let d: ArtifactDef? = ArtifactCatalog.defs.first { $0.id == defID }
        return SeasonReward(id: defID, tier: tier, premium: prem, kind: .artifact, title: d?.name ?? "Artifact",
                            detail: (d?.note ?? "") + " It joins your cabinet as a numbered piece and can be sold at auction.")
    }

    private static func x(_ id: String, _ tier: Int, _ prem: Bool, _ xp: Int) -> SeasonReward {
        SeasonReward(id: id, tier: tier, premium: prem, kind: .xp, title: "\(xp) XP boost",
                     detail: "Added to your Season Pass XP at once. It lifts you towards the next tier and ignores the daily cap.", amount: xp)
    }

    private static func g(_ id: String, _ tier: Int, _ prem: Bool, _ gold: Int) -> SeasonReward {
        SeasonReward(id: id, tier: tier, premium: prem, kind: .gold, title: "\(gold) gold",
                     detail: "Gold buys cosmetics, boxes and comfort in the Store. It never buys in-game money.", amount: gold)
    }
}
