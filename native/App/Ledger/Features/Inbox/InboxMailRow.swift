import SwiftUI
import GameCore
import Simulation
import Businesses
import Events

extension Message {
    var inboxGlyph: String {
        if doc != nil { return Glyph.reports }
        if actionID.hasPrefix("pay29") { return Glyph.bank }
        if actionID == "staffx" || actionID == "mgrraise" || actionID == "mgrpoach" { return Glyph.person }
        if status == "open" { return tone == "bad" ? Glyph.warning : Glyph.inbox }
        switch tone { case "bad": return Glyph.warning; case "good": return Glyph.check; default: return Glyph.news }
    }
    func inboxTint(_ p: OutsidePalette) -> Color {
        if status == "open" { return tone == "bad" ? p.loss : p.accent }
        switch tone { case "good": return p.gain; case "bad": return p.loss; case "warn": return p.caution; default: return p.inkSoft }
    }
    var inboxInitial: String { String(from.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
}

extension Message {
    var inboxCategoryGlyph: String {
        let words: String = (title + " " + body).lowercased()
        if actionID.hasPrefix("pay29") || ["loan", "tax", "invoice", "bank", "fine", "payment", "overdraft"].contains(where: { words.contains($0) }) { return Glyph.bank }
        if ["staffx", "mgrraise", "mgrpoach"].contains(actionID) || ["employee", "worker", "staff", "applicant", "manager", "salary"].contains(where: { words.contains($0) }) { return Glyph.team }
        if ["prop", "mprop", "mfind11"].contains(actionID) || ["premises", "rent", "lease", "landlord", "property"].contains(where: { words.contains($0) }) { return Glyph.home }
        if ["rival", "competitor", "opens next door", "undercut"].contains(where: { words.contains($0) }) { return Glyph.market }
        if actionID == "ctv" || actionID == "acct" || ["customer", "review", "complaint", "queue"].contains(where: { words.contains($0) }) { return Glyph.person }
        return Glyph.news
    }
}

extension View {
    func mailRowStyle() -> some View {
        self.listRowBackground(Color.clear)
            .listRowSeparatorTint(OutsidePalette.game.hairline)
            .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
    }
}

struct InboxMailRow: View {
    private var P: OutsidePalette { .game }
    @EnvironmentObject var store: GameStore
    var message: Message
    var week: Int
    var pinned: Bool
    var openDetail: () -> Void
    var answer: ((Int) -> Void)? = nil
    var guided: Bool = false

    private var open: Bool { message.status == "open" }
    private var unread: Bool { open || !message.isRead }
    private func text(_ s: String) -> String { (store.engine?.displayText(s, companyID: message.companyID) ?? s).tidyMoney }

    private var title: String {
        let t: String = text(message.title)
        guard let e = store.engine, message.companyID != 0, e.state.companies.filter({ $0.status.isLive }).count > 1,
              let co = e.state.company(message.companyID) else { return t }
        return co.name + " \u{00B7} " + t
    }

    private var consequence: String {
        let e: GameEngine? = store.engine
        let raw: String = (open ? nil : e?.answeredOutcome(message)) ?? message.body
        return text(raw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Button { Haptics.tap(); openDetail() } label: { content }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("inbox-row")
            if let answer, open, message.doc == nil, (1...3).contains(message.options.count) { inlineOptions(answer) }
        }
        .padding(.vertical, Theme.Space.m)
    }

    /// The same answer layout as every decision, in the compact size; a tap sends the answer's own index.
    private func inlineOptions(_ answer: @escaping (Int) -> Void) -> some View {
        DecisionChoices(labels: message.options.map { (o: JSONValue) -> String in text(o["l"].string) }, compact: true,
                        identifier: { (_: Int) -> String in "inbox-inline-option" }, pick: answer)
            .padding(.leading, Self.avatar + Theme.Space.m - Theme.Space.s)
    }

    static let avatar: CGFloat = 36

    private var content: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            InboxAvatar(initial: "", glyph: message.inboxCategoryGlyph, tint: unread ? message.inboxTint(P) : P.inkFaint, size: Self.avatar, face: message.inboxFace(store.engine))
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title).textStyle(.headline, tint: unread ? P.ink : P.inkSoft, weight: unread ? .semibold : .regular).lineLimit(2)
                Text(consequence).textStyle(.caption, tint: P.inkSoft).lineLimit(2)
                if guided {
                    Text("Read next").textStyle(.caption, tint: P.accent, weight: .semibold).lineLimit(1)
                }
                if !message.handledBy.isEmpty {
                    Text("Handled by " + message.handledBy).textStyle(.caption, tint: P.accent, weight: .medium).lineLimit(1)
                }
                if store.engine?.messageDocument(messageID: message.id) != nil {
                    Text("Read the report").textStyle(.caption, tint: P.accent, weight: .medium).lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Space.s)
            if open { expiryPill } else if unread { Circle().fill(P.accent).frame(width: 7, height: 7).padding(.top, Theme.Space.xs).accessibilityLabel("Unread") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, guided ? Theme.Space.s : 0)
        .overlay(alignment: .leading) {
            if guided { Capsule().fill(P.accent.opacity(0.7)).frame(width: 3).accessibilityHidden(true) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var expiryPill: some View {
        if let exp = message.expiresWeek {
            let left: Int = exp - week
            let tint: Color = left <= 1 ? P.loss : P.caution
            Text(left > 0 ? "\(left)w left" : "This week")
                .textStyle(.caption, tint: tint, numeric: true, weight: .semibold).lineLimit(1).fixedSize()
        }
    }
}

struct InboxAvatar: View {
    var initial: String
    var glyph: String
    var tint: Color
    var size: CGFloat = 44
    var face: String? = nil

    var body: some View {
        if FaceSheet.image(face) != nil {
            ThumbnailView(kind: .person, key: "inbox", size: size, face: face)
        } else {
            ZStack {
                Circle().fill(tint.opacity(0.22))
                if initial.isEmpty {
                    GlyphView(glyph: glyph, size: size * 0.45, weight: 1.6, tint: tint)
                } else {
                    Text(initial).font(.system(size: size * 0.42, weight: .semibold, design: .rounded)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }
}

extension Message {
    func inboxFace(_ engine: GameEngine?) -> String? {
        guard let engine else { return nil }
        let d: JSONValue = value("data")
        for k in ["sid", "npc", "pid"] where !d[k].isNull {
            if let f = engine.state.people[d[k].int]?.faceKey { return f }
        }
        let name: String = from.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        guard !name.isEmpty, let co = engine.state.company(companyID), let mid = co.managerID, let m = engine.state.people[mid], m.name == name else { return nil }
        return m.faceKey
    }
}
