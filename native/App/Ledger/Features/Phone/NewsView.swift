import SwiftUI
import GameCore
import Businesses
import Simulation
import Countries

/// The News phone app, drawn as a newspaper front page: masthead with the date and the weather line, one big lead story with its
/// standfirst, a two-column grid of smaller stories under section labels, and the older items as a plain list. Every story is a real
/// engine news item (`e.news`) or front page (`e.frontPages`); nothing is invented. Tap the masthead line to read how the paper sees you.
struct NewsView: View {
    @EnvironmentObject var store: GameStore
    @State private var showPaper = false

    var body: some View {
        if let e = store.engine {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    masthead(e)
                    frontPage(e)
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .outsideScreen()
            .accessibilityIdentifier("news-app")
            .navigationDestination(isPresented: $showPaper) { paperPage(e) }
        }
    }

    // MARK: Masthead

    private func masthead(_ e: GameEngine) -> some View {
        let f = e.weatherForecast(countryCode: e.state.homeCountryCode)
        let place: String = WeatherCity.name(e, e.state.homeCountryCode)
        let weather: String = WeatherText.word(f.now.kind) + ", " + WeatherText.deg(f.now.temperature) + " in " + place
        return VStack(spacing: 8) {
            HStack { OutsideBack(); Spacer() }
            Rectangle().fill(Theme.ivory).frame(height: 2)
            Text(e.paperName).font(.serifTitle(38)).foregroundStyle(Theme.ivory)
                .lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Rectangle().fill(Theme.ivory).frame(height: 0.8)
            HStack(spacing: 8) {
                Text(GameCalendar.dateString(week: e.state.week).uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(1.2)
                Spacer(minLength: 6)
                GlyphView(glyph: Glyph.weather(f.now.kind), size: 14, weight: 1.5, tint: Theme.ivoryMuted)
                Text(weather).font(.system(size: 11.5))
            }
            .foregroundStyle(Theme.ivoryMuted)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Button { showPaper = true } label: {
                HStack(spacing: 6) {
                    Text("How the paper sees you:").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                    Text(e.publicImageWord).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.gold)
                    GlyphView(glyph: Glyph.chevron, size: 11, weight: 2, tint: Theme.gold)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("news-paper-link")
        }
        .padding(.bottom, 14)
    }

    // MARK: Front page

    private struct Lead {
        var headline: String
        var standfirst: String
        var brief: [String]
        var dateline: String
        var skipText: String?
    }

    @ViewBuilder private func frontPage(_ e: GameEngine) -> some View {
        let news: [NewsItem] = e.news
        let thisWeek: [NewsItem] = news.filter { $0.week == e.state.week }.sorted { ($0.tone == "bad" ? 0 : 1) < ($1.tone == "bad" ? 0 : 1) }
        let older: [NewsItem] = news.filter { $0.week != e.state.week }
        if let lead = lead(e, thisWeek: thisWeek, older: older) {
            leadStory(lead)
            let rest: [NewsItem] = thisWeek.filter { $0.text != lead.skipText }
            if !rest.isEmpty { storyGrid(rest) }
            let earlier: [NewsItem] = older.filter { $0.text != lead.skipText }
            if !earlier.isEmpty { earlierList(earlier) }
        } else {
            VStack(spacing: 8) {
                Text("No news yet").font(.serifTitle(24)).foregroundStyle(Theme.ivory)
                Text("Headlines about the economy, your rivals and your companies appear as the weeks go by.")
                    .font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 40)
        }
    }

    /// The lead is the newest printed front page; with none yet, the first news item (bad news first) leads without a standfirst.
    private func lead(_ e: GameEngine, thisWeek: [NewsItem], older: [NewsItem]) -> Lead? {
        if let p = e.frontPages.first {
            let side: [String] = p.side.map { e.displayText($0) }
            return Lead(headline: e.displayText(p.headline.tidyMoney), standfirst: e.displayText(p.deck), brief: side,
                        dateline: "FRONT PAGE · " + GameCalendar.dateString(week: p.week).uppercased(), skipText: nil)
        }
        if let n = thisWeek.first ?? older.first {
            return Lead(headline: n.text, standfirst: "", brief: [], dateline: "TOP STORY · " + GameCalendar.dateString(week: n.week).uppercased(), skipText: n.text)
        }
        return nil
    }

    private func leadStory(_ l: Lead) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l.dateline).font(.system(size: 10.5, weight: .semibold)).tracking(1.4).foregroundStyle(Theme.gold)
            Text(l.headline).font(.serifTitle(31)).foregroundStyle(Theme.ivory)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            if !l.standfirst.isEmpty {
                Text(l.standfirst).font(.system(size: 15.5, design: .serif)).italic().foregroundStyle(Theme.ivoryMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !l.brief.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(l.brief.enumerated()), id: \.offset) { _, s in
                        Text("— " + s).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.top, 2)
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: Two-column grid

    private func sectionLabel(_ title: String) -> some View {
        HStack(spacing: 10) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(1.6).foregroundStyle(Theme.ivory)
            Rectangle().fill(Theme.borderStrong).frame(height: 1)
        }
        .padding(.top, 14).padding(.bottom, 10)
    }

    @ViewBuilder private func storyGrid(_ items: [NewsItem]) -> some View {
        let left: [NewsItem] = items.enumerated().filter { $0.offset % 2 == 0 }.map { $0.element }
        let right: [NewsItem] = items.enumerated().filter { $0.offset % 2 == 1 }.map { $0.element }
        sectionLabel("This week")
        HStack(alignment: .top, spacing: 0) {
            column(left).padding(.trailing, 12)
            Rectangle().fill(Theme.border).frame(width: 1)
            column(right).padding(.leading, 12)
        }
    }

    private func column(_ items: [NewsItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, n in
                if i > 0 { Rectangle().fill(Theme.hairline).frame(height: 1).padding(.vertical, 12) }
                story(n)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func kicker(_ tone: String) -> (String, String, Color) {
        switch tone {
        case "bad": return ("Warning", Glyph.warning, Theme.loss)
        case "good": return ("Good news", Glyph.market, Theme.gain)
        default: return ("Report", Glyph.news, Theme.ivoryMuted)
        }
    }

    private func story(_ n: NewsItem) -> some View {
        let k = kicker(n.tone)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                GlyphView(glyph: k.1, size: 11, weight: 1.8, tint: k.2)
                Text(k.0.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(1).foregroundStyle(k.2)
            }
            Text(n.text).font(.serifTitle(16)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Earlier

    private func earlierList(_ items: [NewsItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Earlier")
            ForEach(Array(items.enumerated()), id: \.offset) { i, n in
                if i > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(GameCalendar.dateString(week: n.week)).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.ivoryFaint).frame(width: 74, alignment: .leading)
                    Text(n.text).font(.system(size: 13.5, design: .serif)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: The paper (how it sees you, the printed front pages)

    private func paperPage(_ e: GameEngine) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) { paper(e) }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .ledgerBackground()
        .appScreen(title: e.paperName, subtitle: "The local business paper")
    }

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
