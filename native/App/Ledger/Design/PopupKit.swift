import SwiftUI

/// The three popup categories of the UI quality spec:
/// 1. Contextual popover (small, anchored to its control): `InfoPopoverButton` / `.contextPopover` below.
/// 2. Standard modal (sized to content, dimmed and locked background, x in the title row): `.centerSheet(isPresented:/item:)`.
/// 3. Confirmation (consequences first, destructive marked, never confirmed by a background tap): `PendingAction` with
///    `.confirmAction($pending)`, which shows `ConfirmPopup`.

/// A contextual popover: a small card with a short text, anchored near the control that opened it. It stays a popover on iPhone too.
private struct ContextPopoverModifier<Card: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder var card: () -> Card

    func body(content: Content) -> some View {
        content.popover(isPresented: $isPresented, arrowEdge: .top) {
            card()
                .frame(width: 250, alignment: .leading)
                .padding(14)
                .presentationCompactAdaptation(.popover)
        }
    }
}

extension View {
    /// Shows a small popover anchored to this view.
    func contextPopover<Card: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Card) -> some View {
        modifier(ContextPopoverModifier(isPresented: isPresented, card: content))
    }
}

/// The small round (i) button that opens a compact contextual popover with a short note.
struct InfoPopoverButton: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var text: String
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Text("i").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(P.inkSoft)
                .frame(width: 17, height: 17)
                .overlay(Circle().strokeBorder(P.inkSoft, lineWidth: 1))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("About " + title)
        .contextPopover(isPresented: $open) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(P.ink)
                Text(text).font(.system(size: 12.5)).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
