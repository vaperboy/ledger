import Foundation
import GameCore
import Countries
import Employees
import Finance

/// Boards: one per chain, or per company that has co-owners. Seats (chair, directors, CFO, secretary; specialists invited when relevant),
/// meetings with points to decide, emergency meetings, votes by shares, and your right hand on every board.
/// Originals: features/company/shelf_stock_chains_boards.js (boards, meetings, emergencies, `voteOn`), features/company/chain_registration_and_boards.js
/// (seats, `votersX`, owner votes), features/company/shareholders_and_board.js (directors elected by the owners, the board questions a CEO).
/// A board is saved on its company or chain as `brd` {seats[], mode, freq, last, mts[], cands[], candR}.
extension ManagerModel {
    // MARK: Seats

    public struct SeatRole: Identifiable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var permanent: Bool
        public var stat: String
        public var maxSeats: Int
        public var baseFee: Double
        public var text: String
    }
    /// Original: `ROLE13`.
    public static let seatRoles: [SeatRole] = [
        SeatRole(id: "chair", title: "Board chair", permanent: true, stat: "people", maxSeats: 1, baseFee: 14000, text: "Runs the meetings and keeps the board on the numbers"),
        SeatRole(id: "director", title: "Director", permanent: true, stat: "ops", maxSeats: 4, baseFee: 9000, text: "Independent view; weighs every big decision"),
        SeatRole(id: "cfo", title: "CFO", permanent: true, stat: "fin", maxSeats: 1, baseFee: 32000, text: "Cash, debt and profit; first to speak on money"),
        SeatRole(id: "sec", title: "Board secretary", permanent: true, stat: "ops", maxSeats: 1, baseFee: 6000, text: "Minutes, follow-ups and reminders"),
        SeatRole(id: "mkt", title: "Marketing manager", permanent: false, stat: "sales", maxSeats: 1, baseFee: 22000, text: "Brand and campaigns; marketing works about 5% better"),
        SeatRole(id: "hr", title: "HR manager", permanent: false, stat: "people", maxSeats: 1, baseFee: 20000, text: "Hiring and morale; fewer people quit"),
        SeatRole(id: "legal", title: "Legal adviser", permanent: false, stat: "risk", maxSeats: 1, baseFee: 16000, text: "Contracts, permits and disputes; fines about 10% lower"),
        SeatRole(id: "analyst", title: "Data analyst", permanent: false, stat: "fin", maxSeats: 1, baseFee: 18000, text: "Numbers behind prices, stock and demand"),
        SeatRole(id: "consult", title: "External consultant", permanent: false, stat: "ops", maxSeats: 1, baseFee: 26000, text: "Outside eyes on what is not working"),
    ]
    static let maxBoard = 7
    static let adviserBackgrounds = ["former director", "ex-banker", "sits on two other boards", "built and sold a company", "twenty years in the trade", "former partner at a big firm"]
    static let oldSeatTypes = ["fin": "cfo", "law": "legal", "ind": "consult", "mkt": "mkt", "chair": "chair"]

    /// The company whose board a branch sits on: its `branch.of` parent (and that company's parent, a few hops up) while the parent is live, set up,
    /// in the same country and under the same holding. A chain store, or a branch that left those terms, keeps its own board.
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
    /// Live companies that share `root`'s board as branches.
    static func boardBranches(_ s: GameState, root: Company) -> [Company] {
        s.companies.filter { $0.status.isLive && $0.id != root.id && boardParent(s, $0)?.id == root.id }
    }
    public static func boardKey(_ s: GameState, _ co: Company) -> String {
        let root = boardParent(s, co) ?? co
        return Chains.chain(s, of: root) != nil ? "ch:\(root.value("chain").int)" : "co:\(root.id)"
    }
    static func isChainKey(_ k: String) -> Bool { k.hasPrefix("ch:") }
    static func keyID(_ k: String) -> Int { Int(k.dropFirst(3)) ?? 0 }
    static func emptyBoard() -> JSONValue { .object(["seats": .array([]), "mode": "needed", "freq": 4, "last": -99, "mts": .array([]), "cands": .array([])]) }

    public static func board(_ s: GameState, key: String) -> JSONValue {
        let b: JSONValue = isChainKey(key) ? (Chains.chain(s, id: keyID(key))?["brd"] ?? .null) : (s.company(keyID(key))?.value("brd") ?? .null)
        return b.isNull ? emptyBoard() : b
    }
    static func writeBoard(_ s: inout GameState, key: String, _ b: JSONValue) {
        if isChainKey(key) { if var ch = Chains.chain(s, id: keyID(key)) { ch["brd"] = b; Chains.save(&s, ch) } }
        else if let i = s.companyIndex(keyID(key)) { s.companies[i].set("brd", b) }
    }
    /// Every board that can meet: each chain with stores, and each other company that is set up. Original: `V.boards12`.
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
    /// A board exists once a chain is registered, or somebody else owns part of a company. Original: `active`.
    public static func boardActive(_ s: GameState, key: String) -> Bool { isChainKey(key) ? Chains.chain(s, id: keyID(key)) != nil : !holders(s, key: key).isEmpty }
    static func seatRoleID(_ x: JSONValue) -> String? { x["r"].isNull ? oldSeatTypes[x["type"].string] : x["r"].string }
    /// Seats in use; entries without a role (left by older saves) hold no seat.
    static func heldSeatCount(_ L: [JSONValue]) -> Int { L.filter { seatRoleID($0) != nil }.count }

    public struct Seat: Identifiable, Equatable, Sendable {
        public var id: Int
        public var role: String
        public var title: String
        public var monthlyFee: Double
        public var adviceTaken: Int
        public var adviceRefused: Int
        public var mood: Double
        public var isAdviser: Bool
        public var isOwner: Bool
        /// "adv" (outside adviser or director), "own" (your own staff, they keep their job) or "exec".
        public var kind: String = "adv"
    }
    /// Seats that still have a person in them. Original: `seatsOf`.
    public static func seats(_ s: GameState, key: String) -> [Seat] {
        board(s, key: key)["seats"].array.compactMap { x in
            guard let n = s.people[x["id"].int], let r = seatRoleID(x) else { return nil }
            let ok = x["kind"].string == "adv" ? n.employerID == -4 : [-1, -2, -3].contains(n.employerID) || n.employerID > 0
            guard ok else { return nil }
            return Seat(id: n.id, role: r, title: x["t"].string.isEmpty ? (seatRoles.first { $0.id == r }?.title ?? r) : x["t"].string, monthlyFee: x["fee"].double,
                        adviceTaken: x["ok"].int, adviceRefused: x["no"].int, mood: x["mood"].isNull ? 60 : x["mood"].double, isAdviser: x["kind"].string == "adv", isOwner: x["owner"].bool, kind: x["kind"].string.isEmpty ? "adv" : x["kind"].string)
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
        var x: [String: JSONValue] = ["w0": .number(Double(s.week)), "fee": 0, "ok": 0, "no": 0, "mood": 60]
        for (k, v) in seat { x[k] = v }
        L.append(.object(x)); b["seats"] = .array(L)
        writeBoard(&s, key: key, b)
        return true
    }
    /// Take a person off every board. Original: `ACT.bd12rm`.
    static func removeSeat(_ s: inout GameState, personID: Int) {
        for key in boardKeys(s) {
            var b = board(s, key: key)
            let L = b["seats"].array
            if L.contains(where: { $0["id"].int == personID }) { b["seats"] = .array(L.filter { $0["id"].int != personID }); writeBoard(&s, key: key, b) }
        }
    }

    // MARK: Settings

    public static func setBoardMode(_ s: inout GameState, key: String, regular: Bool? = nil, quarterly: Bool? = nil) {
        var b = board(s, key: key)
        if let r = regular { b["mode"] = .string(r ? "regular" : "needed") }
        if let q = quarterly { b["freq"] = .number(q ? 13 : 4) }
        writeBoard(&s, key: key, b)
    }

    // MARK: Hiring advisers and officers

    /// Pay for a search and meet three candidates for a seat. Original: `ACT.bd13find`.
    public static func searchForSeat(_ s: inout GameState, key: String, role: String, data: GameData) -> [Person]? {
        guard let R = seatRoles.first(where: { $0.id == role }) else { return nil }
        let cur = playerCurrency(s, data)
        let cost = cur.scaledPrice(8000)
        guard Payments.liquid(s) >= cost, !boardCompanies(s, key: key).isEmpty else { return nil }
        Payments.playerPays(&s, cost, label: "Search: \(R.title)")
        var b = board(s, key: key)
        let cands: [Person] = (0..<3).map { _ in
            var n = generateCandidate(company: nil, type: "gen", state: &s, data: data)
            n.set("adv13", role); n.set("advBg", s.random.pick(adviserBackgrounds))
            n.set("fee13", cur.roundedStep(cur.scaledPrice(R.baseFee * (0.7 + n.value("stats")[R.stat].double / 150)), about: 500))
            s.people[n.id] = n
            return n
        }
        b["cands"] = .array(cands.map { .number(Double($0.id)) }); b["candR"] = .string(role)
        writeBoard(&s, key: key, b)
        return cands
    }

    public enum SeatResult: Equatable, Sendable { case ok, full, refused, votedDown(Int), taken, bad }

    /// Offer a fee for a seat. A director needs more than half of the shares behind them. Original: `ACT.bd13hire` and the election step.
    public static func fillSeat(_ s: inout GameState, key: String, personID: Int, monthlyFee fee: Double) -> SeatResult {
        var b = board(s, key: key)
        guard var n = s.people[personID], !boardCompanies(s, key: key).isEmpty else { return .bad }
        if n.employerID != 0 { return .taken }
        let role = n.str("adv13").isEmpty ? b["candR"].string : n.str("adv13")
        guard let R = seatRoles.first(where: { $0.id == role }) else { return .bad }
        if seats(s, key: key).filter({ $0.role == role }).count >= R.maxSeats { return .full }
        let want = n.num("fee13")
        func drop() { b["cands"] = .array(b["cands"].array.filter { $0.int != personID }); writeBoard(&s, key: key, b) }
        if !(fee >= want || (fee >= want * 0.9 && s.random.chance(0.5))) { drop(); return .refused }
        let H = holders(s, key: key)
        if role == "director" && !H.isEmpty, let co0 = boardCompanies(s, key: key).first {
            let q = leadership(n)
            var yes = HoldingStakes.votingPercent(co0)
            for x in H where HashedRandom.first("el15:\(x.h["name"].string):\(personID)") < 0.25 + q * 0.8 { yes += x.h["pct"].double }
            if yes <= 50 { drop(); return .votedDown(Int(jsRound(yes))) }
        }
        n.employerID = -4
        s.people[personID] = n
        b = board(s, key: key)
        b["cands"] = .array([])
        writeBoard(&s, key: key, b)
        addSeat(&s, boardKey: key, seat: ["id": .number(Double(personID)), "kind": "adv", "r": .string(role), "t": .string(R.title), "fee": .number(fee)])
        s.note("\(n.name) is now \(R.title.lowercased()) of \(boardName(s, key: key)).", tone: "good")
        return .ok
    }

    /// Let an adviser go. Original: `ACT.bd12rm`.
    public static func removeFromBoard(_ s: inout GameState, key: String, personID: Int) {
        if var n = s.people[personID], n.employerID == -4 { n.employerID = 0; s.people[personID] = n }
        var b = board(s, key: key)
        b["seats"] = .array(b["seats"].array.filter { $0["id"].int != personID })
        writeBoard(&s, key: key, b)
    }

    // MARK: Who sits at the table and who votes

    public struct Voter: Identifiable, Equatable, Sendable {
        public var id: String
        public var personID: Int?
        public var name: String
        public var title: String
        public var type: String        // lh, chair, director, cfo, ..., ceo, regional, owner
        public var votes: Bool
        public var percent: Double
    }
    /// Owners and seated directors vote; the CEO, regional and store managers attend and advise but never vote unless explicitly seated. Original: `votersX`.
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
        for (i, x) in holders(s, key: key).enumerated() { L.append(Voter(id: "h\(i)", personID: nil, name: x.h["name"].string, title: "Co-owner · \(Int(jsRound(x.h["pct"].double)))%", type: "owner", votes: true, percent: x.h["pct"].double)) }
        return L
    }

    // MARK: Votes on big moves

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
        /// Outside owners hold directorships, so the directors (you included) decide on the CEO, not the owner alone.
        public var directorsDecide: Bool = false
        public var directorsYes: Int = 0
        public var directorsTotal: Int = 0
        public var directors: [VoteLine] = []
    }
    /// How the directors vote on a CEO matter when outside shareholders hold board seats. Original: `voteOn` run over the board.
    public struct DirectorsDecision: Equatable, Sendable {
        public var decide: Bool
        public var yes: Int
        public var total: Int
        public var lines: [VoteLine]
        /// More than half of the directors, you included.
        public var passes: Bool { yes * 2 > total }
        public var percentYes: Int { total == 0 ? 0 : Int(jsRound(Double(yes) * 100 / Double(total))) }
    }
    /// The board decides on dismissing the CEO (or on `appointing` a person as CEO) when outside shareholders sit as directors and you hold the
    /// vote: you and each seated director get one vote. When outsiders hold control, or none of them has a seat, the shares decide as before.
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
    /// A co-owner's view of replacing the CEO, by what they want from the company, and what they say about it.
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
    /// What the board and the owners say to a sale (`sell`), a closing (`close`) or a big loan (`loan`). More than half of the shares wins.
    /// Original: `voteOn` and `voteSheetX`.
    public static func boardVote(_ s: GameState, kind: String, companyID: Int, amount: Double = 0, advisory: Bool = false) -> BoardVote {
        let none = BoardVote(advice: [], board: [], owners: [], percentYes: 100, passes: true, decidingOwner: nil, pushedThroughAlone: false, active: false)
        guard let co = s.company(companyID) else { return none }
        let key = boardKey(s, co)
        // A sole owner has no binding board; `advisory` still asks the managers, and the owner decides alone.
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
            default: let ratio = (debt + amount) / yp; yes = ratio < 3; why = yes ? "Debt stays at \(String(format: "%.1f", ratio)) years of profit." : "Debt would be \(Int(ratio)) times a year of profit."
            }
            let q = leadership(v.personID.flatMap { s.people[$0] })
            if HashedRandom.first("vo13:\(v.id):\(kind):\(s.week)") < 0.12 * (1 - q) { yes.toggle(); why = yes ? "The risk is worth taking." : "Too early to decide." }
            return VoteLine(id: v.id, name: v.name, title: v.title, yes: yes, reason: why, percent: v.percent, isYou: false)
        }
        // The CEO does not vote on their own removal. In advisory mode the department heads speak too.
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
        // A holding of yours with a seat (or control) votes with you.
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

    // MARK: Replacing the CEO

    public enum CEOChange: Equatable, Sendable {
        case dismissed
        case voteFailed(percentYes: Int)
        case blocked(weeks: Int)
        case refused(String)
    }
    /// Propose replacing the manager (CEO) of a company. A sole owner, or an owner with more than half of the shares, decides alone, unless outside
    /// shareholders sit as directors: then the directors vote (`ceoDirectors`). With
    /// co-owners it is a vote by shares: they weigh the results against what they want from the company. A failed vote shakes the CEO's
    /// trust in you and the co-owners who backed them, and the proposal cannot be made again for eight weeks.
    public static func proposeCEOChange(_ s: inout GameState, companyID: Int, data: GameData) -> CEOChange {
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
        if vote.active && !vote.passes {
            s.companies[ci].set("ceoBlk", s.week + 8)
            s.companies[ci].set("mood", max(0, mood(s.companies[ci]) - 8))
            moveHolders(no, 3)
            s.note("\(vote.directorsDecide ? "The board" : "The co-owners") of \(co.name) voted against replacing the CEO. The CEO knows you tried.", tone: "n", companyID: companyID)
            return .voteFailed(percentYes: vote.directorsDecide ? DirectorsDecision(decide: true, yes: vote.directorsYes, total: vote.directorsTotal, lines: []).percentYes : Int(jsRound(vote.percentYes)))
        }
        dismissForBoard(&s, companyID: companyID, data: data)
        if vote.active {
            if vote.pushedThroughAlone { recordPushedThrough(&s, companyID: companyID) }
            else { moveHolders(yes, 4); moveHolders(no, -3) }
        }
        return .dismissed
    }
    /// You go ahead against everyone else: the owners and the board lose some morale. Original: `ui.b13cont`.
    public static func recordPushedThrough(_ s: inout GameState, companyID: Int) {
        guard let i = s.companyIndex(companyID) else { return }
        var H = s.companies[i].value("holders").array
        for k in H.indices { H[k]["mood"] = .number(max(0, (H[k]["mood"].isNull ? 60 : H[k]["mood"].double) - 8)) }
        s.companies[i].set("holders", .array(H))
        let key = boardKey(s, s.companies[i])
        var b = board(s, key: key)
        var L = b["seats"].array
        for k in L.indices { L[k]["mood"] = .number(max(0, (L[k]["mood"].isNull ? 60 : L[k]["mood"].double) - 4)) }
        b["seats"] = .array(L)
        writeBoard(&s, key: key, b)
        s.note("Pushed through against the others at \(s.companies[i].name). They are not happy.", tone: "bad", companyID: companyID)
    }
}
