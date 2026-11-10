import SwiftUI
import UIKit
import Combine

enum PopupDraw {
    case card(title: String, size: CenterSheetSize, category: PopupCategory? = nil, tone: PopupTone? = nil, palette: OutsidePalette? = nil)
    case raw
}

struct PopupEntry {
    var key: String
    var seq: Int
    var priority: PopupPriority
    var draw: PopupDraw
    var content: () -> AnyView
    var onClose: () -> Void
    var item: PopupQueue.Item { PopupQueue.Item(key: key, priority: priority, seq: seq) }
}

final class PopupHost: ObservableObject {
    private static var counter = 0

    @Published private(set) var entries: [String: PopupEntry] = [:]
    @Published private(set) var claims = 0
    private(set) weak var parentHost: PopupHost?
    private var holdsClaim = false
    private var parentLink: AnyCancellable?

    func claim() { claims += 1 }
    func release() { claims = max(0, claims - 1) }

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

    func gathered() -> [PopupEntry] {
        Array(entries.values) + (parentHost?.gathered() ?? [])
    }

    func drawnEntries() -> [PopupEntry] {
        claims > 0 ? [] : gathered()
    }

    private static func nextSeq() -> Int { counter += 1; return counter }

    func upsert(key: String, priority: PopupPriority, draw: PopupDraw, content: @escaping () -> AnyView, onClose: @escaping () -> Void) {
        let seq: Int = entries[key]?.seq ?? PopupHost.nextSeq()
        entries[key] = PopupEntry(key: key, seq: seq, priority: priority, draw: draw, content: content, onClose: onClose)
    }

    var hasVisible: Bool { !drawnEntries().isEmpty }

    func remove(_ key: String) {
        if entries[key] != nil { entries[key] = nil }
    }
}

private struct PopupHostKey: EnvironmentKey { static let defaultValue: PopupHost? = nil }
extension EnvironmentValues {
    var popupHost: PopupHost? {
        get { self[PopupHostKey.self] }
        set { self[PopupHostKey.self] = newValue }
    }
}

private struct OutcomeStoreKey: EnvironmentKey { static let defaultValue: GameStore? = nil }
extension EnvironmentValues {
    var outcomeStore: GameStore? {
        get { self[OutcomeStoreKey.self] }
        set { self[OutcomeStoreKey.self] = newValue }
    }
}

private struct PopupCloseKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }
extension EnvironmentValues {
    var popupClose: (() -> Void)? {
        get { self[PopupCloseKey.self] }
        set { self[PopupCloseKey.self] = newValue }
    }
}

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
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: signature)
    }

    @ViewBuilder private func entryView(_ e: PopupEntry) -> some View {
        entryBody(e).environment(\.popupPriority, e.priority)
    }

    @ViewBuilder private func entryBody(_ e: PopupEntry) -> some View {
        switch e.draw {
        case .card(let title, let size, let category, let tone, let palette):
            if let palette {
                CenterSheetFrame(onClose: e.onClose, title: title, size: size, category: category, tone: tone) { e.content().environment(\.popupClose, e.onClose) }
                    .environment(\.outsidePalette, palette)
            } else {
                CenterSheetFrame(onClose: e.onClose, title: title, size: size, category: category, tone: tone) { e.content().environment(\.popupClose, e.onClose) }
            }
        case .raw:
            e.content().environment(\.popupClose, e.onClose)
        }
    }
}

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
        var drawn: PopupDraw = draw
        if case .card(let t, let s, let c, let tn, _) = draw { drawn = .card(title: t, size: s, category: c, tone: tn, palette: p) }
        return view.background(
            PopupRegistration(host: host, key: key, priority: priority, active: active, draw: drawn,
                              content: { AnyView(make().environment(\.outsidePalette, p).modifier(carried)) },
                              onClose: onClose, onDismiss: onDismiss)
        )
    }
}

extension View {
    func popupHost() -> some View { modifier(PopupHostModifier()) }

    func hostedPopup<Content: View>(key: String, priority: PopupPriority, active: Bool, onClose: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(HostedPopupModifier(key: key, priority: priority, active: active, draw: .raw, onClose: onClose, onDismiss: nil, card: content))
    }
}
