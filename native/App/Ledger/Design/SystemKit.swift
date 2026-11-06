import SwiftUI

// The core pieces of the design system (tokens in Theme.swift). Older components are thin wrappers over these.

// MARK: Icon

/// A house icon at one of the three icon sizes (`Theme.Icon`), always drawn with the same stroke width. No circle, no outline.
struct LedgerGlyph: View {
    var glyph: String
    var size: CGFloat = Theme.Icon.medium
    var tint: Color? = nil

    var body: some View {
        GlyphView(glyph: glyph, size: size, weight: Theme.Icon.stroke * 24 / max(size, 1), tint: tint)
    }
}

// MARK: Row

/// The one list row. Leading mark (none, house glyph, SF symbol, initials, picture), title over a caption, a value with an optional
/// pill and note on the right, an optional red count, and a chevron when the row opens something. With `action` the whole row is the
/// button. `inset` is the horizontal padding (0 inside a padded group, 14 in a group with no padding of its own).
struct LedgerRow: View {
    enum Leading { case empty, glyph(String), symbol(String), initials(String), thumb(ThumbSpec) }
    enum Density { case regular, compact }

    @Environment(\.outsidePalette) private var P
    var leading: Leading = .empty
    var leadingTint: Color? = nil
    var title: String
    var subtitle: String = ""
    var value: String = ""
    var valueTint: Color? = nil
    var valueNote: String = ""
    var valueNoteTint: Color? = nil
    var pill: String? = nil
    var pillTone: AcctPill.Tone = .neutral
    var badge: Int = 0
    /// nil: a chevron when the row has an action.
    var chevron: Bool? = nil
    var inset: CGFloat = 0
    var density: Density = .regular
    var lineLimit: Int = 2
    /// Accessibility identifier of the row (none when empty).
    var identifier: String = ""
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button {
                Haptics.tap()
                action()
            } label: { row(chevron: chevron ?? true) }
                .buttonStyle(AcctPressStyle())
                .modifier(OptionalIdentifier(identifier: identifier))
        } else {
            row(chevron: chevron ?? false)
                .modifier(OptionalIdentifier(identifier: identifier))
        }
    }

    private var hasTrailing: Bool { !value.isEmpty || !valueNote.isEmpty || pill != nil }

    private func row(chevron: Bool) -> some View {
        HStack(spacing: Theme.Space.m) {
            leadingView
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title.tidyText).textStyle(.headline).lineLimit(lineLimit).multilineTextAlignment(.leading)
                if !subtitle.isEmpty {
                    Text(subtitle.tidyText).textStyle(.caption).lineLimit(lineLimit).multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: Theme.Space.s)
            RedBubble(count: badge)
            if hasTrailing {
                VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                    if !value.isEmpty {
                        Text(value.tidyText).textStyle(.headline, tint: valueTint, numeric: true).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    if let pill { AcctPill(text: pill, tone: pillTone) }
                    if !valueNote.isEmpty {
                        Text(valueNote.tidyText).textStyle(.caption, tint: valueNoteTint ?? P.inkFaint, numeric: true).lineLimit(1)
                    }
                }
            }
            if chevron { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint) }
        }
        .padding(.horizontal, inset)
        .padding(.vertical, density == .regular ? Theme.Space.m : Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var leadingView: some View {
        switch leading {
        case .empty:
            EmptyView()
        case .glyph(let g):
            LedgerGlyph(glyph: g, size: Theme.Icon.medium, tint: (leadingTint ?? P.accent).inPalette(P))
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle((leadingTint ?? P.accent).inPalette(P))
                .frame(width: Theme.Icon.medium, height: Theme.Icon.medium)
                .accessibilityHidden(true)
        case .initials(let letters):
            Text(letters)
                .textStyle(.caption, tint: P.accentInk, weight: .semibold)
                .frame(width: 36, height: 36)
                .background(Circle().fill(leadingTint ?? P.accent))
        case .thumb(let spec):
            ThumbnailView(spec, size: 40)
        }
    }
}

/// Sets an accessibility identifier only when there is one, so rows that never had an id do not gain one.
struct OptionalIdentifier: ViewModifier {
    var identifier: String
    @ViewBuilder func body(content: Content) -> some View {
        if identifier.isEmpty { content } else { content.accessibilityIdentifier(identifier) }
    }
}
