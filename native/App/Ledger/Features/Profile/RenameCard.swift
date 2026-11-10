import SwiftUI

struct RenameCard<Status: View>: View {
    var placeholder: String
    @Binding var text: String
    var note: String
    var buttonTitle: String
    var enabled: Bool
    var capitalization: TextInputAutocapitalization = .never
    var identifier: String
    var onSubmit: () -> Void
    @ViewBuilder var status: () -> Status
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain).textStyle(.headline, weight: .regular)
                .textInputAutocapitalization(capitalization).autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { if enabled { onSubmit() } }
                .padding(.horizontal, Theme.Space.m).frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.inset))
                .accessibilityIdentifier(identifier + "-field")
            status()
            if !note.isEmpty { Text(note).textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true) }
            Button(buttonTitle) { Haptics.tap(); onSubmit() }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .disabled(!enabled)
                .accessibilityIdentifier(identifier + "-save")
        }
        .onAppear { focused = true }
    }
}

struct NameTapLabel<Content: View>: View {
    var label: String
    var tint: Color = Theme.inkSoft
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: Theme.Space.xs) {
                content()
                LedgerGlyph(glyph: Glyph.edit, size: 13, tint: tint)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label + ", rename")
        .accessibilityIdentifier("rename-" + label)
    }
}
