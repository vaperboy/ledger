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

/// What a call site asks for when it names no category. `.fit` is a medium popup, `.fitBleed` the same without the body inset (photos),
/// `.tall` a detail panel whose content scrolls by itself (a `PopupStack`, a page with its own scroll view): only that case gets a fixed
/// height. The rules live in `PopupSystem.swift` (`PopupCategory`, `PopupLayout`).
enum CenterSheetSize { case fit, fitBleed, tall }

/// The header of a medium popup or detail panel: the title centred, the close x on a round soft fill at the right. A compact popup has no
/// header row: its icon and title sit inside the body.
struct PopupHeaderRow: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var showsClose: Bool
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .textStyle(.figure, tint: P.ink)
                .lineLimit(2).minimumScaleFactor(0.85).multilineTextAlignment(.center)
                .padding(.horizontal, 64)
            HStack {
                Spacer(minLength: 0)
                if showsClose { PopupCloseButton(onClose: onClose) }
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 64)
        .accessibilityElement(children: .contain)
    }
}

/// The x of a popup: a soft round button (44pt), id `popup-close`.
struct PopupCloseButton: View {
    @Environment(\.outsidePalette) private var P
    var onClose: () -> Void

    var body: some View {
        Button { onClose() } label: {
            LedgerGlyph(glyph: Glyph.close, size: Theme.Icon.small, tint: P.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(P.ink.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle()).accessibilityLabel("Close").accessibilityIdentifier("popup-close")
    }
}

/// The one popup frame. Every popup (every `.centerSheet`, `GamePopup`, confirmation and hosted popup) is drawn by it, in one of three
/// categories (`PopupCategory`) with one tone (`PopupTone`). All share the glass surface (`PopupGlass`); only the size differs:
///   compact  icon ring and title inside the body, exactly as high as the content, no header row, no grabber.
///   medium   header row, as high as the content, scrolls past 70% of the screen.
///   detail   header row and pinned footer, as high as the content up to 92% of the screen; fixed at that height only when the content
///            scrolls by itself (`size: .tall`).
/// No minimum height and no stretching: a short popup is short. Every card is centred on the screen at its category's width and
/// arrives with a short scale and fade.
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
    /// The popup's category; nil: `.tall` is a detail panel, anything else medium.
    var category: PopupCategory? = nil
    /// The event's tone; nil: taken from the variant.
    var tone: PopupTone? = nil
    /// SF Symbol of a compact popup's icon ring; nil: the tone's own symbol.
    var icon: String? = nil
    @ViewBuilder var content: () -> Content
    @State private var footerHeight: CGFloat = 0
    @State private var shown = false
    @State private var locked = false
    @State private var contentTitle = ""
    @State private var drag: CGFloat = 0
    @State private var keyboardUp = false
    /// The content's natural height, measured from a hidden copy (0 until measured).
    @State private var natural: CGFloat = 0

    private var cat: PopupCategory { category ?? PopupLayout.category(for: size) }
    private var shade: PopupTone { tone ?? PopupTone(variant: variant) }

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
        let width: CGFloat = PopupLayout.cardWidth(cat, screenWidth: screen.width)
        return ZStack {
            backdrop
            card(screen: screen)
                .frame(width: width)
                .offset(y: drag)
                .scaleEffect(shown || reduceMotion ? 1 : 0.94)
                .opacity(shown ? 1 : 0)
        }
        .frame(width: screen.width, height: screen.height)
    }

