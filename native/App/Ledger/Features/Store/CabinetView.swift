import SwiftUI
import GameCore
import Simulation

struct CabinetView: View {
    private let session = StoreSession.shared
    @State private var selling: ArtifactItem?

    var body: some View {
        let cabinet: Cabinet = session.state.cabinet
        PhonePageScroll(spacing: Theme.Space.l) {
            collections(cabinet)
            pieces(cabinet)
        }
        .appScreen(title: "Artifacts", subtitle: "Pieces and collections")
        .task { await session.load() }
        .centerSheet(item: $selling, title: "Sell a piece") { (item: ArtifactItem) in PieceSaleCard(item: item) }
    }

    private func collections(_ cabinet: Cabinet) -> some View {
        OnlineGroup(title: "Collections", footer: "Own at least one piece of every artifact in a collection to receive its cosmetic, once.") {
            ForEach(Array(ArtifactCatalog.collections.enumerated()), id: \.element.id) { (i: Int, col: ArtifactCollection) in
                if i > 0 { Hairline() }
                let p = cabinet.progress(col)
                let done: Bool = cabinet.isComplete(col)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    HStack {
                        Text(col.name).textStyle(.headline)
                        Spacer()
                        Text(done ? "Complete" : "\(p.have) of \(p.total)").textStyle(.caption, tint: done ? Theme.gain : Theme.inkSoft, numeric: true)
                    }
                    HStack(spacing: Theme.Space.s) {
                        ForEach(col.members, id: \.self) { (id: String) in
                            if let def = ArtifactCatalog.def(id) { ItemArt(artifact: def, size: 40).opacity(cabinet.owns(id) ? 1 : 0.3) }
                        }
                    }
                    ProgressView(value: Double(p.have), total: Double(p.total)).tint(done ? Theme.gain : Theme.accent)
                    Text(col.blurb + " Reward: " + (GoldCosmetics.cosmetic(col.rewardID)?.item.title ?? "a cosmetic") + ".").textStyle(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(col.members.map { (id: String) -> String in
                        (cabinet.owns(id) ? "Have " : "Missing ") + (ArtifactCatalog.def(id)?.name ?? id)
                    }.joined(separator: ", ")).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Theme.Space.s)
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private func pieces(_ cabinet: Cabinet) -> some View {
        let canSell: Bool = StoreGate.access(countryCode: nil) != .hidden
        OnlineGroup(title: "Your artifacts", footer: cabinet.items.isEmpty ? "Artifacts come from boxes and auctions." : (canSell ? "Tap a piece to sell it at once or at auction. Cash goes to your personal account." : "")) {
            if cabinet.items.isEmpty {
                Text("Nothing here yet.").textStyle(.body, tint: Theme.inkSoft).frame(minHeight: 52, alignment: .leading)
            } else {
                ForEach(Array(cabinet.sorted.enumerated()), id: \.element.id) { (i: Int, item: ArtifactItem) in
                    if i > 0 { Hairline() }
                    if canSell {
                        Button { selling = item } label: { ArtifactRow(item: item, trailing: "Sell") }.buttonStyle(PressableStyle())
                    } else {
                        ArtifactRow(item: item)
                    }
                }
            }
        }
    }
}

struct PieceSaleCard: View {
    var item: ArtifactItem
    private let session = StoreSession.shared
    @State private var desk = PieceDesk()
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func close() { if let c = popupClose { c() } else { systemDismiss() } }

    var body: some View {
        if desk.auctioning != nil {
            ListingCard(item: item) { (listed: Bool) in
                if listed { close() } else { desk.auctioning = nil }
            }
        } else {
            let rarity: BoxRarity = ArtifactCatalog.def(item.defID)?.rarity ?? .common
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                ArtifactRow(item: item)
                line("Market value", session.money(AuctionMarket.suggestedStart(rarity, priceLevel: session.priceLevel)))
                line("Sell now", session.money(session.quickPrice(item)))
                Text(AuctionRules.quickSaleText + " An auction can pay more, but takes time and a " + String(AuctionRules.feePercent) + "% fee.")
                    .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                PieceActions(item: item, desk: desk)
                if let why = session.problem { Text(why).textStyle(.body, tint: Theme.loss) }
            }
        }
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack { Text(title).textStyle(.body); Spacer(); Text(value).textStyle(.body, numeric: true) }
    }
}

enum LookCategory: String, CaseIterable, Identifiable {
    case avatar, theme, namePlate, backdrop, tradePlate, flair

    var id: String { rawValue }

    var kind: SeasonReward.Kind? {
        switch self {
        case .avatar: return nil
        case .theme: return .theme
        case .namePlate: return .namePlate
        case .backdrop: return .backdrop
        case .tradePlate: return .tradePlate
        case .flair: return .richListFlair
        }
    }

    var title: String {
        switch self {
        case .avatar: return "Avatar"
        case .theme: return "Theme"
        case .namePlate: return "Name plate"
        case .backdrop: return "Backdrop"
        case .tradePlate: return "Trade plate"
        case .flair: return "Flair"
        }
    }

    var appliedAt: String {
        switch self {
        case .avatar: return "Shown beside your name everywhere."
        case .theme: return "Tints your profile and the Season Pass."
        case .namePlate: return "Frames your name on your profile."
        case .backdrop: return "Fills the background of your profile."
        case .tradePlate: return "Frames your company name on your profile."
        case .flair: return "Sits beside your name on your profile."
        }
    }
}

enum LookKit {
    static func reward(_ look: [String: String], _ kind: SeasonReward.Kind) -> SeasonReward? {
        look[kind.rawValue].flatMap { SeasonRewards.item($0) }
    }

    static func tint(_ r: SeasonReward) -> UInt32 { r.colors.first ?? 0xD6B889 }

    static func deep(_ r: SeasonReward) -> UInt32 { r.colors.count > 1 ? r.colors[1] : EmblemCatalog.mix(tint(r), 0x000000, 0.7) }

    static func accent(_ look: [String: String]) -> Color? {
        reward(look, .theme).map { Color(hex: tint($0)) }
    }

    static func plate(_ r: SeasonReward) -> LinearGradient {
        LinearGradient(colors: [Color(hex: EmblemCatalog.mix(deep(r), tint(r), 0.22)), Color(hex: deep(r))], startPoint: .top, endPoint: .bottom)
    }

    static func ink(_ r: SeasonReward) -> Color { Color(hex: tint(r)) }

    @MainActor static func company(_ store: GameStore) -> String {
        store.engine?.state.companies.first { $$0.status.isLive }?.name ?? ""
    }
}

struct LookBackdrop: View {
    var look: [String: String]

    var body: some View {
        if let r = LookKit.reward(look, .backdrop) {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: EmblemCatalog.mix(LookKit.tint(r), 0x000000, 0.1)), Color(hex: LookKit.deep(r))], startPoint: .top, endPoint: .bottom))
        }
    }
}

