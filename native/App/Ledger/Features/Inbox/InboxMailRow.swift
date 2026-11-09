import SwiftUI
import GameCore
import Simulation
import Businesses

extension Message {
    /// The sender's icon circle in the Inbox: payroll from the bank, people matters from a person, otherwise by urgency and tone.
    var inboxGlyph: String {
        if doc != nil { return Glyph.reports }
        if actionID.hasPrefix("pay29") { return Glyph.bank }
        if actionID == "staffx" || actionID == "mgrraise" || actionID == "mgrpoach" { return Glyph.person }
        if status == "open" { return tone == "bad" ? Glyph.warning : Glyph.inbox }
        switch tone { case "bad": return Glyph.warning; case "good": return Glyph.check; default: return Glyph.news }
    }
    /// The avatar colour for a sender in the Inbox, from the messages palette.
    func inboxTint(_ p: OutsidePalette) -> Color {
        if status == "open" { return tone == "bad" ? p.loss : p.accent }
        switch tone { case "good": return p.gain; case "bad": return p.loss; case "warn": return p.caution; default: return p.inkSoft }
    }
    /// The letter in the avatar circle: the first letter of the sender's name.
    var inboxInitial: String { String(from.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
}

extension Message {
    /// Row icon: money, people, customers, rivals, property or other, from what the message is about.
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
    /// A list row without the system chrome: page background, a hairline underneath, mail-width insets.
    func mailRowStyle() -> some View {
        self.listRowBackground(Color.clear)
            .listRowSeparatorTint(OutsidePalette.game.hairline)
            .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
    }
}

/// One message in the mail-style list: unread dot, sender icon circle, sender and time, subject, a two-line preview, and (for
/// a decision) how long it waits. The company link is its own button so it works without opening the message.
struct InboxMailRow: View {
    private var P: OutsidePalette { .game }
    @EnvironmentObject var store: GameStore
    var message: Message
    var week: Int
    var pinned: Bool
    var openDetail: () -> Void
    /// A decision with one to three options is answered from the row (the same confirmation rules apply).
    var answer: ((Int) -> Void)? = nil
    /// Set while the first-steps guide is running: a gentle marker on the messages worth opening next.
    var guided: Bool = false

    private var open: Bool { message.status == "open" }
    private var unread: Bool { open || !message.isRead }
    private func text(_ s: String) -> String { (store.engine?.displayText(s, companyID: message.companyID) ?? s).tidyMoney }

    /// With more than one company the company name leads the title.
    private var title: String {
        let t: String = text(message.title)
        guard let e = store.engine, message.companyID != 0, e.state.companies.filter({ $0.status.isLive }).count > 1,
              let co = e.state.company(message.companyID) else { return t }
        return co.name + " \u{00B7} " + t
    }

    /// One grey line: what happens if it is left (a decision), what came of it (an answered one), else the text.
    private var consequence: String {
        let e: GameEngine? = store.engine
        let raw: String = (open ? e?.expiryOutcome(message) : e?.answeredOutcome(message)) ?? message.body
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

    /// The options as buttons under the row, side by side when they fit, else stacked; the first (the suggested answer) in the accent.
    private func inlineOptions(_ answer: @escaping (Int) -> Void) -> some View {
        let labels: [String] = message.options.map { (o: JSONValue) -> String in text(o["l"].string) }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.s) { optionButtons(labels, answer, fullWidth: false) }
            VStack(alignment: .leading, spacing: Theme.Space.s) { optionButtons(labels, answer, fullWidth: true) }
        }
        .padding(.leading, Self.avatar + Theme.Space.m - Theme.Space.s)
    }

    static let avatar: CGFloat = 36

    private func optionButtons(_ labels: [String], _ answer: @escaping (Int) -> Void, fullWidth: Bool) -> some View {
        ForEach(Array(labels.enumerated()), id: \.offset) { (i: Int, label: String) in
            Button(label) { Haptics.tap(); answer(i) }
                .buttonStyle(TertiaryButtonStyle(size: .compact, tint: i == 0 ? P.accent : P.inkSoft))
                .accessibilityIdentifier("inbox-inline-option")
        }
    }

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

/// The sender's round avatar in the messages app: a filled circle in the sender's colour with the first letter of the name; a message
/// with no usable letter shows its icon instead.
struct InboxAvatar: View {
    var initial: String
    var glyph: String
    var tint: Color
    var size: CGFloat = 44
    /// The portrait key of the person the message is about or from (`Person.faceKey`); the circle below stays the fallback.
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
    /// The portrait of the person a message is about or from: the person id the message carries (`sid`, `npc`, `pid`), otherwise the manager
    /// of its company when the sender is named like them ("Mia, manager"). Nil when it is about nobody in particular.
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
