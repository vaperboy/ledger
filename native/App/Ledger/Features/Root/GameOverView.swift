import SwiftUI
import GameCore
import Events
import Businesses
import Simulation

struct GameOverView: View {
    @EnvironmentObject var store: GameStore
    @Environment(AdCoordinator.self) private var ads
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var engine: GameEngine
    @State private var ruleGrown: CGFloat = 0
    @State private var barGrown: CGFloat = 0
    @State private var rowsShown = 0
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 42

    var body: some View {
        let s = engine.state
        let over = s.gameOver
        let endWeek = over["week"].isNull ? s.week : over["week"].int
        let endWorth: Double = over["nw"].isNull ? engine.netWorth.total : over["nw"].double
        let reason: String = over["reason"].string == "insolvent"
            ? "You owe more than you own and the bank has ended it."
            : "Your account stayed empty for too long. The bank has stopped lending."
        let weeks = max(1, endWeek + 1)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("The ledger is closed").textStyle(.label, tint: Theme.inkFaint)
                    CountedFigure(value: endWorth, format: { (v: Double) -> String in store.short(v) }, tint: endWorth < 0 ? Theme.loss : Theme.ink, duration: 1.4)
                        .font(.hero(heroSize))
                        .lineLimit(2).minimumScaleFactor(0.8)
                    Rectangle().fill(Theme.gold).frame(height: 2)
                        .scaleEffect(x: reduceMotion ? 1 : ruleGrown, anchor: .leading)
                        .accessibilityHidden(true)
                    Text("\(s.player.name)'s net worth at the end").textStyle(.body, tint: Theme.inkSoft)
                    Text(reason).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                    Text("\(engine.difficulty.name) mode").textStyle(.caption, tint: Theme.inkFaint)
                }
                .padding(.top, Theme.Space.xxl)
                group("The run") {
                    FigureRow(items: [
                        .init(label: "Lasted", value: duration(weeks: weeks)),
                        .init(label: "Ended", value: GameCalendar.dateString(week: endWeek)),
                        .init(label: "Best net worth", value: store.short(max(s.stats.peakNetWorth, 0))),
                    ], columns: 3)
                }
                companiesGroup(s)
                totalsGroup(s)
            }
            .padding(.horizontal, Theme.Space.page).padding(.bottom, Theme.Space.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .task { await playEntrance() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Theme.Space.s) {
                SecondChanceOffer()
                if store.canRetrySameSetup {
                    Button("Retry with the same setup") { Haptics.tap(); store.retryWithSameSetup(); ads.resetForNewSave() }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                        .accessibilityIdentifier("game-over-retry")
                }
                Button("Back to the start screen") { Haptics.tap(); store.quitToMenu() }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("game-over-start")
            }
            .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.m).padding(.bottom, Theme.Space.s)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .background(Theme.page)
            .overlay(alignment: .top) { Hairline() }
        }
        .ledgerBackground()
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(title).textStyle(.label, tint: Theme.inkFaint)
            content()
        }
    }

    private func companiesGroup(_ s: GameState) -> some View {
        let businesses = s.companies.filter { $0.type != "hold" }
        let standing = businesses.filter { $0.status.isLive }.count
        let sold = businesses.filter { $0.status == .sold }.count
        let bust = businesses.filter { $0.status == .bust }.count
        return group("Companies") {
            if businesses.isEmpty {
                Text("You never started or bought a company.").textStyle(.body, tint: Theme.inkSoft)
            } else {
                outcomeBar(standing: standing, sold: sold, bust: bust)
                FigureRow(items: [
                    .init(label: "Standing", value: "\(standing)", tint: standing > 0 ? Theme.gain : Theme.ink),
                    .init(label: "Sold", value: "\(sold)"),
                    .init(label: "Went bust", value: "\(bust)", tint: bust > 0 ? Theme.loss : Theme.ink),
                ], columns: 3)
            }
        }
    }

    private func outcomeBar(standing: Int, sold: Int, bust: Int) -> some View {
        let total = CGFloat(max(1, standing + sold + bust))
        return GeometryReader { g in
            HStack(spacing: 2) {
                if standing > 0 { Rectangle().fill(Theme.gain).frame(width: g.size.width * barGrown * CGFloat(standing) / total) }
                if sold > 0 { Rectangle().fill(Theme.inkSoft).frame(width: g.size.width * barGrown * CGFloat(sold) / total) }
                if bust > 0 { Rectangle().fill(Theme.loss).frame(width: g.size.width * barGrown * CGFloat(bust) / total) }
            }
            .clipShape(Capsule())
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private func totalsGroup(_ s: GameState) -> some View {
        let trophies = Trophies.entries(s)
        let reached = trophies.filter { $0.reachedWeek != nil }.count
        let rows: [(glyph: String, title: String, value: String)] = [
            (Glyph.team, "Wages paid", store.short(s.stats.wagesPaid)),
            (Glyph.reports, "Tax paid", store.short(s.stats.taxPaid)),
            (Glyph.arrowIn, "Dividends you received", store.short(s.stats.dividendsReceived)),
            (Glyph.bank, "Interest paid", store.short(s.stats.interestPaid)),
            (Glyph.achievements, "Trophies", "\(reached) of \(trophies.count)"),
        ]
        return group("Over the whole run") {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { (i: Int, r: (glyph: String, title: String, value: String)) in
                    if i > 0 { Hairline().padding(.leading, Theme.Icon.medium + Theme.Space.m) }
                    LedgerRow(leading: .glyph(r.glyph), leadingTint: Theme.inkSoft, title: r.title, value: r.value)
                        .opacity(reduceMotion || rowsShown > i ? 1 : 0)
                        .offset(y: reduceMotion || rowsShown > i ? 0 : 8)
                }
                trophyStrip(trophies.filter { $0.reachedWeek != nil }, firstIndex: rows.count)
            }
        }
    }

    @ViewBuilder private func trophyStrip(_ reached: [Trophies.Entry], firstIndex: Int) -> some View {
        let shown: [Trophies.Entry] = Array(reached.prefix(6))
        if !shown.isEmpty {
            HStack(spacing: Theme.Space.s) {
                ForEach(Array(shown.enumerated()), id: \.offset) { (i: Int, t: Trophies.Entry) in
                    let on: Bool = reduceMotion || rowsShown > firstIndex + i
                    ThumbnailView(kind: .trophy, key: ArtLibrary.trophyKey(id: t.id, group: t.group), size: 40, shape: .round, glyph: Glyph.achievements)
                        .overlay(Circle().strokeBorder(Theme.gold, lineWidth: 1.5))
                        .scaleEffect(on ? 1 : 0.5).opacity(on ? 1 : 0)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, Theme.Space.m)
        }
    }

    private func playEntrance() async {
        if reduceMotion { ruleGrown = 1; barGrown = 1; rowsShown = 99; return }
        Motion.animate(.easeOut(duration: 0.9)) { ruleGrown = 1 }
        try? await Task.sleep(nanoseconds: 500_000_000)
        Motion.animate(Motion.revealAnimation) { barGrown = 1 }
        try? await Task.sleep(nanoseconds: 700_000_000)
        for _ in 0..<12 {
            Motion.animate(Motion.quickAnimation) { rowsShown += 1 }
            try? await Task.sleep(nanoseconds: 140_000_000)
        }
    }

    private func duration(weeks: Int) -> String {
        if weeks < 13 { return "\(weeks) week\(weeks == 1 ? "" : "s")" }
        let years = weeks / 52, months = (weeks % 52) * 12 / 52
        var parts: [String] = []
        if years > 0 { parts.append("\(years) year\(years == 1 ? "" : "s")") }
        if months > 0 { parts.append("\(months) month\(months == 1 ? "" : "s")") }
        return parts.joined(separator: " ")
    }
}
