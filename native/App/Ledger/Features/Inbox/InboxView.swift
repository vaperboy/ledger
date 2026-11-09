import SwiftUI
import GameCore
import Simulation
import Events
import Countries
import Finance

/// Decisions and news. Decisions come first, by how soon they expire; each shows what every choice does before you commit and
/// opens the company (and the section) it concerns. Search, a company filter and grouping keep hundreds of messages usable.
struct InboxView: View {
    private var P: OutsidePalette { .game }
    /// Needs you: open decisions; All: everything.
    /// Handled: what a hired rank, accountant or desk took care of for you (the Inbox shows who).
    enum Tab: String, CaseIterable, Hashable { case decisions = "Needs you", handled = "Handled", all = "All" }
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: Tab = .decisions
    @State private var query = ""
    /// nil = every company; 0 = messages about the group or you personally
    @State private var companyFilter: Int? = nil
    @State private var limit = InboxView.page
    @State private var pending: PendingAction?
    @State private var detailID: Int?
    @State private var burst: MoneyBurst?
    @State private var scrollTarget: Int?
    @AppStorage("inboxPinned") private var pinnedText = ""
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 40

    static let page = 40

    /// A titled block of messages (an urgency band or a company).
    struct Block: Identifiable {
        var id: String
        var title: String
        var note: String = ""
        var tint: Color = Theme.ivoryFaint
        var companyID: Int? = nil
        var messages: [Message]
    }

    private var waitingCount: Int { store.openDecisionCount }

    private func matches(_ m: Message, _ t: Tab) -> Bool {
        switch t {
        case .all: return true
        case .decisions: return m.status == "open" && m.isOwnerAddressed
        case .handled: return !m.handledBy.isEmpty
        }
    }

