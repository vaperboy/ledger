import SwiftUI

/// First step of a new game: build a half-body avatar and pick a unique username.
struct AvatarSetupStep: View {
    enum Part: String, CaseIterable, Identifiable {
        case face, hair, outfit
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var onDone: () -> Void
    var onBack: () -> Void

    @Environment(OnlineSession.self) private var online
    @StateObject private var checker = UsernameChecker()
    @ObservedObject private var local = ProfileLocal.shared
    @State private var look = AvatarLook()
    @State private var username = ""
    @State private var part: Part = .face
    @State private var note = ""
    @FocusState private var typing: Bool

    private var nameOK: Bool { checker.canUse || (checker.verdict == .unchanged && ProfileRules.problem(with: username) == nil) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            AppHeader(title: "Create your look", subtitle: "Before your first company", onBack: onBack)
                .padding(.top, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    preview
                    SegmentedPill(items: Part.allCases, title: { (p: Part) -> String in p.title }, selection: $part, identifier: { (p: Part) -> String in "avatar-part-" + p.rawValue })
                    picker
                    if !note.isEmpty { Text(note).textStyle(.caption, tint: Theme.accent) }
                    usernameField
                }
                .padding(.bottom, Theme.Space.l)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            Button("Continue") { Haptics.tap(); finish() }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .disabled(!nameOK)
                .accessibilityIdentifier("avatar-continue")
        }
        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.page.ignoresSafeArea())
        .onAppear { username = local.name; look = local.avatar }
    }

    private var preview: some View {
        HStack {
            Spacer(minLength: 0)
            HalfBodyAvatar(look: look, width: 170)
                .padding(.top, Theme.Space.s)
                .frame(maxWidth: 220)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surfaceRaised))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var picker: some View {
        switch part {
        case .face: AvatarFacePicker(look: look, onChange: { (l: AvatarLook) in look = l; note = "" })
        case .hair: AvatarHairPicker(look: look, onChange: { (l: AvatarLook) in look = l; note = "" })
        case .outfit:
            AvatarOutfitPicker(look: look, onPick: { (o: OutfitDef, open: Bool) in
                if open { look.outfit = o.id; note = "" } else { note = o.title + " unlocks at level \(o.level)." }
            })
        }
    }

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Username").textStyle(.label, tint: Theme.inkFaint)
            TextField("Username", text: $username)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($typing)
                .submitLabel(.done)
                .onSubmit { typing = false }
                .textStyle(.figure)
                .padding(.vertical, Theme.Space.s)
                .overlay(alignment: .bottom) { Hairline() }
                .onChange(of: username) { _, new in checker.check(new, current: local.name, online: online) }
                .accessibilityIdentifier("avatar-username")
            UsernameStatusLine(checker: checker)
            Text("At least 3 letters. Other players see it, and no one else can use it.").textStyle(.caption, tint: Theme.inkSoft)
        }
    }

    private func finish() {
        typing = false
        local.setAvatar(look)
        let name: String = ProfileRules.clean(username)
        if ProfileRules.problem(with: name) == nil, name != local.name { local.setName(name) }
        onDone()
    }
}
