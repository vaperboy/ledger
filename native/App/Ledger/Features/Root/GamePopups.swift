import SwiftUI
import GameCore
import Countries
import Events
import Simulation

/// Everything the game tells the player in words is a popup on the main screen, never a banner: the notice queue (a refusal, a warning,
/// the outcome of an answer), a top-priority decision, the short daily report and the week, month and year reports. They sit in
/// `RootView`'s overlay, one at a time, the most urgent on top.
struct PopupLayer: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        ZStack {
            if let r = store.reportSheet { ReportDigestSheet(digest: r).id(r.reportID).transition(.opacity) }
            else if let d = store.dailySheet { DailyReportPopup(digest: d).transition(.opacity) }
            if let id = store.decisionPopup { DecisionPopup(messageID: id).id(id).transition(.opacity) }
            if let n = store.toast { NoticePopup(notice: n).id(n.id).transition(.opacity) }
        }
    }
}

/// One notice from `GameStore.tell` / `show`: what happened, and a single OK.
struct NoticePopup: View {
    @EnvironmentObject var store: GameStore
    var notice: Toast

    private var heading: String {
        if !notice.title.isEmpty { return notice.title }
        return notice.tone == "bad" ? "Problem" : "Please note"
    }

    var body: some View {
        GamePopup(title: heading, showsClose: false, onClose: { store.dismissNotice() }) {
            VStack(alignment: .leading, spacing: 12) {
                if !notice.text.isEmpty {
                    Text(notice.text.tidyMoney).font(.system(size: 14)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer(minLength: 0)
                    Button("OK") { Haptics.tap(); store.dismissNotice() }
                        .buttonStyle(ImportantButtonStyle()).accessibilityIdentifier("notice-ok")
                }
            }
        }
    }
}

/// A decision from Home's top priorities, answered where the player is: the message, every option with what it does, and the same
/// "Are you sure" rule as the Inbox. The result is told in a notice popup.
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
        GamePopup(title: e.displayText(m.title, companyID: m.companyID), showsClose: true, onClose: { store.decisionPopup = nil }) {
            ViewThatFits(in: .vertical) {
                content(e, m)
                ScrollView { content(e, m) }.scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxHeight: 460)
        }
    }

    private func content(_ e: GameEngine, _ m: Message) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let intro: String = e.displayText(m.body, companyID: m.companyID)
            if !intro.isEmpty { Text(intro.tidyMoney).font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) }
            ForEach(Array(m.options.enumerated()), id: \.offset) { pair in
                optionRow(e, m, pair.offset, pair.element)
            }
        }
    }

    private func optionRow(_ e: GameEngine, _ m: Message, _ index: Int, _ opt: JSONValue) -> some View {
        let label: String = e.displayText(opt["l"].string, companyID: m.companyID)
        let detail: String = e.displayText(opt["d"].string, companyID: m.companyID)
        let lines: [String] = MessageCard.preview(e, m, opt)
        return VStack(alignment: .leading, spacing: 4) {
            optionButton(label, primary: index == 0) { choose(e, m, index) }
            if !detail.isEmpty { Text(detail.tidyMoney).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) }
            ForEach(lines, id: \.self) { line in
                Text(line.tidyMoney).font(.system(size: 12)).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func optionButton(_ label: String, primary: Bool, action: @escaping () -> Void) -> some View {
        if primary {
            Button(action: action) { Text(label).frame(maxWidth: .infinity) }.buttonStyle(ImportantButtonStyle())
        } else {
            Button(action: action) { Text(label).frame(maxWidth: .infinity) }.buttonStyle(GreyOutlineButtonStyle())
        }
    }

    /// The same rule as the Inbox: a routine answer goes at once; an irreversible one, or a spend above the player's size, is asked first.
    private func choose(_ e: GameEngine, _ m: Message, _ index: Int) {
        guard m.options.indices.contains(index) else { return }
        let opt: JSONValue = m.options[index]
        let label: String = e.displayText(opt["l"].string, companyID: m.companyID)
        let need: DecisionConfirmation = DecisionConfirm.confirmation(for: m, option: index)
        guard need.needsQuestion else { send(e, m, index, label); return }
        var lines: [String] = []
        let d: String = e.displayText(opt["d"].string, companyID: m.companyID)
        if !d.isEmpty { lines.append(d) }
        lines += MessageCard.preview(e, m, opt)
        if index == 0 || m.options.count == 1 { lines += e.messageFacts(m) }
        let company: Company? = m.companyID != 0 ? e.state.company(m.companyID) : nil
        let place: String = company?.name ?? ""
        let fallback: String = e.displayText(m.title, companyID: m.companyID)
        var action = PendingAction(title: label + (place.isEmpty ? "" : " · " + place), message: lines.isEmpty ? fallback : lines.joined(separator: "\n"),
                                   button: label, destructive: need.irreversible) { send(e, m, index, label) }
        if !need.irreversible, let amount = need.amount {
            action.amount = amount
            action.currency = company.map { e.currency(for: $0) } ?? e.homeCurrency
        }
        if ConfirmThreshold.skips(action) { send(e, m, index, label); return }
        pending = action
    }

    private func send(_ e: GameEngine, _ m: Message, _ index: Int, _ label: String) {
        let effects: [String] = m.options.indices.contains(index) ? MessageCard.preview(e, m, m.options[index]) : []
        let ok: Bool = store.act { $0.answer(messageID: m.id, option: index) } ?? false
        store.decisionPopup = nil
        store.announceAnswer(label: label, effects: effects, ok: ok)
    }
}

/// The short report after an ordinary day: sales, what went well, and the messages that need a look. Real figures only.
struct DailyReportPopup: View {
    @EnvironmentObject var store: GameStore
    var digest: DailyDigest

    private var wentWell: [String] {
        var out: [String] = []
        if digest.sales > 0 {
            out.append("\(digest.sales) sale\(digest.sales == 1 ? "" : "s"), \(store.short(digest.revenue)) taken")
            if let best = digest.bestCompany { out.append("Busiest: \(best) with \(digest.bestSales)") }
        }
        return out + digest.wentWell
    }

    var body: some View {
        GamePopup(title: digest.dateLabel, showsClose: false, onClose: { store.dismissDailySheet() }) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Daily report").capsLabel()
                section("Went well", wentWell, tint: Theme.gain)
                section("Needs a look", digest.staffMessages, tint: Theme.caution)
                if digest.decisionsOpen > 0 {
                    Text("\(digest.decisionsOpen) decision\(digest.decisionsOpen == 1 ? "" : "s") waiting in the Inbox").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                }
                HStack {
                    Spacer(minLength: 0)
                    Button("Continue") { Haptics.tap(); store.dismissDailySheet() }
                        .buttonStyle(ImportantButtonStyle()).accessibilityIdentifier("daily-continue")
                }
            }
        }
    }

    @ViewBuilder private func section(_ title: String, _ lines: [String], tint: Color) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).capsLabel()
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(tint).frame(width: 5, height: 5).offset(y: -2)
                        Text(line.tidyMoney).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
