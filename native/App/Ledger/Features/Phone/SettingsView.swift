import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: GameStore
    @State private var haptics = Haptics.enabled
    @State private var confirmQuit = false
    @State private var showImporter = false

    var body: some View {
        Form {
            Section("Feel") {
                Toggle("Haptic feedback", isOn: $haptics).onChange(of: haptics) { _, v in Haptics.enabled = v }
            }
            Section("Saving") {
                Button("Save now") { store.save(backup: true); store.show("Saved.", tone: "good") }
                if let text = store.exportText() {
                    ShareLink(item: text, subject: Text("Ledger save"), message: Text("Ledger save")) { Label("Export this game", systemImage: "square.and.arrow.up") }
                }
                Button("Import a save from the web game") { showImporter = true }
                Text("The game saves itself every day, and keeps a backup every month. Imports keep your original file untouched.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Back to the start screen", role: .destructive) { confirmQuit = true }
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            }
        }
        .scrollContentBackground(.hidden)
        .ledgerBackground()
        .navigationTitle("Settings")
        .confirmationDialog("Leave this game?", isPresented: $confirmQuit) {
            Button("Save and leave", role: .destructive) { store.quitToMenu() }
        } message: { Text("It is saved first. You can continue it from the start screen.") }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText, .json, .data]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8) { store.importLegacy(text: text) } else { store.errorText = "That file could not be read as text." }
        }
    }
}