struct LookNamePlate: View {
    var look: [String: String]
    var name: String

    var body: some View {
        let plate: SeasonReward? = LookKit.reward(look, .namePlate)
        let flair: SeasonReward? = LookKit.reward(look, .richListFlair)
        HStack(spacing: Theme.Space.xs) {
            if let plate {
                Text(name).textStyle(.title, tint: LookKit.ink(plate)).lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.xs)
                    .background(Capsule().fill(LookKit.plate(plate)))
                    .overlay(Capsule().strokeBorder(LookKit.ink(plate).opacity(0.5), lineWidth: 1))
            } else {
                Text(name).textStyle(.title).lineLimit(1).minimumScaleFactor(0.7)
            }
            if let flair { ItemArt(reward: flair, rarity: GoldCosmetics.cosmetic(flair.id)?.rarity, size: 24) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct LookTradeChip: View {
    var look: [String: String]
    var company: String

    var body: some View {
        if let plate = LookKit.reward(look, .tradePlate), !company.isEmpty {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "storefront.fill").font(.caption.weight(.semibold))
                Text(company).textStyle(.caption, tint: LookKit.ink(plate), weight: .semibold).lineLimit(1)
            }
            .foregroundStyle(LookKit.ink(plate))
            .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.xxs + 2)
            .background(Capsule().fill(LookKit.plate(plate)))
            .accessibilityElement(children: .combine)
        }
    }
}

struct EquippedSummary: View {
    var look: [String: String]
    var avatar: String?
    var onPick: ((LookCategory) -> Void)? = nil

