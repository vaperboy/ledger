import Foundation
import GameCore
import Countries
import Employees
import Finance

extension ManagerModel {

    static let maxBoard = 7

    public static func boardParent(_ s: GameState, _ co: Company) -> Company? {
        func parent(_ c: Company) -> Company? {
            let b = c.value("branch")
            guard c.value("chain").isNull, !b.isNull, !b["of"].isNull, b["of"].int != c.id, let p = s.company(b["of"].int),
                  p.status.isLive, p.status != .setup, p.type != "hold", p.countryCode == c.countryCode, p.holdingID == c.holdingID else { return nil }
            return p
        }
        var cur = co, hops = 0
        while hops < 4, let p = parent(cur) { cur = p; hops += 1 }
        return cur.id == co.id ? nil : cur
    }
    static func boardBranches(_ s: GameState, root: Company) -> [Company] {
        s.companies.filter { $0.status.isLive && $0.id != root.id && boardParent(s, $0)?.id == root.id }
    }
    public static func boardKey(_ s: GameState, _ co: Company) -> String {
        let root = boardParent(s, co) ?? co
        return Chains.chain(s, of: root) != nil ? "ch:\(root.value("chain").int)" : "co:\(root.id)"
    }
    static func isChainKey(_ k: String) -> Bool { k.hasPrefix("ch:") }
    static func keyID(_ k: String) -> Int { Int(k.dropFirst(3)) ?? 0 }
    static func emptyBoard() -> JSONValue { .object(["seats": .array([]), "last": -99, "mts": .array([])]) }

    public static func board(_ s: GameState, key: String) -> JSONValue {
        let b: JSONValue = isChainKey(key) ? (Chains.chain(s, id: keyID(key))?["brd"] ?? .null) : (s.company(keyID(key))?.value("brd") ?? .null)
        return b.isNull ? emptyBoard() : b
    }
    static func writeBoard(_ s: inout GameState, key: String, _ b: JSONValue) {
        if isChainKey(key) { if var ch = Chains.chain(s, id: keyID(key)) { ch["brd"] = b; Chains.save(&s, ch) } }
        else if let i = s.companyIndex(keyID(key)) { s.companies[i].set("brd", b) }
    }
    public static func boardKeys(_ s: GameState) -> [String] {
        Chains.list(s).filter { !Chains.stores(s, $0).isEmpty }.map { "ch:\($0["id"].int)" }
            + s.companies.filter { $0.status.isLive && $0.status != .setup && $0.type != "hold" && $0.value("chain").isNull && boardParent(s, $0) == nil }.map { "co:\($0.id)" }
    }
    public static func boardCompanies(_ s: GameState, key: String) -> [Company] {
        if isChainKey(key) {
            let stores = Chains.chain(s, id: keyID(key)).map { Chains.stores(s, $0) } ?? []
            let ids = Set(stores.map { $0.id })
            return stores + stores.flatMap { boardBranches(s, root: $0) }.filter { !ids.contains($0.id) }
        }
        return s.company(keyID(key)).map { $0.status.isLive ? [$0] + boardBranches(s, root: $0) : [] } ?? []
    }
    public static func boardName(_ s: GameState, key: String) -> String {
        isChainKey(key) ? Chains.chain(s, id: keyID(key))?["name"].string ?? "Chain" : s.company(keyID(key))?.name ?? "Company"
    }
    static func holders(_ s: GameState, key: String) -> [(h: JSONValue, co: Company)] {
        boardCompanies(s, key: key).flatMap { c in c.value("holders").array.filter { $0["pct"].double > 0 && $0["hid"].int == 0 }.map { ($0, c) } }
    }
    public static func boardActive(_ s: GameState, key: String) -> Bool { isChainKey(key) ? Chains.chain(s, id: keyID(key)) != nil : !holders(s, key: key).isEmpty }
    static func seatRoleID(_ x: JSONValue) -> String? { x["r"].isNull ? nil : x["r"].string }
    static func heldSeatCount(_ L: [JSONValue]) -> Int { L.filter { seatRoleID($0) != nil }.count }

