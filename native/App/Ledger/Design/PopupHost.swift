import SwiftUI
import UIKit
import Combine

/// How a registered popup is drawn: `.card` is wrapped in the standard centred card (header with x, scrolling body); `.raw` draws its own
/// complete popup (a `GamePopup`, a report page).
enum PopupDraw {
    case card(title: String, size: CenterSheetSize)
    case raw
}

/// One popup registered with a host. The content closure is kept as `AnyView`; the card's own state lives in the host's layer.
struct PopupEntry {
    var key: String
    var seq: Int
    var priority: PopupPriority
    var draw: PopupDraw
    var content: () -> AnyView
    var onClose: () -> Void
    var item: PopupQueue.Item { PopupQueue.Item(key: key, priority: priority, seq: seq) }
}

/// The one popup host. The app root owns one and draws every popup above the whole app (tab bar included) as an overlay: no cover, no
/// sheet, no dialog, so showing a popup never touches navigation. A `.sheet` that can raise popups installs a nested host with
/// `.popupHost()`; it shows its own popups and those of the host above it.
final class PopupHost: ObservableObject {
    private static var counter = 0

    @Published private(set) var entries: [String: PopupEntry] = [:]
    /// How many nested hosts (sheets) are open under this one. While one is, it draws this host's popups, so they are drawn once.
    @Published private(set) var claims = 0
    /// The host above this one (set while this nested host's sheet is open), and whether this host holds a claim on it.
    private(set) weak var parentHost: PopupHost?
    private var holdsClaim = false
    private var parentLink: AnyCancellable?

    func claim() { claims += 1 }
    func release() { claims = max(0, claims - 1) }

    /// A nested host (the content of a `.sheet`) takes over drawing the popups of the host above it for as long as it is open. The claim is
    /// taken once and given back once (`detach`, or when this host is deallocated, so a sheet that vanishes without `onDisappear` cannot
    /// leave the host above silent for good).
    func attach(to above: PopupHost?) {
        guard !holdsClaim, let above, above !== self else { return }
        parentHost = above
        holdsClaim = true
        above.claim()
        parentLink = above.objectWillChange.sink { [weak self] (_: Void) in self?.objectWillChange.send() }
    }

    func detach() {
        parentLink = nil
        if holdsClaim { holdsClaim = false; parentHost?.release() }
        parentHost = nil
    }

    deinit {
        if holdsClaim, let above = parentHost {
            DispatchQueue.main.async { above.release() }
        }
    }

    /// Every popup this host and the hosts above it have registered.
    func gathered() -> [PopupEntry] {
        Array(entries.values) + (parentHost?.gathered() ?? [])
    }

    /// What this host's layer draws: nothing while a nested host (a sheet) is open on top of it, because that one draws these popups
    /// too (once, over the sheet); otherwise its own popups and those of the hosts above it.
    func drawnEntries() -> [PopupEntry] {
        claims > 0 ? [] : gathered()
    }

    private static func nextSeq() -> Int { counter += 1; return counter }

    func upsert(key: String, priority: PopupPriority, draw: PopupDraw, content: @escaping () -> AnyView, onClose: @escaping () -> Void) {
        let seq: Int = entries[key]?.seq ?? PopupHost.nextSeq()
        entries[key] = PopupEntry(key: key, seq: seq, priority: priority, draw: draw, content: content, onClose: onClose)
    }

    /// The one definition of "a popup is showing here": at least one registered popup is drawn (any kind, panels included).
    var hasVisible: Bool { !drawnEntries().isEmpty }

    func remove(_ key: String) {
        if entries[key] != nil { entries[key] = nil }
    }
}

private struct PopupHostKey: EnvironmentKey { static let defaultValue: PopupHost? = nil }
extension EnvironmentValues {
    /// The host that takes this view's popups (a plain reference, read without observing, so a view never re-renders when popups change).
    var popupHost: PopupHost? {
        get { self[PopupHostKey.self] }
        set { self[PopupHostKey.self] = newValue }
    }
}

private struct PopupCloseKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }
extension EnvironmentValues {
    /// Set for everything drawn inside a popup: closes that popup. A view that used `\.dismiss` to close its centred popup calls this
    /// first (the system dismiss would pop the page under the popup, because the popup is no longer a presentation).
    var popupClose: (() -> Void)? {
        get { self[PopupCloseKey.self] }
        set { self[PopupCloseKey.self] = newValue }
    }
}

/// Draws the popups of a host (and of the host above it): every registered popup stays in the hierarchy so its state survives while
/// another one is on top, but only the first in `PopupQueue` order is visible and takes touches.
struct PopupHostLayer: View {
    @ObservedObject var host: PopupHost
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let drawn: [PopupEntry] = host.drawnEntries()
        let all: [PopupEntry] = drawn.sorted { (a: PopupEntry, b: PopupEntry) -> Bool in a.seq < b.seq }
        let top: String? = PopupQueue.visible(all.map { (e: PopupEntry) -> PopupQueue.Item in e.item })
        let signature: [String] = all.map { (e: PopupEntry) -> String in e.key } + [top ?? ""]
        return ZStack {
            ForEach(all, id: \.key) { (e: PopupEntry) in
                let on: Bool = e.key == top
                entryView(e)
                    .opacity(on ? 1 : 0)
                    .scaleEffect(on || reduceMotion || !e.priority.isDialog ? 1 : Motion.hiddenScale)
                    .allowsHitTesting(on)
                    .accessibilityHidden(!on)
                    .zIndex(on ? 1 : 0)
                    .transition(e.priority.isDialog ? Motion.confirmTransition(reduceMotion) : Motion.panelTransition(reduceMotion))
            }
        }
        .animation(Motion.arrive(reduceMotion), value: signature)
    }

    @ViewBuilder private func entryView(_ e: PopupEntry) -> some View {
        switch e.draw {
        case .card(let title, let size):
            CenterSheetFrame(onClose: e.onClose, title: title, size: size) { e.content().environment(\.popupClose, e.onClose) }
        case .raw:
            e.content().environment(\.popupClose, e.onClose)
        }
    }
}

