import SwiftUI
import GameCore
import Businesses
import Simulation

extension Glyph {
    /// A five-point star, in the same 24 x 24 outline style as the other house icons.
    static let reviewStar = "M12 3 L14.6 8.6 L20.7 9.3 L16.2 13.4 L17.5 19.4 L12 16.4 L6.5 19.4 L7.8 13.4 L3.3 9.3 L9.4 8.6 Z"
}

/// A rating as five star glyphs and "4.2 / 5". The wording comes from `StandingWords`, so every screen writes a rating the same way.
struct StarRatingView: View {
    var rating: Double
    var size: CGFloat = 15
    /// Hide the number (a rating that is not shown yet).
    var showsNumber = true

    var body: some View {
        HStack(spacing: 6) {
            Text(StandingWords.starGlyphs(rating)).font(.system(size: size)).foregroundStyle(Theme.gold)
            if showsNumber {
                Text(String(format: "%.1f / 5", rating)).font(.system(size: size - 1.5).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "%.1f out of 5 stars", rating))
    }
}

/// The Reviews app (Phone): what customers write about each of your businesses, and how your rivals are rated. Your reviews are the
/// stored reviews of the company (`reviewSummary`). The rivals' ratings and review counts come from the review board (`reviewBoard`), and
/// the lines shown under a rival (`rivalDetail`) are a small sample the engine writes for it around its rating, the same every time:
/// rivals are not simulated customer by customer.
struct ReviewsApp: View {
    @EnvironmentObject var store: GameStore
    enum Side: String, CaseIterable, Hashable { case yours = "Yours", rivals = "Rivals" }
    /// The business shown; 0 = the first one that has reviews.
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
        .appScreen(title: "Reviews", subtitle: PhoneApp.reviews.subtitle)
        .onAppear { take() }
        .onChange(of: store.appRequest) { _, _ in take() }
    }

    /// The businesses that have reviews: open ones other than finance, energy, holdings and clubs (the review board's own rule).
    static func companies(_ e: GameEngine) -> [Company] {
        e.state.companies.filter { (co: Company) -> Bool in
            guard co.status == .open, let family = e.tradeInfo(companyID: co.id)?.family else { return false }
            return !["fin", "energy", "hold", "club"].contains(family)
        }
    }