    /// The page behind: blurred and dimmed, lighter while the card is dragged away. A tap closes (unless locked).
    private var backdrop: some View {
        let factor: Double = PopupSizing.dragDimFactor(offset: drag)
        return ZStack {
            Rectangle().fill(.ultraThinMaterial).opacity(shown ? factor : 0)
            Color.black.opacity(shown ? 0.4 * factor : 0)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { backdropTap() }
        .accessibilityIdentifier("popup-backdrop")
    }

    /// A tap outside first puts the keyboard away (a typed value is never thrown out by that tap); only a tap with no keyboard closes.
    private func backdropTap() {
        if keyboardUp {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            return
        }
        if !locked && backdropCloses { onClose() }
    }

    private func card(screen: CGSize) -> some View {
        let cardMax: CGFloat = PopupLayout.maxHeight(cat, screenHeight: screen.height)
        let swipe: Bool = cat != .compact && !locked && backdropCloses
        let headRoom: CGFloat = cat == .compact ? 150 : (hasHeader ? 64 : 20)
        let bodyMax: CGFloat = max(120, cardMax - headRoom - footerHeight)
        return VStack(spacing: 0) {
            if swipe { grabber }
            head(swipe: swipe)
            inner(bodyMax: bodyMax)
            Color.clear.frame(height: footerHeight)
        }
        .foregroundStyle(P.ink)
        .environment(\.insidePopup, true)
        .environment(\.popupTone, shade)
        .environment(\.popupCategory, cat)
        .frame(height: size == .tall ? cardMax : nil)
        .overlayPreferenceValue(CenterSheetFooterKey.self, alignment: .bottom) { (f: AnyView?) in footerLayer(f) }
        .modifier(PopupGlass(tone: shade, light: P.isLight))
        .overlay { celebration }
        // The scheme wraps the glass too, so a light palette gets light material behind its dark text.
        .environment(\.colorScheme, P.isLight ? .light : .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("popup-card")
    }

    private var hasHeader: Bool { !shownTitle.isEmpty || showsClose }

    /// Compact: icon ring and centred title (the x, if any, at the corner). Medium and detail: the header row.
    @ViewBuilder private func head(swipe: Bool) -> some View {
        if cat == .compact {
            VStack(spacing: 14) {
                PopupIconRing(systemName: icon ?? shade.defaultSymbol, tone: shade)
                if !shownTitle.isEmpty {
                    Text(shownTitle)
                        .textStyle(.title, tint: P.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, PopupLayout.inset)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
            .overlay(alignment: .topTrailing) {
                if showsClose { PopupCloseButton(onClose: onClose).padding(10) }
            }
        } else if hasHeader {
            PopupHeaderRow(title: shownTitle, showsClose: showsClose, onClose: onClose)
                .contentShape(Rectangle())
                .gesture(dismissDrag, including: swipe ? GestureMask.all : GestureMask.subviews)
        }
    }

    /// The footer sits over the bottom of the card (the body above it has been given its height), measured so the body keeps the room that is left.
    @ViewBuilder private func footerLayer(_ fromContent: AnyView?) -> some View {
        if let footer = pinnedFooter ?? fromContent {
            footer.frame(maxWidth: .infinity).background(GeometryReader { (g: GeometryProxy) in
                Color.clear.preference(key: CenterSheetFooterHeightKey.self, value: g.size.height)
            })
        }
    }

    /// The title shown: the `title:` argument, else the one the content set with `.centerSheetTitle`.
    private var shownTitle: String { title.isEmpty ? contentTitle : title }

    private var grabber: some View {
        Capsule().fill(P.ink.opacity(0.22)).frame(width: 40, height: 5).padding(.top, 8).allowsHitTesting(false)
    }

    /// A reward card throws a confetti burst when it arrives (never under Reduce Motion).
    @ViewBuilder private var celebration: some View {
        if variant == .reward && !reduceMotion { ConfettiBurst() }
    }

    /// The body: exactly as high as the content, scrolling only past the category's room. A hidden copy of the content at its natural
    /// height (outside any scroll view) is measured, and the scroll view gets exactly that height; until then it is invisible, never a
    /// guessed height. A detail panel whose content scrolls by itself (`.tall`) fills the panel instead.
    @ViewBuilder private func inner(bodyMax: CGFloat) -> some View {
        if size == .tall {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical) { padded }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .frame(height: natural > 0 ? min(natural, bodyMax) : 1)
                .opacity(natural > 0 ? 1 : 0)
                .background(alignment: .top) {
                    padded
                        .hidden()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .onGeometryChange(for: CGFloat.self, of: { (g: GeometryProxy) -> CGFloat in g.size.height }) { (h: CGFloat) in
                            if abs(h - natural) > 0.5 { natural = h }
                        }
                }
                .clipped()
        }
    }

    /// The content at its natural height with the category's insets.
    private var padded: some View {
        let pad: CGFloat = size == .fitBleed ? 0 : PopupLayout.inset
        return content()
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, pad)
            .padding(.top, cat == .compact ? 10 : (hasHeader ? 4 : pad))
            .padding(.bottom, pad)
    }

    /// Swipe down on the header closes a medium or detail card; a short pull springs back.
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
    var category: PopupCategory?
    var tone: PopupTone?
    var onDismiss: (() -> Void)?
    @ViewBuilder var card: () -> Card

    func body(content: Content) -> some View {
        let flag: Binding<Bool> = $isPresented
        return content.modifier(HostedPopupModifier(key: "sheet", priority: .panel, active: isPresented, draw: .card(title: title, size: size, category: category, tone: tone),
                                                    onClose: { flag.wrappedValue = false }, onDismiss: onDismiss, card: card))
    }
}

private struct CenterSheetItem<Item: Identifiable, Card: View>: ViewModifier {
    @Binding var item: Item?
    var title: String
    var size: CenterSheetSize
    var category: PopupCategory?
    var tone: PopupTone?
    var onDismiss: (() -> Void)?
    @ViewBuilder var card: (Item) -> Card

    func body(content: Content) -> some View {
        let current: Item? = item
        let slot: Binding<Item?> = $item
        let build: (Item) -> Card = card
        return content.modifier(HostedPopupModifier(key: current.map { (i: Item) -> String in "item-\(i.id)" } ?? "item", priority: .panel, active: current != nil,
                                                    draw: .card(title: title, size: size, category: category, tone: tone),
                                                    onClose: { slot.wrappedValue = nil }, onDismiss: onDismiss,
                                                    card: { () -> AnyView in
                                                        if let i = current { return AnyView(build(i)) }
                                                        return AnyView(EmptyView())
                                                    }))
    }
}

extension View {
    /// Same use as `.sheet(isPresented:)`, but the content is a centred popup card drawn by the app's popup host (no cover, no navigation change).
    func centerSheet<Content: View>(isPresented: Binding<Bool>, title: String = "", size: CenterSheetSize = .fit, category: PopupCategory? = nil, tone: PopupTone? = nil,
                                    onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(CenterSheetBool(isPresented: isPresented, title: title, size: size, category: category, tone: tone, onDismiss: onDismiss, card: content))
    }

    /// Same use as `.sheet(item:)`, but the content opens as a centred popup card.
    func centerSheet<Item: Identifiable, Content: View>(item: Binding<Item?>, title: String = "", size: CenterSheetSize = .fit, category: PopupCategory? = nil, tone: PopupTone? = nil,
                                                        onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        modifier(CenterSheetItem(item: item, title: title, size: size, category: category, tone: tone, onDismiss: onDismiss, card: content))
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
