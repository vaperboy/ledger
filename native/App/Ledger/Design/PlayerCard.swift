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
    /// Worn items by kind: backdrop, richListFlair, theme, profileCard (item or card id).
    var worn: [String: String] = [:]
    /// Kept so stored and shared profiles still decode; the card does not show badges.
    var badgeIcons: [String] = []
    var badgeTexts: [String] = []
    var figures: [PlayerCardFigure] = []
    /// Shown in place of level, badges and figures when the player keeps them private.
    var privateNote: String? = nil
    var hallOfFame = false
    /// Badges that cannot be bought (badge.creator, badge.beta), shown beside the name.
    var exclusiveBadges: [String] = []
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
        let texts: [String] = p.badges.filter { (b: String) -> Bool in b != HallOfFameBadge.name && ProfileBadge(rawValue: b) == nil }
        self.init(name: p.displayName,
                  levelText: p.level.map { (l: Int) -> String in "Level \(l)" } ?? "",
                  detail: hidden ? "" : p.subline,
                  avatar: shared?.avatar ?? AvatarLook.generated(for: p.displayName),
                  worn: hidden ? [:] : (shared?.worn ?? [:]),
                  badgeIcons: hidden ? [] : (shared?.badges ?? []),
                  badgeTexts: hidden ? [] : Array(texts.prefix(2)),
                  figures: hidden ? [] : figures,
                  privateNote: hidden ? "This player keeps their profile private." : nil,
                  hallOfFame: p.badges.contains(HallOfFameBadge.name),
                  exclusiveBadges: ProfileBadge.exclusive(in: p.badges))
    }
}

/// A part of the card a player can tap to change it.
enum CardPart: String, CaseIterable, Identifiable {
    case backdrop, flair, character

    var id: String { rawValue }
}

/// The one player card, used wherever a player is shown in full.
/// The backdrop fills the whole card. The top part is picture only (the avatar stands in it, no text); a dark scrim rises from the bottom
/// so the name, title, level and figures sit on a calm area, never on busy art.
///
/// Backdrop art spec (slot `art.backdrop.<id>`, or `backdrop.<id>.png` in the art folder): one 4:3 landscape picture, 1600 x 1200 px,
/// drawn aspect-fill and centred, so it is cropped on tall or wide cards. Keep the subject inside the middle 70% and in the upper 55%
/// (the avatar covers the middle, the bottom 45% sits under the scrim, so keep it low in detail and dark). No text or logos in the art.
struct PlayerCard: View {
    var data: PlayerCardData
    var onRename: (() -> Void)? = nil
    /// When set, every part of the card is tappable and empty slots show a "+".
    var onPart: ((CardPart) -> Void)? = nil

    private static let avatarWidth: CGFloat = 150
    static let pictureHeight: CGFloat = 176

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        VStack(spacing: 0) {
            picture
            info
        }
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                backdropFill
                    .contentShape(Rectangle())
                    .onTapGesture { if let onPart { Haptics.tap(); onPart(.backdrop) } }
                    .accessibilityHidden(true)
                scrim.allowsHitTesting(false)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile-card")
    }

    private var backdrop: SeasonReward? { LookKit.item(data.worn["backdrop"] ?? "") }
    private var cardDef: CardDef? { data.worn["profileCard"].flatMap { (id: String) -> CardDef? in CardCatalog.def(forItem: id) } }
    private var flair: SeasonReward? { LookKit.item(data.worn["richListFlair"] ?? "") }

    @ViewBuilder private var backdropFill: some View {
        if let b = backdrop {
            BackdropFill(reward: b, scrim: 0.12)
        } else if let d = cardDef {
            CardFace(def: d, radius: 0)
        } else {
            LinearGradient(colors: [Theme.accent.opacity(0.4), Color(hex: 0x1A1B1D)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// Clear over the picture, then darker down to the text area.
    private var scrim: some View {
        LinearGradient(stops: [.init(color: Color.black.opacity(0), location: 0),
                               .init(color: Color.black.opacity(0), location: 0.3),
                               .init(color: Color.black.opacity(0.72), location: 0.58),
                               .init(color: Color.black.opacity(0.9), location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }

    private var picture: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            avatarView
            if let onPart, backdrop == nil, cardDef == nil {
                AddChip(title: "Backdrop") { onPart(.backdrop) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(Theme.Space.m)
            }
        }
        .frame(height: Self.pictureHeight)
    }

    @ViewBuilder private var avatarView: some View {
        let art = HalfBodyAvatar(look: data.avatar, width: Self.avatarWidth)
            .frame(width: Self.avatarWidth, height: Self.pictureHeight, alignment: .bottom)
            .clipped()
        if let onPart {
            Button { Haptics.tap(); onPart(.character) } label: { art.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel("Character")
                .accessibilityIdentifier("card-part-character")
        } else {
            art.accessibilityHidden(true)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            nameRow
            if !data.username.isEmpty && data.username != data.name {
                Text("@" + data.username).textStyle(.caption, tint: Theme.inkSoft).lineLimit(1)
            }
            let line: String = [data.title, data.levelText].filter { (s: String) -> Bool in !s.isEmpty }.joined(separator: " \u{00B7} ")
            if !line.isEmpty { Text(line).textStyle(.body, tint: Theme.ink, weight: .medium).lineLimit(1).minimumScaleFactor(0.8) }
            if !data.detail.isEmpty { Text(data.detail).textStyle(.caption, tint: Theme.inkSoft).lineLimit(1) }
            if let note = data.privateNote {
                Text(note).textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            } else {
                figures
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.l).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.l)
    }

    private var nameRow: some View {
        HStack(spacing: Theme.Space.s) {
            nameLabel
            flairView
            if data.hallOfFame { HallOfFameMark() }
            ProfileBadgeRow(ids: data.exclusiveBadges)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder private var nameLabel: some View {
        let view = Text(data.name).textStyle(.title, tint: Theme.ink, weight: .semibold)
            .lineLimit(1).minimumScaleFactor(0.6)
            .shadow(color: Color.black.opacity(0.55), radius: 6, x: 0, y: 1)
            .accessibilityLabel(data.name)
        if onPart == nil, let onRename {
            NameTapLabel(label: data.name, tint: Theme.ink, action: onRename) { view }
        } else {
            view
        }
    }

    @ViewBuilder private var flairView: some View {
        if let flair {
            let art = ItemArt(reward: flair, rarity: GoldCosmetics.cosmetic(flair.id)?.rarity, size: 28)
            if let onPart {
                Button { Haptics.tap(); onPart(.flair) } label: { art.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Flair")
                    .accessibilityIdentifier("card-part-flair")
            } else {
                art
            }
        } else if let onPart {
            AddChip(title: "Flair") { onPart(.flair) }
        }
    }

    @ViewBuilder private var figures: some View {
        if !data.figures.isEmpty {
            HStack(spacing: Theme.Space.xs) {
                ForEach(data.figures.prefix(3)) { (f: PlayerCardFigure) in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.value).textStyle(.headline, numeric: true).lineLimit(1).minimumScaleFactor(0.6)
                        Text(f.title).textStyle(.label, tint: Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Color.white.opacity(0.08)))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// A small "+" button shown on an empty slot of your own card.
struct AddChip: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                Text(title).textStyle(.caption, tint: Theme.ink, weight: .semibold)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, Theme.Space.m).frame(minHeight: 32)
            .background(Capsule().fill(Color.black.opacity(0.5)))
            .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Add " + title.lowercased())
        .accessibilityIdentifier("card-add-" + title.lowercased())
    }
}
