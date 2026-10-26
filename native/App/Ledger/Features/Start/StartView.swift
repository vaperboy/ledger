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
            VStack(spacing: Theme.Space.xl) {
                VStack(spacing: 6) {
                    Text("LEDGER").font(.serifTitle(42)).tracking(9).foregroundStyle(Theme.ivory)
                    Text("Business tycoon simulator").font(.label).tracking(1.5).foregroundStyle(Theme.ivoryFaint)
                }.padding(.top, 48)

                if let problem = store.loadProblem {
                    problemCard(problem)
                } else if store.hasSavedGame {
                    continueCard
                }

                newGameCard
                importCard
            }
            .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
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
                        .buttonStyle(GoldButtonStyle()).disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding().ledgerBackground()
                .navigationTitle("Paste save text").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showPaste = false } } }
            }
        }
    }

    // MARK: States

    private var continueCard: some View {
        LedgerSection("Your game") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                if let s = summary {
                    let country = countries.first { $0.code == s.countryCode }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.playerName).font(.serifTitle(24)).foregroundStyle(Theme.ivory)
                        Text("\(country.map { "\($0.flag) \($0.name)" } ?? s.countryCode) · \(GameCalendar.dateString(week: s.week)) · week \(s.week + 1)")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                        Text(s.companies == 0 ? "No companies yet" : "\(s.companies) \(s.companies == 1 ? "company" : "companies")")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                        HStack(spacing: 4) {
                            Text("Saved")
                            Text(s.savedAt, format: .relative(presentation: .named))
                        }
                        .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                    }
                } else {
                    // The save opens (from the copy kept before the last one) but its summary could not be read.
                    Text("A saved game is waiting.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                }
                Button { store.loadCurrent() } label: { Text("Continue") }.buttonStyle(GoldButtonStyle())
            }
        }
    }

    private func problemCard(_ problem: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.caution)
                    SectionLabel("Your save could not be opened")
                }
                Text(problem).font(.bodyText).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                Text("The file stays on this device untouched until you start or import another game, which replaces it.")
                    .font(.caption).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                Button("Try again") { store.loadCurrent(); summary = store.currentSaveSummary() }.buttonStyle(QuietButtonStyle())
            }
        }
    }

    private var newGameCard: some View {
        LedgerSection("New game") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                TextField("Your name", text: $name)
                    .textInputAutocapitalization(.words)
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.ivory.opacity(0.25)).frame(height: 0.5) }
                Picker("Home country", selection: $countryCode) {
                    ForEach(countries) { c in Text("\(c.flag) \(c.name)").tag(c.code) }
                }
                .pickerStyle(.menu)
                if let c = countries.first(where: { $0.code == countryCode }) {
                    Text("Currency: \(c.currencyCode)").font(.caption).foregroundStyle(Theme.ivoryMuted)
                }
                if !countryCode.isEmpty { storyPicker }
                if countries.isEmpty {
                    Text("The country list could not be loaded, so a new game cannot start. Reinstalling the app restores it.")
                        .font(.caption).foregroundStyle(Theme.loss)
                }
                if store.hasSavedGame {
                    Button("Begin") { begin() }.buttonStyle(QuietButtonStyle()).disabled(countryCode.isEmpty)
                    Text("Replaces your saved game; you will be asked first.").font(.caption).foregroundStyle(Theme.ivoryFaint)
                } else {
                    Button("Begin") { begin() }.buttonStyle(GoldButtonStyle()).disabled(countryCode.isEmpty)
                }
            }
        }
    }

    /// Each story with the numbers the engine produces for the chosen country (a game is built and read, nothing is typed in).
    private var storyPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionLabel("Your story")
            let country = countries.first { $0.code == countryCode }
            let cur = country.map { Currency(country: $0, rates: ExchangeRates()) }
            ForEach(LifeStory.allCases, id: \.self) { s in
                Button { story = s } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: story == s ? "largecircle.fill.circle" : "circle").foregroundStyle(story == s ? Theme.gold : Theme.ivoryFaint)
                            Text(s.title.tidyMoney).font(.bodyText.weight(story == s ? .semibold : .regular)).foregroundStyle(story == s ? Theme.gold : Theme.ivory)
                        }
                        Text(s.tagline).font(.caption).foregroundStyle(Theme.ivoryMuted)
                        if let p = previews[s], let cur {
                            Text(storyFacts(p, cur)).font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if story.needsCity, let country {
                Picker("Where is the family café?", selection: Binding(get: { familyCityID.isEmpty ? (country.cities.first?.id ?? "") : familyCityID }, set: { familyCityID = $0 })) {
                    ForEach(country.cities) { Text($0.name).tag($0.id) }
                }.pickerStyle(.menu)
            }
        }
        .task(id: countryCode + "|" + familyCityID) { loadPreviews() }
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
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionLabel("Bring a save from the web game")
                Text("Your original file is kept untouched. The game is converted into a new native save" + (store.hasSavedGame ? ", which replaces the current one." : "."))
                    .font(.caption).foregroundStyle(Theme.ivoryMuted)
                HStack {
                    Button("Choose file") { showImporter = true }.buttonStyle(QuietButtonStyle())
                    Button("Paste text") { showPaste = true }.buttonStyle(QuietButtonStyle())
                }
            }
        }
    }
}
