import SwiftUI
import GameCore
import Businesses
import Simulation
import Countries

/// The Weather phone app: it imitates a real weather app. Current conditions for one city, the day hour by hour, the weeks ahead,
/// a city switcher for the countries where the player has companies, and what the weather does to each company. Its own warning
/// (storm, heatwave, flood) is read from the engine (`bigWeatherWarnings`) and also shows as a bubble and a banner on the Phone home.
/// The engine forecast is weekly: the weeks ahead are
/// the engine's own forecast. The separate "Typical day" card only illustrates the usual shape of a day around this week's temperature.
struct WeatherApp: View {
    @EnvironmentObject var store: GameStore
    @State private var chosen: String? = nil

    var body: some View {
        if let e = store.engine {
            let cc: String = chosen ?? countries(e).first ?? e.state.homeCountryCode
            let kind: String = e.weatherForecast(countryCode: cc).now.kind
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    WeatherHeader()
                    WeatherWarningCards(engine: e)
                    WeatherCityBar(engine: e, countries: countries(e), selection: Binding(get: { cc }, set: { chosen = $0 }))
                    WeatherNowCard(engine: e, country: cc)
                    WeatherWeeksCard(engine: e, country: cc)
                    WeatherHourlyCard(engine: e, country: cc)
                    WeatherCompaniesCard(engine: e, country: cc)
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .outsideScreen(OutsidePalette.weather(kind: kind))
            .accessibilityIdentifier("weather-app")
        }
    }

    /// Home country first, then every other country where a company is open.
    private func countries(_ e: GameEngine) -> [String] {
        var out: [String] = [e.state.homeCountryCode]
        for co in e.state.companies where co.status == .open && !out.contains(co.countryCode) { out.append(co.countryCode) }
        return out
    }
}

