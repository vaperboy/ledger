import SwiftUI

/// One person (or an open post) of the Team list as a thin bordered row: a small portrait, the name, one short line, the pay and a chevron.
/// An open post shows its title and a gold word ("Appoint") instead of a name. The row has no button of its own: the caller wraps it.
struct ThinPersonRow: View {
    var name: String?
    /// The post or role: the title of an open post, the line under a name.
    var title: String
    var note: String = ""
    var noteTint: Color = Theme.ivoryFaint
    var wage: String? = nil
    /// A gold word at the right of an open post ("Appoint").
    var cue: String? = nil
    var chevron = true
    var roleKey: String? = nil
    var face: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            if name == nil {
                TeamInitials(name: nil, size: 30)
            } else {
                ThumbnailView(kind: .person, key: roleKey ?? title, size: 30, initials: name, face: face)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(name ?? title).font(.system(size: 14, weight: .medium)).foregroundStyle(name == nil ? Theme.ivoryMuted : Theme.ivory).lineLimit(1)
                if name != nil || !note.isEmpty {
                    Text(line).font(.system(size: 11.5)).foregroundStyle(noteTint).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if let wage { Text(wage).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivory) }
            if let cue { Text(cue).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold) }
            if chevron { GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var line: String {
        if name == nil { return note }
        return note.isEmpty ? title : title + " \u{00B7} " + note
    }
}
