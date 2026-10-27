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
                    row(Glyph.phone, "Haptic feedback") { Toggle("", isOn: $haptics).labelsHidden().tint(Theme.gold).onChange(of: haptics) { _, v in Haptics.enabled = v; store.saved("haptic feedback " + (v ? "on" : "off")) } }
                }
                group("How much I decide", footer: "Routine payroll is approved when the company can pay it, gaps in a team are filled, and small complaints are handled. Campaigns pause when cash would drop below the reserve. Big choices (hiring a manager, loans, sales, legal trouble) always come to your inbox. Sales, closures, loans, dismissals and other irreversible steps always ask, whatever the size you set for spending.") {
                    row(Glyph.check, "Approve routine payroll for me") { Toggle("", isOn: $policy.autoPayroll).labelsHidden().tint(Theme.gold) }
                    CardLine()
                    row(Glyph.hire, "Replace people who leave", detail: "Recruits at the going rate when there is cash") { Toggle("", isOn: $policy.autoRehire).labelsHidden().tint(Theme.gold) }
                    CardLine()
                    row(Glyph.people, "Staff answer routine complaints", detail: "Serious ones still come to you") { Toggle("", isOn: $policy.autoComplaints).labelsHidden().tint(Theme.gold) }
                    CardLine()
                    row(Glyph.bank, "Cash reserve", detail: policy.reserveWeeks == 0 ? "None" : "\(policy.reserveWeeks.formatted()) weeks of costs") {
                        StepperPill(value: $policy.reserveWeeks, range: 0...8, step: 0.5)
                    }
                    CardLine()
                    row(Glyph.info, "Ask before spending", detail: askDetail) {
                        StepperPill(value: $askStep, range: 0...Double(ConfirmThreshold.sizes.count - 1), step: 1)
                    }
                    CardLine()
                    row(Glyph.invest, "Pay dividends automatically", detail: policy.autoDividendWeeks == 0 ? "Never" : "Above \(Int(policy.autoDividendWeeks)) weeks of spare cash") {
                        StepperPill(value: $policy.autoDividendWeeks, range: 0...26, step: 2)
                    }
                }
                group("Saving", footer: "The game saves itself every day, and keeps a backup every month. Imports keep your original file untouched.") {
                    Button { store.save(backup: true); store.show("Saved.", tone: "good"); Haptics.success() } label: { RowLine(glyph: Glyph.save, title: "Save now", chevron: true) }.buttonStyle(.plain)
                    if let text = store.exportText() {
                        CardLine()
                        ShareLink(item: text, subject: Text("Ledger save"), message: Text("Ledger save")) { RowLine(glyph: Glyph.share, title: "Export this game", chevron: true) }.buttonStyle(.plain)
                    }
                    CardLine()
                    Button { showImporter = true } label: { RowLine(glyph: Glyph.download, title: "Import a save from the web game", chevron: true) }.buttonStyle(.plain)
                }
                group("Game") {
                    Button { confirmQuit = true } label: { RowLine(glyph: Glyph.exit, tint: Theme.loss, title: "Back to the start screen", subtitle: "Saved first", chevron: true) }.buttonStyle(.plain)
                    CardLine()
                    RowLine(glyph: Glyph.info, title: "Version", trailing: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .ledgerBackground()
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
            CardSection(title) { VStack(alignment: .leading, spacing: 0) { inner } }
            if !footer.isEmpty { Text(footer).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).padding(.horizontal, 2).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func row<Trailing: View>(_ glyph: String, _ title: String, detail: String = "", @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: Theme.Space.m) {
            IconCircle(glyph: glyph, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14.5)).foregroundStyle(Theme.ivory)
                if !detail.isEmpty { Text(detail).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 8)
    }
}

/// Minus and plus in one grey-outlined box.
struct StepperPill: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var body: some View {
        HStack(spacing: 0) {
            Button { value = max(range.lowerBound, value - step); Haptics.choose() } label: { GlyphView(glyph: Glyph.minus, size: 14, weight: 2, tint: Theme.gold).frame(width: 40, height: 32) }
                .disabled(value <= range.lowerBound)
            Rectangle().fill(Theme.divider).frame(width: 1, height: 18)
            Button { value = min(range.upperBound, value + step); Haptics.choose() } label: { GlyphView(glyph: Glyph.hire, size: 14, weight: 2, tint: Theme.gold).frame(width: 40, height: 32) }
                .disabled(value >= range.upperBound)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.gold)
        .buttonStyle(.plain)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: 1))
    }
}
