import SwiftUI
import GameCore
import Countries
import Events
import Simulation

/// What the player must read or decide is a popup on the main screen: the notice queue (a refusal or a serious problem), the outcome of
/// an answered decision, a top-priority decision, the daily report, the week, month and year reports and the rewards. Plain information
/// goes to its own page, never to a popup or banner. This view only REGISTERS the popups with the app's popup host (see `PopupHost`, `PopupPriority`):
/// the host draws them, one at a time, in the order confirm, decision, alert (error, red alert, notice), report and daily, reward and
/// feature unlock, panel.
struct PopupLayer: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .hostedPopup(key: "error", priority: .alert, active: store.errorText != nil, onClose: { store.errorText = nil }) {
                ErrorPopup(text: store.errorText ?? "") { store.errorText = nil }
            }
            .hostedPopup(key: "decision-\(store.decisionPopup ?? 0)", priority: .decision, active: store.decisionPopup != nil, onClose: { store.decisionPopup = nil }) {
                DecisionPopup(messageID: store.decisionPopup ?? 0).environmentObject(store)
            }
            .hostedPopup(key: "alert-\(store.redAlerts.first?.id ?? 0)", priority: .alert, active: !store.redAlerts.isEmpty, onClose: { }) {
                if let a = store.redAlerts.first { RedAlertPopup(message: a).environmentObject(store) }
            }
            .hostedPopup(key: "notice-\(store.toast?.id.uuidString ?? "")", priority: .notice, active: store.toast != nil, onClose: { store.dismissNotice() }) {
                if let n = store.toast { NoticePopup(notice: n).environmentObject(store) }
            }
            .hostedPopup(key: "outcome-\(store.outcomes.first?.id.uuidString ?? "")", priority: .notice, active: !store.outcomes.isEmpty, onClose: { store.dismissOutcome() }) {
                if let n = store.outcomes.first { OutcomePopup(note: n).environmentObject(store) }
            }
            .hostedPopup(key: "report-\(store.reportSheet?.reportID ?? 0)", priority: .report, active: store.reportSheet != nil, onClose: { }) {
                if let r = store.reportSheet { ReportDigestSheet(digest: r).environmentObject(store) }
            }
            .hostedPopup(key: "daily", priority: .report, active: store.dailySheet != nil && store.reportSheet == nil, onClose: { }) {
                if let d = store.dailySheet { DailyReportPopup(digest: d).environmentObject(store) }
            }
            .hostedPopup(key: "celebration-\(store.celebrationQueue.first?.id ?? 0)", priority: .celebration, active: !store.celebrationQueue.isEmpty, onClose: { }) {
                if let c = store.celebrationQueue.first { CelebrationPopup(item: c).environmentObject(store) }
            }
            .modifier(unlockRegistration)
    }

    /// The announcement of a newly opened feature: an announcement like a reward (not a panel the player opened), shown only when
    /// nothing else is waiting; closing it counts as Skip.
    private var unlockRegistration: HostedPopupModifier<AnyView> {
        let ready: UnlockPrompt? = store.unlockReady
        let s: GameStore = store
        return HostedPopupModifier(key: "unlock-" + (ready?.id ?? ""), priority: .celebration, active: ready != nil,
                                   draw: .card(title: "", size: .fit),
                                   onClose: { if let p = s.unlockReady { s.dismissUnlock(p) } }, onDismiss: nil,
                                   card: { () -> AnyView in
                                       guard let p = s.unlockReady else { return AnyView(EmptyView()) }
                                       return AnyView(UnlockPopup(prompt: p).environmentObject(s))
                                   })
    }
}

/// An error told in the same in-game popup as every question, not in an iOS alert.
struct ErrorPopup: View {
    var text: String
    var onClose: () -> Void

    var body: some View {
        GamePopup(title: "Something went wrong", showsClose: false, category: .compact, tone: .danger, icon: "exclamationmark.triangle", onClose: onClose) {
            PopupBody {
                Text(text).popupText(.body)
                PopupOptionButton(title: "Close", highlighted: true, identifier: "error-ok", action: onClose)
            }
        }
    }
}

/// One notice from `GameStore.tell` / `show`: what happened, and a single OK.
struct NoticePopup: View {
    @EnvironmentObject var store: GameStore
    var notice: Toast

    private var heading: String {
        if !notice.title.isEmpty { return notice.title }
        return notice.tone == "bad" ? "Problem" : "Notice"
    }

    var body: some View {
        if notice.style == "luxury" { luxury } else if notice.style == "recap" { recap } else { plain }
    }

