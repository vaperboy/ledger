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

/// Height of a popup's pinned footer, so the scrolling body gets the room that is left.
private struct CenterSheetFooterHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The action row a content view hands to the frame with `.popupFooter { }`; the frame pins it under the scrolling body.
private struct CenterSheetFooterKey: PreferenceKey {
    static var defaultValue: AnyView? = nil
    static func reduce(value: inout AnyView?, nextValue: () -> AnyView?) { if let n = nextValue() { value = n } }
}

/// How a centred popup is sized. The five size classes (toast, compact, standard, tall, full) are defined in `PopupSizing.swift`; the frame
/// picks one from the content for `.fit` and `.fitBleed`, and `.tall` is always the full class.
/// `.fit` (default): exactly as high as its content, at most 80% of the screen, scrolling only when taller.
/// `.fitBleed`: like `.fit` without the 16pt content padding (full-bleed photos). `.tall`: a fixed 80% of the screen, only for multi-step flows with their own pages: wrap them in `PopupStack` (Design/PopupStack.swift), where `popupClose` steps back one page and closes only at the root.
enum CenterSheetSize { case fit, fitBleed, tall }

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
                Text(title).popupText(.title).lineLimit(2).minimumScaleFactor(0.85)
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

/// The centred popup card: dimmed backdrop, rounded themed card with a fixed 44pt header row the frame draws (optional title left, x right).
/// Content never draws its own close button. The card picks one of five size classes (`PopupSizeClass`, rules in `PopupSizing`) from the
/// height of its content: width, backdrop and entrance follow the class, and the card springs to its new size when the content changes.
/// Arrives with a fade, a scale from the class's start scale and a short rise; a tall or full card swipes down to close.
struct CenterSheetFrame<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onClose: () -> Void
    var title: String = ""
    var size: CenterSheetSize = .fit
    var showsClose: Bool = true
    /// False: a tap outside never closes this card (the daily report), whatever the content says.
    var backdropCloses: Bool = true
    var variant: PopupVariant = .standard
    /// Optional footer pinned below the scrolling body (always visible, inside the card); none by default.
    var pinnedFooter: AnyView? = nil
    @ViewBuilder var content: () -> Content
    @State private var footerHeight: CGFloat = 0
    @State private var shown = false
    @State private var locked = false
    @State private var contentTitle = ""
    @State private var measuredClass: PopupSizeClass = .standard
    @State private var drag: CGFloat = 0
    @State private var keyboardUp = false

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            layout(screen: geo.size)
        }
        .toggleStyle(LedgerToggleStyle())
        .onPreferenceChange(CenterSheetLockKey.self) { locked = $0 }
        .onPreferenceChange(CenterSheetTitleKey.self) { contentTitle = $0 }
        .onPreferenceChange(CenterSheetFooterHeightKey.self) { footerHeight = $0 }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { (_: Notification) in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { (_: Notification) in keyboardUp = false }
        .onAppear {
            Haptics.play(variant.appearCue)
            Motion.animate(Motion.arrive(reduceMotion)) { shown = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func layout(screen: CGSize) -> some View {
        let cls: PopupSizeClass = size == .tall ? .full : measuredClass
        let dim: Double = PopupSizing.dim(of: cls) * PopupSizing.dragDimFactor(offset: drag)
        let rise: CGFloat = PopupSizing.entryRise(of: cls, reduceMotion: reduceMotion)
        let startScale: CGFloat = PopupSizing.entryScale(of: cls, reduceMotion: reduceMotion)
        return ZStack {
            Color.black.opacity(shown ? dim : 0).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { backdropTap() }
                .accessibilityIdentifier("popup-backdrop")
            card(screen: screen, cls: cls)
                .frame(maxWidth: PopupSizing.maxWidth(of: cls))
                .padding(.horizontal, PopupMetrics.margin)
                .scaleEffect(shown ? 1 : startScale)
                .offset(y: (shown ? 0 : rise) + drag)
                .opacity(shown ? 1 : 0)
        }
        .frame(width: screen.width, height: screen.height)
        .animation(Motion.size(reduceMotion), value: cls)
    }

    /// A tap outside first puts the keyboard away (a typed value is never thrown out by that tap); only a tap with no keyboard closes.
    private func backdropTap() {
        if keyboardUp {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            return
        }
        if !locked && backdropCloses { onClose() }
    }

    private func card(screen: CGSize, cls: PopupSizeClass) -> some View {
        let room: CGFloat = PopupSizing.room(screenHeight: screen.height)
        let head: CGFloat = shownTitle.isEmpty ? PopupMetrics.header : PopupMetrics.header + 1
        let swipe: Bool = cls.isSwipeable && !locked && backdropCloses
        let fixedHeight: CGFloat? = size == .tall ? PopupSizing.fullHeight(screenHeight: screen.height) : nil
        let shape: RoundedRectangle = RoundedRectangle(cornerRadius: PopupRadius.card, style: .continuous)
        let mask: GestureMask = swipe ? GestureMask.all : GestureMask.subviews
        return VStack(spacing: 0) {
            headerRow
                .contentShape(Rectangle())
                .gesture(dismissDrag, including: mask)
            inner(room: room - head - footerHeight, head: head + footerHeight, screenHeight: screen.height)
            Color.clear.frame(height: footerHeight)
        }
        .foregroundStyle(P.ink)
        .environment(\.insidePopup, true)
        .environment(\.colorScheme, P.isLight ? .light : .dark)
        .frame(height: fixedHeight)
        .overlayPreferenceValue(CenterSheetFooterKey.self, alignment: .bottom) { (f: AnyView?) in footerLayer(f) }
        .background(shape.fill(P.card))
        .clipShape(shape)
        .overlay(shape.strokeBorder(P.lineStrong, lineWidth: 1))
        .overlay(alignment: .top) { grabber(swipe) }
        .overlay { celebration }
    }

    /// The footer sits over the bottom of the card (the body above it has been given its height), measured so the body keeps the room that is left.
    @ViewBuilder private func footerLayer(_ fromContent: AnyView?) -> some View {
        if let footer = pinnedFooter ?? fromContent {
            footer.frame(maxWidth: .infinity).background(GeometryReader { (g: GeometryProxy) in
                Color.clear.preference(key: CenterSheetFooterHeightKey.self, value: g.size.height)
            })
        }
    }

    /// The title shown in the header: the `title:` argument, else the one the content set with `.centerSheetTitle`.
    private var shownTitle: String { title.isEmpty ? contentTitle : title }

    private var headerRow: some View {
        PopupHeaderRow(title: shownTitle, showsClose: showsClose, onClose: onClose)
    }

    @ViewBuilder private func grabber(_ visible: Bool) -> some View {
        if visible {
            Capsule().fill(P.lineStrong).frame(width: 36, height: 4).padding(.top, 5).allowsHitTesting(false)
        }
    }

    /// A reward card throws a confetti burst when it arrives (never under Reduce Motion).
    @ViewBuilder private var celebration: some View {
        if variant == .reward && !reduceMotion { ConfettiBurst() }
    }

    @ViewBuilder private func inner(room: CGFloat, head: CGFloat, screenHeight: CGFloat) -> some View {
        if size == .tall {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            FitScroll(maxHeight: room, onMeasure: { (h: CGFloat) in measure(h + head, screenHeight: screenHeight) }) {
                content().padding(size == .fitBleed ? 0 : 16)
            }
        }
    }

    /// Picks the size class for the measured card height; the spring on `layout` animates the change.
    private func measure(_ cardHeight: CGFloat, screenHeight: CGFloat) {
        let next: PopupSizeClass = PopupSizing.sizeClass(requested: size, cardHeight: cardHeight, screenHeight: screenHeight, previous: measuredClass)
        if next != measuredClass { measuredClass = next }
    }

    /// Swipe down on the header closes a tall or full card; a short pull springs back.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { (v: DragGesture.Value) in
                drag = PopupSizing.dragOffset(translation: v.translation.height)
            }
            .onEnded { (v: DragGesture.Value) in
                let away: Bool = PopupSizing.shouldDismiss(translation: v.translation.height, predictedEnd: v.predictedEndTranslation.height)
                if away { onClose() }
                // A card that stays (a step back inside a popup stack) springs back; one that closes has faded out by then.
                let delay: Double = away ? 0.4 : 0
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    Motion.animate(Motion.size(reduceMotion)) { drag = 0 }
                }
            }
    }
}

