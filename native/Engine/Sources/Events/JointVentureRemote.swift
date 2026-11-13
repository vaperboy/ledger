import Foundation
import GameCore
import Countries
import Finance
import Businesses

// A board with real players on it is run by the game server. These are the steps the company takes to follow it:
// remember the server's ids, show the server's count, and carry out what the server decided.
public extension JointVenture {

    static func setRemote(_ s: inout GameState, companyID: Int, ventureID: String) {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]), st.remoteID != ventureID else { return }
        st.remoteID = ventureID
        save(&s, i, st)
    }

    static func linkInvite(_ s: inout GameState, companyID: Int, inviteID: Int, remoteID: String) {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]), let k = st.invites.firstIndex(where: { $0.id == inviteID }) else { return }
        st.invites[k].remoteID = remoteID
        save(&s, i, st)
    }

    // Closes an invitation that the server refused, or that ran out there.
    @discardableResult
    static func dropInvite(_ s: inout GameState, companyID: Int, inviteID: Int, status: String, why: String?) -> Bool {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]), let k = st.invites.firstIndex(where: { $0.id == inviteID && $0.status == "sent" }) else { return false }
        let inv = st.invites[k]
        st.invites[k].status = status
        save(&s, i, st)
        if let why {
            let co = s.companies[i]
            s.addMessage(from: "\(co.name) partners", title: "The invitation to \(inv.name) did not go out", body: why, companyID: co.id, tone: "bad")
        }
        return true
    }

    // A real player accepted on the server and has paid. The invitation is made here first if this company never held it.
    @discardableResult
    static func remoteJoin(_ s: inout GameState, companyID: Int, playerID: String, name: String, pct: Double, price: Double, lockAt: Double?,
                           data: GameData, context fc: FinanceContext) -> String? {
        guard let i = s.companyIndex(companyID) else { return "That company is gone." }
        var st = state(s.companies[i]) ?? State(members: [Member(id: Member.me, name: s.player.name, role: "chair", mock: false, joined: s.week, lockUntil: 0, linkKey: "me")])
        if st.members.contains(where: { $0.id == "p:" + playerID }) { return nil }
        let inviteID: Int
        if let inv = st.invites.first(where: { $0.playerID == playerID && $0.status == "sent" }) {
            inviteID = inv.id
        } else {
            inviteID = makeInvite(&s, i, &st, playerID: playerID, name: name, linkKey: playerID, role: "partner", mock: false, pct: pct, price: price).id
            save(&s, i, st)
        }
        if let why = respond(&s, companyID: companyID, inviteID: inviteID, accept: true, settled: true, data: data, context: fc) { return why }
        if let lockAt, var joined = state(s.companies[i]), let k = joined.members.firstIndex(where: { $0.id == "p:" + playerID }) {
            joined.members[k].lockAt = lockAt
            save(&s, i, joined)
        }
        return nil
    }

    static func linkItem(_ s: inout GameState, companyID: Int, meetingID: Int, itemID: Int, remoteID: String, remoteMeeting: String, closesAt: Double?) {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]), let k = st.meetings.firstIndex(where: { $0.id == meetingID }),
              let n = st.meetings[k].items.firstIndex(where: { $0.id == itemID }) else { return }
        st.meetings[k].items[n].remoteID = remoteID
        st.meetings[k].items[n].remoteMeeting = remoteMeeting
        if let closesAt { st.meetings[k].closesAt = closesAt }
        save(&s, i, st)
    }

    // Takes an item off the agenda because the server would not have it. An emptied meeting goes with it.
    @discardableResult
    static func dropItem(_ s: inout GameState, companyID: Int, meetingID: Int, itemID: Int, why: String) -> Bool {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]), let k = st.meetings.firstIndex(where: { $0.id == meetingID && !$0.closed }),
              let n = st.meetings[k].items.firstIndex(where: { $0.id == itemID && $0.outcome == nil }) else { return false }
        let it = st.meetings[k].items.remove(at: n)
        if st.meetings[k].items.isEmpty {
            st.meetings.remove(at: k)
        } else if st.meetings[k].items.allSatisfy({ $0.outcome != nil }) {
            finish(&s, i, &st, k)
        }
        save(&s, i, st)
        let co = s.companies[i]
        s.addMessage(from: "\(co.name) board", title: "Not put to the board: \(it.title)", body: why, companyID: co.id, tone: "bad")
        return true
    }

    // The server's running count for an open item, in shares.
    @discardableResult
    static func remoteStanding(_ s: inout GameState, companyID: Int, meetingID: Int, itemID: Int, yes: Double, no: Double, total: Double) -> Bool {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]), let k = st.meetings.firstIndex(where: { $0.id == meetingID && !$0.closed }),
              let n = st.meetings[k].items.firstIndex(where: { $0.id == itemID }) else { return false }
        let it = st.meetings[k].items[n]
        if it.remoteYes == yes, it.remoteNo == no, it.remoteTotal == total { return false }
        st.meetings[k].items[n].remoteYes = yes
        st.meetings[k].items[n].remoteNo = no
        st.meetings[k].items[n].remoteTotal = total
        save(&s, i, st)
        return true
    }

    // The server counted an item. It is carried out here when it passed; the meeting closes once every item is counted.
    @discardableResult
    static func remoteResult(_ s: inout GameState, companyID: Int, meetingID: Int, itemID: Int, passed: Bool, votes: [String: JVRules.Choice],
                             data: GameData, context fc: FinanceContext) -> Bool {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]), let k = st.meetings.firstIndex(where: { $0.id == meetingID && !$0.closed }),
              let n = st.meetings[k].items.firstIndex(where: { $0.id == itemID && $0.outcome == nil }) else { return false }
        for (member, choice) in votes { st.meetings[k].items[n].votes[member] = choice }
        decide(&s, i, &st, k, n, outcome: passed ? .passed : .failed, data: data, context: fc)
        let it = st.meetings[k].items[n]
        if passed, it.kind == .dividend, !it.applied, s.companies[i].status.isLive {
            // The partners have their money from the server already, so the company's side is booked even when it is short.
            let outside = jsRound(it.amount * (1 - s.companies[i].ownership / 100))
            if outside > 0 { _ = Payments.companyPays(&s, companyID: companyID, amount: outside, category: nil, label: "Dividend to other shareholders") }
            st.meetings[k].items[n].applied = true
            st.meetings[k].items[n].result = "\(fc.currency(s.companies[i].countryCode, s).display(it.amount)) was paid out by shares."
        }
        if st.meetings[k].items.allSatisfy({ $0.outcome != nil }) { finish(&s, i, &st, k) }
        save(&s, i, st)
        return true
    }

    static func linkBuyBack(_ s: inout GameState, companyID: Int, offerID: Int, remoteID: String) {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]), var offers = st.buybacks, let k = offers.firstIndex(where: { $0.id == offerID }) else { return }
        offers[k].remoteID = remoteID
        st.buybacks = offers
        save(&s, i, st)
    }

    // The server closed an offer without a sale: the partner said no, or it ran out.
    @discardableResult
    static func closeBuyBack(_ s: inout GameState, companyID: Int, offerID: Int, declined: Bool, data: GameData, context fc: FinanceContext) -> Bool {
        if declined { return answerBuyBack(&s, companyID: companyID, offerID: offerID, accept: false, data: data, context: fc) == nil }
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]), var offers = st.buybacks,
              let k = offers.firstIndex(where: { $0.id == offerID && $0.status == "sent" }) else { return false }
        offers[k].status = "expired"
        st.buybacks = offers
        save(&s, i, st)
        return true
    }

    // A real partner's shares went back to the owner on the server, for this price. Books the purchase and takes them off the board.
    @discardableResult
    static func partnerLeft(_ s: inout GameState, companyID: Int, memberID: String, price: Double, data: GameData, context fc: FinanceContext) -> String? {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]), let mk = st.members.firstIndex(where: { $0.id == memberID && $0.id != Member.me }) else {
            return "That partner is no longer here."
        }
        let m = st.members[mk]
        let held = CapTable.table(s.companies[i]).holders.first { $0.name == m.name }?.shares ?? 0
        if held <= 0 {
            st.members.remove(at: mk)
            save(&s, i, st)
            return nil
        }
        var offers = st.buybacks ?? []
        let amount = jsRound(max(0, price))
        let offerID: Int
        if let k = offers.firstIndex(where: { $0.memberID == memberID && $0.status == "sent" }) {
            offers[k].price = amount
            offers[k].shares = held
            offerID = offers[k].id
        } else {
            let o = Buyback(id: s.makeID(), memberID: memberID, name: m.name, shares: held, price: amount, fair: amount, sentAt: 0, expiresAt: 0, mock: false, status: "sent")
            offers.append(o)
            offerID = o.id
        }
        st.buybacks = offers
        save(&s, i, st)
        return answerBuyBack(&s, companyID: companyID, offerID: offerID, accept: true, settled: true, data: data, context: fc)
    }

    // The quarter's policy dividend that the server has passed on to the real partners.
    static func markDividendSent(_ s: inout GameState, companyID: Int, week: Int) {
        guard let i = s.companyIndex(companyID), var st = state(s.companies[i]), st.remotePaidWeek != week else { return }
        st.remotePaidWeek = week
        save(&s, i, st)
    }
}

