import SwiftUI
import GameCore
import Simulation

struct CabinetView: View {
    private let session = StoreSession.shared
    @State private var detail: ArtifactItem?

    var body: some View {
        let cabinet: Cabinet = session.state.cabinet
        PhonePageScroll(spacing: Theme.Space.l) {
            storage(cabinet)
            collections(cabinet)
        }
        .appScreen(title: "Artifacts", subtitle: "What you own")
        .task { await session.load() }
        .centerSheet(item: $detail, title: "") { (item: ArtifactItem) in ArtifactDetailCard(item: item, onDone: { detail = nil }) }
    }

    private func collections(_ cabinet: Cabinet) -> some View {
        OnlineGroup(title: "Collections", footer: "Own every artifact in a collection to earn its reward, once.") {
            VStack(spacing: Theme.Space.s) {
                ForEach(ArtifactCatalog.collections) { (col: ArtifactCollection) in CollectionCard(collection: col, cabinet: cabinet) }
            }
            .padding(.vertical, Theme.Space.s)
        }
    }

    @ViewBuilder private func storage(_ cabinet: Cabinet) -> some View {
        let items: [ArtifactItem] = cabinet.sorted
        let rows: [[ArtifactItem]] = stride(from: 0, to: items.count, by: 3).map { (i: Int) -> [ArtifactItem] in Array(items[i..<min(i + 3, items.count)]) }
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("In storage").textStyle(.label, tint: Theme.inkFaint).padding(.leading, Theme.Space.xs)
            if items.isEmpty {
                Text("Nothing here yet. Artifacts and cards come from boxes, the Season Pass, levelling and auctions.")
                    .textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true).padding(Theme.Space.m)
            } else {
                VStack(spacing: Theme.Space.m) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { (_: Int, row: [ArtifactItem]) in shelf(row) }
                }
                .padding(Theme.Space.m)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Color(hex: 0x1D1812)))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Color(hex: 0x4A3A28), lineWidth: 2))
                .accessibilityIdentifier("artifact-storage")
            }
        }
    }

    private func shelf(_ row: [ArtifactItem]) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: Theme.Space.s) {
                ForEach(row) { (item: ArtifactItem) in crate(item) }
                ForEach(0..<(3 - row.count), id: \.self) { (_: Int) in Color.clear.frame(maxWidth: .infinity) }
            }
            LinearGradient(colors: [Color(hex: 0x6B5236), Color(hex: 0x3E2F1F)], startPoint: .top, endPoint: .bottom)
                .frame(height: 8).clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
    }

    private func crate(_ item: ArtifactItem) -> some View {
        let def: ArtifactDef? = ArtifactCatalog.def(item.defID)
        let card: CardDef? = CardCatalog.def(forItem: item.id)
        let rarity: BoxRarity = def?.rarity ?? card?.rarity ?? .common
        return Button { Haptics.tap(); detail = item } label: {
            VStack(spacing: Theme.Space.xs) {
                ZStack {
                    if let card { CardThumb(def: card, width: 84) }
                    else if let def { ItemArt(artifact: def, size: 64) }
                    else { RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.inset).frame(width: 64, height: 64) }
                }
                .frame(height: 70)
                .shadow(color: rarity.tint.opacity(rarity == .common ? 0 : 0.5), radius: 8)
                Text(card?.name ?? def?.name ?? "Artifact").textStyle(.caption, tint: Theme.ink).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, Theme.Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(card?.name ?? def?.name ?? "Artifact")
        .accessibilityIdentifier("artifact-" + item.id)
    }
}

struct ArtifactDetailCard: View {
    var item: ArtifactItem
    var onDone: () -> Void
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @ObservedObject private var season = SeasonModel.shared
    @ObservedObject private var local = ProfileLocal.shared
    private let session = StoreSession.shared
    @State private var desk = PieceDesk()
    @State private var mode: Mode = .info
    @State private var friends: [PlayerProfile] = []
    @State private var pending: PendingAction?
    @State private var problem: String?

