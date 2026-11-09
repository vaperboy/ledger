import SwiftUI
import UniformTypeIdentifiers
import GameCore
import Simulation

/// Settings app: a plain list like the system Settings. Grouped rows with an icon in front, switches for on and off, popups for
/// a choice, chevrons for what opens something; no hero and no figures. Every control keeps its engine call and its "Saved" message.
struct SettingsView: View {
    /// Inside the Start screen's popup: the popup is the panel, so no background of its own.
    var embedded = false
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @Environment(AdCoordinator.self) private var ads
    @State private var haptics = Haptics.enabled
    @State private var sounds = SoundCues.enabled
    @State private var reminders: Bool = Reminders.enabled
    @State private var showImporter = false
    @State private var showPaste = false
    @State private var showRedeem = false
    @State private var giftCode = ""
    @State private var giftNote = ""
    @State private var pasted = ""
    @State private var askStep = ConfirmThreshold.step
    @State private var pending: PendingAction?
    @State private var showWardrobe = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                AccountSettingsGroup()
                feelGroup
                savingGroup
                proGroup
                if store.classicStartUnlocked { newGameGroup }
                gameGroup
            }
            .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.l)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .modifier(SettingsBackdrop(embedded: embedded))
        .onChange(of: askStep) { _, v in ConfirmThreshold.step = v; store.saved("asking before spending: " + askLabel(v).lowercased()) }
        .onChange(of: haptics) { _, v in Haptics.enabled = v; store.saved("haptic feedback " + (v ? "on" : "off")) }
        .onChange(of: sounds) { _, v in SoundCues.enabled = v; store.saved("sounds " + (v ? "on" : "off")) }
        .onChange(of: reminders) { _, v in Reminders.enabled = v; store.saved("reminders " + (v ? "on" : "off")) }
        .confirmAction($pending)
        .centerSheet(isPresented: $showWardrobe, title: "Wardrobe", size: .tall) { WardrobeView() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText, .json, .data]) { result in importPicked(result) }
        .centerSheet(isPresented: $showRedeem, title: "Redeem a code", size: .fit) {
            VStack(alignment: .leading, spacing: PopupSpace.block) {
                Text("Type the code from your gift. It opens the full game for the time it names.").popupText(.body)
                PopupTextInput(placeholder: "XXXX-XXXX-XXXX-XXXX", text: $giftCode, actionTitle: "Redeem", identifier: "redeem-code", hint: giftNote.hasPrefix("Unlocked") ? giftNote : nil, message: giftNote.isEmpty || giftNote.hasPrefix("Unlocked") ? nil : giftNote, onSubmit: redeemTapped, onAction: redeemTapped)
            }
        }
        .centerSheet(isPresented: $showPaste) {
            VStack(spacing: Theme.Space.m) {
                TextEditor(text: $pasted).popupText(.code).frame(height: 220)
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .top) { Hairline() }.overlay(alignment: .bottom) { Hairline() }
                Button(store.hasSavedGame ? "Import and replace" : "Import") { importPasted() }
                    .buttonStyle(QuietButtonStyle()).disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .centerSheetTitle("Paste save text")
        }
    }

    // MARK: Groups

    private var feelGroup: some View {
        group("Feel") {
            toggleRow(Glyph.phone, "Haptic feedback", isOn: $haptics)
            rule
            toggleRow(Glyph.phone, "Sounds", detail: "Short cues, silent when the ringer is muted", isOn: $sounds)
            rule
            toggleRow(Glyph.phone, "Reminders", isOn: $reminders)
            rule
            Button { store.customPickerOpen = true } label: {
                plainRow(store.customGlyph, "Custom tab", detail: "Long-press it in the tab bar to change it too", value: store.customTarget == nil ? "Not picked" : store.customTitle, chevron: true)
            }.buttonStyle(PressableStyle())
            .accessibilityIdentifier("settings-custom-tab")
        }
    }

    private var savingGroup: some View {
        group("Saves", footer: store.engine == nil ? "" : "Saved daily, with a monthly backup.") {
            if store.engine != nil {
                Button { store.save(backup: true); store.show("Saved.", tone: "good"); Haptics.success() } label: {
                    plainRow(Glyph.save, "Save now", chevron: true)
                }.buttonStyle(PressableStyle())
                if let text = store.exportText() {
                    rule
                    ShareLink(item: text, subject: Text("Ledger save"), message: Text("Ledger save")) {
                        plainRow(Glyph.share, "Export this game", chevron: true)
                    }.buttonStyle(PressableStyle())
                }
                if !embedded {
                    rule
                    NavigationLink {
                        PhonePageScroll(spacing: 14) { SaveSlotsView() }.appScreen(title: "Save slots", subtitle: "Named copies and cloud backup")
                    } label: {
                        plainRow(Glyph.save, "Save slots", detail: "Named copies of this game", chevron: true)
                    }.buttonStyle(PressableStyle())
                }
                rule
            }
            Button { showImporter = true } label: {
                plainRow(Glyph.download, "Import a save from the web game", chevron: true)
            }.buttonStyle(PressableStyle())
            rule
            Button { showPaste = true } label: {
                plainRow(Glyph.download, "Paste save text", chevron: true)
            }.buttonStyle(PressableStyle())
        }
    }

    /// The two older ways to begin, once the new-player ladder has reached them. Their own group in red, away from the saves: each
    /// replaces the running game (confirmed first).
    private var newGameGroup: some View {
        group("New game", footer: "Replaces the game you are playing; the copy before it is kept as a backup.") {
            Button { askNewGame(.loan) } label: {
                plainRow(Glyph.bank, "New game: start-up loan", detail: LifeStory.loan.tagline, tint: Theme.loss, chevron: true)
            }.buttonStyle(PressableStyle())
            rule
            Button { askNewGame(.heir) } label: {
                plainRow(Glyph.home, "New game: the family café", detail: LifeStory.heir.tagline, tint: Theme.loss, chevron: true)
            }.buttonStyle(PressableStyle())
        }
    }

    private func askNewGame(_ story: LifeStory) {
        let code: String = store.engine?.state.homeCountryCode ?? (Locale.current.region?.identifier == "GB" ? "UK" : (Locale.current.region?.identifier ?? "NO"))
        let who: String = store.engine?.state.player.name ?? ""
        pending = PendingAction(title: "Start a new game?", message: "It replaces the saved game. The copy before it is kept as a backup file, but the game will no longer open it.",
                                button: "Start new game", destructive: true) { store.newGame(name: who, countryCode: code, story: story); ads.resetForNewSave() }
    }

    /// Current plan, renewal date, manage, restore. Prices are never written here.
    private var proGroup: some View {
        group("Ledger Pro") {
            plainRow(Glyph.lock, "Plan", value: planName)
            if let end = ent.plusRenews {
                rule
                plainRow(Glyph.info, "Plus renews", value: end.formatted(date: .abbreviated, time: .omitted))
            }
            if !ent.isPlus {
                rule
                Button { ent.paywall = PaywallRequest(title: ent.ownsPro ? "Ledger Plus" : "Ledger Pro") } label: {
                    plainRow(Glyph.lock, ent.ownsPro ? "Get Ledger Plus" : "Get Ledger Pro", chevron: true)
                }.buttonStyle(PressableStyle())
                .accessibilityIdentifier("settings-ledger-pro")
            }
            if ent.isPlus {
                rule
                Button { Task { await ent.manageSubscription() } } label: { plainRow(Glyph.settings, "Manage subscription", chevron: true) }
                    .buttonStyle(PressableStyle())
            }
            rule
            Button { Haptics.tap(); showWardrobe = true } label: {
                plainRow(Glyph.lock, "Wardrobe", detail: "Badges and colours", value: ent.isPro ? "" : "Preview", chevron: true)
            }.buttonStyle(PressableStyle())
            .accessibilityIdentifier("settings-wardrobe")
            rule
            Button { Haptics.tap(); giftCode = ""; giftNote = ""; showRedeem = true } label: { plainRow(Glyph.lock, "Redeem a code", detail: "A gift code opens the full game", chevron: true) }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("settings-redeem")
            rule
            Button { Task { await ent.restore() } } label: { plainRow(Glyph.download, "Restore purchases", detail: ent.message ?? "", chevron: true) }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("settings-restore")
            #if DEBUG
            rule
            Button { cycleDebugPlan() } label: { plainRow(Glyph.info, "Debug plan", value: ent.debugMode.rawValue) }
                .buttonStyle(PressableStyle())
            #endif
        }
    }

    private func redeemTapped() {
        let trimmed: String = giftCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        giftNote = ent.redeem(trimmed)
        Haptics.tap()
    }

    private var planName: String {
        if ent.isPlus { return "Plus" }
        if ent.hasGift && !ent.ownsPro { return "Gift" }
        if ent.isFounder { return "Founder" }
        if ent.ownsPro { return "Pro" }
        return ent.hasPass ? "Pro for a day" : "Free"
    }

    #if DEBUG
    /// Force free, Pro or Plus for testing (debug builds only).
    private func cycleDebugPlan() {
        let all = Entitlements.DebugMode.allCases
        let next: Int = ((all.firstIndex(of: ent.debugMode) ?? 0) + 1) % all.count
        ent.setDebug(all[next])
    }
    #endif

    private var gameGroup: some View {
        group("Game") {
            if store.engine != nil {
                Button { store.quitToMenu() } label: {
                    plainRow(Glyph.exit, "Back to the start screen", detail: "Saved first", tint: Theme.loss, chevron: true)
                }.buttonStyle(PressableStyle())
                rule
            }
            plainRow(Glyph.info, "Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
        }
    }

    // MARK: Import

    /// Pasted text replaces the running game, so it is asked first (the file path does the same).
    private func importPasted() {
        let text: String = pasted
        showPaste = false
        pasted = ""
        guard store.hasSavedGame else { store.importLegacy(text: text); return }
        pending = PendingAction(title: "Import this save?", message: "It replaces the game you are playing now. The copy before it is kept as a backup file, but the game will no longer open it.",
                                button: "Import and replace", destructive: true) { store.importLegacy(text: text) }
    }

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

    /// "Always ask", or the size under which small spends are not asked, in the home currency.
    private func askLabel(_ step: Int) -> String {
        guard step > 0, let cur = store.engine?.homeCurrency else { return "Always ask" }
        return "Under " + cur.tidyShort(ConfirmThreshold.limit(step: step, currency: cur)).tidyMoney
    }

    // MARK: Rows

    /// The hairline between rows, starting under the title (past the icon).
    private var rule: some View { Hairline().padding(.leading, Theme.Icon.medium + Theme.Space.m) }

    private func group<Content: View>(_ title: String, footer: String = "", @ViewBuilder _ content: () -> Content) -> some View {
        let inner = content()
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title).capsLabel(Theme.inkFaint).padding(.horizontal, Theme.Space.m)
            Card(padding: 0) {
                VStack(alignment: .leading, spacing: 0) { inner }.padding(.horizontal, Theme.Space.m)
            }
            if !footer.isEmpty {
                Text(footer).textStyle(.caption).padding(.horizontal, Theme.Space.m).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func titleBlock(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).textStyle(.headline).fixedSize(horizontal: false, vertical: true)
            if !detail.isEmpty { Text(detail).textStyle(.caption).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func toggleRow(_ glyph: String, _ title: String, detail: String = "", isOn: Binding<Bool>) -> some View {
        HStack(spacing: Theme.Space.m) {
            LedgerGlyph(glyph: glyph, tint: Theme.accent)
            titleBlock(title, detail)
            Spacer(minLength: Theme.Space.s)
            LedgerSwitch(isOn: isOn)
        }
        .padding(.vertical, Theme.Space.s).frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    private func plainRow(_ glyph: String, _ title: String, detail: String = "", value: String = "", tint: Color = Theme.gold, chevron: Bool = false) -> some View {
        HStack(spacing: Theme.Space.m) {
            LedgerGlyph(glyph: glyph, tint: tint)
            titleBlock(title, detail)
            Spacer(minLength: Theme.Space.s)
            if !value.isEmpty { Text(value).textStyle(.body, tint: Theme.inkSoft, numeric: true) }
            if chevron { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint) }
        }
        .padding(.vertical, Theme.Space.s).frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The page background, except inside a popup that already paints the panel.
private struct SettingsBackdrop: ViewModifier {
    var embedded: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if embedded { content } else { content.ledgerBackground() }
    }
}
