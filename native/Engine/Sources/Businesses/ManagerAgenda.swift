import Foundation
import GameCore
import Countries
import Employees
import Finance

/// The board's one decision list. What the owner can be asked to decide is fixed: sell a company, close it, start a dividend, replace the CEO,
/// put in capital, and open or close a chain location. Each item appears when the numbers or a proposal call for it, with the recommendation of
/// the person who knows the company (its manager, the chain's CEO or chain manager, else the board). Approving first puts the move to the
/// shares through `boardVote` (a sole owner decides alone), then carries it out through the game's own systems; a refused item stays on the list with
/// the reason. A declined item is not raised again for a while. Saved on the board `brd`: `memo` {item: week until which it is not raised
/// again}, `locp[]` (location proposals, see `ChainLocations`), `fu[]` (follow-up jobs) and `mts[]` (emergency meetings, see `ManagerMeetings`).
extension ManagerModel {
    static let declinedQuietWeeks = 12, approvedQuietWeeks = 8, locationQuietWeeks = 26
    static let keptMeetings = 24, keptFollowUps = 20

    // MARK: Types

    public struct BoardDecision: Identifiable, Equatable, Sendable {
        public var id: String
        /// The board it belongs to (`boardKey`).
        public var key: String
        /// sell, close, dividend, ceo, inject, open (a chain location) or shut (close a chain location).
        public var kind: String
        public var companyID: Int
        public var title: String
        /// What approving does, what it costs once (0 if nothing), and what could go wrong.
        public var effect: String
        public var cost: Double
        public var risk: String
        /// "Name, Title" of who recommends, and what they recommend and why.
        public var advisor: String
        public var recommends: Bool
        public var reason: String
        /// For a location: the proposal's number and what it is about (a city id to open in, a store id to close).
        public var proposalID: Int = 0
        public var target: String = ""
    }

    public enum BoardDecisionResult: Equatable, Sendable {
        /// Carried out, with what happened.
        case done(String)
        case declined
        /// The shares voted it down: the percent that were for it.
        case voteFailed(Int)
        /// Could not be carried out now; the item stays on the list.
        case refused(String)
        case gone
    }

    // MARK: Reading

    /// A job the board handed on after a decision, with who has it and when it lapses.
    public struct FollowUp: Identifiable, Equatable, Sendable {
        public var id: Int
        public var text: String
        public var companyID: Int
        public var assignee: String
        public var week: Int
        public var due: Int
        public var status: String       // "" open, "done", "lapsed"
        public var note: String
    }

    public static func followUps(_ s: GameState, key: String) -> [FollowUp] {
        board(s, key: key)["fu"].array.map {
            FollowUp(id: $0["id"].int, text: $0["text"].string, companyID: $0["co"].int, assignee: $0["who"].string, week: $0["w"].int, due: $0["due"].int, status: $0["st"].string, note: $0["note"].string)
        }
    }
    public static func openFollowUps(_ s: GameState, key: String) -> [FollowUp] { followUps(s, key: key).filter { $0.status.isEmpty } }

    /// Who speaks for a company: its manager, else the board.
    static func advisor(_ s: GameState, _ co: Company) -> String {
        if let mid = co.managerID, let n = s.people[mid] { return "\(n.name), Manager" }
        return "Your board"
    }

    /// Points waiting for the owner on one board: the decision list, plus emergencies nobody has answered yet.
    public static func openDecisionCount(_ s: GameState, key: String, data: GameData) -> Int {
        boardDecisions(s, key: key, data: data).count + meetings(s, key: key).filter { $0.isEmergency && $0.status.isEmpty }.count
    }

    /// Every board's decisions in one list, the ones their advisers recommend first.
    public static func boardDecisions(_ s: GameState, data: GameData) -> [BoardDecision] {
        let all = boardKeys(s).flatMap { boardDecisions(s, key: $0, data: data) }
        return all.filter { $0.recommends } + all.filter { !$0.recommends }
    }