    private func page(_ e: GameEngine) -> some View {
        let companies: [Company] = Self.companies(e)
        let chosen: Company? = companies.first { $0.id == companyID } ?? companies.first
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if let co = chosen {
                    selector(companies, co)
                    SegmentedPill(items: Side.allCases, title: { $0.rawValue }, selection: $side, identifier: { "reviews-side-" + $0.rawValue.lowercased() })
                    if side == .yours { yours(e, co) } else { rivals(e, co) }
                } else {
                    Card(padding: 14, radius: Theme.Radius.card) {
                        Text("Reviews arrive once a business is open and customers come.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("reviews-app")
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
            HStack(spacing: 10) {
                IconCircle(glyph: Glyph.reviewStar, size: 30)
                Text(chosen.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                Spacer(minLength: 8)
                GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim)
            }
            .padding(.horizontal, 12).frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Business: \(chosen.name)")
        .accessibilityIdentifier("reviews-business-picker")
    }

    private func take() {
        guard let id = store.takeReviewsRequest() else { return }
        companyID = id
        side = .yours
        openRival = nil
    }

    // MARK: Your reviews

    @ViewBuilder private func yours(_ e: GameEngine, _ co: Company) -> some View {
        let all: Int = max(1, co.value("rv41").array.count)
        let r: ReviewSummary = e.reviewSummary(co, limit: all)
        yourHero(r)
        if r.count > 0 {
            starsGiven(r)
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(r.lines) { (line: ReviewLine) in
                    EntityCard { reviewCard(line) }
                }
            }
        } else {
            Card(padding: 12, radius: Theme.Radius.row) {
                Text("No reviews yet.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    private func yourHero(_ r: ReviewSummary) -> some View {
        Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 6) {
                if r.enough {
                    StarRatingView(rating: r.rating, size: 22)
                    Text(r.word).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gold)
                } else {
                    Text("No rating yet").font(.serifTitle(24)).foregroundStyle(Theme.ivoryMuted)
                }
                Text(r.count == 1 ? "1 review" : "\(r.count) reviews").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    /// How many reviews gave each number of stars, five to one, as thin bars.
    private func starsGiven(_ r: ReviewSummary) -> some View {
        let top: Double = Double(max(1, r.histogram.max() ?? 1))
        return Card(padding: 14, radius: Theme.Radius.card) {
            VStack(spacing: 7) {
                ForEach([5, 4, 3, 2, 1], id: \.self) { (stars: Int) in
                    let n: Int = r.histogram.indices.contains(stars - 1) ? r.histogram[stars - 1] : 0
                    HStack(spacing: 10) {
                        Text("\(stars)\u{2605}").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).frame(width: 30, alignment: .leading)
                        GeometryReader { g in
                            Capsule().fill(Theme.hairline)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(stars >= 4 ? Theme.gain : (stars == 3 ? Theme.gold : Theme.loss))
                                        .frame(width: n == 0 ? 0 : max(3, g.size.width * CGFloat(Double(n) / top)))
                                }
                        }.frame(height: 5)
                        Text("\(n)").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.ivory).frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func reviewCard(_ line: ReviewLine) -> some View {
        let when: String = line.weeksAgo == 0 ? "This week" : "\(line.weeksAgo) wk ago"
        let who: String = (line.flag.isEmpty ? "" : line.flag + " ") + "\(line.who), \(line.age)"
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(String(repeating: "\u{2605}", count: line.stars) + String(repeating: "\u{2606}", count: max(0, 5 - line.stars)))
                    .font(.system(size: 12)).foregroundStyle(Theme.gold)
                Spacer()
                Text(when).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }
            Text(line.text.tidyMoney).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
            Text(who).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }
    }

    // MARK: Your rivals

    @ViewBuilder private func rivals(_ e: GameEngine, _ co: Company) -> some View {
        let group: ReviewGroup? = e.reviewBoard().first { (g: ReviewGroup) -> Bool in g.rows.contains { $0.companyID == co.id } }
        if let group {
            Text(group.title.tidyText).capsLabel()
            VStack(spacing: 10) {
                ForEach(group.rows) { (row: ReviewRow) in
                    boardRow(e, co, row)
                }
            }
        } else {
            Card(padding: 12, radius: Theme.Radius.row) {
                Text("Rivals appear once the business has opened.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    private func boardRow(_ e: GameEngine, _ co: Company, _ row: ReviewRow) -> some View {
        let shown: Bool = row.count >= Reviews.minimumShown
        let rank: String = row.rank.map { "Rated \($0) of \(row.of ?? $0)" } ?? "No rating yet"
        let open: Bool = row.rivalID != nil && openRival == row.rivalID
        return EntityCard {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    Haptics.tap()
                    if let rid = row.rivalID { openRival = (openRival == rid) ? nil : rid }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name + (row.mine ? " (yours)" : "")).font(.system(size: 14, weight: .medium)).foregroundStyle(row.mine ? Theme.gold : Theme.ivory).lineLimit(1)
                            Text("\(rank) \u{00B7} \(row.count) reviews").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        }
                        Spacer(minLength: 8)
                        if shown { StarRatingView(rating: row.rating, size: 13, showsNumber: false) } else { Text("\u{2013}").foregroundStyle(Theme.ivoryFaint) }
                        if row.rivalID != nil { MoreChevron().rotationEffect(.degrees(open ? 90 : 0)) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(row.rivalID == nil)
                if shown {
                    Text(String(format: "%.1f / 5", row.rating)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                }
                if open, let rid = row.rivalID, let d = e.rivalDetail(companyID: co.id, rivalID: rid) {
                    ForEach(d.reviews) { (line: ReviewLine) in
                        CardLine()
                        reviewCard(line)
                    }
                }
            }
        }
    }
}
