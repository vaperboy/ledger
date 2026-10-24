import SwiftUI
import GameCore
import Businesses
import Simulation

/// What is happening around you: the headlines, the local business paper, and the weather and visitors that move your customers.
/// Original: the news list, `V.paper40` (business paper) and `V.wx56` (weather and tourism).
struct NewsView: View {
    enum Page: String, CaseIterable, Hashable { case headlines = "Headlines", paper = "The paper", weather = "Weather and visitors" }
    @EnvironmentObject var store: GameStore
    @State private var page: Page = .headlines

    var body: some View {
        if let e = store.engine {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    SectionTabs(items: Page.allCases, title: { $0.rawValue }, selection: $page).padding(.horizontal, -Theme.Space.margin)
                    switch page {
                    case .headlines: headlines(e)
                    case .paper: paper(e)
                    case .weather: WeatherPage(engine: e)
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ledgerBackground()
            .navigationTitle("News")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Headlines

    @ViewBuilder private func headlines(_ e: GameEngine) -> some View {
        let news = e.news
        if news.isEmpty {
            Text("No news yet. Headlines about the economy, your rivals and your companies appear as the weeks go by.").font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted)
        } else {
            let weeks = news.map { $0.week }.reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }
            ForEach(weeks, id: \.self) { w in
                LedgerSection(title: w == e.state.week ? "This week" : GameCalendar.dateString(week: w), trailing: { EmptyView() }) {
                    VStack(spacing: 0) {
                        ForEach(news.filter { $0.week == w }) { n in
                            ListRow(symbol: n.tone == "bad" ? "exclamationmark.triangle.fill" : n.tone == "good" ? "arrow.up.right.circle.fill" : "newspaper.fill",
                                    tint: n.tone == "bad" ? Theme.loss : n.tone == "good" ? Theme.gain : Theme.ivoryMuted, title: n.text)
                        }
                    }
                }
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
        LedgerSection(title: "How the paper sees you", trailing: { Text(e.publicImageWord).font(.system(size: 12)).foregroundStyle(Theme.gold) }) {
            VStack(spacing: 0) {
                FlatRow(label: "Trust", value: "\(Int(img.trust.rounded()))", rule: false)
                FlatRow(label: "Boldness", value: "\(Int(img.bold.rounded()))")
                FlatRow(label: "Care for people", value: "\(Int(img.care.rounded()))")
            }
        }
        if pages.isEmpty {
            Text("No front page yet. The first issue is printed at the end of a week with something to report.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint)
        }
        ForEach(Array(pages.enumerated()), id: \.offset) { _, p in
            LedgerSection(title: GameCalendar.dateString(week: p.week), trailing: { EmptyView() }) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(e.displayText(p.headline)).font(.serifTitle(19)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                    if !p.deck.isEmpty { Text(e.displayText(p.deck)).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) }
                    ForEach(Array(p.side.enumerated()), id: \.offset) { _, s in
                        Text("· " + e.displayText(s)).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// The weather this week and the next three, visitors' events, and how they move each of your companies this week.
struct WeatherPage: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    private var countries: [String] {
        let live = engine.state.companies.filter { $0.status == .open }.map { $0.countryCode }
        let codes = live.isEmpty ? [engine.state.homeCountryCode] : live
        return codes.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    private func word(_ kind: String) -> String { WeatherEvents.kindWords[kind] ?? kind.capitalized }
    private func symbol(_ kind: String) -> String {
        switch kind {
        case "sun": return "sun.max"; case "rain": return "cloud.rain"; case "snow": return "snowflake"; case "heat": return "thermometer.sun"
        case "cold": return "thermometer.snowflake"; case "storm": return "cloud.bolt.rain"; default: return "cloud.sun"
        }
    }
    private func pct(_ f: Double) -> String { (f >= 1 ? "+" : "−") + "\(Int((abs(f - 1) * 100).rounded()))%" }

    var body: some View {
        let e = engine
        let storm = e.state.inbox.first { $0.status == "open" && $0.actionID == WeatherEvents.prepareAction }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if let m = storm {
                Button { store.showPhone = false; store.go(.openMessage(m.id)) } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.loss)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.displayText(m.title, companyID: m.companyID)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ivory).multilineTextAlignment(.leading)
                            Text("Decide whether to secure your places in the Inbox  →").font(.system(size: 12)).foregroundStyle(Theme.gold)
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            companies(e)
            ForEach(countries, id: \.self) { cc in country(e, cc) }
        }
    }

    @ViewBuilder private func companies(_ e: GameEngine) -> some View {
        let open = e.state.companies.filter { $0.status == .open }
        let moved: [(Company, (weather: Double, tourists: Double, workingTime: Double, kind: String))] = open.compactMap { co in
            guard let l = e.weatherLine(companyID: co.id) else { return nil }
            return abs(l.weather - 1) >= 0.03 || abs(l.tourists - 1) >= 0.03 || l.workingTime < 0.97 ? (co, l) : nil
        }
        LedgerSection(title: "Your companies this week", trailing: { EmptyView() }) {
            if open.isEmpty {
                Text("Once a company is open, this shows how the weather and visitors move its customers.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint)
            } else if moved.isEmpty {
                Text("The weather and visitors move none of your companies by much this week.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(moved.enumerated()), id: \.element.0.id) { i, pair in
                        let (co, l) = pair
                        if i > 0 { Hairline() }
                        Button { store.showPhone = false; store.openCompany(co.id, section: .operations) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: symbol(l.kind)).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(co.name).font(.system(size: 14)).foregroundStyle(Theme.ivory)
                                    Text(effects(l)).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.ivoryFaint)
                            }.padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func effects(_ l: (weather: Double, tourists: Double, workingTime: Double, kind: String)) -> String {
        var parts: [String] = []
        if abs(l.weather - 1) >= 0.03 { parts.append("customers \(pct(l.weather)) from the weather") }
        if abs(l.tourists - 1) >= 0.03 { parts.append("visitors \(pct(l.tourists))") }
        if l.workingTime < 0.97 { parts.append("working time \(pct(l.workingTime))") }
        return parts.joined(separator: " · ").prefix(1).uppercased() + parts.joined(separator: " · ").dropFirst()
    }

    @ViewBuilder private func country(_ e: GameEngine, _ cc: String) -> some View {
        let c = e.data.countries[cc]
        let f = e.weatherForecast(countryCode: cc)
        let events = e.touristEvents(countryCode: cc)
        LedgerSection(title: (c.map { $0.flag + " " + $0.name } ?? cc), trailing: { EmptyView() }) {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: symbol(f.now.kind)).font(.system(size: 15)).foregroundStyle(Theme.gold).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This week: " + word(f.now.kind)).font(.system(size: 14)).foregroundStyle(Theme.ivory)
                        Text("\(f.now.rainyDays) rainy day\(f.now.rainyDays == 1 ? "" : "s")" + (f.now.againstNormal > 0.1 ? " · nicer than usual" : f.now.againstNormal < -0.1 ? " · worse than usual" : ""))
                            .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                    }
                    Spacer(minLength: 8)
                    Text("\(Int(f.now.temperature.rounded()))°").font(.system(size: 15).monospacedDigit()).foregroundStyle(Theme.ivory)
                }.padding(.vertical, 8)
                ForEach(f.ahead, id: \.week) { d in
                    Hairline()
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: symbol(d.kind)).font(.system(size: 13)).foregroundStyle(d.kind == "storm" ? Theme.loss : Theme.ivoryMuted).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Week of " + GameCalendar.dateString(week: d.week)).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                            Text(word(d.kind) + (d.uncertain ? " · uncertain" : "")).font(.system(size: 11.5)).foregroundStyle(d.kind == "storm" ? Theme.loss : Theme.ivoryFaint)
                        }
                        Spacer(minLength: 8)
                        Text("\(Int(d.temperatureLow.rounded()))–\(Int(d.temperatureHigh.rounded()))°").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                    }.padding(.vertical, 8)
                }
                if !events.isEmpty {
                    Hairline()
                    ForEach(Array(events.enumerated()), id: \.offset) { _, ev in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: ev.factor >= 1 ? "person.3.fill" : "person.crop.circle.badge.xmark").font(.system(size: 12)).foregroundStyle(ev.factor >= 1 ? Theme.gain : Theme.loss).frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.displayText(ev.text)).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                                Text("Visitors \(pct(ev.factor)) until " + GameCalendar.dateString(week: ev.until) + (ev.city.map { " · \($0)" } ?? ""))
                                    .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                            }
                            Spacer(minLength: 0)
                        }.padding(.vertical, 8)
                    }
                }
            }
        }
    }
}
