import SwiftUI
import Simulation

struct AvatarDef: Identifiable, Equatable {
    enum Unlock: Equatable {
        case free
        case gold
        case rank(Int)
        case pro
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
        case .badge(let b): return "Earn the " + Cosmetics.badge(b).title.lowercased() + " badge in Goals"
        case .collection(let c): return "Complete the " + (ArtifactCatalog.collection(c)?.name ?? "") + " collection"
        case .level(let n): return "Reach level \(n)"
        case .season(let id): return "Claim " + (SeasonRewards.item(id)?.title ?? "the reward") + " in the Season Pass"
        }
    }
}

enum AvatarCatalog {
    private static func a(_ id: String, _ title: String, _ tier: BoxRarity, _ unlock: AvatarDef.Unlock, _ symbol: String, _ top: UInt32, _ bottom: UInt32,
                          _ ink: UInt32, _ motif: EmblemMotif, badge: String? = nil) -> AvatarDef {
        AvatarDef(id: id, title: title, tier: tier, unlock: unlock,
                  spec: EmblemSpec(symbol: symbol, badge: badge, top: top, bottom: bottom, ink: ink, motif: motif, shape: .round))
    }

    static let all: [AvatarDef] = [
        a("av.briefcase", "Briefcase", .common, .free, "briefcase.fill", 0xC9A86A, 0x4D3C1C, 0xFFF1D0, .rings),
        a("av.coffee", "Coffee break", .common, .free, "cup.and.saucer.fill", 0xA87850, 0x45301E, 0xFFE6CC, .dots),
        a("av.leaf", "Leaf", .common, .free, "leaf.fill", 0x6FA064, 0x2A4524, 0xDDF2D4, .hills),
        a("av.bolt", "Spark", .common, .free, "bolt.fill", 0xD6B440, 0x5A4610, 0xFFF3BE, .rays),
        a("av.star", "Evening star", .common, .free, "star.fill", 0x5C6AA8, 0x242B55, 0xE2E7FF, .stars),
        a("av.sun", "Morning sun", .common, .free, "sun.max.fill", 0xD98A4A, 0x69320F, 0xFFE8C4, .rays),
        a("av.moon", "Night shift", .common, .free, "moon.stars.fill", 0x4B4F8F, 0x1C1D3F, 0xDADCFF, .stars),
        a("av.drop", "Clear drop", .common, .free, "drop.fill", 0x4F94BD, 0x1B3E57, 0xD3EEFB, .waves),
        a("av.hare", "Quick hare", .common, .free, "hare.fill", 0x9A8D78, 0x403A2E, 0xF3EBDD, .stripes),
        a("av.bird", "Early bird", .common, .free, "bird.fill", 0x4E9A92, 0x1B4440, 0xD2F3EE, .dots),
        a("av.key", "Brass key", .common, .gold, "key.fill", 0xB78F4A, 0x4A3412, 0xFFE8B4, .grid),
        a("av.paw", "Paw print", .common, .gold, "pawprint.fill", 0x9A6E5A, 0x40271E, 0xF6DDD0, .dots),
        a("av.tortoise", "Patient tortoise", .common, .gold, "tortoise.fill", 0x6E9A6A, 0x25402A, 0xDCF2D8, .hills),
        a("av.summit", "Summit", .common, .gold, "mountain.2.fill", 0x7E8FA8, 0x2E3849, 0xE4EBF7, .hills),
        a("av.sailboat", "Sailboat", .rare, .gold, "sailboat.fill", 0x3E7FA8, 0x143650, 0xCFEAFB, .waves),
        a("av.workshop", "Workshop", .rare, .gold, "gearshape.2.fill", 0x8C8A93, 0x35343B, 0xECEBF2, .grid),
        a("av.jet", "Jet set", .rare, .gold, "airplane", 0x5C86C4, 0x1F3866, 0xD7E5FB, .rays),
        a("av.toast", "Toast", .rare, .gold, "wineglass.fill", 0xA8485E, 0x4A1727, 0xFBD3DC, .stars),
        a("av.diamond", "Cut diamond", .epic, .gold, "diamond.fill", 0x6AA8C8, 0x1B3F58, 0xE1F6FF, .rays),
        a("av.goldstar", "Gold star", .epic, .gold, "star.circle.fill", 0xDDB84C, 0x6B4A0E, 0xFFF3C8, .rings),
        a("av.sleight", "Sleight of hand", .epic, .gold, "wand.and.stars", 0x8A64B8, 0x321F55, 0xEBDDFA, .stars),
        a("av.rank1", "Shopkeeper", .common, .rank(1), "storefront.fill", 0xB58A5A, 0x49331C, 0xFFE9CE, .stripes),
        a("av.rank2", "Trader", .common, .rank(2), "cart.fill", 0x7C9A66, 0x2C4025, 0xE3F3D8, .grid),
        a("av.rank3", "Merchant", .rare, .rank(3), "shippingbox.fill", 0x5F83B0, 0x213A5C, 0xD6E5F8, .grid),
        a("av.rank4", "Entrepreneur", .rare, .rank(4), "lightbulb.fill", 0xD0A640, 0x5A400E, 0xFFEFB8, .rays),
        a("av.rank5", "Executive", .rare, .rank(5), "chart.line.uptrend.xyaxis", 0x4E8C7C, 0x1A4038, 0xD0F2E8, .grid),
        a("av.rank6", "Magnate", .epic, .rank(6), "building.columns.fill", 0x9A78C0, 0x372458, 0xEEDFFC, .rings),
        a("av.rank7", "Mogul", .epic, .rank(7), "banknote.fill", 0x6FA28A, 0x1F4536, 0xD8F5E6, .stars),
        a("av.rank8", "Tycoon", .legendary, .rank(8), "trophy.fill", 0xE2BE55, 0x6B4A0A, 0xFFF4CC, .rays, badge: "star.fill"),
        a("av.coin", "Coin collector", .common, .badge("logo.coin"), "dollarsign.circle.fill", 0xC9A24A, 0x58420F, 0xFFF0C2, .rings),
        a("av.seal", "Sealed deal", .rare, .badge("logo.seal"), "checkmark.seal.fill", 0x5A8FB8, 0x1E3F5E, 0xD9ECFB, .rings),
        a("av.laurel", "Laurel", .rare, .badge("logo.laurel"), "rosette", 0x7FA06A, 0x2D4A25, 0xE0F3D5, .stars),
        a("av.crest", "Gold crest", .epic, .badge("logo.crest"), "shield.fill", 0xC8A04A, 0x4F3A0E, 0xFFEFC0, .grid, badge: "star.fill"),
        a("av.counting", "Counting House", .epic, .collection("counting"), "circle.grid.3x3.fill", 0xA8803A, 0x4A3512, 0xFFE9B0, .rings),
        a("av.harbour", "Harbour light", .epic, .collection("harbour"), "water.waves", 0x2F7080, 0x143642, 0xBDEBF2, .waves),
        a("av.market", "Market bell", .epic, .collection("market"), "bell.fill", 0xB2677A, 0x57293A, 0xFAD2DC, .stripes),
        a("av.archive", "Town archive", .epic, .collection("archive"), "scroll.fill", 0x9C957F, 0x45423A, 0xF1ECDD, .grid),
        a("av.lvl3", "Chain builder", .rare, .level(3), "link", 0x5F9A8C, 0x1C443C, 0xD2F4EA, .grid),
        a("av.lvl5", "Franchisor", .rare, .level(5), "building.2.fill", 0xB08A58, 0x4A3416, 0xFFE9C6, .stripes),
        a("av.lvl7", "Going abroad", .epic, .level(7), "globe.europe.africa.fill", 0x4E86B8, 0x16345A, 0xD4E8FB, .waves),
        a("av.s1.first", "First steps", .common, .season("badge.s1.first"), "flag.fill", 0xB8985A, 0x4A3A18, 0xFFEFC8, .dots),
        a("av.s1.finish", "Season 1 finisher", .rare, .season("badge.s1.complete"), "medal.fill", 0xC4A24E, 0x5A410E, 0xFFF0BE, .rings),
        a("av.s1.crown", "Season 1 crown", .epic, .season("badge.s1.crown"), "seal.fill", 0xE0BC5E, 0x6B4A0A, 0xFFF4CC, .rays, badge: "star.fill"),
        a("av.flame", "Ember", .rare, .pro, "flame.fill", 0xD4743C, 0x5E230B, 0xFFE0C8, .rays),
        a("av.sparkle", "Sparkle", .rare, .pro, "sparkles", 0x8F7AD0, 0x2F2560, 0xE8E0FF, .stars),
        a("av.infinity", "Long game", .epic, .pro, "infinity", 0x4FA09C, 0x14433F, 0xCFF5F0, .rings),
    ]

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