    public static func boardDecisions(_ s: GameState, key: String, data: GameData) -> [BoardDecision] {
        let cos = boardCompanies(s, key: key)
        guard !cos.isEmpty else { return [] }
        let memo = board(s, key: key)["memo"]
        var out: [BoardDecision] = []
        for c in cos where c.status == .open && c.type != "hold" {
            let cur = World(state: s, data: data).currency(c)
            let h3 = Array(c.monthlyHistory.suffix(3)), h6 = Array(c.monthlyHistory.suffix(6))
            let p3 = h3.reduce(0.0) { $0 + $1.profit }, r3 = h3.reduce(0.0) { $0 + $1.revenue }
            let p6 = h6.reduce(0.0) { $0 + $1.profit }, r6 = h6.reduce(0.0) { $0 + $1.revenue }
            let loss3 = h3.count == 3 && h3.allSatisfy { $0.profit < 0 }
            let loss6 = h6.count == 6 && h6.allSatisfy { $0.profit < 0 }
            let deep3 = r3 <= 0 || p3 < -r3 * 0.1, deep6 = r6 <= 0 || p6 < -r6 * 0.1
            let adviser = advisor(s, c)
            func add(_ kind: String, _ title: String, effect: String, cost: Double = 0, risk: String, advisor by: String? = nil, recommends: Bool, reason: String) {
                let id = "\(kind):\(c.id)"
                if !memo[id].isNull && memo[id].int > s.week { return }
                out.append(BoardDecision(id: id, key: key, kind: kind, companyID: c.id, title: title, effect: effect, cost: cost, risk: risk, advisor: by ?? adviser, recommends: recommends, reason: reason))
            }
            if loss3, SaleListings.routeProblem(s, companyID: c.id, route: "broker", pct: 100) == nil {
                add("sell", "Put \(c.name) up for sale", effect: "\(c.name) is listed with a broker. Offers reach you; nothing is sold until you accept one.",
                    risk: "If you later accept an offer you stop owning the business.", recommends: deep3,
                    reason: deep3 ? "It lost \(cur.short(-p3)) over three months, more than a tenth of what it took in." : "The loss is small against its sales. A change of course may be enough.")
            }
            if loss6 && !s.isBranch(c) {
                add("close", "Close \(c.name)", effect: "\(c.name) is wound up: assets sold at a discount, staff let go, loans repaid as far as the money goes. You get what is left.",
                    risk: "It cannot be undone, and notice and redundancy pay come first.", recommends: deep6,
                    reason: deep6 ? "Six months of losses, \(cur.short(-p6)) in all." : "Six months of small losses. It may still turn.")
            }
            if c.form == .limited, c.str("dp27", "none") == "none", !c.value("holders").array.isEmpty, h3.count == 3, p3 > 0, c.cash > 0 {
                add("dividend", "Start a regular dividend at \(c.name)", effect: "\(c.name) pays 25% of profit to its owners each quarter, when there is profit and cash after costs.",
                    risk: "Cash leaves the company every quarter. You receive your share.", recommends: c.cash > p3,
                    reason: "It made \(cur.short(p3)) over three months and pays its owners nothing." + (c.cash > p3 ? "" : " Cash is thin, so I would wait."))
            }
            let wk = c.num("wkD")
            if c.cash < 0 || (wk < 0 && c.cash / -wk < 8) {
                let x = cur.roundedStep(max(cur.scaledPrice(20000), abs(wk) * 8), about: 1000)
                if Payments.liquid(s) >= x {
                    let mild = p3 > -r3 * 0.1
                    add("inject", "Put \(cur.short(x)) into \(c.name)", effect: "You move \(cur.short(x)) from your own cash into the company.", cost: x,
                        risk: "It is your money; it only helps if the trouble is temporary.", recommends: mild,
                        reason: mild ? "Cash would run out within weeks, but the business itself holds up." : "Cash is going and so is the business. The money would only cover losses.")
                }
            }
            if let mid = c.managerID, let n = s.people[mid], loss3, s.week - c.int("mgrW0") >= 13, c.int("ceoBlk") <= s.week {
                let director = seats(s, key: key).first { $0.role == "director" }.flatMap { s.people[$0.id] }
                add("ceo", "Replace \(n.name) as manager of \(c.name)", effect: "The manager is dismissed under the notice and severance rules of the country.",
                    risk: "The company has no manager until you appoint one.", advisor: director.map { "\($0.name), Director" } ?? "Your board", recommends: deep3,
                    reason: deep3 ? "Three losing months in a row, \(cur.short(-p3)) in all. A new leader may turn it." : "Three losing months, but small ones. Give them time.")
            }
        }
        if isChainKey(key) {
            for p in ChainLocations.proposals(s, chainID: keyID(key)) {
                let open = p.kind == "open"
                out.append(BoardDecision(id: "\(p.kind):\(p.chainID):\(p.id)", key: key, kind: p.kind, companyID: p.storeID,
                                         title: open ? "Open a location in \(p.cityName)" : "Close \(p.storeName)",
                                         effect: open ? "A new location opens in \(p.cityName), built to the chain's standards and running about three weeks after it is set up."
                                                      : "\(p.storeName) is closed: its stock and people move to sister locations as far as they fit, the rest are made redundant and the lease is given up.",
                                         cost: p.cost, risk: open ? "The money is paid at once and the rent stays." : "It cannot be undone, and redundancy pay is due.",
                                         advisor: p.by, recommends: true, reason: p.why, proposalID: p.id, target: p.target))
            }
        }
        return out
    }

