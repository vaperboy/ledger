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
    @State private var askStep = Double(ConfirmThreshold.step)
    @State private var pending: PendingAction?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                group("Feel") {
                    row("hand.tap", "Haptic feedback") { Toggle("", isOn: $haptics).labelsHidden().tint(Theme.gold).onChange(of: haptics) { _, v in Haptics.enabled = v; store.saved("haptic feedback " + (v ? "on" : "off")) } }
                }
                group("How much I decide", footer: "Routine payroll is approved when the company can pay it, gaps in a team are filled, and small complaints are handled. Campaigns pause when cash would drop below the reserve. Big choices (hiring a manager, loans, sales, legal trouble) always come to your inbox. Sales, closures, loans, dismissals and other irreversible steps always ask, whatever the size you set for spending.") {
                    row("checkmark.seal", "Approve routine payroll for me") { Toggle("", isOn: $policy.autoPayroll).labelsHidden().tint(Theme.gold) }
                    Hairline()
                    row("person.badge.plus", "Replace people who leave", detail: "Recruits at the going rate when there is cash") { Toggle("", isOn: $policy.autoRehire).labelsHidden().tint(Theme.gold) }
                    Hairline()
                    row("bubble.left.and.bubble.right", "Staff answer routine complaints", detail: "Serious ones still come to you") { Toggle("", isOn: $policy.autoComplaints).labelsHidden().tint(Theme.gold) }
                    Hairline()
                    row("shield", "Cash reserve", detail: policy.reserveWeeks == 0 ? "None" : "\(policy.reserveWeeks.formatted()) weeks of costs") {
                        StepperPill(value: $policy.reserveWeeks, range: 0...8, step: 0.5)
                    }
                    Hairline()
                    row("questionmark.circle", "Ask before spending", detail: askDetail) {
                        StepperPill(value: $askStep, range: 0...Double(ConfirmThreshold.sizes.count - 1), step: 1)
                    }
                    Hairline()
                    row("banknote", "Pay dividends automatically", detail: policy.autoDividendWeeks == 0 ? "Never" : "Above \(Int(policy.autoDividendWeeks)) weeks of spare cash") {
                        StepperPill(value: $policy.autoDividendWeeks, range: 0...26, step: 2)
                    }
                }
                group("Saving", footer: "The game saves itself every day, and keeps a backup every month. Imports keep your original file untouched.") {
                    Button { store.save(backup: true); store.show("Saved.", tone: "good"); Haptics.success() } label: { ListRow(symbol: "square.and.arrow.down", tint: Theme.ivoryMuted, title: "Save now", chevron: true).padding(.vertical, 4) }.buttonStyle(.plain)
                    if let text = store.exportText() {
                        Hairline()
                        ShareLink(item: text, subject: Text("Ledger save"), message: Text("Ledger save")) { ListRow(symbol: "square.and.arrow.up", tint: Theme.ivoryMuted, title: "Export this game", chevron: true) }.buttonStyle(.plain)
                    }
                    Hairline()
                    Button { showImporter = true } label: { ListRow(symbol: "tray.and.arrow.down", tint: Theme.ivoryMuted, title: "Import a save from the web game", chevron: true) }.buttonStyle(.plain)
                }
                group("Game") {
                    Button { confirmQuit = true } label: { ListRow(symbol: "rectangle.portrait.and.arrow.right", tint: Theme.loss, title: "Back to the start screen", subtitle: "Saved first", chevron: true) }.buttonStyle(.plain)
                    Hairline()
                    ListRow(symbol: "info.circle", tint: Theme.ivoryMuted, title: "Version", trailing: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .ledgerBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { policy = store.engine?.state.policy ?? ManagementPolicy() }
        .onChange(of: askStep) { _, v in ConfirmThreshold.step = Int(v); store.saved("asking before spending: " + askDetail.lowercased()) }
        .onChange(of: policy) { old, v in
            // Loading the page sets `policy` from the game; only a real change by the player is saved and reported.
            guard let current = store.engine?.state.policy, current != v else { return }
            store.act { $0.setPolicy(v) }
            store.saved(policyChange(from: old, to: v))
        }
        .confirmAction($pending)
        .confirmationDialog("Leave this game?", isPresented: $confirmQuit) {
            Button("Save and leave", role: .destructive) { store.quitToMenu() }
        } message: { Text("It is saved first. You can continue it from the start screen.") }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText, .json, .data]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { store.errorText = "That file could not be read as text."; return }
            // Ask once the file picker has gone: an import replaces the game you are playing.
            DispatchQueue.main.async {
                pending = PendingAction(title: "Import this save?", message: "It replaces the game you are playing now. The copy before it is kept as a backup file, but the game will no longer open it.",
                                        button: "Import and replace", destructive: true) { store.importLegacy(text: text) }
            }
        }
    }

    /// What the player just changed, in words, for the "Saved" message.
    private func policyChange(from old: ManagementPolicy, to v: ManagementPolicy) -> String {
        if old.autoPayroll != v.autoPayroll { return "routine payroll " + (v.autoPayroll ? "approved for you" : "comes to you") }
        if old.autoRehire != v.autoRehire { return "replacing people who leave is " + (v.autoRehire ? "on" : "off") }
        if old.autoComplaints != v.autoComplaints { return "staff " + (v.autoComplaints ? "answer" : "no longer answer") + " routine complaints" }
        if old.reserveWeeks != v.reserveWeeks { return v.reserveWeeks == 0 ? "no cash reserve" : "cash reserve of \(v.reserveWeeks.formatted()) weeks of costs" }
        if old.autoDividendWeeks != v.autoDividendWeeks { return v.autoDividendWeeks == 0 ? "no automatic dividends" : "dividends above \(Int(v.autoDividendWeeks)) weeks of spare cash" }
        return "how much you decide"
    }

    private var askDetail: String {
        let step = Int(askStep)
        guard step > 0, let cur = store.engine?.homeCurrency else { return "Always ask" }
        return "Not for small spends under \(cur.tidyShort(ConfirmThreshold.limit(step: step, currency: cur)).tidyMoney); the result is still reported"
    }

    private func group<Content: View>(_ title: String, footer: String = "", @ViewBuilder _ content: () -> Content) -> some View {
        let inner = content()
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            LedgerSection(title) { VStack(alignment: .leading, spacing: 0) { inner } }
            if !footer.isEmpty { Text(footer).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func row<Trailing: View>(_ symbol: String, _ title: String, detail: String = "", @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14.5)).foregroundStyle(Theme.ivory)
                if !detail.isEmpty { Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 10)
    }
}

/// Minus and plus in one hairline capsule.
struct StepperPill: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var body: some View {
        HStack(spacing: 0) {
            Button { value = max(range.lowerBound, value - step); Haptics.choose() } label: { Image(systemName: "minus").frame(width: 38, height: 30) }
                .disabled(value <= range.lowerBound)
            Rectangle().fill(Theme.hairline).frame(width: 0.5, height: 16)
            Button { value = min(range.upperBound, value + step); Haptics.choose() } label: { Image(systemName: "plus").frame(width: 38, height: 30) }
                .disabled(value >= range.upperBound)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.gold)
        .buttonStyle(.plain)
        .overlay(Capsule().strokeBorder(Theme.ivory.opacity(0.2), lineWidth: 0.75))
    }
}
