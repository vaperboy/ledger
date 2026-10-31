import SwiftUI
import Countries

/// How much a manager or executive may decide alone: asks you, decides within a spend limit, or has full control.
/// One picker for every place that sets authority (company manager, management team, chain and group executives). It changes nothing
/// itself: the caller passes the engine actions, so each place keeps its own rules.
struct AuthorityPicker: View {
    enum Style { case compact, full }

    var level: Int
    /// Needed only for the spend limit; without it the picker sets the level alone (`AuthorityLevelPicker`).
    var currency: Currency? = nil
    /// The current spend limit, shown when the level is "Within limit".
    var limit: Double? = nil
    /// Spend limits to choose from, already in `currency`.
    var limitSteps: [Double] = []
    var limitLabel = "Spend up to"
    var style: Style = .compact
    var setLevel: (Int) -> Void
    var setLimit: ((Double) -> Void)? = nil

    var body: some View {
        let lvl = min(2, max(0, level))
        switch style {
        case .compact:
            HStack(spacing: 16) {
                Menu(AuthorityWords.label(lvl)) {
                    ForEach(0..<3, id: \.self) { l in Button(AuthorityWords.label(l)) { setLevel(l); Haptics.choose() } }
                }
                limitMenu(lvl)
            }
        case .full:
            VStack(alignment: .leading, spacing: 6) {
                SectionTabs(items: [0, 1, 2], title: { AuthorityWords.label($0) }, selection: Binding(get: { lvl }, set: { setLevel($0) }))
                    .padding(.horizontal, -Theme.Space.margin)
                Text(AuthorityWords.consequence(lvl)).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                limitMenu(lvl).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
            }
        }
    }

    @ViewBuilder private func limitMenu(_ lvl: Int) -> some View {
        if lvl == 1, let currency, let setLimit, let limit, !limitSteps.isEmpty {
            Menu("\(limitLabel) \(currency.tidyShort(limit))") {
                ForEach(limitSteps, id: \.self) { v in Button(currency.tidyShort(v)) { setLimit(v); Haptics.choose() } }
            }
        }
    }
}

/// A row of the Group tab that leads somewhere: a title, one line of detail, a figure or chevron on the right.
struct GroupLinkRow: View {
    var title: String
    var sub: String
    var trailing: String = ""
    var tint: Color = Theme.ivory
    var subTint: Color = Theme.ivoryFaint

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineLimit(1)
                if !sub.isEmpty { Text(sub).font(.system(size: 11)).foregroundStyle(subTint).lineLimit(2) }
            }
            Spacer(minLength: 8)
            if !trailing.isEmpty { Text(trailing).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(tint).lineLimit(1) }
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.gold.opacity(0.85))
        }
        .padding(.vertical, 9).contentShape(Rectangle())
    }
}
