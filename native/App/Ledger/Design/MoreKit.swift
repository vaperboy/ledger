import SwiftUI

struct MoreHeader: View {
    var glyph: String
    var title: String
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

struct EntityCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Card(padding: 12, radius: Theme.Radius.row, content: content)
    }
}

struct MoreChevron: View {
    var body: some View { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint) }
}

struct FigureStrip: View {
    var items: [KeyFigures.Item]
    var columns = 3

    var body: some View {
        FigureRow(items: items, columns: columns, alignment: .center, combineCells: true)
    }
}

struct TinyButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonStyle(size: .compact, tint: tint).makeBody(configuration: configuration)
    }
}
