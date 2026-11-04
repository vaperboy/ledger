import SwiftUI
import UniformTypeIdentifiers
import GameCore
import Countries
import SaveSystem
import Businesses
import Simulation
import Finance

/// First screen. The game keeps one save (written after every day, with the previous copy and month-end backups kept by
/// `SaveStore`), so the screen has three states:
/// - no save: start a new game or bring one over from the web game;
/// - a save: continue it, with what it holds (who, where, which week, how many companies, when it was saved);
/// - a save that could not be opened: why, a retry, and the warning that a new game or an import replaces it.
/// Starting or importing over an existing save asks first, because it replaces that save.
struct StartView: View {
    @EnvironmentObject var store: GameStore
    @Environment(AdCoordinator.self) private var ads
    @State private var summary: SaveSummary?
    @State private var pending: PendingAction?
    @State private var settingUp = false
    @State private var showSettings = false
    private let countries: [Country] = (try? CountryBook.bundled().countries) ?? []

    /// What is replaced if the player goes ahead, in one line.
    private var replacedLine: String {
        if let s = summary { return "\(s.playerName)'s game (week \(s.week + 1), \(s.companies) \(s.companies == 1 ? "company" : "companies")) will be replaced." }
        return "The saved game that could not be opened will be replaced."
    }

    /// Runs `body` at once when there is no save, otherwise after the player confirms replacing it.
    private func replacingSave(_ title: String, button: String, _ body: @escaping () -> Void) {
        guard store.hasSavedGame else { body(); return }
        pending = PendingAction(title: title, message: replacedLine + " The copy before it is kept as a backup file, but the game will no longer open it.",
                                button: button, destructive: true, run: body)
    }

    /// The new-player start: the company is created fully set up and open on day 1 (`LifeStory.fresh`).
    private func begin(country: String, trade: String, company: String) {
        replacingSave("Start a new game?", button: "Start new game") {
            store.newGame(name: "", countryCode: country, story: .fresh, tradeID: trade, companyName: company)
            ads.resetForNewSave()
        }
    }

    var body: some View {
        Group {
            if settingUp {
                NewPlayerSetup(onClose: { settingUp = false }, begin: { (country: String, trade: String, company: String) in begin(country: country, trade: trade, company: company) })
            } else {
                home
            }
        }
        .ledgerBackground()
        .onAppear { summary = store.currentSaveSummary() }
        .confirmAction($pending)
        .centerSheet(isPresented: $showSettings, title: "Settings", size: .tall) { SettingsView(embedded: true) }
    }

    /// Name, one primary button (Start, or Continue with New game under it) and the Settings gear.
    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AppHeader(title: "Ledger", subtitle: "Business tycoon simulator") {
                    Button { Haptics.tap(); showSettings = true } label: {
                        GlyphView(glyph: Glyph.settings, size: 22)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Settings")
                }
                .padding(.top, 40)

                if let problem = store.loadProblem {
                    problemCard(problem)
                } else if store.hasSavedGame {
                    continueCard
                }
                primaryButtons
            }
            .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var primaryButtons: some View {
        if store.hasSavedGame && store.loadProblem == nil {
            Button { Haptics.tap(); settingUp = true } label: {
                Text("New game").font(.system(size: 14)).foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(PressableStyle())
        } else {
            QuietButton(title: "Start", fullWidth: true) { settingUp = true }
        }
    }

    // MARK: States

    private var continueCard: some View {
        Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Your game").capsLabel()
                if let s = summary {
                    let country = countries.first { $0.code == s.countryCode }
                    HStack(spacing: 12) {
                        IconCircle(glyph: Glyph.person, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.playerName).font(.serifTitle(24)).foregroundStyle(Theme.ivory)
                            Text("\(country.map { "\($0.flag) \($0.name)" } ?? s.countryCode) · \(GameCalendar.dateString(week: s.week))")
                                .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                        }
                    }
                    FigureCard(items: [
                        .init(label: "Week", value: "\(s.week + 1)"),
                        .init(label: "Companies", value: "\(s.companies)"),
                        .init(label: "Saved", value: s.savedAt.formatted(.relative(presentation: .named))),
                    ]).environment(\.insideCard, true)
                } else {
                    // The save opens (from the copy kept before the last one) but its summary could not be read.
                    Text("A saved game is waiting.").font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted)
                }
                QuietButton(title: "Continue", fullWidth: true) { store.loadCurrent() }
            }
        }
    }

    private func problemCard(_ problem: String) -> some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: 10) {
                    IconCircle(glyph: Glyph.warning, size: 34, tint: Theme.caution)
                    Text("Your save could not be opened").font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory)
                }
                Text(problem).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                Text("The file stays on this device untouched until you start or import another game, which replaces it.")
                    .font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                QuietButton(title: "Try again") { store.loadCurrent(); summary = store.currentSaveSummary() }
            }
        }
    }
}
