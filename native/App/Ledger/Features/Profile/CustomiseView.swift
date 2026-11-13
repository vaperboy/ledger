import SwiftUI
import GameCore
import Simulation

/// One screen to dress your player card. It opens on the live card: tap any part of the card (backdrop, avatar, flair), or an
/// empty "+" slot, to open the matching tab. Items you do not own yet can be tried on and show on the card.
struct CustomiseView: View {
    enum Part: String, CaseIterable, Identifiable {
        case character, backdrop, flair

        var id: String { rawValue }

        init(card: CardPart) {
            switch card {
            case .character: self = .character
            case .backdrop: self = .backdrop
            case .flair: self = .flair
            }
        }

        var title: String {
            switch self {
            case .character: return "Character"
            case .backdrop: return "Backdrop"
            case .flair: return "Flair"
            }
        }

        var hint: String {
            switch self {
            case .character: return "Your face, skin, hair and outfit. Other players see them."
            case .backdrop: return "Fills your whole card."
            case .flair: return "Sits beside your name."
            }
        }

        var kind: SeasonReward.Kind? {
            switch self {
            case .backdrop: return .backdrop
            case .flair: return .richListFlair
            case .character: return nil
            }
        }
    }

    enum Look: String, CaseIterable, Identifiable {
        case face, skin, hair, outfit

        var id: String { rawValue }

        var title: String {
            switch self {
            case .face: return "Face"
            case .skin: return "Skin colour"
            case .hair: return "Hair"
            case .outfit: return "Outfit"
            }
        }
    }

    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @ObservedObject private var season = SeasonModel.shared
    @ObservedObject private var avatars = AvatarModel.shared
    @ObservedObject private var local = ProfileLocal.shared
    private let session = StoreSession.shared
    @State private var part: Part?
    @State private var look: Look = .face
    @State private var pending: PendingAction?
    @State private var note = ""
    @State private var trial: [String: String] = [:]
    @State private var trialLook: AvatarLook?