    private func filtered(_ e: GameEngine, _ t: Tab) -> [Message] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return e.state.inbox.filter { m in
            guard matches(m, t) else { return false }
            if let c = companyFilter, m.companyID != c { return false }
            if q.isEmpty { return true }
            let co = m.companyID != 0 ? (e.state.company(m.companyID)?.name ?? "") : ""
            return [m.title, m.body, m.from, co].contains { e.displayText($0, companyID: m.companyID).lowercased().contains(q) }
        }
    }

    // MARK: Blocks

    /// One chronological list, newest first, no sub-folders.
    private func blocks(_ e: GameEngine, _ list: [Message]) -> [Block] {
        // While the first-steps guide runs, information comes before questions: the questions stay one tap away under Needs you.
        let guide: Bool = store.tutorialActive
        let sorted: [Message] = list.sorted { (a: Message, b: Message) -> Bool in
            if guide, isQuestion(a) != isQuestion(b) { return !isQuestion(a) }
            return a.week != b.week ? a.week > b.week : a.id > b.id
        }
        return sorted.isEmpty ? [] : [Block(id: "all", title: "", messages: sorted)]
    }

    private func isQuestion(_ m: Message) -> Bool { m.status == "open" && m.isOwnerAddressed }

    /// The blocks cut to the first `limit` messages, so a long inbox stays quick.
    private func limited(_ blocks: [Block]) -> (blocks: [Block], hidden: Int) {
        var left = limit, out: [Block] = [], hidden = 0
        for b in blocks {
            if left <= 0 { hidden += b.messages.count; continue }
            var c = b
            if c.messages.count > left { hidden += c.messages.count - left; c.messages = Array(c.messages.prefix(left)) }
            left -= c.messages.count
            out.append(c)
        }
        return (out, hidden)
    }

    // MARK: Answering

    /// A routine answer is sent at once, and the sheet closes. Only a consequential one is confirmed, in the in-game popup: one that cannot be
    /// undone, or a spend at or above the player's own "Ask before spending" size (the engine decides which, see `DecisionConfirm`). A small
    /// spend under that size is sent at once too, and the "Answered" message says what it was.
    /// `inline`: answered from the list row itself, so the player stays in the Inbox for the next one.
    private func ask(_ message: Message, _ index: Int, inline: Bool = false) {
        guard let e = store.engine, message.options.indices.contains(index) else { return }
        let opt = message.options[index]
        let label = e.displayText(opt["l"].string, companyID: message.companyID)
        if message.actionID == PersonalFinance.dueAction {
            // Every way of settling the tax commits money or a loan: always say what it does first.
            pending = PendingAction(title: label, message: e.displayText(opt["d"].string, companyID: message.companyID), button: label, alwaysAsk: true) {
                answer(message, index, label, inline: inline)
            }
            return
        }
        let need: DecisionConfirmation = DecisionConfirm.confirmation(for: message, option: index)
        guard need.needsQuestion else { answer(message, index, label, inline: inline); return }
        var lines: [String] = []
        let d = e.displayText(opt["d"].string, companyID: message.companyID)
        if !d.isEmpty { lines.append(d) }
        lines += MessageCard.preview(e, message, opt)
        if index == 0 || message.options.count == 1 { lines += e.messageFacts(message) }
        let company: Company? = message.companyID != 0 ? e.state.company(message.companyID) : nil
        let where_: String = company?.name ?? ""
        let fallback: String = e.displayText(message.title, companyID: message.companyID)
        let title: String = label + (where_.isEmpty ? "" : " · " + where_)
        let body: String = lines.isEmpty ? fallback : lines.joined(separator: "\n")
        var action = MessageCard.answerConfirm(title: title, message: body, button: label, need: need) { answer(message, index, label, inline: inline) }
        if !need.irreversible, let amount = need.amount {
            // A message about the group or you personally has no company: its money is in the home currency.
            action.amount = amount
            action.currency = company.map { e.currency(for: $0) } ?? e.homeCurrency
        }
        // Under the player's size: no question at all, so nothing can hold the answer back.
        if ConfirmThreshold.skips(action) { answer(message, index, label, inline: inline); return }
        pending = action
    }

    /// Sends the answer. The detail sheet closes at once: the answer is on record and the list shows it as answered.
    private func answer(_ message: Message, _ index: Int, _ label: String, inline: Bool = false) {
        var effects: [String] = []
        if let e = store.engine, message.options.indices.contains(index) { effects = MessageCard.preview(e, message, message.options[index]) }
        // An option with no preview lines is told by its own description.
        if effects.isEmpty, let e = store.engine, message.options.indices.contains(index) {
            let d: String = e.displayText(message.options[index]["d"].string, companyID: message.companyID)
            if !d.isEmpty { effects = [d] }
        }
        let ok = store.act { $0.answer(messageID: message.id, option: index) } ?? false
        if ok { Haptics.option() }
        detailID = nil
        if ok {
            // What was chosen and what it does: one outcome popup (the tax decision names the payment route it took).
            store.announceAnswer(label: label, effects: effects, ok: true, messageTitle: message.title, companyID: message.companyID)
        } else if message.actionID == PersonalFinance.dueAction {
            // The tax decision stays open when a route cannot cover the bill: say so and let the player choose another.
            Haptics.warning()
            store.tell("Not applied", "That way of paying could not cover the bill, so it is still open. Choose another way.", tone: "warn")
        } else {
            store.announceAnswer(label: label, effects: effects, ok: ok, messageTitle: message.title, companyID: message.companyID)
        }
    }

    /// While the first-steps guide runs the Inbox opens on everything (information first), not on the questions; with nothing to read the
    /// guide's reading step is over.
    private func openOnInformation() {
        guard store.tutorialActive, detailID == nil, tab == .decisions else { return }
        tab = .all
        if store.tutorialStep == .readInbox, (store.engine?.tutorialInboxGuide ?? []).isEmpty { store.tutorialAdvance(from: .readInbox) }
    }

    private func takeRequest() {
        guard let id = store.takeMessageRequest() else { return }
        tab = .all; query = ""; companyFilter = nil
        if let i = store.engine?.state.inbox.firstIndex(where: { $0.id == id }) { limit = max(limit, i + waitingCount + 20) }
        detailID = id
        scrollTarget = id
    }

    /// Scrolls the All page to a requested message (only that page scrolls; the request is cleared once it has).
    private func scrollToTarget(_ proxy: ScrollViewProxy) {
        guard let id = scrollTarget else { return }
        scrollTarget = nil
        DispatchQueue.main.async { Motion.animate(Motion.move(reduceMotion)) { proxy.scrollTo(id, anchor: .top) } }
    }

    /// The confirmation belongs to the screen that asked: the list while the detail sheet is closed, the sheet while it is open.
    /// One presenter at a time, so an answer is never confirmed twice.
    private var listPending: Binding<PendingAction?> {
        Binding<PendingAction?>(get: { detailID == nil ? pending : nil }, set: { newValue in if detailID == nil { pending = newValue } })
    }

    // MARK: Body

    /// The Inbox app, mail style: one row per message (sender icon circle, subject, preview, time, unread dot), swipe actions, and a
    /// detail sheet that keeps every decision and the company link. It is pushed on the Phone tab's stack (which owns the company
    /// destinations and the deep-link requests), so it has no stack of its own; its options menu sits in the app header.
    var body: some View {
        Group {
            if let e = store.engine {
                SegmentPager(items: Tab.allCases, selection: $tab) { (k: Tab) in
                    page(e, k)
                }
            }
        }
        .onAppear {
            takeRequest()
            openOnInformation()
        }
        .onChange(of: store.appRequest) { _, _ in takeRequest() }
        .safeAreaInset(edge: .top, spacing: 0) {
            SectionTabs(items: Tab.allCases, title: { $0.rawValue }, selection: $tab, badge: { tab in tab == .decisions ? waitingCount : 0 })
                .pulseOnce(when: waitingCount)
                .padding(.vertical, Theme.Space.xs).background(P.ground)
        }
        // Search lives on the All page only, so another page is never filtered by a query that is not on screen.
        .onChange(of: tab) { _, now in limit = Self.page; if now != .all { query = "" } }
        .onChange(of: query) { _, _ in limit = Self.page }
        // A company link tapped anywhere closes the detail first, so Back from the company lands on the Inbox list.
        .onChange(of: store.depth(store.tab)) { _, _ in detailID = nil }
        .centerSheet(isPresented: Binding(get: { detailID != nil }, set: { if !$0 { detailID = nil } }), category: .medium, tone: detailTone) { detailSheet }
        .confirmAction(listPending)
        .ledgerBackground()
        .appScreen(title: "Inbox", subtitle: waitingCount > 0 ? "\(waitingCount) waiting for you" : "Decisions, offers and warnings") { optionsMenu }
        .environment(\.outsidePalette, P)
    }

    private func page(_ e: GameEngine, _ k: Tab) -> some View {
        let list: [Message] = filtered(e, k)
        let cut = limited(blocks(e, list))
        return ScrollViewReader { (proxy: ScrollViewProxy) in
            mailList(e, list: list, cut: cut, k)
                .onAppear { if k == .all { scrollToTarget(proxy) } }
                .onChange(of: scrollTarget) { _, _ in if k == .all { scrollToTarget(proxy) } }
        }
    }

    private func mailList(_ e: GameEngine, list: [Message], cut: (blocks: [Block], hidden: Int), _ k: Tab) -> some View {
        let week: Int = e.state.week
        let alerts: [PayrollAlert] = payrollAlerts(e, k)
        let guide: [Int] = store.tutorialActive ? e.tutorialInboxGuide : []
        return List {
            if !list.isEmpty || !alerts.isEmpty || k == .all {
                hero(e, k, list, extra: alerts.count).mailRowStyle().listRowSeparator(.hidden)
            }
            if k == .all { searchField.padding(.bottom, Theme.Space.s).mailRowStyle().listRowSeparator(.hidden) }
            if k == .all, !guide.isEmpty {
                Text("New here? Open the messages marked Read next. Questions that need you are under Needs you.")
                    .textStyle(.caption, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
                    .mailRowStyle().listRowSeparator(.hidden)
            }
            if companyFilter != nil { filterLine(e).mailRowStyle() }
            if list.isEmpty && alerts.isEmpty { empty(e, k).mailRowStyle() }
            ForEach(alerts) { (a: PayrollAlert) in payrollRow(a).mailRowStyle() }
            ForEach(cut.blocks) { (b: Block) in
                ForEach(b.messages) { (m: Message) in
                    mailRow(m, week: week, inline: k == .decisions, guide: k == .all ? guide : []).transition(.opacity)
                }
            }
            if cut.hidden > 0 {
                QuietButton(title: "Show \(min(Self.page, cut.hidden)) more of \(cut.hidden)", fullWidth: true) { limit += Self.page }
                    .mailRowStyle()
            }
        }
        .listStyle(.plain).scrollBounceBehavior(.basedOnSize)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .animation(Motion.quick(reduceMotion), value: list.count)
        .frame(maxWidth: 760).frame(maxWidth: .infinity)
    }

    private func mailRow(_ m: Message, week: Int, inline: Bool, guide: [Int] = []) -> some View {
        let pinnedNow: Bool = pinned.contains(m.id)
        let answer: ((Int) -> Void)? = inline ? { (i: Int) in ask(m, i, inline: true) } : nil
        let marked: Bool = guide.contains(m.id)
        return InboxMailRow(message: m, week: week, pinned: pinnedNow, openDetail: {
            detailID = m.id
            if marked { store.tutorialAdvance(from: .readInbox) }
        }, answer: answer, guided: marked)
            .coachAnchor(.inboxGuided, enabled: marked && m.id == guide.first)
            .id(m.id)
            .mailRowStyle()
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { togglePin(m.id) } label: { Label(pinnedNow ? "Unpin" : "Pin", systemImage: pinnedNow ? "pin.slash" : "pin") }
                    .tint(P.accent2)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if m.status != "open" && !m.isRead {
                    Button { store.markRead(m.id) } label: { Label("Read", systemImage: "envelope.open") }.tint(P.lineStrong)
                }
            }
    }

    // MARK: Payroll

    /// Payroll that waits for the owner (no manager or accountant approves it): a needs-you item answered here, on the Needs you tab.
    private func payrollAlerts(_ e: GameEngine, _ k: Tab) -> [PayrollAlert] {
        guard k == .decisions, query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return e.payrollAlerts().filter { companyFilter == nil || $0.companyID == companyFilter }
    }

    private func payrollRow(_ a: PayrollAlert) -> some View {
        let fmt = BankFmt(store: store, company: store.engine?.state.company(a.companyID))
        let text: String = a.isLate ? "Payroll \(fmt.short(a.amount)) is late. \(a.reason)" : "Payroll \(fmt.short(a.amount)) on \(a.dateText) needs you. \(a.reason)"
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(a.companyName).textStyle(.caption, tint: P.inkFaint)
            Text(text.tidyText).textStyle(.body, tint: P.ink).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer(minLength: 0)
                Button(a.isLate ? "Pay now" : "Approve payroll") { runPayroll(a, fmt) }
                    .buttonStyle(SecondaryButtonStyle(size: .compact, tint: P.accent))
                    .accessibilityIdentifier("inbox-payroll-\(a.companyID)")
            }
        }
        .padding(.vertical, Theme.Space.s)
        .moneyTravel($burst, source: a.companyID)
    }

    private func runPayroll(_ a: PayrollAlert, _ fmt: BankFmt) {
        let outcome: PayrollAlertOutcome? = store.act { (e: inout GameEngine) -> PayrollAlertOutcome in e.resolvePayrollAlert(companyID: a.companyID) }
        switch outcome {
        case .approved?:
            Haptics.success()
            store.show("Payroll approved: about \(fmt.short(a.amount)) goes out on \(a.dateText).", tone: "good")
            burst = MoneyBurst(label: "Payroll", amount: a.amount, outgoing: true, text: fmt.short(a.amount), source: a.companyID)
        case .paidLate(let paid, let short)?:
            if short > 0.5 {
                Haptics.warning()
                store.show("Paid \(fmt.short(paid)). Still short \(fmt.short(short)): put money into the company and run it again.", tone: "warn")
            } else {
                Haptics.success()
                store.show("Late payroll paid: \(fmt.short(paid)).", tone: "good")
                burst = MoneyBurst(label: "Payroll", amount: paid, outgoing: true, text: fmt.short(paid), source: a.companyID)
            }
        case .notNeeded(let why)?:
            Haptics.warning()
            store.show(why, tone: "warn")
        case nil:
            break
        }
    }

    // MARK: Pinning (a view preference kept on the device, not game state)

    private var pinned: Set<Int> { Set(pinnedText.split(separator: ",").compactMap { Int($0) }) }

    private func togglePin(_ id: Int) {
        var set: Set<Int> = pinned
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        pinnedText = set.sorted().map(String.init).joined(separator: ",")
        Haptics.tap()
    }

    // MARK: Detail

    @ViewBuilder private var detailSheet: some View {
        if let e = store.engine, let id = detailID, let m = e.state.inbox.first(where: { $0.id == id }), let d = m.doc {
            DocumentView(doc: d, close: { detailID = nil })
                .onAppear { store.markRead(m.id) }
        } else if let e = store.engine, let id = detailID, let m = e.state.inbox.first(where: { $0.id == id }) {
            MessageCard(message: m, week: e.state.week, full: true, ask: { (msg: Message, i: Int) in ask(msg, i) })
                .centerSheetTitle("Message")
                .confirmAction($pending)
        } else {
            Color.clear.onAppear { detailID = nil }
        }
    }

    /// The page's hero: how many messages it holds, in words, and one line that matters (the first expiry, who answered, what is unread).
    private func hero(_ e: GameEngine, _ k: Tab, _ list: [Message], extra: Int = 0) -> some View {
        let n: Int = list.count + extra
        let title: String
        var note: String = ""
        switch k {
        case .decisions:
            title = n == 1 ? "decision needs you" : "decisions need you"
            let soonest: Int? = list.compactMap { (m: Message) -> Int? in m.expiresWeek.map { $0 - e.state.week } }.min()
            if let left = soonest { note = left <= 0 ? "The first one expires this week." : "The first one expires in \(left) week\(left == 1 ? "" : "s")." }
        case .handled:
            title = "handled by your team"
        case .all:
            title = n == 1 ? "message" : "messages"
            let unread: Int = store.unreadCount
            note = unread > 0 ? "\(unread) unread" : "All read"
        }
        return VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text("\(n)").font(.hero(heroSize)).foregroundStyle(P.ink).lineLimit(1)
            Text(title).textStyle(.body, tint: P.inkSoft)
            if !note.isEmpty { Text(note).textStyle(.caption, tint: k == .decisions ? P.caution : P.inkFaint) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Space.m).padding(.bottom, Theme.Space.l)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inbox-hero")
    }

    /// An open decision reads as a warning; anything else in the Inbox is information.
    private var detailTone: PopupTone {
        guard let id = detailID, let m = store.engine?.state.inbox.first(where: { $0.id == id }) else { return .info }
        return m.status == "open" ? .warning : .info
    }

    /// The search box (the system search field needs a navigation bar, which the app header replaces).
    private var searchField: some View {
        HStack(spacing: Theme.Space.s) {
            LedgerGlyph(glyph: Glyph.search, size: Theme.Icon.small, tint: P.inkFaint)
            TextField("Search messages", text: $query).textStyle(.body, tint: P.ink).autocorrectionDisabled().submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: { LedgerGlyph(glyph: Glyph.close, size: Theme.Icon.small, tint: P.inkFaint).frame(width: 44, height: 36).contentShape(Rectangle()) }.buttonStyle(PressableStyle()).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Space.m).frame(minHeight: 40)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(P.inset))
    }

    private var optionsMenu: some View {
        Menu {
            if let e = store.engine {
                let ids = Array(Set(e.state.inbox.map { $0.companyID })).sorted { (e.state.company($0)?.name ?? "") < (e.state.company($1)?.name ?? "") }
                if ids.count > 1 {
                    Picker("Show", selection: $companyFilter) {
                        Text("Every company").tag(Int?.none)
                        ForEach(ids, id: \.self) { id in
                            Text(id == 0 ? "Group and personal" : (e.state.company(id)?.name ?? "A former company")).tag(Int?.some(id))
                        }
                    }
                }
            }
            Button("Mark all read") {
                let n = store.unreadCount
                store.act { e in e.update { s, _, _ in for i in s.inbox.indices where s.inbox[i].status != "open" { s.inbox[i].isRead = true } } }
                store.show("Marked \(n) message\(n == 1 ? "" : "s") as read. Open decisions stay open.", tone: "n")
            }.disabled(store.unreadCount == 0)
        } label: {
            GlyphView(glyph: Glyph.list, size: 18, weight: 1.8, tint: P.ink)
                .frame(width: 40, height: 40)
                .overlay(Circle().strokeBorder(P.lineStrong, lineWidth: 1))
                .contentShape(Circle())
                .accessibilityLabel("Inbox options")
        }
    }

    private func filterLine(_ e: GameEngine) -> some View {
        let name = companyFilter == 0 ? "Group and personal" : (companyFilter.flatMap { e.state.company($0)?.name } ?? "A former company")
        return HStack {
            Text("Only " + name).textStyle(.caption)
            Spacer()
            Button("Show all") { companyFilter = nil }.buttonStyle(TertiaryButtonStyle(size: .compact))
        }
    }

    private func empty(_ e: GameEngine, _ k: Tab) -> some View {
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let text = searching ? "No message matches \u{201C}\(query)\u{201D}."
            : e.state.inbox.isEmpty ? "Nothing here yet."
            : k == .decisions ? "Nothing needs you right now."
            : k == .handled ? "Nothing handled for you yet." : "Nothing here yet."
        return EmptyState(glyph: k == .decisions && !searching ? Glyph.check : Glyph.inbox, title: text)
            .padding(.top, Theme.Space.xxl)
    }
}

