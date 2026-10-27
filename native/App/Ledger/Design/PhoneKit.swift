import SwiftUI

// Shared pieces for the pages of the Phone apps (Inbox, News, Stats, Goals, World, Luxury, Ventures, Rich list, Settings), built on
// NewLook.swift: a titled card section, a figure card, an icon row, and a few extra house icons in the same 24 x 24 style.

extension Glyph {
    static let arrowIn = "M17 7 L7 17 M7 9 V17 H15"
    static let arrowOut = "M7 17 L17 7 M9 7 H17 V15"
    static let check = "M5 12 L10 17 L19 7"
    static let ring = "M12 4 A8 8 0 1 0 12 20 A8 8 0 1 0 12 4"
    static let clock = "M12 4 A8 8 0 1 0 12 20 A8 8 0 1 0 12 4 M12 8 V12 L15 14"
    static let search = "M11 4 A7 7 0 1 0 11 18 A7 7 0 1 0 11 4 M16 16 L20 20"
    static let close = "M6 6 L18 18 M18 6 L6 18"
    static let minus = "M5 12 H19"
    static let sun = "M12 8 A4 4 0 1 0 12 16 A4 4 0 1 0 12 8 M12 2 V5 M12 19 V22 M2 12 H5 M19 12 H22"
    static let cloud = "M6 17 H17 C20 17 20 12 17 12 C17 8 11 7 9.5 11 C6 11 5 17 6 17 Z"
    static let rain = "M6 15 H17 C20 15 20 10 17 10 C17 6 11 5 9.5 9 C6 9 5 15 6 15 Z M9 18 L8 21 M13 18 L12 21 M17 18 L16 21"
    static let snow = "M12 3 V21 M4 7.5 L20 16.5 M4 16.5 L20 7.5"
    static let storm = "M13 3 L6 14 H12 L11 21 L18 10 H12 Z"
    static let save = "M5 4 H16 L19 7 V20 H5 Z M8 4 V9 H15 V4 M8 20 V14 H16 V20"
    static let share = "M12 15 V4 M8 8 L12 4 L16 8 M5 12 V20 H19 V12"
    static let download = "M12 4 V15 M8 11 L12 15 L16 11 M5 20 H19"
    static let exit = "M10 4 H5 V20 H10 M9 12 H20 M16 8 L20 12 L16 16"
    static let info = "M12 4 A8 8 0 1 0 12 20 A8 8 0 1 0 12 4 M12 11 V16 M12 8 V8.5"
    static let calendar = "M4 6 H20 V20 H4 Z M4 10 H20 M8 3 V7 M16 3 V7"
    static let list = "M5 7 H19 M5 12 H19 M5 17 H19"
    static let people = "M3 20 C3 15 15 15 15 20 M15 15 C19 14.5 21.5 16.5 21.5 20 M9 5 A3 3 0 1 0 9 11 A3 3 0 1 0 9 5"
    static let lock = "M6 11 H18 V20 H6 Z M8 11 V8 A4 4 0 0 1 16 8 V11"
    static let sort = "M7 5 V19 M4 8 L7 5 L10 8 M17 19 V5 M14 16 L17 19 L20 16"

    /// The icon for a kind of weather (see `WeatherEvents.kindWords`).
    static func weather(_ kind: String) -> String {
        switch kind {
        case "sun", "heat": return sun
        case "rain": return rain
        case "snow", "cold": return snow
        case "storm": return storm
        default: return cloud
        }
    }
}

private struct InsideCardKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True inside a `CardSection`: nested figure strips drop their own frame instead of drawing a card in a card.
    var insideCard: Bool {
        get { self[InsideCardKey.self] }
        set { self[InsideCardKey.self] = newValue }
    }
}

/// A titled block: the small champagne label above (with an optional note or link at the right), the content inside a bordered card.
/// Rows inside separate themselves with `CardLine()`.
struct CardSection<Content: View, Trailing: View>: View {
    var title: String
    var rule = true
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.tidyText).capsLabel()
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, 2)
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: Theme.Space.s) { content() }
                    .environment(\.insideCard, true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension CardSection where Trailing == EmptyView {
    init(_ title: String, rule: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, rule: rule, trailing: { EmptyView() }, content: content)
    }
}