// Money and news from the server about companies the player co-owns with other players.
public enum JointVentureSettlements {
    static let key = "jvHeld"
    static let sender = "Partner shares"

    public struct Holding: Equatable, Identifiable, Sendable {
        public var id: String
        public var name: String
        public var paid: Double
        public var received: Double
        public var sinceWeek: Int
    }

    public static func holdings(_ s: GameState) -> [Holding] {
        (s.rest[key]?.array ?? []).map { (v: JSONValue) -> Holding in
            Holding(id: v["id"].string, name: v["name"].string, paid: v["paid"].double, received: v["got"].double, sinceWeek: v["w"].int)
        }
    }

    static func write(_ s: inout GameState, _ list: [Holding]) {
        s.rest[key] = .array(list.suffix(40).map { (h: Holding) -> JSONValue in
            .object(["id": .string(h.id), "name": .string(h.name), "paid": .number(h.paid), "got": .number(h.received), "w": .number(Double(h.sinceWeek))])
        })
    }

    static func change(_ s: inout GameState, ventureID: String, name: String, _ body: (inout Holding) -> Void) {
        var list = holdings(s)
        if let k = list.firstIndex(where: { $0.id == ventureID }) {
            body(&list[k])
        } else {
            var h = Holding(id: ventureID, name: name, paid: 0, received: 0, sinceWeek: s.week)
            body(&h)
            list.append(h)
        }
        write(&s, list)
    }

