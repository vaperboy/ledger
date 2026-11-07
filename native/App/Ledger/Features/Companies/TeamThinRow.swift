import SwiftUI

/// One person (or an open post) of a Team list as a thin row on the surface tone: a small portrait, the name, one short line, the pay and a
/// chevron. An open post shows its title and an accent word ("Appoint") instead of a name. The row has no button of its own: the caller wraps it.
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

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            if name == nil {
                TeamInitials(name: nil, size: 30)
            } else {
                ThumbnailView(kind: .person, key: roleKey ?? title, size: 30, initials: name, face: face)
            }
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text((name ?? title).tidyText).textStyle(.headline, tint: name == nil ? P.inkSoft : P.ink).lineLimit(1)
                if name != nil || !note.isEmpty {
                    Text(line.tidyText).textStyle(.caption, tint: noteTint).lineLimit(2)
                }
            }
            Spacer(minLength: Theme.Space.s)
            if let wage { Text(wage).textStyle(.body, tint: P.ink, numeric: true).lineLimit(1) }
            if let cue { Text(cue).textStyle(.body, tint: P.accent, weight: .medium).lineLimit(1) }
            if chevron { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint) }
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(P.surface))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var line: String {
        if name == nil { return note }
        return note.isEmpty ? title : title + " \u{00B7} " + note
    }
}
