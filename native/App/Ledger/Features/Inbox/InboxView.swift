import SwiftUI
import GameCore
import Simulation
import Events
import Countries

/// Decisions and news. Decisions come first, by how soon they expire; each shows what every choice does before you commit and
/// opens the company (and the section) it concerns. Search, a company filter and grouping keep hundreds of messages usable.
struct InboxView: View {
    enum Tab: String, CaseIterable, Hashable { case all = "All", decisions = "Decisions", risks = "Risks", updates = "Updates" }
    @EnvironmentObject var store: GameStore
    @State private var tab: Tab = .all
    @State private var query = ""
    /// nil = every company; 0 = messages about the group or you personally
    @State private var companyFilter: Int? = nil
    @State private var byCompany = false
    @State private var limit = InboxView.page
    @State private var pending: PendingAction?
    @State private var path: [CompanyRoute] = []

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
                return Block(id: "co\(id)", title: name, note: note, tint: open.isEmpty ? Theme.ivoryFaint : Theme.caution,
                             companyID: id != 0 && e.state.company(id) != nil ? id : nil,
                             messages: open.sorted { (Self.urgency($0, week: week), $0.expiresWeek ?? .max) < (Self.urgency($1, week: week), $1.expiresWeek ?? .max) } + rest)
            }
        }
        let open = list.filter { $0.status == "open" }.sorted { ($0.expiresWeek ?? .max, -$0.week) < ($1.expiresWeek ?? .max, -$1.week) }
        let rest = list.filter { $0.status != "open" }
        var out: [Block] = []
        let bands: [(Int, String, String, Color)] = [
            (0, "Act this week", "Expires at the end of the week", Theme.loss),
            (1, "Coming up", "Expires in the next weeks", Theme.caution),
            (2, "No deadline", "Waits for you", Theme.ivoryFaint),
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
        guard let id = store.openMessageID else { return }
        tab = .all; query = ""; companyFilter = nil; path = []
        if let i = store.engine?.state.inbox.firstIndex(where: { $0.id == id }) { limit = max(limit, i + waitingCount + 20) }
        store.openMessageID = nil
        DispatchQueue.main.async { withAnimation { proxy.scrollTo(id, anchor: .top) } }
    }

    // MARK: Body

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let e = store.engine {
                    let list = filtered(e)
                    let cut = limited(blocks(e, list))
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: Theme.Space.m) {
                                if companyFilter != nil { filterLine(e) }
                                if list.isEmpty { empty(e) }
                                ForEach(cut.blocks) { b in
                                    if !b.title.isEmpty { header(b) }
                                    ForEach(b.messages) { m in MessageCard(message: m, week: e.state.week, ask: ask).id(m.id) }
                                }
                                if cut.hidden > 0 {
                                    Button { limit += Self.page } label: {
                                        Text("Show \(min(Self.page, cut.hidden)) more of \(cut.hidden)").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gold)
                                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    }.buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                            .frame(maxWidth: 760).frame(maxWidth: .infinity)
                        }
                        // A deep link (from Team, a suggestion or a toast) can arrive before this tab was ever shown: take it on appear too,
                        // and clear every filter so the requested one is not hidden.
                        .onAppear { takeRequest(proxy) }
                        .onChange(of: store.openMessageID) { _, _ in takeRequest(proxy) }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                SectionTabs(items: Tab.allCases, title: { $0.rawValue }, selection: $tab, badge: { tab in tab == .decisions ? waitingCount : 0 }).padding(.vertical, Theme.Space.xs).background(Theme.walnut.opacity(0.9))
            }
            .searchable(text: $query, prompt: "Search messages")
            .onChange(of: tab) { _, _ in limit = Self.page }
            .onChange(of: query) { _, _ in limit = Self.page }
            .confirmAction($pending)
            .ledgerBackground()
            .companyRouteDestinations()
            .routeRequests(for: .inbox, path: $path)
            .returnBar(for: .inbox)
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) { optionsMenu }
            }
        }
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
                store.act { e in e.update { s, _, _ in for i in s.inbox.indices where s.inbox[i].status != "open" { s.inbox[i].isRead = true } } }
            }.disabled(store.unreadCount == 0)
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle").accessibilityLabel("Inbox options")
        }
    }

    private func header(_ b: Block) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(b.title).capsLabel()
            if !b.note.isEmpty { Text(b.note).font(.system(size: 11)).foregroundStyle(b.tint) }
            Spacer(minLength: 8)
            if let id = b.companyID {
                Button { store.openCompany(id) } label: { Text("Open →").font(.system(size: 12)).foregroundStyle(Theme.gold) }.buttonStyle(.plain)
            }
        }
        .padding(.top, Theme.Space.s)
    }

    private func filterLine(_ e: GameEngine) -> some View {
        let name = companyFilter == 0 ? "Group and personal" : (companyFilter.flatMap { e.state.company($0)?.name } ?? "A former company")
        return HStack {
            Text("Only " + name).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
            Spacer()
            Button("Show all") { companyFilter = nil }.font(.system(size: 12.5)).foregroundStyle(Theme.gold).buttonStyle(.plain)
        }
    }

    private func empty(_ e: GameEngine) -> some View {
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let text = searching ? "No message matches \u{201C}\(query)\u{201D}."
            : e.state.inbox.isEmpty ? "Nothing here yet. Offers, warnings and decisions arrive as the weeks go by."
            : tab == .decisions ? "No decision is waiting for you." : "Nothing under \(tab.rawValue.lowercased())."
        return VStack(spacing: 8) {
            Image(systemName: tab == .decisions && !searching ? "checkmark.circle" : "tray").font(.largeTitle).foregroundStyle(Theme.ivoryFaint)
            Text(text).font(.bodyText).foregroundStyle(Theme.ivoryMuted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 80)
    }
}