    /// The card shown on coming back: what changed while the player was away, one line each.
    private var recap: some View {
        GamePopup(title: notice.title, showsClose: false, category: .compact, tone: .info, icon: "clock", onClose: { store.dismissNotice() }) {
            PopupBody {
                ForEach(notice.text.split(separator: "\n").map { String($0) }, id: \.self) { line in
                    Text(line).popupText(.body).fixedSize(horizontal: false, vertical: true)
                }
                PopupOptionButton(title: "Continue", highlighted: true, identifier: "recap-ok") { store.dismissNotice() }
            }
        }
    }

    /// A high-value purchase: a gold-edged card whose edge draws round while it fades in (variant: reward).
    private var luxury: some View {
        GamePopup(title: "Acquired", showsClose: false, variant: .reward, category: .compact, tone: .prestige, icon: "crown", onClose: { store.dismissNotice() }) {
            PopupBody {
                GoldReveal {
                    VStack(spacing: 6) {
                        GoldRingMark(glyph: Glyph.achievements, size: 52)
                        Text(notice.title).popupText(.figure, variant: .reward).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        Text(notice.subtitle).popupText(.subtitle)
                        if let price = notice.rows.first { Text(price.tidyMoney).popupText(.rowValue) }
                    }
                }
                PopupOptionButton(title: "Done", highlighted: true, identifier: "notice-ok") { store.dismissNotice() }
            }
        }
    }

    private var plain: some View {
        GamePopup(title: heading, showsClose: false, category: .compact, tone: .danger, icon: "exclamationmark.triangle", onClose: { store.dismissNotice() }) {
            PopupBody {
                if !notice.text.isEmpty { Text(notice.text.tidyMoney).popupText(.body) }
                PopupOptionButton(title: "Done", highlighted: true, identifier: "notice-ok") { store.dismissNotice() }
            }
        }
    }
}

/// The one small popup after a decision was answered or an action confirmed: what was chosen and what came of it, one OK. Fed by
/// `GameStore.outcome(chosen:result:)`; queued, so only one shows at a time.
struct OutcomePopup: View {
    @EnvironmentObject var store: GameStore
    var note: OutcomeNote

    /// "Done: X" already says what was chosen, so the chosen line is left out then.
    private var showsChoice: Bool { note.result != "Done: " + note.chosen }
    private var lines: [String] { note.result.split(separator: "\n").map { String($0) } }

    var body: some View {
        GamePopup(title: "Done", showsClose: false, category: .compact, tone: .success, icon: "checkmark", onClose: { store.dismissOutcome() }) {
            PopupBody {
                if showsChoice { Text("You chose: " + note.chosen).popupText(.title).fixedSize(horizontal: false, vertical: true) }
                ForEach(Array(lines.enumerated()), id: \.offset) { (pair: (offset: Int, element: String)) in
                    Text(pair.element.tidyMoney).popupText(.body).fixedSize(horizontal: false, vertical: true)
                }
                PopupOptionButton(title: "OK", highlighted: true, identifier: "outcome-ok") { store.dismissOutcome() }
            }
        }
    }
}

/// A decision from Home's Needs you, answered where the player is: the message, every option with what it does, and the same
/// "Are you sure" rule as the Inbox. The outcome is one small popup after it.
struct DecisionPopup: View {
    @EnvironmentObject var store: GameStore
    var messageID: Int
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let m = e.state.inbox.first(where: { $0.id == messageID }), m.status == "open" {
                card(e, m)
            } else {
                Color.clear.frame(width: 0, height: 0).onAppear { store.decisionPopup = nil }
            }
        }
        .confirmAction($pending)
    }

    private func card(_ e: GameEngine, _ m: Message) -> some View {
        GamePopup(title: e.displayText(m.title, companyID: m.companyID), showsClose: true, category: .medium, tone: .warning, onClose: { store.decisionPopup = nil }) {
            content(e, m)
        }
    }

    private func content(_ e: GameEngine, _ m: Message) -> some View {
        PopupBody {
            let intro: String = e.displayText(m.body, companyID: m.companyID)
            if !intro.isEmpty { Text(intro.tidyMoney).popupText(.subtitle) }
            ForEach(Array(m.options.enumerated()), id: \.offset) { pair in
                optionRow(e, m, pair.offset, pair.element)
            }
        }
    }

    private func optionRow(_ e: GameEngine, _ m: Message, _ index: Int, _ opt: JSONValue) -> some View {
        let label: String = e.displayText(opt["l"].string, companyID: m.companyID)
        let detail: String = e.displayText(opt["d"].string, companyID: m.companyID)
        let lines: [String] = MessageCard.preview(e, m, opt)
        return VStack(alignment: .leading, spacing: PopupSpace.tight) {
            PopupOptionButton(title: label) { choose(e, m, index) }
            if !detail.isEmpty { Text(detail.tidyMoney).popupText(.caption) }
            ForEach(lines, id: \.self) { line in
                Text(line.tidyMoney).popupText(.effect)
            }
        }
    }

    /// The same rule as the Inbox, shared with Home's inline answers (`DecisionAnswering`).
    private func choose(_ e: GameEngine, _ m: Message, _ index: Int) {
        DecisionAnswering.choose(store, e, m, index, ask: { (a: PendingAction) in pending = a }, done: { store.decisionPopup = nil })
    }
}

