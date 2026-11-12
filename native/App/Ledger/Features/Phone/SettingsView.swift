import SwiftUI
import GameCore
import Simulation

struct SettingsView: View {
    var embedded = false
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @Environment(OnlineSession.self) private var online
    @State private var haptics = Haptics.enabled
    @State private var sounds = SoundCues.enabled
    @State private var reminders: Bool = Reminders.enabled
    @State private var pushOn: Set<PushCategory> = Set(PushAlerts.enabledCategories)
    @State private var askStep = ConfirmThreshold.step
    @State private var pending: PendingAction?
    @State private var showAdmin = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                AccountSettingsGroup()
                lookGroup
                feelGroup
                alertsGroup
                if store.engine != nil { helpGroup }
                if store.engine != nil && !embedded { savingGroup }
                proGroup
                gameGroup
                DeleteAccountGroup()
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
        .navigationDestination(isPresented: $showAdmin) { AdminAccessView() }
    }

    private var lookGroup: some View {
        group("Profile") {
            if store.engine != nil {
                Button { store.openProfile() } label: { plainRow(Glyph.person, "Profile", detail: "Your name, look, friend code and who can see you", chevron: true) }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("settings-profile")
            }
        }
    }

    private var feelGroup: some View {
        group("Feel") {
            toggleRow(Glyph.phone, "Haptic feedback", isOn: $haptics)
            rule
            toggleRow(Glyph.phone, "Sounds", detail: "Short cues, silent when the ringer is muted", isOn: $sounds)
            if store.engine != nil {
                rule
                Button { store.customPickerOpen = true } label: {
                    plainRow(store.customGlyph, "Custom tab", detail: "Store, Market or any app or company. Long-press it in the tab bar too.", value: store.customTitle, chevron: true)
                }.buttonStyle(PressableStyle())
                .accessibilityIdentifier("settings-custom-tab")
            }
        }
    }

    private var alertsGroup: some View {
        group("Alerts", footer: "Push alerts arrive only on builds signed for notifications.") {
            toggleRow(Glyph.phone, "Reminders", isOn: $reminders)
            ForEach(PushCategory.allCases) { (c: PushCategory) in
                rule
                toggleRow(Glyph.phone, c.title, detail: c.detail, isOn: pushBinding(c))
            }
        }
    }

    private func pushBinding(_ c: PushCategory) -> Binding<Bool> {
        Binding<Bool>(get: { pushOn.contains(c) }, set: { (v: Bool) in
            if v { pushOn.insert(c) } else { pushOn.remove(c) }
            PushAlerts.setEnabled(c, v)
            store.saved(c.title.lowercased() + " alerts " + (v ? "on" : "off"))
            Task { await PushAlerts.sync(service: online.service, signedIn: online.isSignedIn) }
        })
    }

    private var helpGroup: some View {
        group("Help") {
            Button { askReplay() } label: {
                plainRow(Glyph.info, "Replay the tutorial", detail: "\(Tutorial.stepCount) short steps on your own company", chevron: true)
            }.buttonStyle(PressableStyle())
            .accessibilityIdentifier("settings-replay-tutorial")
        }
    }

    private func askReplay() {
        pending = PendingAction(title: "Replay the tutorial?", message: "The \(Tutorial.stepCount) steps start again from the first one. Nothing in your game changes.",
                                button: "Replay") {
            store.tutorialReplay()
            store.show("The tutorial starts again.", tone: "good")
        }
    }

    private var savingGroup: some View {
        group("Saves", footer: "The game saves itself after every day.") {
            NavigationLink {
                PhonePageScroll(spacing: 14) { SaveSlotsView() }.appScreen(title: "Save slots", subtitle: "Your careers and cloud backup")
            } label: {
                plainRow(Glyph.save, "Save slots", detail: "Each slot is its own career", chevron: true)
            }.buttonStyle(PressableStyle())
        }
    }

    private var proGroup: some View {
        group("Ledger Pro") {
            plainRow(Glyph.lock, "Plan", value: planName)
            if let end = ent.plusRenews {
                rule
                plainRow(Glyph.info, "Plus renews", value: end.formatted(date: .abbreviated, time: .omitted))
            }
            if ent.isPlus {
                rule
                Button { Task { await ent.manageSubscription() } } label: { plainRow(Glyph.settings, "Manage subscription", chevron: true) }
                    .buttonStyle(PressableStyle())
            }
            #if DEBUG
            rule
            Button { cycleDebugPlan() } label: { plainRow(Glyph.info, "Debug plan", value: ent.debugMode.rawValue) }
                .buttonStyle(PressableStyle())
            #endif
        }
    }

    private var planName: String {
        if ent.isPlus { return "Plus" }
        if ent.isFounder { return "Founder" }
        if ent.ownsPro { return "Pro" }
        return ent.hasPass ? "Pro for a day" : "Free"
    }

    #if DEBUG
    private func cycleDebugPlan() {
        let all = Entitlements.DebugMode.allCases
        let next: Int = ((all.firstIndex(of: ent.debugMode) ?? 0) + 1) % all.count
        ent.setDebug(all[next])
    }
    #endif

    private var gameGroup: some View {
        group("Game") {
            if store.engine != nil || online.isSignedIn {
                Button { askLeave() } label: {
                    plainRow(Glyph.exit, leaveTitle, detail: store.engine != nil ? "Saved first" : "", tint: Theme.loss, chevron: true)
                }.buttonStyle(PressableStyle())
                .accessibilityIdentifier("settings-sign-out")
                rule
            }
            plainRow(Glyph.info, "Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                .onLongPressGesture(minimumDuration: 1.5) { if !embedded { Haptics.tap(); showAdmin = true } }
        }
    }

    private var leaveTitle: String {
        if !online.isSignedIn { return "Back to the start menu" }
        return store.engine != nil ? "Sign out and back to the start menu" : "Sign out"
    }

    private func askLeave() {
        let signedIn: Bool = online.isSignedIn
        let inGame: Bool = store.engine != nil
        if !signedIn { store.quitToMenu(); return }
        pending = PendingAction.online(title: "Sign out?",
                                       effect: inGame ? "you become a guest on this device and return to the start menu. Your game is saved first and stays on this device."
                                                      : "you become a guest on this device. Your game stays; your profile and progress wait for you to sign in again.",
                                       button: "Sign out", tone: .info, icon: "rectangle.portrait.and.arrow.right") {
            Task {
                await online.signOut()
                if inGame { store.quitToMenu() }
            }
        }
    }

    private func askLabel(_ step: Int) -> String {
        guard step > 0, let cur = store.engine?.homeCurrency else { return "Always ask" }
        return "Under " + cur.tidyShort(ConfirmThreshold.limit(step: step, currency: cur)).tidyMoney
    }

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

private struct SettingsBackdrop: ViewModifier {
    var embedded: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if embedded { content } else { content.ledgerBackground() }
    }
}
