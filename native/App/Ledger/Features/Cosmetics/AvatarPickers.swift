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
                if !note.isEmpty { Text(note).textStyle(.caption, tint: Theme.inkFaint).lineLimit(1).minimumScaleFactor(0.7) }
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

struct AvatarFacePicker: View {
    var look: AvatarLook
    var onChange: (AvatarLook) -> Void

    var body: some View {
        LazyVGrid(columns: avatarColumns, spacing: Theme.Space.s) {
            ForEach(AvatarParts.faces) { (f: FaceDef) in
                AvatarPickTile(title: f.title, selected: look.face == f.id, identifier: "avatar-face-\(f.id)", action: {
                    Haptics.choose()
                    var next: AvatarLook = look
                    next.face = f.id
                    onChange(next)
                }) { AvatarHead(look: AvatarLook(face: f.id, hair: look.hair, hairColour: look.hairColour, outfit: look.outfit, skin: look.skin), size: 56) }
            }
        }
    }
}

struct AvatarHairPicker: View {
    var look: AvatarLook
    var onChange: (AvatarLook) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Style").textStyle(.label, tint: Theme.inkFaint)
                LazyVGrid(columns: avatarColumns, spacing: Theme.Space.s) {
                    ForEach(AvatarParts.hairStyles) { (h: HairStyleDef) in
                        AvatarPickTile(title: h.title, selected: look.hair == h.id, identifier: "avatar-hair-\(h.id)", action: {
                            Haptics.choose()
                            var next: AvatarLook = look
                            next.hair = h.id
                            onChange(next)
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
                            var next: AvatarLook = look
                            next.hairColour = i
                            onChange(next)
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
    /// Called with the outfit and whether the player owns it. Locked outfits can still be tried on.
    var onPick: (OutfitDef, Bool) -> Void
    @ObservedObject private var avatars = AvatarModel.shared

    var body: some View {
        LazyVGrid(columns: avatarColumns, spacing: Theme.Space.s) {
            ForEach(AvatarParts.outfits) { (o: OutfitDef) in
                let open: Bool = avatars.bestLevel >= o.level
                AvatarPickTile(title: o.title, selected: look.outfit == o.id, locked: !open, note: open ? "" : "Level \(o.level)", identifier: "avatar-outfit-" + o.id, action: {
                    Haptics.choose()
                    onPick(o, open)
                }) {
                    HalfBodyAvatar(look: AvatarLook(face: look.face, hair: look.hair, hairColour: look.hairColour, outfit: o.id, skin: look.skin), width: 66)
                        .frame(width: 66, height: 66, alignment: .top).clipped()
                }
            }
        }
    }
}

/// A row of skin tones. The picked tone tints the face and body layers.
struct AvatarSkinPicker: View {
    var look: AvatarLook
    var onChange: (AvatarLook) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
            ForEach(0..<AvatarParts.skinTones.count, id: \.self) { (i: Int) in
                let on: Bool = look.skin == i
                Button {
                    Haptics.choose()
                    var next: AvatarLook = look
                    next.skin = i
                    onChange(next)
                } label: {
                    Circle().fill(AvatarParts.skinTone(i)).frame(width: 40, height: 40)
                        .padding(4)
                        .overlay(Circle().strokeBorder(on ? Theme.ink : Color.clear, lineWidth: 2))
                        .frame(minWidth: 48, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Skin colour \(i + 1)")
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("avatar-skin-\(i)")
            }
        }
    }
}
