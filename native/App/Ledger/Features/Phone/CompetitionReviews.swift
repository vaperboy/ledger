import SwiftUI
import GameCore
import Businesses
import Simulation

extension Glyph {
    static let reviewStar = "M12 3 L14.6 8.6 L20.7 9.3 L16.2 13.4 L17.5 19.4 L12 16.4 L6.5 19.4 L7.8 13.4 L3.3 9.3 L9.4 8.6 Z"
}

struct StarRatingView: View {
    @Environment(\.outsidePalette) private var P
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    var rating: Double
    var size: CGFloat = 15
    var showsNumber = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(StandingWords.starGlyphs(rating)).font(.system(size: size * scale)).foregroundStyle(P.accent)
            if showsNumber {
                Text(String(format: "%.1f / 5", rating)).textStyle(size >= 18 ? .headline : .caption, tint: P.inkSoft, numeric: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "%.1f out of 5 stars", rating))
    }
}

struct CompetitionReviews: View {
    @EnvironmentObject var store: GameStore
    enum Side: String, CaseIterable, Hashable { case yours = "Yours", rivals = "Rivals" }
    @State private var companyID = 0
    @State private var side: Side = .yours
    @State private var openRival: Int?

    var body: some View {
        Group {
            if let e = store.engine {
                page(e)
            } else {
                Color.clear
            }
        }
    }

