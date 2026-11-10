import SwiftUI
import GameCore
import Simulation
import Events
import Countries
import Finance
import Businesses

struct InboxView: View {
    private var P: OutsidePalette { .game }
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var companyFilter: Int? = nil
    @State private var limit = InboxView.page
    @State private var pending: PendingAction?
    @State private var detailID: Int?
    @State private var scrollTarget: Int?
    @AppStorage("inboxPinned") private var pinnedText = ""
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 40

    static let page = 40

    struct Block: Identifiable {
        var id: String
        var title: String
        var note: String = ""
        var tint: Color = Theme.ivoryFaint
        var companyID: Int? = nil
        var messages: [Message]
    }

    private var waitingCount: Int { store.openDecisionCount }

    private func filtered(_ e: GameEngine) -> [Message] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return e.state.inbox.filter { m in
            if let c = companyFilter, m.companyID != c { return false }
            if q.isEmpty { return true }
            let co = m.companyID != 0 ? (e.state.company(m.companyID)?.name ?? "") : ""
            return [m.title, m.body, m.from, co].contains { e.displayText($0, companyID: m.companyID).lowercased().contains(q) }
        }
    }

    private func blocks(_ e: GameEngine, _ list: [Message]) -> [Block] {
        InboxLayout.sections(list, week: e.state.week, infoFirst: store.tutorialActive).map { (p: InboxSection) -> Block in
            Block(id: p.id, title: p.title, messages: p.messages)
        }
    }

    private func isQuestion(_ m: Message) -> Bool { m.status == "open" && m.isOwnerAddressed }

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

    private func ask(_ message: Message, _ index: Int, inline: Bool = false) {
        guard let e = store.engine, message.options.indices.contains(index) else { return }
        let opt = message.options[index]
        let label = e.displayText(opt["l"].string, companyID: message.companyID)
        if message.actionID == PersonalFinance.dueAction {
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
            action.amount = amount
            action.currency = company.map { e.currency(for: $0) } ?? e.homeCurrency
        }
        if ConfirmThreshold.skips(action) { answer(message, index, label, inline: inline); return }
        pending = action
    }

    private func answer(_ message: Message, _ index: Int, _ label: String, inline: Bool = false) {
        var effects: [String] = []
        if let e = store.engine, message.options.indices.contains(index) { effects = MessageCard.preview(e, message, message.options[index]) }
        if effects.isEmpty, let e = store.engine, message.options.indices.contains(index) {
            let d: String = e.displayText(message.options[index]["d"].string, companyID: message.companyID)
            if !d.isEmpty { effects = [d] }
        }
        let ok = store.act { $0.answer(messageID: message.id, option: index) } ?? false
        if ok { Haptics.option() }
        detailID = nil
        if ok {
            store.announceAnswer(label: label, effects: effects, ok: true, messageTitle: message.title, companyID: message.companyID)
        } else if message.actionID == PersonalFinance.dueAction {
            Haptics.warning()
            store.tell("Not applied", "That way of paying could not cover the bill, so it is still open. Choose another way.", tone: "warn")
        } else {
            store.announceAnswer(label: label, effects: effects, ok: ok, messageTitle: message.title, companyID: message.companyID)
        }
    }

    private func openOnInformation() {
        guard store.tutorialActive, detailID == nil else { return }
        if store.tutorialStep == .readInbox, (store.engine?.tutorialInboxGuide ?? []).isEmpty { store.tutorialAdvance(from: .readInbox) }
    }

    private func takeRequest() {
        guard let id = store.takeMessageRequest() else { return }
        query = ""; companyFilter = nil
        if let i = store.engine?.state.inbox.firstIndex(where: { $0.id == id }) { limit = max(limit, i + waitingCount + 20) }
        detailID = id
        scrollTarget = id
    }

    private func scrollToTarget(_ proxy: ScrollViewProxy) {
        guard let id = scrollTarget else { return }
        scrollTarget = nil
        DispatchQueue.main.async { Motion.animate(Motion.move(reduceMotion)) { proxy.scrollTo(id, anchor: .top) } }
    }

    private var listPending: Binding<PendingAction?> {
        Binding<PendingAction?>(get: { detailID == nil ? pending : nil }, set: { newValue in if detailID == nil { pending = newValue } })
    }

    var body: some View {
        Group {
            if let e = store.engine {
                page(e)
            }
        }
        .onAppear {
            takeRequest()
            openOnInformation()
        }
        .onChange(of: store.appRequest) { _, _ in takeRequest() }
        .onChange(of: query) { _, _ in limit = Self.page }
        .onChange(of: store.depth(store.tab)) { _, _ in detailID = nil }
        .centerSheet(isPresented: Binding(get: { detailID != nil }, set: { if !$0 { detailID = nil } }), category: .medium, tone: detailTone) { detailSheet }
        .confirmAction(listPending)
        .ledgerBackground()
        .appScreen(title: "Inbox", subtitle: waitingCount > 0 ? "\(waitingCount) waiting for you" : "Decisions, offers and warnings") { optionsMenu }
        .environment(\.outsidePalette, P)
    }

    private func page(_ e: GameEngine) -> some View {
        let list: [Message] = filtered(e)
        let cut = limited(blocks(e, list))
        return ScrollViewReader { (proxy: ScrollViewProxy) in
            mailList(e, list: list, cut: cut)
                .onAppear { scrollToTarget(proxy) }
                .onChange(of: scrollTarget) { _, _ in scrollToTarget(proxy) }
        }
    }

    private func mailList(_ e: GameEngine, list: [Message], cut: (blocks: [Block], hidden: Int)) -> some View {
        let week: Int = e.state.week
        let alerts: [PayrollAlert] = payrollAlerts(e)
        let guide: [Int] = store.tutorialActive ? e.tutorialInboxGuide : []
        return List {
            hero(e, list, extra: alerts.count).mailRowStyle().listRowSeparator(.hidden)
            searchField.padding(.bottom, Theme.Space.s).mailRowStyle().listRowSeparator(.hidden)
            if !guide.isEmpty {
                Text("New here? Open the messages marked Read next.")
                    .textStyle(.caption, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
                    .mailRowStyle().listRowSeparator(.hidden)
            }
            if companyFilter != nil { filterLine(e).mailRowStyle() }
            if list.isEmpty && alerts.isEmpty { empty(e).mailRowStyle() }
            ForEach(alerts) { (a: PayrollAlert) in payrollRow(a).mailRowStyle() }
            ForEach(cut.blocks) { (b: Block) in
                if !b.title.isEmpty {
                    Text(b.title).textStyle(.caption, tint: P.inkFaint, weight: .semibold)
                        .padding(.top, Theme.Space.m).mailRowStyle().listRowSeparator(.hidden)
                }
                ForEach(b.messages) { (m: Message) in
                    mailRow(m, week: week, inline: true, guide: guide).transition(.opacity)
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
        let answer: ((Int) -> Void)? = inline && m.isOwnerAddressed ? { (i: Int) in ask(m, i, inline: true) } : nil
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

    private func payrollAlerts(_ e: GameEngine) -> [PayrollAlert] {
        guard query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return e.payrollAlerts().filter { companyFilter == nil || $0.companyID == companyFilter }
    }

    private func payrollRow(_ a: PayrollAlert) -> some View {
        let fmt = BankFmt(store: store, company: store.engine?.state.company(a.companyID))
        let text: String = "Payroll \(fmt.short(a.amount)) is late. \(a.reason) It is paid on the 15th once the company has the cash."
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(a.companyName).textStyle(.caption, tint: P.inkFaint)
            Text(text.tidyText).textStyle(.body, tint: P.ink).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Theme.Space.s)
    }

    private var pinned: Set<Int> { Set(pinnedText.split(separator: ",").compactMap { Int($0) }) }

    private func togglePin(_ id: Int) {
        var set: Set<Int> = pinned
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        pinnedText = set.sorted().map(String.init).joined(separator: ",")
        Haptics.tap()
    }

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

    private func hero(_ e: GameEngine, _ list: [Message], extra: Int = 0) -> some View {
        let waiting: [Message] = list.filter { isQuestion($0) }
        let n: Int = waiting.count + extra
        var note: String = ""
        let title: String
        if n > 0 {
            title = n == 1 ? "decision needs you" : "decisions need you"
            let soonest: Int? = waiting.compactMap { (m: Message) -> Int? in m.expiresWeek.map { $0 - e.state.week } }.min()
            if let left = soonest { note = left <= 0 ? "The first one expires this week." : "The first one expires in \(left) week\(left == 1 ? "" : "s")." }
        } else {
            title = "Nothing needs you"
            let unread: Int = store.unreadCount
            note = unread > 0 ? "\(unread) unread" : "All read"
        }
        return VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            if n > 0 { Text("\(n)").font(.hero(heroSize)).foregroundStyle(P.ink).lineLimit(1) }
            Text(title).textStyle(n > 0 ? .body : .headline, tint: P.inkSoft)
            if !note.isEmpty { Text(note).textStyle(.caption, tint: n > 0 ? P.caution : P.inkFaint) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Space.m).padding(.bottom, Theme.Space.l)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inbox-hero")
    }

    private var detailTone: PopupTone {
        guard let id = detailID, let m = store.engine?.state.inbox.first(where: { $0.id == id }) else { return .info }
        return m.status == "open" ? .warning : .info
    }

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

    private func empty(_ e: GameEngine) -> some View {
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let text = searching ? "No message matches \u{201C}\(query)\u{201D}." : "Nothing here yet."
        return EmptyState(glyph: Glyph.inbox, title: text)
            .padding(.top, Theme.Space.xxl)
    }
}

struct MessageCard: View {
    private var P: OutsidePalette { .game }
    @EnvironmentObject var store: GameStore
    var message: Message
    var week: Int
    var full = false
    var ask: (Message, Int) -> Void

    private func text(_ s: String) -> String { (store.engine?.displayText(s, companyID: message.companyID) ?? s).tidyMoney }

    static func preview(_ e: GameEngine, _ message: Message, _ option: JSONValue) -> [String] {
        let cur = message.companyID != 0 ? (e.state.company(message.companyID).map { e.currency(for: $0) } ?? e.homeCurrency) : e.homeCurrency
        return EffectPreview.lines(option["fx"], currency: cur)
    }
    private func preview(_ option: JSONValue) -> [String] { store.engine.map { Self.preview($0, message, option) } ?? [] }

    static func answerConfirm(title: String, message: String, button: String, need: DecisionConfirmation, run: @escaping () -> Void) -> PendingAction {
        let words: String = button.lowercased()
        let hold: Bool = need.irreversible && ["sell", "fire", "dismiss", "sack", "let go", "wind up", "terminate"].contains { words.contains($0) }
        return PendingAction(title: title, message: message, button: button, destructive: hold, alwaysAsk: need.irreversible && !hold,
                             tone: hold ? nil : .warning, run: run)
    }

    private var link: (title: String, run: () -> Void)? {
        guard let e = store.engine, let target = InboxLayout.target(message, in: e.state) else { return nil }
        switch target {
        case .company(let id, let key):
            let name: String = e.state.company(id)?.name ?? "the company"
            return ("Open " + name, { openCompanyLink(id, key) })
        case .app(let key):
            if key == "profile" { return ("Open your profile", { store.openProfile() }) }
            guard let app = PhoneApp(rawValue: key), app.visibility(e) == .open else { return nil }
            return ("Open " + app.title, { store.openApp(app) })
        }
    }

    private func openCompanyLink(_ id: Int, _ key: String) {
        switch key {
        case "staff": store.openCompany(id, section: .staff)
        case "properties": store.openCompany(id, section: .properties)
        case "sales": store.openCompany(id, section: .salesMarket)
        case "finances": store.openCompany(id, section: .finances)
        case "club": store.openCompany(id, section: .club)
        default: store.openCompany(id)
        }
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
            if let link { QuietButton(title: link.title) { link.run() } }
            if open { decision }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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

    private func optionButton(_ idx: Int, _ opt: JSONValue) -> some View {
        let effect: String = preview(opt).joined(separator: ". ")
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
