import SwiftUI
import Countries

/// A row of the Group tab that leads somewhere: a title, one line of detail, a figure or chevron on the right.
struct GroupLinkRow: View {
    var title: String
    var sub: String
    var trailing: String = ""
    var tint: Color = Theme.ivory
    var subTint: Color = Theme.ivoryFaint

    /// The `LedgerRow` look (its texts stay separate accessibility elements, as before).
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title).textStyle(.headline).lineLimit(1).minimumScaleFactor(0.8)
                if !sub.isEmpty { Text(sub).textStyle(.caption, tint: subTint).lineLimit(2) }
            }
            Spacer(minLength: Theme.Space.s)
            if !trailing.isEmpty { Text(trailing).textStyle(.headline, tint: tint, numeric: true).lineLimit(1).minimumScaleFactor(0.8) }
            LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
        }
        .padding(.vertical, Theme.Space.s).contentShape(Rectangle())
    }
}
