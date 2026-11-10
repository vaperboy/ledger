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
        OnlineGroup(title: "Your artifacts and cards", footer: cabinet.items.isEmpty ? "Artifacts and cards come from boxes, the Season Pass, levelling and auctions." : (canSell ? "Tap a piece to sell it at once or in the Auctions app. Cash goes to your personal account. Wear cards in Customise." : "")) {
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
            if let def { CardFace(def: def) } else { shape.fill(Theme.inset) }
        }
        .clipShape(shape)
        .accessibilityElement(children: .combine)
    }
}

