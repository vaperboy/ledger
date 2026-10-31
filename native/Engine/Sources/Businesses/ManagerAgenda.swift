import Foundation
import GameCore
import Countries
import Employees
import Finance

/// Board agendas, decisions and what they do (Stage 6).
///
/// A meeting is held only when there is something to decide. Its agenda is built from what is true in the companies the board looks
/// after: losses, thin margins, low awareness, missing paperwork, a company without a manager, sold-out days, a bottleneck, owners
/// waiting for a dividend, and the signs of trouble among the people. Approving an item changes the game through the systems that already
/// exist (prices, stock rules, the broker listing of a company, marketing through the manager, document applications, equipment and
/// premises purchases, the manager search, dividend policy, the meeting with a manager). An item the board cannot carry out right now is
/// refused with the reason and stays on the agenda. The answer to every item is kept as an outcome; a declined item is not raised again
/// for a while; a meeting closes when its last item is decided or after `lapseWeeks`.
///
/// Saved on the board `brd`: `mts[]` (meetings; items carry `key`, `eff`, `risk`, `cost?`, `by?`, `st`, `out`, `dw`), `memo` {key: week until
/// which the same point is not raised again} and `fu[]` (follow-up actions). All keys are written only when set.
extension ManagerModel {
    /// A regular meeting nobody decided is closed after this many weeks; its open points lapse.
    public static let lapseWeeks = 4
    static let declinedQuietWeeks = 12, approvedQuietWeeks = 8, lapsedQuietWeeks = 4
    static let keptMeetings = 24, keptFollowUps = 20, maxAgenda = 5

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

    /// Points waiting for the owner on one board: undecided items of open regular meetings, plus emergencies nobody has answered yet.
    public static func openDecisionCount(_ s: GameState, key: String) -> Int {
        meetings(s, key: key).reduce(0) { n, m in
            if m.isEmergency { return n + (m.status.isEmpty ? 1 : 0) }
            return n + (m.status.isEmpty ? m.items.filter { !$0.action.isEmpty && $0.status.isEmpty }.count : 0)
        }
    }

    /// What a meeting called now would put on the agenda (empty when there is nothing to decide, so no meeting would be held).
    public static func agendaPreview(_ s: GameState, key: String, data: GameData) -> [MeetingItem] {
        let cos = boardCompanies(s, key: key)
        guard !cos.isEmpty else { return [] }
        return agendaItems(s, key: key, cos: cos, data: data).enumerated().map { itemFrom($0.element, index: $0.offset) }
    }

    // MARK: Building the agenda

    static func missingDocs(_ s: GameState, _ c: Company, data: GameData) -> [String] {
        guard let bd = data.catalog[c.type] else { return [] }
        let w = World(state: s, data: data)
        return Documents.needed(c, bd, w).filter { $0 != "vat_not_applicable" && !["ok", "applied"].contains(c.value("docs")[$0]["st"].string) }
    }

    /// Points that are still open in a meeting younger than the lapse time (they block a second copy of the same point).
    static func pendingKeys(_ b: JSONValue, week: Int) -> Set<String> {
        var out = Set<String>()
        for m in b["mts"].array where !m["emg"].bool && m["st"].string.isEmpty && week - m["w"].int < lapseWeeks {
            for it in m["items"].array where it["st"].string.isEmpty && !it["key"].string.isEmpty { out.insert(it["key"].string) }
        }
        return out
    }

    /// The points a meeting held now would deal with: what each seat brings up, minus what is already open and what was answered recently.
    static func agendaItems(_ s: GameState, key: String, cos: [Company], data: GameData) -> [JSONValue] {
        let vs = voters(s, key: key)
        var raw: [JSONValue] = []
        for v in vs { for r in recommendations(s, voter: v, cos: cos, data: data) where !raw.contains(where: { $0["text"].string == r["text"].string }) { raw.append(r) } }
        for r in questionCEO(s, key: key, cos: cos) { raw.append(r) }
        let b = board(s, key: key)
        let pending = pendingKeys(b, week: s.week)
        let memo = b["memo"]
        var seen = Set<String>()
        var out: [JSONValue] = []
        for var it in raw {
            guard let c = s.company(it["co"].int), c.status.isLive else { continue }
            let k = "\(it["act"].string):\(c.id)"
            if pending.contains(k) || (!memo[k].isNull && memo[k].int > s.week) || !seen.insert(k).inserted { continue }
            let d = describe(s, act: it["act"].string, company: c, data: data)
            it["key"] = .string(k)
            it["eff"] = .string(d.effect)
            it["risk"] = .string(d.risk)
            if d.cost > 0 { it["cost"] = .number(d.cost) }
            if !it["who"].isNull, let v = vs.first(where: { $0.personID == it["who"].int }) { it["by"] = .string("\(v.name), \(v.title)") }
            out.append(it)
        }
        return Array(out.prefix(maxAgenda))
    }

