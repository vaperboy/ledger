import SwiftUI
import GameCore
import Simulation
import Events
import Countries

/// Decisions and news. A decision shows what each choice does before you commit, and when the offer expires.
struct InboxView: View {
    enum Tab: String, CaseIterable, Hashable { case all = "All", decisions = "Decisions", risks = "Risks", updates = "Updates" }
    @EnvironmentObject var store: GameStore
    @State private var tab: Tab = .all

    private var waitingCount: Int { store.engine?.state.inbox.filter { msg in msg.status == "open" }.count ?? 0 }

    private func matches(_ m: Message) -> Bool {
        switch tab {
        case .all: return true
        case .decisions: return m.status == "open"
        case .risks: return m.tone == "bad"
        case .updates: return m.status != "open" && m.tone != "bad"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let e = store.engine {
                    let messages = e.state.inbox.filter(matches)
                    let waiting = e.state.inbox.filter { $0.status == "open" }.count
                    if messages.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray").font(.largeTitle).foregroundStyle(Theme.ivoryFaint)
                            Text(tab == .all ? "Nothing here yet" : "Nothing under \(tab.rawValue.lowercased())").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: Theme.Space.m) {
                                    if waiting > 0 && tab == .all {
                                        Text("\(waiting) decision\(waiting == 1 ? "" : "s") waiting for you").font(.caption.weight(.semibold)).foregroundStyle(Theme.caution).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    ForEach(messages.prefix(80)) { m in MessageCard(message: m, week: e.state.week).id(m.id) }
                                }
                                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                                .frame(maxWidth: 760).frame(maxWidth: .infinity)
                            }
                            .onChange(of: store.openMessageID) { _, id in
                                if let id { withAnimation { proxy.scrollTo(id, anchor: .top) }; store.openMessageID = nil }
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                SectionTabs(items: Tab.allCases, title: { $0.rawValue }, selection: $tab, badge: { tab in tab == .decisions ? waitingCount : 0 }).padding(.vertical, Theme.Space.xs).background(Theme.walnut.opacity(0.9))
            }
            .ledgerBackground()
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Mark all read") {
                        store.act { e in e.update { s, _, _ in for i in s.inbox.indices where s.inbox[i].status != "open" { s.inbox[i].isRead = true } } }
                    }.disabled(store.unreadCount == 0)
                }
            }
        }
    }
}

struct MessageCard: View {
    @EnvironmentObject var store: GameStore
    var message: Message
    var week: Int

    private func text(_ s: String) -> String { store.engine?.localized(s, companyID: message.companyID) ?? s }

    private func preview(_ option: JSONValue) -> [String] {
        guard let e = store.engine else { return [] }
        let cur = message.companyID != 0 ? (e.state.company(message.companyID).map { e.currency(for: $0) } ?? e.homeCurrency) : e.homeCurrency
        return EffectPreview.lines(option["fx"], currency: cur)
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
                Text(text(message.title)).font(.subheadline).foregroundStyle(Theme.ivoryMuted).lineLimit(2)
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
                        }
                    }
                    if open {
                        if let exp = message.expiresWeek {
                            let left = exp - week
                            Chip(text: left > 0 ? "Expires in \(left) week\(left == 1 ? "" : "s")" : "Expires this week", tint: left <= 1 ? Theme.loss : Theme.caution, symbol: "clock")
                        }
                        let opts = Array(message.options.enumerated())
                        if message.expiresWeek != nil {
                            Text("If you leave it, the cheapest answer is taken when time runs out.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        }
                        if opts.isEmpty {
                            Text("Nothing to choose here. This is dealt with in the company it concerns.").font(.caption).foregroundStyle(Theme.ivoryMuted)
                        }
                        let detailed = message.options.contains { !$0["d"].string.isEmpty || !preview($0).isEmpty }
                        if !detailed && opts.count <= 3 {
                            HStack(spacing: 8) {
                                ForEach(opts, id: \.offset) { idx, opt in
                                    if idx == 0 {
                                        Button(text(opt["l"].string)) { store.answer(message, option: idx) }.buttonStyle(SmallGoldButtonStyle())
                                    } else {
                                        Button(text(opt["l"].string)) { store.answer(message, option: idx) }.buttonStyle(SmallOutlineButtonStyle())
                                    }
                                }
                            }
                        } else {
                            VStack(spacing: 8) {
                                ForEach(opts, id: \.offset) { idx, opt in
                                    Button { store.answer(message, option: idx) } label: {
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
            }
            .onAppear { if !open { store.markRead(message.id) } }
        }
    }
}
