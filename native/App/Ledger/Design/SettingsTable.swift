import SwiftUI

/// How a settings row opens: a small sheet for a simple change, or a full-screen page for a bigger decision.
enum SettingOpens {
    case sheet, page
    var glyph: String { self == .sheet ? Glyph.settings : Glyph.chevron }
}

/// One row of a settings table: the setting's name with a grey note, its current value on the right, and a mark for what a tap opens
/// (a chevron for a full page, the small settings mark for a sheet). Used by the company tabs that replaced their second row of
/// sub-tabs with one page. Money in `value` must already come through the store or currency formatter.
struct SettingsTableRow: View {
    var title: String
    var note: String = ""
    var value: String
    var valueTint: Color = Theme.ivory
    var opens: SettingOpens = .page
    /// With a glyph the row takes the overview-table look: an icon circle in front, an optional coloured change line under the value,
    /// and a chevron at the end for both popups and pages.
    var glyph: String? = nil
    /// A picture slot in place of the icon circle (same 34 pt height, so the row does not change height).
    var thumb: ThumbSpec? = nil
    var change: String = ""
    var changeTint: Color = Theme.gain
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            if glyph != nil { overviewRow } else { plainRow }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(opens == .sheet ? "Opens a small sheet to change it" : "Opens a page")
    }

    private var overviewRow: some View {
        HStack(spacing: 10) {
            if let thumb { ThumbnailView(thumb, size: 34) } else { IconCircle(glyph: glyph ?? Glyph.settings, size: 34) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title.tidyText).font(.system(size: 14)).foregroundStyle(Theme.ivory).lineLimit(2)
                if !note.isEmpty { Text(note.tidyText).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value.tidyText).font(.system(size: 14).monospacedDigit()).foregroundStyle(valueTint).lineLimit(2).multilineTextAlignment(.trailing)
                if !change.isEmpty { Text(change.tidyText).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(changeTint).lineLimit(1) }
            }
            .frame(maxWidth: 150, alignment: .trailing)
            GlyphView(glyph: Glyph.chevron, size: 12, weight: 1.8, tint: Theme.ivoryFaint)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Theme.tableLine).frame(height: 1) }
        .contentShape(Rectangle())
    }

    private var plainRow: some View {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title.tidyText).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(2)
                    if !note.isEmpty { Text(note.tidyText).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(2) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(value.tidyText).font(.system(size: 13).monospacedDigit()).foregroundStyle(valueTint)
                    .lineLimit(2).multilineTextAlignment(.trailing).minimumScaleFactor(0.8)
                    .frame(maxWidth: 150, alignment: .trailing)
                GlyphView(glyph: opens.glyph, size: opens == .sheet ? 14 : 12, weight: 1.8, tint: Theme.ivoryDim)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.tableLine).frame(height: 1) }
            .contentShape(Rectangle())
    }
}

/// The settings list of the overview-table look: one bordered card with a caps label and rows made with `SettingsTableRow(glyph:)`.
struct OverviewSettingsCard<Content: View>: View {
    var heading: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 6) {
                Text(heading.uppercased()).capsLabel()
                VStack(spacing: 0, content: content)
            }
        }
    }
}

/// The sharp box around settings rows with its caps header.
struct SettingsTable<Content: View>: View {
    var heading: String = "Setting"
    @ViewBuilder var content: () -> Content

    var body: some View {
        SharpTable {
            TableHeader(columns: [TableColumn(title: heading), TableColumn(title: "Now", width: 150)])
            content()
        }
    }
}

/// A full-screen page for one bigger decision: scrolling content under the new-look header (round back button, title, subtitle).
struct SettingsPage<Content: View>: View {
    var title: String
    var subtitle: String
    var tab: AppTab = .company
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l, content: content)
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .appScreen(title: title, subtitle: subtitle, tab: tab)
    }
}
