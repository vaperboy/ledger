import SwiftUI
import GameCore
import Businesses
import Simulation

/// What is happening around you: the headlines, the local business paper.
/// Original: the news list, `V.paper40` (business paper).
struct NewsView: View {
    enum Page: String, CaseIterable, Hashable { case headlines = "Headlines", paper = "The paper" }
    @EnvironmentObject var store: GameStore
    @State private var page: Page = .headlines

    var body: some View {
        if let e = store.engine {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    SectionTabs(items: Page.allCases, title: { $0.rawValue }, selection: $page).padding(.horizontal, -18)
                    switch page {
                    case .headlines: headlines(e)
                    case .paper: paper(e)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ledgerBackground()
        }
    }

    // MARK: Headlines

    @ViewBuilder private func headlines(_ e: GameEngine) -> some View {
        let news = e.news
        if news.isEmpty {
            NoteCard(text: "No news yet. Headlines about the economy, your rivals and your companies appear as the weeks go by.", glyph: Glyph.news)
        } else {
            // Two sections only: this week (bad news first), then everything older with its date under each line.
            let now = news.filter { $0.week == e.state.week }.sorted { ($0.tone == "bad" ? 0 : 1) < ($1.tone == "bad" ? 0 : 1) }
            let older = news.filter { $0.week != e.state.week }
            if !now.isEmpty {
                CardSection("This week") { newsRows(now, dated: false) }
            }
            if !older.isEmpty {
                CardSection("Earlier") { newsRows(older, dated: true) }
            }
        }
    }

    private func newsRows(_ items: [NewsItem], dated: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, n in
                if i > 0 { CardLine() }
                RowLine(glyph: n.tone == "bad" ? Glyph.warning : n.tone == "good" ? Glyph.market : Glyph.news,
                        tint: n.tone == "bad" ? Theme.loss : n.tone == "good" ? Theme.gain : Theme.ivoryMuted, title: n.text,
                        subtitle: dated ? GameCalendar.dateString(week: n.week) : "")
            }
        }
    }

    // MARK: The paper

    @ViewBuilder private func paper(_ e: GameEngine) -> some View {
        let pages = e.frontPages
        let img = e.publicImage
        VStack(alignment: .leading, spacing: 4) {
            Text(e.paperName).font(.serifTitle(24)).foregroundStyle(Theme.ivory)
            Text("The local business paper. A front page every week; interviews arrive in your inbox.").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
        }
        CardSection(title: "How the paper sees you", trailing: { Text(e.publicImageWord).font(.system(size: 12)).foregroundStyle(Theme.gold) }) {
            VStack(spacing: 0) {
                FlatRow(label: "Trust", value: "\(Int(img.trust.rounded()))", rule: false)
                FlatRow(label: "Boldness", value: "\(Int(img.bold.rounded()))")
                FlatRow(label: "Care for people", value: "\(Int(img.care.rounded()))")
            }
        }
        if pages.isEmpty {
            NoteCard(text: "No front page yet. The first issue is printed at the end of a week with something to report.", glyph: Glyph.news)
        }
        ForEach(Array(pages.enumerated()), id: \.offset) { _, p in
            CardSection(title: GameCalendar.dateString(week: p.week), trailing: { EmptyView() }) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(e.displayText(p.headline.tidyMoney)).font(.serifTitle(19)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                    if !p.deck.isEmpty { Text(e.displayText(p.deck)).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) }
                    ForEach(Array(p.side.enumerated()), id: \.offset) { _, s in
                        Text("· " + e.displayText(s)).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