struct MessageCard: View {
    @EnvironmentObject var store: GameStore
    var message: Message
    var week: Int
    /// Asks to answer with an option (the Inbox confirms it first).
    var ask: (Message, Int) -> Void

    private func text(_ s: String) -> String { store.engine?.displayText(s, companyID: message.companyID) ?? s }

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

    private var symbol: String {
        if message.actionID.hasPrefix("pay29") { return "banknote" }
        if message.actionID == "staffx" || message.actionID == "mgrraise" || message.actionID == "mgrpoach" { return "person.fill" }
        if message.status == "open" { return message.tone == "bad" ? "exclamationmark.triangle.fill" : "briefcase.fill" }
        switch message.tone { case "bad": return "exclamationmark.triangle.fill"; case "good": return "checkmark.circle.fill"; default: return "newspaper.fill" }
    }
    private var tint: Color {
        if message.status == "open" { return message.tone == "bad" ? Theme.loss : Theme.gold }
        return Theme.tone(message.tone == "n" ? "" : message.tone)
    }
    private var age: String {
        let d = week - message.week
        return d <= 0 ? "This week" : d == 1 ? "1 week ago" : "\(d) weeks ago"
    }

    var body: some View {
        let open = message.status == "open"
        if !open && message.tone != "bad" && message.isRead {
            HStack(alignment: .center, spacing: 10) {
                IconBadge(symbol: symbol, tint: tint, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(text(message.title)).font(.subheadline).foregroundStyle(Theme.ivoryMuted).lineLimit(2)
                    if let o = store.engine?.answeredOutcome(message) { Text(o).font(.caption2).foregroundStyle(Theme.ivoryFaint).lineLimit(1) }
                }
                Spacer()
                Text(message.from).font(.caption2).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
            }
            .padding(.horizontal, Theme.Space.s).padding(.vertical, 2)
        } else {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack(alignment: .top, spacing: Theme.Space.m) {
                        IconBadge(symbol: symbol, tint: tint, size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(message.from).font(.caption.weight(.semibold)).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
                                Spacer()
                                Text(age).font(.caption2).foregroundStyle(Theme.ivoryFaint)
                                if !message.isRead || open { Circle().fill(open ? Theme.caution : Theme.gold).frame(width: 7, height: 7) }
                            }
                            Text(text(message.title)).font(.bodyText.weight(.semibold)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                            Text(text(message.body)).font(.caption).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                            if open, let facts = store.engine?.messageFacts(message), !facts.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(facts, id: \.self) { f in Text("• " + f).font(.caption2).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) }
                                }.padding(.top, 2)
                            }
                            if let o = store.engine?.answeredOutcome(message) {
                                Text(o).font(.caption2.weight(.medium)).foregroundStyle(Theme.ivoryFaint).padding(.top, 2)
                            }
                            if message.companyID != 0, let co = store.engine?.state.company(message.companyID) {
                                let sec = Self.section(for: message)
                                Button { store.openCompany(co.id, section: sec) } label: {
                                    Text("Open \(co.name)" + (sec.map { " · " + $0.rawValue } ?? "") + " →").font(.caption.weight(.medium)).foregroundStyle(Theme.gold)
                                }.buttonStyle(.plain).padding(.top, 2).accessibilityIdentifier("open-company-link")
                            }
                        }
                    }
                    if open { decision }
                }
            }
            .onAppear { if !open { store.markRead(message.id) } }
        }
    }

    @ViewBuilder private var decision: some View {
        if let exp = message.expiresWeek {
            let left = exp - week
            Chip(text: left > 0 ? "Expires in \(left) week\(left == 1 ? "" : "s")" : "Expires this week", tint: left <= 1 ? Theme.loss : Theme.caution, symbol: "clock")
            if let leave = store.engine?.expiryOutcome(message) {
                Text(leave).font(.caption2).foregroundStyle(Theme.ivoryFaint)
            }
        }
        let opts = Array(message.options.enumerated())
        if opts.isEmpty {
            Text("Nothing to choose here. This is dealt with in the company it concerns.").font(.caption).foregroundStyle(Theme.ivoryMuted)
        }
        let detailed = message.options.contains { !$0["d"].string.isEmpty || !preview($0).isEmpty }
        if !detailed && opts.count <= 3 {
            HStack(spacing: 8) {
                ForEach(opts, id: \.offset) { idx, opt in
                    if idx == 0 {
                        Button(text(opt["l"].string)) { ask(message, idx) }.buttonStyle(SmallGoldButtonStyle())
                    } else {
                        Button(text(opt["l"].string)) { ask(message, idx) }.buttonStyle(SmallOutlineButtonStyle())
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                ForEach(opts, id: \.offset) { idx, opt in
                    Button { ask(message, idx) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(text(opt["l"].string)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ivory)
                            if !opt["d"].string.isEmpty { Text(text(opt["d"].string)).font(.caption).foregroundStyle(Theme.ivoryMuted).multilineTextAlignment(.leading) }
                            ForEach(preview(opt), id: \.self) { line in
                                Text("• " + line).font(.caption2).foregroundStyle(Theme.gold.opacity(0.9))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Space.m)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Color.white.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(idx == 0 ? Theme.gold.opacity(0.55) : Theme.hairline, lineWidth: 0.75))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
