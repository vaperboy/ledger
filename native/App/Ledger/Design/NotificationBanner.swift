import SwiftUI
import GameCore
import Simulation

// iOS-style notification banners: the one way the game tells the player something without a blocking popup.
// A rounded translucent card below the status bar, slides down with a spring, swipes up to leave. One at a time, the most severe
// first; it waits while a report or any popup is open. No game rules here.

/// What a tap on a banner does.
enum BannerTarget {
    /// Nothing to open: the tap just closes the banner.
    case none
    /// A decision (an open Inbox message with options) the owner can answer right there, in the decision popup.
    case message(Int)
    /// A place in the app: the tap goes straight there (no question). The name is only a label.
    case place(String, () -> Void)
}

/// One banner. `severity` is the 1 to 5 level of the delegation rules; 4 and 5, and every alert, stay until swiped away or acted on.
struct BannerItem: Identifiable {
    let id = UUID()
    /// Dedupe key: a second banner with the same key replaces the first.
    var key: String
    var source: String
    var title: String
    var body: String = ""
    var glyph: String
    var severity: Int = 1
    var isAlert = false
    /// True for a banner that mirrors a standing alert (it leaves when the alert is gone).
    var fromAlert = false
    var lifetime: Double = 5
    var target: BannerTarget = .none

    var sticky: Bool { severity >= 4 || isAlert }
    var tint: Color { isAlert ? Theme.alert : Theme.gold }
}

/// The "Take me to ...?" question after a tap on a banner that has no decision of its own.
struct BannerConfirm: Identifiable {
    let id = UUID()
    var place: String
    var go: () -> Void
}

/// The banner queue: at most one on screen (`current`), the rest wait in `pending`, most severe first.
@MainActor
final class BannerQueue: ObservableObject {
    @Published private(set) var current: BannerItem?
    @Published private(set) var pending: [BannerItem] = []
    @Published var confirm: BannerConfirm?
    /// Alert keys already announced, so a standing alert is shown once and again only after it went away.
    private var announced: Set<String> = []

    var hasPending: Bool { !pending.isEmpty }

    /// Adds a banner; one with the same key (or the same words) replaces what is waiting instead of piling up.
    func post(_ item: BannerItem) {
        if let c = current, c.key == item.key { return }
        pending.removeAll { (p: BannerItem) -> Bool in p.key == item.key }
        pending.append(item)
        pending = pending.enumerated().sorted { (a: (offset: Int, element: BannerItem), b: (offset: Int, element: BannerItem)) -> Bool in
            a.element.severity != b.element.severity ? a.element.severity > b.element.severity : a.offset < b.offset
        }.map { $0.element }
    }

    /// Shows the next waiting banner (the layer calls this when nothing blocks).
    func advance() {
        guard current == nil, !pending.isEmpty else { return }
        current = pending.removeFirst()
    }

    func dismiss(_ id: UUID) { if current?.id == id { current = nil } }

    /// Standing alerts: announces new ones once, and withdraws banners of alerts that are gone.
    func sync(alerts: [BannerItem]) {
        let live: Set<String> = Set(alerts.map { $0.key })
        pending.removeAll { (p: BannerItem) -> Bool in p.fromAlert && !live.contains(p.key) }
        if let c = current, c.fromAlert, !live.contains(c.key) { current = nil }
        announced = announced.intersection(live)
        for a in alerts where !announced.contains(a.key) { announced.insert(a.key); post(a) }
    }

    func reset() { current = nil; pending = []; confirm = nil; announced = [] }
}

extension GameStore {
    /// A low-severity banner for ordinary feedback ("Dividend paid", "Payment received"): 3 s, no tap action.
    func banner(_ title: String, body: String = "", source: String = "Ledger", glyph: String = Glyph.check) {
        banners.post(BannerItem(key: "note-" + title + body, source: source, title: title.tidyText, body: body.tidyText, glyph: glyph, severity: 1, lifetime: 3))
    }
}