    public struct Seat: Identifiable, Equatable, Sendable {
        public var id: Int
        public var role: String
        public var title: String
        public var isAdviser: Bool
        public var isOwner: Bool
        public var kind: String = "adv"
    }
    public static func seats(_ s: GameState, key: String) -> [Seat] {
        board(s, key: key)["seats"].array.compactMap { x in
            guard let n = s.people[x["id"].int], let r = seatRoleID(x) else { return nil }
            let ok = x["kind"].string == "adv" ? n.employerID == -4 : [-1, -2, -3].contains(n.employerID) || n.employerID > 0
            guard ok else { return nil }
            return Seat(id: n.id, role: r, title: x["t"].string.isEmpty ? r.capitalized : x["t"].string, isAdviser: x["kind"].string == "adv", isOwner: x["owner"].bool,
                        kind: x["kind"].string.isEmpty ? "adv" : x["kind"].string)
        }
    }
    public static func boardHas(_ s: GameState, _ co: Company, role: String) -> Bool { seats(s, key: boardKey(s, co)).contains { $0.role == role } }

    @discardableResult
    static func addSeat(_ s: inout GameState, boardKey key: String, seat: [String: JSONValue]) -> Bool {
        var b = board(s, key: key)
        var L = b["seats"].array
        let id = seat["id"]?.int ?? 0
        if L.contains(where: { $0["id"].int == id }) { return true }
        if heldSeatCount(L) + 2 >= maxBoard { return false }
        var x: [String: JSONValue] = ["w0": .number(Double(s.week))]
        for (k, v) in seat { x[k] = v }
        L.append(.object(x)); b["seats"] = .array(L)
        writeBoard(&s, key: key, b)
        return true
    }
    static func removeSeat(_ s: inout GameState, personID: Int) {
        for key in boardKeys(s) {
            var b = board(s, key: key)
            let L = b["seats"].array
            if L.contains(where: { $0["id"].int == personID }) { b["seats"] = .array(L.filter { $0["id"].int != personID }); writeBoard(&s, key: key, b) }
        }
    }

    public struct Voter: Identifiable, Equatable, Sendable {
        public var id: String
        public var personID: Int?
        public var name: String
        public var title: String
        public var type: String
        public var votes: Bool
        public var percent: Double
    }
    public static func voters(_ s: GameState, key: String) -> [Voter] {
        var L: [Voter] = []
        if let lh = Headquarters.rightHand(s), let n = s.people[lh.personID] { L.append(Voter(id: "p\(n.id)", personID: n.id, name: n.name, title: "Your right hand", type: "lh", votes: false, percent: 0)) }
        for x in seats(s, key: key) { if let n = s.people[x.id] { L.append(Voter(id: "p\(n.id)", personID: n.id, name: n.name, title: x.title, type: x.role, votes: x.role == "director", percent: 0)) } }
        let cos = boardCompanies(s, key: key)
        if let gc = s.rest["group"]?["ceo"], let n = person(s, gc) { L.append(Voter(id: "p\(n.id)", personID: n.id, name: n.name, title: "CEO", type: "ceo", votes: false, percent: 0)) }
        else if let c = cos.first(where: { $0.managerID != nil && s.people[$0.managerID!] != nil }), let n = s.people[c.managerID!] { L.append(Voter(id: "p\(n.id)", personID: n.id, name: n.name, title: "CEO", type: "ceo", votes: false, percent: 0)) }
        var seen = Set<Int>()
        for c in cos { if let r = regionals(s).first(where: { $0["id"].int == c.value("region").int && !c.value("region").isNull }), let n = person(s, r), seen.insert(n.id).inserted {
            L.append(Voter(id: "p\(n.id)", personID: n.id, name: n.name, title: "Regional manager", type: "regional", votes: false, percent: 0)) } }
        for (i, x) in holders(s, key: key).enumerated() { L.append(Voter(id: "h\(i)", personID: nil, name: x.h["name"].string, title: "Co-owner · \(Int(saturating: jsRound(x.h["pct"].double)))%", type: "owner", votes: true, percent: x.h["pct"].double)) }
        return L
    }

