import SwiftUI
import UIKit

/// A content view can call `.centerSheetLocked()` so a tap outside the popup does not close it (only its own buttons do).
private struct CenterSheetLockKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// A content view can call `.centerSheetTitle("...")` to put a title in the frame's header row when the title depends on the content.
private struct CenterSheetTitleKey: PreferenceKey {
    static var defaultValue: String = ""
    static func reduce(value: inout String, nextValue: () -> String) { if value.isEmpty { value = nextValue() } }
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

/// How high a centred popup is. `.fit` (default): exactly as high as its content, at most 80% of the screen, scrolling only when taller.
/// `.tall`: a fixed 80% of the screen, only for multi-step flows with a NavigationStack inside.
enum CenterSheetSize { case fit, tall }

/// One size/spacing set for every centred popup (CenterSheetFrame and GamePopup), so all cards share width, margin, header and room.
enum PopupMetrics {
    static let maxWidth: CGFloat = 560
    static let margin: CGFloat = 22
    static let header: CGFloat = 44
    static let roomFraction: CGFloat = 0.8
}

/// The fixed 44pt header row of every popup: optional title left (serif 16), the x right (44pt target), thin divider under a title.
struct PopupHeaderRow: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var showsClose: Bool
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 16, weight: .semibold, design: .serif)).foregroundStyle(P.ink).lineLimit(2).minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading).padding(.leading, 16)
                Spacer(minLength: 8)
                if showsClose { closeButton }
            }
            .frame(height: PopupMetrics.header)
            if !title.isEmpty { Rectangle().fill(P.line).frame(height: 1) }
        }
    }

    private var closeButton: some View {
        Button { onClose() } label: {
            GlyphView(glyph: Glyph.close, size: 13, weight: 1.8, tint: P.ink)
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(P.lineStrong, lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle()).accessibilityLabel("Close").accessibilityIdentifier("popup-close")
        .padding(.trailing, 6)
    }
}

/// The centred popup card: dimmed backdrop, rounded themed card (max 560 wide, max 80% of the screen high) with a fixed 44pt header row the
/// frame draws (optional title left, x right). Content never draws its own close button.
/// Arrives with a fade and a 0.95 to 1 scale; no slide.
struct CenterSheetFrame<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onClose: () -> Void
    var title: String = ""
    var size: CenterSheetSize = .fit
    @ViewBuilder var content: () -> Content
    @State private var shown = false
    @State private var locked = false
    @State private var contentTitle = ""

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { if !locked { onClose() } }
                    .accessibilityIdentifier("popup-backdrop")
                card(room: geo.size.height * PopupMetrics.roomFraction)
                    .frame(maxWidth: PopupMetrics.maxWidth)
                    .padding(.horizontal, PopupMetrics.margin)
                    .scaleEffect(shown || reduceMotion ? 1 : 0.95)
                    .opacity(shown ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .toggleStyle(LedgerToggleStyle())
        .background(ClearCoverBackground())
        .onPreferenceChange(CenterSheetLockKey.self) { locked = $0 }
        .onPreferenceChange(CenterSheetTitleKey.self) { contentTitle = $0 }
        .onAppear { withAnimation(Motion.arrive(reduceMotion)) { shown = true } }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func card(room: CGFloat) -> some View {
        let head: CGFloat = shownTitle.isEmpty ? PopupMetrics.header : PopupMetrics.header + 1
        return VStack(spacing: 0) {
            headerRow
            inner(room: room - head)
        }
        .foregroundStyle(P.ink)
        .environment(\.colorScheme, P.isLight ? .light : .dark)
        .frame(height: size == .tall ? max(260, room) : nil)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(P.card))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(P.lineStrong, lineWidth: 1))
    }

    /// The title shown in the header: the `title:` argument, else the one the content set with `.centerSheetTitle`.
    private var shownTitle: String { title.isEmpty ? contentTitle : title }

    private var headerRow: some View {
        PopupHeaderRow(title: shownTitle, showsClose: true, onClose: onClose)
    }

    @ViewBuilder private func inner(room: CGFloat) -> some View {
        if size == .tall {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            FitScroll(maxHeight: room) { content().padding(16) }
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
    var title: String
    var size: CenterSheetSize
    var onDismiss: (() -> Void)?
    @ViewBuilder var card: () -> Card
    @State private var cover = false

    func body(content: Content) -> some View {
        content
            .onAppear { if isPresented && !cover { centerInstant { cover = true } } }
            .onChange(of: isPresented) { _, now in centerInstant { cover = now } }
            .fullScreenCover(isPresented: $cover, onDismiss: onDismiss) {
                CenterSheetFrame(onClose: { centerInstant { cover = false; isPresented = false } }, title: title, size: size) { card() }
                    .presentationBackground(.clear)
            }
    }
}

private struct CenterSheetItem<Item: Identifiable, Card: View>: ViewModifier {
    @Binding var item: Item?
    var title: String
    var size: CenterSheetSize
    var onDismiss: (() -> Void)?
    @ViewBuilder var card: (Item) -> Card
    @State private var shownItem: Item?

    func body(content: Content) -> some View {
        content
            .onAppear { if let i = item, shownItem == nil { centerInstant { shownItem = i } } }
            .onChange(of: item?.id) { _, _ in centerInstant { shownItem = item } }
            .fullScreenCover(item: $shownItem, onDismiss: onDismiss) { (i: Item) in
                CenterSheetFrame(onClose: { centerInstant { shownItem = nil; item = nil } }, title: title, size: size) { card(i) }
                    .presentationBackground(.clear)
            }
    }
}

extension View {
    /// Same use as `.sheet(isPresented:)`, but the content opens as a centred popup card (like the daily report), not from the bottom.
    func centerSheet<Content: View>(isPresented: Binding<Bool>, title: String = "", size: CenterSheetSize = .fit, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(CenterSheetBool(isPresented: isPresented, title: title, size: size, onDismiss: onDismiss, card: content))
    }

    /// Same use as `.sheet(item:)`, but the content opens as a centred popup card.
    func centerSheet<Item: Identifiable, Content: View>(item: Binding<Item?>, title: String = "", size: CenterSheetSize = .fit, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        modifier(CenterSheetItem(item: item, title: title, size: size, onDismiss: onDismiss, card: content))
    }

    /// Inside a centred popup: puts this title in the frame's header row.
    func centerSheetTitle(_ title: String) -> some View {
        preference(key: CenterSheetTitleKey.self, value: title)
    }

    /// Inside a centred popup: a tap outside the card does not close it.
    func centerSheetLocked(_ locked: Bool = true) -> some View {
        preference(key: CenterSheetLockKey.self, value: locked)
    }
}