    /// What approving a point does, what it costs once, and what could go wrong. Everything here is also what `applyItem` carries out.
    static func describe(_ s: GameState, act: String, company c: Company, data: GameData) -> (cost: Double, effect: String, risk: String) {
        let w = World(state: s, data: data)
        let cur = w.currency(c)
        switch act {
        case "price":
            return (0, "Prices at \(c.name) go up one step.", "Some price-sensitive customers may stop buying; every sale earns more.")
        case "stock":
            return (0, "\(c.name) orders plenty of stock from now on.", "More cash is tied up in stock; fewer sales are lost to empty shelves.")
        case "sale":
            return (0, "\(c.name) is listed with a broker. Offers reach you; nothing is sold until you accept one.", "If you later accept an offer you stop owning the business.")
        case "marketing":
            let ch = (data.catalog[c.type]?.audience ?? 0) > 0.5 ? "google" : "meta"
            let now = c.value("mkt")[ch]["b"].double
            let step = marketingSteps(ch, cur).first(where: { $0 > now }).map { $0 - now } ?? 0
            let more = step > 0 ? " by about \(cur.short(step)) a week" : ""
            let who = c.managerID != nil ? "The manager raises" : "You raise"
            return (0, c.managerID != nil ? "\(who) the marketing budget one step\(more)." : "A job for you: raise the marketing budget\(more) under Sales and Market.",
                    "The cost runs every week; awareness builds slowly and fades if you stop.")
        case "hire":
            return (0, "A search for a manager for \(c.name) starts. The best candidate, with pay already agreed, comes to you as an offer.", "Nothing is paid until you accept. A manager is a fixed monthly cost.")
        case "paperwork":
            let ids = missingDocs(s, c, data: data)
            let bd = data.catalog[c.type]
            let fees = bd.map { b in ids.reduce(0.0) { $0 + Documents.cost($1, company: c, b, w) } } ?? 0
            return (fees, "\(c.name) applies for the \(ids.count) missing \(ids.count == 1 ? "document" : "documents") now.", "Fees are paid at once and approval takes some weeks.")
        case "fireceo":
            return (0, "The manager of \(c.name) is dismissed under the notice and severance rules of the country.", "The company has no manager until you appoint one.")
        case "capacity":
            if let bd = data.catalog[c.type], let p = bottleneckProposal(s, c, bd, data: data) {
                let nm = bd.equipment.first(where: { $0.id == p.id })?.name ?? "equipment"
                if p.kind == "space" { return (p.cost * 0.5, "\(c.name) takes about a quarter more space.", "Cash leaves the company now and the rent or fit-out cost stays.") }
                return (p.cost, "\(c.name) buys \(nm.lowercased()).", "Cash leaves the company now; it only pays if demand stays high.")
            }
            return (0, "", "")
        case "dividend":
            return (0, "\(c.name) pays 25% of profit to its owners each quarter, when there is profit and cash after costs.", "Cash leaves the company every quarter. You receive your share.")
        case "morale":
            return (0, "You talk with the manager of \(c.name) about how the work is going.", "The manager will expect you to keep listening.")
        case "overtime":
            return (0, "The manager of \(c.name) is asked to hire more people.", "More wages every month. The manager hires only if the company can afford it safely.")
        case "leaving":
            return (0, "A follow-up goes to you: talk to the person at \(c.name) who is leaving.", "If nothing is done they leave when their notice ends.")
        default:
            return (0, "", "")
        }
    }

    // MARK: Carrying out a point

    enum ItemEffect: Equatable {
        case ok(String, followUp: String?, check: String?)
        case refused(String)
    }

    /// Put the company up with a broker, as the emergency answer "put it up for sale" does. False if it was listed already.
    @discardableResult
    static func listForSale(_ s: inout GameState, companyID: Int) -> Bool {
        var list = s.rest["sales"]?.array ?? []
        if list.contains(where: { $0["co"].int == companyID }) { return false }
        list.append(.object(["co": .number(Double(companyID)), "m": "broker", "w0": .number(Double(s.week)), "offers": .array([])]))
        s.rest["sales"] = .array(list)
        return true
    }

