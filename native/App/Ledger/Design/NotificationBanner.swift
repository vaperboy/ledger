import SwiftUI
import GameCore
import Simulation

// Banners and toasts: the one way the game tells the player something without a blocking popup. A banner is a card below the
// status bar (source, title, body); a toast is the compact form for any notification (a result, a warning, "Chosen: Agree"), tinted by its tone,
// gone after 2.5 s, at most two at once, tap or swipe up to leave, and never held back by a popup. A banner waits while a report or a blocking popup is open. No game rules here.

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
    /// A toast: one compact line coloured by `tone` ("n", "good", "warn", "bad"), never sticky.
    var compact = false
    var tone = "n"

    var sticky: Bool { !compact && (severity >= 4 || isAlert) }
    var tint: Color {
        if isAlert { return Theme.alert }
        if compact && tone != "n" { return Theme.tone(tone) }
        return Theme.gold
    }
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
    /// Toasts on screen, oldest first: at most `maxToasts`, shown at once and never held back by a popup.
    @Published private(set) var toasts: [BannerItem] = []
    static let maxToasts = 2
    @Published var confirm: BannerConfirm?
    /// Alert keys already announced, so a standing alert is shown once and again only after it went away.
    private var announced: Set<String> = []

    var hasPending: Bool { !pending.isEmpty }

    /// Adds a banner; one with the same key (or the same words) replaces what is waiting instead of piling up.
    func post(_ item: BannerItem) {
        // A toast is the answer to something the player just did: it shows at once, beside any banner, and the oldest leaves at the third.
        if item.compact {
            toasts.removeAll { (t: BannerItem) -> Bool in t.key == item.key }
            toasts.append(item)
            if toasts.count > Self.maxToasts { toasts.removeFirst(toasts.count - Self.maxToasts) }
            return
        }
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

    func dismiss(_ id: UUID) {
        if current?.id == id { current = nil }
        toasts.removeAll { (t: BannerItem) -> Bool in t.id == id }
    }

    /// Standing alerts: announces new ones once, and withdraws banners of alerts that are gone.
    func sync(alerts: [BannerItem]) {
        let live: Set<String> = Set(alerts.map { $0.key })
        pending.removeAll { (p: BannerItem) -> Bool in p.fromAlert && !live.contains(p.key) }
        if let c = current, c.fromAlert, !live.contains(c.key) { current = nil }
        announced = announced.intersection(live)
        for a in alerts where !announced.contains(a.key) { announced.insert(a.key); post(a) }
    }

    func reset() { current = nil; pending = []; toasts = []; confirm = nil; announced = [] }
}

extension GameStore {
    /// Ordinary feedback ("Dividend paid", "Payment received"): a good-tone toast; a body is joined to the title.
    func banner(_ title: String, body: String = "", source: String = "Ledger", glyph: String = Glyph.check) {
        notify(body.isEmpty ? title : title + ". " + body, tone: "good")
    }

    /// The one notification channel: a result, warning or news line told in a small top toast that leaves by itself.
    /// Tone "good", "warn", "bad" or "n" (info).
    func notify(_ text: String, tone: String = "warn") {
        let line: String = text.tidyText
        let glyph: String = tone == "good" ? Glyph.check : (tone == "n" ? Glyph.info : Glyph.warning)
        banners.post(BannerItem(key: "toast-" + line, source: "", title: line, glyph: glyph,
                                severity: 3, lifetime: Motion.toastSeconds, compact: true, tone: tone))
    }

    /// Confirms the player's answer at the top of the screen: "Chosen: Agree".
    func chose(_ label: String) {
        let l: String = label.tidyText
        if l.isEmpty { return }
        notify("Chosen: " + l, tone: "n")
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
        store.holdsHomeFigures || store.popupOpen || queue.confirm != nil
    }

    private var slide: Animation { reduceMotion ? Motion.quickAnimation : Motion.moveAnimation }

