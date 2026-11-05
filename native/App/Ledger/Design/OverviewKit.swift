import SwiftUI

// The shared overview layout (NEXT_JOBS G, mockup native/design/table-layout-2026-10): figure cards, one bordered table whose rows each
// open their own page or popup, a row of count tiles, a latest-activity list and a warning note with an action. Each screen still brings
// its own content and icons; these pieces only draw. Money in every string must already come through the store or currency formatter.

extension Glyph {
    static let ovKey = "M8 14 A4 4 0 1 0 8 6 A4 4 0 1 0 8 14 M11 10 H21 M17 10 V14"
    static let ovCoin = "M12 3 A9 9 0 1 0 12 21 A9 9 0 1 0 12 3 M9 12 H15 M9 9 H15"
    static let ovShield = "M12 3 L19 6 V12 C19 16 16 19 12 21 C8 19 5 16 5 12 V6 Z"
    static let ovCalendar = "M5 5 H19 V20 H5 Z M5 10 H19 M9 3 V7 M15 3 V7"
}

/// The small champagne caps label above a block.
private struct OverviewCaps: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(1.4).foregroundStyle(Theme.gold).lineLimit(1).minimumScaleFactor(0.8)
    }
}

// MARK: Figure card

/// One hero figure: a small label, a big serif value and a grey or coloured line under it (the change against before).
struct OverviewFigureCard: View {
    var label: String
    var value: String
    var note: String = ""
    var noteTint: Color = Theme.ivoryMuted
    /// The number behind `value`: when it changes the figure rolls and flashes green or red. nil keeps the figure still.
    var live: Double? = nil
    /// With `live`: the figure counts up to its value (from 0 the first time, from the old value when it changes) using this text.
    var countFormat: ((Double) -> String)? = nil
    var valueTint: Color = Theme.ivory

    var body: some View {
        Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.gold).lineLimit(1)
                figureText
                Text(note.tidyText).font(.system(size: 11.5)).foregroundStyle(noteTint).lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var figureText: some View {
        if let live, let countFormat {
            CountedFigure(value: live, format: countFormat, tint: valueTint).font(.serifTitle(30)).lineLimit(1).minimumScaleFactor(0.6)
        } else {
            Text(value).font(.serifTitle(30)).foregroundStyle(Theme.ivory).lineLimit(1).minimumScaleFactor(0.6).moneyFlash(live ?? 0)
        }
    }
}

// MARK: Table

/// One choice of a row that opens a small popup menu instead of a page.
struct OverviewMenuItem: Identifiable {
    var id: String { title }
    var title: String
    var action: () -> Void
}

/// One row of an `OverviewTable`: an icon circle, a name with a grey line, a value with a small coloured note under it, a chevron.
/// A row with `menu` entries opens that menu; otherwise a tap runs `action`.
struct OverviewRowData: Identifiable {
    var id: String
    var glyph: String
    var title: String
    var subtitle: String = ""
    var value: String = ""
    var valueTint: Color = Theme.ivory
    var note: String = ""
    var noteTint: Color = Theme.ivoryFaint
    /// The number behind `value` and its text: the value counts up to it (see `CountedFigure`) instead of showing at once.
    var live: Double? = nil
    var liveText: ((Double) -> String)? = nil
    var menu: [OverviewMenuItem] = []
    var action: () -> Void = {}
}

struct OverviewRow: View {
    var row: OverviewRowData

    var body: some View {
        if row.menu.isEmpty {
            Button { Haptics.tap(); row.action() } label: { label }.buttonStyle(PressableStyle())
        } else {
            Menu {
                ForEach(row.menu) { item in Button(item.title) { Haptics.choose(); item.action() } }
            } label: { label }
        }
    }

    @ViewBuilder private var valueView: some View {
        if let live = row.live, let text = row.liveText {
            CountedFigure(value: live, format: text, tint: row.valueTint).font(.system(size: 14).monospacedDigit())
        } else {
            Text(row.value.tidyText).font(.system(size: 14).monospacedDigit()).foregroundStyle(row.valueTint)
        }
    }

    private var label: some View {
        HStack(spacing: 10) {
            IconCircle(glyph: row.glyph, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title.tidyText).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(2).multilineTextAlignment(.leading)
                if !row.subtitle.isEmpty {
                    Text(row.subtitle.tidyText).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                if !row.value.isEmpty {
                    valueView
                        .lineLimit(2).multilineTextAlignment(.trailing).minimumScaleFactor(0.8)
                }
                if !row.note.isEmpty {
                    Text(row.note.tidyText).font(.system(size: 11.5)).foregroundStyle(row.noteTint).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: 150, alignment: .trailing)
            GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The overview table: one bordered card with a caps heading (and anything at its right, such as a period menu), the rows, and an
/// optional "View all" link under them that opens the same table in full.
struct OverviewTable<Trailing: View>: View {
    var title: String
    var rows: [OverviewRowData]
    var emptyText: String = ""
    var footer: String = ""
    var footerAction: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        Card(padding: 0, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    OverviewCaps(text: title)
                    Spacer(minLength: 8)
                    trailing()
                }
                .padding(.top, 12).padding(.bottom, 4)
                if rows.isEmpty && !emptyText.isEmpty {
                    Text(emptyText).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).padding(.vertical, 8)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    if i > 0 { CardLine() }
                    OverviewRow(row: row)
                }
                if let footerAction, !footer.isEmpty {
                    CardLine()
                    HStack {
                        Spacer()
                        Button { Haptics.tap(); footerAction() } label: {
                            Text(footer).font(.system(size: 12.5)).foregroundStyle(Theme.gold).frame(minHeight: 36)
                        }.buttonStyle(PressableStyle())
                    }
                } else {
                    Spacer().frame(height: 6)
                }
            }
            .padding(.horizontal, 14)
        }
    }
}

extension OverviewTable where Trailing == EmptyView {
    init(title: String, rows: [OverviewRowData], emptyText: String = "", footer: String = "", footerAction: (() -> Void)? = nil) {
        self.init(title: title, rows: rows, emptyText: emptyText, footer: footer, footerAction: footerAction, trailing: { EmptyView() })
    }
}

// MARK: Count tiles

// MARK: Activity

// MARK: Note

