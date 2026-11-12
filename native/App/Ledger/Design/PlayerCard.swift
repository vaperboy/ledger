import SwiftUI
import GameCore
import Simulation

struct PlayerCardFigure: Identifiable, Equatable {
    var title: String
    var value: String
    var id: String { title }
}

/// Everything the player card shows. Built from your own data or from a shared online profile.
struct PlayerCardData {
    var name: String
    var username: String = ""
    var title: String = ""
    var levelText: String = ""
    var detail: String = ""
    var avatar: AvatarLook
    /// Worn items by kind: backdrop, namePlate, richListFlair, theme, profileCard (item or card id).
    var worn: [String: String] = [:]
    var badgeIcons: [String] = []
    var badgeTexts: [String] = []
    var figures: [PlayerCardFigure] = []
    /// Shown in place of level, badges and figures when the player keeps them private.
    var privateNote: String? = nil
    var hallOfFame = false
}

extension PlayerCardData {
    /// Another player's card from the shared profile; private profiles keep their details hidden.
    init(profile p: PlayerProfile) {
        let shared = ProfileLookCode.decode(p.avatarLook)
        let hidden: Bool = p.relation != .you && p.privacy == .onlyMe
        var figures: [PlayerCardFigure] = []
        if let l = p.level { figures.append(PlayerCardFigure(title: "Level", value: "\(l)")) }
        if let n = p.companyCount { figures.append(PlayerCardFigure(title: "Companies", value: "\(n)")) }
        if let w = p.gameWeek { figures.append(PlayerCardFigure(title: "Week", value: "\(w + 1)")) }
        if let t = p.tradesCompleted, figures.count < 3 { figures.append(PlayerCardFigure(title: "Trades", value: "\(t)")) }
        let texts: [String] = p.badges.filter { (b: String) -> Bool in b != HallOfFameBadge.name }
        self.init(name: p.displayName,
                  levelText: p.level.map { (l: Int) -> String in "Level \(l)" } ?? "",
                  detail: hidden ? "" : p.subline,
                  avatar: shared?.avatar ?? AvatarLook.generated(for: p.displayName),
                  worn: hidden ? [:] : (shared?.worn ?? [:]),
                  badgeIcons: hidden ? [] : (shared?.badges ?? []),
                  badgeTexts: hidden ? [] : Array(texts.prefix(2)),
                  figures: hidden ? [] : figures,
                  privateNote: hidden ? "This player keeps their profile private." : nil,
                  hallOfFame: p.badges.contains(HallOfFameBadge.name))
    }
}

/// The one player card, used wherever a player is shown in full: a backdrop across the top with the name plate on it,
/// the half-body avatar standing on the left across the backdrop edge, then title, level, badges and three figures.
struct PlayerCard: View {
    var data: PlayerCardData
    var onRename: (() -> Void)? = nil

