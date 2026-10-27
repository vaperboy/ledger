import SwiftUI
import GameCore
import Simulation

extension Message {
    /// The sender's icon circle in the Inbox: payroll from the bank, people matters from a person, otherwise by urgency and tone.
    var inboxGlyph: String {
        if actionID.hasPrefix("pay29") { return Glyph.bank }
        if actionID == "staffx" || actionID == "mgrraise" || actionID == "mgrpoach" { return Glyph.person }
        if status == "open" { return tone == "bad" ? Glyph.warning : Glyph.inbox }
        switch tone { case "bad": return Glyph.warning; case "good": return Glyph.check; default: return Glyph.news }
    }
    var inboxTint: Color {
        if status == "open" { return tone == "bad" ? Theme.loss : Theme.gold }
        return Theme.tone(tone == "n" ? "" : tone)
    }
}

extension View {
    /// A list row without the system chrome: page background, a hairline underneath, mail-width insets.
    func mailRowStyle() -> some View {
        self.listRowBackground(Color.clear)
            .listRowSeparatorTint(Theme.tableLine)
            .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
    }
}

/// One message in the mail-style list: unread dot, sender icon circle, sender and time, subject, a two-line preview, and (for
/// a decision) how long it waits. The company link is its own button so it works without opening the message.
struct InboxMailRow: View {
    @EnvironmentObject var store: GameStore
    var message: Message
    var week: Int
    var pinned: Bool
    var openDetail: () -> Void

    private var open: Bool { message.status == "open" }
    private var unread: Bool { open || !message.isRead }
    private func text(_ s: String) -> String { (store.engine?.displayText(s, companyID: message.companyID) ?? s).tidyMoney }

    private var time: String {
        let d: Int = week - message.week
        return d <= 0 ? "Now" : "\(d)w ago"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { Haptics.tap(); openDetail() } label: { content }
                .buttonStyle(.plain)
                .accessibilityIdentifier("inbox-row")
            companyLink
        }
        .padding(.vertical, 8)
    }

    private var content: some View {
        let dot: Color = unread ? (open ? Theme.caution : Theme.gold) : Color.clear
        return HStack(alignment: .top, spacing: 10) {
            Circle().fill(dot).frame(width: 8, height: 8).padding(.top, 17).accessibilityHidden(true)
            IconCircle(glyph: message.inboxGlyph, size: 40, tint: message.inboxTint)
            textColumn
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            senderLine
            Text(text(message.title)).font(.system(size: 14.5, weight: unread ? .semibold : .regular))
                .foregroundStyle(unread ? Theme.ivory : Theme.ivoryMuted).lineLimit(2).multilineTextAlignment(.leading)
            Text(text(message.body)).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(2).multilineTextAlignment(.leading)
            if open { deadline }
        }
    }

    private var senderLine: some View {
        HStack(spacing: 6) {
            Text(message.from).font(.system(size: 12.5, weight: unread ? .semibold : .regular)).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
            if pinned { GlyphView(glyph: Glyph.goals, size: 11, weight: 1.8, tint: Theme.gold).accessibilityLabel("Pinned") }
            Spacer(minLength: 6)
            Text(time).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
        }
    }

    @ViewBuilder private var deadline: some View {
        if let exp = message.expiresWeek {
            let left: Int = exp - week
            let words: String = left > 0 ? "Expires in \(left) week\(left == 1 ? "" : "s")" : "Expires this week"
            let tint: Color = left <= 1 ? Theme.loss : Theme.caution
            HStack(spacing: 5) {
                GlyphView(glyph: Glyph.clock, size: 12, weight: 1.8, tint: tint)
                Text(words).font(.system(size: 11.5, weight: .medium)).foregroundStyle(tint)
            }
            .padding(.top, 2)
        } else {
            Text("Waiting for your answer").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.caution).padding(.top, 2)
        }
    }

    @ViewBuilder private var companyLink: some View {
        if message.companyID != 0, let co = store.engine?.state.company(message.companyID) {
            let sec: CompanySection? = MessageCard.section(for: message)
            let name: String = "Open \(co.name)" + (sec.map { " · " + $0.rawValue } ?? "")
            Button { store.openCompany(co.id, section: sec) } label: {
                HStack(spacing: 4) {
                    Text(name).font(.system(size: 12, weight: .medium))
                    GlyphView(glyph: Glyph.chevron, size: 10, weight: 2, tint: Theme.gold)
                }
                .foregroundStyle(Theme.gold).frame(minHeight: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 66)
            .accessibilityIdentifier("open-company-link")
        }
    }
}