    public struct VoteLine: Identifiable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var title: String
        public var yes: Bool
        public var reason: String
        public var percent: Double
        public var isYou: Bool
    }
    public struct BoardVote: Equatable, Sendable {
        public var advice: [VoteLine]
        public var board: [VoteLine]
        public var owners: [VoteLine]
        public var percentYes: Double
        public var passes: Bool
        public var decidingOwner: String?
        public var pushedThroughAlone: Bool
        public var active: Bool
        public var directorsDecide: Bool = false
        public var directorsYes: Int = 0
        public var directorsTotal: Int = 0
        public var directors: [VoteLine] = []
    }
    public struct DirectorsDecision: Equatable, Sendable {
        public var decide: Bool
        public var yes: Int
        public var total: Int
        public var lines: [VoteLine]
        public var passes: Bool { yes * 2 > total }
        public var percentYes: Int { total == 0 ? 0 : Int(saturating: jsRound(Double(yes) * 100 / Double(total))) }
    }
    public static func ceoDirectors(_ s: GameState, companyID: Int, appointing personID: Int? = nil) -> DirectorsDecision {
        let none = DirectorsDecision(decide: false, yes: 0, total: 0, lines: [])
        guard let co = s.company(companyID) else { return none }
        let key = boardKey(s, co)
        guard boardActive(s, key: key), HoldingStakes.votingPercent(co) > HoldingStakes.controlAbove else { return none }
        let dirs = seats(s, key: key).filter { $0.role == "director" }
        guard dirs.contains(where: { $0.isOwner }) else { return none }
        let p3 = co.monthlyHistory.suffix(3).reduce(0) { $0 + $1.profit }
        var lines = [VoteLine(id: "you", name: "\(s.player.name) (you)", title: "Owner", yes: true, reason: "", percent: co.ownership, isYou: true)]
        for d in dirs {
            let n = s.people[d.id]
            var yes: Bool, why: String
            let holder = holders(s, key: key).first { $0.co.id == co.id && ($0.h["npc"].int == d.id || $0.h["name"].string == (n?.name ?? "")) }
            if let personID = personID {
                yes = leadership(s.people[personID]) >= 0.45
                why = yes ? "A capable choice." : "Not the leader this company needs."
            } else if let h = holder?.h {
                yes = ownerVote(s, kind: "ceo", co: co, holder: h); why = ceoOpinion(co, holder: h).why
            } else {
                yes = p3 < 0; why = yes ? "It lost money over three months. A new leader may turn it." : "It made money over three months. Give them time."
            }
            if holder == nil, HashedRandom.first("dv13:\(d.id):\(companyID):\(s.week)") < 0.12 * (1 - leadership(n)) { yes.toggle(); why = yes ? "The risk is worth taking." : "Too early to decide." }
            lines.append(VoteLine(id: "p\(d.id)", name: n?.name ?? "Director", title: d.title, yes: yes, reason: why, percent: 0, isYou: false))
        }
        return DirectorsDecision(decide: true, yes: lines.filter { $0.yes }.count, total: lines.count, lines: lines)
    }
    static func ceoOpinion(_ co: Company, holder h: JSONValue) -> (yes: Bool, why: String) {
        let hist = co.monthlyHistory
        let p3 = hist.suffix(3).reduce(0) { $0 + $1.profit }
        let r3 = hist.suffix(3).reduce(0) { $0 + $1.revenue }
        let rPrev = hist.count >= 6 ? hist.dropLast(3).suffix(3).reduce(0) { $0 + $1.revenue } : r3
        let falling = r3 < rPrev * 0.97
        switch h["k27"].string {
        case "div": return p3 <= 0 ? (true, "No profit, no dividend. Time for someone else.") : (false, "It pays. I want the dividends to keep coming.")
        case "growth": return falling || p3 < 0 ? (true, "We are not growing. I want a leader who is.") : (false, "Sales are growing. Do not break it.")
        case "exit": return p3 < 0 ? (true, "A weak result hurts the price I get. Replace them.") : (false, "Leave it alone until I sell.")
        default: return p3 < 0 && hist.suffix(3).allSatisfy({ $0.profit < 0 }) ? (true, "Three losing months. I do not like it, but it has to change.") : (false, "I do not like change. Give them time.")
        }
    }
    static func ownerVote(_ s: GameState, kind: String, co: Company, holder h: JSONValue) -> Bool {
        if kind == "ceo" {
            let base = ceoOpinion(co, holder: h).yes
            return HashedRandom.first("ov13:\(h["name"].string):\(kind):\(s.week)") < 0.9 ? base : !base
        }
        let p3 = co.monthlyHistory.suffix(3).reduce(0) { $0 + $1.profit }
        let base = kind == "sell" || kind == "close" ? p3 < 0 : p3 > 0
        return HashedRandom.first("ov13:\(h["name"].string):\(kind):\(s.week)") < 0.85 ? base : !base
    }
    public static func boardVote(_ s: GameState, kind: String, companyID: Int, amount: Double = 0, advisory: Bool = false) -> BoardVote {
        let none = BoardVote(advice: [], board: [], owners: [], percentYes: 100, passes: true, decidingOwner: nil, pushedThroughAlone: false, active: false)
        guard let co = s.company(companyID) else { return none }
        let key = boardKey(s, co)
        guard boardActive(s, key: key) || advisory else { return none }
        let active = boardActive(s, key: key)
        let hist = co.monthlyHistory
        let h3 = hist.suffix(3), p3 = h3.reduce(0) { $0 + $1.profit }, r3 = h3.reduce(0) { $0 + $1.revenue }
        let yp = max(1, hist.suffix(12).reduce(0) { $0 + $1.profit })
        let debt = s.loans.filter { $0.companyID == companyID }.reduce(0) { $0 + $1.balance }
        func line(_ v: Voter) -> VoteLine {
            var yes: Bool, why: String
            switch kind {
            case "sell": yes = p3 < 0 || (r3 > 0 && p3 / r3 < 0.02); why = yes ? (p3 < 0 ? "It lost money over three months." : "It barely makes money.") : "It made money over three months. Keep it."
            case "close": yes = p3 < 0; why = yes ? "Losses over three months." : "It is profitable. Sell it rather than close it."
            case "ceo": yes = p3 < 0; why = yes ? "It lost money over three months. A new leader may turn it." : "It made money over three months. Give them time."
            case "dividend": yes = p3 > 0; why = yes ? "It made money over three months. The owners should see some of it." : "There is no profit to pay out."
            case "open": yes = p3 >= 0; why = yes ? "The chain is making money. Another location can grow it." : "The chain lost money over three months. Fix that first."
            default: let ratio = (debt + amount) / yp; yes = ratio < 3; why = yes ? "Debt stays at \(String(format: "%.1f", ratio)) years of profit." : "Debt would be \(Int(ratio)) times a year of profit."
            }
            let q = leadership(v.personID.flatMap { s.people[$0] })
            if HashedRandom.first("vo13:\(v.id):\(kind):\(s.week)") < 0.12 * (1 - q) { yes.toggle(); why = yes ? "The risk is worth taking." : "Too early to decide." }
            return VoteLine(id: v.id, name: v.name, title: v.title, yes: yes, reason: why, percent: v.percent, isYou: false)
        }
        let ceoID = co.managerID
        var table = voters(s, key: key).filter { $0.type != "owner" && !(kind == "ceo" && $0.personID != nil && $0.personID == ceoID) }
        if !active {
            for c in OwnerMeetings.counterparts(s, companyID: companyID) where c.position != "ceo" && !table.contains(where: { $0.personID == c.id }) {
                table.append(Voter(id: "p\(c.id)", personID: c.id, name: c.name, title: c.title, type: c.position, votes: false, percent: 0))
            }
        }
        let all = table.map(line)
        let advice = all.filter { l in !active || table.first { $0.id == l.id }?.votes != true }
        let board = all.filter { l in active && table.first { $0.id == l.id }?.votes == true }
        var owners = [VoteLine(id: "you", name: "\(s.player.name) (you)", title: "Owner", yes: true, reason: "", percent: co.ownership, isYou: true)]
        for l in co.value("holders").array where l["hid"].int != 0 && l["pct"].double > 0 && (l["seat"].bool || l["pct"].double > HoldingStakes.controlAbove) {
            owners.append(VoteLine(id: l["name"].string, name: l["name"].string, title: "Your holding", yes: true, reason: "", percent: l["pct"].double, isYou: true))
        }
        for x in holders(s, key: key) where x.co.id == co.id {
            owners.append(VoteLine(id: x.h["name"].string, name: x.h["name"].string, title: "Co-owner", yes: ownerVote(s, kind: kind, co: co, holder: x.h),
                                   reason: kind == "ceo" ? ceoOpinion(co, holder: x.h).why : "", percent: x.h["pct"].double, isYou: false))
        }
        let yesPct = owners.filter { $0.yes }.reduce(0) { $0 + $1.percent }
        let big = owners.first { $0.percent >= 51 }
        let pass = big.map { $0.yes } ?? (yesPct > 50)
        let dd = kind == "ceo" ? ceoDirectors(s, companyID: companyID) : DirectorsDecision(decide: false, yes: 0, total: 0, lines: [])
        let lonely = !dd.decide && pass && owners.count > 1 && owners.filter { !$0.isYou }.allSatisfy { !$0.yes }
        return BoardVote(advice: advice, board: board, owners: owners, percentYes: yesPct, passes: dd.decide ? dd.passes : pass, decidingOwner: dd.decide ? nil : big?.name,
                         pushedThroughAlone: lonely, active: active, directorsDecide: dd.decide, directorsYes: dd.yes, directorsTotal: dd.total, directors: dd.lines)
    }

    public enum CEOChange: Equatable, Sendable {
        case dismissed
        case voteFailed(percentYes: Int)
        case blocked(weeks: Int)
        case refused(String)
    }
    public static func proposeCEOChange(_ s: inout GameState, companyID: Int, data: GameData, shareholdersMet: Bool = false) -> CEOChange {
        guard let ci = s.companyIndex(companyID), s.companies[ci].managerID != nil, s.companies[ci].status.isLive else { return .refused("There is nobody to replace.") }
        let co = s.companies[ci]
        if !co.value("ceoBlk").isNull, co.int("ceoBlk") > s.week { return .blocked(weeks: co.int("ceoBlk") - s.week) }
        let vote = boardVote(s, kind: "ceo", companyID: companyID, advisory: true)
        func moveHolders(_ names: Set<String>, _ delta: Double) {
            var list = s.companies[ci].value("holders").array
            for k in list.indices where names.contains(list[k]["name"].string) { list[k]["sat"] = .number(clamp((list[k]["sat"].isNull ? 60 : list[k]["sat"].double) + delta, 0, 100)) }
            s.companies[ci].set("holders", .array(list))
        }
        let yes = Set(vote.owners.filter { !$0.isYou && $0.yes }.map { $0.name }), no = Set(vote.owners.filter { !$0.isYou && !$0.yes }.map { $0.name })
        if vote.active && !vote.passes && !(shareholdersMet && !vote.directorsDecide) {
            s.companies[ci].set("ceoBlk", s.week + 8)
            s.companies[ci].set("mood", max(0, mood(s.companies[ci]) - 8))
            moveHolders(no, 3)
            s.note("\(vote.directorsDecide ? "The board" : "The co-owners") of \(co.name) voted against replacing the CEO. The CEO knows you tried.", tone: "n", companyID: companyID)
            return .voteFailed(percentYes: vote.directorsDecide ? DirectorsDecision(decide: true, yes: vote.directorsYes, total: vote.directorsTotal, lines: []).percentYes : Int(saturating: jsRound(vote.percentYes)))
        }
        dismissForBoard(&s, companyID: companyID, data: data)
        if vote.active {
            if vote.pushedThroughAlone { recordPushedThrough(&s, companyID: companyID) }
            else { moveHolders(yes, 4); moveHolders(no, -3) }
        }
        return .dismissed
    }
    public static func recordPushedThrough(_ s: inout GameState, companyID: Int) {
        guard let i = s.companyIndex(companyID) else { return }
        var H = s.companies[i].value("holders").array
        for k in H.indices { H[k]["mood"] = .number(max(0, (H[k]["mood"].isNull ? 60 : H[k]["mood"].double) - 8)) }
        s.companies[i].set("holders", .array(H))
        s.note("Pushed through against the others at \(s.companies[i].name). They are not happy.", tone: "bad", companyID: companyID)
    }
}
