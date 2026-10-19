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
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                group("Feel") {
                    row("hand.tap", "Haptic feedback") { Toggle("", isOn: $haptics).labelsHidden().tint(Theme.gold).onChange(of: haptics) { _, v in Haptics.enabled = v } }
                }
                group("How much I decide", footer: "Routine payroll is approved when the company can pay it, gaps in a team are filled, and small complaints are handled. Campaigns pause when cash would drop below the reserve. Big choices (hiring a manager, loans, sales, legal trouble) always come to your inbox.") {
                    row("checkmark.seal", "Approve routine payroll for me") { Toggle("", isOn: $policy.autoPayroll).labelsHidden().tint(Theme.gold) }
                    Divider().overlay(Theme.hairline)
                    row("person.badge.plus", "Replace people who leave", detail: "Recruits at the going rate when there is cash") { Toggle("", isOn: $policy.autoRehire).labelsHidden().tint(Theme.gold) }
                    Divider().overlay(Theme.hairline)
                    row("bubble.left.and.bubble.right", "Staff answer routine complaints", detail: "Serious ones still come to you") { Toggle("", isOn: $policy.autoComplaints).labelsHidden().tint(Theme.gold) }
                    Divider().overlay(Theme.hairline)
                    row("shield", "Cash reserve", detail: policy.reserveWeeks == 0 ? "None" : "\(policy.reserveWeeks.formatted()) weeks of costs") {
                        StepperPill(value: $policy.reserveWeeks, range: 0...8, step: 0.5)
                    }
                    Divider().overlay(Theme.hairline)
                    row("banknote", "Pay dividends automatically", detail: policy.autoDividendWeeks == 0 ? "Never" : "Above \(Int(policy.autoDividendWeeks)) weeks of spare cash") {
                        StepperPill(value: $policy.autoDividendWeeks, range: 0...26, step: 2)
                    }
                }
                group("Saving", footer: "The game saves itself every day, and keeps a backup every month. Imports keep your original file untouched.") {
                    Button { store.save(backup: true); store.show("Saved.", tone: "good"); Haptics.success() } label: { ListRow(symbol: "square.and.arrow.down", tint: Theme.ivoryMuted, title: "Save now", chevron: true) }.buttonStyle(.plain)
                    if let text = store.exportText() {
                        Divider().overlay(Theme.hairline)
                        ShareLink(item: text, subject: Text("Ledger save"), message: Text("Ledger save")) { ListRow(symbol: "square.and.arrow.up", tint: Theme.ivoryMuted, title: "Export this game", chevron: true) }.buttonStyle(.plain)
                    }
                    Divider().overlay(Theme.hairline)
                    Button { showImporter = true } label: { ListRow(symbol: "tray.and.arrow.down", tint: Theme.ivoryMuted, title: "Import a save from the web game", chevron: true) }.buttonStyle(.plain)
                }
                group("Game") {
                    Button { confirmQuit = true } label: { ListRow(symbol: "rectangle.portrait.and.arrow.right", tint: Theme.loss, title: "Back to the start screen", subtitle: "Saved first", chevron: true) }.buttonStyle(.plain)
                    Divider().overlay(Theme.hairline)
                    ListRow(symbol: "info.circle", tint: Theme.ivoryMuted, title: "Version", trailing: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
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

    private func group<Content: View>(_ title: String, footer: String = "", @ViewBuilder _ content: () -> Content) -> some View {
        let inner = content()
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title).font(.bodyText.weight(.semibold)).foregroundStyle(Theme.ivory).padding(.leading, 4)
            Card { VStack(alignment: .leading, spacing: Theme.Space.m) { inner } }
            if !footer.isEmpty { Text(footer).font(.caption).foregroundStyle(Theme.ivoryFaint).padding(.horizontal, 4) }
        }
    }

    private func row<Trailing: View>(_ symbol: String, _ title: String, detail: String = "", @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: Theme.Space.m) {
            IconBadge(symbol: symbol, tint: Theme.ivoryMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.bodyText.weight(.medium)).foregroundStyle(Theme.ivory)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(Theme.ivoryFaint) }
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

/// Minus and plus in one dark capsule.
struct StepperPill: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var body: some View {
        HStack(spacing: 0) {
            Button { value = max(range.lowerBound, value - step); Haptics.choose() } label: { Image(systemName: "minus").frame(width: 38, height: 32) }
                .disabled(value <= range.lowerBound)
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 18)
            Button { value = min(range.upperBound, value + step); Haptics.choose() } label: { Image(systemName: "plus").frame(width: 38, height: 32) }
                .disabled(value >= range.upperBound)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.ivory)
        .buttonStyle(.plain)
        .liquidGlassCapsule(interactive: true)
    }
}
