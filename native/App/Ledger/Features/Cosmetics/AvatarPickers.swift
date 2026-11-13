import SwiftUI

/// A selectable tile used by the avatar pickers.
struct AvatarPickTile<Art: View>: View {
    var title: String
    var selected: Bool
    var locked: Bool = false
    var note: String = ""
    var identifier: String
    var action: () -> Void
    @ViewBuilder var art: () -> Art

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        Button(action: action) {
            VStack(spacing: 4) {
                art()
                    .saturation(locked ? 0 : 1).opacity(locked ? 0.5 : 1)
                    .overlay(alignment: .bottomTrailing) {
                        if locked { LedgerGlyph(glyph: Glyph.lock, size: 11, tint: Theme.ink).padding(3).background(Circle().fill(Theme.surfaceRaised)) }
                    }
                Text(title).textStyle(.caption, tint: locked ? Theme.inkFaint : Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.8)
                if !note.isEmpty { Text(note).textStyle(.caption, tint: Theme.inkFaint).lineLimit(2).minimumScaleFactor(0.7) }
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .top).padding(.vertical, Theme.Space.xs)
            .background(shape.fill(selected ? Theme.accentWash : Color.clear))
            .overlay(shape.strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title + (locked ? ", locked. " + note : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

private let avatarColumns: [GridItem] = [GridItem(.adaptive(minimum: 76), spacing: Theme.Space.s)]

/// One tap in a picker: what was picked, whether the player has it, and how to apply it to a look. A pick the player does not own can
/// still be tried on; the screen decides what to do with it.
struct AvatarPick {
    var title: String
    var owned: Bool
    /// Where the item comes from, for items the player does not have.
    var how: String
    var apply: (inout AvatarLook) -> Void
}

/// An item in a picker and whether the player has it.
struct PickRow<T: Identifiable>: Identifiable {
    var item: T
    var owned: Bool
    var id: T.ID { item.id }
}

/// The items of a part, the ones the player has first, then the others; each group keeps its catalogue order.
@MainActor
private func ownedFirst<T: Identifiable>(_ items: [T], itemID: (T) -> String, own: AvatarOwnership, shown: Set<String>) -> [PickRow<T>] {
    let visible: [T] = items.filter { (x: T) -> Bool in shown.contains(itemID(x)) }
    let mine: [PickRow<T>] = visible.filter { (x: T) -> Bool in own.owns(itemID(x)) }.map { (x: T) -> PickRow<T> in PickRow(item: x, owned: true) }
    let other: [PickRow<T>] = visible.filter { (x: T) -> Bool in !own.owns(itemID(x)) }.map { (x: T) -> PickRow<T> in PickRow(item: x, owned: false) }
    return mine + other
}

@MainActor
private func pick(_ title: String, _ itemID: String, _ owned: Bool, _ apply: @escaping (inout AvatarLook) -> Void) -> AvatarPick {
    AvatarPick(title: title, owned: owned, how: owned ? "" : AvatarOwnership.how(itemID), apply: apply)
}

struct AvatarFacePicker: View {
    var look: AvatarLook
    var onPick: (AvatarPick) -> Void
    @ObservedObject private var avatars = AvatarModel.shared
    @ObservedObject private var season = SeasonModel.shared

    var body: some View {
        let rows = ownedFirst(AvatarParts.faces, itemID: { (f: FaceDef) -> String in f.itemID }, own: AvatarOwnership(), shown: AvatarParts.shown())
        LazyVGrid(columns: avatarColumns, spacing: Theme.Space.s) {
            ForEach(rows) { (row: PickRow<FaceDef>) in
                let f: FaceDef = row.item
                AvatarPickTile(title: f.title, selected: look.face == f.id, locked: !row.owned, note: row.owned ? "" : AvatarOwnership.how(f.itemID), identifier: "avatar-face-\(f.id)", action: {
                    Haptics.choose()
                    onPick(pick(f.title, f.itemID, row.owned) { (l: inout AvatarLook) in l.face = f.id })
                }) { AvatarHead(look: AvatarLook(face: f.id, hair: look.hair, hairColour: look.hairColour, outfit: look.outfit, skin: look.skin), size: 56) }
            }
        }
    }
}

/// Skin tones. A picked tone tints the face and body layers.
struct AvatarSkinPicker: View {
    var look: AvatarLook
    var onPick: (AvatarPick) -> Void
    @ObservedObject private var avatars = AvatarModel.shared
    @ObservedObject private var season = SeasonModel.shared

    var body: some View {
        let rows = ownedFirst(AvatarParts.skins, itemID: { (s: SkinDef) -> String in s.itemID }, own: AvatarOwnership(), shown: AvatarParts.shown())
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
            ForEach(rows) { (row: PickRow<SkinDef>) in
                let t: SkinDef = row.item
                let on: Bool = look.skin == t.id
                Button {
                    Haptics.choose()
                    onPick(pick(t.title, t.itemID, row.owned) { (l: inout AvatarLook) in l.skin = t.id })
                } label: {
                    VStack(spacing: 2) {
                        Circle().fill(Color(hex: t.colour)).frame(width: 40, height: 40)
                            .padding(4)
                            .overlay(Circle().strokeBorder(on ? Theme.ink : Color.clear, lineWidth: 2))
                            .opacity(row.owned ? 1 : 0.5)
                        Text(t.title).textStyle(.caption, tint: row.owned ? Theme.inkSoft : Theme.inkFaint).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(minWidth: 48, minHeight: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Skin colour " + t.title + (row.owned ? "" : ", locked"))
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("avatar-skin-" + t.id)
            }
        }
    }
}

struct AvatarHairPicker: View {
    var look: AvatarLook
    var onPick: (AvatarPick) -> Void
    @ObservedObject private var avatars = AvatarModel.shared
    @ObservedObject private var season = SeasonModel.shared

    var body: some View {
        let rows = ownedFirst(AvatarParts.hairStyles, itemID: { (h: HairStyleDef) -> String in h.itemID }, own: AvatarOwnership(), shown: AvatarParts.shown())
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Style").textStyle(.label, tint: Theme.inkFaint)
                LazyVGrid(columns: avatarColumns, spacing: Theme.Space.s) {
                    ForEach(rows) { (row: PickRow<HairStyleDef>) in
                        let h: HairStyleDef = row.item
                        AvatarPickTile(title: h.title, selected: look.hair == h.id, locked: !row.owned, note: row.owned ? "" : AvatarOwnership.how(h.itemID), identifier: "avatar-hair-" + h.id, action: {
                            Haptics.choose()
                            onPick(pick(h.title, h.itemID, row.owned) { (l: inout AvatarLook) in l.hair = h.id })
                        }) { AvatarHead(look: AvatarLook(face: look.face, hair: h.id, hairColour: look.hairColour, outfit: look.outfit, skin: look.skin), size: 56) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Colour").textStyle(.label, tint: Theme.inkFaint)
                HStack(spacing: Theme.Space.s) {
                    ForEach(0..<AvatarParts.hairColours.count, id: \.self) { (i: Int) in
                        Button {
                            Haptics.choose()
                            onPick(AvatarPick(title: "Hair colour", owned: true, how: "", apply: { (l: inout AvatarLook) in l.hairColour = i }))
                        } label: {
                            Circle().fill(AvatarParts.hairColour(i)).frame(width: 28, height: 28)
                                .padding(4)
                                .overlay(Circle().strokeBorder(look.hairColour == i ? Theme.ink : Color.clear, lineWidth: 2))
                                .frame(minWidth: 36, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("Hair colour \(i + 1)")
                        .accessibilityAddTraits(look.hairColour == i ? .isSelected : [])
                        .accessibilityIdentifier("avatar-colour-\(i)")
                    }
                }
            }
        }
    }
}

struct AvatarOutfitPicker: View {
    var look: AvatarLook
    var onPick: (AvatarPick) -> Void
    @ObservedObject private var avatars = AvatarModel.shared
    @ObservedObject private var season = SeasonModel.shared

    var body: some View {
        let rows = ownedFirst(AvatarParts.outfits, itemID: { (o: OutfitDef) -> String in o.itemID }, own: AvatarOwnership(), shown: AvatarParts.shown())
        LazyVGrid(columns: avatarColumns, spacing: Theme.Space.s) {
            ForEach(rows) { (row: PickRow<OutfitDef>) in
                let o: OutfitDef = row.item
                AvatarPickTile(title: o.title, selected: look.outfit == o.id, locked: !row.owned, note: row.owned ? "" : AvatarOwnership.how(o.itemID), identifier: "avatar-outfit-" + o.id, action: {
                    Haptics.choose()
                    onPick(pick(o.title, o.itemID, row.owned) { (l: inout AvatarLook) in l.outfit = o.id })
                }) {
                    HalfBodyAvatar(look: AvatarLook(face: look.face, hair: look.hair, hairColour: look.hairColour, outfit: o.id, skin: look.skin), width: 66)
                        .frame(width: 66, height: 66, alignment: .top).clipped()
                }
            }
        }
    }
}