    var body: some View {
        let key = PumpKey(blocked: blocked, hasPending: queue.hasPending, hasCurrent: queue.current != nil)
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if store.engine != nil {
                    ForEach(queue.toasts) { (item: BannerItem) in
                        BannerCard(item: item, reduceMotion: reduceMotion, onTap: { tapped(item) }, onClose: { close(item) })
                            .id(item.id)
                            .transition(Motion.toastTransition(reduceMotion))
                    }
                    if let item = queue.current {
                        BannerCard(item: item, reduceMotion: reduceMotion, onTap: { tapped(item) }, onClose: { close(item) })
                            .id(item.id)
                            .transition(Motion.toastTransition(reduceMotion))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .hostedPopup(key: "banner-confirm", priority: .confirm, active: queue.confirm != nil, onClose: { queue.confirm = nil }) {
            if let c = queue.confirm { confirmPopup(c) }
        }
        .animation(slide, value: queue.current?.id)
        .animation(slide, value: queue.toasts.map { $0.id })
        .task(id: key) {
            if key.blocked || key.hasCurrent || !key.hasPending { return }
            let gap: Double = Motion.bannerGapSeconds
            try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000))
            if Task.isCancelled { return }
            Motion.animate(slide) { queue.advance() }
        }
        .onAppear { syncAlerts() }
        .onChange(of: store.engine == nil) { _, gone in if gone { queue.reset() } else { syncAlerts() } }
        .onChange(of: store.engine != nil ? store.phoneAlerts : []) { _, _ in syncAlerts() }
    }

    private func close(_ item: BannerItem) { Motion.animate(slide) { queue.dismiss(item.id) } }

    private func tapped(_ item: BannerItem) {
        Haptics.tap()
        Motion.animate(slide) { queue.dismiss(item.id) }
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
                item.isAlert = m.isAlert
                if m.status == "open" && !m.options.isEmpty { item.target = .message(m.id) }
                else { let id = m.id; item.target = .place("the Inbox", { s.openMessage(id) }) }
            } else if a.app == .accounting && a.companyID != 0 {
                // Payroll only the owner can approve: a toast and a standing alert, not a sticky banner.
                item.severity = 3
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

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous) }

    /// The compact line of a toast: a small accent glyph and the sentence.
    private var toastLine: some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            LedgerGlyph(glyph: item.glyph, size: Theme.Icon.small, tint: item.tint)
            Text(item.title).textStyle(.headline)
                .lineLimit(3).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }

    private var full: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            LedgerGlyph(glyph: item.glyph, size: Theme.Icon.medium, tint: item.tint)
                .frame(width: Theme.Icon.large, height: 38)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                HStack {
                    Text(item.source).textCase(.uppercase).textStyle(.caption, tint: Theme.inkFaint, weight: .medium)
                    Spacer(minLength: 0)
                    Text("now").textStyle(.caption, tint: Theme.inkFaint)
                }
                Text(item.title).textStyle(.headline)
                    .lineLimit(2).multilineTextAlignment(.leading)
                if !item.body.isEmpty {
                    Text(item.body).textStyle(.body, tint: Theme.inkSoft)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
            }
        }
    }

    var body: some View {
        Group { if item.compact { toastLine } else { full } }
        .padding(.horizontal, 14).padding(.vertical, item.compact ? 10 : 12)
        .frame(maxWidth: 460, alignment: .leading)
        .background(ZStack {
            shape.fill(Theme.surfaceRaised)
            if item.isAlert { shape.fill(Theme.alert.opacity(0.10)) }
        })
        .overlay(shape.strokeBorder(item.isAlert ? item.tint.opacity(0.55) : Theme.line, lineWidth: item.isAlert ? 1 : 0.5))
        .environment(\.colorScheme, .dark)
        .elevation(.raised)
        .padding(.horizontal, 12).padding(.top, 6)
        .offset(y: drag)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { (v: DragGesture.Value) in drag = v.translation.height < 0 ? v.translation.height : v.translation.height / 8 }
                .onEnded { (v: DragGesture.Value) in
                    if v.translation.height < -28 || v.velocity.height < -350 {
                        Motion.animate(Motion.quickAnimation) { drag = -320 }
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: UInt64(Motion.bannerLeaveSeconds * 1_000_000_000))
                            onClose()
                        }
                    } else {
                        Motion.animate(Motion.moveAnimation) { drag = 0 }
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
