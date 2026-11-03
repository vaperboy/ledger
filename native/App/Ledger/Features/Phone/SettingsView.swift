import SwiftUI
import UniformTypeIdentifiers
import GameCore
import Simulation

/// Settings app: a plain list like the system Settings. Grouped rows with a round icon in front, switches for on and off, popups for
/// a choice, chevrons for what opens something; no hero and no figures. Every control keeps its engine call and its "Saved" message.
struct SettingsView: View {
    @EnvironmentObject var store: GameStore
    @State private var haptics = Haptics.enabled
    @State private var showImporter = false
    @State private var policy = ManagementPolicy()
    @State private var askStep = ConfirmThreshold.step
    @State private var pending: PendingAction?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                feelGroup
                savingGroup
                gameGroup
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 20)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .ledgerBackground()
        .onAppear { policy = store.engine?.state.policy ?? ManagementPolicy() }
        .onChange(of: askStep) { _, v in ConfirmThreshold.step = v; store.saved("asking before spending: " + askLabel(v).lowercased()) }
        .onChange(of: haptics) { _, v in Haptics.enabled = v; store.saved("haptic feedback " + (v ? "on" : "off")) }
        .onChange(of: policy) { old, v in
            // Loading the page sets `policy` from the game; only a real change by the player is saved and reported.
            guard let current = store.engine?.state.policy, current != v else { return }
            store.act { $0.setPolicy(v) }
            store.saved(policyChange(from: old, to: v))
        }
        .confirmAction($pending)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText, .json, .data]) { result in importPicked(result) }
    }

    // MARK: Groups

    private var feelGroup: some View {
        group("Feel") {
            toggleRow(Glyph.phone, "Haptic feedback", isOn: $haptics)
            rule
            Button { store.customPickerOpen = true } label: {
                plainRow(store.customGlyph, "Custom tab", detail: "Long-press it in the tab bar to change it too", value: store.customTitle, chevron: true)
            }.buttonStyle(PressableStyle())
            .accessibilityIdentifier("settings-custom-tab")
        }
    }

    private var savingGroup: some View {
        group("Saving", footer: "Saved daily, with a monthly backup.") {
            Button { store.save(backup: true); store.show("Saved.", tone: "good"); Haptics.success() } label: {
                plainRow(Glyph.save, "Save now", chevron: true)
            }.buttonStyle(PressableStyle())
            if let text = store.exportText() {
                rule
                ShareLink(item: text, subject: Text("Ledger save"), message: Text("Ledger save")) {
                    plainRow(Glyph.share, "Export this game", chevron: true)
                }.buttonStyle(PressableStyle())
            }
            rule
            Button { showImporter = true } label: {
                plainRow(Glyph.download, "Import a save from the web game", chevron: true)
            }.buttonStyle(PressableStyle())
        }
    }

    private var gameGroup: some View {
        group("Game") {
            Button { store.quitToMenu() } label: {
                plainRow(Glyph.exit, "Back to the start screen", detail: "Saved first", tint: Theme.loss, chevron: true)
            }.buttonStyle(PressableStyle())
            rule
            plainRow(Glyph.info, "Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
        }
    }

    // MARK: Import

    private func importPicked(_ result: Result<URL, Error>) {
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

    // MARK: Words

    /// What the player just changed, in words, for the "Saved" message.
    private func policyChange(from old: ManagementPolicy, to v: ManagementPolicy) -> String {
        if old.autoPayroll != v.autoPayroll { return "routine payroll " + (v.autoPayroll ? "approved for you" : "comes to you") }
        if old.autoRehire != v.autoRehire { return "replacing people who leave is " + (v.autoRehire ? "on" : "off") }
        if old.autoComplaints != v.autoComplaints { return "staff " + (v.autoComplaints ? "answer" : "no longer answer") + " routine complaints" }
        if old.reserveWeeks != v.reserveWeeks { return v.reserveWeeks == 0 ? "no cash reserve" : "cash reserve of \(v.reserveWeeks.formatted()) weeks of costs" }
        if old.autoDividendWeeks != v.autoDividendWeeks { return v.autoDividendWeeks == 0 ? "no automatic dividends" : "dividends above \(Int(v.autoDividendWeeks)) weeks of spare cash" }
        return "how much you decide"
    }

    /// "Always ask", or the size under which small spends are not asked, in the home currency.
    private func askLabel(_ step: Int) -> String {
        guard step > 0, let cur = store.engine?.homeCurrency else { return "Always ask" }
        return "Under " + cur.tidyShort(ConfirmThreshold.limit(step: step, currency: cur)).tidyMoney
    }

    // MARK: Rows

    private var rule: some View { Rectangle().fill(Theme.divider).frame(height: 1).padding(.leading, 44) }

    private func group<Content: View>(_ title: String, footer: String = "", @ViewBuilder _ content: () -> Content) -> some View {
        let inner = content()
        return VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 12, weight: .medium)).tracking(0.6).foregroundStyle(Theme.ivoryFaint).padding(.horizontal, 14)
            Card(padding: 0) {
                VStack(alignment: .leading, spacing: 0) { inner }.padding(.horizontal, 14)
            }
            if !footer.isEmpty {
                Text(footer).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).padding(.horizontal, 14).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func titleBlock(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
            if !detail.isEmpty { Text(detail).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func toggleRow(_ glyph: String, _ title: String, detail: String = "", isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            IconCircle(glyph: glyph, size: 32)
            titleBlock(title, detail)
            Spacer(minLength: 8)
            LedgerSwitch(isOn: isOn)
        }
        .padding(.vertical, 9).frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    private func plainRow(_ glyph: String, _ title: String, detail: String = "", value: String = "", tint: Color = Theme.gold, chevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            IconCircle(glyph: glyph, size: 32, tint: tint)
            titleBlock(title, detail)
            Spacer(minLength: 8)
            if !value.isEmpty { Text(value).font(.system(size: 14).monospacedDigit()).foregroundStyle(Theme.ivoryMuted) }
            if chevron { GlyphView(glyph: Glyph.chevron, size: 12, weight: 1.8, tint: Theme.ivoryDim) }
        }
        .padding(.vertical, 9).frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
