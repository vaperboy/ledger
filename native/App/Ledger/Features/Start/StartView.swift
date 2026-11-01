import SwiftUI
import UniformTypeIdentifiers
import GameCore
import Countries
import SaveSystem
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
    @State private var name = ""
    @State private var countryCode = ""
    @State private var showImporter = false
    @State private var showPaste = false
    @State private var pasted = ""
    @State private var summary: SaveSummary?
    @State private var pending: PendingAction?
    @State private var story: LifeStory = .loan
    @State private var familyCityID = ""
    @State private var previews: [LifeStory: StoryPreview] = [:]
    private let countries: [Country] = ((try? CountryBook.bundled().countries) ?? []).sorted { $0.name < $1.name }

    /// The country of the device's region if the game has it; otherwise the first in the list. No country is the built-in default.
    private var initialCountry: String {
        let region = Locale.current.region?.identifier ?? ""
        let code = region == "GB" ? "UK" : region
        return countries.first { $0.code == code }?.code ?? countries.first?.code ?? ""
    }

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

    private func begin() {
        let n = name.trimmingCharacters(in: .whitespaces)
        replacingSave("Start a new game?", button: "Start new game") { store.newGame(name: n, countryCode: countryCode, story: story, cityID: story.needsCity && !familyCityID.isEmpty ? familyCityID : nil) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AppHeader(title: "Ledger", subtitle: "Business tycoon simulator").padding(.top, 40)

                if let problem = store.loadProblem {
                    problemCard(problem)
                } else if store.hasSavedGame {
                    continueCard
                }

                newGameCard
                importCard
            }
            .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .ledgerBackground()
        .onAppear {
            if countryCode.isEmpty { countryCode = initialCountry }
            summary = store.currentSaveSummary()
        }
        .confirmAction($pending)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText, .json, .data]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { store.errorText = "That file could not be read as text."; return }
            // Ask once the file picker has gone, so the question is not lost behind it.
            DispatchQueue.main.async { replacingSave("Import this save?", button: "Import") { store.importLegacy(text: text) } }
        }
        .sheet(isPresented: $showPaste) {
            NavigationStack {
                VStack(spacing: Theme.Space.m) {
                    TextEditor(text: $pasted).font(.system(.caption, design: .monospaced)).frame(minHeight: 220)
                        .scrollContentBackground(.hidden)
                        .overlay(alignment: .top) { Hairline() }.overlay(alignment: .bottom) { Hairline() }
                    // The warning sits on the button itself here, so no second dialog has to appear over a closing sheet.
                    if store.hasSavedGame { Text(replacedLine).font(.caption).foregroundStyle(Theme.caution).frame(maxWidth: .infinity, alignment: .leading) }
                    Button(store.hasSavedGame ? "Import and replace" : "Import") { showPaste = false; store.importLegacy(text: pasted); pasted = "" }
                        .buttonStyle(QuietButtonStyle()).disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding().ledgerBackground()
                .navigationTitle("Paste save text").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showPaste = false } } }
            }
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

    @ViewBuilder private var newGameCard: some View {
        CardSection("New game") {
            TextField("Your name", text: $name)
                .textInputAutocapitalization(.words)
                .font(.system(size: 15))
                .padding(.vertical, 8)
            CardLine()
            HStack {
                Text("Home country").font(.system(size: 14)).foregroundStyle(Theme.ivoryMuted)
                Spacer()
                Picker("Home country", selection: $countryCode) {
                    ForEach(countries) { c in Text("\(c.flag) \(c.name)").tag(c.code) }
                }
                .pickerStyle(.menu)
            }
            if let c = countries.first(where: { $0.code == countryCode }) {
                Text("Currency: \(c.currencyCode)").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            }
            if countries.isEmpty {
                Text("The country list could not be loaded, so a new game cannot start. Reinstalling the app restores it.")
                    .font(.system(size: 12)).foregroundStyle(Theme.loss)
            }
        }
        if !countryCode.isEmpty { storyPicker }
        QuietButton(title: "Begin", fullWidth: true) { begin() }
            .disabled(countryCode.isEmpty).opacity(countryCode.isEmpty ? 0.4 : 1)
        if store.hasSavedGame {
            Text("Replaces your saved game; you will be asked first.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
        }
    }

    /// Each story with the numbers the engine produces for the chosen country (a game is built and read, nothing is typed in).
    private var storyPicker: some View {
        let country = countries.first { $0.code == countryCode }
        let cur = country.map { Currency(country: $0, rates: ExchangeRates()) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Your story").capsLabel().padding(.horizontal, 2)
            ForEach(LifeStory.allCases, id: \.self) { s in
                ChoiceCard(title: s.title.tidyMoney, subtitle: storyLine(s, cur), selected: story == s) { story = s }
            }
            if story.needsCity, let country {
                Picker("Where is the family café?", selection: Binding(get: { familyCityID.isEmpty ? (country.cities.first?.id ?? "") : familyCityID }, set: { familyCityID = $0 })) {
                    ForEach(country.cities) { Text($0.name).tag($0.id) }
                }.pickerStyle(.menu)
            }
        }
        .task(id: countryCode + "|" + familyCityID) { loadPreviews() }
    }

    private func storyLine(_ s: LifeStory, _ cur: Currency?) -> String {
        guard let p = previews[s], let cur else { return s.tagline }
        return s.tagline + "\n" + storyFacts(p, cur)
    }

    private func storyFacts(_ p: StoryPreview, _ cur: Currency) -> String {
        var parts = ["Cash \(cur.tidyDisplay(p.cash))"]
        if p.debt > 0 { parts.append("debt \(cur.tidyDisplay(p.debt)), repaid with about \(cur.tidyDisplay(p.monthlyRepayment)) a month") } else { parts.append("no debt") }
        if let n = p.companyName { parts.append("you own \(n), worth about \(cur.tidyDisplay(p.companyValue))") } else { parts.append("no business yet") }
        parts.append("credit \(Int(p.credit.rounded()))")
        return parts.joined(separator: " · ")
    }

    private func loadPreviews() {
        guard !countryCode.isEmpty else { return }
        var out: [LifeStory: StoryPreview] = [:]
        for s in LifeStory.allCases { if let p = GameEngine.storyPreview(s, countryCode: countryCode, cityID: s.needsCity && !familyCityID.isEmpty ? familyCityID : nil) { out[s] = p } }
        previews = out
    }

    private var importCard: some View {
        CardSection("Bring a save from the web game") {
            Text("Your original file is kept untouched. The game is converted into a new native save" + (store.hasSavedGame ? ", which replaces the current one." : "."))
                .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                QuietButton(title: "Choose file", fullWidth: true) { showImporter = true }
                QuietButton(title: "Paste text", fullWidth: true) { showPaste = true }
            }
        }
    }
}
