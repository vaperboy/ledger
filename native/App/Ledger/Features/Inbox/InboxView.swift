import SwiftUI
import GameCore
import Simulation
import Events
import Countries

/// Decisions and news. Decisions come first, by how soon they expire; each shows what every choice does before you commit and
/// opens the company (and the section) it concerns. Search, a company filter and grouping keep hundreds of messages usable.
struct InboxView: View {
    private var P: OutsidePalette { .inbox }
    enum Tab: String, CaseIterable, Hashable { case all = "All", decisions = "Decisions", risks = "Risks", updates = "Updates" }
    @EnvironmentObject var store: GameStore
    @State private var tab: Tab = .all
    @State private var query = ""
    /// nil = every company; 0 = messages about the group or you personally
    @State private var companyFilter: Int? = nil
    @State private var byCompany = false
    @State private var limit = InboxView.page
    @State private var pending: PendingAction?
    @State private var detailID: Int?
    @AppStorage("inboxPinned") private var pinnedText = ""

    static let page = 60

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

    private func matches(_ m: Message) -> Bool {
        switch tab {
        case .all: return true
        case .decisions: return m.status == "open"
        case .risks: return m.tone == "bad"
        case .updates: return m.status != "open" && m.tone != "bad"
        }
    }

    private func filtered(_ e: GameEngine) -> [Message] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return e.state.inbox.filter { m in
            guard matches(m) else { return false }
            if let c = companyFilter, m.companyID != c { return false }
            if q.isEmpty { return true }
            let co = m.companyID != 0 ? (e.state.company(m.companyID)?.name ?? "") : ""
            return [m.title, m.body, m.from, co].contains { e.displayText($0, companyID: m.companyID).lowercased().contains(q) }
        }
    }

    // MARK: Blocks

    private static func urgency(_ m: Message, week: Int) -> Int {
        guard let exp = m.expiresWeek else { return 2 }
        let left = exp - week
        return left <= 1 ? 0 : 1
    }

    private func blocks(_ e: GameEngine, _ list: [Message]) -> [Block] {
        let week = e.state.week
        if byCompany {
            let ids = Array(Set(list.map { $0.companyID }))
            let sorted = ids.sorted { a, b in
                let oa = list.filter { $0.companyID == a && $0.status == "open" }.count, ob = list.filter { $0.companyID == b && $0.status == "open" }.count
                if oa != ob { return oa > ob }
                if (a == 0) != (b == 0) { return b == 0 }
                return (e.state.company(a)?.name ?? "") < (e.state.company(b)?.name ?? "")
            }
            return sorted.map { id in
                let msgs = list.filter { $0.companyID == id }
                let open = msgs.filter { $0.status == "open" }
                let rest = msgs.filter { $0.status != "open" }
                let name = id == 0 ? "Group and personal" : (e.state.company(id)?.name ?? "A former company")
                let note = open.isEmpty ? "\(msgs.count) message\(msgs.count == 1 ? "" : "s")" : "\(open.count) waiting"
                return Block(id: "co\(id)", title: name, note: note, tint: open.isEmpty ? P.inkFaint : P.caution,
                             companyID: id != 0 && e.state.company(id) != nil ? id : nil,
                             messages: open.sorted { (Self.urgency($0, week: week), $0.expiresWeek ?? .max) < (Self.urgency($1, week: week), $1.expiresWeek ?? .max) } + rest)
            }
        }
        let open = list.filter { $0.status == "open" }.sorted { ($0.expiresWeek ?? .max, -$0.week) < ($1.expiresWeek ?? .max, -$1.week) }
        let rest = list.filter { $0.status != "open" }
        var out: [Block] = []
        let bands: [(Int, String, String, Color)] = [
            (0, "Act this week", "Expires at the end of the week", P.loss),
            (1, "Coming up", "Expires in the next weeks", P.caution),
            (2, "No deadline", "Waits for you", P.inkFaint),
        ]
        for (u, title, note, tint) in bands {
            let msgs = open.filter { Self.urgency($0, week: week) == u }
            if !msgs.isEmpty { out.append(Block(id: "u\(u)", title: title + " · \(msgs.count)", note: note, tint: tint, messages: msgs)) }
        }
        if !rest.isEmpty { out.append(Block(id: "rest", title: open.isEmpty ? "" : "Everything else", messages: rest)) }
        return out
    }

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

    private func ask(_ message: Message, _ index: Int) {
        guard let e = store.engine, message.options.indices.contains(index) else { return }
        let opt = message.options[index]
        let label = e.displayText(opt["l"].string, companyID: message.companyID)
        // Payroll approvals are routine: answered at once. Every other decision is confirmed with what it does.
        if message.actionID.hasPrefix("pay29") { answer(message, index, label); return }
        var lines: [String] = []
        let d = e.displayText(opt["d"].string, companyID: message.companyID)
        if !d.isEmpty { lines.append(d) }
        lines += MessageCard.preview(e, message, opt)
        if index == 0 || message.options.count == 1 { lines += e.messageFacts(message) }
        let where_ = message.companyID != 0 ? (e.state.company(message.companyID)?.name ?? "") : ""
        pending = PendingAction(title: label + (where_.isEmpty ? "" : " · " + where_),
                                message: lines.isEmpty ? e.displayText(message.title, companyID: message.companyID) : lines.joined(separator: "\n"),
                                button: label) { answer(message, index, label) }
    }

    private func answer(_ message: Message, _ index: Int, _ label: String) {
        let ok = store.act { $0.answer(messageID: message.id, option: index) } ?? false
        if ok { Haptics.success(); store.show("Answered: \(label)", tone: "good") }
        else { Haptics.warning(); store.show("That answer could not be applied: the message is no longer open.", tone: "warn") }
    }

    private func takeRequest(_ proxy: ScrollViewProxy) {
        guard let id = store.takeMessageRequest() else { return }
        tab = .all; query = ""; companyFilter = nil
        if let i = store.engine?.state.inbox.firstIndex(where: { $0.id == id }) { limit = max(limit, i + waitingCount + 20) }
        detailID = id
        DispatchQueue.main.async { withAnimation { proxy.scrollTo(id, anchor: .top) } }
    }

    // MARK: Body

    /// The Inbox app, mail style: one row per message (sender icon circle, subject, preview, time, unread dot), swipe actions, and a
    /// detail sheet that keeps every decision and the company link. It is pushed on the Phone tab's stack (which owns the company
    /// destinations and the deep-link requests), so it has no stack of its own; its options menu sits in the app header.
    var body: some View {
        Group {
            if let e = store.engine {
                let list: [Message] = filtered(e)
                let cut = limited(blocks(e, list))
                ScrollViewReader { proxy in
                    mailList(e, list: list, cut: cut)
                        // A deep link (from Team, a suggestion or a toast) can arrive before this tab was ever shown: take it on appear too,
                        // and clear every filter so the requested one is not hidden.
                        .onAppear { takeRequest(proxy) }
                        .onChange(of: store.appRequest) { _, _ in takeRequest(proxy) }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: Theme.Space.xs) {
                searchField
                SectionTabs(items: Tab.allCases, title: { $0.rawValue }, selection: $tab, badge: { tab in tab == .decisions ? waitingCount : 0 })
            }
            .padding(.vertical, Theme.Space.xs).background(P.ground)
        }
        .onChange(of: tab) { _, _ in limit = Self.page }
        .onChange(of: query) { _, _ in limit = Self.page }
        // A company link tapped anywhere closes the detail first, so Back from the company lands on the Inbox list.
        .onChange(of: store.phonePath.count) { _, _ in detailID = nil }
        .sheet(isPresented: Binding(get: { detailID != nil }, set: { if !$0 { detailID = nil } })) { detailSheet }
        .confirmAction($pending)
        .ledgerBackground()
        .appScreen(title: "Inbox", subtitle: waitingCount > 0 ? "\(waitingCount) waiting for you" : "Decisions, offers and warnings") { optionsMenu }
        .environment(\.outsidePalette, P)
    }

    private func mailList(_ e: GameEngine, list: [Message], cut: (blocks: [Block], hidden: Int)) -> some View {
        let week: Int = e.state.week
        return List {
            if companyFilter != nil { filterLine(e).mailRowStyle() }
            if list.isEmpty { empty(e).mailRowStyle() }
            ForEach(cut.blocks) { (b: Block) in
                if !b.title.isEmpty { header(b).mailRowStyle() }
                ForEach(b.messages) { (m: Message) in
                    mailRow(m, week: week)
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
        .frame(maxWidth: 760).frame(maxWidth: .infinity)
    }

    private func mailRow(_ m: Message, week: Int) -> some View {
        let pinnedNow: Bool = pinned.contains(m.id)
        return InboxMailRow(message: m, week: week, pinned: pinnedNow, openDetail: { detailID = m.id })
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
                if m.companyID != 0, store.engine?.state.company(m.companyID) != nil {
                    Button { store.openCompany(m.companyID, section: MessageCard.section(for: m)) } label: { Label("Company", systemImage: "building.2") }
                        .tint(P.accent2)
                }
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
        if let e = store.engine, let id = detailID, let m = e.state.inbox.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack {
                        Text("Message").font(.serifTitle(24)).foregroundStyle(P.ink)
                        Spacer()
                        Button { detailID = nil } label: {
                            GlyphView(glyph: Glyph.close, size: 16, weight: 1.8, tint: P.ink)
                                .frame(width: 40, height: 40)
                                .overlay(Circle().strokeBorder(P.lineStrong, lineWidth: 1))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain).accessibilityLabel("Close message")
                    }
                    MessageCard(message: m, week: e.state.week, full: true, ask: ask)
                }
                .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(P.ground.ignoresSafeArea())
            .confirmAction($pending)
            .presentationDetents([.large])
        } else {
            Color.clear.onAppear { detailID = nil }
        }
    }

    /// The search box (the system search field needs a navigation bar, which the app header replaces).
    private var searchField: some View {
        HStack(spacing: 8) {
            GlyphView(glyph: Glyph.search, size: 16, weight: 1.8, tint: P.inkFaint)
            TextField("Search messages", text: $query).font(.system(size: 14)).foregroundStyle(P.ink).autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { GlyphView(glyph: Glyph.close, size: 13, weight: 2, tint: P.inkFaint).frame(width: 32, height: 32).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12).frame(minHeight: 36)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).fill(P.cardDeep))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(P.line, lineWidth: 1))
        .padding(.horizontal, 18)
    }

    private var optionsMenu: some View {
        Menu {
            Toggle("Group by company", isOn: $byCompany)
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

    private func header(_ b: Block) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(b.title.tidyMoney).capsLabel()
            if !b.note.isEmpty { Text(b.note.tidyMoney).font(.system(size: 11)).foregroundStyle(b.tint) }
            Spacer(minLength: 8)
            if let id = b.companyID {
                Button { store.openCompany(id) } label: {
                    LinkLabel(text: "Open")
                }.buttonStyle(.plain)
            }
        }
        .padding(.top, Theme.Space.s)
    }

    private func filterLine(_ e: GameEngine) -> some View {
        let name = companyFilter == 0 ? "Group and personal" : (companyFilter.flatMap { e.state.company($0)?.name } ?? "A former company")
        return HStack {
            Text("Only " + name).font(.system(size: 12.5)).foregroundStyle(P.inkSoft)
            Spacer()
            Button("Show all") { companyFilter = nil }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(P.accent).buttonStyle(.plain).frame(minHeight: 36)
        }
    }

    private func empty(_ e: GameEngine) -> some View {
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let text = searching ? "No message matches \u{201C}\(query)\u{201D}."
            : e.state.inbox.isEmpty ? "Nothing here yet. Offers, warnings and decisions arrive as the weeks go by."
            : tab == .decisions ? "No decision is waiting for you." : "Nothing under \(tab.rawValue.lowercased())."
        return VStack(spacing: 8) {
            IconCircle(glyph: tab == .decisions && !searching ? Glyph.check : Glyph.inbox, size: 56, tint: P.inkFaint)
            Text(text).font(.bodyText).foregroundStyle(P.inkSoft).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 80)
    }
}