    private func page(_ e: GameEngine) -> some View {
        let companies: [Company] = CompetitionApp.reviewCompanies(e)
        let chosen: Company? = companies.first { $0.id == companyID } ?? companies.first
        return Group {
            if let co = chosen {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        selector(companies, co)
                        SegmentedPill(items: Side.allCases, title: { $0.rawValue }, selection: $side, identifier: { "competition-reviews-" + $0.rawValue.lowercased() })
                    }
                    .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.s)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
                    SegmentPager(items: Side.allCases, selection: $side) { (sd: Side) in
                        sidePage(e, co, sd)
                    }
                }
            } else {
                EmptyState(glyph: Glyph.reviewStar, title: "No reviews yet", message: "Reviews arrive once a business is open and customers come.")
                    .padding(.horizontal, Theme.Space.page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .accessibilityIdentifier("competition-reviews")
    }

    private func sidePage(_ e: GameEngine, _ co: Company, _ sd: Side) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                if sd == .yours { yours(e, co) } else { rivals(e, co) }
            }
            .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.xs).padding(.bottom, Theme.Space.xl)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
    }

    private func selector(_ companies: [Company], _ chosen: Company) -> some View {
        Menu {
            ForEach(companies) { (co: Company) in
                Button {
                    companyID = co.id
                    openRival = nil
                    Haptics.choose()
                } label: {
                    if co.id == chosen.id { Label(co.name, systemImage: "checkmark") } else { Text(co.name) }
                }
            }
        } label: {
            BusinessPickerLabel(caption: "Business", title: chosen.name)
        }
        .accessibilityLabel("Business: \(chosen.name)")
        .accessibilityIdentifier("competition-business-picker")
    }

    @ViewBuilder private func yours(_ e: GameEngine, _ co: Company) -> some View {
        let all: Int = max(1, co.value("rv41").array.count)
        let r: ReviewSummary = e.reviewSummary(co, limit: all)
        yourHero(r)
        if r.count > 0 {
            starsGiven(r)
            LedgerSection("What customers say") {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(r.lines.enumerated()), id: \.element.id) { (n: Int, line: ReviewLine) in
                        if n > 0 { Hairline() }
                        reviewCard(line)
                            .padding(.vertical, Theme.Space.m)
                            .newMarker(.competition, CompetitionApp.lineKey(e, co, line), style: .dot, alignment: .topTrailing)
                    }
                }
            }
        } else {
            EmptyState(glyph: Glyph.reviewStar, title: "No reviews yet", message: "Customers write once they have bought.", centered: false)
        }
    }

    private func yourHero(_ r: ReviewSummary) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if r.enough {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(String(format: "%.1f", r.rating)).font(.system(size: 44, weight: .medium, design: .serif).monospacedDigit()).foregroundStyle(Theme.ink)
                    Text("out of 5").textStyle(.caption, tint: Theme.inkFaint)
                }
                StarRatingView(rating: r.rating, size: 18, showsNumber: false)
                Text(r.word + " \u{00B7} " + (r.count == 1 ? "1 review" : "\(r.count) reviews")).textStyle(.body, tint: Theme.inkSoft)
            } else {
                Text("No rating yet").textStyle(.display, tint: Theme.inkSoft)
                Text(r.count == 1 ? "1 review so far" : "\(r.count) reviews so far").textStyle(.caption, tint: Theme.inkFaint)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func starsGiven(_ r: ReviewSummary) -> some View {
        let top: Double = Double(max(1, r.histogram.max() ?? 1))
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach([5, 4, 3, 2, 1], id: \.self) { (stars: Int) in
                let n: Int = r.histogram.indices.contains(stars - 1) ? r.histogram[stars - 1] : 0
                ProgressLine(fraction: Double(n) / top, tint: stars >= 4 ? Theme.gain : (stars == 3 ? Theme.accent : Theme.loss),
                             label: "\(stars)\u{2605}", value: "\(n)")
            }
        }
    }

    private func reviewCard(_ line: ReviewLine) -> some View {
        let when: String = line.weeksAgo == 0 ? "This week" : "\(line.weeksAgo) wk ago"
        let who: String = (line.flag.isEmpty ? "" : line.flag + " ") + "\(line.who), \(line.age)"
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(repeating: "\u{2605}", count: line.stars) + String(repeating: "\u{2606}", count: max(0, 5 - line.stars)))
                    .textStyle(.caption, tint: Theme.accent)
                    .accessibilityLabel("\(line.stars) of 5 stars")
                Spacer()
                Text(when).textStyle(.caption, tint: Theme.inkFaint)
            }
            Text(line.text.tidyMoney).textStyle(.body).fixedSize(horizontal: false, vertical: true)
            Text(who).textStyle(.caption, tint: Theme.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func rivals(_ e: GameEngine, _ co: Company) -> some View {
        let group: ReviewGroup? = e.reviewBoard().first { (g: ReviewGroup) -> Bool in g.rows.contains { $0.companyID == co.id } }
        if let group {
            LedgerSection(group.title.tidyText) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(group.rows.enumerated()), id: \.element.id) { (n: Int, row: ReviewRow) in
                        if n > 0 { Hairline() }
                        boardRow(e, co, row)
                    }
                }
            }
        } else {
            EmptyState(glyph: Glyph.reviewStar, title: "No rivals yet", message: "Rivals appear once the business has opened.", centered: false)
        }
    }

    private func boardRow(_ e: GameEngine, _ co: Company, _ row: ReviewRow) -> some View {
        let shown: Bool = row.count >= Reviews.minimumShown
        let rank: String = row.rank.map { "Rated \($0) of \(row.of ?? $0)" } ?? "No rating yet"
        let open: Bool = row.rivalID != nil && openRival == row.rivalID
        let rating: String = shown ? String(format: " \u{00B7} %.1f / 5", row.rating) : ""
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Button {
                Haptics.tap()
                if let rid = row.rivalID { openRival = (openRival == rid) ? nil : rid }
            } label: {
                HStack(alignment: .center, spacing: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(row.name + (row.mine ? " (yours)" : "")).textStyle(.headline, tint: row.mine ? Theme.accent : nil).lineLimit(1)
                        Text("\(rank) \u{00B7} \(row.count) reviews" + rating).textStyle(.caption, tint: Theme.inkFaint)
                    }
                    Spacer(minLength: Theme.Space.s)
                    if shown { StarRatingView(rating: row.rating, size: 13, showsNumber: false) } else { Text("\u{2013}").textStyle(.body, tint: Theme.inkFaint) }
                    if row.rivalID != nil { MoreChevron().rotationEffect(.degrees(open ? 90 : 0)) }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .disabled(row.rivalID == nil)
            if open, let rid = row.rivalID, let d = e.rivalDetail(companyID: co.id, rivalID: rid) {
                Text("Typical comments").capsLabel(Theme.inkFaint)
                ForEach(d.reviews) { (line: ReviewLine) in
                    Hairline()
                    reviewCard(line)
                }
            }
        }
        .padding(.vertical, Theme.Space.s)
    }
}

struct BusinessPickerLabel: View {
    @Environment(\.outsidePalette) private var P
    var caption: String
    var title: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(caption.tidyText).capsLabel(P.inkFaint)
            HStack(spacing: Theme.Space.xs) {
                Text(title.tidyText).textStyle(.figure).lineLimit(1).minimumScaleFactor(0.7)
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint).rotationEffect(.degrees(90))
                Spacer(minLength: 0)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
