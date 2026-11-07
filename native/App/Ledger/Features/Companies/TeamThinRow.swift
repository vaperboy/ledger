import SwiftUI

/// One person (or an open post) of a Team list as a clean 60 pt row straight on the page: a portrait, the name over one subline (role,
/// mood, a note), the monthly pay right-aligned and a chevron. An open post shows its title and an accent word ("Appoint") instead.
/// No box: lists separate rows with `PersonRowRule`. The row has no button of its own: the caller wraps it.
struct ThinPersonRow: View {
    @Environment(\.outsidePalette) private var P
    var name: String?
    /// The post or role: the title of an open post, the line under a name.
    var title: String
    var note: String = ""
    var noteTint: Color = Theme.inkFaint
    var wage: String? = nil
    /// An accent word at the right of an open post ("Appoint").
    var cue: String? = nil
    var chevron = true
    var roleKey: String? = nil
    var face: String? = nil
    /// The engine's mood word ("Happy", "Mixed", "Unhappy", "Leaving", "Content"); shown in the subline, tinted when it needs a look.
    var mood: String? = nil

    static let portrait: CGFloat = 36

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            if name == nil {
                TeamInitials(name: nil, size: Self.portrait)
            } else {
                ThumbnailView(kind: .person, key: roleKey ?? title, size: Self.portrait, initials: name, face: face)
            }
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text((name ?? title).tidyText).textStyle(.headline, tint: name == nil ? P.inkSoft : P.ink).lineLimit(1)
                if name != nil || !note.isEmpty { subline.lineLimit(2) }
            }
            Spacer(minLength: Theme.Space.s)
            if let wage {
                Text(wage).textStyle(.headline, tint: P.ink, numeric: true).lineLimit(1).minimumScaleFactor(0.8)
            }
            if let cue { Text(cue).textStyle(.body, tint: P.accent, weight: .medium).lineLimit(1) }
            if chevron { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint) }
        }
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Role, then the mood word in its tone, then the note: one caption line.
    private var subline: Text {
        var parts: [Text] = []
        if name == nil {
            parts.append(Text(note.tidyText).foregroundColor(noteTint.inPalette(P)))
        } else {
            parts.append(Text(title.tidyText).foregroundColor(P.inkSoft))
            if let mood, !mood.isEmpty { parts.append(Text(mood).foregroundColor(Self.moodTint(mood, P))) }
            if !note.isEmpty { parts.append(Text(note.tidyText).foregroundColor(noteTint.inPalette(P))) }
        }
        var out: Text = parts.first ?? Text("")
        for p in parts.dropFirst() { out = out + Text(" \u{00B7} ").foregroundColor(P.inkFaint) + p }
        return out.font(Font.step(.caption))
    }

    /// Calm words stay soft; a mood that needs the owner takes the caution or loss tone.
    static func moodTint(_ word: String, _ P: OutsidePalette) -> Color {
        switch word {
        case "Leaving": return P.loss
        case "Unhappy": return P.caution
        case "Happy": return P.gain
        default: return P.inkSoft
        }
    }
}

/// The hairline between two person rows, inset to start under the name.
struct PersonRowRule: View {
    var body: some View { Hairline().padding(.leading, ThinPersonRow.portrait + Theme.Space.m) }
}

/// A group of a Team screen: a small-caps label in faint ink above its content, no box and no rule. Groups sit 24-32 pt apart.
struct TeamBlock<Content: View, Trailing: View>: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(title).textStyle(.label, tint: P.inkFaint)
                Spacer(minLength: Theme.Space.s)
                trailing()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension TeamBlock where Trailing == EmptyView {
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

/// The hero of a Team screen: an optional small-caps label, one big serif figure with its unit, and one context line under it.
struct TeamHero: View {
    @Environment(\.outsidePalette) private var P
    var label: String = ""
    var value: String
    var unit: String = ""
    var context: String = ""
    var contextTint: Color? = nil
    var valueTint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if !label.isEmpty { Text(label).textStyle(.label, tint: P.inkFaint) }
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(value.tidyText).textStyle(.display, tint: valueTint).lineLimit(1).minimumScaleFactor(0.6)
                if !unit.isEmpty { Text(unit.tidyText).textStyle(.body, tint: P.inkSoft).lineLimit(1) }
            }
            if !context.isEmpty {
                Text(context.tidyText).textStyle(.caption, tint: contextTint).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
