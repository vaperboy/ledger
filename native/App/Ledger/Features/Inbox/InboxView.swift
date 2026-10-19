import SwiftUI
import GameCore
import Simulation
import Events
import Countries

/// Decisions and news. A decision shows what each choice does before you commit, and when the offer expires.
struct InboxView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        NavigationStack {
            Group {
                if let e = store.engine {
                    let messages = e.state.inbox
                    if messages.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray").font(.largeTitle).foregroundStyle(Theme.ivoryFaint)
                            Text("Nothing here yet").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: Theme.Space.m) {
                                    ForEach(messages.prefix(80)) { m in MessageCard(message: m, week: e.state.week).id(m.id) }
                                }
                                .padding(Theme.Space.l)
                                .frame(maxWidth: 760).frame(maxWidth: .infinity)
                            }
                            .onChange(of: store.openMessageID) { _, id in
                                if let id { withAnimation { proxy.scrollTo(id, anchor: .top) }; store.openMessageID = nil }
                            }
                        }
                    }
                }
            }
            .ledgerBackground()
            .navigationTitle("Inbox")
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

    private func preview(_ option: JSONValue) -> [String] {
        guard let e = store.engine else { return [] }
        let cur = message.companyID != 0 ? (e.state.company(message.companyID).map { e.currency(for: $0) } ?? e.homeCurrency) : e.homeCurrency
        return EffectPreview.lines(option["fx"], currency: cur)
    }

    var body: some View {
        let open = message.status == "open"
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline) {
                    if !message.isRead || open { Circle().fill(open ? Theme.caution : Theme.gold).frame(width: 7, height: 7) }
                    Text(message.title).font(.system(.headline, design: .serif)).foregroundStyle(Theme.ivory)
                    Spacer()
                    Text(message.from).font(.caption).foregroundStyle(Theme.ivoryFaint)
                }
                Text(message.body).font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                if open {
                    if let exp = message.expiresWeek {
                        let left = exp - week
                        Chip(text: left > 0 ? "Expires in \(left) week\(left == 1 ? "" : "s")" : "Expires this week", tint: left <= 1 ? Theme.loss : Theme.caution)
                    }
                    VStack(spacing: 8) {
                        ForEach(Array(message.options.enumerated()), id: \.offset) { idx, opt in
                            Button { store.answer(message, option: idx) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(opt["l"].string).font(.system(.subheadline).weight(.semibold)).foregroundStyle(Theme.ivory)
                                    if !opt["d"].string.isEmpty { Text(opt["d"].string).font(.caption).foregroundStyle(Theme.ivoryMuted).multilineTextAlignment(.leading) }
                                    ForEach(preview(opt), id: \.self) { line in
                                        Text("• " + line).font(.caption2).foregroundStyle(Theme.gold.opacity(0.9))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Theme.Space.m)
                                .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.walnut.opacity(0.6)))
                                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.gold.opacity(0.35), lineWidth: 0.75))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onAppear { if !open { store.markRead(message.id) } }
        .opacity(open || !message.isRead ? 1 : 0.8)
    }
}
