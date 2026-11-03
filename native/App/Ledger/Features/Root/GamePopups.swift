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
            if let a = store.redAlerts.first { RedAlertPopup(message: a).id(a.id).transition(.opacity) }
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
        if notice.style == "answered" { answered } else if notice.style == "luxury" { luxury } else { plain }
    }

    /// A high-value purchase: a gold-edged card whose edge draws round while it fades in.
    private var luxury: some View {
        GamePopup(title: "Acquired", showsClose: false, onClose: { store.dismissNotice() }) {
            VStack(spacing: 12) {
                GoldReveal {
                    VStack(spacing: 6) {
                        GoldRingMark(glyph: Glyph.achievements, size: 52)
                        Text(notice.title).font(.serifTitle(21)).foregroundStyle(Theme.ivory).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        Text(notice.subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                        if let price = notice.rows.first { Text(price.tidyMoney).font(.system(size: 15, weight: .medium).monospacedDigit()).foregroundStyle(Theme.gold) }
                    }
                }
                PopupOptionButton(title: "OK", highlighted: true, identifier: "notice-ok") { store.dismissNotice() }
            }
        }
    }

    /// The result of an answered decision: a check, what was chosen, which company, and every change it made.
    private var answered: some View {
        GamePopup(title: "Done", showsClose: false, onClose: { store.dismissNotice() }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    GlyphView(glyph: Glyph.check, size: 22, weight: 1.8, tint: Theme.gain)
                        .frame(width: 40, height: 40).background(Circle().fill(Theme.gain.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notice.title).font(.serifTitle(19)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                        if !notice.subtitle.isEmpty { Text(notice.subtitle.tidyMoney).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted) }
                    }
                }
                if !notice.rows.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(notice.rows, id: \.self) { (line: String) in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle().fill(Theme.gold).frame(width: 5, height: 5).offset(y: -2)
                                Text(line.tidyMoney).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
                }
                PopupOptionButton(title: "OK", highlighted: true, identifier: "notice-ok") { store.dismissNotice() }
            }
        }
    }

    private var plain: some View {
        GamePopup(title: heading, showsClose: false, onClose: { store.dismissNotice() }) {
            VStack(alignment: .leading, spacing: 12) {
                if !notice.text.isEmpty {
                    Text(notice.text.tidyMoney).font(.system(size: 14)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                }
                PopupOptionButton(title: "OK", highlighted: true, identifier: "notice-ok") { store.dismissNotice() }
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
            FitScroll(maxHeight: 460) { content(e, m) }
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
            PopupOptionButton(title: label, highlighted: index == recommendedIndex(m),
                              destructive: DecisionConfirm.confirmation(for: m, option: index).irreversible) { choose(e, m, index) }
            if !detail.isEmpty { Text(detail.tidyMoney).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) }
            ForEach(lines, id: \.self) { line in
                Text(line.tidyMoney).font(.system(size: 12)).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The recommended option is the first one that is not irreversible; it alone is highlighted. Irreversible options are outlined in red.
    private func recommendedIndex(_ m: Message) -> Int? {
        for i in m.options.indices where !DecisionConfirm.confirmation(for: m, option: i).irreversible { return i }
        return nil
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
        store.announceAnswer(label: label, effects: effects, ok: ok, messageTitle: m.title, companyID: m.companyID)
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
        GamePopup(title: digest.dateLabel, showsClose: false, dismissOnBackdrop: false, onClose: { store.dismissDailySheet() }) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Daily report").capsLabel()
                moneyLines
                section("Handled for you", Array(digest.handled.prefix(3)), tint: Theme.gold)
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

    /// What the day did to your money: always there, even on a quiet day, so every day has something to read.
    @ViewBuilder private var moneyLines: some View {
        if let c = digest.cashChange, let n = digest.netWorthChange {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your money").capsLabel()
                moneyRow("Cash", c)
                moneyRow("Net worth", n)
                if digest.isEmpty { Text("A quiet day: nothing sold, nothing new in the Inbox.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint) }
            }
        }
    }

    private func moneyRow(_ label: String, _ change: Double) -> some View {
        HStack {
            Text(label).font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted)
            Spacer(minLength: 8)
            Text((change >= 0 ? "+" : "") + store.short(change)).font(.system(size: 13.5, weight: .medium).monospacedDigit())
                .foregroundStyle(abs(change) < 1 ? Theme.ivoryMuted : change > 0 ? Theme.gain : Theme.loss)
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

/// A company about to be force-sold: a see-through red alert over everything. Tapping outside does nothing; the player has to read it and press Continue.
struct RedAlertPopup: View {
    @EnvironmentObject var store: GameStore
    var message: Message

    var body: some View {
        ZStack {
            Color(red: 0.8, green: 0.06, blue: 0.08).opacity(0.34).ignoresSafeArea()
                .contentShape(Rectangle()).onTapGesture { }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    GlyphView(glyph: Glyph.warning, size: 24, weight: 1.8, tint: Color.white)
                    Text("About to be sold").font(.system(size: 12, weight: .bold)).tracking(1.4).foregroundStyle(Color.white.opacity(0.9))
                }
                Text(store.engine?.displayText(message.title, companyID: message.companyID) ?? message.title)
                    .font(.serifTitle(22)).foregroundStyle(Color.white).fixedSize(horizontal: false, vertical: true)
                Text((store.engine?.displayText(message.body, companyID: message.companyID) ?? message.body).tidyMoney)
                    .font(.system(size: 14.5)).foregroundStyle(Color.white.opacity(0.92)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if message.companyID != 0 {
                        Button("Open the company") {
                            Haptics.tap(); store.dismissRedAlert(); store.openCompany(message.companyID, section: nil)
                        }.buttonStyle(QuietButtonStyle())
                    }
                    Spacer(minLength: 0)
                    Button("Continue") { Haptics.tap(); store.dismissRedAlert() }
                        .buttonStyle(ImportantButtonStyle()).accessibilityIdentifier("alert-continue")
                }
            }
            .padding(18).frame(maxWidth: 420)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(Color(red: 0.42, green: 0.04, blue: 0.06).opacity(0.78)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(Color(red: 1, green: 0.4, blue: 0.4).opacity(0.7), lineWidth: 1.5))
            .padding(.horizontal, 22)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}
