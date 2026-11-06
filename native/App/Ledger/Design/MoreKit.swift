import SwiftUI

// Shared pieces for the pages inside one company's More menu (Customers, Market, Chain, Franchise, Club, Holding, Plant, Projects ...).
// Built on the new-look pieces in NewLook.swift: a header strip per page, labelled blocks in bordered cards, entity cards, stat strips,
// tiny outlined buttons and a chevron on every row that opens something.

/// The intro of a More page: an unoutlined icon (or a picture), the title and one line saying what the page is. No box.
struct MoreHeader: View {
    var glyph: String
    var title: String
    /// A picture in place of the icon (a rival's logo); same 38 pt.
    var thumb: ThumbSpec? = nil
    var blurb: String

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            if let thumb { ThumbnailView(thumb, size: 38) } else { IconCircle(glyph: glyph, size: 38) }
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title).textStyle(.figure).lineLimit(1).minimumScaleFactor(0.8)
                Text(blurb.tidyText).textStyle(.caption).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A labelled block: caps label (and a note or control at the right), then the content on one surface group (cards inside draw flat).
/// Pass `card: false` when the content is made of its own `EntityCard`s.
struct MoreBlock<Content: View, Trailing: View>: View {
    var title: String
    var card = true
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).capsLabel()
                Spacer(minLength: Theme.Space.s)
                trailing()
            }
            .padding(.horizontal, Theme.Space.xxs)
            if card {
                Card(padding: 14, radius: Theme.Radius.card, content: content)
            } else {
                VStack(alignment: .leading, spacing: 10, content: content)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension MoreBlock where Trailing == EmptyView {
    init(_ title: String, card: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, card: card, trailing: { EmptyView() }, content: content)
    }
}

/// A surface tile for one independent entity (flat inside a group) (a chain store, a rival, a key account, a stadium, a field).
struct EntityCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Card(padding: 12, radius: Theme.Radius.row, content: content)
    }
}

/// The cue at the right of a row that opens something.
struct MoreChevron: View {
    var body: some View { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint) }
}

/// Figures in a strip separated by hairlines, up to `columns` to a line, centred: `FigureRow`.
struct FigureStrip: View {
    var items: [KeyFigures.Item]
    var columns = 3

    var body: some View {
        FigureRow(items: items, columns: columns, alignment: .center, combineCells: true)
    }
}

/// The compact secondary button: text in `tint` (accent by default), 32 pt drawn, 44 pt hit area.
struct TinyButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonStyle(size: .compact, tint: tint).makeBody(configuration: configuration)
    }
}
