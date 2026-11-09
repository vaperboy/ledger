import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Joint ventures: a limited company the player co-owns with friends. Owners hold real shares (the company's cap table); decisions are taken
/// at board meetings by `JVRules` (planned each quarter, or urgent when any owner calls one) and a passed item is carried out here through the
/// game's own actions, so the books stay balanced. Saved on the company as `jv`. The friends come from the online layer; a partner marked
/// `mock` is a sample player whose votes the app's stand-in service casts.
public enum JointVenture {
    // MARK: Saved state

    public struct Member: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var name: String
        /// chair, cfo or partner.
        public var role: String
        public var mock: Bool
        public var joined: Int
        public var lockUntil: Int
        public var linkKey: String
        public var roleTitle: String { role == "chair" ? "Chair" : role == "cfo" ? "CFO" : "Partner" }
        public static let me = "me"
    }
    public struct Invite: Codable, Equatable, Identifiable, Sendable {
        public var id: Int
        public var playerID: String
        public var name: String
        public var linkKey: String
        public var role: String
        public var mock: Bool
        public var pct: Double
        /// What this friend alone pays; no one else is shown it.
        public var price: Double
        public var sent: Int
        public var expires: Int
        /// sent, accepted, declined, expired.
        public var status: String
    }
    public struct Item: Codable, Equatable, Identifiable, Sendable {
        public var id: Int
        public var kind: JVRules.Kind
        public var title: String
        public var effect: String
        public var by: String
        public var amount: Double = 0
        public var steps: Int = 0
        public var name: String = ""
        public var playerID: String = ""
        public var linkKey: String = ""
        public var role: String = "partner"
        public var mock: Bool = true
        public var pct: Double = 0
        public var price: Double = 0
        public var takesMoneyOut: Bool { kind.takesMoneyOut }
        public var votes: [String: JVRules.Choice] = [:]
        public var outcome: JVRules.Outcome? = nil
        /// What the game did with it, or why it could not.
        public var result: String = ""
        public var applied: Bool = false
        public var chairUsedBefore: Bool = false
    }
    public struct Meeting: Codable, Equatable, Identifiable, Sendable {
        public var id: Int
        public var planned: Bool
        /// The week the agenda went out, the meeting date, and the last week a vote counts.
        public var opened: Int
        public var week: Int
        public var deadline: Int
        public var calledBy: String
        public var calledByTitle: String
        public var reason: String
        public var items: [Item]
        public var closed: Bool = false
        public var closedWeek: Int? = nil
        public var urgent: Bool { !planned }
    }
    /// A message the app can turn into a local notification when the date comes.
    public struct Note: Codable, Equatable, Identifiable, Sendable {
        public var id: Int
        public var meetingID: Int
        public var companyID: Int
        public var fireWeek: Int
        public var title: String
        public var body: String
    }
    public struct State: Codable, Equatable, Sendable {
        public var members: [Member] = []
        public var invites: [Invite] = []
        public var meetings: [Meeting] = []
        public var queue: [Item] = []
        public var notes: [Note] = []
        public var nextPlanned: Int? = nil
        public var lastPlanned: Int? = nil
        public var lastUrgent: [String: Int] = [:]
    }

    public static func state(_ co: Company) -> State? {
        let v = co.value("jv")
        guard !v.isNull, let d = try? JSONEncoder().encode(v) else { return nil }
        return try? JSONDecoder().decode(State.self, from: d)
    }
    static func save(_ s: inout GameState, _ i: Int, _ st: State) {
        var st = st
        st.meetings = Array(st.meetings.suffix(40)); st.notes = Array(st.notes.suffix(40)); st.invites = Array(st.invites.suffix(30))
        if let d = try? JSONEncoder().encode(st), let v = try? JSONDecoder().decode(JSONValue.self, from: d) { s.companies[i].set("jv", v) }
    }
    public static func isVenture(_ co: Company) -> Bool { state(co) != nil }
    /// Owners other than you.
    public static func partners(_ st: State) -> [Member] { st.members.filter { $0.id != Member.me } }

    // MARK: Reads

    public struct Stake: Identifiable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var role: String
        public var roleTitle: String
        public var shares: Int
        public var pct: Double
        public var lockUntil: Int
        public var locked: Bool
        public var isYou: Bool
    }
    public static func stakes(_ s: GameState, companyID: Int) -> [Stake] {
        guard let co = s.company(companyID), let st = state(co) else { return [] }
        let t = CapTable.table(co)
        return st.members.map { m in
            let sh = m.id == Member.me ? t.you : (t.holders.first { $0.name == m.name }?.shares ?? 0)
            return Stake(id: m.id, name: m.id == Member.me ? s.player.name : m.name, role: m.role, roleTitle: m.roleTitle, shares: sh,
                         pct: Double(sh) / Double(max(1, t.total)) * 100, lockUntil: m.lockUntil, locked: JVRules.isLocked(lockUntil: m.lockUntil, week: s.week), isYou: m.id == Member.me)
        }
    }
    /// Shares by member id, plus every other holder under "x:<name>" (they take no part in the vote and so abstain).
    static func shareMap(_ co: Company, _ st: State) -> [String: Int] {
        let t = CapTable.table(co)
        var out: [String: Int] = [:]
        var named = Set<String>()
        for m in st.members {
            if m.id == Member.me { out[m.id] = t.you } else if let h = t.holders.first(where: { $0.name == m.name }) { out[m.id] = h.shares; named.insert(h.name) }
        }
        for h in t.holders where !named.contains(h.name) && h.shares > 0 { out["x:" + h.name] = h.shares }
        return out
    }
    public static func tally(_ s: GameState, companyID: Int, meetingID: Int, itemID: Int) -> JVRules.Tally? {
        guard let co = s.company(companyID), let st = state(co), let m = st.meetings.first(where: { $0.id == meetingID }), let it = m.items.first(where: { $0.id == itemID }) else { return nil }
        return JVRules.tally(shares: shareMap(co, st), votes: it.votes)
    }
    public static func venture(_ s: GameState) -> [Company] { s.companies.filter { $0.status.isLive && isVenture($0) } }
    /// Meetings you still have to vote on (open and you have not voted on every item).
    public static func waitingForYou(_ s: GameState) -> Int {
        venture(s).reduce(0) { n, co in
            n + (state(co)?.meetings.filter { !$0.closed && $0.opened <= s.week && $0.items.contains { $0.votes[Member.me] == nil } }.count ?? 0)
        }
    }
    /// Why you may not take money out of a company that has partners without a vote; nil when you may.
    public static func payoutBlock(_ s: GameState, companyID: Int) -> String? {
        guard let co = s.company(companyID), let st = state(co), !partners(st).isEmpty else { return nil }
        return "\(co.name) has partners. Money goes out to owners only when a board meeting votes for it."
    }

    // MARK: Inviting a friend

    public struct Terms: Equatable, Sendable {
        public var companyName: String
        public var pct: Double
        public var price: Double
        public var fair: Double
        public var shares: Int
        public var lockUntil: Int
        public var lines: [String]
    }
    static func companyValue(_ s: GameState, _ co: Company, data: GameData) -> Double { max(0, Valuation.companyValue(co, state: s, trades: data.catalog)) }

    /// What the friend is shown before they join, and what the owner sees as the fair price: a plain list of what will happen.
    public static func terms(_ s: GameState, companyID: Int, pct: Double, price: Double, data: GameData, context fc: FinanceContext) -> Terms? {
        guard let co = s.company(companyID) else { return nil }
        let t = CapTable.table(co)
        let shares = CapTable.sharesForPercent(pct, total: t.total)
        let fair = JVRules.fairPrice(value: companyValue(s, co, data: data), pct: pct)
        let cur = fc.currency(co.countryCode, s)
        let lock = JVRules.lockUpEnd(joined: s.week)
        let lines = [
            "You get \(String(format: "%.1f", pct))% of \(co.name) (\(shares) new shares).",
            "You pay \(cur.display(price)) to the company when you join.",
            "You cannot sell or leave until \(GameCalendar.dateString(week: lock)).",
            "Your voting power is \(String(format: "%.1f", pct))%: decisions go by shares among the votes cast, and a vote you miss counts as an abstention.",
            "Dividends are paid only when the board votes for one, to all owners by their shares.",
        ]
        return Terms(companyName: co.name, pct: pct, price: price, fair: fair, shares: shares, lockUntil: lock, lines: lines)
    }

    public enum InviteResult: Equatable, Sendable {
        case sent(inviteID: Int)
        /// The venture has partners, so a meeting must vote first.
        case needsVote(meetingID: Int)
        case refused(String)
    }

    /// Check an invitation against the guard rails; nil when it is fine.
    static func inviteProblem(_ s: GameState, _ co: Company, _ st: State, linkKey: String, pct: Double, price: Double, myLinkKeys: Set<String>, data: GameData) -> String? {
        if !co.status.isLive || co.status == .setup { return "\(co.name) is not open yet." }
        if co.type == "hold" || s.isBranch(co) { return "Only an ordinary limited company can have partners." }
        if let why = JVRules.linkProblem(candidate: linkKey, mine: myLinkKeys, partners: Set(st.members.map { $0.linkKey })) { return why }
        if st.invites.contains(where: { $0.linkKey == linkKey && $0.status == "sent" }) { return "That player has been invited already." }
        let t = CapTable.table(co)
        let ownerAfter = Double(t.you) / Double(max(1, t.total + CapTable.sharesForPercent(pct, total: t.total))) * 100
        if let why = JVRules.stakeProblem(pct: pct, existingPartners: partners(st).count + st.invites.filter { $0.status == "sent" }.count, ownerAfterPct: ownerAfter) { return why }
        return JVRules.priceProblem(price: price, fair: JVRules.fairPrice(value: companyValue(s, co, data: data), pct: pct), rules: s.worldRules)
    }

    @discardableResult
    static func makeInvite(_ s: inout GameState, _ i: Int, _ st: inout State, playerID: String, name: String, linkKey: String, role: String, mock: Bool, pct: Double, price: Double) -> Invite {
        let inv = Invite(id: s.makeID(), playerID: playerID, name: name, linkKey: linkKey, role: role == "cfo" ? "cfo" : "partner", mock: mock, pct: pct, price: price,
                         sent: s.week, expires: s.week + JVRules.inviteWeeks, status: "sent")
        st.invites.append(inv)
        return inv
    }

    /// Invite a friend with their own price. With no partners yet you decide alone; with partners, the invitation is put to an urgent meeting first.
    public static func invite(_ s: inout GameState, companyID: Int, playerID: String, name: String, linkKey: String, role: String = "partner", mock: Bool = true,
                              pct: Double, price: Double, myLinkKeys: Set<String>, data: GameData, context fc: FinanceContext) -> InviteResult {
        guard let i = s.companyIndex(companyID) else { return .refused("That company is gone.") }
        let co = s.companies[i]
        var st = state(co) ?? State(members: [Member(id: Member.me, name: s.player.name, role: "chair", mock: false, joined: s.week, lockUntil: 0, linkKey: "me")])
        if let why = inviteProblem(s, co, st, linkKey: linkKey, pct: pct, price: price, myLinkKeys: myLinkKeys, data: data) { return .refused(why) }
        if partners(st).isEmpty {
            let inv = makeInvite(&s, i, &st, playerID: playerID, name: name, linkKey: linkKey, role: role, mock: mock, pct: pct, price: price)
            save(&s, i, st)
            return .sent(inviteID: inv.id)
        }
        var item = newItem(&s, .partner, by: s.player.name, fc.currency(co.countryCode, s))
        item.name = name; item.playerID = playerID; item.linkKey = linkKey; item.role = role; item.mock = mock; item.pct = pct; item.price = price
        item.effect = JVRules.effect(.partner, name: name, pct: pct, price: price, money: { fc.currency(co.countryCode, s).display($0) })
        let m = openUrgent(&s, i, &st, by: Member.me, reason: "\(name) wants to join", items: [item], data: data, context: fc)
        save(&s, i, st)
        return .needsVote(meetingID: m)
    }

    /// The friend answers. On yes they pay, the shares are issued and they become an owner with a lock-up.
    @discardableResult
    public static func respond(_ s: inout GameState, companyID: Int, inviteID: Int, accept: Bool, data: GameData, context fc: FinanceContext) -> String? {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]), let k = st.invites.firstIndex(where: { $0.id == inviteID && $0.status == "sent" }) else { return "That invitation is no longer open." }
        let inv = st.invites[k]
        let co = s.companies[i]
        if !accept {
            st.invites[k].status = "declined"; save(&s, i, st)
            s.addMessage(from: "\(co.name) partners", title: "\(inv.name) said no", body: "\(inv.name) turned down the invitation to join \(co.name).", companyID: co.id)
            return nil
        }
        // The company may have moved since the price was set: the price must still sit in the band.
        if let why = JVRules.priceProblem(price: inv.price, fair: JVRules.fairPrice(value: companyValue(s, co, data: data), pct: inv.pct), rules: s.worldRules) {
            st.invites[k].status = "declined"; save(&s, i, st)
            s.addMessage(from: "\(co.name) partners", title: "\(inv.name) could not join", body: "The value of \(co.name) has moved since the price was set. \(why)", companyID: co.id)
            return why
        }
        if partners(st).count >= JVRules.maxPartners { return "There is no room for another partner." }
        let shares = CapTable.sharesForPercent(inv.pct, total: CapTable.table(co).total)
        let lock = JVRules.lockUpEnd(joined: s.week)
        Payments.companyReceives(&s, companyID: companyID, amount: inv.price, category: nil, label: "New shares sold to \(inv.name)")
        CapTable.issue(&s, i, newShares: shares, to: inv.name, paid: inv.price, extra: ["jv": true, "sat": 70, "lock": .number(Double(lock))])
        st.invites[k].status = "accepted"
        st.members.append(Member(id: "p:" + inv.playerID, name: inv.name, role: inv.role, mock: inv.mock, joined: s.week, lockUntil: lock, linkKey: inv.linkKey))
        if st.nextPlanned == nil { st.nextPlanned = JVRules.nextPlannedWeek(after: nil, now: s.week) }
        save(&s, i, st)
        let cur = fc.currency(co.countryCode, s)
        s.note("\(inv.name) joined \(co.name) as a partner for \(cur.display(inv.price)).", tone: "good", companyID: companyID)
        s.addMessage(from: "\(co.name) partners", title: "\(inv.name) joined \(co.name)", body: "\(inv.name) holds \(String(format: "%.1f", inv.pct))% and cannot sell before \(GameCalendar.dateString(week: lock)). Planned board meetings run every quarter.", companyID: co.id, tone: "good")
        return nil
    }

    // MARK: Agenda items

    static func newItem(_ s: inout GameState, _ kind: JVRules.Kind, by: String, _ cur: Currency) -> Item {
        Item(id: s.makeID(), kind: kind, title: kind.title, effect: "", by: by)
    }

    /// Build an agenda item with the facts the vote needs; nil with the reason when it cannot be put.
    public static func makeItem(_ s: inout GameState, companyID: Int, kind: JVRules.Kind, by: String, amount: Double = 0, steps: Int = 0, data: GameData, context fc: FinanceContext) -> (item: Item?, problem: String?) {
        guard let co = s.company(companyID) else { return (nil, "That company is gone.") }
        let cur = fc.currency(co.countryCode, s)
        var it = newItem(&s, kind, by: by, cur)
        it.amount = jsRound(amount); it.steps = steps
        switch kind {
        case .dividend:
            let top = Payments.maximumDividend(co, state: s, context: fc)
            if it.amount <= 0 || it.amount > top { return (nil, top <= 0 ? "There is no retained profit to pay out." : "At most \(cur.display(top)) can be paid out now.") }
        case .capital: if it.amount <= 0 { return (nil, "Name an amount.") }
        case .price: it.steps = steps < 0 ? -1 : 1
        case .hire: if co.managerID != nil { return (nil, "\(co.name) has a manager already.") }
        case .sell, .dissolve: break
        case .partner: return (nil, "Invite a friend from the Partners section.")
        }
        it.effect = JVRules.effect(kind, amount: it.amount, steps: it.steps, money: { cur.display($0) })
        return (it, nil)
    }

    /// Put an item on the next planned meeting (any owner may).
    @discardableResult
    public static func queue(_ s: inout GameState, companyID: Int, item: Item) -> Bool {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]), !partners(st).isEmpty else { return false }
        st.queue.append(item); save(&s, i, st)
        return true
    }

    // MARK: Meetings

    static func memberTitle(_ m: Member) -> String { "\(m.roleTitle) \(m.name)" }

    static func announce(_ s: inout GameState, _ co: Company, _ st: inout State, _ m: Meeting, data: GameData, context fc: FinanceContext) {
        let date = GameCalendar.dateString(week: m.week)
        let agenda = m.items.isEmpty ? "nothing to decide" : m.items.map { $0.title.lowercased() }.joined(separator: ", ")
        let title = m.planned ? "\(co.name) board meeting on \(date): \(agenda)" : "\(m.calledByTitle) called an emergency meeting: \(m.reason)"
        let body = m.planned ? "Agenda: \(agenda). Vote by \(GameCalendar.dateString(week: m.deadline)); a vote not cast counts as an abstention."
                             : "\(m.calledByTitle) called it for \(co.name). Vote by \(GameCalendar.dateString(week: m.deadline)); a vote not cast counts as an abstention."
        if m.calledBy != Member.me {
            s.addMessage(kind: "info", from: "\(co.name) board", title: title, body: body, companyID: co.id, tone: m.planned ? "n" : "bad", sev: m.planned ? 2 : 3)
            st.notes.append(Note(id: s.makeID(), meetingID: m.id, companyID: co.id, fireWeek: s.week, title: title, body: body))
        }
        if m.planned, m.deadline - 1 > s.week {
            st.notes.append(Note(id: s.makeID(), meetingID: m.id, companyID: co.id, fireWeek: m.deadline - 1, title: "\(co.name): vote closes soon", body: "Your vote on the \(date) board meeting counts until \(GameCalendar.dateString(week: m.deadline))."))
        }
    }

    @discardableResult
    static func openUrgent(_ s: inout GameState, _ i: Int, _ st: inout State, by: String, reason: String, items: [Item], data: GameData, context fc: FinanceContext) -> Int {
        let co = s.companies[i]
        let caller = st.members.first { $0.id == by }
        var its = items
        for k in its.indices { its[k].votes[by] = .yes }   // the one who puts it, backs it
        let m = Meeting(id: s.makeID(), planned: false, opened: s.week, week: s.week + JVRules.urgentWindowWeeks, deadline: JVRules.deadline(planned: false, openedWeek: s.week, meetingWeek: s.week),
                        calledBy: by, calledByTitle: caller.map { by == Member.me ? "You" : memberTitle($0) } ?? "A partner", reason: reason, items: its)
        st.meetings.append(m)
        st.lastUrgent[by] = s.week
        announce(&s, co, &st, m, data: data, context: fc)
        return m.id
    }

    public enum CallResult: Equatable, Sendable { case called(meetingID: Int), refused(String) }

    /// Any owner, or the holder of a role, calls an urgent meeting with one or two items.
    public static func callUrgent(_ s: inout GameState, companyID: Int, by memberID: String, reason: String, items: [Item], data: GameData, context fc: FinanceContext) -> CallResult {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]) else { return .refused("That company has no partners.") }
        guard st.members.contains(where: { $0.id == memberID }) else { return .refused("Only an owner or a role holder can call a meeting.") }
        if partners(st).isEmpty { return .refused("You need a partner before there is a board to call.") }
        if st.meetings.contains(where: { !$0.closed && $0.urgent }) { return .refused("An emergency meeting is already open. Let it finish first.") }
        if let last = st.lastUrgent[memberID], s.week - last < 2 { return .refused("You called one just now. Wait two weeks before the next.") }
        guard !items.isEmpty, items.count <= 3 else { return .refused("Put one to three items to the meeting.") }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = openUrgent(&s, i, &st, by: memberID, reason: trimmed.isEmpty ? items[0].title : trimmed, items: items, data: data, context: fc)
        save(&s, i, st)
        return .called(meetingID: id)
    }

    public static func castVote(_ s: inout GameState, companyID: Int, meetingID: Int, itemID: Int, member memberID: String, choice: JVRules.Choice) -> Bool {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]), st.members.contains(where: { $0.id == memberID }),
              let mk = st.meetings.firstIndex(where: { $0.id == meetingID && !$0.closed }), JVRules.isOpen(week: s.week, deadline: st.meetings[mk].deadline),
              let ik = st.meetings[mk].items.firstIndex(where: { $0.id == itemID }) else { return false }
        st.meetings[mk].items[ik].votes[memberID] = choice
        save(&s, i, st)
        return true
    }

    // MARK: The week

    /// Called once a week: invitations lapse, planned meetings go out two weeks ahead, and meetings past their deadline are counted and carried out.
    public static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        for i in s.companies.indices where s.companies[i].status.isLive {
            guard var st = state(s.companies[i]) else { continue }
            var changed = false
            for k in st.invites.indices where st.invites[k].status == "sent" && s.week > st.invites[k].expires { st.invites[k].status = "expired"; changed = true }
            if let due = st.nextPlanned, !partners(st).isEmpty, s.week >= due - JVRules.plannedNoticeWeeks, !st.meetings.contains(where: { !$0.closed && $0.planned }) {
                let m = plannedMeeting(&s, i, &st, date: due, data: data, context: fc)
                st.meetings.append(m)
                st.lastPlanned = due
                st.nextPlanned = due + JVRules.quarterWeeks
                announce(&s, s.companies[i], &st, m, data: data, context: fc)
                changed = true
            }
            for k in st.meetings.indices where !st.meetings[k].closed && s.week > st.meetings[k].deadline {
                count(&s, i, &st, k, data: data, context: fc)
                changed = true
            }
            if changed { save(&s, i, st) }
        }
    }

    /// The quarterly agenda: a dividend when there is profit to share, a call for capital when cash runs short, and what owners queued.
    static func plannedMeeting(_ s: inout GameState, _ i: Int, _ st: inout State, date: Int, data: GameData, context fc: FinanceContext) -> Meeting {
        let co = s.companies[i]
        let cur = fc.currency(co.countryCode, s)
        var items = st.queue
        st.queue = []
        let p3 = co.monthlyHistory.suffix(3).reduce(0) { $0 + $1.profit }
        let top = Payments.maximumDividend(co, state: s, context: fc)
        let pay = min(top, jsRound(p3 * 0.25))
        if p3 > 0, pay > 0, !items.contains(where: { $0.kind == .dividend }) {
            var it = newItem(&s, .dividend, by: "The board", cur)
            it.amount = pay; it.effect = JVRules.effect(.dividend, amount: pay, money: { cur.display($0) })
            items.append(it)
        }
        let need = fc.weeklyCost(co, s) * 8
        if co.cash < need, !items.contains(where: { $0.kind == .capital }) {
            var it = newItem(&s, .capital, by: "The board", cur)
            it.amount = jsRound(max(1, need - co.cash)); it.effect = JVRules.effect(.capital, amount: it.amount, money: { cur.display($0) })
            items.append(it)
        }
        return Meeting(id: s.makeID(), planned: true, opened: s.week, week: date, deadline: date, calledBy: "board", calledByTitle: "The board", reason: "Quarterly meeting", items: items)
    }

    /// Count the votes on every item, carry out what passed, close the meeting and tell you.
    static func count(_ s: inout GameState, _ i: Int, _ st: inout State, _ k: Int, data: GameData, context fc: FinanceContext) {
        let co = s.companies[i]
        let shares = shareMap(co, st)
        let chairID = st.members.first { $0.role == "chair" }?.id ?? Member.me
        var lines: [String] = []
        for n in st.meetings[k].items.indices {
            var it = st.meetings[k].items[n]
            let t = JVRules.tally(shares: shares, votes: it.votes)
            // A tie broken by the chair once: if this kind of item tied and was broken before, the status quo stands.
            let broke = st.meetings.contains { $0.id != st.meetings[k].id && $0.items.contains { $0.kind == it.kind && ($0.outcome == .chairPassed || $0.outcome == .chairFailed) } }
            it.chairUsedBefore = broke
            let out = JVRules.decide(t, chair: it.votes[chairID], chairUsedBefore: broke)
            it.outcome = out
            if out.passes {
                let r = apply(&s, i, &st, it, data: data, context: fc)
                it.applied = r.ok; it.result = r.text
            } else {
                it.result = out.word + "."
            }
            st.meetings[k].items[n] = it
            lines.append("\(it.title): \(out.word)" + (out.passes ? (it.applied ? ". " : ". Not carried out: ") + it.result : ""))
        }
        st.meetings[k].closed = true
        st.meetings[k].closedWeek = s.week
        let m = st.meetings[k]
        let body = lines.isEmpty ? "Nothing was on the agenda." : lines.joined(separator: "\n")
        let resultTitle = "\(co.name) meeting result: \(m.planned ? "quarterly" : m.reason)"
        s.addMessage(from: "\(co.name) board", title: resultTitle, body: body, companyID: co.id, tone: m.items.contains { $0.applied } ? "good" : "n")
        st.notes.append(Note(id: s.makeID(), meetingID: m.id, companyID: co.id, fireWeek: s.week, title: resultTitle, body: body))
    }

    // MARK: Leaving and selling shares

    /// What buying a partner's shares back does, worked out before anything moves.
    public struct ExitTerms: Equatable, Sendable {
        public var name: String
        public var shares: Int
        public var pct: Double
        public var price: Double
        public var locked: Bool
        public var lockUntil: Int
        /// Why it cannot be done now; nil when it can.
        public var problem: String?
        /// "If you do this, this will happen", in plain lines.
        public var lines: [String]
    }

    /// A partner leaves or sells only after the lock-up. The price is their share of what the company is worth now, with no premium either way.
    public static func exitTerms(_ s: GameState, companyID: Int, memberID: String, data: GameData, context fc: FinanceContext) -> ExitTerms? {
        guard let co = s.company(companyID), let st = state(co), let m = st.members.first(where: { $0.id == memberID && $0.id != Member.me }) else { return nil }
        let t = CapTable.table(co)
        let shares = t.holders.first { $0.name == m.name }?.shares ?? 0
        let pct = Double(shares) / Double(max(1, t.total)) * 100
        let price = jsRound(companyValue(s, co, data: data) * Double(shares) / Double(max(1, t.total)))
        let cur = fc.currency(co.countryCode, s)
        let locked = JVRules.isLocked(lockUntil: m.lockUntil, week: s.week)
        var problem: String?
        if locked { problem = "\(m.name) cannot sell or leave until \(GameCalendar.dateString(week: m.lockUntil))." }
        else if shares <= 0 { problem = "\(m.name) holds no shares." }
        else if Payments.liquid(s) < price { problem = "You need \(cur.display(price)) in cash to buy their shares." }
        let after = Double(t.you + shares) / Double(max(1, t.total)) * 100
        let lines = [
            "You pay \(cur.display(price)) from your own money: \(String(format: "%.1f", pct))% of what \(co.name) is worth now. Nobody gets a premium.",
            "\(m.name) leaves the board and their shares become yours.",
            "Your share of \(co.name) goes from \(String(format: "%.1f", t.youPct))% to \(String(format: "%.1f", after))%.",
        ]
        return ExitTerms(name: m.name, shares: shares, pct: pct, price: price, locked: locked, lockUntil: m.lockUntil, problem: problem, lines: lines)
    }

    /// You buy a partner's shares back (they have asked to leave, or you offer and they agree). Returns why it did not go through.
    @discardableResult
    public static func buyOut(_ s: inout GameState, companyID: Int, memberID: String, data: GameData, context fc: FinanceContext) -> String? {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]), let k = st.members.firstIndex(where: { $0.id == memberID && $0.id != Member.me }),
              let t = exitTerms(s, companyID: companyID, memberID: memberID, data: data, context: fc) else { return "That partner is no longer here." }
        if let why = t.problem { return why }
        let m = st.members[k]
        let co = s.companies[i]
        Payments.playerPays(&s, t.price, label: "Bought \(m.name)'s shares in \(co.name)", companyID: companyID)
        CapTable.buyFromHolder(&s, i, holder: m.name)
        st.members.remove(at: k)
        save(&s, i, st)
        let cur = fc.currency(co.countryCode, s)
        s.note("\(m.name) left \(co.name). You bought their \(String(format: "%.1f", t.pct))% for \(cur.display(t.price)).", tone: "n", companyID: companyID)
        return nil
    }

    /// A partner asks to sell or leave. Inside the lock-up it is refused and nothing is sent; after it, you are told what buying them out costs.
    @discardableResult
    public static func partnerWantsOut(_ s: inout GameState, companyID: Int, memberID: String, data: GameData, context fc: FinanceContext) -> String? {
        guard let t = exitTerms(s, companyID: companyID, memberID: memberID, data: data, context: fc), let co = s.company(companyID) else { return "That partner is no longer here." }
        if t.locked { return t.problem }
        let cur = fc.currency(co.countryCode, s)
        s.addMessage(from: "\(co.name) partners", title: "\(t.name) wants to sell", body: "\(t.name) wants to leave \(co.name) and sell \(String(format: "%.1f", t.pct))% at what it is worth now: \(cur.display(t.price)). Buy them out from the Partners section of the company, or keep them as a partner.", companyID: co.id, tone: "n")
        return nil
    }

    /// After a sale of the whole company: what each owner's shares got, in one message. (Partners' own money is theirs; this is the record.)
    static func announceSale(_ s: inout GameState, company co: Company, price: Double, buyer: String, context fc: FinanceContext) {
        guard let st = state(co), !partners(st).isEmpty else { return }
        let cur = fc.currency(co.countryCode, s)
        let pay = JVRules.dissolvePayout(value: price, shares: shareMap(co, st))
        let lines = st.members.map { m in "\(m.id == Member.me ? "You" : m.name) \(cur.display(pay[m.id] ?? 0))" }
        s.addMessage(from: "\(co.name) board", title: "\(co.name) was sold to \(buyer)", body: "Paid out by shares from \(cur.display(price)): " + lines.joined(separator: ", ") + ".", companyID: co.id, tone: "good")
    }

    // MARK: Reminders

    /// The board meeting waiting for your vote that the app should remind you of: an emergency meeting before a planned one, the soonest first.
    public struct PendingVote: Equatable, Sendable {
        public var companyName: String
        public var urgent: Bool
        public var reason: String
        public var weeksLeft: Int
    }
    public static func pendingVote(_ s: GameState) -> PendingVote? {
        var found: [(Meeting, Company)] = []
        for co in venture(s) {
            for m in state(co)?.meetings ?? [] where !m.closed && m.opened <= s.week && s.week <= m.deadline && m.items.contains(where: { $0.votes[Member.me] == nil }) { found.append((m, co)) }
        }
        guard let hit = found.min(by: { ($0.0.urgent ? 0 : 1, $0.0.deadline) < ($1.0.urgent ? 0 : 1, $1.0.deadline) }) else { return nil }
        return PendingVote(companyName: hit.1.name, urgent: hit.0.urgent, reason: hit.0.reason, weeksLeft: max(0, hit.0.deadline - s.week))
    }

    // MARK: Carrying out a passed item

    /// The game's own actions do the work, so the books balance exactly as they would for the owner alone.
    static func apply(_ s: inout GameState, _ i: Int, _ st: inout State, _ it: Item, data: GameData, context fc: FinanceContext) -> (ok: Bool, text: String) {
        let co = s.companies[i]
        let cur = fc.currency(co.countryCode, s)
        guard co.status.isLive else { return (false, "The company is no longer there.") }
        switch it.kind {
        case .dividend:
            switch Payments.payDividend(&s, companyID: co.id, amount: it.amount, context: fc) {
            case .ok: return (true, "\(cur.display(it.amount)) was paid out by shares.")
            case .noRetainedProfit: return (false, "There is no retained profit left to pay out.")
            case .notEnoughCash: return (false, "The company no longer has the cash for it.")
            default: return (false, "The company cannot pay a dividend.")
            }
        case .price:
            let now = s.companies[i].priceLevel
            let next = it.steps < 0 ? max(-3, now - 1) : min(3, now + 1)
            if next == now { return (false, "Prices are as far \(it.steps < 0 ? "down" : "up") as they go.") }
            s.companies[i].priceLevel = next
            return (true, "Prices moved one step \(it.steps < 0 ? "down" : "up").")
        case .hire:
            guard co.managerID == nil, let bd = data.catalog[co.type] else { return (false, "\(co.name) has a manager already.") }
            let c = ManagerModel.generateCandidate(company: co, type: bd.managerType, faces: true, state: &s, data: data)
            switch ManagerModel.hire(&s, personID: c.id, companyID: co.id, monthlyWage: c.askingMonthlyWage, data: data) {
            case .ok: return (true, "\(c.name) was hired as manager at \(cur.display(c.askingMonthlyWage)) a month.")
            default: return (false, "The manager found would not take the job at the going rate. Put it again.")
            }
        case .sell:
            if let why = SaleListings.routeProblem(s, companyID: co.id, route: "broker", pct: 100, board: true) { return (false, why) }
            let started = SaleListings.start(&s, companyID: co.id, route: "broker", extra: ["jv": .number(1)])
            return started ? (true, "\(co.name) is listed with a broker. Offers come to its Sell page for you to answer for all owners; none under \(Int(JVRules.lowestSaleShare * 100))% of its value is accepted. When it sells, every owner is paid by their shares.") : (false, "\(co.name) cannot be listed now.")
        case .partner:
            if let why = inviteProblem(s, co, st, linkKey: it.linkKey, pct: it.pct, price: it.price, myLinkKeys: [], data: data) { return (false, why) }
            makeInvite(&s, i, &st, playerID: it.playerID, name: it.name, linkKey: it.linkKey, role: it.role, mock: it.mock, pct: it.pct, price: it.price)
            return (true, "\(it.name) was invited. They join when they accept.")
        case .capital:
            // Only your own share is real money here: a sample partner has no account to take cash from, and money booked for them would come from nowhere.
            let t = CapTable.table(co)
            let mine = jsRound(it.amount * t.youPct / 100)
            guard Payments.liquid(s) >= mine else { return (false, "You do not have your \(cur.display(mine)) for it.") }
            if mine > 0 { _ = Payments.injectCash(&s, companyID: co.id, amount: mine) }
            return (true, "You put in \(cur.display(mine)), your share of the call. Partners were not asked for cash.")
        case .dissolve:
            let value = companyValue(s, s.companies[i], data: data)
            let shares = shareMap(s.companies[i], st)
            let pay = JVRules.dissolvePayout(value: value, shares: shares)
            s.rest["jvgo"] = .number(Double(co.id))   // the board's own decision: the sale guard lets this one through
            let done = CompanySale.complete(&s, companyIndex: i, buyer: "Dissolution", price: value, data: data, context: fc)
            s.rest["jvgo"] = nil
            guard done != nil else { return (false, "The company cannot be dissolved now.") }
            let others = st.members.filter { $0.id != Member.me }.map { "\($0.name) \(cur.display(pay[$0.id] ?? 0))" }.joined(separator: ", ")
            return (true, "Paid out by shares from a value of \(cur.display(value)): you \(cur.display(pay[Member.me] ?? 0))" + (others.isEmpty ? "." : "; \(others)."))
        }
    }
}