/// The line between two rows inside a card.
struct CardLine: View {
    @Environment(\.outsidePalette) private var palette
    var body: some View { Rectangle().fill(palette.divider).frame(height: 1) }
}

/// Key figures in a bordered card, cells separated by vertical lines; a second row follows the first when there are more than `columns`.
struct FigureCard: View {
    typealias Item = KeyFigures.Item
    var items: [Item]
    var columns = 3
    @Environment(\.insideCard) private var insideCard

    var body: some View {
        if insideCard {
            strip
        } else {
            Card(padding: 14, radius: Theme.Radius.hero) { strip }
        }
    }

    private var strip: some View {
        let rows: [[Item]] = stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                if r > 0 { CardLine().padding(.vertical, 10) }
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { i, it in
                        Stat(label: it.label, value: it.value, tint: it.tint, sub: it.sub)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, i == 0 ? 0 : 12)
                            .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(Theme.divider).frame(width: 1) } }
                    }
                    ForEach(0..<(columns - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
            }
        }
    }
}

/// The headline of a page: a small label over one big serif figure, in a hero card, with an optional grey line under it.
struct HeroFigure: View {
    var label: String
    var value: String
    var tint: Color = Theme.ivory
    var note: String = ""

    var body: some View {
        Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).capsLabel()
                Text(value.tidyText).font(.hero(34)).foregroundStyle(tint).minimumScaleFactor(0.6).lineLimit(1)
                if !note.isEmpty { Text(note.tidyText).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// An empty or explanatory state in a card (never a bare grey line).
struct NoteCard: View {
    var text: String
    var glyph: String = Glyph.info
    var tint: Color? = nil
    @Environment(\.outsidePalette) private var palette

    var body: some View {
        Card(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                GlyphView(glyph: glyph, size: 18, weight: 1.5, tint: palette.inkFaint)
                Text(text.tidyText).font(.system(size: 13.5)).foregroundStyle(tint ?? palette.inkSoft).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }
}

/// A row inside a card: a small round icon, a title with a grey line, a figure with a grey line under it, optional chevron.
struct RowLine: View {
    var glyph: String
    var tint: Color = Theme.gold
    var title: String
    var subtitle: String = ""
    var trailing: String = ""
    var trailingSub: String = ""
    var trailingTint: Color = Theme.ivory
    var chevron = false

    var body: some View {
        HStack(spacing: 12) {
            IconCircle(glyph: glyph, size: 34, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.tidyText).font(.system(size: 14.5)).foregroundStyle(Theme.ivory).lineLimit(3).multilineTextAlignment(.leading)
                if !subtitle.isEmpty { Text(subtitle.tidyText).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).lineLimit(3).multilineTextAlignment(.leading) }
            }
            Spacer(minLength: 8)
            if !trailing.isEmpty || !trailingSub.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    if !trailing.isEmpty { Text(trailing.tidyText).font(.system(size: 14.5, weight: .medium).monospacedDigit()).foregroundStyle(trailingTint) }
                    if !trailingSub.isEmpty { Text(trailingSub.tidyText).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }
                }
            }
            if chevron { GlyphView(glyph: Glyph.chevron, size: 13, weight: 2, tint: Theme.ivoryDim) }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A quiet link: champagne text and a chevron, 44 pt tall.
struct LinkLabel: View {
    var text: String
    var body: some View {
        HStack(spacing: 4) {
            Text(text).font(.system(size: 12.5, weight: .medium))
            GlyphView(glyph: Glyph.chevron, size: 11, weight: 2, tint: Theme.gold)
        }
        .foregroundStyle(Theme.gold).frame(minHeight: 44).contentShape(Rectangle())
    }
}

/// The grey-outlined secondary button for the other answers next to a `QuietButtonStyle` one (8 pt corners, never filled).
struct GreyOutlineButtonStyle: ButtonStyle {
    @Environment(\.outsidePalette) private var palette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(minHeight: 36)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(palette.lineStrong, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

/// The body of a Phone app page: a scroll view with the standard margins and a readable maximum width.
struct PhonePageScroll<Content: View>: View {
    var spacing: CGFloat = 14
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content() }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .ledgerBackground()
    }
}