struct MessageCard: View {
    private var P: OutsidePalette { .game }
    @EnvironmentObject var store: GameStore
    var message: Message
    var week: Int
    /// The whole card (decisions, outcome, company link) even for an answered, read message: the detail sheet.
    var full = false
    /// Asks to answer with an option (the Inbox confirms it first).
    var ask: (Message, Int) -> Void

    private func text(_ s: String) -> String { (store.engine?.displayText(s, companyID: message.companyID) ?? s).tidyMoney }

    /// The effects of an option, in the currency of the company it concerns.
    static func preview(_ e: GameEngine, _ message: Message, _ option: JSONValue) -> [String] {
        let cur = message.companyID != 0 ? (e.state.company(message.companyID).map { e.currency(for: $0) } ?? e.homeCurrency) : e.homeCurrency
        return EffectPreview.lines(option["fx"], currency: cur)
    }
    private func preview(_ option: JSONValue) -> [String] { store.engine.map { Self.preview($0, message, option) } ?? [] }

    /// The question before an answer: an irreversible sale or dismissal is held to confirm (red), any other irreversible answer is
    /// always asked in the warning tone, and a spend is asked by its size (the caller sets the amount).
    static func answerConfirm(title: String, message: String, button: String, need: DecisionConfirmation, run: @escaping () -> Void) -> PendingAction {
        let words: String = button.lowercased()
        let hold: Bool = need.irreversible && ["sell", "fire", "dismiss", "sack", "let go", "wind up", "terminate"].contains { words.contains($0) }
        return PendingAction(title: title, message: message, button: button, destructive: hold, alwaysAsk: need.irreversible && !hold,
                             tone: hold ? nil : .warning, run: run)
    }