    // MARK: Deciding

    /// The kind of vote the shares hold on a decision (`boardVote`); nil where the owner decides alone or the vote is part of the move.
    static func voteKind(_ kind: String) -> String? {
        switch kind {
        case "sell": return "sell"
        case "close", "shut": return "close"
        case "dividend": return "dividend"
        case "open": return "open"
        default: return nil
        }
    }

    /// Does the board carry a move? Nil when it does (or when you own it alone); else the share of yes votes.
    public static func boardGate(_ s: GameState, kind: String, companyID: Int) -> Int? {
        let v = boardVote(s, kind: kind, companyID: companyID, advisory: true)
        return v.active && !v.passes ? Int(jsRound(v.percentYes)) : nil
    }

    /// Put an item to the board and carry it out (`approve`), or turn it down. "close" ends in `GameEngine.windUpCompany`, which this model cannot reach:
    /// the engine calls `boardGate` and `settleDecision` around it.
    @discardableResult
    public static func decideBoardItem(_ s: inout GameState, id: String, approve: Bool, data: GameData, context fc: FinanceContext) -> BoardDecisionResult {
        guard let d = boardDecisions(s, data: data).first(where: { $0.id == id }) else { return .gone }
        if !approve { settleDecision(&s, d, approved: false); return .declined }
        if let vk = voteKind(d.kind), let pct = boardGate(s, kind: vk, companyID: d.companyID) { settleDecision(&s, d, approved: false); return .voteFailed(pct) }
        let r = carryOut(&s, d, data: data, context: fc)
        if case .refused = r { return r }
        if case .voteFailed = r { settleDecision(&s, d, approved: false); return r }
        settleDecision(&s, d, approved: true)
        return r
    }

    /// A decision taken: it is not raised again for a while, and a location proposal leaves the list.
    public static func settleDecision(_ s: inout GameState, _ d: BoardDecision, approved: Bool) {
        var b = board(s, key: d.key)
        var memo = b["memo"].isNull ? JSONValue.object([:]) : b["memo"]
        for (k, v) in memo.object where v.int <= s.week { memo[k] = .null }   // forget what has run out
        if d.proposalID != 0 {
            b["locp"] = .array(b["locp"].array.filter { $0["id"].int != d.proposalID })
            memo[ChainLocations.memoKey(kind: d.kind, target: d.target)] = .number(Double(s.week + locationQuietWeeks))
        } else {
            memo[d.id] = .number(Double(s.week + (approved ? approvedQuietWeeks : declinedQuietWeeks)))
        }
        b["memo"] = .object(memo.object.filter { !$0.value.isNull })
        writeBoard(&s, key: d.key, b)
    }

