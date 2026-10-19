import SwiftUI
import UniformTypeIdentifiers
import Countries

/// First screen: continue, start a new game, or bring a save over from the HTML game.
struct StartView: View {
    @EnvironmentObject var store: GameStore
    @State private var name = ""
    @State private var countryCode = ""
    @State private var showImporter = false
    @State private var showPaste = false
    @State private var pasted = ""
    private let countries: [Country] = ((try? CountryBook.bundled().countries) ?? []).sorted { $0.name < $1.name }

    /// The country of the device's region if the game has it; otherwise the first in the list. No country is the built-in default.
    private var initialCountry: String {
        let region = Locale.current.region?.identifier ?? ""
        let code = region == "GB" ? "UK" : region
        return countries.first { $0.code == code }?.code ?? countries.first?.code ?? ""
    }

    private func begin() { store.newGame(name: name.trimmingCharacters(in: .whitespaces), countryCode: countryCode) }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.xl) {
                VStack(spacing: 6) {
                    Text("LEDGER").font(.system(size: 40, weight: .semibold, design: .default)).tracking(8).foregroundStyle(Theme.gold)
                    Text("Business tycoon simulator").font(.label).tracking(1.5).foregroundStyle(Theme.ivoryFaint)
                }.padding(.top, 48)

                if store.hasSavedGame {
                    Button { store.loadCurrent() } label: { Text("Continue") }.buttonStyle(GoldButtonStyle())
                }

                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        SectionLabel("New game")
                        TextField("Your name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.words)
                        Picker("Home country", selection: $countryCode) {
                            ForEach(countries) { c in Text("\(c.flag) \(c.name)").tag(c.code) }
                        }
                        .pickerStyle(.menu)
                        if let c = countries.first(where: { $0.code == countryCode }) {
                            Text("Currency: \(c.currencyCode)").font(.caption).foregroundStyle(Theme.ivoryMuted)
                        }
                        if store.hasSavedGame {
                            Button("Begin") { begin() }.buttonStyle(QuietButtonStyle())
                        } else {
                            Button("Begin") { begin() }.buttonStyle(GoldButtonStyle())
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        SectionLabel("Bring a save from the web game")
                        Text("Your original file is kept untouched. The game is converted into a new native save.")
                            .font(.caption).foregroundStyle(Theme.ivoryMuted)
                        HStack {
                            Button("Choose file") { showImporter = true }.buttonStyle(QuietButtonStyle())
                            Button("Paste text") { showPaste = true }.buttonStyle(QuietButtonStyle())
                        }
                    }
                }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .ledgerBackground()
        .onAppear { if countryCode.isEmpty { countryCode = initialCountry } }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText, .json, .data]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8) { store.importLegacy(text: text) }
            else { store.errorText = "That file could not be read as text." }
        }
        .sheet(isPresented: $showPaste) {
            NavigationStack {
                VStack(spacing: Theme.Space.m) {
                    TextEditor(text: $pasted).font(.system(.caption, design: .monospaced)).frame(minHeight: 220)
                        .scrollContentBackground(.hidden).background(Theme.leather).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
                    Button("Import") { showPaste = false; store.importLegacy(text: pasted); pasted = "" }.buttonStyle(GoldButtonStyle()).disabled(pasted.isEmpty)
                }
                .padding().ledgerBackground()
                .navigationTitle("Paste save text").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showPaste = false } } }
            }
        }
    }
}
