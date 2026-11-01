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

    public static func boardKey(_ s: GameState, _ co: Company) -> String { Chains.chain(s, of: co) != nil ? "ch:\(co.value("chain").int)" : "co:\(co.id)" }
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
            + s.companies.filter { $0.status.isLive && $0.status != .setup && $0.type != "hold" && $0.value("chain").isNull }.map { "co:\($0.id)" }
    }
    public static func boardCompanies(_ s: GameState, key: String) -> [Company] {
        if isChainKey(key) { return Chains.chain(s, id: keyID(key)).map { Chains.stores(s, $0) } ?? [] }
        return s.company(keyID(key)).map { $0.status.isLive ? [$0] : [] } ?? []
    }
    public static func boardName(_ s: GameState, key: String) -> String {
        isChainKey(key) ? Chains.chain(s, id: keyID(key))?["name"].string ?? "Chain" : s.company(keyID(key))?.name ?? "Company"
    }
    static func holders(_ s: GameState, key: String) -> [(h: JSONValue, co: Company)] {
        boardCompanies(s, key: key).flatMap { c in c.value("holders").array.filter { $0["pct"].double > 0 }.map { ($0, c) } }
    }
    /// A board exists once a chain is registered, or somebody else owns part of a company. Original: `active`.
    public static func boardActive(_ s: GameState, key: String) -> Bool { isChainKey(key) ? Chains.chain(s, id: keyID(key)) != nil : !holders(s, key: key).isEmpty }
    static func seatRoleID(_ x: JSONValue) -> String? { x["r"].isNull ? oldSeatTypes[x["type"].string] : x["r"].string }

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
    }
    /// Seats that still have a person in them. Original: `seatsOf`.
    public static func seats(_ s: GameState, key: String) -> [Seat] {
        board(s, key: key)["seats"].array.compactMap { x in
            guard let n = s.people[x["id"].int], let r = seatRoleID(x) else { return nil }
            let ok = x["kind"].string == "adv" ? n.employerID == -4 : [-1, -2, -3].contains(n.employerID) || n.employerID > 0
            guard ok else { return nil }
            return Seat(id: n.id, role: r, title: x["t"].string.isEmpty ? (seatRoles.first { $0.id == r }?.title ?? r) : x["t"].string, monthlyFee: x["fee"].double,
                        adviceTaken: x["ok"].int, adviceRefused: x["no"].int, mood: x["mood"].isNull ? 60 : x["mood"].double, isAdviser: x["kind"].string == "adv", isOwner: x["owner"].bool)
        }
    }
    public static func boardHas(_ s: GameState, _ co: Company, role: String) -> Bool { seats(s, key: boardKey(s, co)).contains { $0.role == role } }

    @discardableResult
    static func addSeat(_ s: inout GameState, boardKey key: String, seat: [String: JSONValue]) -> Bool {
        var b = board(s, key: key)
        var L = b["seats"].array
        let id = seat["id"]?.int ?? 0
        if L.contains(where: { $0["id"].int == id }) { return true }
        if L.count + 2 >= maxBoard { return false }
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
            var yes = co0.ownership
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
    /// Owners and the CEO vote, chiefs vote, advisers advise. Original: `votersX`.
    public static func voters(_ s: GameState, key: String) -> [Voter] {
        var L: [Voter] = []
        if let lh = Headquarters.rightHand(s), let n = s.people[lh.personID] { L.append(Voter(id: "p\(n.id)", personID: n.id, name: n.name, title: "Your right hand", type: "lh", votes: false, percent: 0)) }
        for x in seats(s, key: key) { if let n = s.people[x.id] { L.append(Voter(id: "p\(n.id)", personID: n.id, name: n.name, title: x.title, type: x.role, votes: x.role == "director", percent: 0)) } }
        let cos = boardCompanies(s, key: key)
        if let gc = s.rest["group"]?["ceo"], let n = person(s, gc) { L.append(Voter(id: "p\(n.id)", personID: n.id, name: n.name, title: "CEO", type: "ceo", votes: true, percent: 0)) }
        else if let c = cos.first(where: { $0.managerID != nil && s.people[$0.managerID!] != nil }), let n = s.people[c.managerID!] { L.append(Voter(id: "p\(n.id)", personID: n.id, name: n.name, title: "CEO", type: "ceo", votes: true, percent: 0)) }
        var seen = Set<Int>()
        for c in cos { if let r = regionals(s).first(where: { $0["id"].int == c.value("region").int && !c.value("region").isNull }), let n = person(s, r), seen.insert(n.id).inserted {
            L.append(Voter(id: "p\(n.id)", personID: n.id, name: n.name, title: "Regional manager", type: "regional", votes: true, percent: 0)) } }
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
    }
    static func ownerVote(_ s: GameState, kind: String, co: Company, holder h: JSONValue) -> Bool {
        let p3 = co.monthlyHistory.suffix(3).reduce(0) { $0 + $1.profit }
        let base = kind == "sell" || kind == "close" ? p3 < 0 : p3 > 0
        return HashedRandom.first("ov13:\(h["name"].string):\(kind):\(s.week)") < 0.85 ? base : !base
    }
    /// What the board and the owners say to a sale (`sell`), a closing (`close`) or a big loan (`loan`). More than half of the shares wins.
    /// Original: `voteOn` and `voteSheetX`.
    public static func boardVote(_ s: GameState, kind: String, companyID: Int, amount: Double = 0) -> BoardVote {
        guard let co = s.company(companyID) else { return BoardVote(advice: [], board: [], owners: [], percentYes: 100, passes: true, decidingOwner: nil, pushedThroughAlone: false, active: false) }
        let key = boardKey(s, co)
        guard boardActive(s, key: key) else { return BoardVote(advice: [], board: [], owners: [], percentYes: 100, passes: true, decidingOwner: nil, pushedThroughAlone: false, active: false) }
        let hist = co.monthlyHistory
        let h3 = hist.suffix(3), p3 = h3.reduce(0) { $0 + $1.profit }, r3 = h3.reduce(0) { $0 + $1.revenue }
        let yp = max(1, hist.suffix(12).reduce(0) { $0 + $1.profit })
        let debt = s.loans.filter { $0.companyID == companyID }.reduce(0) { $0 + $1.balance }
        func line(_ v: Voter) -> VoteLine {
            var yes: Bool, why: String
            switch kind {
            case "sell": yes = p3 < 0 || (r3 > 0 && p3 / r3 < 0.02); why = yes ? (p3 < 0 ? "It lost money over three months." : "It barely makes money.") : "It made money over three months. Keep it."
            case "close": yes = p3 < 0; why = yes ? "Losses over three months." : "It is profitable. Sell it rather than close it."
            default: let ratio = (debt + amount) / yp; yes = ratio < 3; why = yes ? "Debt stays at \(String(format: "%.1f", ratio)) years of profit." : "Debt would be \(Int(ratio)) times a year of profit."
            }
            let q = leadership(v.personID.flatMap { s.people[$0] })
            if HashedRandom.first("vo13:\(v.id):\(kind):\(s.week)") < 0.12 * (1 - q) { yes.toggle(); why = yes ? "The risk is worth taking." : "Too early to decide." }
            return VoteLine(id: v.id, name: v.name, title: v.title, yes: yes, reason: why, percent: v.percent, isYou: false)
        }
        let all = voters(s, key: key).filter { $0.type != "owner" }.map(line)
        let advice = all.filter { l in voters(s, key: key).first { $0.id == l.id }?.votes == false }
        let board = all.filter { l in voters(s, key: key).first { $0.id == l.id }?.votes == true }
        var owners = [VoteLine(id: "you", name: "\(s.player.name) (you)", title: "Owner", yes: true, reason: "", percent: co.ownership, isYou: true)]
        for x in holders(s, key: key) where x.co.id == co.id {
            owners.append(VoteLine(id: x.h["name"].string, name: x.h["name"].string, title: "Co-owner", yes: ownerVote(s, kind: kind, co: co, holder: x.h), reason: "", percent: x.h["pct"].double, isYou: false))
        }
        let yesPct = owners.filter { $0.yes }.reduce(0) { $0 + $1.percent }
        let big = owners.first { $0.percent >= 51 }
        let pass = big.map { $0.yes } ?? (yesPct > 50)
        let lonely = pass && owners.count > 1 && owners.filter { !$0.isYou }.allSatisfy { !$0.yes }
        return BoardVote(advice: advice, board: board, owners: owners, percentYes: yesPct, passes: pass, decidingOwner: big?.name, pushedThroughAlone: lonely, active: true)
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