    /// Do what an approved item says. Changes the game only when it can be carried out in full.
    static func carryOut(_ s: inout GameState, _ d: BoardDecision, data: GameData, context fc: FinanceContext) -> BoardDecisionResult {
        guard let co = s.company(d.companyID), co.status.isLive, let ci = s.companyIndex(d.companyID) else { return .refused("That company is no longer there.") }
        switch d.kind {
        case "sell":
            if let why = SaleListings.routeProblem(s, companyID: co.id, route: "broker", pct: 100) { return .refused(why == "It is already on the market." ? "\(co.name) is already listed for sale." : why) }
            guard listForSale(&s, companyID: co.id) else { return .refused("\(co.name) cannot be listed for sale now.") }
            return .done("\(co.name) is listed with a broker. Offers will reach you.")
        case "dividend":
            guard co.form == .limited else { return .refused("Only a limited company pays dividends.") }
            if co.str("dp27", "none") != "none" { return .refused("\(co.name) already pays a dividend.") }
            s.companies[ci].set("dp27", "low")
            return .done("\(co.name) will pay 25% of profit each quarter.")
        case "inject":
            guard Payments.liquid(s) >= d.cost, Payments.injectCash(&s, companyID: co.id, amount: d.cost) else { return .refused("You do not have the money for that now.") }
            return .done("You put \(World(state: s, data: data).currency(co).short(d.cost)) into \(co.name).")
        case "ceo":
            guard co.managerID != nil else { return .refused("\(co.name) has no manager to dismiss.") }
            // With co-owners this is a vote by shares (you decide alone above half); a failed vote closes the point.
            switch proposeCEOChange(&s, companyID: co.id, data: data) {
            case .dismissed:
                addFollowUp(&s, key: d.key, text: "Appoint a new manager for \(co.name) (Team).", companyID: co.id, check: "mgr")
                return .done("The manager of \(co.name) was dismissed.")
            case .voteFailed(let pct): return .voteFailed(pct)
            case .blocked(let w): return .refused("Replacing the manager was put to the owners lately. Try again in \(w) \(w == 1 ? "week" : "weeks").")
            case .refused(let why): return .refused(why)
            }
        case "open", "shut":
            return ChainLocations.carryOut(&s, d, data: data, context: fc)
        default:
            return .refused("There is nothing the board can do about that.")
        }
    }

    /// Put the company up with a broker, as the emergency answer "put it up for sale" does: the same listing the owner's sale routes make
    /// (`SaleListings`, run by `CompanySale`). False if it was listed already or cannot be sold.
    @discardableResult
    static func listForSale(_ s: inout GameState, companyID: Int) -> Bool { SaleListings.start(&s, companyID: companyID, route: "broker") }

    // MARK: Follow-up jobs

    static func addFollowUp(_ s: inout GameState, key: String, text: String, companyID: Int, check: String?) {
        var b = board(s, key: key)
        let co = s.company(companyID)
        let who = co?.managerID.flatMap { s.people[$0] }?.name
        var fu = b["fu"].array
        var rec: [String: JSONValue] = ["id": .number(Double(s.makeID())), "text": .string(text), "co": .number(Double(companyID)), "who": .string(who == nil ? "You" : "You, with \(who!)"),
                                        "w": .number(Double(s.week)), "due": .number(Double(s.week + 8)), "st": ""]
        if let c = check { rec["chk"] = .string(c) }
        fu.append(.object(rec))
        // keep every open job and the latest finished ones
        let open = fu.filter { $0["st"].string.isEmpty }, closed = fu.filter { !$0["st"].string.isEmpty }.suffix(keptFollowUps)
        b["fu"] = .array(Array(closed) + open)
        writeBoard(&s, key: key, b)
    }

    /// The owner marks a follow-up done by hand (for jobs the game cannot check).
    @discardableResult
    public static func completeFollowUp(_ s: inout GameState, key: String, id: Int) -> Bool {
        var b = board(s, key: key)
        var fu = b["fu"].array
        guard let i = fu.firstIndex(where: { $0["id"].int == id && $0["st"].string.isEmpty }) else { return false }
        fu[i]["st"] = "done"; fu[i]["note"] = "Marked done by you"; fu[i]["cw"] = .number(Double(s.week))
        b["fu"] = .array(fu)
        writeBoard(&s, key: key, b)
        return true
    }

    /// Weekly: follow-ups with a check close when the check is true; old ones lapse.
    static func sweepBoards(_ s: inout GameState) {
        for key in boardKeys(s) {
            var b = board(s, key: key)
            var changed = false
            var fu = b["fu"].array
            for i in fu.indices where fu[i]["st"].string.isEmpty {
                let co = s.company(fu[i]["co"].int)
                let done: Bool
                switch fu[i]["chk"].string {
                case "mgr": done = co?.managerID != nil
                case "notice": done = co.map { c in !c.staff.contains { $0.noticeWeeks > 0 } } ?? true
                default: done = false
                }
                if co == nil || !(co!.status.isLive) { fu[i]["st"] = "lapsed"; fu[i]["note"] = "The company is gone."; changed = true }
                else if done { fu[i]["st"] = "done"; fu[i]["note"] = "Done."; fu[i]["cw"] = .number(Double(s.week)); changed = true }
                else if s.week >= fu[i]["due"].int { fu[i]["st"] = "lapsed"; fu[i]["note"] = "Not done in time."; fu[i]["cw"] = .number(Double(s.week)); changed = true }
            }
            if changed { b["fu"] = .array(fu); writeBoard(&s, key: key, b) }
        }
    }
}
