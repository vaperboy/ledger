import SwiftUI
import UIKit

struct InfoPopoverButton: View {
    var title: String
    var text: String
    var body: some View { InfoSheetButton(title: title, text: text) }
}

struct PopupPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonStyle(fullWidth: true).makeBody(configuration: configuration)
    }
}

struct PopupQuietButtonStyle: ButtonStyle {
    var passive: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonStyle(fullWidth: true, passive: passive).makeBody(configuration: configuration)
    }
}

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

struct LedgerField: View {
    @Environment(\.outsidePalette) private var P
    var placeholder: String
    @Binding var text: String
    var prefix: String? = nil
    var suffix: String? = nil
    var keyboard: UIKeyboardType = .default
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

typealias PopupTextInput = LedgerField
