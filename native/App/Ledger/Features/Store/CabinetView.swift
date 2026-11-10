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
        OnlineGroup(title: "Your artifacts and cards", footer: cabinet.items.isEmpty ? "Artifacts and cards come from boxes, the Season Pass, levelling and auctions." : (canSell ? "Tap a piece to sell it at once or in the Auctions app. Cash goes to your personal account. Wear cards in Your look." : "")) {
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

    var body: some View {
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

    private func line(_ title: String, _ value: String) -> some View {
        HStack { Text(title).textStyle(.body); Spacer(); Text(value).textStyle(.body, numeric: true) }
    }
}

enum LookCategory: String, CaseIterable, Identifiable {
    case avatar, card, theme, namePlate, backdrop, tradePlate, flair

    var id: String { rawValue }

    var kind: SeasonReward.Kind? {
        switch self {
        case .avatar, .card: return nil
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
        case .card: return "Profile card"
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
        case .card: return "Fills the background of your profile. Rare cards move."
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

    static func card(_ look: [String: String], cabinet: Cabinet) -> CardDef? {
        guard let id = look[SeasonPass.profileCardKey], cabinet.contains(id), let d = CardCatalog.def(forItem: id), d.kind == .profile else { return nil }
        return d
    }

    @MainActor static func company(_ store: GameStore) -> String {
        store.engine?.state.companies.first { $0.type != "hold" && $0.status.isLive }?.name ?? ""
    }
}

struct LookBackdrop: View {
    var look: [String: String]
    private let session = StoreSession.shared

    var body: some View {
        if let d = LookKit.card(look, cabinet: session.state.cabinet) {
            CardFace(def: d)
        } else if let r = LookKit.reward(look, .backdrop) {
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
        if c == .card { return LookKit.card(look, cabinet: StoreSession.shared.state.cabinet)?.name ?? "None" }
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

struct CompanyPick: Identifiable {
    var id: Int
}

struct LookView: View {
    var startOnCompanies = false
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
    @State private var picking: CompanyPick?

    private var worn: [String: String] { season.pass.equipped }
    private var shown: [String: String] { worn.merging(trial) { (_: String, new: String) -> String in new } }
    private var shownAvatar: String? { trial[LookCategory.avatar.rawValue] ?? avatars.equipped }

    var body: some View {
        let cabinet: Cabinet = session.state.cabinet
        PhonePageScroll(spacing: Theme.Space.l) {
            preview
            if startOnCompanies { companies(cabinet) }
            OnlineGroup(title: "Equipped", footer: "Tap a line to change it.") {
                EquippedSummary(look: worn, avatar: avatars.equipped) { (c: LookCategory) in Haptics.choose(); category = c }
            }
            chips
            picker(category, cabinet: cabinet)
            if !startOnCompanies { companies(cabinet) }
            OnlineGroup(title: "", footer: "Company colours and logo badges unlock with Ledger Pro and your career.") {
                Button { Haptics.tap(); showColours = true } label: { OnlineLine(glyph: Glyph.luxury, title: "Colours and logo badge", note: "Your company logo on the home screen", chevron: true) }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("look-colours")
            }
        }
        .appScreen(title: "Your look", subtitle: "Wear what you have won and bought")
        .centerSheet(isPresented: $showColours, title: "Colours and badge", size: .tall) { WardrobeView() }
        .centerSheet(item: $picking, title: "Company card", size: .tall) { (p: CompanyPick) in CompanyCardPicker(companyID: p.id) }
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
        if c == .card {
            cardGrid(cabinet)
        } else if let kind = c.kind {
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

    private func cardGrid(_ cabinet: Cabinet) -> some View {
        let key: String = SeasonPass.profileCardKey
        let owned: [ArtifactItem] = cabinet.sorted.filter { CardCatalog.def(forItem: $0.id)?.kind == .profile }
        let current: String? = worn[key].flatMap { (id: String) -> String? in cabinet.contains(id) ? id : nil }
        let chosenID: String? = trial[key] ?? current ?? owned.first?.id
        return Group {
            if owned.isEmpty {
                OnlineGroup(title: LookCategory.card.title, footer: LookCategory.card.appliedAt) {
                    Text("You do not own a profile card yet. Open a card pack, climb the Season Pass or level up.").textStyle(.body, tint: Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true).padding(.vertical, Theme.Space.s).frame(minHeight: 52, alignment: .leading)
                    Hairline()
                    NavigationLink { StoreApp() } label: { OnlineLine(glyph: Glyph.luxury, title: "Card packs", note: "Basic, premium and elite, with the odds shown", chevron: true) }
                        .buttonStyle(PressableStyle())
                }
            } else {
                VStack(spacing: Theme.Space.m) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
                        ForEach(owned) { (item: ArtifactItem) in
                            if let d = CardCatalog.def(forItem: item.id) {
                                cell(title: d.name, selected: item.id == chosenID, worn: item.id == current) { CardThumb(def: d, width: 72) } action: {
                                    Haptics.choose(); trial[key] = item.id == current ? nil : item.id
                                }
                            }
                        }
                    }
                    if let item = owned.first(where: { (i: ArtifactItem) -> Bool in i.id == chosenID }), let d = CardCatalog.def(forItem: item.id) {
                        detail(title: d.name, note: (d.isAnimated ? "Animated. " : "") + ArtifactCatalog.label(item), rarity: d.rarity, applied: LookCategory.card.appliedAt, worn: current == item.id) {
                            Haptics.success()
                            season.equipProfileCard(item.id)
                            trial[key] = nil
                        }
                    }
                    if current != nil {
                        Button { Haptics.choose(); season.equipProfileCard(nil); trial[key] = nil } label: { Text("Wear no card").frame(maxWidth: .infinity) }
                            .buttonStyle(TertiaryButtonStyle())
                    }
                }
            }
        }
    }

    @ViewBuilder private func companies(_ cabinet: Cabinet) -> some View {
        if let e = store.engine {
            let live: [Company] = e.state.companies.filter { $0.status.isLive }
            if !live.isEmpty {
                OnlineGroup(title: "Companies", footer: "Each company card can be used by one company at a time. Using it on another company moves it.") {
                    ForEach(Array(live.enumerated()), id: \.element.id) { (i: Int, co: Company) in
                        if i > 0 { Hairline() }
                        Button { Haptics.tap(); picking = CompanyPick(id: co.id) } label: {
                            HStack(spacing: Theme.Space.m) {
                                CompanyCardView(name: co.name, def: e.companyCard(co.id, cabinet: cabinet)).frame(maxWidth: .infinity)
                                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
                            }
                            .padding(.vertical, Theme.Space.xs)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel(co.name + ", company card")
                        .accessibilityIdentifier("look-company-" + String(co.id))
                    }
                }
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

struct CardMotion: View {
    var def: CardDef

    private func tone(_ i: Int) -> Color { Color(hex: def.colors[min(i, def.colors.count - 1)]) }

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { (ctx: TimelineViewDefaultContext) in
                layer(ctx.date.timeIntervalSinceReferenceDate, geo.size)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func layer(_ t: Double, _ size: CGSize) -> some View {
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        switch def.motion {
        case .none:
            EmptyView()
        case .shimmer:
            let p: Double = t.truncatingRemainder(dividingBy: 5) / 5
            LinearGradient(colors: [.clear, Color.white.opacity(0.24), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: w * 0.45, height: h * 2.4)
                .rotationEffect(.degrees(22))
                .offset(x: CGFloat(p * 2 - 1) * w * 0.8)
        case .drift:
            ZStack {
                Circle().fill(RadialGradient(colors: [tone(0).opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: w * 0.4))
                    .frame(width: w * 0.8, height: w * 0.8)
                    .offset(x: CGFloat(sin(t * 0.45)) * w * 0.28, y: CGFloat(cos(t * 0.35)) * h * 0.3)
                Circle().fill(RadialGradient(colors: [tone(1).opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: w * 0.4))
                    .frame(width: w * 0.8, height: w * 0.8)
                    .offset(x: CGFloat(cos(t * 0.3)) * w * 0.28, y: CGFloat(sin(t * 0.5)) * h * 0.3)
            }
        case .pulse:
            RadialGradient(colors: [tone(0).opacity(0.3 + 0.2 * sin(t * 1.1)), .clear], center: .center, startRadius: 0, endRadius: max(w, h) * 0.6)
        case .aurora:
            ZStack {
                Ellipse().fill(tone(0)).frame(width: w * 0.9, height: h * 0.5)
                    .offset(x: CGFloat(sin(t * 0.4)) * w * 0.25, y: CGFloat(cos(t * 0.3)) * h * 0.2)
                Ellipse().fill(tone(1)).frame(width: w * 0.8, height: h * 0.5)
                    .offset(x: CGFloat(cos(t * 0.35)) * w * 0.25, y: CGFloat(sin(t * 0.45)) * h * 0.2)
            }
            .blur(radius: 22)
            .opacity(0.4)
            .blendMode(.plusLighter)
        }
    }
}

struct CardFace: View {
    var def: CardDef
    var radius: CGFloat = Theme.Radius.card
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rim: Double {
        switch def.rarity {
        case .common: return 0.08
        case .rare: return 0.16
        case .epic: return 0.26
        case .legendary: return 0.38
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: def.colors.map { (c: UInt32) -> Color in Color(hex: c) }, startPoint: .topLeading, endPoint: .bottomTrailing))
            if def.isAnimated && !reduceMotion { CardMotion(def: def) }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(rim), lineWidth: 1))
    }
}

struct CardThumb: View {
    var def: CardDef
    var width: CGFloat = 64

    var body: some View {
        ZStack {
            CardFace(def: def, radius: Theme.Radius.small)
            if !def.logo.isEmpty {
                Image(systemName: def.logo).font(.system(size: width * 0.3, weight: .semibold)).foregroundStyle(Color.white.opacity(0.92))
            }
        }
        .frame(width: width, height: width * 0.62)
        .overlay(alignment: .topTrailing) {
            if def.isAnimated { Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.white.opacity(0.9)).padding(4) }
        }
        .accessibilityHidden(true)
    }
}

struct CompanyCardView: View {
    var name: String
    var def: CardDef?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        HStack(spacing: Theme.Space.m) {
            Image(systemName: def?.logo ?? "briefcase.fill")
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.white.opacity(0.92))
                .frame(width: 40, height: 40).background(Circle().fill(Color.white.opacity(0.16)))
            Text(name).textStyle(.headline, tint: def == nil ? Theme.ink : Color.white).lineLimit(1)
            Spacer(minLength: 0)
            if let def { RarityTag(rarity: def.rarity) }
        }
        .padding(Theme.Space.m)
        .frame(minHeight: 64)
        .background {
            if let def { CardFace(def: def) } else { shape.fill(Theme.inset) }
        }
        .clipShape(shape)
        .accessibilityElement(children: .combine)
    }
}

struct CompanyCardBanner: View {
    @EnvironmentObject var store: GameStore
    var company: Company
    private let session = StoreSession.shared

    var body: some View {
        if let e = store.engine, let d = e.companyCard(company.id, cabinet: session.state.cabinet) {
            CompanyCardView(name: company.name, def: d)
        }
    }
}

struct CompanyCardLink: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var company: Company
    @State private var open = false
    private let session = StoreSession.shared

    var body: some View {
        let d: CardDef? = store.engine?.companyCard(company.id, cabinet: session.state.cabinet)
        PageGroup("Look") {
            LedgerRow(leading: .glyph(Glyph.luxury), leadingTint: P.inkSoft, title: "Company card", subtitle: d?.name ?? "Colours, logo and animated cards",
                      identifier: "manage-card") { open = true }
        }
        .navigationDestination(isPresented: $open) { LookView(startOnCompanies: true) }
    }
}

struct CompanyCardPicker: View {
    var companyID: Int
    @EnvironmentObject var store: GameStore
    @Environment(\.popupClose) private var popupClose
    private let session = StoreSession.shared

    var body: some View {
        let cabinet: Cabinet = session.state.cabinet
        let owned: [ArtifactItem] = cabinet.sorted.filter { CardCatalog.def(forItem: $0.id)?.kind == .company }
        let used: [Int: String] = store.engine?.companyCardAssignments() ?? [:]
        let names: [Int: String] = Dictionary((store.engine?.state.companies ?? []).map { (c: Company) -> (Int, String) in (c.id, c.name) }, uniquingKeysWith: { (a: String, _: String) -> String in a })
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if owned.isEmpty {
                Text("You do not own a company card yet. Open a card pack, climb the Season Pass or level up.").textStyle(.body, tint: Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(owned) { (item: ArtifactItem) in
                    if let d = CardCatalog.def(forItem: item.id) {
                        row(item, d, usedBy: used.first(where: { (_: Int, v: String) -> Bool in v == item.id })?.key, names: names)
                    }
                }
                if used[companyID] != nil {
                    Button { Haptics.choose(); remove() } label: { Text("Remove the card").frame(maxWidth: .infinity) }
                        .buttonStyle(TertiaryButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ item: ArtifactItem, _ d: CardDef, usedBy: Int?, names: [Int: String]) -> some View {
        let here: Bool = usedBy == companyID
        let note: String
        if here { note = "On this company" }
        else if let other = usedBy { note = "Used by " + (names[other] ?? "another company") + ". Using it here moves it." }
        else { note = "Not in use" }
        return Button { apply(item) } label: {
            HStack(spacing: Theme.Space.m) {
                CardThumb(def: d, width: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name).textStyle(.headline)
                    HStack(spacing: Theme.Space.xs) {
                        RarityTag(rarity: d.rarity)
                        Text(ArtifactCatalog.label(item)).textStyle(.caption)
                    }
                    Text(note).textStyle(.caption, tint: here ? Theme.gain : Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Theme.Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(d.name + ", " + note)
    }

    private func apply(_ item: ArtifactItem) {
        Haptics.success()
        let cabinet: Cabinet = session.state.cabinet
        let id: Int = companyID
        _ = store.act { (e: inout GameEngine) -> Void in _ = e.applyCompanyCard(itemID: item.id, companyID: id, cabinet: cabinet) }
        popupClose?()
    }

    private func remove() {
        let id: Int = companyID
        _ = store.act { (e: inout GameEngine) -> Void in e.clearCompanyCard(companyID: id) }
        popupClose?()
    }
}