/// Registers one popup with the host of its environment while `active`. It is a zero-size UIKit view so it can follow every update of the
/// view that owns the popup (the content closure always is the newest) without that view observing the host.
struct PopupRegistration: UIViewRepresentable {
    var host: PopupHost?
    var key: String
    var priority: PopupPriority
    var active: Bool
    var draw: PopupDraw
    var content: () -> AnyView
    var onClose: () -> Void
    var onDismiss: (() -> Void)?

    final class Coordinator {
        let uid: String = UUID().uuidString
        var host: PopupHost?
        var current: String?
        var wasActive = false
        var gone = false

        func sync(_ r: PopupRegistration) {
            guard !gone, let host = r.host else { return }
            self.host = host
            if r.active {
                let full: String = uid + "|" + r.key
                if let old = current, old != full { host.remove(old) }
                current = full
                wasActive = true
                host.upsert(key: full, priority: r.priority, draw: r.draw, content: r.content, onClose: r.onClose)
            } else {
                if let old = current { host.remove(old); current = nil }
                if wasActive {
                    wasActive = false
                    r.onDismiss?()
                }
            }
        }

        func teardown() {
            gone = true
            if let k = current { host?.remove(k) }
            current = nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        v.isHidden = true
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let c: Coordinator = context.coordinator
        let snapshot: PopupRegistration = self
        DispatchQueue.main.async { c.sync(snapshot) }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.teardown()
    }
}

private struct PopupHostModifier: ViewModifier {
    @Environment(\.popupHost) private var parent
    @StateObject private var host = PopupHost()

    func body(content: Content) -> some View {
        content
            .overlay { PopupHostLayer(host: host) }
            .environment(\.popupHost, host)
            .onAppear { host.attach(to: parent) }
            .onDisappear { host.detach() }
    }
}

/// The custom environment values the registering view had, put back around the popup content (which is drawn at the app root).
struct PopupCarriedEnvironment: ViewModifier {
    var insideCard: Bool
    var markerBudget: MarkerBudget?
    var markerPageActive: Bool
    var tabBarClearance: CGFloat
    var openHire: (HireRequest) -> Void
    var hidesRootBack: Bool

    func body(content: Content) -> some View {
        content
            .environment(\.insideCard, insideCard)
            .environment(\.markerBudget, markerBudget)
            .environment(\.markerPageActive, markerPageActive)
            .environment(\.tabBarClearance, tabBarClearance)
            .environment(\.openHire, openHire)
            .environment(\.hidesRootBack, hidesRootBack)
    }
}

/// Registers a popup with the host and carries the palette of the registering view over to the host's layer
/// (an outside app keeps its colours in its popups).
struct HostedPopupModifier<Card: View>: ViewModifier {
    @Environment(\.popupHost) private var host
    @Environment(\.outsidePalette) private var palette
    @Environment(\.insideCard) private var insideCard
    @Environment(\.markerBudget) private var markerBudget
    @Environment(\.markerPageActive) private var markerPageActive
    @Environment(\.tabBarClearance) private var tabBarClearance
    @Environment(\.openHire) private var openHire
    @Environment(\.hidesRootBack) private var hidesRootBack
    var key: String
    var priority: PopupPriority
    var active: Bool
    var draw: PopupDraw
    var onClose: () -> Void
    var onDismiss: (() -> Void)?
    var card: () -> Card

    init(key: String, priority: PopupPriority, active: Bool, draw: PopupDraw, onClose: @escaping () -> Void, onDismiss: (() -> Void)?, card: @escaping () -> Card) {
        self.key = key
        self.priority = priority
        self.active = active
        self.draw = draw
        self.onClose = onClose
        self.onDismiss = onDismiss
        self.card = card
    }

    func body(content view: Content) -> some View {
        let p: OutsidePalette = palette
        let make: () -> Card = card
        let carried: PopupCarriedEnvironment = PopupCarriedEnvironment(insideCard: insideCard, markerBudget: markerBudget, markerPageActive: markerPageActive,
                                                                       tabBarClearance: tabBarClearance, openHire: openHire, hidesRootBack: hidesRootBack)
        return view.background(
            PopupRegistration(host: host, key: key, priority: priority, active: active, draw: draw,
                              content: { AnyView(make().environment(\.outsidePalette, p).modifier(carried)) },
                              onClose: onClose, onDismiss: onDismiss)
        )
    }
}

extension View {
    /// Inside a `.sheet` that can raise popups: its own popups (and those of the host above) are drawn over the sheet, not under it.
    func popupHost() -> some View { modifier(PopupHostModifier()) }

    /// Registers a popup that draws its own complete card (a `GamePopup`, a report) with the host while `active`.
    func hostedPopup<Content: View>(key: String, priority: PopupPriority, active: Bool, onClose: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(HostedPopupModifier(key: key, priority: priority, active: active, draw: .raw, onClose: onClose, onDismiss: nil, card: content))
    }
}
