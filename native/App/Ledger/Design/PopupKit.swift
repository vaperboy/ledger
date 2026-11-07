import SwiftUI
import UIKit

/// The three popup categories of the UI quality spec:
/// 1. Short note behind an (i): `InfoPopoverButton` / `InfoSheetButton`, a compact centred popup (no system popover).
/// 2. Standard modal (sized to content, dimmed and locked background, x in the title row): `.centerSheet(isPresented:/item:)`.
/// 3. Confirmation (consequences first, destructive marked, never confirmed by a background tap): `PendingAction` with
///    `.confirmAction($pending)`, which shows `ConfirmPopup`.

/// The small round (i) button for a short note; it opens the same centred popup as `InfoSheetButton`.
struct InfoPopoverButton: View {
    var title: String
    var text: String
    var body: some View { InfoSheetButton(title: title, text: text) }
}


/// Height of the measured content of a `FitScroll` (-1 until measured, so even a measured 0 is reported).
private struct FitScrollHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = -1
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// A scroll area that is exactly as high as its content, up to `maxHeight`; only taller content scrolls (vertically). Unlike
/// `.frame(maxHeight:)` it never stretches to the maximum, so a popup around it never shows empty space. Content that measures almost
/// nothing (it fills space by itself) gets `maxHeight`; nothing stays hidden: after a short moment it is shown whatever the measurement.
struct FitScroll<Content: View>: View {
    var maxHeight: CGFloat
    /// Called with the measured content height whenever it changes (a popup frame picks its size class from it).
    var onMeasure: ((CGFloat) -> Void)? = nil
    /// Height used while the content has not measured (nil: `maxHeight`). Popups pass a small value so nothing is ever stretched to the maximum.
    var unmeasured: CGFloat? = nil
    @ViewBuilder var content: () -> Content
    @State private var natural: CGFloat = -1
    @State private var forceShow = false
    @State private var armed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let reported: Bool = natural >= 0
        let usable: Bool = natural > 0.5
        let height: CGFloat = usable ? min(natural, maxHeight) : (unmeasured ?? maxHeight)
        ScrollView(.vertical) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { (g: GeometryProxy) in
                        Color.clear.preference(key: FitScrollHeightKey.self, value: g.size.height)
                    }
                )
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .frame(height: height)
        .animation(armed ? Motion.size(reduceMotion) : nil, value: height)
        .opacity(reported || forceShow ? 1 : 0)
        .onPreferenceChange(FitScrollHeightKey.self) { (h: CGFloat) in
            natural = h
            if h > 0.5 {
                onMeasure?(h)
                if !armed { DispatchQueue.main.async { armed = true } }
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            forceShow = true
        }
    }
}

// MARK: Popup buttons

/// A small press-in with a spring, so a popup button answers the finger at once (none under Reduce Motion).
struct PopupPressFeedback: ViewModifier {
    var pressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .animation(Motion.tap(reduceMotion), value: pressed)
    }
}

/// The filled button of a popup with a SOLE action (Continue, OK, Claim): the primary button at full width. Never beside other options.
struct PopupPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonStyle(fullWidth: true).makeBody(configuration: configuration)
    }
}

/// An option of a popup: the secondary button at full width, the same for every option. A passive option
/// (Decide later, Postpone, Later, Not now, Skip, Remind me) is drawn lightly grayed.
struct PopupQuietButtonStyle: ButtonStyle {
    var passive: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonStyle(fullWidth: true, passive: passive).makeBody(configuration: configuration)
    }
}

/// One option button of a popup. Every option is the same equal outline; `highlighted` (filled champagne) is only for a SOLE action
/// (Continue, OK, Claim). `destructive` is kept for call sites but changes nothing: irreversible actions are explained in text.
struct PopupOptionButton: View {
    var title: String
    var highlighted: Bool = false
    var destructive: Bool = false
    var identifier: String = ""
    var action: () -> Void

    static func isPassive(_ title: String) -> Bool {
        let t: String = title.trimmingCharacters(in: .whitespaces).lowercased()
        let names: [String] = ["decide later", "postpone", "later", "not now", "skip", "remind me"]
        for n in names where t == n || t.hasPrefix(n + " ") { return true }
        return false
    }

    var body: some View {
        let go: () -> Void = { Haptics.play(.tap); action() }
        if highlighted {
            Button(action: go) { Text(title) }.buttonStyle(PopupPrimaryButtonStyle()).accessibilityIdentifier(identifier)
        } else {
            Button(action: go) { Text(title) }.buttonStyle(PopupQuietButtonStyle(passive: PopupOptionButton.isPassive(title))).accessibilityIdentifier(identifier)
        }
    }
}

/// The one text input of the game (pages and popups): an inset field with no outline (a focus ring while typing), an optional prefix
/// (a currency mark) and suffix (a unit), an optional action button inside the field (Set, Done) that also puts the keyboard away, and a
/// validation or hint line below. The action sits in the field itself, so a decimal pad (no return key) can always be closed, also inside
/// a popup overlay where a keyboard toolbar does not show.
struct LedgerField: View {
    @Environment(\.outsidePalette) private var P
    var placeholder: String
    @Binding var text: String
    var prefix: String? = nil
    var suffix: String? = nil
    var keyboard: UIKeyboardType = .default
    /// Title of the in-field button; a decimal pad shows "Done" while focused when none is given.
    var actionTitle: String? = nil
    var actionEnabled = true
    var identifier = ""
    var hint: String? = nil
    var message: String? = nil
    var onFocusChange: (Bool) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    var onAction: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PopupSpace.tight) {
            HStack(spacing: Theme.Space.s) {
                if let p = prefix { Text(p).popupText(.rowLabel) }
                TextField(placeholder, text: $text)
                    .keyboardType(keyboard).focused($focused)
                    .textStyle(.headline, numeric: true)
                    .accessibilityIdentifier(identifier)
                    .onSubmit { focused = false; onSubmit() }
                if let u = suffix { Text(u).popupText(.caption) }
                accessory
            }
            .padding(.horizontal, PopupSpace.block).frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: PopupRadius.control, style: .continuous).fill(P.inset))
            .overlay(RoundedRectangle(cornerRadius: PopupRadius.control, style: .continuous).strokeBorder(focused ? P.focus : Color.clear, lineWidth: 1))
            if let h = hint { Text(h).popupText(.caption) }
            if let m = message { Text(m).popupText(.risk) }
        }
        .onChange(of: focused) { _, f in onFocusChange(f) }
    }

    @ViewBuilder private var accessory: some View {
        if let t = actionTitle {
            Button(t) { Haptics.play(.tap); focused = false; onAction() }
                .buttonStyle(TertiaryButtonStyle(size: .compact))
                .disabled(!actionEnabled).accessibilityIdentifier(identifier + "-action")
        } else if focused && keyboard == .decimalPad {
            Button("Done") { focused = false }
                .buttonStyle(TertiaryButtonStyle(size: .compact))
        }
    }
}

/// The older name of `LedgerField`.
typealias PopupTextInput = LedgerField
