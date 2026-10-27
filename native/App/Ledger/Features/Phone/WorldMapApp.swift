import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// A map pin: a teardrop with a hole, drawn so the World app needs no image.
struct WorldPinShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let r = w / 2
        let c = CGPoint(x: rect.midX, y: rect.minY + r)
        p.addArc(center: c, radius: r, startAngle: .degrees(150), endAngle: .degrees(30), clockwise: false)
        p.addLine(to: CGPoint(x: rect.midX, y: rect.minY + h))
        p.closeSubpath()
        let hole = CGRect(x: c.x - r * 0.38, y: c.y - r * 0.38, width: r * 0.76, height: r * 0.76)
        p.addEllipse(in: hole)
        return p
    }
}

/// The World phone app, drawn as a map-style list: a simple schematic of the four world regions with a pin where you have companies,
/// region chips, and one row per country with a location pin and its key facts (population, currency, your companies and cities).
/// The three existing World pages (Around you, Biggest companies, Records) open from the foot of the list.
struct WorldMapApp: View {
    @EnvironmentObject var store: GameStore
    @State private var region: String = "All"
    @State private var opened: PhonePage?

    private let regionOrder: [String] = ["Americas", "Europe", "Middle East", "Asia and Pacific"]

    var body: some View {
        if let e = store.engine {
            let presence: [WorldAround.CountryPresence] = e.mapPresence()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(e, presence)
                    schematic(e, presence)
                    chips(e)
                    countryRows(e, presence)
                    morePages
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .outsideScreen()
            .accessibilityIdentifier("world-app")
            .navigationDestination(item: $opened) { (p: PhonePage) in
                pageContent(p).appScreen(title: p.rawValue, subtitle: "World")
            }
        }
    }

    // MARK: Header

