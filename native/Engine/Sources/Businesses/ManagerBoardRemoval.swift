import Foundation
import GameCore
import Countries
import Employees
import Finance

/// What taking one person off a board would do, shown before the owner confirms.
public struct SeatRemovalTerms: Equatable, Sendable {
    public var allowed: Bool
    /// Why it cannot be done (empty when allowed).
    public var reason: String
    public var keepsJob: Bool
    /// You hold half or less of the shares: the shareholders vote, and the seat holder may stay.
    public var needsVote: Bool = false
    public var noticeMonths: Int
    /// Notice pay, paid by the board's companies.
    public var cost: Double
    /// One plain sentence for the confirm popup.
    public var summary: String
}

extension ManagerModel {
    /// Directors are on a contract with three months notice; every other outside seat has one month. Your own staff have none.
    static func removalNoticeMonths(role: String) -> Int { role == "director" ? 3 : 1 }

    /// The smallest share the owner holds in the companies behind the board (shareholders vote to remove an outside seat holder).
    static func controlShare(_ s: GameState, key: String) -> Double {
        boardCompanies(s, key: key).map { $0.ownership }.min() ?? 0
    }

    public static func seatRemovalTerms(_ s: GameState, key: String, personID: Int) -> SeatRemovalTerms {
        func no(_ why: String) -> SeatRemovalTerms { SeatRemovalTerms(allowed: false, reason: why, keepsJob: false, noticeMonths: 0, cost: 0, summary: why) }
        guard let seat = seats(s, key: key).first(where: { $0.id == personID }) else { return no("They do not hold a seat on this board.") }
        let name = s.people[personID]?.name ?? "They"
        if seat.kind == "own" {
            return SeatRemovalTerms(allowed: true, reason: "", keepsJob: true, noticeMonths: 0, cost: 0,
                                    summary: "\(name) keeps their job and loses only the seat and its fee. No notice is owed.")
        }
        let share = controlShare(s, key: key)
        let months = removalNoticeMonths(role: seat.role)
        let cost = seat.monthlyFee * Double(months)
        let unit = months == 1 ? "month" : "months"
        if share <= 50 {
            return SeatRemovalTerms(allowed: true, reason: "", keepsJob: false, needsVote: true, noticeMonths: months, cost: cost,
                                    summary: "You hold \(Int(jsRound(share)))%, so the shareholders vote on removing \(name). Only if more than half of the shares agree are they let go, and then \(months) \(unit) notice is paid. If the vote fails they stay.")
        }
        return SeatRemovalTerms(allowed: true, reason: "", keepsJob: false, noticeMonths: months, cost: cost,
                                summary: "\(name) is on a contract with \(months) \(unit) notice. The shareholders (you hold \(Int(jsRound(share)))%) vote them out and the companies pay the notice.")
    }

    /// Take one person off the board. Own staff keep their job; outside seat holders are paid their notice. Returns the reason when refused.
    public static func removeSeatHolder(_ s: inout GameState, key: String, personID: Int) -> String? {
        let t = seatRemovalTerms(s, key: key, personID: personID)
        guard t.allowed, let seat = seats(s, key: key).first(where: { $0.id == personID }), var n = s.people[personID] else {
            return t.reason.isEmpty ? "They do not hold a seat on this board." : t.reason
        }
        let cos = boardCompanies(s, key: key)
        if t.needsVote {
            // The co-owners vote their shares: a weak seat holder is easier to vote out. More than half of all shares must agree.
            let q = leadership(n)
            var yes = controlShare(s, key: key)
            for x in holders(s, key: key) where HashedRandom.first("rm15:\(x.h["name"].string):\(personID):\(s.week)") < 0.7 - q * 0.5 { yes += x.h["pct"].double }
            if yes <= 50 {
                let said = "The shareholders voted against removing \(n.name): only \(Int(jsRound(yes)))% of the shares were for it."
                s.note(said, tone: "n")
                return said
            }
        }
        if t.cost > 0 && !cos.isEmpty {
            for c in cos { _ = Payments.companyPays(&s, companyID: c.id, amount: t.cost / Double(cos.count), category: "oth", label: "Notice pay: \(n.name)") }
        }
        if seat.kind == "adv" && n.employerID == -4 { n.employerID = 0; s.people[personID] = n }
        var b = board(s, key: key)
        b["seats"] = .array(b["seats"].array.filter { $0["id"].int != personID })
        writeBoard(&s, key: key, b)
        let at = boardName(s, key: key)
        if seat.kind == "own" {
            s.note("\(n.name) was taken off the board of \(at) and keeps their job.", tone: "n")
        } else {
            let unit = t.noticeMonths == 1 ? "month" : "months"
            s.note("\(n.name) was removed from the board of \(at) by the shareholders. Notice pay: \(t.noticeMonths) \(unit).", tone: "n")
        }
        return nil
    }
}