    enum Mode { case info, gift, company }

    var body: some View {
        let def: ArtifactDef? = ArtifactCatalog.def(item.defID)
        let card: CardDef? = CardCatalog.def(forItem: item.id)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            switch mode {
            case .info: info(def, card)
            case .gift: giftList
            case .company: companyList
            }
            if let problem { Text(problem).textStyle(.body, tint: Theme.loss) }
        }
        .confirmAction($pending)
        .centerSheetTitle(card?.name ?? def?.name ?? "Artifact")
    }

    @ViewBuilder private func info(_ def: ArtifactDef?, _ card: CardDef?) -> some View {
        HStack(spacing: Theme.Space.l) {
            if let card { CardThumb(def: card, width: 110) } else if let def { ItemArt(artifact: def, size: 96) }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                if let r = def?.rarity ?? card?.rarity { RarityTag(rarity: r) }
                Text(ArtifactCatalog.label(item)).textStyle(.caption)
                if item.isFirstOwner { Text("First owner").textStyle(.caption, tint: Theme.gold, weight: .semibold) }
            }
            Spacer(minLength: 0)
        }
        if let note = def?.note, !note.isEmpty { Text(note).textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true) }
        useButtons(card)
        if !item.isBound {
            Button { Haptics.tap(); mode = .gift; Task { await loadFriends() } } label: { Text("Gift to a friend").frame(maxWidth: .infinity) }
                .buttonStyle(SecondaryButtonStyle(size: .compact, fullWidth: true))
                .accessibilityIdentifier("artifact-gift")
        }
        PieceActions(item: item, desk: desk).environment(\.popupClose, { onDone() })
    }

    @ViewBuilder private func useButtons(_ card: CardDef?) -> some View {
        if let card, card.kind == .profile {
            let on: Bool = season.pass.equipped[SeasonPass.profileCardKey] == item.id
            Button { Haptics.success(); season.equipProfileCardAsking(on ? nil : item.id, pending: $pending) } label: { Text(on ? "Active on your profile" : "Set as profile active").frame(maxWidth: .infinity) }
                .buttonStyle(PrimaryButtonStyle(size: .compact, fullWidth: true))
                .accessibilityIdentifier("artifact-set-active")
        } else if let card, card.kind == .company {
            Button { Haptics.tap(); mode = .company } label: { Text("Use for a company").frame(maxWidth: .infinity) }
                .buttonStyle(PrimaryButtonStyle(size: .compact, fullWidth: true))
                .accessibilityIdentifier("artifact-use-company")
        } else {
            let at: Int? = local.showcase.firstIndex(of: item.id)
            Button { toggleShowcase() } label: { Text(at == nil ? "Show on your profile" : "Remove from your profile").frame(maxWidth: .infinity) }
                .buttonStyle(PrimaryButtonStyle(size: .compact, fullWidth: true))
                .accessibilityIdentifier("artifact-showcase")
        }
    }

    private func toggleShowcase() {
        var list: [String] = local.showcase
        if let i = list.firstIndex(of: item.id) { list.remove(at: i); problem = nil }
        else if list.count < ProfileLocal.showcaseSlots { list.append(item.id); problem = nil }
        else { Haptics.warning(); problem = "The profile showcase holds \(ProfileLocal.showcaseSlots). Take one off first."; return }
        Haptics.choose()
        local.setShowcase(list)
    }

    private var giftList: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(friends.isEmpty ? "You have no friends to send it to yet." : "Pick a friend. It leaves your storage.").textStyle(.caption)
            ForEach(friends) { (f: PlayerProfile) in
                ChoiceCard(title: f.displayName, selected: false) {
                    Task {
                        problem = await GiftSender.send(item, to: f, online: online, store: store)
                        if problem == nil { onDone() }
                    }
                }
            }
            Button("Back") { mode = .info }.buttonStyle(TertiaryButtonStyle())
        }
    }

    private var companyList: some View {
        let list: [Company] = store.engine?.state.companies.filter { (c: Company) -> Bool in c.status.isLive } ?? []
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Which company wears it?").textStyle(.caption)
            ForEach(list) { (c: Company) in
                ChoiceCard(title: c.name, selected: false) {
                    let cabinet: Cabinet = session.state.cabinet
                    let id: String = item.id
                    _ = store.act { (e: inout GameEngine) -> Void in _ = e.applyCompanyCard(itemID: id, companyID: c.id, cabinet: cabinet) }
                    Haptics.success()
                    onDone()
                }
            }
            Button("Back") { mode = .info }.buttonStyle(TertiaryButtonStyle())
        }
    }

    private func loadFriends() async {
        guard online.isSignedIn else { friends = []; return }
        friends = (try? await online.service.friends())?.friends ?? []
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
        store.engine?.state.companies.first { $0.status.isLive }?.name ?? ""
    }
}