    /// Do what an approved point says. Changes the game only when it can be carried out in full.
    static func applyItem(_ s: inout GameState, item it: JSONValue, data: GameData, marketing: MarketingTables?) -> ItemEffect {
        let cid = it["co"].int
        guard let co = s.company(cid), co.status.isLive, let ci = s.companyIndex(cid) else { return .refused("That company is no longer there.") }
        let w = World(state: s, data: data)
        let cur = w.currency(co)
        switch it["act"].string {
        case "price":
            if Chains.chain(s, of: co) != nil { Chains.setStoreRule(&s, companyID: cid, rule: .priceSteps(min(1, co.value("off")["price"].double + 1))) }
            else {
                guard co.priceLevel < 3 else { return .refused("Prices at \(co.name) are already at the top step.") }
                s.companies[ci].priceLevel = co.priceLevel + 1
            }
            return .ok("Prices at \(co.name) went up one step.", followUp: nil, check: nil)
        case "stock":
            if Chains.chain(s, of: co) != nil { Chains.setStoreRule(&s, companyID: cid, rule: .ordering(2)) } else { s.companies[ci].set("stockPol", 2) }
            return .ok("\(co.name) now orders plenty.", followUp: nil, check: nil)
        case "sale":
            guard listForSale(&s, companyID: cid) else { return .refused("\(co.name) is already listed for sale.") }
            return .ok("\(co.name) is listed with a broker. Offers will reach you.", followUp: nil, check: nil)
        case "fireceo":
            guard co.managerID != nil else { return .refused("\(co.name) has no manager to dismiss.") }
            dismissForBoard(&s, companyID: cid, data: data)
            return .ok("The manager of \(co.name) was dismissed.", followUp: "Appoint a new manager for \(co.name) (Team).", check: "mgr")
        case "marketing":
            guard co.managerID != nil, let m = marketing else {
                return .ok("Marketing at \(co.name) is yours to raise.", followUp: "Raise the marketing budget at \(co.name) (Sales and Market).", check: nil)
            }
            let before = co.value("mkt").object.values.reduce(0.0) { $0 + $1["b"].double }
            let said = ask(&s, companyID: cid, key: "mkt_more", data: data, marketing: m) ?? ""
            let after = s.companies[ci].value("mkt").object.values.reduce(0.0) { $0 + $1["b"].double }
            guard after > before else { return .refused(said.isEmpty ? "The manager could not raise marketing now." : "The manager: \(said)") }
            return .ok("The manager raised marketing at \(co.name) to \(cur.short(after)) a week.", followUp: nil, check: nil)
        case "hire":
            guard co.managerID == nil else { return .refused("\(co.name) already has a manager.") }
            guard let bd = data.catalog[co.type] else { return .refused("Nobody can search for \(co.name).") }
            let key = boardKey(s, co)
            let by = it["who"].isNull ? nil : s.people[it["who"].int]
            let seat = by ?? seats(s, key: key).compactMap { s.people[$0.id] }.first ?? Headquarters.rightHand(s).flatMap { s.people[$0.personID] }
            guard let n = seat else { return .refused("Nobody at the table can run a search.") }
            if offerManagerCandidate(&s, need: co, bd: bd, from: n, data: data) {
                return .ok("\(n.name) found a candidate; the offer is in your Inbox.", followUp: "Answer the manager offer for \(co.name) (Inbox).", check: "mgr")
            }
            return .ok("\(n.name) found nobody suitable yet.", followUp: "Find a manager for \(co.name) (Team).", check: "mgr")
        case "paperwork":
            guard let bd = data.catalog[co.type] else { return .refused("No paperwork can be filed for \(co.name).") }
            let ids = missingDocs(s, co, data: data)
            guard !ids.isEmpty else { return .refused("Nothing is missing at \(co.name) now.") }
            let fees = ids.reduce(0.0) { $0 + Documents.cost($1, company: co, bd, w) }
            guard co.cash >= fees else { return .refused("\(co.name) has \(cur.short(co.cash)) and the fees come to \(cur.short(fees)). Put money in first.") }
            var done = 0
            for id in ids where Documents.apply(id, companyID: cid, state: &s, data: data) == .ok { done += 1 }
            guard done > 0 else { return .refused("The applications could not be filed (an accountant agreement may be needed first).") }
            return .ok("\(co.name) applied for \(done) of \(ids.count) missing \(ids.count == 1 ? "document" : "documents").", followUp: nil, check: nil)
        case "capacity":
            guard let bd = data.catalog[co.type], let p = bottleneckProposal(s, co, bd, data: data), p.kind == "eq" || p.kind == "space" else {
                return .refused("The bottleneck at \(co.name) has changed; nothing to buy now.")
            }
            let price = p.kind == "space" ? p.cost * 0.5 : p.cost
            guard co.cash >= price else { return .refused("\(co.name) has \(cur.short(co.cash)); this needs \(cur.short(price)).") }
            var n = recommender(it, s) ?? Person(raw: [:])
            if n.name.isEmpty { n.name = "The board" }
            let cash0 = co.cash, m20 = co.value("prem")["m2"].double
            buyForProposal(&s, ci, p, n, data: data)
            let after = s.companies[ci]
            guard after.cash < cash0 || after.value("prem")["m2"].double > m20 else { return .refused("The purchase could not be made.") }
            return .ok(p.kind == "space" ? "\(co.name) took more space." : "\(co.name) bought the equipment.", followUp: nil, check: nil)
        case "dividend":
            guard co.form == .limited else { return .refused("Only a limited company pays dividends.") }
            if co.str("dp27", "none") != "none" { return .refused("\(co.name) already pays a dividend.") }
            s.companies[ci].set("dp27", "low")
            return .ok("\(co.name) will pay 25% of profit each quarter.", followUp: nil, check: nil)
        case "morale":
            guard let mid = co.managerID, let mg = s.people[mid], let m = marketing else { return .refused("\(co.name) has no manager to talk to.") }
            if CounterpartMeeting.isCoolingDown(lastWeek: co.value("meetW").isNull ? nil : co.num("meetW"), now: s.week) { return .refused("You met \(mg.name) a few days ago. Give it a week or two.") }
            meetOne(&s, companyID: cid, goal: "morale", tone: "casual", data: data, marketing: m)
            return .ok("You talked with \(mg.name); morale is better.", followUp: nil, check: nil)
        case "overtime":
            guard co.managerID != nil, let m = marketing else { return .refused("\(co.name) has no manager to ask.") }
            let said = ask(&s, companyID: cid, key: "hire", data: data, marketing: m) ?? ""
            return .ok(said.isEmpty ? "The manager was asked to hire." : "The manager: \(said)", followUp: nil, check: nil)
        case "leaving":
            return .ok("Noted.", followUp: "Talk to the person leaving \(co.name) (Team).", check: "notice")
        default:
            return .refused("There is nothing the board can do about that.")
        }
    }
    private static func recommender(_ it: JSONValue, _ s: GameState) -> Person? { it["who"].isNull ? nil : s.people[it["who"].int] }