    private var glyph: String { message.inboxGlyph }
    private var tint: Color { message.inboxTint(P) }
    private var age: String {
        let d = week - message.week
        return d <= 0 ? "This week" : d == 1 ? "1 week ago" : "\(d) weeks ago"
    }

    var body: some View {
        let open = message.status == "open"
        if !full && !open && message.tone != "bad" && message.isRead {
            HStack(alignment: .center, spacing: 10) {
                InboxAvatar(initial: message.inboxInitial, glyph: glyph, tint: tint, size: 30, face: message.inboxFace(store.engine))
                VStack(alignment: .leading, spacing: 1) {
                    Text(text(message.title)).font(.subheadline).foregroundStyle(P.inkSoft).lineLimit(2)
                    if let o = store.engine?.answeredOutcome(message) { Text(o).font(.caption2).foregroundStyle(P.inkFaint).lineLimit(1) }
                }
                Spacer()
                Text(message.from).font(.caption2).foregroundStyle(P.inkFaint).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(P.card.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(P.line.opacity(0.7), lineWidth: 1))
        } else if full {
            detail(open: open)
                .onAppear { if !open { store.markRead(message.id) } }
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .bottom, spacing: 8) {
                    InboxAvatar(initial: message.inboxInitial, glyph: glyph, tint: tint, size: 36, face: message.inboxFace(store.engine))
                    bubble(open: open)
                    Spacer(minLength: 24)
                }
                if open { decision }
            }
            .onAppear { if !open { store.markRead(message.id) } }
        }
    }

    /// The opened message: who sent it and when, the subject as the title, the text, what came of it, the company link, then the choices.
    private func detail(open: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.m) {
                InboxAvatar(initial: message.inboxInitial, glyph: glyph, tint: tint, size: 40, face: message.inboxFace(store.engine))
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(message.from).textStyle(.headline, tint: P.ink).lineLimit(1)
                    Text(age).textStyle(.caption, tint: P.inkFaint)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(text(message.title)).textStyle(.title, tint: P.ink).fixedSize(horizontal: false, vertical: true)
                Text(text(message.body)).textStyle(.body, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
                if let o = store.engine?.answeredOutcome(message) {
                    Text(o).textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
                }
                if !message.handledBy.isEmpty {
                    Text("Handled by " + message.handledBy).textStyle(.caption, tint: P.accent, weight: .medium)
                }
            }
            if open { decision }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The message as a chat bubble: sender and age on top, the subject, the text, what it means, and what it means.
    private func bubble(open: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(message.from).font(.caption.weight(.semibold)).foregroundStyle(tint).lineLimit(1)
                Spacer(minLength: 8)
                Text(age).font(.caption2).foregroundStyle(P.inkFaint)
                if !message.isRead || open { NewMarkerShape(style: .dot, important: open) }
            }
            Text(text(message.title)).font(.bodyText.weight(.semibold)).foregroundStyle(P.ink).fixedSize(horizontal: false, vertical: true)
            Text(text(message.body)).font(.caption).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true)
            if let o = store.engine?.answeredOutcome(message) {
                Text(o).font(.caption2.weight(.medium)).foregroundStyle(P.inkFaint).padding(.top, 2)
            }
            if !message.handledBy.isEmpty {
                Text("Handled by " + message.handledBy).font(.caption2.weight(.medium)).foregroundStyle(P.accent)
            }
        }
        .padding(.horizontal, full ? 0 : 14).padding(.vertical, full ? 0 : 11)
        .background(shape.fill(full ? Color.clear : P.card))
        .overlay(shape.strokeBorder(full ? Color.clear : P.line, lineWidth: 1))
    }

    @ViewBuilder private var decision: some View {
        if let exp = message.expiresWeek {
            let left = exp - week
            HStack(spacing: 6) {
                GlyphView(glyph: Glyph.clock, size: 14, weight: 1.8, tint: left <= 1 ? P.loss : P.caution)
                Text(left > 0 ? "Expires in \(left) week\(left == 1 ? "" : "s")" : "Expires this week").popupText(.risk, variant: left <= 1 ? .destructive : .standard)
            }
            .accessibilityElement(children: .combine)
            if let leave = store.engine?.expiryOutcome(message) {
                Text(leave).popupText(.caption)
            }
        }
        let opts = Array(message.options.enumerated())
        if opts.isEmpty {
            Text("Dealt with in the company.").popupText(.caption)
        }
        VStack(spacing: Theme.Space.s) {
            ForEach(opts, id: \.offset) { idx, opt in
                optionButton(idx, opt)
            }
        }
    }

    /// A full-width option: its label, and under it one grey line of what it does (`EffectPreview`); no line when the preview is empty.
    private func optionButton(_ idx: Int, _ opt: JSONValue) -> some View {
        let effect: String = preview(opt).joined(separator: ". ")
        // An option that carries its own sentence (the tax payment choices) shows it when it has no computed effect.
        let detail: String = effect.isEmpty ? text(opt["d"].string) : effect + "."
        return Button { ask(message, idx) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(text(opt["l"].string)).popupText(.button)
                if !detail.isEmpty { Text(detail).popupText(.caption).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, Theme.Space.s).padding(.leading, Theme.Space.m).padding(.trailing, Theme.Space.xxl)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(P.inset))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).strokeBorder(idx == 0 ? P.accent.opacity(0.7) : Color.clear, lineWidth: 1))
            .overlay(alignment: .trailing) { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint).padding(.trailing, Theme.Space.m) }
            .contentShape(Rectangle())
        }.buttonStyle(PressableStyle()).accessibilityIdentifier("inbox-option")
    }
}
