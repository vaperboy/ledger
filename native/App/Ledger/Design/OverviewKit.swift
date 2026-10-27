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
        Text(text.uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(1.4).foregroundStyle(Theme.gold).lineLimit(1)
    }
}

/// A caps label with a quiet link at the right ("View all ›").
private struct OverviewCapsLine: View {
    var text: String
    var link: String = ""
    var action: (() -> Void)? = nil
    var body: some View {
        HStack {
            OverviewCaps(text: text)
            Spacer(minLength: 8)
            if let action, !link.isEmpty {
                Button { Haptics.tap(); action() } label: {
                    Text(link).font(.system(size: 12)).foregroundStyle(Theme.gold).frame(minHeight: 28)
                }.buttonStyle(.plain)
            }
        }
    }
}

// MARK: Figure card

/// One hero figure: a small label, a big serif value and a grey or coloured line under it (the change against before).
struct OverviewFigureCard: View {
    var label: String
    var value: String
    var note: String = ""
    var noteTint: Color = Theme.ivoryMuted

    var body: some View {
        Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.gold).lineLimit(1)
                Text(value).font(.serifTitle(30)).foregroundStyle(Theme.ivory).lineLimit(1).minimumScaleFactor(0.6)
                Text(note.tidyText).font(.system(size: 11.5)).foregroundStyle(noteTint).lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
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
    var menu: [OverviewMenuItem] = []
    var action: () -> Void = {}
}

struct OverviewRow: View {
    var row: OverviewRowData

    var body: some View {
        if row.menu.isEmpty {
            Button { Haptics.tap(); row.action() } label: { label }.buttonStyle(.plain)
        } else {
            Menu {
                ForEach(row.menu) { item in Button(item.title) { Haptics.choose(); item.action() } }
            } label: { label }
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
                    Text(row.value.tidyText).font(.system(size: 14).monospacedDigit()).foregroundStyle(row.valueTint)
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
                        }.buttonStyle(.plain)
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

struct CountTileData: Identifiable {
    var id: String { label }
    var glyph: String
    var count: Int
    var label: String
    var tint: Color = Theme.ivory
    var action: () -> Void
}

/// A row of three or four tiles with a number each; every tile opens its area. The caps line can carry a "View all" link.
struct CountTiles: View {
    var title: String
    var link: String = ""
    var linkAction: (() -> Void)? = nil
    var tiles: [CountTileData]

    var body: some View {
        Card(padding: 12, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 6) {
                OverviewCapsLine(text: title, link: link, action: linkAction)
                HStack(spacing: 8) {
                    ForEach(tiles) { t in tile(t) }
                }
            }
        }
    }

    private func tile(_ t: CountTileData) -> some View {
        Button { Haptics.tap(); t.action() } label: {
            VStack(spacing: 4) {
                GlyphView(glyph: t.glyph, size: 20, weight: 1.5)
                Text("\(t.count)").font(.serifTitle(24)).foregroundStyle(t.tint)
                Text(t.label).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(t.label): \(t.count)")
    }
}

// MARK: Activity

struct ActivityItem: Identifiable {
    var id: String
    var glyph: String
    var title: String
    var subtitle: String
    var action: () -> Void
}

/// The latest-activity list: icon, title, grey line, chevron; each row opens what it is about.
struct ActivityList: View {
    var title: String = "Latest activity"
    var items: [ActivityItem]
    var emptyText: String = "Nothing yet."

    var body: some View {
        Card(padding: 0, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 0) {
                OverviewCaps(text: title).padding(.top, 12).padding(.bottom, 4)
                if items.isEmpty {
                    Text(emptyText).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).padding(.vertical, 8)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { CardLine() }
                    Button { Haptics.tap(); item.action() } label: { row(item) }.buttonStyle(.plain)
                }
                Spacer().frame(height: 6)
            }
            .padding(.horizontal, 14)
        }
    }

    private func row(_ item: ActivityItem) -> some View {
        HStack(spacing: 10) {
            IconCircle(glyph: item.glyph, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title.tidyText).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineLimit(2).multilineTextAlignment(.leading)
                Text(item.subtitle.tidyText).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(2).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: Note

/// An amber note with one action at the right (the payroll warning with "Appoint").
struct OverviewNote: View {
    var text: String
    var actionTitle: String
    var accessibilityLabel: String = ""
    var action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            GlyphView(glyph: Glyph.warning, size: 16, weight: 1.9, tint: Theme.caution)
            Text(text.tidyText).font(.system(size: 12.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { Haptics.tap(); action() } label: {
                Text("\(actionTitle) ›").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.gold, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel.isEmpty ? actionTitle : accessibilityLabel)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.caution.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Color(hex: 0x6A5630), lineWidth: 1))
    }
}