/// The banner layer: sits over the whole app, takes taps only on the card (and the question popup).
struct NotificationBannerLayer: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject var queue: BannerQueue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct PumpKey: Equatable { var blocked: Bool; var hasPending: Bool; var hasCurrent: Bool }

    /// A report, the daily report, a reward, a day running or any popup: banners wait until it is closed.
    private var blocked: Bool {
        store.holdsHomeFigures || !store.notices.isEmpty || store.decisionPopup != nil || !store.redAlerts.isEmpty || queue.confirm != nil
    }

    private var slide: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.85) }

    var body: some View {
        let key = PumpKey(blocked: blocked, hasPending: queue.hasPending, hasCurrent: queue.current != nil)
        ZStack(alignment: .top) {
            if store.engine != nil, let item = queue.current {
                BannerCard(item: item, reduceMotion: reduceMotion, onTap: { tapped(item) }, onClose: { close(item) })
                    .id(item.id)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
            if let c = queue.confirm { confirmPopup(c) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(slide, value: queue.current?.id)
        .task(id: key) {
            if key.blocked || key.hasCurrent || !key.hasPending { return }
            try? await Task.sleep(nanoseconds: 450_000_000)
            if Task.isCancelled { return }
            withAnimation(slide) { queue.advance() }
        }
        .onAppear { syncAlerts() }
        .onChange(of: store.engine == nil) { _, gone in if gone { queue.reset() } else { syncAlerts() } }
        .onChange(of: store.engine != nil ? store.phoneAlerts : []) { _, _ in syncAlerts() }
    }

    private func close(_ item: BannerItem) { withAnimation(slide) { queue.dismiss(item.id) } }

    private func tapped(_ item: BannerItem) {
        Haptics.tap()
        withAnimation(slide) { queue.dismiss(item.id) }
        switch item.target {
        case .none: break
        case .message(let id): store.decisionPopup = id
        case .place(_, let go): go()
        }
    }

    private func confirmPopup(_ c: BannerConfirm) -> some View {
        GamePopup(title: "Take me to \(c.place)?", showsClose: false, onClose: { queue.confirm = nil }) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                QuietButton(title: "Not now") { queue.confirm = nil }
                Button("Go there") { Haptics.tap(); queue.confirm = nil; c.go() }
                    .buttonStyle(ImportantButtonStyle()).accessibilityIdentifier("banner-go")
            }
        }
        .transition(.opacity)
    }

    /// Reads the Phone's standing alerts (payroll, weather, open decisions) into banners.
    private func syncAlerts() {
        guard let e = store.engine else { return }
        let s: GameStore = store
        var out: [BannerItem] = []
        for a in store.phoneAlerts {
            var item = BannerItem(key: "alert-" + a.id, source: a.source, title: a.title, body: a.detail, glyph: a.app.glyph)
            item.fromAlert = true
            if a.messageID != 0, let m = e.state.inbox.first(where: { $0.id == a.messageID }) {
                item.severity = e.severityLevel(of: m)
                item.isAlert = m.isAlert || m.tone == "bad"
                if m.status == "open" && !m.options.isEmpty { item.target = .message(m.id) }
                else { let id = m.id; item.target = .place("the Inbox", { s.openMessage(id) }) }
            } else if a.app == .accounting && a.companyID != 0 {
                // Payroll that needs the owner: the most urgent kind, stays until acted on.
                item.severity = 5
                item.isAlert = true
                let cid: Int = a.companyID
                if let m = e.state.inbox.first(where: { $0.status == "open" && $0.companyID == cid && $0.actionID.hasPrefix("pay29") && !$0.options.isEmpty }) {
                    item.target = .message(m.id)
                } else {
                    item.target = .place("Accounting payroll", { s.openAccounting(companyID: cid, payroll: true) })
                }
            } else {
                item.severity = 3
                let app: PhoneApp = a.app
                item.target = .place(a.source, { s.openApp(app) })
            }
            out.append(item)
        }
        queue.sync(alerts: out)
    }
}

/// One banner card: follows the finger, flies up on a swipe, closes itself after its lifetime unless it is sticky.
private struct BannerCard: View {
    var item: BannerItem
    var reduceMotion: Bool
    var onTap: () -> Void
    var onClose: () -> Void
    @State private var drag: CGFloat = 0

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            GlyphView(glyph: item.glyph, size: 18, weight: 1.6, tint: item.tint)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(hex: 0x1C1D1F)))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(item.tint.opacity(0.45), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.source).textCase(.uppercase).font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 0)
                    Text("now").font(.system(size: 11))
                }
                .foregroundStyle(Theme.ivoryFaint)
                Text(item.title).font(.system(size: 14.5, weight: .bold)).foregroundStyle(Theme.ivory)
                    .lineLimit(2).multilineTextAlignment(.leading)
                if !item.body.isEmpty {
                    Text(item.body).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: 460, alignment: .leading)
        .background(ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color(hex: 0x1E1F21, opacity: 0.7))
            if item.isAlert { shape.fill(Theme.alert.opacity(0.10)) }
        })
        .overlay(shape.strokeBorder(item.isAlert ? Theme.alert.opacity(0.55) : Color(hex: 0x3A3B3E), lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .padding(.horizontal, 12).padding(.top, 6)
        .offset(y: drag)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { (v: DragGesture.Value) in drag = v.translation.height < 0 ? v.translation.height : v.translation.height / 8 }
                .onEnded { (v: DragGesture.Value) in
                    if v.translation.height < -28 || v.velocity.height < -350 {
                        withAnimation(.easeIn(duration: 0.2)) { drag = -320 }
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 190_000_000)
                            onClose()
                        }
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { drag = 0 }
                    }
                }
        )
        .task(id: item.id) {
            guard !item.sticky else { return }
            try? await Task.sleep(nanoseconds: UInt64(item.lifetime * 1_000_000_000))
            if Task.isCancelled { return }
            onClose()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Dismiss") { onClose() }
        .accessibilityIdentifier("notification-banner")
    }
}
