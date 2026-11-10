import SwiftUI
import UIKit

private struct CenterSheetLockKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

private struct CenterSheetTitleKey: PreferenceKey {
    static var defaultValue: String = ""
    static func reduce(value: inout String, nextValue: () -> String) { if value.isEmpty { value = nextValue() } }
}

private struct CenterSheetFooterHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct CenterSheetFooterKey: PreferenceKey {
    static var defaultValue: AnyView? = nil
    static func reduce(value: inout AnyView?, nextValue: () -> AnyView?) { if let n = nextValue() { value = n } }
}

enum CenterSheetSize { case fit, fitBleed, tall }

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

struct CenterSheetFrame<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.popupPriority) private var priority
    var onClose: () -> Void
    var title: String = ""
    var size: CenterSheetSize = .fit
    var showsClose: Bool = true
    var backdropCloses: Bool = true
    var variant: PopupVariant = .standard
    var pinnedFooter: AnyView? = nil
    var category: PopupCategory? = nil
    var tone: PopupTone? = nil
    var icon: String? = nil
    @ViewBuilder var content: () -> Content
    @State private var footerHeight: CGFloat = 0
    @State private var shown = false
    @State private var locked = false
    @State private var contentTitle = ""
    @State private var drag: CGFloat = 0
    @State private var keyboardUp = false
    @State private var natural: CGFloat = 0

    private var cat: PopupCategory { category ?? PopupLayout.category(for: size) }
    private var shade: PopupTone { tone ?? PopupTone(variant: variant) }
    private var entrance: PopupEntrance { PopupEntrance.of(category: cat, variant: variant, tone: shade, priority: priority) }

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
            Motion.animate(reduceMotion ? nil : entrance.animation) { shown = true }
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
                .offset(x: shown || reduceMotion ? 0 : entrance.dx, y: drag + (shown || reduceMotion ? 0 : entrance.dy))
                .scaleEffect(shown || reduceMotion ? 1 : entrance.scale)
                .opacity(shown ? 1 : 0)
        }
        .frame(width: screen.width, height: screen.height)
    }

    private var backdrop: some View {
        let factor: Double = PopupSizing.dragDimFactor(offset: drag)
        return ZStack {
            if reduceTransparency {
                Color.black.opacity(shown ? 0.7 * factor : 0)
            } else {
                Rectangle().fill(.ultraThinMaterial).opacity(shown ? factor : 0)
                Color.black.opacity(shown ? 0.4 * factor : 0)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { backdropTap() }
        .accessibilityIdentifier("popup-backdrop")
    }

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
        .clipShape(RoundedRectangle(cornerRadius: PopupLayout.radius, style: .continuous))
        .modifier(PopupGlass(tone: shade, light: P.isLight))
        .overlay { celebration }
        .environment(\.colorScheme, P.isLight ? .light : .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("popup-card")
    }

    private var hasHeader: Bool { !shownTitle.isEmpty || showsClose }

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

    @ViewBuilder private func footerLayer(_ fromContent: AnyView?) -> some View {
        if let footer = pinnedFooter ?? fromContent {
            footer.frame(maxWidth: .infinity).background(GeometryReader { (g: GeometryProxy) in
                Color.clear.preference(key: CenterSheetFooterHeightKey.self, value: g.size.height)
            })
        }
    }

    private var shownTitle: String { title.isEmpty ? contentTitle : title }

    private var grabber: some View {
        Capsule().fill(P.ink.opacity(0.22)).frame(width: 40, height: 5).padding(.top, 8).allowsHitTesting(false)
    }

    @ViewBuilder private var celebration: some View {
        if variant == .reward && !reduceMotion { ConfettiBurst() }
    }

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

    private var padded: some View {
        let pad: CGFloat = size == .fitBleed ? 0 : PopupLayout.inset
        return content()
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, pad)
            .padding(.top, cat == .compact ? 10 : (hasHeader ? 4 : pad))
            .padding(.bottom, pad)
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { (v: DragGesture.Value) in
                drag = PopupSizing.dragOffset(translation: v.translation.height)
            }
            .onEnded { (v: DragGesture.Value) in
                let away: Bool = PopupSizing.shouldDismiss(translation: v.translation.height, predictedEnd: v.predictedEndTranslation.height)
                if away { onClose() }
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
    func centerSheet<Content: View>(isPresented: Binding<Bool>, title: String = "", size: CenterSheetSize = .fit, category: PopupCategory? = nil, tone: PopupTone? = nil,
                                    onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(CenterSheetBool(isPresented: isPresented, title: title, size: size, category: category, tone: tone, onDismiss: onDismiss, card: content))
    }

    func centerSheet<Item: Identifiable, Content: View>(item: Binding<Item?>, title: String = "", size: CenterSheetSize = .fit, category: PopupCategory? = nil, tone: PopupTone? = nil,
                                                        onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        modifier(CenterSheetItem(item: item, title: title, size: size, category: category, tone: tone, onDismiss: onDismiss, card: content))
    }

    func centerSheetTitle(_ title: String) -> some View {
        preference(key: CenterSheetTitleKey.self, value: title)
    }

    func popupFooter<F: View>(@ViewBuilder _ footer: () -> F) -> some View {
        let built: F = footer()
        return preference(key: CenterSheetFooterKey.self, value: AnyView(PopupActionBar { built }))
    }

    func centerSheetLocked(_ locked: Bool = true) -> some View {
        preference(key: CenterSheetLockKey.self, value: locked)
    }
}
