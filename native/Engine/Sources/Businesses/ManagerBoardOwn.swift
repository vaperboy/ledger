import Foundation
import GameCore
import Countries
import Employees

/// One possible board member for a seat: somebody of your own, or a searched candidate.
public struct BoardCandidate: Identifiable, Equatable, Sendable {
    public var id: Int { personID }
    public var personID: Int
    public var name: String
    public var qualification: String
    public var feePerYear: Double
    public var isOwnStaff: Bool
}

extension ManagerModel {
    /// An employee on the board of their own company sits for this share of the normal fee.
    static let ownCompanySeatFeeShare = 0.5
    static let ownStaffMinScore = 55.0

    /// Strength for a seat: the matching leadership number when the person has one (managers), otherwise their skill.
    static func seatScore(_ n: Person, _ R: SeatRole) -> Double {
        let st = n.value("stats")
        return st.isNull || st[R.stat].isNull ? n.skill : st[R.stat].double
    }
    static func ownSeatMonthlyFee(_ s: GameState, key: String, person n: Person, role R: SeatRole, data: GameData) -> Double {
        let cur = playerCurrency(s, data)
        let base = cur.roundedStep(cur.scaledPrice(R.baseFee * (0.7 + seatScore(n, R) / 150)), about: 500)
        let own = boardCompanies(s, key: key).contains { $0.id == n.employerID }
        return own ? cur.roundedStep(base * ownCompanySeatFeeShare, about: 500) : base
    }
    /// Employees and managers of your live companies, in company order.
    static func ownPeople(_ s: GameState) -> [Person] {
        var seen = Set<Int>(), out: [Person] = []
        for c in s.companies where c.status.isLive {
            let ids = (c.managerID.map { [$0] } ?? []) + c.staff.map { $0.id }
            for id in ids { if let n = s.people[id], n.employerID == c.id, seen.insert(id).inserted { out.append(n) } }
        }
        return out
    }
    static func ownSeatProblem(_ s: GameState, key: String, role: String, personID: Int) -> String? {
        guard let R = seatRoles.first(where: { $0.id == role }) else { return "There is no such seat." }
        guard !boardCompanies(s, key: key).isEmpty else { return "There is no board here." }
        let L = board(s, key: key)["seats"].array
        if L.contains(where: { $0["id"].int == personID }) { return "Already on this board." }
        if seats(s, key: key).filter({ $0.role == role }).count >= R.maxSeats { return "That seat is full." }
        if heldSeatCount(L) + 2 >= maxBoard { return "The board is full." }
        return nil
    }
    /// Your own people who qualify for the seat (not already on the board) followed by the candidates found by a search for it.
    public static func boardCandidates(_ s: GameState, key: String, role: String, data: GameData) -> [BoardCandidate] {
        guard let R = seatRoles.first(where: { $0.id == role }) else { return [] }
        let onBoard = Set(board(s, key: key)["seats"].array.map { $0["id"].int })
        var out: [BoardCandidate] = []
        if ownSeatProblem(s, key: key, role: role, personID: -1) == nil {
            for n in ownPeople(s) where !onBoard.contains(n.id) && seatScore(n, R) >= ownStaffMinScore {
                let at = s.company(n.employerID)?.name ?? "your group"
                out.append(BoardCandidate(personID: n.id, name: n.name, qualification: "\(n.role) at \(at), \(R.stat) \(Int(seatScore(n, R)))",
                                          feePerYear: ownSeatMonthlyFee(s, key: key, person: n, role: R, data: data) * 12, isOwnStaff: true))
            }
        }
        let b = board(s, key: key)
        if b["candR"].string == role {
            for x in b["cands"].array { if let n = s.people[x.int], n.employerID == 0 {
                out.append(BoardCandidate(personID: n.id, name: n.name, qualification: "\(n.str("advBg")), \(R.stat) \(Int(seatScore(n, R)))", feePerYear: n.num("fee13") * 12, isOwnStaff: false)) } }
        }
        return out
    }
    /// Seat one of your own people; they keep their job. Removal is `removeFromBoard`. Returns the reason when refused.
    public static func appointOwn(_ s: inout GameState, key: String, role: String, personID: Int, data: GameData) -> String? {
        guard let R = seatRoles.first(where: { $0.id == role }) else { return "There is no such seat." }
        if let why = ownSeatProblem(s, key: key, role: role, personID: personID) { return why }
        guard let n = s.people[personID], ownPeople(s).contains(where: { $0.id == personID }) else { return "Only your own people can be seated this way." }
        guard seatScore(n, R) >= ownStaffMinScore else { return "\(n.name) is not experienced enough for that seat." }
        let fee = ownSeatMonthlyFee(s, key: key, person: n, role: R, data: data)
        guard addSeat(&s, boardKey: key, seat: ["id": .number(Double(personID)), "kind": "own", "r": .string(role), "t": .string(R.title), "fee": .number(fee)]) else { return "The board is full." }
        s.note("\(n.name) now also sits as \(R.title.lowercased()) on the board of \(boardName(s, key: key)).", tone: "good")
        return nil
    }
}
