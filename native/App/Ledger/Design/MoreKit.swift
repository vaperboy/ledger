import SwiftUI

// Shared pieces for the pages inside one company's More menu (Customers, Market, Chain, Franchise, Club, Holding, Plant, Projects ...).
// Built on the new-look pieces in NewLook.swift: a header strip per page, labelled blocks in bordered cards, entity cards, stat strips,
// tiny outlined buttons and a chevron on every row that opens something.

/// The header strip of a More page: icon circle, title and one line saying what the page is.
struct MoreHeader: View {
    var glyph: String
    var title: String
    var blurb: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        HStack(spacing: 12) {
            IconCircle(glyph: glyph, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.serifTitle(18)).foregroundStyle(Theme.ivory).lineLimit(1).minimumScaleFactor(0.8)
                Text(blurb.tidyText).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Theme.surfaceTable))
        .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A labelled block: small-caps label (and a note or control at the right), then the content in a bordered card.
/// Pass `card: false` when the content is made of its own `EntityCard`s.
struct MoreBlock<Content: View, Trailing: View>: View {
    var title: String
    var card = true
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).capsLabel()
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, 2)
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

/// A bordered card for one independent entity (a chain store, a rival, a key account, a stadium, a field).
struct EntityCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Card(padding: 12, radius: Theme.Radius.row, content: content)
    }
}

/// The cue at the right of a row that opens something.
struct MoreChevron: View {
    var body: some View { GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim) }
}

/// Figures in a strip separated by hairlines, up to `columns` to a line (the shape of `KeyFigures`, in the new look).
struct FigureStrip: View {
    var items: [KeyFigures.Item]
    var columns = 3

    var body: some View {
        let count: Int = max(1, columns)
        let starts: [Int] = Array(stride(from: 0, to: items.count, by: count))
        VStack(spacing: 8) {
            ForEach(starts, id: \.self) { (start: Int) in
                let row: [KeyFigures.Item] = Array(items[start..<min(start + count, items.count)])
                if start > 0 { Rectangle().fill(Theme.divider).frame(height: 1) }
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { (i: Int, it: KeyFigures.Item) in
                        if i > 0 { Rectangle().fill(Theme.divider).frame(width: 1) }
                        cell(it)
                    }
                    ForEach(0..<(count - row.count), id: \.self) { (_: Int) in Color.clear.frame(maxWidth: .infinity) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func cell(_ it: KeyFigures.Item) -> some View {
        VStack(spacing: 2) {
            Text(it.label).font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
            Text(it.value.tidyText).font(.system(size: 14, weight: .medium).monospacedDigit()).foregroundStyle(it.tint)
                .lineLimit(1).minimumScaleFactor(0.7)
            if !it.sub.isEmpty { Text(it.sub.tidyText).font(.system(size: 10)).foregroundStyle(Theme.ivoryFaint).lineLimit(1).minimumScaleFactor(0.8) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The tiny outlined button: 12 pt text in `tint`, a grey outline, 12 pt corners. Never filled (only Next Day is).
struct TinyButtonStyle: ButtonStyle {
    var tint: Color = Theme.gold

    func makeBody(configuration: Configuration) -> some View {
        TinyButtonBody(configuration: configuration, tint: tint)
    }

    private struct TinyButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
            let edge: Color = tint == Theme.loss ? Theme.loss.opacity(0.6) : Theme.borderStrong
            let fade: Double = enabled ? (configuration.isPressed ? 0.6 : 1) : 0.4
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .frame(minHeight: 28)
                .overlay(shape.strokeBorder(edge, lineWidth: 1))
                .contentShape(Rectangle())
                .opacity(fade)
        }
    }
}