    private static let avatarWidth: CGFloat = 120
    private static let backdropHeight: CGFloat = 96

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        let ringItem: SeasonReward? = LookKit.item(data.worn["theme"] ?? "")
        let accent: Color = ringItem.map { (r: SeasonReward) -> Color in Color(hex: LookKit.tint(r)) } ?? Theme.gold
        VStack(spacing: 0) {
            top(accent: accent)
            info
        }
        .frame(maxWidth: .infinity)
        .background(shape.fill(Theme.surfaceRaised))
        .overlay(alignment: .bottomLeading) { avatar(accent: accent, framed: ringItem != nil) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(ringItem == nil ? Theme.line : accent.opacity(0.8), lineWidth: ringItem == nil ? 1 : 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile-card")
    }

    private var backdrop: SeasonReward? { LookKit.item(data.worn["backdrop"] ?? "") }
    private var cardDef: CardDef? { data.worn["profileCard"].flatMap { (id: String) -> CardDef? in CardCatalog.def(forItem: id) } }

    private func top(accent: Color) -> some View {
        ZStack(alignment: .bottomLeading) {
            backdropFill
            plateRow
        }
        .frame(height: Self.backdropHeight)
        .clipped()
    }

    @ViewBuilder private var backdropFill: some View {
        if let b = backdrop {
            BackdropFill(reward: b, scrim: 0.3)
        } else if let d = cardDef {
            CardFace(def: d, radius: 0)
        } else {
            LinearGradient(colors: [Theme.accent.opacity(0.32), Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var plateRow: some View {
        HStack(spacing: Theme.Space.xs) {
            if let onRename {
                NameTapLabel(label: data.name, tint: Theme.ink, action: onRename) { CardNamePlate(name: data.name, worn: data.worn) }
            } else {
                CardNamePlate(name: data.name, worn: data.worn)
            }
            if data.hallOfFame { HallOfFameMark() }
            Spacer(minLength: 0)
        }
        .padding(.leading, Self.avatarWidth + Theme.Space.l + Theme.Space.s).padding(.trailing, Theme.Space.m).padding(.bottom, Theme.Space.s)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if !data.username.isEmpty && data.username != data.name {
                Text("@" + data.username).textStyle(.caption, tint: Theme.inkSoft).lineLimit(1)
            }
            let line: String = [data.title, data.levelText].filter { (s: String) -> Bool in !s.isEmpty }.joined(separator: " \u{00B7} ")
            if !line.isEmpty { Text(line).textStyle(.body, tint: Theme.ink, weight: .medium).lineLimit(1).minimumScaleFactor(0.8) }
            if !data.detail.isEmpty { Text(data.detail).textStyle(.caption).lineLimit(1) }
            if let note = data.privateNote {
                Text(note).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            } else {
                badges
                figures
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.avatarWidth * AvatarArt.aspect - Self.backdropHeight + Theme.Space.l, alignment: .topLeading)
        .padding(.leading, Self.avatarWidth + Theme.Space.l + Theme.Space.s).padding(.trailing, Theme.Space.m)
        .padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.m)
    }

    @ViewBuilder private var badges: some View {
        if !data.badgeIcons.isEmpty || !data.badgeTexts.isEmpty {
            HStack(spacing: Theme.Space.xs) {
                ForEach(data.badgeIcons, id: \.self) { (id: String) in
                    if AvatarCatalog.def(id) != nil { ItemArt(avatar: id, size: 28) }
                }
                ForEach(data.badgeTexts, id: \.self) { (t: String) in
                    Text(t).textStyle(.caption, tint: Theme.accent).lineLimit(1)
                        .padding(.horizontal, Theme.Space.s).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.accentWash))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Badges")
        }
    }

    @ViewBuilder private var figures: some View {
        if !data.figures.isEmpty {
            HStack(spacing: Theme.Space.xs) {
                ForEach(data.figures.prefix(3)) { (f: PlayerCardFigure) in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.value).textStyle(.headline, numeric: true).lineLimit(1).minimumScaleFactor(0.6)
                        Text(f.title).textStyle(.label, tint: Theme.inkFaint).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.inset))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func avatar(accent: Color, framed: Bool) -> some View {
        ZStack(alignment: .bottom) {
            Circle().fill(accent.opacity(framed ? 0.3 : 0.12)).frame(width: Self.avatarWidth * 0.86, height: Self.avatarWidth * 0.86)
                .offset(y: -Self.avatarWidth * 0.34)
            HalfBodyAvatar(look: data.avatar, width: Self.avatarWidth)
        }
        .frame(width: Self.avatarWidth)
        .padding(.leading, Theme.Space.m)
        .accessibilityHidden(true)
    }
}

/// The name on its plate. The plate takes its backdrop and sheen from the worn backdrop, its trim from the worn plate.
struct CardNamePlate: View {
    var name: String
    var worn: [String: String]

    var body: some View {
        let plate: SeasonReward? = LookKit.item(worn["namePlate"] ?? "")
        let backdrop: SeasonReward? = LookKit.item(worn["backdrop"] ?? "")
        let flair: SeasonReward? = LookKit.item(worn["richListFlair"] ?? "")
        let ink: Color = plate.map { (r: SeasonReward) -> Color in LookKit.ink(r) } ?? Theme.ink
        let source: SeasonReward? = backdrop ?? plate
        let rarity: BoxRarity? = backdrop.flatMap { (r: SeasonReward) -> BoxRarity? in r.rarity ?? GoldCosmetics.cosmetic(r.id)?.rarity }
        let sheen: Bool = (rarity ?? .common) >= .epic
        HStack(spacing: Theme.Space.xs) {
            Text(name).textStyle(.title, tint: ink).lineLimit(1).minimumScaleFactor(0.6)
            if let flair { ItemArt(reward: flair, rarity: GoldCosmetics.cosmetic(flair.id)?.rarity, size: 24) }
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.xs)
        .background { plateFill(source) }
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ink.opacity(plate == nil ? 0.18 : 0.55), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .storeSheen(radius: 12, enabled: sheen, strength: 0.25)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func plateFill(_ source: SeasonReward?) -> some View {
        if let source {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(LookKit.plate(source))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.42))
        }
    }
}