    private func header(_ e: GameEngine, _ presence: [WorldAround.CountryPresence]) -> some View {
        let sites: Int = presence.reduce(0) { $0 + $1.cities.reduce(0) { $0 + $1.companies } }
        return HStack(spacing: 12) {
            OutsideBack()
            VStack(alignment: .leading, spacing: 1) {
                Text("World").font(.serifTitle(26)).foregroundStyle(Theme.ivory).accessibilityAddTraits(.isHeader)
                Text(presence.isEmpty ? "No company abroad or at home yet" : "\(sites) \(sites == 1 ? "company" : "companies") in \(presence.count) \(presence.count == 1 ? "country" : "countries")")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Schematic

    private struct RegionSpot { var name: String; var x: CGFloat; var y: CGFloat; var w: CGFloat; var h: CGFloat }

    private var spots: [RegionSpot] {
        [RegionSpot(name: "Americas", x: 0.20, y: 0.52, w: 0.24, h: 0.78),
         RegionSpot(name: "Europe", x: 0.50, y: 0.30, w: 0.20, h: 0.34),
         RegionSpot(name: "Middle East", x: 0.60, y: 0.58, w: 0.13, h: 0.22),
         RegionSpot(name: "Asia and Pacific", x: 0.82, y: 0.52, w: 0.26, h: 0.62)]
    }

    private func companiesIn(_ regionName: String, _ e: GameEngine, _ presence: [WorldAround.CountryPresence]) -> Int {
        presence.filter { e.data.countries[$0.id]?.region == regionName }.reduce(0) { $0 + $1.cities.reduce(0) { $0 + $1.companies } }
    }

    private func schematic(_ e: GameEngine, _ presence: [WorldAround.CountryPresence]) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
        return GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let h: CGFloat = geo.size.height
            ZStack {
                grid(w, h)
                ForEach(spots, id: \.name) { (s: RegionSpot) in
                    regionBlob(s, w, h, e, presence)
                }
            }
        }
        .frame(height: 190)
        .background(shape.fill(Theme.surfaceTable))
        .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
        .clipShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schematic of the world regions. " + regionSummary(e, presence))
    }

    private func regionSummary(_ e: GameEngine, _ presence: [WorldAround.CountryPresence]) -> String {
        let parts: [String] = regionOrder.compactMap { r in
            let n: Int = companiesIn(r, e, presence)
            return n > 0 ? "\(r): \(n)" : nil
        }
        return parts.isEmpty ? "No companies yet." : parts.joined(separator: ", ") + "."
    }

    private func grid(_ w: CGFloat, _ h: CGFloat) -> some View {
        Path { p in
            for i in 1..<6 { let x = w * CGFloat(i) / 6; p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h)) }
            for j in 1..<4 { let y = h * CGFloat(j) / 4; p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y)) }
        }
        .stroke(Theme.hairline, lineWidth: 1)
    }

    private func regionBlob(_ s: RegionSpot, _ w: CGFloat, _ h: CGFloat, _ e: GameEngine, _ presence: [WorldAround.CountryPresence]) -> some View {
        let n: Int = companiesIn(s.name, e, presence)
        let on: Bool = region == s.name
        let blob = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return ZStack {
            blob.fill(n > 0 ? Theme.goldWash : Theme.surface)
                .frame(width: w * s.w, height: h * s.h)
                .overlay(blob.strokeBorder(on ? Theme.gold : Theme.borderStrong, lineWidth: on ? 1.5 : 1).frame(width: w * s.w, height: h * s.h))
            VStack(spacing: 2) {
                if n > 0 {
                    WorldPinShape().fill(Theme.gold, style: FillStyle(eoFill: true)).frame(width: 16, height: 22)
                    Text("\(n)").font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(Theme.gold)
                }
                Text(s.name.uppercased()).font(.system(size: 8.5, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(n > 0 ? Theme.ivory : Theme.ivoryFaint).multilineTextAlignment(.center).lineLimit(2)
            }
            .frame(width: w * s.w - 6)
        }
        .position(x: w * s.x, y: h * s.y)
        .onTapGesture { region = region == s.name ? "All" : s.name }
    }

    // MARK: Chips

    private func chips(_ e: GameEngine) -> some View {
        let names: [String] = ["All"] + regionOrder
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(names, id: \.self) { (n: String) in chip(n) }
            }
        }
    }

    private func chip(_ name: String) -> some View {
        let on: Bool = region == name
        return Button { region = name } label: {
            Text(name).font(.system(size: 12.5, weight: on ? .semibold : .regular)).foregroundStyle(on ? Theme.gold : Theme.ivoryMuted)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Capsule().fill(on ? Theme.goldSelected : Color.clear))
                .overlay(Capsule().strokeBorder(on ? Theme.gold : Theme.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Country rows

    private func sortedCountries(_ e: GameEngine, _ presence: [WorldAround.CountryPresence]) -> [Country] {
        let mine: Set<String> = Set(presence.map { $0.id })
        let all: [Country] = e.data.countries.countries.filter { region == "All" || $0.region == region }
        return all.sorted { a, b in
            let am: Int = mine.contains(a.code) ? 0 : 1
            let bm: Int = mine.contains(b.code) ? 0 : 1
            if am != bm { return am < bm }
            return a.name < b.name
        }
    }

    @ViewBuilder private func countryRows(_ e: GameEngine, _ presence: [WorldAround.CountryPresence]) -> some View {
        let list: [Country] = sortedCountries(e, presence)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(list) { (c: Country) in
                countryRow(e, c, presence.first(where: { $0.id == c.code }))
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
        }
    }

    private func countryRow(_ e: GameEngine, _ c: Country, _ here: WorldAround.CountryPresence?) -> some View {
        let sites: Int = here?.cities.reduce(0) { $0 + $1.companies } ?? 0
        let home: Bool = c.code == e.state.homeCountryCode
        return HStack(alignment: .top, spacing: 12) {
            pin(on: sites > 0)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(c.flag + " " + c.name).font(.serifTitle(17)).foregroundStyle(Theme.ivory)
                    if home { Text("HOME").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(Theme.gold) }
                }
                Text(facts(c)).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                if let here, sites > 0 {
                    let cities: String = here.cities.filter { $0.companies > 0 }.map { "\($0.name) (\($0.companies))" }.joined(separator: ", ")
                    Text("\(sites) \(sites == 1 ? "company" : "companies"): " + cities).font(.system(size: 12.5)).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No company here").font(.system(size: 12)).foregroundStyle(Theme.ivoryDim)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func facts(_ c: Country) -> String {
        let pop: String = c.populationMillions >= 10 ? String(format: "%.0f m", c.populationMillions) : String(format: "%.1f m", c.populationMillions)
        return "\(c.region) · \(pop) people · \(c.currencyCode)"
    }

    private func pin(on: Bool) -> some View {
        ZStack {
            if on {
                WorldPinShape().fill(Theme.gold, style: FillStyle(eoFill: true))
            } else {
                WorldPinShape().stroke(Theme.ivoryDim, lineWidth: 1.4)
            }
        }
        .frame(width: 20, height: 28)
        .padding(.top, 2)
        .accessibilityHidden(true)
    }

    // MARK: The other World pages

    private var morePages: some View {
        let pages: [PhonePage] = [.around, .biggest, .records]
        return VStack(alignment: .leading, spacing: 0) {
            Text("MORE FROM THE WORLD").capsLabel().padding(.bottom, 6)
            ForEach(pages) { (p: PhonePage) in
                Button { opened = p } label: {
                    HStack(spacing: 12) {
                        GlyphView(glyph: p.glyph, size: 20, weight: 1.5, tint: Theme.gold).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.rawValue).font(.system(size: 14.5)).foregroundStyle(Theme.ivory)
                            Text(p.note).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                        }
                        Spacer(minLength: 8)
                        GlyphView(glyph: Glyph.chevron, size: 13, weight: 2, tint: Theme.ivoryDim)
                    }
                    .padding(.vertical, 11).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
        }
        .padding(.top, 10)
    }

    @ViewBuilder private func pageContent(_ page: PhonePage) -> some View {
        switch page {
        case .around: WorldAroundView()
        case .biggest: RankingView()
        case .records: WorldRecordsView()
        case .stats, .activity, .goals, .achievements: EmptyView()
        }
    }
}
