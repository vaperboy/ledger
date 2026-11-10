import SwiftUI
import GameCore
import Simulation

struct AvatarDef: Identifiable, Equatable {
    enum Unlock: Equatable {
        case free
        case gold
        case rank(Int)
        case pro
        case plus
        case proOwner
        case founder
        case badge(String)
        case collection(String)
        case level(Int)
        case season(String)
    }

    var id: String
    var title: String
    var tier: BoxRarity
    var unlock: Unlock
    var spec: EmblemSpec

    var price: Int? { unlock == .gold ? GoldCosmetics.storePrice(tier) : nil }

    var requirement: String {
        switch unlock {
        case .free: return "Free"
        case .gold: return "Bought with gold"
        case .rank(let i): return "Reach the rank " + (i < Career.ranks.count ? Career.ranks[i].title : "of a tycoon")
        case .pro: return "Ledger Pro"
        case .plus: return "Ledger Plus"
        case .proOwner: return "Ledger Pro"
        case .founder: return "Founder's Edition"
        case .badge(let b): return "Earn the " + Cosmetics.badge(b).title.lowercased() + " badge in Goals"
        case .collection(let c): return "Complete the " + (ArtifactCatalog.collection(c)?.name ?? "") + " collection"
        case .level(let n): return "Reach level \(n)"
        case .season(let id): return "Claim " + (SeasonRewards.item(id)?.title ?? "the reward") + " in the Season Pass"
        }
    }
}

enum AvatarCatalog {
    static let all: [AvatarDef] = AppContent.load("avatars", "avatars")["avatars"].array.map { (e: JSONValue) -> AvatarDef in
        AvatarDef(id: e["id"].string, title: e["title"].string, tier: ContentFile.rarity(e["tier"].string), unlock: unlock(e["unlock"].string, e["value"]),
                  spec: EmblemSpec(symbol: e["symbol"].string, badge: e["badge"].isNull ? nil : e["badge"].string, top: ContentFile.color(e["top"]),
                                   bottom: ContentFile.color(e["bottom"]), ink: ContentFile.color(e["ink"]), motif: EmblemMotif(named: e["motif"].string), shape: .round))
    }

    private static func unlock(_ kind: String, _ value: JSONValue) -> AvatarDef.Unlock {
        switch kind {
        case "gold": return .gold
        case "rank": return .rank(value.int)
        case "pro": return .pro
        case "plus": return .plus
        case "proOwner": return .proOwner
        case "founder": return .founder
        case "badge": return .badge(value.string)
        case "collection": return .collection(value.string)
        case "level": return .level(value.int)
        case "season": return .season(value.string)
        default: return .free
        }
    }

    static func def(_ id: String) -> AvatarDef? { all.first { $0.id == id } }

    static var freeIcons: [AvatarDef] { all.filter { $0.unlock == .free } }

    static func simulatedIcon(for name: String) -> String {
        let pool: [AvatarDef] = freeIcons
        return pool[EmblemCatalog.hash(name) % pool.count].id
    }

    static func colour(for name: String) -> Int { EmblemCatalog.hash("c" + name) % PlayerProfile.avatarColourCount }
}

@MainActor
final class AvatarModel: ObservableObject {
    static let shared = AvatarModel()
    private enum Key {
        static let owned = "ledger.avatar.owned"
        static let equipped = "ledger.avatar.equipped"
        static let rank = "ledger.avatar.bestRank"
        static let badges = "ledger.avatar.badges"
        static let level = "ledger.avatar.bestLevel"
    }

    @Published private(set) var owned: Set<String>
    @Published private(set) var equipped: String?
    @Published private(set) var bestRank: Int
    @Published private(set) var earnedBadges: Set<String>
    @Published private(set) var bestLevel: Int

    private init() {
        let d = UserDefaults.standard
        owned = Set(d.stringArray(forKey: Key.owned) ?? [])
        equipped = d.string(forKey: Key.equipped)
        bestRank = d.integer(forKey: Key.rank)
        earnedBadges = Set(d.stringArray(forKey: Key.badges) ?? [])
        bestLevel = max(1, d.integer(forKey: Key.level))
    }

    func isUnlocked(_ def: AvatarDef, pro: Bool, plus: Bool = false, ownsPro: Bool = false, founder: Bool = false, cabinet: Cabinet) -> Bool {
        switch def.unlock {
        case .free: return true
        case .gold: return owned.contains(def.id)
        case .rank(let i): return bestRank >= i
        case .level(let n): return bestLevel >= n
        case .season(let id): return SeasonModel.shared.pass.owned.contains(id)
        case .pro: return pro
        case .plus: return plus
        case .proOwner: return ownsPro
        case .founder: return founder
        case .badge(let b): return earnedBadges.contains(b)
        case .collection(let c):
            guard let col = ArtifactCatalog.collection(c) else { return false }
            return cabinet.isComplete(col)
        }
    }

    func note(rank: Int, badges: [String], level: Int) {
        let d = UserDefaults.standard
        if rank > bestRank { bestRank = rank; d.set(rank, forKey: Key.rank) }
        if level > bestLevel { bestLevel = level; d.set(level, forKey: Key.level) }
        let merged: Set<String> = earnedBadges.union(badges)
        if merged != earnedBadges { earnedBadges = merged; d.set(Array(merged), forKey: Key.badges) }
    }

    func grant(_ id: String) {
        guard !owned.contains(id) else { return }
        owned.insert(id)
        UserDefaults.standard.set(Array(owned), forKey: Key.owned)
    }

    func equip(_ id: String) {
        equipped = id
        UserDefaults.standard.set(id, forKey: Key.equipped)
    }
}

struct PlayerAvatar: View {
    var initials: String
    var colour: Int
    var icon: String?
    var isYou: Bool = false
    var size: CGFloat = 44
    @ObservedObject private var avatars = AvatarModel.shared

    init(initials: String, colour: Int, icon: String?, isYou: Bool = false, size: CGFloat = 44) {
        self.initials = initials; self.colour = colour; self.icon = icon; self.isYou = isYou; self.size = size
    }

    init(player: PlayerProfile, size: CGFloat = 44) {
        self.init(initials: player.initials, colour: player.avatarColour, icon: player.avatarIcon, isYou: player.relation == .you, size: size)
    }

    init(name: String, isYou: Bool, size: CGFloat = 36) {
        self.init(initials: ArtLibrary.initials(name), colour: AvatarCatalog.colour(for: name), icon: isYou ? nil : AvatarCatalog.simulatedIcon(for: name), isYou: isYou, size: size)
    }

    private var shown: String? {
        let id: String? = isYou ? (avatars.equipped ?? icon) : icon
        guard let id, AvatarCatalog.def(id) != nil else { return nil }
        return id
    }

    var body: some View {
        if let id = shown {
            ItemArt(avatar: id, size: size)
        } else {
            ProfileAvatar(initials: initials, colour: colour, size: size)
        }
    }
}