private struct CenterSheetBool<Card: View>: ViewModifier {
    @Binding var isPresented: Bool
    var title: String
    var size: CenterSheetSize
    var onDismiss: (() -> Void)?
    @ViewBuilder var card: () -> Card

    func body(content: Content) -> some View {
        let flag: Binding<Bool> = $isPresented
        return content.modifier(HostedPopupModifier(key: "sheet", priority: .panel, active: isPresented, draw: .card(title: title, size: size),
                                                    onClose: { flag.wrappedValue = false }, onDismiss: onDismiss, card: card))
    }
}

private struct CenterSheetItem<Item: Identifiable, Card: View>: ViewModifier {
    @Binding var item: Item?
    var title: String
    var size: CenterSheetSize
    var onDismiss: (() -> Void)?
    @ViewBuilder var card: (Item) -> Card

    func body(content: Content) -> some View {
        let current: Item? = item
        let slot: Binding<Item?> = $item
        let build: (Item) -> Card = card
        return content.modifier(HostedPopupModifier(key: current.map { (i: Item) -> String in "item-\(i.id)" } ?? "item", priority: .panel, active: current != nil,
                                                    draw: .card(title: title, size: size),
                                                    onClose: { slot.wrappedValue = nil }, onDismiss: onDismiss,
                                                    card: { () -> AnyView in
                                                        if let i = current { return AnyView(build(i)) }
                                                        return AnyView(EmptyView())
                                                    }))
    }
}

extension View {
    /// Same use as `.sheet(isPresented:)`, but the content is a centred popup card drawn by the app's popup host (no cover, no navigation change).
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

    /// Inside a centred popup: pins this action row (a `PopupActionBar`) under the scrolling body, so the buttons never scroll away.
    func popupFooter<F: View>(@ViewBuilder _ footer: () -> F) -> some View {
        let built: F = footer()
        return preference(key: CenterSheetFooterKey.self, value: AnyView(PopupActionBar { built }))
    }

    /// Inside a centred popup: a tap outside the card does not close it.
    func centerSheetLocked(_ locked: Bool = true) -> some View {
        preference(key: CenterSheetLockKey.self, value: locked)
    }
}
