import SwiftUI
import UIKit

/// A content view can call `.centerSheetLocked()` so a tap outside the popup does not close it (only its own buttons do).
private struct CenterSheetLockKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// The measured height of the popup content, so the card can size to it.
private struct CenterSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Makes the presented controller's views transparent, so the dimmed backdrop of the popup shows the screen below.
private struct ClearCoverBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { ClearProbe() }
    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class ClearProbe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                var v: UIView? = self
                while let x = v, !(x is UIWindow) {
                    x.backgroundColor = .clear
                    v = x.superview
                }
            }
        }
    }
}

/// The centred popup card: dimmed backdrop, rounded themed card (max 560 wide, max 80% of the screen high), a small x at the top right.
/// The card is as high as its content, up to 80% of the screen; taller content scrolls inside it. Content that fills the space by itself
/// (its own ScrollView or NavigationStack, measured as almost no height) gets the full maximum height and keeps its own scrolling.
/// Arrives with a fade and a 0.95 to 1 scale; no slide.
struct CenterSheetFrame<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onClose: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var shown = false
    @State private var locked = false
    @State private var contentHeight: CGFloat = 0
    @State private var greedy = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { if !locked { onClose() } }
                    .accessibilityIdentifier("popup-backdrop")
                card(maxHeight: geo.size.height * 0.8)
                    .frame(maxWidth: 560)
                    .frame(maxHeight: geo.size.height * 0.8)
                    .padding(.horizontal, 22)
                    .scaleEffect(shown || reduceMotion ? 1 : 0.95)
                    .opacity(shown ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(ClearCoverBackground())
        .onPreferenceChange(CenterSheetLockKey.self) { locked = $0 }
        .onAppear { withAnimation(Motion.arrive(reduceMotion)) { shown = true } }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func card(maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Button { onClose() } label: {
                    GlyphView(glyph: Glyph.close, size: 14, weight: 1.8, tint: P.ink)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(P.lineStrong, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle()).accessibilityLabel("Close").accessibilityIdentifier("popup-close")
            }
            .padding(.top, 10).padding(.trailing, 10).padding(.bottom, 2)
            scrollArea(maxHeight: maxHeight)
        }
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(P.card))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(P.lineStrong, lineWidth: 1))
    }
}

extension CenterSheetFrame {
    /// The content in a vertical scroll view that is as high as the content (header excluded) and no higher than the card allows.
    fileprivate func scrollArea(maxHeight: CGFloat) -> some View {
        let room: CGFloat = max(120, maxHeight - 48)
        let measured: CGFloat = contentHeight
        let fit: CGFloat = (greedy || measured <= 0) ? room : min(measured, room)
        let forced: CGFloat? = greedy ? room : nil
        return ScrollView(.vertical) {
            content()
                .frame(maxWidth: .infinity)
                .frame(height: forced)
                .background(
                    GeometryReader { (g: GeometryProxy) in
                        Color.clear.preference(key: CenterSheetHeightKey.self, value: g.size.height)
                    }
                )
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: fit)
        .onPreferenceChange(CenterSheetHeightKey.self) { (h: CGFloat) in
            contentHeight = h
            if h > 0 && h < 60 { greedy = true }
        }
    }
}

/// Runs a change with the system animation switched off (the popup fades in and out itself).
private func centerInstant(_ change: () -> Void) {
    var t = Transaction()
    t.disablesAnimations = true
    withTransaction(t, change)
}

private struct CenterSheetBool<Card: View>: ViewModifier {
    @Binding var isPresented: Bool
    var onDismiss: (() -> Void)?
    @ViewBuilder var card: () -> Card
    @State private var cover = false

    func body(content: Content) -> some View {
        content
            .onAppear { if isPresented && !cover { centerInstant { cover = true } } }
            .onChange(of: isPresented) { _, now in centerInstant { cover = now } }
            .fullScreenCover(isPresented: $cover, onDismiss: onDismiss) {
                CenterSheetFrame(onClose: { centerInstant { cover = false; isPresented = false } }) { card() }
                    .presentationBackground(.clear)
            }
    }
}

private struct CenterSheetItem<Item: Identifiable, Card: View>: ViewModifier {
    @Binding var item: Item?
    var onDismiss: (() -> Void)?
    @ViewBuilder var card: (Item) -> Card
    @State private var shownItem: Item?

    func body(content: Content) -> some View {
        content
            .onAppear { if let i = item, shownItem == nil { centerInstant { shownItem = i } } }
            .onChange(of: item?.id) { _, _ in centerInstant { shownItem = item } }
            .fullScreenCover(item: $shownItem, onDismiss: onDismiss) { (i: Item) in
                CenterSheetFrame(onClose: { centerInstant { shownItem = nil; item = nil } }) { card(i) }
                    .presentationBackground(.clear)
            }
    }
}

extension View {
    /// Same use as `.sheet(isPresented:)`, but the content opens as a centred popup card (like the daily report), not from the bottom.
    func centerSheet<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(CenterSheetBool(isPresented: isPresented, onDismiss: onDismiss, card: content))
    }

    /// Same use as `.sheet(item:)`, but the content opens as a centred popup card.
    func centerSheet<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        modifier(CenterSheetItem(item: item, onDismiss: onDismiss, card: content))
    }

    /// Inside a centred popup: a tap outside the card does not close it.
    func centerSheetLocked(_ locked: Bool = true) -> some View {
        preference(key: CenterSheetLockKey.self, value: locked)
    }
}