struct BackdropFill: View {
    var reward: SeasonReward
    var scrim: Double = 0.4

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: EmblemCatalog.mix(LookKit.tint(reward), 0x000000, 0.1)), Color(hex: LookKit.deep(reward))], startPoint: .top, endPoint: .bottom)
            picture
            LinearGradient(colors: [Color.black.opacity(scrim), Color.black.opacity(scrim * 0.6)], startPoint: .top, endPoint: .bottom)
        }
        .clipped()
    }

    @ViewBuilder private var picture: some View {
        #if canImport(UIKit)
        if let ui = ArtLibrary.catalogueImage(.backdrop, reward.id) {
            Color.clear.overlay { Image(uiImage: ui).resizable().scaledToFill() }.clipped()
        }
        #endif
    }
}

struct LookBackdrop: View {
    var look: [String: String]
    private let session = StoreSession.shared

    var body: some View {
        ZStack(alignment: .top) {
            if let d = LookKit.card(look, cabinet: session.state.cabinet) { CardFace(def: d) }
            if let r = LookKit.reward(look, .backdrop) {
                BackdropFill(reward: r)
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            }
        }
    }
}

struct HeaderBackdropFill: View {
    var reward: SeasonReward
    static let height: CGFloat = 240

    var body: some View {
        GeometryReader { (g: GeometryProxy) in
            let top: CGFloat = g.frame(in: .global).minY
            BackdropFill(reward: reward, scrim: 0.55)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                .frame(width: g.size.width, height: Self.height)
                .offset(y: -top)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension LookKit {
    static func item(_ id: String) -> SeasonReward? {
        id.isEmpty ? nil : SeasonRewards.item(id)
    }

    static func companyBackdrop(_ e: GameEngine, _ companyID: Int) -> SeasonReward? {
        item(e.companyBackdrop(companyID: companyID))
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
    var logoID: String = ""
    var backdrop: SeasonReward? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        HStack(spacing: Theme.Space.m) {
            if logoID.isEmpty {
                Image(systemName: def?.logo ?? "briefcase.fill")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.white.opacity(0.92))
                    .frame(width: 40, height: 40).background(Circle().fill(Color.white.opacity(0.16)))
            } else {
                LogoBadge(logoID: logoID, size: 40)
            }
            Text(name).textStyle(.headline, tint: def == nil ? Theme.ink : Color.white).lineLimit(1)
            Spacer(minLength: 0)
            if let def { RarityTag(rarity: def.rarity) }
        }
        .padding(Theme.Space.m)
        .frame(minHeight: 64)
        .background {
            ZStack {
                if let def { CardFace(def: def) } else { shape.fill(Theme.inset) }
                if let backdrop { BackdropFill(reward: backdrop, scrim: 0.45) }
            }
        }
        .clipShape(shape)
        .accessibilityElement(children: .combine)
    }
}