    func isUnlocked(_ def: AvatarDef, pro: Bool, cabinet: Cabinet) -> Bool {
        switch def.unlock {
        case .free: return true
        case .gold: return owned.contains(def.id)
        case .rank(let i): return bestRank >= i
        case .level(let n): return bestLevel >= n
        case .season(let id): return SeasonModel.shared.pass.owned.contains(id)
        case .pro: return pro
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

struct AvatarPickerView: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @Environment(Entitlements.self) private var ent
    @ObservedObject private var avatars = AvatarModel.shared
    @ObservedObject private var season = SeasonModel.shared
    private let session = StoreSession.shared
    @State private var selected: String = ""
    @State private var pending: PendingAction?
    @State private var shortOfGold = false
    @State private var shortNeed = 0
    @State private var showPacks = false

    var body: some View {
        let cabinet: Cabinet = session.state.cabinet
        let open: [AvatarDef] = AvatarCatalog.all.filter { avatars.isUnlocked($0, pro: ent.isPro, cabinet: cabinet) }
        let locked: [AvatarDef] = AvatarCatalog.all.filter { (d: AvatarDef) -> Bool in !open.contains(d) }
        PhonePageScroll(spacing: Theme.Space.l) {
            preview(open: open, cabinet: cabinet)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Your icons").capsLabel(Theme.inkFaint).padding(.horizontal, Theme.Space.m)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
                    ForEach(open) { (d: AvatarDef) in cell(d) }
                }
            }
            if !locked.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Locked").capsLabel(Theme.inkFaint).padding(.horizontal, Theme.Space.m)
                    VStack(spacing: 0) {
                        ForEach(Array(locked.enumerated()), id: \.element.id) { (i: Int, d: AvatarDef) in
                            if i > 0 { Hairline() }
                            lockedRow(d)
                        }
                    }
                }
            }
        }
        .appScreen(title: "Profile icon", subtitle: "What other players see")
        .confirmAction($pending)
        .centerSheet(isPresented: $shortOfGold, title: "Not enough gold") { ShortOfGoldCard(needed: shortNeed, onPacks: { shortOfGold = false; showPacks = true }) }
        .navigationDestination(isPresented: $showPacks) { StoreApp() }
        .task {
            await session.load()
            if let e = store.engine { avatars.note(rank: e.careerStatus.rank.index, badges: e.careerCosmetics, level: e.playerLevel.level) }
            if selected.isEmpty { selected = avatars.equipped ?? AvatarCatalog.freeIcons[0].id }
        }
    }

    private func cell(_ d: AvatarDef) -> some View {
        let on: Bool = selected == d.id
        let worn: Bool = (avatars.equipped ?? "") == d.id
        return Button {
            Haptics.choose()
            selected = d.id
        } label: {
            VStack(spacing: 4) {
                ItemArt(avatar: d.id, size: 52)
                Text(d.title).textStyle(.caption, tint: Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.8)
                Text(worn ? "In use" : " ").textStyle(.caption, tint: Theme.gain).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .padding(.vertical, Theme.Space.xs)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(on ? Theme.accentWash : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(d.title + (worn ? ", in use" : ""))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func lockedRow(_ d: AvatarDef) -> some View {
        let on: Bool = selected == d.id
        return Button {
            Haptics.choose()
            selected = d.id
        } label: {
            HStack(spacing: Theme.Space.m) {
                ItemArt(avatar: d.id, size: 44).saturation(0).opacity(0.45)
                    .overlay(alignment: .bottomTrailing) {
                        LedgerGlyph(glyph: Glyph.lock, size: 11, tint: Theme.ink).padding(3).background(Circle().fill(Theme.surfaceRaised))
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.title).textStyle(.body, tint: Theme.inkFaint)
                    Text(d.requirement).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Space.s)
                if let price = d.price { GoldAmount(amount: price, style: .caption) }
            }
            .padding(.vertical, Theme.Space.s)
            .frame(minHeight: 56)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(on ? Theme.accentWash : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(d.title + ", locked. " + d.requirement)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func preview(open: [AvatarDef], cabinet: Cabinet) -> some View {
        let id: String = selected.isEmpty ? (avatars.equipped ?? AvatarCatalog.freeIcons[0].id) : selected
        let d: AvatarDef = AvatarCatalog.def(id) ?? AvatarCatalog.all[0]
        let owned: Bool = open.contains(d)
        let worn: Bool = (avatars.equipped ?? "") == d.id
        return VStack(spacing: Theme.Space.s) {
            ItemArt(avatar: d.id, size: 96).saturation(owned ? 1 : 0).opacity(owned ? 1 : 0.5)
            Text(d.title).textStyle(.title)
            HStack(spacing: Theme.Space.xs) {
                RarityTag(rarity: d.tier)
                Text(owned ? (worn ? "In use" : "Yours") : d.requirement).textStyle(.caption)
            }
            action(d, owned: owned, worn: worn)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.m)
    }

    @ViewBuilder private func action(_ d: AvatarDef, owned: Bool, worn: Bool) -> some View {
        if owned {
            Button(worn ? "In use" : "Use this icon") { wear(d) }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(worn)
                .accessibilityIdentifier("avatar-use")
        } else if let price = d.price {
            Button("Buy for \(StoreText.gold(price))") { ask(d) }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("avatar-buy")
        }
    }

    private func wear(_ d: AvatarDef) {
        Haptics.success()
        avatars.equip(d.id)
        Task { _ = await online.update(ProfileUpdate(avatarIcon: d.id)) }
    }

    private func ask(_ d: AvatarDef) {
        StorePurchase.ask(.avatar(d), pending: $pending, onShort: { (price: Int) in shortNeed = price; shortOfGold = true }, then: { (done: Bool) in
            if done { wear(d) }
        })
    }
}