    static func tell(_ s: inout GameState, title: String, body: String, tone: String = "n") {
        s.addMessage(kind: "info", from: sender, title: title, body: body, companyID: 0, tone: tone)
    }

    static func tail(_ label: String, after prefix: String) -> String {
        label.hasPrefix(prefix) ? String(label.dropFirst(prefix.count)) : label
    }

    // Books one server settlement. `amount` is in game money. Returns false for kinds that are not about co-owned companies.
    public static func book(_ s: inout GameState, _ item: OnlineSettlement, amount: Double) -> Bool {
        guard item.kind.hasPrefix("venture_") else { return false }
        let venture = item.meta["ventureID"].string
        // Rounded the way the account moves it, so holdings and tax record what really moved.
        let money: Double = amount.isFinite ? jsRound(abs(amount)) : 0
        switch item.kind {
        case "venture_stake":
            let name = tail(item.label, after: "Joined ")
            if money > 0 { Payments.playerPays(&s, money, label: "Bought shares in \(name)") }
            change(&s, ventureID: venture, name: name) { (h: inout Holding) -> Void in h.paid += money; h.name = name }
            tell(&s, title: "You are a partner in \(name)", body: "You paid for your shares and hold \(String(format: "%.1f", item.meta["percent"].double))% of \(name). You vote at its board meetings and share in its dividends.", tone: "good")
        case "venture_capital_call":
            let name = tail(item.label, after: "Capital call: ")
            if money > 0 { Payments.playerPays(&s, money, label: item.label.isEmpty ? "Capital call" : item.label) }
            change(&s, ventureID: venture, name: name) { (h: inout Holding) -> Void in h.paid += money }
            tell(&s, title: "Capital call: \(name)", body: "The owners voted to put more money into \(name). Your part was taken from your cash.")
        case "venture_dividend":
            let name = tail(item.label, after: "Dividend: ")
            if money > 0 {
                Payments.playerReceives(&s, money, label: item.label.isEmpty ? "Dividend" : item.label)
                s.tax.dividends += money
            }
            change(&s, ventureID: venture, name: name) { (h: inout Holding) -> Void in h.received += money }
            tell(&s, title: "Dividend from \(name)", body: "Your part of the dividend from \(name) is in your account.", tone: "good")
        case "venture_exit", "venture_dissolved":
            let held: Holding? = holdings(s).first { $0.id == venture }
            if money > 0 { Payments.playerReceives(&s, money, label: item.label.isEmpty ? "Sold partner shares" : item.label) }
            if let held, money > held.paid { s.tax.gains += money - held.paid }
            write(&s, holdings(s).filter { $0.id != venture })
            tell(&s, title: item.kind == "venture_exit" ? "Your shares are sold" : "The company was closed", body: item.label.isEmpty ? "The money for your shares is in your account." : item.label + ". The money is in your account.", tone: "good")
        case "venture_decision":
            if item.meta["companyKey"].isNull, !item.label.isEmpty {
                tell(&s, title: "Board decision", body: item.label, tone: item.meta["passed"].bool ? "good" : "n")
            }
        case "venture_buyback_reply":
            if item.meta["companyKey"].isNull, !item.label.isEmpty { tell(&s, title: "Your offer was turned down", body: item.label) }
        case "venture_capital", "venture_company_payout", "venture_buyback":
            // The owner's side of these is booked by the company when it follows the board, so nothing moves here.
            break
        default:
            return false
        }
        return true
    }
}
