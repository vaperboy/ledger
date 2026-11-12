import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum JointVenture {

    public struct Member: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var name: String
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
        public var price: Double
        public var sent: Int
        public var expires: Int
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
        public var result: String = ""
        public var applied: Bool = false
        public var chairUsedBefore: Bool = false
        public var policy: String? = nil
        public var setting: Setting? = nil
        public var targetID: Int? = nil
    }
    public struct Setting: Codable, Equatable, Sendable {
        public var chainID: Int
        public var rule: String
        public var number: Double
        public var text: String
        public var label: String
        public init(chainID: Int, rule: String, number: Double = 0, text: String = "", label: String) {
            self.chainID = chainID; self.rule = rule; self.number = number; self.text = text; self.label = label
        }
    }
    public struct Buyback: Codable, Equatable, Identifiable, Sendable {
        public var id: Int
        public var memberID: String
        public var name: String
        public var shares: Int
        public var price: Double
        public var fair: Double
        public var sentAt: Double
        public var expiresAt: Double
        public var mock: Bool
        public var status: String
    }
    public struct Meeting: Codable, Equatable, Identifiable, Sendable {
        public var id: Int
        public var planned: Bool
        public var opened: Int
        public var week: Int
        public var deadline: Int
        public var calledBy: String
        public var calledByTitle: String
        public var reason: String
        public var items: [Item]
        public var closed: Bool = false
        public var closedWeek: Int? = nil
        public var opensAt: Double? = nil
        public var closesAt: Double? = nil
        public var urgent: Bool { !planned }
    }
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
        public var buybacks: [Buyback]? = nil
    }

    public static func state(_ co: Company) -> State? {
        let v = co.value("jv")
        guard !v.isNull, let d = try? JSONEncoder().encode(v) else { return nil }
        return try? JSONDecoder().decode(State.self, from: d)
    }
    static func save(_ s: inout GameState, _ i: Int, _ st: State) {
        var st = st
        st.meetings = Array(st.meetings.suffix(40)); st.notes = Array(st.notes.suffix(40)); st.invites = Array(st.invites.suffix(30))
        if let offers = st.buybacks { st.buybacks = Array(offers.suffix(20)) }
        if let d = try? JSONEncoder().encode(st), let v = try? JSONDecoder().decode(JSONValue.self, from: d) { s.companies[i].set("jv", v) }
    }
    public static func isVenture(_ co: Company) -> Bool { state(co) != nil }
    public static func partners(_ st: State) -> [Member] { st.members.filter { $0.id != Member.me } }
    public static func isShared(_ co: Company) -> Bool { state(co).map { !partners($0).isEmpty } ?? false }

    // The co-owned company whose owners vote before this company's dividend policy changes: itself, or a co-owned store of its chain.
    public static func boardCompany(_ s: GameState, companyID: Int) -> Company? {
        guard let co = s.company(companyID) else { return nil }
        if isShared(co) { return co }
        guard let ch = Chains.chain(s, of: co) else { return nil }
        return Chains.stores(s, ch).first { isShared($0) }
    }
    // The co-owned store whose owners vote before a chain's rules change.
    public static func boardCompany(_ s: GameState, chainID: Int) -> Company? {
        guard let ch = Chains.chain(s, id: chainID) else { return nil }
        return Chains.stores(s, ch).first { isShared($0) }
    }

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
    public static func waitingForYou(_ s: GameState) -> Int {
        venture(s).reduce(0) { n, co in
            n + (state(co)?.meetings.filter { !$0.closed && $0.opened <= s.week && $0.items.contains { $0.votes[Member.me] == nil } }.count ?? 0)
        }
    }
    public static func payoutRoom(_ s: GameState, _ co: Company, _ fc: FinanceContext) -> Double {
        let year = co.monthlyHistory.suffix(12).reduce(0) { $0 + $1.profit }
        return max(0, min(year, s.cash - fc.weeklyCost(co, s) * 2)).rounded(.down)
    }
    public static func payoutBlock(_ s: GameState, companyID: Int) -> String? {
        guard let co = boardCompany(s, companyID: companyID) else { return nil }
        return "\(co.name) has partners. Its dividend policy changes only by a vote of the owners."
    }
    public static func settingBlock(_ s: GameState, chainID: Int) -> String? {
        guard let co = boardCompany(s, chainID: chainID) else { return nil }
        return "\(co.name) has partners. Group rules change only by a vote of the owners."
    }

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
            "Your voting power is \(String(format: "%.1f", pct))%: a proposal passes when more than half of all shares vote for it, and a vote you miss counts as an abstention.",
            "Dividends follow the policy the owners vote for, paid to all owners by their shares.",
        ]
        return Terms(companyName: co.name, pct: pct, price: price, fair: fair, shares: shares, lockUntil: lock, lines: lines)
    }

    public enum InviteResult: Equatable, Sendable {
        case sent(inviteID: Int)
        case needsVote(meetingID: Int)
        case refused(String)
    }

    static func inviteProblem(_ s: GameState, _ co: Company, _ st: State, linkKey: String, pct: Double, price: Double, mock: Bool, myLinkKeys: Set<String>, data: GameData) -> String? {
        if !co.status.isLive || co.status == .setup { return "\(co.name) is not open yet." }
        if s.isBranch(co) { return "Only an ordinary limited company can have partners." }
        if let why = JVRules.linkProblem(candidate: linkKey, mine: myLinkKeys, partners: Set(st.members.map { $0.linkKey })) { return why }
        if st.invites.contains(where: { $0.linkKey == linkKey && $0.status == "sent" }) { return "That player has been invited already." }
        let t = CapTable.table(co)
        let ownerAfter = Double(t.you) / Double(max(1, t.total + CapTable.sharesForPercent(pct, total: t.total))) * 100
        if let why = JVRules.stakeProblem(pct: pct, existingPartners: partners(st).count + st.invites.filter { $0.status == "sent" }.count, ownerAfterPct: ownerAfter) { return why }
        return JVRules.priceProblem(price: price, fair: JVRules.fairPrice(value: companyValue(s, co, data: data), pct: pct), mock: mock, rules: s.worldRules)
    }

    @discardableResult
    static func makeInvite(_ s: inout GameState, _ i: Int, _ st: inout State, playerID: String, name: String, linkKey: String, role: String, mock: Bool, pct: Double, price: Double) -> Invite {
        let inv = Invite(id: s.makeID(), playerID: playerID, name: name, linkKey: linkKey, role: role == "cfo" ? "cfo" : "partner", mock: mock, pct: pct, price: price,
                         sent: s.week, expires: s.week + JVRules.inviteWeeks, status: "sent")
        st.invites.append(inv)
        return inv
    }

    public static func invite(_ s: inout GameState, companyID: Int, playerID: String, name: String, linkKey: String, role: String = "partner", mock: Bool = true,
                              pct: Double, price: Double, myLinkKeys: Set<String>, now: Double, data: GameData, context fc: FinanceContext) -> InviteResult {
        guard let i = s.companyIndex(companyID) else { return .refused("That company is gone.") }
        let co = s.companies[i]
        var st = state(co) ?? State(members: [Member(id: Member.me, name: s.player.name, role: "chair", mock: false, joined: s.week, lockUntil: 0, linkKey: "me")])
        if let why = inviteProblem(s, co, st, linkKey: linkKey, pct: pct, price: price, mock: mock, myLinkKeys: myLinkKeys, data: data) { return .refused(why) }
        if partners(st).isEmpty {
            let inv = makeInvite(&s, i, &st, playerID: playerID, name: name, linkKey: linkKey, role: role, mock: mock, pct: pct, price: price)
            save(&s, i, st)
            return .sent(inviteID: inv.id)
        }
        var item = newItem(&s, .partner, by: s.player.name, fc.currency(co.countryCode, s))
        item.name = name; item.playerID = playerID; item.linkKey = linkKey; item.role = role; item.mock = mock; item.pct = pct; item.price = price
        item.effect = JVRules.effect(.partner, name: name, pct: pct, price: price, money: { fc.currency(co.countryCode, s).display($0) })
        let m = openUrgent(&s, i, &st, by: Member.me, reason: "\(name) wants to join", items: [item], now: now)
        _ = settleCompany(&s, i, &st, now: now, data: data, context: fc)
        save(&s, i, st)
        return .needsVote(meetingID: m)
    }

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
        if let why = JVRules.priceProblem(price: inv.price, fair: JVRules.fairPrice(value: companyValue(s, co, data: data), pct: inv.pct), mock: inv.mock, rules: s.worldRules) {
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
        save(&s, i, st)
        let cur = fc.currency(co.countryCode, s)
        s.note("\(inv.name) joined \(co.name) as a partner for \(cur.display(inv.price)).", tone: "good", companyID: companyID)
        s.addMessage(from: "\(co.name) partners", title: "\(inv.name) joined \(co.name)", body: "\(inv.name) holds \(String(format: "%.1f", inv.pct))% and cannot sell before \(GameCalendar.dateString(week: lock)). The board meets every Monday; anything urgent goes to an emergency meeting.", companyID: co.id, tone: "good")
        return nil
    }

    static func newItem(_ s: inout GameState, _ kind: JVRules.Kind, by: String, _ cur: Currency) -> Item {
        Item(id: s.makeID(), kind: kind, title: kind.title, effect: "", by: by)
    }

    public static func makeItem(_ s: inout GameState, companyID: Int, kind: JVRules.Kind, by: String, amount: Double = 0, steps: Int = 0, data: GameData, context fc: FinanceContext) -> (item: Item?, problem: String?) {
        guard let co = s.company(companyID) else { return (nil, "That company is gone.") }
        let cur = fc.currency(co.countryCode, s)
        var it = newItem(&s, kind, by: by, cur)
        it.amount = jsRound(amount); it.steps = steps
        switch kind {
        case .dividend:
            let top = payoutRoom(s, co, fc)
            if it.amount <= 0 || it.amount > top { return (nil, top <= 0 ? "There is no profit to pay out." : "At most \(cur.display(top)) can be paid out now.") }
        case .price: it.steps = steps < 0 ? -1 : 1
        case .hire: if co.managerID != nil { return (nil, "\(co.name) has a manager already.") }
        case .sell, .dissolve: break
        case .partner: return (nil, "Invite a friend from the Partners section.")
        case .policy, .setting: return (nil, "Change that where it is set; it then goes to the board.")
        }
        it.effect = JVRules.effect(kind, amount: it.amount, steps: it.steps, money: { cur.display($0) })
        return (it, nil)
    }

    @discardableResult
    public static func queue(_ s: inout GameState, companyID: Int, item: Item, by memberID: String = Member.me, now: Double) -> Bool {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]), !partners(st).isEmpty else { return false }
        addToAgenda(&s, i, &st, item, by: memberID, now: now)
        save(&s, i, st)
        return true
    }

    // Puts an item on the weekly meeting, opening that meeting if none is open. The proposer counts as voting for it.
    @discardableResult
    static func addToAgenda(_ s: inout GameState, _ i: Int, _ st: inout State, _ item: Item, by memberID: String?, now: Double) -> Int {
        var it = item
        if let memberID { it.votes[memberID] = .yes }
        let co = s.companies[i]
        if let memberID, memberID != Member.me, let who = st.members.first(where: { $0.id == memberID }) {
            s.addMessage(kind: "info", from: "\(co.name) board", title: "\(memberTitle(who)) put an item to the weekly meeting: \(it.title)",
                         body: "If it passes: \(it.effect) Vote before the meeting; a vote not cast counts as an abstention.", companyID: co.id, tone: "n", sev: 2)
        }
        if let k = st.meetings.firstIndex(where: { !$0.closed && $0.planned && ($0.closesAt ?? 0) > now }) {
            st.meetings[k].items.append(it)
            return st.meetings[k].id
        }
        var m = Meeting(id: s.makeID(), planned: true, opened: s.week, week: s.week, deadline: s.week, calledBy: "board", calledByTitle: "The board", reason: "Weekly meeting", items: [it])
        m.opensAt = now
        m.closesAt = JVRules.nextMeeting(after: now)
        st.meetings.append(m)
        return m.id
    }

    static func memberTitle(_ m: Member) -> String { "\(m.roleTitle) \(m.name)" }

    static func announce(_ s: inout GameState, _ co: Company, _ st: inout State, _ m: Meeting) {
        guard m.urgent, m.calledBy != Member.me else { return }
        let title = "\(m.calledByTitle) called an emergency meeting: \(m.reason)"
        let body = "\(m.calledByTitle) called it for \(co.name). You have 24 hours to vote; a vote not cast counts as an abstention."
        s.addMessage(kind: "info", from: "\(co.name) board", title: title, body: body, companyID: co.id, tone: "bad", sev: 3)
        st.notes.append(Note(id: s.makeID(), meetingID: m.id, companyID: co.id, fireWeek: s.week, title: title, body: body))
    }

    @discardableResult
    static func openUrgent(_ s: inout GameState, _ i: Int, _ st: inout State, by: String, reason: String, items: [Item], now: Double) -> Int {
        let co = s.companies[i]
        let caller = st.members.first { $0.id == by }
        var its = items
        for k in its.indices { its[k].votes[by] = .yes }
        var m = Meeting(id: s.makeID(), planned: false, opened: s.week, week: s.week, deadline: s.week,
                        calledBy: by, calledByTitle: caller.map { by == Member.me ? "You" : memberTitle($0) } ?? "A partner", reason: reason, items: its)
        m.opensAt = now
        m.closesAt = now + JVRules.emergencySeconds
        st.meetings.append(m)
        st.lastUrgent[by] = s.week
        announce(&s, co, &st, m)
        return m.id
    }

    public enum CallResult: Equatable, Sendable { case called(meetingID: Int), refused(String) }

    public static func callUrgent(_ s: inout GameState, companyID: Int, by memberID: String, reason: String, items: [Item], now: Double, data: GameData, context fc: FinanceContext) -> CallResult {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]) else { return .refused("That company has no partners.") }
        guard st.members.contains(where: { $0.id == memberID }) else { return .refused("Only an owner or a role holder can call a meeting.") }
        if partners(st).isEmpty { return .refused("You need a partner before there is a board to call.") }
        if st.meetings.contains(where: { !$0.closed && $0.urgent }) { return .refused("An emergency meeting is already open. Let it finish first.") }
        guard !items.isEmpty, items.count <= 3 else { return .refused("Put one to three items to the meeting.") }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = openUrgent(&s, i, &st, by: memberID, reason: trimmed.isEmpty ? items[0].title : trimmed, items: items, now: now)
        _ = settleCompany(&s, i, &st, now: now, data: data, context: fc)
        save(&s, i, st)
        return .called(meetingID: id)
    }

    static func isVoting(_ m: Meeting, week: Int, now: Double) -> Bool {
        if let closes = m.closesAt { return now < closes }
        return JVRules.isOpen(week: week, deadline: m.deadline)
    }

    public static func castVote(_ s: inout GameState, companyID: Int, meetingID: Int, itemID: Int, member memberID: String, choice: JVRules.Choice, now: Double) -> Bool {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]), st.members.contains(where: { $0.id == memberID }),
              let mk = st.meetings.firstIndex(where: { $0.id == meetingID && !$0.closed }), isVoting(st.meetings[mk], week: s.week, now: now),
              let ik = st.meetings[mk].items.firstIndex(where: { $0.id == itemID }) else { return false }
        st.meetings[mk].items[ik].votes[memberID] = choice
        save(&s, i, st)
        return true
    }

    public static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        for i in s.companies.indices where s.companies[i].status.isLive {
            guard var st = state(s.companies[i]) else { continue }
            var changed = false
            for k in st.invites.indices where st.invites[k].status == "sent" && s.week > st.invites[k].expires { st.invites[k].status = "expired"; changed = true }
            for k in st.meetings.indices where !st.meetings[k].closed && st.meetings[k].closesAt == nil && s.week > st.meetings[k].deadline {
                count(&s, i, &st, k, data: data, context: fc)
                changed = true
            }
            if changed { save(&s, i, st) }
        }
    }

    // Closes what is due by the clock: an emergency meeting once every item has over half of all shares for it, any meeting at its deadline.
    public static func settle(_ s: inout GameState, now: Double, data: GameData, context fc: FinanceContext) {
        for i in s.companies.indices where s.companies[i].status.isLive {
            guard var st = state(s.companies[i]) else { continue }
            if settleCompany(&s, i, &st, now: now, data: data, context: fc) { save(&s, i, st) }
        }
    }

    static func settleCompany(_ s: inout GameState, _ i: Int, _ st: inout State, now: Double, data: GameData, context fc: FinanceContext) -> Bool {
        var changed = false
        if !st.queue.isEmpty, !partners(st).isEmpty {
            let waiting = st.queue
            st.queue = []
            for it in waiting { addToAgenda(&s, i, &st, it, by: nil, now: now) }
            changed = true
        }
        for k in st.meetings.indices where !st.meetings[k].closed {
            let m = st.meetings[k]
            guard let closes = m.closesAt else { continue }
            let shares = shareMap(s.companies[i], st)
            let carried = m.urgent && !m.items.isEmpty && m.items.allSatisfy { JVRules.decide(JVRules.tally(shares: shares, votes: $0.votes)).passes }
            if now >= closes || carried {
                count(&s, i, &st, k, data: data, context: fc)
                changed = true
            }
        }
        if var offers = st.buybacks {
            for k in offers.indices where offers[k].status == "sent" && now >= offers[k].expiresAt { offers[k].status = "expired"; changed = true }
            st.buybacks = offers
        }
        return changed
    }

    static func count(_ s: inout GameState, _ i: Int, _ st: inout State, _ k: Int, data: GameData, context fc: FinanceContext) {
        let co = s.companies[i]
        let shares = shareMap(co, st)
        var lines: [String] = []
        for n in st.meetings[k].items.indices {
            var it = st.meetings[k].items[n]
            let out = JVRules.decide(JVRules.tally(shares: shares, votes: it.votes))
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
        let resultTitle = "\(co.name) meeting result: \(m.planned ? "weekly meeting" : m.reason)"
        s.addMessage(from: "\(co.name) board", title: resultTitle, body: body, companyID: co.id, tone: m.items.contains { $0.applied } ? "good" : "n")
        st.notes.append(Note(id: s.makeID(), meetingID: m.id, companyID: co.id, fireWeek: s.week, title: resultTitle, body: body))
    }

    public struct ExitTerms: Equatable, Sendable {
        public var name: String
        public var shares: Int
        public var pct: Double
        public var price: Double
        public var locked: Bool
        public var lockUntil: Int
        public var problem: String?
        public var lines: [String]
    }

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
        let after = Double(t.you + shares) / Double(max(1, t.total)) * 100
        let lines = [
            "\(m.name) holds \(String(format: "%.1f", pct))% of \(co.name), worth \(cur.display(price)) now.",
            "You make an offer from your own money. Nothing moves until \(m.name) accepts; they may also decline.",
            "If they accept, they leave the board and your share goes from \(String(format: "%.1f", t.youPct))% to \(String(format: "%.1f", after))%.",
        ]
        return ExitTerms(name: m.name, shares: shares, pct: pct, price: price, locked: locked, lockUntil: m.lockUntil, problem: problem, lines: lines)
    }

    public static func buyBackOffers(_ st: State) -> [Buyback] { (st.buybacks ?? []).filter { $0.status == "sent" } }

    // An offer for a partner's whole stake. Nothing moves until the partner accepts it.
    @discardableResult
    public static func offerBuyBack(_ s: inout GameState, companyID: Int, memberID: String, price: Double, now: Double, data: GameData, context fc: FinanceContext) -> String? {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]), let m = st.members.first(where: { $0.id == memberID && $0.id != Member.me }),
              let t = exitTerms(s, companyID: companyID, memberID: memberID, data: data, context: fc) else { return "That partner is no longer here." }
        if let why = t.problem { return why }
        if buyBackOffers(st).contains(where: { $0.memberID == memberID }) { return "\(m.name) already has an offer from you to answer." }
        let amount = jsRound(price)
        if let why = JVRules.buyBackProblem(price: amount, fair: t.price, rules: s.worldRules) { return why }
        if Payments.liquid(s) < amount { return "You need \(fc.currency(s.companies[i].countryCode, s).display(amount)) in cash to make that offer." }
        var offers = st.buybacks ?? []
        offers.append(Buyback(id: s.makeID(), memberID: memberID, name: m.name, shares: t.shares, price: amount, fair: t.price, sentAt: now,
                              expiresAt: now + JVRules.buybackOpenSeconds, mock: m.mock, status: "sent"))
        st.buybacks = offers
        save(&s, i, st)
        return nil
    }

    @discardableResult
    public static func withdrawBuyBack(_ s: inout GameState, companyID: Int, offerID: Int) -> Bool {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]), var offers = st.buybacks,
              let k = offers.firstIndex(where: { $0.id == offerID && $0.status == "sent" }) else { return false }
        offers[k].status = "withdrawn"
        st.buybacks = offers
        save(&s, i, st)
        return true
    }

    // The partner's answer. Shares and money move only on a yes, and only if the owner can still pay.
    @discardableResult
    public static func answerBuyBack(_ s: inout GameState, companyID: Int, offerID: Int, accept: Bool, data: GameData, context fc: FinanceContext) -> String? {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]), var offers = st.buybacks,
              let k = offers.firstIndex(where: { $0.id == offerID && $0.status == "sent" }) else { return "That offer is no longer open." }
        let o = offers[k]
        let co = s.companies[i]
        let cur = fc.currency(co.countryCode, s)
        if !accept {
            offers[k].status = "declined"
            st.buybacks = offers
            save(&s, i, st)
            s.addMessage(from: "\(co.name) partners", title: "\(o.name) said no", body: "\(o.name) turned down \(cur.display(o.price)) for their shares in \(co.name). Nothing has changed.", companyID: co.id)
            return nil
        }
        let held = CapTable.table(co).holders.first { $0.name == o.name }?.shares ?? 0
        guard let mk = st.members.firstIndex(where: { $0.id == o.memberID }), held == o.shares, held > 0 else {
            offers[k].status = "expired"
            st.buybacks = offers
            save(&s, i, st)
            return "\(o.name) no longer holds those shares."
        }
        if Payments.liquid(s) < o.price {
            offers[k].status = "expired"
            st.buybacks = offers
            save(&s, i, st)
            s.addMessage(from: "\(co.name) partners", title: "\(o.name) said yes, but you could not pay", body: "You no longer have \(cur.display(o.price)) in cash, so the offer lapsed and \(o.name) keeps their shares.", companyID: co.id, tone: "bad")
            return "You no longer have the cash for it."
        }
        Payments.playerPays(&s, o.price, label: "Bought \(o.name)'s shares in \(co.name)", companyID: companyID)
        CapTable.buyFromHolder(&s, i, holder: o.name)
        st.members.remove(at: mk)
        for a in st.meetings.indices where !st.meetings[a].closed {
            for b in st.meetings[a].items.indices { st.meetings[a].items[b].votes[o.memberID] = nil }
        }
        offers[k].status = "accepted"
        st.buybacks = offers
        save(&s, i, st)
        s.note("\(o.name) accepted your offer and left \(co.name). You paid \(cur.display(o.price)) for their shares.", tone: "good", companyID: companyID)
        s.addMessage(from: "\(co.name) partners", title: "\(o.name) sold you their shares", body: "\(o.name) accepted \(cur.display(o.price)) and left the board of \(co.name). Their shares are yours.", companyID: co.id, tone: "good")
        return nil
    }

    @discardableResult
    public static func partnerWantsOut(_ s: inout GameState, companyID: Int, memberID: String, data: GameData, context fc: FinanceContext) -> String? {
        guard let t = exitTerms(s, companyID: companyID, memberID: memberID, data: data, context: fc), let co = s.company(companyID) else { return "That partner is no longer here." }
        if t.locked { return t.problem }
        let cur = fc.currency(co.countryCode, s)
        s.addMessage(from: "\(co.name) partners", title: "\(t.name) wants to sell", body: "\(t.name) wants to leave \(co.name) and sell \(String(format: "%.1f", t.pct))% at what it is worth now: \(cur.display(t.price)). Make them an offer from the Partners section of the company, or keep them as a partner.", companyID: co.id, tone: "n")
        return nil
    }

    static func announceSale(_ s: inout GameState, company co: Company, price: Double, buyer: String, context fc: FinanceContext) {
        guard let st = state(co), !partners(st).isEmpty else { return }
        let cur = fc.currency(co.countryCode, s)
        let pay = JVRules.dissolvePayout(value: price, shares: shareMap(co, st))
        let lines = st.members.map { m in "\(m.id == Member.me ? "You" : m.name) \(cur.display(pay[m.id] ?? 0))" }
        s.addMessage(from: "\(co.name) board", title: "\(co.name) was sold to \(buyer)", body: "Paid out by shares from \(cur.display(price)): " + lines.joined(separator: ", ") + ".", companyID: co.id, tone: "good")
    }

    public struct PendingVote: Equatable, Sendable {
        public var companyName: String
        public var urgent: Bool
        public var reason: String
        public var weeksLeft: Int
        public var hoursLeft: Int? = nil
    }
    public static func pendingVote(_ s: GameState, now: Double? = nil) -> PendingVote? {
        var found: [(Meeting, Company)] = []
        for co in venture(s) {
            for m in state(co)?.meetings ?? [] where !m.closed && m.items.contains(where: { $0.votes[Member.me] == nil }) {
                if let closes = m.closesAt { if let now, now >= closes { continue } } else if !(m.opened <= s.week && s.week <= m.deadline) { continue }
                found.append((m, co))
            }
        }
        guard let hit = found.min(by: { ($0.0.urgent ? 0 : 1, $0.0.closesAt ?? 0) < ($1.0.urgent ? 0 : 1, $1.0.closesAt ?? 0) }) else { return nil }
        var out = PendingVote(companyName: hit.1.name, urgent: hit.0.urgent, reason: hit.0.reason, weeksLeft: max(0, hit.0.deadline - s.week))
        if let closes = hit.0.closesAt, let now { out.hoursLeft = max(0, Int(((closes - now) / 3600).rounded(.up))) }
        return out
    }

    public enum Change: Equatable, Sendable {
        case policy(String)
        case setting(Setting)
    }
    public enum ProposeResult: Equatable, Sendable {
        case applied
        case added(meetingID: Int)
        case called(meetingID: Int)
        case refused(String)
    }

    static func applyChange(_ s: inout GameState, companyID: Int, change: Change, data: GameData) -> (ok: Bool, text: String) {
        switch change {
        case .policy(let p):
            guard s.company(companyID) != nil, Shareholders.policies.contains(p) else { return (false, "The company is no longer there.") }
            Shareholders.setPolicy(&s, companyID: companyID, policy: p)
            return (true, "The dividend policy is now: \((Shareholders.policyNames[p] ?? p).lowercased()).")
        case .setting(let x):
            guard Chains.chain(s, id: x.chainID) != nil else { return (false, "That chain no longer exists.") }
            switch x.rule {
            case "price": Chains.setRule(&s, chainID: x.chainID, rule: .price(x.number))
            case "stock": Chains.setRule(&s, chainID: x.chainID, rule: .stockPolicy(Int(x.number)))
            case "pay": Chains.setRule(&s, chainID: x.chainID, rule: .pay(x.number))
            case "marketing": Chains.setRule(&s, chainID: x.chainID, rule: .marketing(x.text))
            case "knob": _ = Chains.setKnobStandard(&s, chainID: x.chainID, knob: x.text, value: Int(x.number), data: data)
            case "knobFree": Chains.releaseKnobStandard(&s, chainID: x.chainID, knob: x.text)
            default: return (false, "That rule is not known.")
            }
            return (true, x.label + ".")
        }
    }

    // A change to the dividend policy or to a group rule. A sole owner's change applies at once; with co-owners it goes to the weekly
    // meeting, or to a 24-hour emergency meeting when urgent.
    public static func propose(_ s: inout GameState, companyID: Int, change: Change, urgent: Bool, now: Double, data: GameData, context fc: FinanceContext) -> ProposeResult {
        guard let target = s.company(companyID) else { return .refused("That company is gone.") }
        let owners: Company?
        var item = Item(id: s.makeID(), kind: .policy, title: "", effect: "", by: s.player.name)
        item.targetID = companyID
        switch change {
        case .policy(let p):
            guard Shareholders.policies.contains(p) else { return .refused("That is not a dividend policy.") }
            if p == Shareholders.policy(target) { return .refused("That is already the dividend policy.") }
            owners = boardCompany(s, companyID: companyID)
            let name = (Shareholders.policyNames[p] ?? p).lowercased()
            item.policy = p
            item.title = "Dividend policy: \(name)"
            item.effect = JVRules.effect(.policy, name: name, money: { fc.currency(target.countryCode, s).display($0) })
        case .setting(let x):
            guard Chains.chain(s, id: x.chainID) != nil else { return .refused("That chain no longer exists.") }
            owners = boardCompany(s, chainID: x.chainID)
            item.kind = .setting
            item.setting = x
            item.title = x.label
            item.effect = JVRules.effect(.setting, name: x.label, money: { fc.currency(target.countryCode, s).display($0) })
        }
        guard let board = owners, let i = s.companyIndex(board.id), var st = state(board) else {
            let r = applyChange(&s, companyID: companyID, change: change, data: data)
            return r.ok ? .applied : .refused(r.text)
        }
        if urgent {
            switch callUrgent(&s, companyID: board.id, by: Member.me, reason: item.title, items: [item], now: now, data: data, context: fc) {
            case .called(let id): return .called(meetingID: id)
            case .refused(let why): return .refused(why)
            }
        }
        let id = addToAgenda(&s, i, &st, item, by: Member.me, now: now)
        save(&s, i, st)
        return .added(meetingID: id)
    }

    static func apply(_ s: inout GameState, _ i: Int, _ st: inout State, _ it: Item, data: GameData, context fc: FinanceContext) -> (ok: Bool, text: String) {
        let co = s.companies[i]
        let cur = fc.currency(co.countryCode, s)
        guard co.status.isLive else { return (false, "The company is no longer there.") }
        switch it.kind {
        case .dividend:
            switch Payments.payDividend(&s, companyID: co.id, amount: it.amount) {
            case .ok: return (true, "\(cur.display(it.amount)) was paid out by shares.")
            case .notEnoughCash: return (false, "You no longer have the cash for it.")
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
            if let why = SaleListings.routeProblem(s, companyID: co.id, route: "private", pct: 100, board: true) { return (false, why) }
            let started = SaleListings.start(&s, companyID: co.id, route: "private", extra: ["jv": .number(1)])
            return started ? (true, "\(co.name) is put on the market. Offers come to its Sell page for you to answer for all owners; none under \(Int(JVRules.lowestSaleShare * 100))% of its value is accepted. When it sells, every owner is paid by their shares.") : (false, "\(co.name) cannot be listed now.")
        case .partner:
            if let why = inviteProblem(s, co, st, linkKey: it.linkKey, pct: it.pct, price: it.price, mock: it.mock, myLinkKeys: [], data: data) { return (false, why) }
            makeInvite(&s, i, &st, playerID: it.playerID, name: it.name, linkKey: it.linkKey, role: it.role, mock: it.mock, pct: it.pct, price: it.price)
            return (true, "\(it.name) was invited. They join when they accept.")
        case .policy:
            guard let p = it.policy else { return (false, "There was nothing to change.") }
            return applyChange(&s, companyID: it.targetID ?? co.id, change: .policy(p), data: data)
        case .setting:
            guard let x = it.setting else { return (false, "There was nothing to change.") }
            return applyChange(&s, companyID: co.id, change: .setting(x), data: data)
        case .dissolve:
            let value = companyValue(s, s.companies[i], data: data)
            let shares = shareMap(s.companies[i], st)
            let pay = JVRules.dissolvePayout(value: value, shares: shares)
            s.rest["jvgo"] = .number(Double(co.id))
            let done = CompanySale.complete(&s, companyIndex: i, buyer: "Dissolution", price: value, data: data, context: fc)
            s.rest["jvgo"] = nil
            guard done != nil else { return (false, "The company cannot be dissolved now.") }
            let others = st.members.filter { $0.id != Member.me }.map { "\($0.name) \(cur.display(pay[$0.id] ?? 0))" }.joined(separator: ", ")
            return (true, "Paid out by shares from a value of \(cur.display(value)): you \(cur.display(pay[Member.me] ?? 0))" + (others.isEmpty ? "." : "; \(others)."))
        }
    }
}