    private func worn(_ c: LookCategory) -> String {
        if c == .avatar { return avatar.flatMap { AvatarCatalog.def($0)?.title } ?? "Default" }
        guard let kind = c.kind else { return "None" }
        return LookKit.reward(look, kind)?.title ?? "None"
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(LookCategory.allCases.enumerated()), id: \.element.id) { (i: Int, c: LookCategory) in
                if i > 0 { Hairline() }
                if let onPick {
                    Button { onPick(c) } label: { row(c) }.buttonStyle(PressableStyle())
                } else {
                    row(c)
                }
            }
        }
    }

    private func row(_ c: LookCategory) -> some View {
        HStack {
            Text(c.title).textStyle(.body, tint: Theme.inkSoft)
            Spacer(minLength: Theme.Space.s)
            Text(worn(c)).textStyle(.body).lineLimit(1)
        }
        .frame(minHeight: 40)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct LookView: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @Environment(Entitlements.self) private var ent
    @ObservedObject private var season = SeasonModel.shared
    @ObservedObject private var avatars = AvatarModel.shared
    @ObservedObject private var local = ProfileLocal.shared
    private let session = StoreSession.shared
    @State private var category: LookCategory = .avatar
    @State private var trial: [String: String] = [:]
    @State private var showColours = false

    private var worn: [String: String] { season.pass.equipped }
    private var shown: [String: String] { worn.merging(trial) { (_: String, new: String) -> String in new } }
    private var shownAvatar: String? { trial[LookCategory.avatar.rawValue] ?? avatars.equipped }

    var body: some View {
        let cabinet: Cabinet = session.state.cabinet
        PhonePageScroll(spacing: Theme.Space.l) {
            preview
            OnlineGroup(title: "Equipped", footer: "Tap a line to change it.") {
                EquippedSummary(look: worn, avatar: avatars.equipped) { (c: LookCategory) in Haptics.choose(); category = c }
            }
            chips
            picker(category, cabinet: cabinet)
            OnlineGroup(title: "", footer: "Company colours and logo badges unlock with Ledger Pro and your career.") {
                Button { Haptics.tap(); showColours = true } label: { OnlineLine(glyph: Glyph.luxury, title: "Colours and logo badge", note: "Your company logo on the home screen", chevron: true) }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("look-colours")
            }
        }
        .appScreen(title: "Your look", subtitle: "Wear what you have won and bought")
        .centerSheet(isPresented: $showColours, title: "Colours and badge", size: .tall) { WardrobeView() }
        .task {
            await session.load()
            if let e = store.engine { avatars.note(rank: e.careerStatus.rank.index, badges: e.careerCosmetics, level: e.playerLevel.level) }
        }
    }

    private var preview: some View {
        let name: String = local.name.isEmpty ? (store.engine?.state.player.name ?? "You") : local.name
        let accent: Color = LookKit.accent(shown) ?? Theme.accent
        return VStack(spacing: Theme.Space.s) {
            Group {
                if let id = shownAvatar, trial[LookCategory.avatar.rawValue] != nil { ItemArt(avatar: id, size: 84) } else { ProfilePicture(name: name, size: 84) }
            }
            .overlay(Circle().strokeBorder(accent, lineWidth: 2).frame(width: 90, height: 90))
            LookNamePlate(look: shown, name: name)
            LookTradeChip(look: shown, company: LookKit.company(store))
            if !trial.isEmpty { Text("Preview. Equip it to keep it.").textStyle(.caption, tint: Theme.accent) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.l).padding(.horizontal, Theme.Space.m)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.inset)
                LookBackdrop(look: shown)
            }
        )
        .accessibilityElement(children: .contain)
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.s) {
                ForEach(LookCategory.allCases) { (c: LookCategory) in
                    let on: Bool = c == category
                    Button { Haptics.choose(); category = c } label: {
                        Text(c.title).textStyle(.body, tint: on ? Theme.ink : Theme.inkSoft, weight: on ? .semibold : .regular)
                            .padding(.horizontal, Theme.Space.l).frame(minHeight: 44)
                            .background(Capsule().fill(on ? Theme.accentWash : Theme.inset))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private func picker(_ c: LookCategory, cabinet: Cabinet) -> some View {
        if let kind = c.kind {
            let owned: [SeasonReward] = season.pass.owned.compactMap { SeasonRewards.item($0) }.filter { $0.kind == kind }.sorted { $0.title < $1.title }
            if owned.isEmpty { empty(c) } else { rewardGrid(c, kind: kind, owned: owned) }
        } else {
            avatarGrid(cabinet)
        }
    }

    private func empty(_ c: LookCategory) -> some View {
        OnlineGroup(title: c.title, footer: c.appliedAt) {
            Text("You do not own a " + c.title.lowercased() + " yet. Open boxes or visit the store.").textStyle(.body, tint: Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true).padding(.vertical, Theme.Space.s).frame(minHeight: 52, alignment: .leading)
            Hairline()
            NavigationLink { StoreShelfView() } label: { OnlineLine(glyph: Glyph.luxury, title: "Cosmetics and bundles", note: "Bought with gold", chevron: true) }
                .buttonStyle(PressableStyle())
        }
    }

    private func rewardGrid(_ c: LookCategory, kind: SeasonReward.Kind, owned: [SeasonReward]) -> some View {
        let key: String = kind.rawValue
        let current: String? = worn[key]
        let chosen: SeasonReward = owned.first { $0.id == (trial[key] ?? current) } ?? owned[0]
        let on: Bool = current == chosen.id
        return VStack(spacing: Theme.Space.m) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
                ForEach(owned) { (r: SeasonReward) in
                    cell(title: r.title, selected: r.id == chosen.id, worn: r.id == current) {
                        ItemArt(reward: r, rarity: GoldCosmetics.cosmetic(r.id)?.rarity, size: 48, wide: true)
                    } action: { Haptics.choose(); trial[key] = r.id == current ? nil : r.id }
                }
            }
            detail(title: chosen.title, note: chosen.detail, rarity: GoldCosmetics.cosmetic(chosen.id)?.rarity, applied: c.appliedAt, worn: on) {
                Haptics.success()
                season.equip(chosen.id)
                trial[key] = nil
            }
        }
    }

    private func avatarGrid(_ cabinet: Cabinet) -> some View {
        let key: String = LookCategory.avatar.rawValue
        let owned: [AvatarDef] = AvatarCatalog.all.filter { avatars.isUnlocked($0, pro: ent.isPro, cabinet: cabinet) }
        let current: String? = avatars.equipped
        let chosenID: String = trial[key] ?? current ?? owned.first?.id ?? ""
        let chosen: AvatarDef? = AvatarCatalog.def(chosenID)
        return VStack(spacing: Theme.Space.m) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
                ForEach(owned) { (d: AvatarDef) in
                    cell(title: d.title, selected: d.id == chosenID, worn: d.id == current) { ItemArt(avatar: d.id, size: 48) } action: {
                        Haptics.choose(); trial[key] = d.id == current ? nil : d.id
                    }
                }
            }
            if let chosen {
                detail(title: chosen.title, note: chosen.requirement, rarity: chosen.tier, applied: LookCategory.avatar.appliedAt, worn: current == chosen.id) {
                    Haptics.success()
                    avatars.equip(chosen.id)
                    trial[key] = nil
                    Task { _ = await online.update(ProfileUpdate(avatarIcon: chosen.id)) }
                }
            }
            NavigationLink { AvatarPickerView() } label: {
                Text("All icons and how to unlock them").textStyle(.body, tint: Theme.accent).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func cell<Art: View>(title: String, selected: Bool, worn: Bool, @ViewBuilder art: () -> Art, action: @escaping () -> Void) -> some View {
        let built: Art = art()
        return Button(action: action) {
            VStack(spacing: 4) {
                built
                Text(title).textStyle(.caption, tint: Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.8)
                Text(worn ? "Equipped" : " ").textStyle(.caption, tint: Theme.gain).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 88).padding(.vertical, Theme.Space.xs)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(selected ? Theme.accentWash : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title + (worn ? ", equipped" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func detail(title: String, note: String, rarity: BoxRarity?, applied: String, worn: Bool, equip: @escaping () -> Void) -> some View {
        VStack(spacing: Theme.Space.s) {
            VStack(spacing: 2) {
                HStack(spacing: Theme.Space.xs) {
                    Text(title).textStyle(.headline)
                    if let rarity { RarityTag(rarity: rarity) }
                }
                Text(note).textStyle(.caption).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text(applied).textStyle(.caption, tint: Theme.inkFaint).multilineTextAlignment(.center)
            }
            if worn {
                Button {} label: { Text("Equipped").frame(maxWidth: .infinity) }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true, passive: true)).disabled(true)
            } else {
                Button(action: equip) { Text("Equip").frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("look-equip")
            }
        }
    }
}
