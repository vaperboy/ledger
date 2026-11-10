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
    /// A money movement shown as an arrow and amount in place of `value` (see `ArrowAmount`): positive green up, negative red down.
    var gain: Double? = nil
    var gainFormat: ((Double) -> String)? = nil
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

    private var hasTrailing: Bool { !value.isEmpty || gain != nil || !valueNote.isEmpty || pill != nil }

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
                    if let gain, let gainFormat {
                        ArrowAmount(gain: gain, format: gainFormat, step: .headline).lineLimit(1).minimumScaleFactor(0.7)
                    } else if !value.isEmpty {
                        Text(value.tidyText).textStyle(.headline, tint: valueTint, numeric: true).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    if let pill { AcctPill(text: pill, tone: pillTone) }
                    if !valueNote.isEmpty {
                        Text(valueNote.tidyText).textStyle(.caption, tint: valueNoteTint ?? P.inkFaint, numeric: true).lineLimit(1).minimumScaleFactor(0.8)
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
                .font(.system(size: Theme.Icon.small, weight: .regular))
                .foregroundStyle((leadingTint ?? P.accent).inPalette(P))
                .frame(width: Theme.Icon.medium, height: Theme.Icon.medium)
                .accessibilityHidden(true)
        case .initials(let letters):
            Text(letters)
                .textStyle(.caption, weight: .semibold)
                .containerInk(P.accentInk)
                .frame(width: 36, height: 36)
                .background(Circle().fill(leadingTint ?? P.accent))
        case .thumb(let spec):
            ThumbnailView(spec, size: 40)
        }
    }
}

/// Combines a view's children into one accessibility element when `on`.
struct CombinedElement: ViewModifier {
    var on: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if on { content.accessibilityElement(children: .combine) } else { content }
    }
}

/// Sets an accessibility identifier only when there is one, so rows that never had an id do not gain one.
struct OptionalIdentifier: ViewModifier {
    var identifier: String
    @ViewBuilder func body(content: Content) -> some View {
        if identifier.isEmpty { content } else { content.accessibilityIdentifier(identifier) }
    }
}

// MARK: Figures

/// One key number: a label, the value and an optional note. `.display` is the one big number of a screen (serif 34), `.figure` a key
/// amount (serif 20), `.inline` a cell of a strip (sans 15). `live` rolls and flashes the value when the number behind it changes.
struct Figure: View {
    enum Size { case display, figure, inline }
    var label: String
    var value: String
    var note: String = ""
    var tint: Color? = nil
    var size: Size = .figure
    var live: Double? = nil
    var alignment: HorizontalAlignment = .leading
    @Environment(\.outsidePalette) private var P

    var body: some View {
        let textAlign: TextAlignment = alignment == .center ? .center : (alignment == .trailing ? .trailing : .leading)
        VStack(alignment: alignment, spacing: Theme.Space.xxs) {
            if !label.isEmpty { labelText.lineLimit(1).minimumScaleFactor(0.8) }
            if let live { valueText.moneyFlash(live) } else { valueText }
            if !note.isEmpty {
                Text(note.tidyText).textStyle(.caption, tint: P.inkFaint).lineLimit(2).multilineTextAlignment(textAlign)
            }
        }
    }

    @ViewBuilder private var labelText: some View {
        if size == .inline {
            Text(label.tidyText).textStyle(.caption, tint: P.inkFaint)
        } else {
            Text(label.tidyText).textStyle(.label)
        }
    }

