import Foundation
import GameCore
import Countries
import Employees
import Finance

extension ManagerModel {
    public static let ignorableShare = 5.0

    public struct Attendee: Identifiable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var percent: Double
        public var yes: Bool
        public var isYou: Bool
        public var activity: Double = 0.6
        public var chance: Double = 1
        public var present: Bool = true
        public var arrives: Double = 0

        public init(id: String, name: String, percent: Double, yes: Bool, isYou: Bool = false, activity: Double = 0.6, chance: Double = 1, present: Bool = true, arrives: Double = 0) {
            self.id = id; self.name = name; self.percent = percent; self.yes = yes; self.isYou = isYou
            self.activity = activity; self.chance = chance; self.present = present; self.arrives = arrives
        }
    }

    public struct MeetingVerdict: Equatable, Sendable {
        public var passes: Bool
        public var yesPercent: Double
        public var noPercent: Double
        public var absentPercent: Double
        public var blockers: [Attendee]
        public var blockedByAbsent: Bool
    }

    public struct MeetingRuling: Identifiable, Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case carried, votedDown, blocked, refused }
        public var id: String
        public var kind: Kind
        public var line: String
        public var yesPercent: Double
        public var noPercent: Double
        public var attendees: [Attendee]

        public init(id: String, kind: Kind, line: String, yesPercent: Double, noPercent: Double, attendees: [Attendee]) {
            self.id = id; self.kind = kind; self.line = line; self.yesPercent = yesPercent; self.noPercent = noPercent; self.attendees = attendees
        }
    }

    public struct MeetingBallot: Equatable, Sendable {
        public var attendees: [Attendee]
        public var verdict: MeetingVerdict
        public var alone: Bool
        public var passes: Bool { verdict.passes }
    }

    public static let agendaLimit = 4

    public static func joinChance(percent: Double, activity: Double) -> Double {
        let stake = min(1, max(0, percent) / 30)
        let active = min(1, max(0, activity))
        return min(0.97, 0.35 + 0.4 * stake + 0.2 * active)
    }

    public static func gather(_ stakes: [Attendee], seed: String) -> [Attendee] {
        stakes.map { (a: Attendee) -> Attendee in
            var x = a
            if a.isYou { x.chance = 1; x.present = true; x.arrives = 0; return x }
            var r = HashedRandom("\(seed):\(a.id)")
            x.chance = joinChance(percent: a.percent, activity: a.activity)
            x.present = r.next() < x.chance
            x.arrives = 0.1 + 0.8 * r.next()
            return x
        }
    }

    public static func meetingVerdict(_ people: [Attendee]) -> MeetingVerdict {
        let here = people.filter { $0.present }
        let yes = here.filter { $0.yes }.reduce(0) { $0 + $1.percent }
        let no = here.filter { !$0.yes }.reduce(0) { $0 + $1.percent }
        let away = people.filter { !$0.present }
        let blockers = away.filter { $0.percent > ignorableShare }.sorted { $0.percent > $1.percent }
        let blockPct = blockers.reduce(0) { $0 + $1.percent }
        let majority = yes > no
        let blocked = majority && blockPct > yes - no
        return MeetingVerdict(passes: majority && !blocked, yesPercent: yes, noPercent: no, absentPercent: away.reduce(0) { $0 + $1.percent },
                              blockers: blockers, blockedByAbsent: blocked)
    }

    static func meetingKind(_ kind: String) -> String? {
        switch kind {
        case "sell", "dividend", "open", "ceo": return kind
        case "close", "shut": return "close"
        default: return nil
        }
    }

    static func meetingSeed(_ s: GameState, key: String) -> String { "bm:\(key):\(board(s, key: key)["mc"].int)" }

    public static func meetingStakes(_ s: GameState, _ d: BoardDecision) -> [Attendee] {
        guard let kind = meetingKind(d.kind), let co = s.company(d.companyID) else { return [] }
        let vote = boardVote(s, kind: kind, companyID: d.companyID, advisory: true)
        guard !vote.directorsDecide, vote.owners.contains(where: { !$0.isYou }) else { return [] }
        let held = co.value("holders").array
        return vote.owners.map { (l: VoteLine) -> Attendee in
            let match: JSONValue? = held.first(where: { $0["name"].string == l.name })
            let sat: JSONValue = match.map { $0["sat"] } ?? .null
            return Attendee(id: l.id, name: l.name, percent: l.percent, yes: l.yes, isYou: l.isYou, activity: sat.isNull ? 0.6 : min(1, max(0, sat.double / 100)))
        }
    }

    public static func meetingAttendees(_ s: GameState, key: String, _ d: BoardDecision) -> [Attendee] {
        gather(meetingStakes(s, d), seed: meetingSeed(s, key: key))
    }

    public static func voteChance(opinion: Bool, percent: Double, satisfaction: Double) -> Double {
        let sat = min(1, max(0, satisfaction))
        let firm = 0.1 + 0.2 * min(1, max(0, percent) / 30)
        let lean = 0.5 + (opinion ? 0.2 + firm : -0.2 - firm)
        return min(0.97, max(0.03, lean + 0.2 * (sat - 0.5)))
    }

    public static func castVotes(_ people: [Attendee], seed: String, youYes: Bool) -> [Attendee] {
        people.map { (a: Attendee) -> Attendee in
            var x = a
            if a.isYou { x.yes = youYes; return x }
            var r = HashedRandom("\(seed):v:\(a.id)")
            x.yes = r.next() < voteChance(opinion: a.yes, percent: a.percent, satisfaction: a.activity)
            return x
        }
    }

    public static func ballot(_ s: GameState, key: String, _ d: BoardDecision, youYes: Bool) -> MeetingBallot {
        let here = meetingAttendees(s, key: key, d)
        guard !here.isEmpty else {
            return MeetingBallot(attendees: [], verdict: MeetingVerdict(passes: youYes, yesPercent: youYes ? 100 : 0, noPercent: youYes ? 0 : 100, absentPercent: 0, blockers: [], blockedByAbsent: false), alone: true)
        }
        let voted = castVotes(here, seed: meetingSeed(s, key: key) + ":" + d.id, youYes: youYes)
        return MeetingBallot(attendees: voted, verdict: meetingVerdict(voted), alone: false)
    }

    public static func meetingAgenda(_ s: GameState, keys: [String], data: GameData) -> [BoardDecision] {
        var seen = Set<String>()
        let all = keys.flatMap { (k: String) -> [BoardDecision] in meetingDecisions(s, key: k, data: data) }
            .filter { (d: BoardDecision) -> Bool in meetingKind(d.kind) != nil && seen.insert(d.id).inserted }
        return Array((all.filter { $0.recommends } + all.filter { !$0.recommends }).prefix(agendaLimit))
    }

    public static func meetingGuests(_ s: GameState, _ points: [BoardDecision]) -> [Attendee] {
        var seen = Set<String>()
        return points.flatMap { (d: BoardDecision) -> [Attendee] in meetingAttendees(s, key: d.key, d) }.filter { (a: Attendee) -> Bool in !a.isYou && seen.insert(a.id).inserted }
    }

    public static func meetingSubject(_ d: BoardDecision, _ s: GameState) -> String {
        let name = s.company(d.companyID)?.name ?? "the company"
        switch d.kind {
        case "dividend": return "Dividend at \(name)"
        case "close": return "Closing \(name)"
        case "sell": return "Sale of \(name)"
        case "ceo": return "New manager at \(name)"
        default: return d.title
        }
    }

    public static func meetingDone(_ kind: String) -> String {
        switch kind {
        case "dividend": return "dividend set"
        case "close": return "wound up"
        case "sell": return "listed for sale"
        case "ceo": return "manager replaced"
        case "open": return "location opening"
        default: return "location closed"
        }
    }

    public static func rulingLine(subject: String, ballot b: MeetingBallot, kind: MeetingRuling.Kind, detail: String = "") -> String {
        let yes = Int(saturating: shareOfVote(b.verdict).rounded())
        let tally = " \(yes)% to \(100 - yes)%"
        switch kind {
        case .carried:
            let how = b.alone ? " by you" : tally
            return "\(subject) approved\(how): \(detail)"
        case .votedDown:
            if b.alone { return "\(subject) not carried: you voted no." }
            return "\(subject) rejected\(tally)."
        case .blocked:
            return "\(subject) held up: \(detail) stayed away and could block it."
        case .refused:
            return "\(subject): \(detail)"
        }
    }

    static func shareOfVote(_ v: MeetingVerdict) -> Double {
        let total = v.yesPercent + v.noPercent
        return total <= 0 ? 0 : v.yesPercent * 100 / total
    }

    public static func countMeeting(_ s: inout GameState, key: String) {
        var b = board(s, key: key)
        b["mc"] = .number(Double(b["mc"].int + 1))
        writeBoard(&s, key: key, b)
    }

    static func decisionText(_ kind: String, _ c: Company, manager: String = "") -> (title: String, effect: String, risk: String) {
        switch kind {
        case "sell":
            return ("Put \(c.name) up for sale", "\(c.name) is listed with a broker. Offers reach you; nothing is sold until you accept one.",
                    "If you later accept an offer you stop owning the business.")
        case "close":
            return ("Close \(c.name)", "\(c.name) is wound up: assets sold at a discount, staff let go, loans repaid as far as the money goes. You get what is left.",
                    "It cannot be undone, and notice and redundancy pay come first.")
        case "dividend":
            return ("Start a regular dividend at \(c.name)", "\(c.name) pays 25% of profit to its owners each quarter, when there is profit and cash after costs.",
                    "Cash leaves the company every quarter. You receive your share.")
        default:
            return ("Replace \(manager) as manager of \(c.name)", "The manager is dismissed under the notice and severance rules of the country.",
                    "The company has no manager until you appoint one.")
        }
    }

    public static func putForward(_ s: GameState, key: String, data: GameData) -> [BoardDecision] {
        let raised = Set(boardDecisions(s, key: key, data: data).map { $0.id })
        let memo = board(s, key: key)["memo"]
        var out: [BoardDecision] = []
        for c in boardCompanies(s, key: key) where c.status == .open {
            let p3 = c.monthlyHistory.suffix(3).reduce(0.0) { $0 + $1.profit }
            let adviser = advisor(s, c)
            func add(_ kind: String, manager: String = "", recommends: Bool, reason: String) {
                let id = "\(kind):\(c.id)"
                guard !raised.contains(id), memo[id].isNull || memo[id].int <= s.week else { return }
                let t = decisionText(kind, c, manager: manager)
                out.append(BoardDecision(id: id, key: key, kind: kind, companyID: c.id, title: t.title, effect: t.effect, cost: 0, risk: t.risk,
                                         advisor: adviser, recommends: recommends, reason: reason))
            }
            if !s.isBranch(c) {
                add("close", recommends: false, reason: p3 < 0 ? "Losses over three months. Selling it from Money may bring more than closing." : "It is profitable. Selling it from Money is kinder than closing it.")
            }
            if c.str("dp27", "none") == "none", !c.value("holders").array.isEmpty {
                add("dividend", recommends: p3 > 0 && c.cash > p3, reason: p3 > 0 ? "It made money over three months." : "There is no profit to pay out.")
            }
            if let mid = c.managerID, let n = s.people[mid], c.int("ceoBlk") <= s.week {
                add("ceo", manager: n.name, recommends: p3 < 0, reason: p3 < 0 ? "It lost money over three months." : "It made money over three months. Give them time.")
            }
        }
        return out
    }

    public static func meetingDecisions(_ s: GameState, key: String, data: GameData) -> [BoardDecision] {
        boardDecisions(s, key: key, data: data) + putForward(s, key: key, data: data)
    }
}
