import SwiftUI
import UniformTypeIdentifiers
import GameCore
import Simulation

struct SettingsView: View {
    @EnvironmentObject var store: GameStore
    @State private var haptics = Haptics.enabled
    @State private var confirmQuit = false
    @State private var showImporter = false
    @State private var policy = ManagementPolicy()

    var body: some View {
        Form {
            Section("Feel") {
                Toggle("Haptic feedback", isOn: $haptics).onChange(of: haptics) { _, v in Haptics.enabled = v }
            }
            Section {
                Toggle("Approve routine payroll for me", isOn: $policy.autoPayroll)
                Stepper(value: $policy.reserveWeeks, in: 0...8, step: 0.5) {
                    LabeledContent("Cash reserve", value: policy.reserveWeeks == 0 ? "none" : "\(policy.reserveWeeks.formatted()) weeks of costs")
                }
                Stepper(value: $policy.autoDividendWeeks, in: 0...26, step: 2) {
                    LabeledContent("Pay dividends from", value: policy.autoDividendWeeks == 0 ? "never" : "\(Int(policy.autoDividendWeeks)) weeks of spare cash")
                }
            } header: { Text("How much I decide") } footer: {
                Text("Routine payroll is approved when the company can pay it. Campaigns pause when cash would drop below the reserve. Big choices (hiring a manager, loans, sales, legal trouble) always come to your inbox.")
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
        .onAppear { policy = store.engine?.state.policy ?? ManagementPolicy() }
        .onChange(of: policy) { _, v in _ = store.act { $0.setPolicy(v) } }
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