struct MessageCard: View {
    private var P: OutsidePalette { .inbox }
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

    /// The part of the company a message is about, where that is clear from what it asks.
    static func section(for m: Message) -> CompanySection? {
        let a = m.actionID
        let key: String?
        if a.hasPrefix("pay29") { key = "finances" }
        else if ["staffx", "mgrraise", "mgrpoach", "prop", "mprop", "mfind11"].contains(a) || a.hasPrefix("tg58") { key = "staff" }
        else if a == "ctv" || a == "acct" { key = "customers" }
        else if a == "oil24" { key = "energy" }
        else if a == "club24" || a == "fb24" { key = "club" }
        else if a == "wx56prep" { key = "operations" }
        else { key = nil }
        return key.flatMap { CompanySection(key: $0) }
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
                InboxAvatar(initial: message.inboxInitial, glyph: glyph, tint: tint, size: 30)
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
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .bottom, spacing: 8) {
                    InboxAvatar(initial: message.inboxInitial, glyph: glyph, tint: tint, size: 36)
                    bubble(open: open)
                    Spacer(minLength: 24)
                }
                if open { decision }
            }
            .onAppear { if !open { store.markRead(message.id) } }
        }
    }

    /// The message as a chat bubble: sender and age on top, the subject, the text, what it means, and the link to the company.
    private func bubble(open: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(message.from).font(.caption.weight(.semibold)).foregroundStyle(tint).lineLimit(1)
                Spacer(minLength: 8)
                Text(age).font(.caption2).foregroundStyle(P.inkFaint)
                if !message.isRead || open { Circle().fill(open ? P.caution : P.accent).frame(width: 7, height: 7) }
            }
            Text(text(message.title)).font(.bodyText.weight(.semibold)).foregroundStyle(P.ink).fixedSize(horizontal: false, vertical: true)
            Text(text(message.body)).font(.caption).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true)
            if open, let facts = store.engine?.messageFacts(message), !facts.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(facts, id: \.self) { f in Text("• " + f).font(.caption2).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true) }
                }.padding(.top, 2)
            }
            if let o = store.engine?.answeredOutcome(message) {
                Text(o).font(.caption2.weight(.medium)).foregroundStyle(P.inkFaint).padding(.top, 2)
            }
            if message.companyID != 0, let co = store.engine?.state.company(message.companyID) {
                let sec = Self.section(for: message)
                Button { store.openCompany(co.id, section: sec) } label: {
                    LinkLabel(text: "Open \(co.name)" + (sec.map { " · " + $0.rawValue } ?? ""))
                }.buttonStyle(.plain).accessibilityIdentifier("open-company-link")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(shape.fill(P.card))
        .overlay(shape.strokeBorder(P.line, lineWidth: 1))
    }

    @ViewBuilder private var decision: some View {
        if let exp = message.expiresWeek {
            let left = exp - week
            HStack(spacing: 6) {
                GlyphView(glyph: Glyph.clock, size: 14, weight: 1.8, tint: left <= 1 ? P.loss : P.caution)
                Text(left > 0 ? "Expires in \(left) week\(left == 1 ? "" : "s")" : "Expires this week").font(.system(size: 12, weight: .medium)).foregroundStyle(left <= 1 ? P.loss : P.caution)
            }
            .accessibilityElement(children: .combine)
            if let leave = store.engine?.expiryOutcome(message) {
                Text(leave).font(.caption2).foregroundStyle(P.inkFaint)
            }
        }
        let opts = Array(message.options.enumerated())
        if opts.isEmpty {
            Text("Nothing to choose here. This is dealt with in the company it concerns.").font(.caption).foregroundStyle(P.inkSoft)
        }
        let detailed = message.options.contains { !$0["d"].string.isEmpty || !preview($0).isEmpty }
        if !detailed && opts.count <= 3 {
            WrapRow {
                ForEach(opts, id: \.offset) { idx, opt in
                    if idx == 0 {
                        Button(text(opt["l"].string)) { ask(message, idx) }.buttonStyle(QuietButtonStyle())
                    } else {
                        Button(text(opt["l"].string)) { ask(message, idx) }.buttonStyle(GreyOutlineButtonStyle())
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                ForEach(opts, id: \.offset) { idx, opt in
                    Button { ask(message, idx) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(text(opt["l"].string)).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(P.ink)
                            if !opt["d"].string.isEmpty { Text(text(opt["d"].string)).font(.caption).foregroundStyle(P.inkSoft).multilineTextAlignment(.leading) }
                            ForEach(preview(opt), id: \.self) { line in
                                Text("• " + line).font(.caption2).foregroundStyle(P.accent.opacity(0.9))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10).padding(.leading, 12).padding(.trailing, 32)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(idx == 0 ? P.accentSelected : P.cardDeep))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(idx == 0 ? P.accent : P.line, lineWidth: 1))
                        .overlay(alignment: .trailing) { GlyphView(glyph: Glyph.chevron, size: 13, weight: 2, tint: P.inkDim).padding(.trailing, 12) }
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
