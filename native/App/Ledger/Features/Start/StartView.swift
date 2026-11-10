import SwiftUI
import UniformTypeIdentifiers
import GameCore
import Countries
import SaveSystem
import Businesses
import Simulation
import Finance

struct StartView: View {
    @EnvironmentObject var store: GameStore
    @Environment(AdCoordinator.self) private var ads
    @State private var summary: SaveSummary?
    @State private var pending: PendingAction?
    @State private var settingUp = false
    @State private var showSettings = false
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 44
    private let countries: [Country] = (try? CountryBook.bundled().countries) ?? []

    private var replacedLine: String {
        if let s = summary { return "\(s.playerName)'s game (week \(s.week + 1), \(s.companies) \(s.companies == 1 ? "company" : "companies")) will be replaced." }
        return "The saved game that could not be opened will be replaced."
    }

    private func replacingSave(_ title: String, button: String, _ body: @escaping () -> Void) {
        guard store.hasSavedGame else { body(); return }
        pending = PendingAction(title: title, message: replacedLine + " The copy before it is kept as a backup file, but the game will no longer open it.",
                                button: button, alwaysAsk: true, tone: .warning, icon: "arrow.counterclockwise", run: body)
    }

    private func begin(country: String, trade: String, company: String, player: String, difficulty: Difficulty) {
        replacingSave("Start a new game?", button: "Start new game") {
            store.newGame(name: player, countryCode: country, story: .fresh, tradeID: trade, companyName: company, difficulty: difficulty)
            ads.resetForNewSave()
        }
    }

    var body: some View {
        Group {
            if settingUp {
                NewPlayerSetup(onClose: { settingUp = false }, begin: { (country: String, trade: String, company: String, player: String, difficulty: Difficulty) in begin(country: country, trade: trade, company: company, player: player, difficulty: difficulty) })
            } else {
                home
            }
        }
        .ledgerBackground()
        .onAppear { summary = store.currentSaveSummary() }
        .confirmAction($pending)
        .centerSheet(isPresented: $showSettings, title: "Settings", size: .tall, category: .detail, tone: .info) { SettingsView(embedded: true) }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                HStack {
                    Spacer()
                    Button { Haptics.tap(); showSettings = true } label: {
                        GlyphView(glyph: Glyph.settings, size: 22)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Settings")
                }
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Ledger").font(.serifTitle(heroSize)).foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("A business tycoon game, played one day at a time.").textStyle(.body, tint: Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Theme.Space.xl)
                if let problem = store.loadProblem {
                    problemCard(problem)
                } else if store.hasSavedGame {
                    saveSummary
                } else {
                    promises
                }
            }
            .padding(.horizontal, Theme.Space.page).padding(.bottom, Theme.Space.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { primaryButtons }
    }

    private var primaryButtons: some View {
        VStack(spacing: Theme.Space.xs) {
            if store.hasSavedGame && store.loadProblem == nil {
                Button("Continue") { Haptics.tap(); store.loadCurrent() }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("start-continue")
                Button("New game") { Haptics.tap(); settingUp = true }
                    .buttonStyle(TertiaryButtonStyle(fullWidth: true, tint: Theme.inkSoft))
                    .accessibilityIdentifier("start-new")
            } else {
                Button("Start") { Haptics.tap(); settingUp = true }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("start-new")
            }
        }
        .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.m).padding(.bottom, Theme.Space.s)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Theme.page)
    }

    private var promises: some View {
        let items: [(glyph: String, title: String, line: String)] = [
            (Glyph.group, "Open a business", ""),
            (Glyph.reports, "Keep the books", ""),
            (Glyph.invest, "Top the rich list", ""),
        ]
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { (i: Int, it: (glyph: String, title: String, line: String)) in
                if i > 0 { Hairline().padding(.leading, Theme.Icon.medium + Theme.Space.m) }
                LedgerRow(leading: .glyph(it.glyph), leadingTint: Theme.ink, title: it.title, subtitle: it.line, lineLimit: 3)
                    .padding(.vertical, Theme.Space.xs)
            }
        }
        .padding(.top, Theme.Space.xl)
    }

    private var saveSummary: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Your game").textStyle(.label, tint: Theme.inkFaint)
            if let s = summary {
                let country = countries.first { $0.code == s.countryCode }
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(s.playerName).textStyle(.title).lineLimit(1).minimumScaleFactor(0.7)
                    Text("\(country.map { "\($0.flag) \($0.name)" } ?? s.countryCode) · \(GameCalendar.dateString(week: s.week))")
                        .textStyle(.caption)
                }
                FigureRow(items: [
                    .init(label: "Week", value: "\(s.week + 1)"),
                    .init(label: "Companies", value: "\(s.companies)"),
                    .init(label: "Saved", value: s.savedAt.formatted(.relative(presentation: .named))),
                ], columns: 3)
                .padding(.top, Theme.Space.m)
                .overlay(alignment: .top) { Hairline() }
            } else {
                Text("A saved game is waiting.").textStyle(.body, tint: Theme.inkSoft)
            }
        }
    }

    private func problemCard(_ problem: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                LedgerGlyph(glyph: Glyph.warning, size: Theme.Icon.medium, tint: Theme.warn)
                Text("Your save could not be opened").textStyle(.headline)
            }
            Text(problem).textStyle(.body).fixedSize(horizontal: false, vertical: true)
            Button("Try again") { Haptics.tap(); store.loadCurrent(); summary = store.currentSaveSummary() }
                .buttonStyle(TertiaryButtonStyle(size: .compact))
                .padding(.leading, -Theme.Space.s)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.surfaceRaised))
    }
}