    @ViewBuilder private var valueText: some View {
        switch size {
        case .display:
            Text(value.tidyText).textStyle(.display, tint: tint).lineLimit(2).minimumScaleFactor(0.8)
        case .figure:
            Text(value.tidyText).textStyle(.figure, tint: tint).lineLimit(2).minimumScaleFactor(0.8)
        case .inline:
            Text(value.tidyText).textStyle(.headline, tint: tint, numeric: true).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

/// Key figures side by side, `columns` to a line, separated by vertical hairlines; a further line follows under a hairline. No box.
struct FigureRow: View {
    var items: [KeyFigures.Item]
    var columns = 3
    var alignment: HorizontalAlignment = .leading
    var size: Figure.Size = .inline
    /// Reads each cell as one accessibility element (label and value together).
    var combineCells = false
    @Environment(\.outsidePalette) private var P

    var body: some View {
        let count: Int = max(1, columns)
        let starts: [Int] = Array(stride(from: 0, to: items.count, by: count))
        let frameAlign: Alignment = alignment == .center ? .center : (alignment == .trailing ? .trailing : .leading)
        VStack(spacing: Theme.Space.m) {
            ForEach(starts, id: \.self) { (start: Int) in
                let row: [KeyFigures.Item] = Array(items[start..<min(start + count, items.count)])
                if start > 0 { Hairline() }
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { (i: Int, it: KeyFigures.Item) in
                        Figure(label: it.label, value: it.value, note: it.sub, tint: it.tint, size: size, live: it.live, alignment: alignment)
                            .modifier(CombinedElement(on: combineCells))
                            .frame(maxWidth: .infinity, alignment: frameAlign)
                            .padding(.leading, i > 0 && alignment == .leading ? Theme.Space.m : 0)
                            .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(P.hairline).frame(width: 0.5) } }
                    }
                    ForEach(0..<(count - row.count), id: \.self) { (_: Int) in Color.clear.frame(maxWidth: .infinity) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: Progress

/// The one progress bar: a 4 pt line on a hairline track, with an optional label and value above it. Animates to a new value.
struct ProgressLine: View {
    var fraction: Double
    var tint: Color? = nil
    var label: String = ""
    var value: String = ""
    var height: CGFloat = 4
    @Environment(\.outsidePalette) private var P
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if !label.isEmpty || !value.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(label.tidyText).textStyle(.caption).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: Theme.Space.s)
                    Text(value.tidyText).textStyle(.caption, tint: P.ink, numeric: true).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            bar
        }
        .accessibilityElement(children: .combine)
    }

    private var bar: some View {
        let f: Double = min(1, max(0, fraction))
        return GeometryReader { (g: GeometryProxy) in
            ZStack(alignment: .leading) {
                Capsule().fill(P.line)
                Capsule().fill((tint ?? P.accent).inPalette(P)).frame(width: f <= 0 ? 0 : max(height, g.size.width * CGFloat(f)))
            }
        }
        .frame(height: height)
        .animation(Motion.fill(reduceMotion), value: fraction)
    }
}

// MARK: States

/// A flat empty or explanatory state: a faint icon, a title and the reason or what to do, an optional action. It sits inside a
/// section's group and never draws its own card. `centered: false` is the compact inline form (icon left).
struct EmptyState: View {
    var glyph: String = Glyph.info
    var title: String
    var message: String = ""
    var tint: Color? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var centered: Bool = true
    @Environment(\.outsidePalette) private var P

    var body: some View {
        if centered {
            VStack(spacing: Theme.Space.s) {
                LedgerGlyph(glyph: glyph, size: Theme.Icon.large, tint: tint ?? P.inkFaint)
                words(.center)
                actionButton
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Space.xl)
        } else {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                LedgerGlyph(glyph: glyph, size: Theme.Icon.medium, tint: tint ?? P.inkFaint)
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    words(.leading)
                    actionButton
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func words(_ align: TextAlignment) -> some View {
        VStack(alignment: align == .center ? .center : .leading, spacing: Theme.Space.xxs) {
            Text(title.tidyText).textStyle(.headline).multilineTextAlignment(align).fixedSize(horizontal: false, vertical: true)
            if !message.isEmpty {
                Text(message.tidyText).textStyle(.caption).multilineTextAlignment(align).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var actionButton: some View {
        if let actionTitle, let action {
            Button(actionTitle) {
                Haptics.tap()
                action()
            }
            .buttonStyle(SecondaryButtonStyle(size: .compact, tint: P.accent))
        }
    }
}

/// Something is on its way: an accent spinner with a caption, and optional placeholder rows in the shape of the content.
struct LoadingState: View {
    var text: String = "Loading"
    var rows: Int = 0
    @Environment(\.outsidePalette) private var P

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.s) {
                ProgressView().tint(P.accent)
                Text(text.tidyText).textStyle(.caption)
            }
            ForEach(0..<max(0, rows), id: \.self) { (_: Int) in
                LedgerRow(title: "Placeholder title", subtitle: "Placeholder line", value: "0,000")
                    .redacted(reason: .placeholder)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.l)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Charts

/// The one chart palette: series hues in order, grid, axis text and the zero rule. Defined once; read colours through `color(_:in:)`
/// so an outside app's palette applies.
enum ChartPalette {
    static let series: [Color] = [Theme.accent, Theme.slateBlue, Theme.gain, Theme.roseGold, Theme.warn]
    static let grid: Color = Theme.line
    static let axis: Color = Theme.inkFaint
    static let zero: Color = Theme.inkFaint.opacity(0.5)
    /// Flat fill under a line (no gradient).
    static let areaOpacity: Double = 0.10
    static let lineWidth: CGFloat = 1.5
    static let axisFont: Font = Font.system(size: 11).monospacedDigit()

    static func color(_ index: Int) -> Color {
        let n: Int = series.count
        return series[((index % n) + n) % n]
    }
    static func color(_ index: Int, in palette: OutsidePalette) -> Color { color(index).inPalette(palette) }
}

/// The frame around every chart: a caps title and period, the plot at a fixed height, the key under it, and a quiet line when
/// there is not enough data. Put a Swift Charts `Chart` (or a `Sparkline`) inside, coloured from `ChartPalette`.
struct ChartFrame<Plot: View>: View {
    var title: String = ""
    var period: String = ""
    var key: [(String, Color)] = []
    var height: CGFloat = 120
    var isEmpty: Bool = false
    var emptyText: String = "The chart fills in as days pass."
    @ViewBuilder var plot: () -> Plot
    @Environment(\.outsidePalette) private var P

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if !title.isEmpty || !period.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    if !title.isEmpty { Text(title.tidyText).capsLabel() }
                    Spacer(minLength: Theme.Space.s)
                    if !period.isEmpty { Text(period.tidyText).textStyle(.caption, tint: P.inkFaint) }
                }
            }
            if isEmpty {
                Text(emptyText.tidyText).textStyle(.caption, tint: P.inkFaint)
                    .frame(maxWidth: .infinity, minHeight: height, alignment: .center)
            } else {
                plot().frame(height: height)
            }
            if !key.isEmpty && !isEmpty { ChartKey(items: key) }
        }
    }
}

// MARK: Segments

/// The one segmented control look: an inset track, the chosen option on a lighter fill, no borders. `SegmentedPill` and
/// `SegmentedChoice` draw through it.
struct SegmentTrack<T: Hashable>: View {
    var items: [T]
    var title: (T) -> String
    @Binding var selection: T
    var identifier: (T) -> String
    var badges: ((T) -> Bool)? = nil
    @Environment(\.outsidePalette) private var P

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        let inner = RoundedRectangle(cornerRadius: Theme.Radius.small - 2, style: .continuous)
        let chosen: Color = P.isLight ? P.card : P.ink.opacity(0.12)
        HStack(spacing: Theme.Space.xxs) {
            ForEach(items, id: \.self) { (item: T) in
                let on: Bool = selection == item
                Button {
                    selection = item
                    Haptics.choose()
                } label: {
                    Text(title(item))
                        .textStyle(.body, tint: on ? P.ink : P.inkSoft, weight: on ? .medium : .regular)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, Theme.Space.xs)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(inner.fill(on ? chosen : Color.clear))
                        .contentShape(Rectangle())
                        .flagMarker(!on && (badges?(item) ?? false), alignment: .topTrailing)
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
                .modifier(OptionalIdentifier(identifier: identifier(item)))
                .id(item)
            }
        }
        .padding(Theme.Space.xxs)
        .background(shape.fill(P.inset))
    }
}