    static let barClearance: CGFloat = 130
    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 92), spacing: Theme.Space.s)]

    var body: some View {
        let cabinet: Cabinet = session.state.cabinet
        ScrollViewReader { (proxy: ScrollViewProxy) in
            ScrollView {
                VStack(spacing: Theme.Space.m) {
                    if let e = store.engine {
                        PlayerCard(data: PlayerCardData.mine(e, store: store, trial: trial, trialLook: trialLook), onPart: { (c: CardPart) in
                            choosePart(Part(card: c))
                            withAnimation { proxy.scrollTo("customise-chips", anchor: .center) }
                        })
                    }
                    if let current = part {
                        chips(current).id("customise-chips")
                        hintLine(current)
                        content(current, cabinet)
                    } else {
                        overview
                    }
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Self.barClearance)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .appScreen(title: "Customise", subtitle: "Tap a part of your card")
        .confirmAction($pending)
        .task {
            await session.load()
            if let e = store.engine { avatars.note(rank: e.careerStatus.rank.index, badges: e.careerCosmetics, level: e.playerLevel.level) }
        }
        .onChange(of: LookSync.signature) { _, _ in LookSync.push(online) }
    }

    private func choosePart(_ p: Part) {
        part = p
        note = ""
    }

    // MARK: Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("What do you want to change?").textStyle(.label, tint: Theme.inkFaint).frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.s), GridItem(.flexible(), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
                ForEach(Part.allCases) { (p: Part) in partTile(p) }
            }
        }
    }

    private func partTile(_ p: Part) -> some View {
        let status: String? = wornTitle(p)
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        return Button { Haptics.choose(); choosePart(p) } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack {
                    Text(p.title).textStyle(.headline, tint: Theme.ink)
                    Spacer(minLength: 0)
                    if status == nil { Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent) }
                }
                Text(status ?? "Empty. Tap to add one.").textStyle(.caption, tint: status == nil ? Theme.accent : Theme.inkSoft).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading).padding(Theme.Space.m)
            .background(shape.fill(Theme.inset))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("customise-part-" + p.rawValue)
    }

    /// The title of what is worn for a part, or nil when the slot is empty. The character is always set.
    private func wornTitle(_ p: Part) -> String? {
        switch p {
        case .character: return "Face, skin, hair and outfit"
        case .backdrop:
            if let id = season.pass.equipped[SeasonReward.Kind.backdrop.rawValue], let r = LookKit.item(id) { return r.title }
            if let id = season.pass.equipped[SeasonPass.profileCardKey], let d = CardCatalog.def(forItem: id) { return d.name }
            return nil
        case .flair: return season.pass.equipped[SeasonReward.Kind.richListFlair.rawValue].flatMap { (id: String) -> String? in LookKit.item(id)?.title }
        }
    }

    // MARK: Header

    private func chips(_ current: Part) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.s) {
                ForEach(Part.allCases) { (p: Part) in
                    let on: Bool = p == current
                    Button { Haptics.choose(); part = on ? nil : p; note = "" } label: {
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

    private func hintLine(_ current: Part) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(note.isEmpty ? current.hint : note).textStyle(.caption, tint: note.isEmpty ? Theme.inkSoft : Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
            if !trial.isEmpty || trialLook != nil {
                Button("Stop trying") { Haptics.tap(); trial = [:]; trialLook = nil; note = "" }
                    .buttonStyle(TertiaryButtonStyle(size: .compact))
                    .accessibilityIdentifier("customise-stop-trying")
            }
        }
        .frame(minHeight: 32)
    }

    @ViewBuilder private func content(_ current: Part, _ cabinet: Cabinet) -> some View {
        switch current {
        case .character: characterContent
        case .backdrop: backdropContent(cabinet)
        case .flair: rewardGrid(current.kind ?? .richListFlair)
        }
    }

    // MARK: Character

    private var characterContent: some View {
        let shown: AvatarLook = trialLook ?? local.avatar
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            SegmentedPill(items: Look.allCases, title: { (l: Look) -> String in l.title }, selection: $look, identifier: { (l: Look) -> String in "customise-look-" + l.rawValue })
            switch look {
            case .face: AvatarFacePicker(look: shown, onPick: { (p: AvatarPick) in choose(p) })
            case .skin: AvatarSkinPicker(look: shown, onPick: { (p: AvatarPick) in choose(p) })
            case .hair: AvatarHairPicker(look: shown, onPick: { (p: AvatarPick) in choose(p) })
            case .outfit: AvatarOutfitPicker(look: shown, onPick: { (p: AvatarPick) in choose(p) })
            }
        }
    }

    /// An item you have is worn; one you do not have is tried on the card and says where to get it.
    private func choose(_ p: AvatarPick) {
        if p.owned {
            var next: AvatarLook = local.avatar
            p.apply(&next)
            trialLook = nil
            wear(next)
        } else {
            var tried: AvatarLook = trialLook ?? local.avatar
            p.apply(&tried)
            trialLook = tried
            note = "Trying " + p.title + ". " + p.how + "."
        }
    }

    private func wear(_ look: AvatarLook) {
        local.setAvatar(look)
        note = ""
    }

    // MARK: Backdrop and flair

    private func rewards(_ kind: SeasonReward.Kind) -> [SeasonReward] {
        var seen = Set<String>()
        return (SeasonRewards.all + GoldCosmetics.all.map { (g: GoldCosmetic) -> SeasonReward in g.item })
            .filter { (r: SeasonReward) -> Bool in r.kind == kind && seen.insert(r.id).inserted }
    }

    private func rewardGrid(_ kind: SeasonReward.Kind) -> some View {
        let all: [SeasonReward] = rewards(kind)
        let owned: [SeasonReward] = all.filter { (r: SeasonReward) -> Bool in season.pass.owned.contains(r.id) }.sorted { $0.title < $1.title }
        let shut: [SeasonReward] = all.filter { (r: SeasonReward) -> Bool in !season.pass.owned.contains(r.id) }
        return LazyVGrid(columns: columns, spacing: Theme.Space.s) {
            ForEach(owned + shut) { (r: SeasonReward) in rewardTile(r) }
        }
    }

    @ViewBuilder private func tileArt(_ r: SeasonReward) -> some View {
        ItemArt(reward: r, rarity: GoldCosmetics.cosmetic(r.id)?.rarity, size: 48, wide: true)
    }

    private func rewardTile(_ r: SeasonReward) -> some View {
        let isOpen: Bool = season.pass.owned.contains(r.id)
        let worn: Bool = trial[r.kind.rawValue] == nil && season.pass.equipped[r.kind.rawValue] == r.id
        let trying: Bool = trial[r.kind.rawValue] == r.id
        let how: String = CustomiseView.how(r)
        return LookTile(title: r.title, note: isOpen ? "" : how, worn: worn || trying, wornText: trying ? "Trying" : "Equipped", locked: !isOpen, id: "reward-" + r.id,
                        art: tileArt(r)) {
            if !isOpen {
                Haptics.choose()
                trial[r.kind.rawValue] = trying ? nil : r.id
                note = trying ? "" : "Trying " + r.title + ". " + how + "."
                return
            }
            Haptics.success()
            trial[r.kind.rawValue] = nil
            note = ""
            if worn { season.unequip(r.kind) } else { season.equipAsking(r.id, pending: $pending) }
        }
    }

    @ViewBuilder private func backdropContent(_ cabinet: Cabinet) -> some View {
        let current: String? = season.pass.equipped[SeasonPass.profileCardKey]
        let owned: [ArtifactItem] = cabinet.sorted.filter { (i: ArtifactItem) -> Bool in CardCatalog.def(forItem: i.id)?.kind == .profile }
        let shut: [CardDef] = CardCatalog.all.filter { (d: CardDef) -> Bool in d.kind == .profile && !cabinet.owns(d.id) }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            rewardGrid(.backdrop)
            Text("Cards").textStyle(.label, tint: Theme.inkFaint)
            LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                ForEach(owned) { (item: ArtifactItem) in
                    if let d = CardCatalog.def(forItem: item.id) {
                        let on: Bool = trial[SeasonPass.profileCardKey] == nil && current == item.id
                        LookTile(title: d.name, note: d.isAnimated ? "Animated" : "", worn: on, locked: false, id: "card-" + item.id, art: CardThumb(def: d, width: 72)) {
                            Haptics.success()
                            trial = [:]
                            note = ""
                            if on {
                                season.equipProfileCardAsking(nil, pending: $pending)
                            } else {
                                season.unequip(.backdrop)
                                season.equipProfileCardAsking(item.id, pending: $pending)
                            }
                        }
                    }
                }
                ForEach(shut) { (d: CardDef) in
                    let trying: Bool = trial[SeasonPass.profileCardKey] == d.id
                    LookTile(title: d.name, note: CustomiseView.how(d), worn: trying, wornText: "Trying", locked: true, id: "card-" + d.id, art: CardThumb(def: d, width: 72)) {
                        Haptics.choose()
                        trial[SeasonPass.profileCardKey] = trying ? nil : d.id
                        if !trying { trial[SeasonReward.Kind.backdrop.rawValue] = "" }
                        note = trying ? "" : "Trying " + d.name + ". " + CustomiseView.how(d) + "."
                    }
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
        case .plan: return "Ledger plans"
        case .free: return "Free"
        case .level: return "Reach level " + g.value
        case .rank: return "Reach rank " + g.value
        case .goal: return "Career goal"
        }
    }

    static func how(_ d: CardDef) -> String {
        if let l = CardCatalog.levelRewards.first(where: { (x: CardCatalog.LevelReward) -> Bool in x.defID == d.id }) { return "Reach level \(l.level)" }
        if let s = SeasonRewards.all.first(where: { (x: SeasonReward) -> Bool in x.id == d.id }) { return "Season Pass tier \(s.tier)" + (s.premium ? ", premium track" : "") }
        return "Card packs"
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
