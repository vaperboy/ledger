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
    @ViewBuilder var content: () -> Content
    @State private var natural: CGFloat = -1
    @State private var forceShow = false

    var body: some View {
        let reported: Bool = natural >= 0
        let usable: Bool = natural >= 40
        let height: CGFloat = usable ? min(natural, maxHeight) : maxHeight
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
        .frame(height: height)
        .opacity(reported || forceShow ? 1 : 0)
        .onPreferenceChange(FitScrollHeightKey.self) { (h: CGFloat) in natural = h }
        .task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            forceShow = true
        }
    }
}
