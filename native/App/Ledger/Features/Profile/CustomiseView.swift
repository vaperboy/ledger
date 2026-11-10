import SwiftUI
import GameCore
import Simulation

struct CustomiseView: View {
    enum Part: String, CaseIterable, Identifiable {
        case icon, card, plate, backdrop, flair, badge, showcase

        var id: String { rawValue }

        var title: String {
            switch self {
            case .icon: return "Icon"
            case .card: return "Card"
            case .plate: return "Name plate"
            case .backdrop: return "Backdrop"
            case .flair: return "Flair"
            case .badge: return "Badge"
            case .showcase: return "Showcase"
            }
        }

        var hint: String {
            switch self {
            case .icon: return "Shown beside your name everywhere."
            case .card: return "Fills the background of your profile. Rare cards move."
            case .plate: return "Frames your name on your profile."
            case .backdrop: return "Fills the background of your profile, or tints it."
            case .flair: return "Sits beside your name on your profile."
            case .badge: return "Your rank badge and colour on the home screen."
            case .showcase: return "Pick 3 artifacts to show on your profile."
            }
        }

        var kinds: [SeasonReward.Kind] {
            switch self {
            case .plate: return [.namePlate]
            case .backdrop: return [.backdrop, .theme]
            case .flair: return [.richListFlair]
            default: return []
            }
        }
    }

    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @Environment(Entitlements.self) private var ent
    @ObservedObject private var season = SeasonModel.shared
    @ObservedObject private var avatars = AvatarModel.shared
    @ObservedObject private var local = ProfileLocal.shared
    @AppStorage(CosmeticKeys.badge) private var savedBadge: String = Cosmetics.defaultBadgeID
    @AppStorage(CosmeticKeys.theme) private var savedTheme: String = Cosmetics.defaultThemeID
    private let session = StoreSession.shared
    @State private var part: Part = .icon
    @State private var pending: PendingAction?
    @State private var shortOfGold = false
    @State private var shortNeed = 0
    @State private var showPacks = false
    @State private var note = ""
    @State private var flash: String?

    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 92), spacing: Theme.Space.s)]

    var body: some View {
        let cabinet: Cabinet = session.state.cabinet
        VStack(spacing: Theme.Space.m) {
            ProfileCard(compact: true)
            chips
            slotHeader
            ScrollView {
                content(cabinet).padding(.bottom, Theme.Space.l)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s)
        .frame(maxWidth: 760).frame(maxWidth: .infinity)
        .appScreen(title: "Customise", subtitle: "Tap to wear it")
        .confirmAction($pending)
        .centerSheet(isPresented: $shortOfGold, title: "Not enough gold") { ShortOfGoldCard(needed: shortNeed, onPacks: { shortOfGold = false; showPacks = true }) }
        .navigationDestination(isPresented: $showPacks) { StoreApp() }
        .task {
            await session.load()
            if let e = store.engine { avatars.note(rank: e.careerStatus.rank.index, badges: e.careerCosmetics, level: e.playerLevel.level) }
        }
    }

    private func worn(_ kinds: [SeasonReward.Kind]) -> String {
        let names: [String] = kinds.compactMap { (k: SeasonReward.Kind) -> String? in
            guard let id = season.pass.equipped[k.rawValue] else { return nil }
            return SeasonRewards.item(id)?.title ?? GoldCosmetics.cosmetic(id)?.item.title
        }
        return names.isEmpty ? "Nothing" : names.joined(separator: ", ")
    }

    private var currentName: String {
        switch part {
        case .icon: return AvatarCatalog.def(avatars.equipped ?? "")?.title ?? "Default icon"
        case .card: return season.pass.equipped[SeasonPass.profileCardKey].flatMap { (id: String) -> String? in CardCatalog.def(forItem: id)?.name } ?? "Nothing"
        case .plate, .backdrop, .flair: return worn(part.kinds)
        case .badge: return Cosmetics.badge(savedBadge).title
        case .showcase: return "\(local.showcase.count) of \(ProfileLocal.showcaseSlots) artifacts"
        }
    }

    private var slotHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text("Changing").textStyle(.label, tint: Theme.inkFaint)
                Text(part.title).textStyle(.headline)
                Spacer(minLength: Theme.Space.s)
                if let f = flash {
                    HStack(spacing: 4) {
                        LedgerGlyph(glyph: Glyph.check, size: 12, tint: Theme.gain)
                        Text(f).textStyle(.caption, tint: Theme.gain).lineLimit(1)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            HStack(spacing: Theme.Space.xs) {
                Text("Now").textStyle(.caption, tint: Theme.inkFaint)
                Text(currentName).textStyle(.body, weight: .medium).lineLimit(1)
                if flash == nil { Text("Pick another below to replace it.").textStyle(.caption, tint: Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.8) }
            }
            Text(note.isEmpty ? part.hint : note).textStyle(.caption, tint: note.isEmpty ? Theme.inkSoft : Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
        .animation(.smooth(duration: 0.25), value: flash)
        .onChange(of: currentName) { _, new in
            flash = "Now wearing " + new
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                flash = nil
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.s) {
                ForEach(Part.allCases) { (p: Part) in
                    let on: Bool = p == part
                    Button { Haptics.choose(); part = p; note = ""; flash = nil } label: {
                        Text(p.title).textStyle(.body, tint: on ? Theme.ink : Theme.inkSoft, weight: on ? .semibold : .regular)
                            .padding(.horizontal, Theme.Space.l).frame(minHeight: 44)
                            .background(Capsule().fill(on ? Theme.accentWash : Theme.inset))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("customise-part-" + p.rawValue)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private func content(_ cabinet: Cabinet) -> some View {
        switch part {
        case .icon: iconGrid(cabinet)
        case .card: cardGrid(cabinet)
        case .plate, .backdrop, .flair: rewardGrid(part.kinds)
        case .badge: ColourBadgePicker(earned: store.engine?.careerCosmetics ?? [], theme: $savedTheme, badge: $savedBadge)
        case .showcase: showcaseGrid(cabinet)
        }
    }

    private func iconGrid(_ cabinet: Cabinet) -> some View {
        let open: [AvatarDef] = AvatarCatalog.all.filter { avatars.isUnlocked($0, pro: ent.isPro, cabinet: cabinet) }
        let shut: [AvatarDef] = AvatarCatalog.all.filter { (d: AvatarDef) -> Bool in !open.contains(d) }
        return LazyVGrid(columns: columns, spacing: Theme.Space.s) {
            ForEach(open + shut) { (d: AvatarDef) in
                let isOpen: Bool = open.contains(d)
                let how: String = d.requirement + (d.price.map { (p: Int) -> String in " \u{00B7} " + StoreText.gold(p) } ?? "")
                tile(title: d.title, note: isOpen ? "" : how, worn: avatars.equipped == d.id, locked: !isOpen, id: "icon-" + d.id) {
                    ItemArt(avatar: d.id, size: 48)
                } action: { tapIcon(d, open: isOpen, how: how) }
            }
        }
    }

    private func tapIcon(_ d: AvatarDef, open: Bool, how: String) {
        if open { wear(d); return }
        if d.price != nil { ask(d) } else { Haptics.warning(); note = d.title + ": " + how }
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

    private func rewards(_ kinds: [SeasonReward.Kind]) -> [SeasonReward] {
        var seen = Set<String>()
        return (SeasonRewards.all + GoldCosmetics.all.map { (g: GoldCosmetic) -> SeasonReward in g.item })
            .filter { (r: SeasonReward) -> Bool in kinds.contains(r.kind) && seen.insert(r.id).inserted }
    }

    private func rewardGrid(_ kinds: [SeasonReward.Kind]) -> some View {
        let all: [SeasonReward] = rewards(kinds)
        let owned: [SeasonReward] = all.filter { (r: SeasonReward) -> Bool in season.pass.owned.contains(r.id) }.sorted { $0.title < $1.title }
        let shut: [SeasonReward] = all.filter { (r: SeasonReward) -> Bool in !season.pass.owned.contains(r.id) }
        return LazyVGrid(columns: columns, spacing: Theme.Space.s) {
            ForEach(owned + shut) { (r: SeasonReward) in
                let isOpen: Bool = season.pass.owned.contains(r.id)
                let worn: Bool = season.pass.equipped[r.kind.rawValue] == r.id
                let how: String = CustomiseView.how(r)
                tile(title: r.title, note: isOpen ? (kinds.count > 1 ? r.kind.label : "") : how, worn: worn, locked: !isOpen, id: "reward-" + r.id) {
                    ItemArt(reward: r, rarity: GoldCosmetics.cosmetic(r.id)?.rarity, size: 48, wide: true)
                } action: {
                    if !isOpen { Haptics.warning(); note = r.title + ": " + how; return }
                    Haptics.success()
                    if worn { season.unequip(r.kind) } else { season.equipAsking(r.id, pending: $pending) }
                }
            }
        }
    }

    static func how(_ r: SeasonReward) -> String {
        if let s = SeasonRewards.all.first(where: { (x: SeasonReward) -> Bool in x.id == r.id }) { return "Season Pass tier \(s.tier)" + (s.premium ? ", premium track" : "") }
        guard let g = GoldCosmetics.cosmetic(r.id) else { return "Not available yet" }
        switch g.source {
        case .store: return g.price.map { (p: Int) -> String in "Store, " + StoreText.gold(p) } ?? "Store"
        case .box: return "Cosmetic boxes"
        case .collection: return "Complete a collection"
        }
    }

    static func how(_ d: CardDef) -> String {
        if let l = CardCatalog.levelRewards.first(where: { (x: CardCatalog.LevelReward) -> Bool in x.defID == d.id }) { return "Reach level \(l.level)" }
        if let s = SeasonRewards.all.first(where: { (x: SeasonReward) -> Bool in x.id == d.id }) { return "Season Pass tier \(s.tier)" + (s.premium ? ", premium track" : "") }
        return "Card packs"
    }

    private func cardGrid(_ cabinet: Cabinet) -> some View {
        let current: String? = season.pass.equipped[SeasonPass.profileCardKey]
        let owned: [ArtifactItem] = cabinet.sorted.filter { (i: ArtifactItem) -> Bool in CardCatalog.def(forItem: i.id)?.kind == .profile }
        let shut: [CardDef] = CardCatalog.all.filter { (d: CardDef) -> Bool in d.kind == .profile && !cabinet.owns(d.id) }
        return LazyVGrid(columns: columns, spacing: Theme.Space.s) {
            ForEach(owned) { (item: ArtifactItem) in
                if let d = CardCatalog.def(forItem: item.id) {
                    tile(title: d.name, note: d.isAnimated ? "Animated" : "", worn: current == item.id, locked: false, id: "card-" + item.id) {
                        CardThumb(def: d, width: 72)
                    } action: {
                        Haptics.success()
                        season.equipProfileCardAsking(current == item.id ? nil : item.id, pending: $pending)
                    }
                }
            }
            ForEach(shut) { (d: CardDef) in
                tile(title: d.name, note: CustomiseView.how(d), worn: false, locked: true, id: "card-" + d.id) {
                    CardThumb(def: d, width: 72)
                } action: { Haptics.warning(); note = d.name + ": " + CustomiseView.how(d) }
            }
        }
    }

    @ViewBuilder private func showcaseGrid(_ cabinet: Cabinet) -> some View {
        let pieces: [ArtifactItem] = cabinet.sorted.filter { (i: ArtifactItem) -> Bool in CardCatalog.def(forItem: i.id) == nil && ArtifactCatalog.def(i.defID) != nil }
        if pieces.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("You own no artifacts yet. Open boxes in the Store to find some.").textStyle(.body, tint: Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button { Haptics.tap(); showPacks = true } label: { Text("Open the Store").frame(maxWidth: .infinity) }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true))
            }
        } else {
            LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                ForEach(pieces) { (item: ArtifactItem) in
                    if let def = ArtifactCatalog.def(item.defID) {
                        let at: Int? = local.showcase.firstIndex(of: item.id)
                        tile(title: def.name, note: ArtifactCatalog.label(item), worn: at != nil, wornText: at.map { (n: Int) -> String in "Slot \(n + 1)" } ?? "", locked: false, id: "showcase-" + item.id) {
                            ItemArt(artifact: def, size: 48)
                        } action: { toggleShowcase(item.id) }
                    }
                }
            }
        }
    }

    private func toggleShowcase(_ id: String) {
        var list: [String] = local.showcase
        if let i = list.firstIndex(of: id) {
            list.remove(at: i)
        } else if list.count < ProfileLocal.showcaseSlots {
            list.append(id)
        } else {
            Haptics.warning()
            note = "The showcase holds 3. Tap one to take it off first."
            return
        }
        Haptics.choose()
        note = ""
        local.setShowcase(list)
    }

    private func tile<Art: View>(title: String, note: String, worn: Bool, wornText: String = "Equipped", locked: Bool, id: String, @ViewBuilder art: () -> Art, action: @escaping () -> Void) -> some View {
        LookTile(title: title, note: note, worn: worn, wornText: wornText, locked: locked, id: id, art: art(), action: action)
    }
}

struct LookTile<Art: View>: View {
    var title: String
    var note: String
    var worn: Bool
    var wornText: String = "Equipped"
    var locked: Bool
    var id: String
    var art: Art
    var action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        Button(action: action) {
            VStack(spacing: 4) {
                art
                    .saturation(locked ? 0 : 1).opacity(locked ? 0.45 : 1)
                    .overlay(alignment: .bottomTrailing) {
                        if locked { LedgerGlyph(glyph: Glyph.lock, size: 11, tint: Theme.ink).padding(3).background(Circle().fill(Theme.surfaceRaised)) }
                    }
                Text(title).textStyle(.caption, tint: locked ? Theme.inkFaint : Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.8)
                Text(worn ? wornText : note).textStyle(.caption, tint: worn ? Theme.gain : Theme.inkFaint).lineLimit(3).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .top).padding(.vertical, Theme.Space.xs)
            .background(shape.fill(worn ? Theme.accentWash : Color.clear))
            .overlay(shape.strokeBorder(worn ? Theme.accent : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title + (worn ? ", " + wornText : (locked ? ", locked. " + note : "")))
        .accessibilityAddTraits(worn ? .isSelected : [])
        .accessibilityIdentifier("customise-" + id)
    }
}

struct ColourBadgePicker: View {
    @Environment(Entitlements.self) private var ent
    var earned: [String]
    @Binding var theme: String
    @Binding var badge: String

    var body: some View {
        let pro: Bool = ent.isPro
        let themeID: String = Cosmetics.resolvedTheme(theme.isEmpty ? nil : theme, pro: pro).id
        let badgeID: String = Cosmetics.resolvedBadge(badge.isEmpty ? nil : badge, earned: earned, pro: pro).id
        let accent: Color = Cosmetics.theme(themeID).accent
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Colour").textStyle(.label, tint: Theme.inkFaint)
                HStack(spacing: Theme.Space.s) {
                    ForEach(Cosmetics.themes) { (t: Cosmetics.Palette) in dot(t, on: t.id == themeID, pro: pro) }
                }
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Logo badge").textStyle(.label, tint: Theme.inkFaint)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
                    ForEach(Cosmetics.badges) { (b: Cosmetics.Badge) in cell(b, on: b.id == badgeID, accent: accent, pro: pro) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dot(_ t: Cosmetics.Palette, on: Bool, pro: Bool) -> some View {
        let open: Bool = Cosmetics.isThemeUnlocked(t.id, pro: pro)
        return Button {
            if open { Haptics.choose(); theme = t.id } else { Haptics.warning(); ent.paywall = PaywallRequest(title: "Wardrobe") }
        } label: {
            ZStack {
                Circle().fill(t.accent).frame(width: 34, height: 34)
                if !open { LedgerGlyph(glyph: Glyph.lock, size: 12, tint: Color.black.opacity(0.65)) }
            }
            .padding(4)
            .overlay(Circle().strokeBorder(on ? Theme.ivory : Color.clear, lineWidth: 2))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(t.title + (open ? "" : ", needs Ledger Pro"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func cell(_ b: Cosmetics.Badge, on: Bool, accent: Color, pro: Bool) -> some View {
        let open: Bool = Cosmetics.isBadgeUnlocked(b.id, earned: earned, pro: pro)
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        let note: String = open ? b.title : (b.premium ? "Ledger Pro" : "Earn in Goals")
        return Button {
            if open { Haptics.choose(); badge = b.id } else if b.premium { Haptics.warning(); ent.paywall = PaywallRequest(title: "Wardrobe") } else { Haptics.warning() }
        } label: {
            VStack(spacing: 5) {
                CosmeticBadgeView(badge: b, tint: open ? accent : Theme.ivoryDim, size: 36)
                Text(note).textStyle(.caption, tint: open ? Theme.inkSoft : Theme.inkFaint).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 64).padding(.vertical, Theme.Space.s)
            .background(shape.fill(on ? Theme.inset : Color.clear))
            .overlay(shape.strokeBorder(on ? accent.opacity(0.8) : Color.clear, lineWidth: 1))
            .opacity(open ? 1 : 0.6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(b.title + (open ? "" : (b.premium ? ", needs Ledger Pro" : ", not earned yet")))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