/// Answers an open decision from anywhere (the popup, Home's card): a routine answer goes at once; an irreversible one, or a spend above
/// the player's size, is asked first. The outcome is the one outcome popup (`store.outcome`).
enum DecisionAnswering {
    @MainActor static func choose(_ store: GameStore, _ e: GameEngine, _ m: Message, _ index: Int,
                                  ask: @escaping (PendingAction) -> Void, done: @escaping () -> Void) {
        guard m.options.indices.contains(index) else { return }
        let opt: JSONValue = m.options[index]
        let label: String = e.displayText(opt["l"].string, companyID: m.companyID)
        let need: DecisionConfirmation = DecisionConfirm.confirmation(for: m, option: index)
        guard need.needsQuestion else { send(store, e, m, index, label, done); return }
        var lines: [String] = []
        let d: String = e.displayText(opt["d"].string, companyID: m.companyID)
        if !d.isEmpty { lines.append(d) }
        lines += MessageCard.preview(e, m, opt)
        if index == 0 || m.options.count == 1 { lines += e.messageFacts(m) }
        let company: Company? = m.companyID != 0 ? e.state.company(m.companyID) : nil
        let place: String = company?.name ?? ""
        let fallback: String = e.displayText(m.title, companyID: m.companyID)
        var action = MessageCard.answerConfirm(title: label + (place.isEmpty ? "" : " · " + place), message: lines.isEmpty ? fallback : lines.joined(separator: "\n"),
                                               button: label, need: need) { send(store, e, m, index, label, done) }
        if !need.irreversible, let amount = need.amount {
            action.amount = amount
            action.currency = company.map { e.currency(for: $0) } ?? e.homeCurrency
        }
        if ConfirmThreshold.skips(action) { send(store, e, m, index, label, done); return }
        ask(action)
    }

    @MainActor private static func send(_ store: GameStore, _ e: GameEngine, _ m: Message, _ index: Int, _ label: String, _ done: () -> Void) {
        var effects: [String] = m.options.indices.contains(index) ? MessageCard.preview(e, m, m.options[index]) : []
        if effects.isEmpty, m.options.indices.contains(index) {
            let d: String = e.displayText(m.options[index]["d"].string, companyID: m.companyID)
            if !d.isEmpty { effects = [d] }
        }
        let ok: Bool = store.act { $0.answer(messageID: m.id, option: index) } ?? false
        done()
        store.announceAnswer(label: label, effects: effects, ok: ok, messageTitle: m.title, companyID: m.companyID)
    }
}

/// A company about to be force-sold: a red alert in the shared popup frame (variant: alert), drawn with the alert token. Tapping
/// outside does nothing; the player has to read it and press Continue.
struct RedAlertPopup: View {
    @EnvironmentObject var store: GameStore
    var message: Message

    var body: some View {
        GamePopup(title: "About to be sold", showsClose: false, dismissOnBackdrop: false, variant: .alert, category: .compact, tone: .danger, icon: "exclamationmark.octagon", onClose: { }) {
            PopupBody {
                HStack(spacing: 10) {
                    GlyphView(glyph: Glyph.warning, size: 24, weight: 1.8, tint: Theme.alert)
                    Text(store.engine?.displayText(message.title, companyID: message.companyID) ?? message.title)
                        .popupText(.title).fixedSize(horizontal: false, vertical: true)
                }
                Text((store.engine?.displayText(message.body, companyID: message.companyID) ?? message.body).tidyMoney)
                    .popupText(.body)
                if message.companyID != 0 {
                    PopupOptionButton(title: "Open the company") {
                        store.dismissRedAlert(); store.openCompany(message.companyID, section: nil)
                    }
                }
                PopupOptionButton(title: "Continue", highlighted: true, identifier: "alert-continue") { store.dismissRedAlert() }
            }
        }
    }
}