/// The app's own masthead: the round back button, the title and the grey line, in the weather palette.
struct WeatherHeader: View {
    @Environment(\.outsidePalette) private var P
    var body: some View {
        HStack(spacing: 12) {
            OutsideBack()
            VStack(alignment: .leading, spacing: 1) {
                Text("Weather").font(.serifTitle(26)).foregroundStyle(P.ink).accessibilityAddTraits(.isHeader)
                Text("Conditions, forecast and warnings").font(.system(size: 12.5)).foregroundStyle(P.inkSoft)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Helpers shared by the Weather cards.
enum WeatherText {
    static func word(_ kind: String) -> String { WeatherEvents.kindWords[kind] ?? kind.capitalized }
    static func pct(_ f: Double) -> String { (f >= 1 ? "+" : "−") + "\(Int((abs(f - 1) * 100).rounded()))%" }
    static func deg(_ t: Double) -> String { "\(Int(t.rounded()))°" }
    /// Temperature at an hour of the day: coolest about 3, warmest about 15.
    static func hourly(mean: Double, hour: Int) -> Double { mean + 2.5 * sin((Double(hour) - 9) / 24 * 2 * Double.pi) }
}

// MARK: Warnings

/// The big-event warning(s): storm, heatwave, flood, with the companies that can be hit.
struct WeatherWarningCards: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        let list: [WeatherEvents.BigWarning] = engine.bigWeatherWarnings()
        VStack(spacing: Theme.Space.s) {
            ForEach(list, id: \.countryCode) { w in card(w) }
        }
    }

    private func card(_ w: WeatherEvents.BigWarning) -> some View {
        let names: [String] = w.companyIDs.compactMap { engine.state.company($0)?.name }
        let glyph: String = w.kind == "storm" ? Glyph.storm : (w.kind == "heat" ? Glyph.sun : Glyph.rain)
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    IconCircle(glyph: glyph, size: 36, tint: P.loss)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WARNING").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(P.loss)
                        Text(w.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(P.ink).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                Text("Can hit: " + names.joined(separator: ", ")).font(.system(size: 12.5)).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true)
                ForEach(w.companyIDs, id: \.self) { id in
                    Button { store.openCompany(id, section: .operations) } label: {
                        HStack {
                            Text(engine.state.company(id)?.name ?? "").font(.system(size: 13)).foregroundStyle(P.accent)
                            Spacer(minLength: 0)
                            GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: P.inkDim)
                        }.padding(.vertical, 4).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: City switcher

/// The city switcher: one chip per country where the player has a company.
struct WeatherCityBar: View {
    @Environment(\.outsidePalette) private var P
    var engine: GameEngine
    var countries: [String]
    @Binding var selection: String

    var body: some View {
        if countries.count > 1 {
            Menu {
                ForEach(countries, id: \.self) { cc in
                    Button(label(cc)) { selection = cc }
                }
            } label: {
                HStack(spacing: 8) {
                    GlyphView(glyph: Glyph.world, size: 16, weight: 1.5)
                    Text(label(selection)).font(.system(size: 14)).foregroundStyle(P.ink)
                    Spacer(minLength: 0)
                    Text("Change city").font(.system(size: 12)).foregroundStyle(P.inkFaint)
                    GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: P.inkDim)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(P.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(P.line, lineWidth: 1))
            }
            .accessibilityIdentifier("weather-city-switcher")
        }
    }

    private func label(_ cc: String) -> String {
        WeatherCity.name(engine, cc) + ", " + (engine.data.countries[cc]?.name ?? cc)
    }
}

enum WeatherCity {
    /// The city of the player's first open company in a country, or the player's own city at home.
    static func name(_ e: GameEngine, _ cc: String) -> String {
        let id: String = e.state.companies.first(where: { $0.status == .open && $0.countryCode == cc })?.cityID ?? e.state.player.cityID
        return e.data.countries.city(id, preferring: cc)?.city.name ?? (e.data.countries[cc]?.name ?? cc)
    }
}

// MARK: Now, hourly, weeks

struct WeatherNowCard: View {
    @Environment(\.outsidePalette) private var P
    var engine: GameEngine
    var country: String

    var body: some View {
        let f = engine.weatherForecast(countryCode: country)
        let note: String = f.now.againstNormal > 0.1 ? "Nicer than usual" : (f.now.againstNormal < -0.1 ? "Worse than usual" : "Usual for the month")
        return Card(padding: 18) {
            VStack(spacing: 6) {
                Text(WeatherCity.name(engine, country)).font(.serifTitle(22)).foregroundStyle(P.ink)
                GlyphView(glyph: Glyph.weather(f.now.kind), size: 34, weight: 1.4)
                Text(WeatherText.deg(f.now.temperature)).font(.serifTitle(64)).foregroundStyle(P.ink).monospacedDigit()
                Text(WeatherText.word(f.now.kind)).font(.system(size: 15)).foregroundStyle(P.inkSoft)
                Text("\(f.now.rainyDays) rainy day\(f.now.rainyDays == 1 ? "" : "s") this week · \(note)").font(.system(size: 12)).foregroundStyle(P.inkFaint)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }
}

struct WeatherHourlyCard: View {
    @Environment(\.outsidePalette) private var P
    var engine: GameEngine
    var country: String

    var body: some View {
        let f = engine.weatherForecast(countryCode: country)
        let hours: [Int] = [0, 3, 6, 9, 12, 15, 18, 21]
        return CardSection(title: "Typical day (illustration, not a forecast)", trailing: { EmptyView() }) {
            HStack(spacing: 0) {
                ForEach(hours, id: \.self) { h in
                    VStack(spacing: 8) {
                        Text(String(format: "%02d", h)).font(.system(size: 11).monospacedDigit()).foregroundStyle(P.inkFaint)
                        GlyphView(glyph: Glyph.weather(f.now.kind), size: 18, weight: 1.4, tint: P.inkSoft)
                        Text(WeatherText.deg(WeatherText.hourly(mean: f.now.temperature, hour: h))).font(.system(size: 13).monospacedDigit()).foregroundStyle(P.ink)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

struct WeatherWeeksCard: View {
    @Environment(\.outsidePalette) private var P
    var engine: GameEngine
    var country: String

    var body: some View {
        let f = engine.weatherForecast(countryCode: country)
        return CardSection(title: "The weeks ahead", trailing: { EmptyView() }) {
            VStack(spacing: 0) {
                ForEach(f.ahead, id: \.week) { d in
                    row(d)
                    if d.week != f.ahead.last?.week { CardLine() }
                }
            }
        }
    }

    private func row(_ d: WeatherEvents.Forecast) -> some View {
        let storm: Bool = d.kind == "storm"
        return HStack(spacing: 10) {
            IconCircle(glyph: Glyph.weather(d.kind), size: 30, tint: storm ? P.loss : P.inkSoft)
            VStack(alignment: .leading, spacing: 2) {
                Text("Week of " + GameCalendar.dateString(week: d.week)).font(.system(size: 13.5)).foregroundStyle(P.ink)
                Text(WeatherText.word(d.kind) + (d.uncertain ? " · uncertain" : "")).font(.system(size: 11.5)).foregroundStyle(storm ? P.loss : P.inkFaint)
            }
            Spacer(minLength: 8)
            Text("\(Int(d.temperatureLow.rounded()))–\(Int(d.temperatureHigh.rounded()))°").font(.system(size: 13).monospacedDigit()).foregroundStyle(P.inkSoft)
        }
        .padding(.vertical, 8)
    }
}

// MARK: Companies

/// How the weather moves each open company in the chosen country this week.
struct WeatherCompaniesCard: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var country: String

    var body: some View {
        let open: [Company] = engine.state.companies.filter { $0.status == .open && $0.countryCode == country }
        return CardSection(title: "Your companies here", trailing: { EmptyView() }) {
            if open.isEmpty {
                Text("You have no open company in this country. The forecast above is for the city itself.").font(.system(size: 13)).foregroundStyle(P.inkSoft)
            } else {
                VStack(spacing: 0) {
                    ForEach(open, id: \.id) { co in
                        row(co)
                        if co.id != open.last?.id { CardLine() }
                    }
                }
            }
        }
    }

    private func row(_ co: Company) -> some View {
        let line = engine.weatherLine(companyID: co.id)
        return Button { store.openCompany(co.id, section: .operations) } label: {
            HStack(spacing: 10) {
                IconCircle(glyph: Glyph.weather(line?.kind ?? "mixed"), size: 32, tint: P.inkSoft)
                VStack(alignment: .leading, spacing: 2) {
                    Text(co.name).font(.system(size: 14)).foregroundStyle(P.ink)
                    Text(effects(line)).font(.system(size: 11.5)).foregroundStyle(P.inkFaint).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                GlyphView(glyph: Glyph.chevron, size: 13, weight: 2, tint: P.inkDim)
            }
            .padding(.vertical, 8).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func effects(_ l: (weather: Double, tourists: Double, workingTime: Double, kind: String)?) -> String {
        guard let l else { return "No reading" }
        var parts: [String] = []
        if abs(l.weather - 1) >= 0.03 { parts.append("customers \(WeatherText.pct(l.weather)) from the weather") }
        if abs(l.tourists - 1) >= 0.03 { parts.append("visitors \(WeatherText.pct(l.tourists))") }
        if l.workingTime < 0.97 { parts.append("working time \(WeatherText.pct(l.workingTime))") }
        if parts.isEmpty { return "Not moved by much this week" }
        let text: String = parts.joined(separator: " · ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
