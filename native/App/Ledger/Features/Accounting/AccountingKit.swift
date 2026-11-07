import SwiftUI

// The flat pieces the Accounting pages are drawn with: rows and groups sit on the ivory page itself, aligned to the page margin, with
// hairlines between rows and faint caps labels over groups (no panels around ordinary content).

/// One row of an Accounting list: `LedgerRow` aligned to the page margin. With an `action` the whole row is the button and shows a
/// chevron; without one it is plain information. The identifier is the title unless one is given.
struct AcctLine: View {
    @Environment(\.outsidePalette) private var P
    var glyph: String? = nil
    var initials: String? = nil
    var title: String
    var subtitle: String = ""
    var value: String = ""
    var valueTint: Color? = nil
    var valueNote: String = ""
    var valueNoteTint: Color? = nil
    var pill: String? = nil
    var pillTone: AcctPill.Tone = .neutral
    var identifier: String = ""
    var action: (() -> Void)? = nil

    var body: some View {
        LedgerRow(leading: leading, leadingTint: glyph != nil ? P.accent : nil, title: title, subtitle: subtitle, value: value,
                  valueTint: valueTint, valueNote: valueNote, valueNoteTint: valueNoteTint, pill: pill, pillTone: pillTone,
                  inset: 0, identifier: identifier.isEmpty ? title : identifier, action: action)
            .frame(minHeight: 52)
    }

    private var leading: LedgerRow.Leading {
        if let glyph { return .glyph(glyph) }
        if let initials { return .initials(initials) }
        return .empty
    }
}

/// A group of rows on the page: no surface, no padding at the sides. `padding` only spaces it from above and below.
struct AcctFlat<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(.vertical, padding > 0 ? Theme.Space.xs : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.insideCard, true)
    }
}

/// The label over a group: small caps in faint ink.
struct AcctCaps: View {
    @Environment(\.outsidePalette) private var P
    var text: String
    var body: some View {
        Text(text.tidyText).textStyle(.label, tint: P.inkFaint).textCase(.uppercase).lineLimit(1)
    }
}