    // MARK: Deciding

    /// A point decided: kept on the meeting with its outcome, remembered so it is not raised again soon, and the meeting closes with its last point.
    static func recordDecision(_ b: inout JSONValue, meeting k: Int, item idx: Int, status: String, outcome: String, week: Int, quiet: Int) {
        var mts = b["mts"].array
        guard mts.indices.contains(k), mts[k]["items"].array.indices.contains(idx) else { return }
        var items = mts[k]["items"].array
        items[idx]["st"] = .string(status)
        items[idx]["out"] = .string(outcome)
        items[idx]["dw"] = .number(Double(week))
        let key = items[idx]["key"].string
        if !key.isEmpty {
            var memo = b["memo"].isNull ? JSONValue.object([:]) : b["memo"]
            // forget what has run out, so the record stays small
            for (mk, mv) in memo.object where mv.int <= week { memo[mk] = .null }
            memo[key] = .number(Double(week + quiet))
            b["memo"] = .object(memo.object.filter { !$0.value.isNull })
        }
        mts[k]["items"] = .array(items)
        if !mts[k]["emg"].bool, mts[k]["st"].string.isEmpty, !items.contains(where: { !$0["act"].string.isEmpty && $0["st"].string.isEmpty }) {
            mts[k]["st"] = "closed"; mts[k]["cw"] = .number(Double(week))
        }
        b["mts"] = .array(mts)
    }

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

    // MARK: Weekly: lapse, close, check the follow-ups

    /// Regular meetings that nobody finished lapse after `lapseWeeks`; follow-ups with a check close when the check is true; old ones lapse.
    static func sweepBoards(_ s: inout GameState) {
        for key in boardKeys(s) {
            var b = board(s, key: key)
            var changed = false
            var mts = b["mts"].array
            for k in mts.indices where !mts[k]["emg"].bool && mts[k]["st"].string.isEmpty {
                var items = mts[k]["items"].array
                let open = items.indices.filter { !items[$0]["act"].string.isEmpty && items[$0]["st"].string.isEmpty }
                if open.isEmpty { mts[k]["st"] = "closed"; mts[k]["cw"] = .number(Double(s.week)); changed = true; continue }
                guard s.week - mts[k]["w"].int >= lapseWeeks else { continue }
                var memo = b["memo"].isNull ? JSONValue.object([:]) : b["memo"]
                for i in open {
                    items[i]["st"] = "late"; items[i]["out"] = "No decision was taken."; items[i]["dw"] = .number(Double(s.week))
                    if !items[i]["key"].string.isEmpty { memo[items[i]["key"].string] = .number(Double(s.week + lapsedQuietWeeks)) }
                }
                b["memo"] = memo
                mts[k]["items"] = .array(items); mts[k]["st"] = "lapsed"; mts[k]["cw"] = .number(Double(s.week)); changed = true
            }
            if changed { b["mts"] = .array(mts) }
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
