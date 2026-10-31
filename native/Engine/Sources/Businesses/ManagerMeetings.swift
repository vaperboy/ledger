import Foundation
import GameCore
import Countries
import Employees
import Finance

/// Board meetings and emergencies, meetings with your managers, the data analyst's report, and a manager nobody meets slipping.
/// Originals: features/company/shelf_stock_chains_boards.js (`holdMeeting`, `recs`, `emergency`, `doEmg`, `emgWeek`, `boardsWeek`, `briefing`),
/// features/company/shareholders_and_board.js (`extraX`, `ownersWeek`), engine/management/meetings.js (`callMeeting`, `meetOne`,
/// `analystReport`), features/people/owner_attention.js (`OA59`).
extension ManagerModel {
    // MARK: Reading meetings

    public struct MeetingItem: Identifiable, Equatable, Sendable {
        public var id: Int
        public var text: String
        public var action: String       // price, stock, sale, hire, marketing, paperwork, fireceo, capacity, dividend, morale, overtime, leaving
        public var companyID: Int
        public var recommendedBy: Int?
        public var status: String       // "" to decide, "yes", "no", "late" (nobody decided in time)
        public var invited: [String]
        /// What approving does, what it costs once (0 if nothing), and what could go wrong. Empty on points from older saves.
        public var effect: String = ""
        public var cost: Double = 0
        public var risk: String = ""
        /// What happened when it was decided, and the week.
        public var outcome: String = ""
        public var decidedWeek: Int? = nil
        /// Who raised it, "Name, Title".
        public var raisedBy: String = ""
    }
    public struct MeetingRow: Equatable, Sendable { public var companyID: Int; public var name: String; public var revenue: Double; public var profit: Double; public var previous: Double; public var cash: Double }
    public struct EmergencyVote: Equatable, Sendable { public var personID: Int?; public var name: String; public var title: String; public var pick: Int; public var isRightHand: Bool }
    public struct BoardMeeting: Identifiable, Equatable, Sendable {
        public var id: Int
        public var week: Int
        public var isEmergency: Bool
        public var title: String
        public var why: String
        public var rows: [MeetingRow]
        public var items: [MeetingItem]
        public var exceptions: [String]
        public var rightHandNote: String
        public var options: [String]
        public var votes: [EmergencyVote]
        public var rightHandPick: Int?
        public var status: String        // "", "you", "lh", "late"
        public var picked: Int?
        public var companyID: Int
        public var kind: String
        /// Who sat at the table when it was held (names and titles); empty on older saves.
        public var attendees: [String] = []
        /// The week it closed (decided, lapsed or answered); nil while open.
        public var closedWeek: Int? = nil
        /// A regular meeting is open while "", then "closed" (every point decided) or "lapsed" (time ran out). Emergencies: "", "you", "lh", "late".
        public var isOpen: Bool { status.isEmpty }
        /// The minutes: what was on the agenda, what was decided and what came of it.
        public var minutes: [String] {
            if isEmergency {
                guard let p = picked, options.indices.contains(p) else { return [] }
                return ["Decision: \(options[p])" + (status == "lh" ? " (your right hand decided)" : "")]
            }
            return items.filter { !$0.action.isEmpty }.map { it in
                switch it.status {
                case "yes": return "Approved: \(it.text) " + (it.outcome.isEmpty ? "" : "Result: \(it.outcome)")
                case "no": return "Declined: \(it.text)"
                case "late": return "No decision: \(it.text)"
                default: return "Open: \(it.text)"
                }
            }
        }
    }
    /// The meetings of a board, newest first. A regular meeting from before the agenda rules (no status) reads as closed when nothing is left to
    /// decide in it, and as lapsed after `lapseWeeks`, so old saves do not keep phantom points on the badges.
    public static func meetings(_ s: GameState, key: String) -> [BoardMeeting] {
        board(s, key: key)["mts"].array.map { m in
            var x = meetingFrom(m)
            guard !x.isEmergency, x.status.isEmpty else { return x }
            if !x.items.contains(where: { !$0.action.isEmpty && $0.status.isEmpty }) { x.status = "closed" }
            else if s.week - x.week >= lapseWeeks {
                x.status = "lapsed"
                for i in x.items.indices where x.items[i].status.isEmpty { x.items[i].status = "late" }
            }
            return x
        }
    }
    public static func meeting(_ s: GameState, key: String, id: Int) -> BoardMeeting? { meetings(s, key: key).first { $0.id == id } }
    static func itemFrom(_ j: JSONValue, index: Int) -> MeetingItem {
        MeetingItem(id: index, text: j["text"].string, action: j["act"].string, companyID: j["co"].int, recommendedBy: j["who"].isNull ? nil : j["who"].int,
                    status: j["st"].string, invited: j["inv"].array.map { $0.string }, effect: j["eff"].string, cost: j["cost"].double, risk: j["risk"].string,
                    outcome: j["out"].string, decidedWeek: j["dw"].isNull ? nil : j["dw"].int, raisedBy: j["by"].string)
    }
    static func meetingFrom(_ m: JSONValue) -> BoardMeeting {
        var x = BoardMeeting(id: m["id"].int, week: m["w"].int, isEmergency: m["emg"].bool, title: m["title"].string, why: m["why"].string,
                     rows: m["rows"].array.map { MeetingRow(companyID: $0["id"].int, name: $0["name"].string, revenue: $0["rev"].double, profit: $0["prof"].double, previous: $0["prev"].double, cash: $0["cash"].double) },
                     items: m["items"].array.enumerated().map { itemFrom($0.element, index: $0.offset) },
                     exceptions: m["ex"].array.map { $0.string }, rightHandNote: m["lh"].string, options: m["opts"].array.map { $0.string },
                     votes: m["votes"].array.map { EmergencyVote(personID: $0["id"].isNull ? nil : $0["id"].int, name: $0["name"].string, title: $0["t"].string, pick: $0["pick"].int, isRightHand: $0["lh"].bool) },
                     rightHandPick: m["lhPick"].isNull ? nil : m["lhPick"].int, status: m["st"].string, picked: m["pickI"].isNull ? nil : m["pickI"].int, companyID: m["co"].int, kind: m["kind"].string)
        x.attendees = m["att"].array.map { $0.string }
        x.closedWeek = m["cw"].isNull ? nil : m["cw"].int
        if x.title.isEmpty && !x.isEmergency { x.title = x.why == "Regular meeting" ? "Regular board meeting" : "Board meeting" }
        return x
    }

    // MARK: Points for a meeting

    static let seatToAdviceType: [String: String] = ["cfo": "fin", "legal": "law", "mkt": "mkt", "analyst": "lh", "consult": "ind", "chair": "chair", "director": "ind",
                                                    "hr": "exec", "lh": "lh", "ceo": "exec", "regional": "exec"]
    static func invited(for act: String) -> [String] {
        ["price": ["mkt", "analyst"], "stock": ["analyst"], "sale": ["legal", "cfo"], "hire": ["hr"], "marketing": ["mkt"], "paperwork": ["legal"], "dividend": ["cfo"], "capacity": ["analyst"]][act] ?? []
    }
    /// What a person at the table would bring up. Original: `recs`.
    static func recommendations(_ s: GameState, voter v: Voter, cos: [Company], data: GameData) -> [JSONValue] {
        guard let typ = seatToAdviceType[v.type] else { return [] }
        let cur = playerCurrency(s, data)
        var out: [JSONValue] = []
        func H3(_ c: Company) -> [MonthRecord] { Array(c.monthlyHistory.suffix(3)) }
        func item(_ text: String, _ act: String, _ c: Company) -> JSONValue {
            .object(["text": .string(text), "act": .string(act), "co": .number(Double(c.id)), "who": v.personID.map { .number(Double($0)) } ?? .null, "inv": .array(invited(for: act).map { .string($0) })])
        }
        if ["fin", "lh", "exec"].contains(typ), let bad = cos.first(where: { H3($0).count == 3 && H3($0).allSatisfy { $0.profit < 0 } }) {
            out.append(item("\(bad.name) lost money three months in a row (\(H3(bad).map { cur.short($0.profit) }.joined(separator: ", "))). Put it up for sale?", "sale", bad))
        }
        if ["ind", "exec", "lh"].contains(typ) {
            let low = cos.compactMap { c -> (Company, Double)? in
                guard let h = H3(c).last, c.priceLevel < 3, h.revenue > 0 else { return nil }
                let m = h.profit / h.revenue
                return m > -0.15 && m < (data.catalog[c.type]?.margin ?? 0.08) - 0.03 ? (c, m) : nil
            }.min { $0.1 < $1.1 }
            if let (c, m) = low { out.append(item("Margin at \(c.name) is \(Int(jsRound(m * 100)))%, the trade normally makes about \(Int(jsRound((data.catalog[c.type]?.margin ?? 0.08) * 100)))%. Raise prices one step.", "price", c)) }
        }
        if typ == "mkt" || typ == "chair", let quiet = cos.filter({ $0.awareness < 35 }).min(by: { $0.awareness < $1.awareness }) {
            out.append(item("Only \(Int(jsRound(quiet.awareness)))% of the area knows \(quiet.name). Spend more on marketing.", "marketing", quiet))
        }
        if typ == "law", let c = cos.first(where: { !missingDocs(s, $0, data: data).isEmpty }) {
            out.append(item("\(c.name) is missing paperwork it needs. Fix it before an inspection finds it.", "paperwork", c))
        }
        if ["exec", "chair", "lh"].contains(typ), let nom = cos.first(where: { $0.managerID == nil && $0.staff.count >= 3 }) {
            out.append(item("\(nom.name) has \(nom.staff.count) staff and no manager. Hire one.", "hire", nom))
        }
        if typ == "lh" || typ == "fin", let so = cos.first(where: { $0.value("dlast")["so"].double >= 2 }) {
            out.append(item("\(so.name) sold out \(so.value("dlast")["so"].int) days last week, about \(so.value("dlast")["lost"].int) sales lost. Order more.", "stock", so))
        }
        // capacity: the bottleneck is something the company can buy (equipment, space)
        if ["ind", "exec", "lh", "chair"].contains(typ), let c = cos.first(where: { c in
            guard c.value("lastW")["util"].double > 0.9, let bd = data.catalog[c.type], let p = bottleneckProposal(s, c, bd, data: data), p.kind == "eq" || p.kind == "space" else { return false }
            return c.cash >= (p.kind == "space" ? p.cost * 0.5 : p.cost)
        }), let bd = data.catalog[c.type], let p = bottleneckProposal(s, c, bd, data: data) {
            let what = p.kind == "space" ? "more space" : (bd.equipment.first(where: { $0.id == p.id })?.name.lowercased() ?? "equipment")
            out.append(item("\(c.name) runs at \(Int(jsRound(c.value("lastW")["util"].double * 100)))% of what it can deliver and the limit is \(p.kind == "space" ? "space" : "equipment"). Buy \(what).", "capacity", c))
        }
        // owners wait for a dividend
        if ["fin", "chair"].contains(typ), let c = cos.first(where: { $0.form == .limited && $0.str("dp27", "none") == "none" && !$0.value("holders").array.isEmpty && H3($0).count == 3 && H3($0).reduce(0.0, { $0 + $1.profit }) > 0 && $0.cash > 0 }) {
            out.append(item("\(c.name) made \(cur.short(H3(c).reduce(0.0) { $0 + $1.profit })) over three months and pays its owners nothing. Start a regular dividend.", "dividend", c))
        }
        // signs of trouble among the people
        if ["exec", "chair", "lh"].contains(typ) {
            if let c = cos.first(where: { $0.managerID != nil && mood($0) < 40 }) { out.append(item("The manager of \(c.name) is low in morale. Talk with them.", "morale", c)) }
            if let c = cos.first(where: { $0.managerID != nil && $0.value("dlast")["ot"].double > 0 }) { out.append(item("Staff at \(c.name) worked overtime last week. Ask the manager to hire more people.", "overtime", c)) }
            if let c = cos.first(where: { $0.staff.contains { $0.noticeWeeks > 0 } }) { out.append(item("Someone at \(c.name) is working their notice. Talk to them before they go.", "leaving", c)) }
        }
        return Array(out.prefix(3))
    }

    /// The board questions a CEO after three loss months. Original: `R12.extraX` step.
    static func questionCEO(_ s: GameState, key: String, cos: [Company]) -> [JSONValue] {
        guard let d = seats(s, key: key).first(where: { $0.role == "director" }) else { return [] }
        var out: [JSONValue] = []
        for c in cos {
            let H = Array(c.monthlyHistory.suffix(3))
            guard let mid = c.managerID, let n = s.people[mid], H.count == 3, H.allSatisfy({ $0.profit < 0 }), s.week - c.int("mgrW0") >= 13 else { continue }
            out.append(.object(["text": .string("The board questions \(n.name) as \(cos.count > 1 ? "manager of \(c.name)" : "CEO"): three months of losses in a row. Replace them?"),
                                "act": "fireceo", "co": .number(Double(c.id)), "who": .number(Double(d.id)), "inv": .array(["hr", "legal"])]))
        }
        return out
    }

    // MARK: Holding a meeting

    /// Call the board together. A meeting is held only when there is something to decide: no points, no meeting and no message.
    /// Original: `ACT.bd12meet` and `holdMeeting`.
    @discardableResult
    public static func holdBoardMeeting(_ s: inout GameState, key: String, data: GameData, why: String = "") -> Int? {
        let cos = boardCompanies(s, key: key)
        guard !cos.isEmpty else { return nil }
        let b0 = board(s, key: key)
        if s.week - b0["last"].int < 2 && why.isEmpty { return nil }
        let items = agendaItems(s, key: key, cos: cos, data: data)
        guard !items.isEmpty else { return nil }
        let cur = playerCurrency(s, data)
        let rows: [JSONValue] = cos.map { c in
            let a = c.monthlyHistory.last, b = c.monthlyHistory.dropLast().last
            return .object(["id": .number(Double(c.id)), "name": .string(c.name), "rev": .number(a?.revenue ?? 0), "prof": .number(a?.profit ?? 0), "prev": .number(b?.profit ?? 0), "cash": .number(jsRound(c.cash))])
        }
        let title = why.isEmpty ? "Meeting you called" : "Regular board meeting"
        let att = voters(s, key: key).prefix(8).map { JSONValue.string("\($0.name), \($0.title)") }
        var m: [String: JSONValue] = ["id": .number(Double(s.makeID())), "w": .number(Double(s.week)), "rows": .array(rows), "items": .array(items), "ex": .array([]), "why": .string(why),
                                      "title": .string(title), "att": .array(att), "st": ""]
        if Headquarters.rightHand(s) != nil {
            m["lh"] = .string("Start with this: \(items[0]["text"].string)" + (items.count > 1 ? " The rest can wait a week." : ""))
        }
        var b = board(s, key: key)
        b["mts"] = .array(([.object(m)] + b["mts"].array).prefix(keptMeetings).map { $0 })
        b["last"] = .number(Double(s.week))
        writeBoard(&s, key: key, b)
        let rev = rows.reduce(0) { $0 + $1["rev"].double }, pr = rows.reduce(0) { $0 + $1["prof"].double }
        s.addMessage(kind: "info", from: "Board of \(boardName(s, key: key))", title: "Board meeting · \(boardName(s, key: key))",
                     body: "Revenue last month \(cur.short(rev)), profit \(cur.short(pr)). \(items.count) \(items.count == 1 ? "point" : "points") to decide, first: \(items[0]["text"].string)",
                     companyID: cos[0].id, tone: "n", status: "done")
        return m["id"]!.int
    }

    /// `done` and `followUp` carry the outcome text (`followUp` also means a follow-up job was recorded); `refused` leaves the point on the agenda.
    public enum ItemResult: Equatable, Sendable { case done(String), declined, gone, followUp(String), refused(String) }

    /// Approve or reject a point. Approving carries the point out through the game's own systems (see `applyItem`); when that cannot be done
    /// the point stays on the agenda with the reason. Either answer is kept as the outcome and the point is not raised again for a while.
    /// Original: `ACT.bd12yes`, `ACT.bd12no`.
    @discardableResult
    public static func decideMeetingItem(_ s: inout GameState, key: String, meetingID: Int, item idx: Int, approve: Bool, data: GameData, marketing: MarketingTables? = nil) -> ItemResult {
        var b = board(s, key: key)
        let mts = b["mts"].array
        guard let k = mts.firstIndex(where: { $0["id"].int == meetingID }), mts[k]["items"].array.indices.contains(idx), mts[k]["items"][idx]["st"].string.isEmpty,
              mts[k]["st"].string.isEmpty else { return .gone }
        let it = mts[k]["items"][idx]
        var effect: ItemEffect = .ok("Declined.", followUp: nil, check: nil)
        if approve {
            effect = applyItem(&s, item: it, data: data, marketing: marketing)
            if case .refused(let why) = effect { return .refused(why) }
            b = board(s, key: key)   // the effect may have touched the board (a dismissed manager, a seat)
        }
        let who = it["who"].isNull ? -1 : it["who"].int
        var seatsJSON = b["seats"].array
        if let si = seatsJSON.firstIndex(where: { $0["id"].int == who }) {
            if approve { seatsJSON[si]["ok"] = .number(seatsJSON[si]["ok"].double + 1); seatsJSON[si]["mood"] = .number(min(100, (seatsJSON[si]["mood"].isNull ? 60 : seatsJSON[si]["mood"].double) + 4)) }
            else {
                seatsJSON[si]["no"] = .number(seatsJSON[si]["no"].double + 1)
                let mo = max(0, (seatsJSON[si]["mood"].isNull ? 60 : seatsJSON[si]["mood"].double) - 6)
                seatsJSON[si]["mood"] = .number(mo)
                if seatsJSON[si]["kind"].string == "adv" && mo < 25, var n = s.people[who] {
                    n.employerID = 0; s.people[who] = n
                    seatsJSON.remove(at: si)
                    s.addMessage(kind: "info", from: n.name, title: "Leaving the board", body: "You rarely take my advice, so I am stepping down from the board of \(boardName(s, key: key)).", tone: "bad", status: "done")
                }
            }
        }
        b["seats"] = .array(seatsJSON)
        var outcome = "Declined."
        var follow: (String, String?)? = nil
        if approve, case .ok(let text, let fu, let chk) = effect { outcome = text; if let fu { follow = (fu, chk) } }
        recordDecision(&b, meeting: k, item: idx, status: approve ? "yes" : "no", outcome: outcome, week: s.week, quiet: approve ? approvedQuietWeeks : declinedQuietWeeks)
        writeBoard(&s, key: key, b)
        guard approve else { return .declined }
        if let (text, chk) = follow { addFollowUp(&s, key: key, text: text, companyID: it["co"].int, check: chk); return .followUp(outcome) }
        return .done(outcome)
    }
    static func dismissForBoard(_ s: inout GameState, companyID: Int, data: GameData) { fire(&s, companyID: companyID, data: data) }

    // MARK: Emergencies

    public struct EmergencyKind: Sendable { public var title: String; public var options: [(String, String)] }
    public static let emergencyKinds: [String: EmergencyKind] = [
        "drop": EmergencyKind(title: "Revenue fell sharply", options: [("Cut prices one step", "price-"), ("Marketing push, +50%", "mkt+"), ("Wait and watch", "wait")]),
        "cash": EmergencyKind(title: "Cash is running out", options: [("Move money in from you", "cashin"), ("Stop all marketing", "mkt0"), ("Wait and watch", "wait")]),
        "mgr": EmergencyKind(title: "The manager has left", options: [("Find a new manager now", "hire"), ("Run it yourself, 20 h", "self"), ("Wait and watch", "wait")]),
        "loss": EmergencyKind(title: "Three months of losses", options: [("Put it up for sale", "sell"), ("Cut costs: stop marketing", "mkt0"), ("Give it three more months", "wait")]),
        "stock": EmergencyKind(title: "Selling out again and again", options: [("Order plenty from now on", "stock"), ("Give stock to the assistant", "asst"), ("Wait and watch", "wait")]),
        "rating": EmergencyKind(title: "Reviews are falling fast", options: [("Train the staff", "course"), ("Raise pay 5%", "raise"), ("Wait and watch", "wait")]),
    ]

    /// Carry out one emergency answer. Original: `doEmg`. Returns "hire" when the player now has to pick a manager.
    @discardableResult
    static func doEmergency(_ s: inout GameState, companyID: Int, code: String, data: GameData) -> String {
        guard let i = s.companyIndex(companyID) else { return "" }
        let co = s.companies[i]
        let chain = Chains.chain(s, of: co)
        let cur = World(state: s, data: data).currency(co)
        switch code {
        case "price-":
            if chain != nil { Chains.setStoreRule(&s, companyID: companyID, rule: .priceSteps(max(-1, co.value("off")["price"].double - 1))) } else { s.companies[i].priceLevel = max(-3, co.priceLevel - 1) }
        case "mkt+":
            var m = co.value("mkt")
            for (k, v) in m.object { m[k]["b"] = .number(jsRound(v["b"].double * 1.5)) }
            s.companies[i].set("mkt", m)
        case "mkt0": s.companies[i].set("mkt", .object([:]))
        case "cashin":
            let x = cur.roundedStep(max(cur.scaledPrice(20000), abs(co.num("wkD")) * 6), about: 1000)
            if s.cash >= x { Payments.injectCash(&s, companyID: companyID, amount: x) }
        case "hire": return "hire"
        case "self": s.companies[i].ownerHours = max(co.ownerHours, 20)
        case "sell": listForSale(&s, companyID: companyID)
        case "stock":
            if chain != nil { Chains.setStoreRule(&s, companyID: companyID, rule: .ordering(2)) } else { s.companies[i].set("stockPol", 2) }
        case "asst":
            var a = co.value("asst")
            if a["npc"].int != 0 { var d = a["duties"].array.map { $0.string }; if !d.contains("equip") { d = Array(d.suffix(1)) + ["equip"] }; a["duties"] = .array(d.map { .string($0) }); s.companies[i].set("asst", a) }
        case "course":
            Payments.companyPays(&s, companyID: companyID, amount: cur.scaledPrice(4000) * Double(max(1, co.staff.count)), category: "oth", label: "Staff training")
            s.companies[i].quality = min(100, s.companies[i].quality + 4)
        case "raise":
            var staff = s.companies[i].staff
            for k in staff.indices { staff[k].monthlyWage = cur.roundedStep(staff[k].monthlyWage * 1.05, about: 100); staff[k].happyUntilWeek = s.week + 26 }
            s.companies[i].staff = staff
        default: break
        }
        return ""
    }

    /// What your right hand would pick. Original: `lhPick`.
    static func rightHandPick(_ s: GameState, kind: String, co: Company, lh: Person?) -> Int {
        var best = 0
        let hist = co.monthlyHistory
        switch kind {
        case "drop": best = co.awareness < 40 ? 1 : 0
        case "cash": best = s.cash > abs(co.num("wkD")) * 8 ? 0 : 1
        case "mgr": best = co.staff.count >= 3 ? 0 : 1
        case "loss": best = hist.suffix(6).filter { $0.profit < 0 }.count >= 5 ? 0 : 1
        case "stock": best = co.value("asst")["npc"].int != 0 ? 1 : 0
        case "rating": best = co.staff.contains { $0.noticeWeeks > 0 } ? 1 : 0
        default: break
        }
        if let n = lh, HashedRandom.first("lhp:\(co.id):\(kind):\(s.week)") > 0.5 + leadership(n) * 0.5 { best = (best + 1) % 2 }
        return best
    }

    /// A problem at a company. Someone above the store deals with it first; otherwise the board meets (or, without a board, you are asked).
    /// Original: `emergency`.
    static func emergency(_ s: inout GameState, companyID: Int, kind: String, why: String, data: GameData) {
        guard let ci = s.companyIndex(companyID), let E = emergencyKinds[kind] else { return }
        var co = s.companies[ci]
        var emg = co.value("emg12")
        if !emg[kind].isNull && Double(s.week) - emg[kind].double < 6 { return }
        let lh = Headquarters.rightHand(s).flatMap { s.people[$0.personID] }
        let pk = rightHandPick(s, kind: kind, co: co, lh: lh)
        if handleBelow(&s, companyID: companyID, kind: kind, why: why, pick: pk, data: data) {
            emg[kind] = .number(Double(s.week)); s.companies[ci].set("emg12", emg)
            if kind == "mgr" { s.companies[ci].set("mgr12", s.companies[ci].managerID.map { .number(Double($0)) } ?? .null) }
            return
        }
        co = s.companies[ci]
        let key = boardKey(s, co)
        if !boardActive(s, key: key) {
            let mg = co.managerID.flatMap { s.people[$0] }
            if mg == nil && kind != "mgr" { return }
            emg[kind] = .number(Double(s.week)); s.companies[ci].set("emg12", emg)
            s.addMessage(kind: "ask", from: mg?.name ?? co.name, title: "\(E.title) at \(co.name)", body: why + (mg != nil ? "\nWhat do you want me to do?" : ""), companyID: companyID, tone: "bad", status: "open",
                         options: E.options.map { .option($0.0) }, action: "emg37", data: .object(["kind": .string(kind)]), expiresWeek: s.week + 2)
            return
        }
        emg[kind] = .number(Double(s.week)); s.companies[ci].set("emg12", emg)
        var votes: [JSONValue] = []
        for v in voters(s, key: key) {
            var p = v.type == "lh" ? rightHandPick(s, kind: kind, co: co, lh: lh) : v.type == "cfo" ? (kind == "loss" ? 0 : kind == "cash" ? 1 : 2) : v.type == "mkt" ? (kind == "drop" ? 1 : 2) : 0
            if HashedRandom.first("mv:\(v.id):\(kind):\(s.week)") < 0.15 { p = Int(HashedRandom.first("mv2:\(v.id):\(s.week)") * Double(E.options.count)) % E.options.count }
            votes.append(.object(["id": v.personID.map { .number(Double($0)) } ?? .null, "name": .string(v.name), "t": .string(v.title), "pick": .number(Double(p)), "lh": .bool(v.type == "lh")]))
        }
        let id = s.makeID()
        let lhVote = votes.first { $0["lh"].bool }
        var m: [String: JSONValue] = ["id": .number(Double(id)), "w": .number(Double(s.week)), "emg": true, "kind": .string(kind), "co": .number(Double(companyID)), "title": .string("\(E.title) · \(co.name)"),
                                      "why": .string(why), "votes": .array(votes), "opts": .array(E.options.map { .string($0.0) }), "st": .string("")]
        if let l = lhVote { m["lhPick"] = l["pick"] }
        var b = board(s, key: key)
        b["mts"] = .array(([.object(m)] + b["mts"].array).prefix(keptMeetings).map { $0 })
        writeBoard(&s, key: key, b)
        let tally = E.options.indices.map { i in votes.filter { $0["pick"].int == i }.count }
        let body = why + (lhVote != nil && lh != nil ? "\n\(lh!.name) (your right hand): \(E.options[lhVote!["pick"].int].0)." : "")
            + (votes.isEmpty ? "" : "\nBoard: " + E.options.enumerated().map { "\($0.element.0) \(tally[$0.offset])" }.joined(separator: " · "))
        s.addMessage(kind: "ask", from: "Emergency board meeting", title: "\(E.title) at \(co.name)", body: body, companyID: companyID, tone: "bad", status: "open",
                     options: E.options.map { .option($0.0) }, action: "emg12", data: .object(["k": .string(key), "id": .number(Double(id))]), expiresWeek: s.week + 2)
    }

    /// The player (or the inbox) answers an emergency. Returns "hire" when a new manager is needed.
    @discardableResult
    public static func pickEmergency(_ s: inout GameState, key: String, meetingID: Int, option idx: Int, by who: String = "you", data: GameData) -> String? {
        var b = board(s, key: key)
        var mts = b["mts"].array
        guard let k = mts.firstIndex(where: { $0["id"].int == meetingID }), mts[k]["emg"].bool, mts[k]["st"].string.isEmpty || mts[k]["st"].string == "late",
              let E = emergencyKinds[mts[k]["kind"].string], E.options.indices.contains(idx) else { return nil }
        mts[k]["st"] = .string(who); mts[k]["pickI"] = .number(Double(idx))
        var L = b["seats"].array
        for v in mts[k]["votes"].array { if let si = L.firstIndex(where: { $0["id"].int == v["id"].int && !v["id"].isNull }) {
            if v["pick"].int == idx { L[si]["ok"] = .number(L[si]["ok"].double + 1) } else { L[si]["no"] = .number(L[si]["no"].double + 1); L[si]["mood"] = .number(max(0, (L[si]["mood"].isNull ? 60 : L[si]["mood"].double) - 4)) } } }
        b["mts"] = .array(mts); b["seats"] = .array(L)
        writeBoard(&s, key: key, b)
        // the inbox message for it is done
        if let mi = s.inbox.firstIndex(where: { $0.actionID == "emg12" && $0.value("data")["id"].int == meetingID && $0.status == "open" }) {
            s.inbox[mi].set("status", "done"); s.inbox[mi].set("pick", idx); s.inbox[mi].isRead = true
        }
        return doEmergency(&s, companyID: mts[k]["co"].int, code: E.options[idx].1, data: data)
    }

    /// Answers to the messages "emg12" (a board meeting), "emg37" (a manager without a board asks you), "org56" and "cpx56" and "mfind11".
    public static func handlesAnswer(_ action: String) -> Bool { ["emg12", "emg37", "org56", "cpx56", "mfind11", "mprop"].contains(action) }
    public static func answerGroup(_ s: inout GameState, message m: Message, option idx: Int, data: GameData, context fc: FinanceContext, marketing: MarketingTables) {
        let d = m.value("data")
        switch m.actionID {
        case "emg12": _ = pickEmergency(&s, key: d["k"].string, meetingID: d["id"].int, option: idx, data: data)
        case "emg37":
            if let E = emergencyKinds[d["kind"].string], E.options.indices.contains(idx) { doEmergency(&s, companyID: m.companyID, code: E.options[idx].1, data: data) }
        case "org56": if idx == 0 { runOrganisation(&s, d, data: data, context: fc) }
        case "mprop": answerProposal(&s, message: m, option: idx, data: data, marketing: marketing)
        case "cpx56": if idx == 0, s.company(d["co"].int) != nil { Chains.setStoreRule(&s, companyID: d["co"].int, rule: .priceSteps(d["v"].double)) }
        case "mfind11":
            guard idx == 0, let ci = s.companyIndex(m.companyID), s.companies[ci].managerID == nil, let n = s.people[d["n"].int] else { return }
            if hire(&s, personID: n.id, companyID: m.companyID, monthlyWage: max(1, d["w"].double), data: data) != .ok {
                s.addMessage(kind: "info", from: n.name, title: "Changed my mind", body: "Sorry, I took another job.", companyID: m.companyID, tone: "bad", status: "done")
            }
        default: break
        }
    }

    // MARK: Weekly: emergencies, regular meetings, the secretary, your right hand

    /// Original: `emgWeek`, `seatsWeek`, `ownersWeek`.
    static func boardsWeekly(_ s: inout GameState, data: GameData) {
        // revenue history, cash change and the signs of trouble
        for i in s.companies.indices {
            let co0 = s.companies[i]
            guard co0.status == .open, co0.type != "hold", !co0.value("lastW").isNull else { continue }
            var rw = co0.value("rw12").array.map { $0.double }
            rw.append(jsRound(co0.value("lastW")["rev"].double)); rw = Array(rw.suffix(10))
            s.companies[i].set("rw12", .array(rw.map { .number($0) }))
            let wkD = co0.cash - (co0.value("cashPrev").isNull ? co0.cash : co0.num("cashPrev"))
            s.companies[i].set("wkD", wkD); s.companies[i].set("cashPrev", co0.cash)
            let co = s.companies[i]
            let cur = World(state: s, data: data).currency(co)
            let age = s.week - (co.openedWeek ?? co.foundedWeek)
            if rw.count >= 6 && age >= 8 {
                let avg = rw[(rw.count - 6)..<(rw.count - 2)].reduce(0, +) / 4, last2 = Array(rw.suffix(2))
                if avg > cur.scaledPrice(2000) && last2.allSatisfy({ $0 < avg * 0.75 }) {
                    emergency(&s, companyID: co.id, kind: "drop", why: "Revenue the last two weeks: \(cur.display(last2[0])) and \(cur.display(last2[1])), against about \(cur.display(jsRound(avg))) a week before.", data: data)
                }
            }
            if wkD < 0 && co.cash > 0 && co.cash / -wkD < 4 {
                emergency(&s, companyID: co.id, kind: "cash", why: "Cash \(cur.display(jsRound(co.cash))), and the company burns about \(cur.display(jsRound(-wkD))) a week. That is under four weeks left.", data: data)
            }
            if !co.value("mgr12").isNull && co.managerID == nil && !co.staff.isEmpty {
                emergency(&s, companyID: co.id, kind: "mgr", why: "\(s.people[co.value("mgr12").int]?.name ?? "The manager") is gone. \(co.staff.count) staff have no one in charge.", data: data)
            }
            s.companies[i].set("mgr12", co.managerID.map { .number(Double($0)) } ?? .null)
            if GameCalendar.isMonthEnd(week: s.week) {
                let H = Array(co.monthlyHistory.suffix(3))
                if age >= 26 && H.count == 3 && H.allSatisfy({ $0.profit < 0 }) {
                    emergency(&s, companyID: co.id, kind: "loss", why: "Losses: \(H.map { cur.display(jsRound($0.profit)) }.joined(separator: ", ")).", data: data)
                }
            }
            let so = co.value("dlast")["so"].double
            let so12 = so >= 3 ? co.int("so12") + 1 : 0
            s.companies[i].set("so12", so12)
            if so12 >= 2 { emergency(&s, companyID: co.id, kind: "stock", why: "Sold out \(Int(so)) days last week, about \(co.value("dlast")["lost"].int) sales lost.", data: data) }
            let r = Pricing.rating(co)
            let rth = Array((co.value("rth12").array.map { $0.double } + [r]).suffix(5))
            s.companies[i].set("rth12", .array(rth.map { .number($0) }))
            if rth.count >= 5 && rth[0] - r >= 0.4 && co.int("rvN") >= 20 {
                emergency(&s, companyID: co.id, kind: "rating", why: "The rating fell from \(String(format: "%.1f", rth[0])) to \(String(format: "%.1f", r)) in a month.", data: data)
            }
        }
        sweepBoards(&s)
        // meetings nobody answered; right hand answers what you left waiting
        for key in boardKeys(s) {
            var b = board(s, key: key)
            var mts = b["mts"].array, changed = false
            for k in mts.indices where mts[k]["emg"].bool && mts[k]["st"].string.isEmpty && s.week - mts[k]["w"].int >= 3 { mts[k]["st"] = "late"; changed = true }
            if changed { b["mts"] = .array(mts); writeBoard(&s, key: key, b) }
        }
        if let lh = Headquarters.rightHand(s), lh.decidesForYou {
            for m in s.inbox where m.status == "open" && m.actionID == "emg12" && s.week >= m.week + 1 {
                let d = m.value("data")
                guard let mt = meeting(s, key: d["k"].string, id: d["id"].int), mt.status.isEmpty, let pick = mt.rightHandPick else { continue }
                _ = pickEmergency(&s, key: d["k"].string, meetingID: mt.id, option: pick, by: "lh", data: data)
                s.note("\(s.people[lh.personID]?.name ?? "Your right hand") decided for you at \(s.company(m.companyID)?.name ?? "a company"): \(mt.options[pick]).", tone: "n", companyID: m.companyID)
            }
        }
        // seats at work: an HR manager talks people out of leaving; the secretary chases open points
        for i in s.companies.indices where s.companies[i].status == .open {
            let key = boardKey(s, s.companies[i])
            let st = seats(s, key: key)
            s.companies[i].set("brdLaw", st.contains { $0.role == "legal" })
            s.companies[i].set("brdMkt", st.contains { $0.role == "mkt" })
            if st.contains(where: { $0.role == "hr" }) {
                var staff = s.companies[i].staff
                for k in staff.indices where staff[k].noticeWeeks > 0 && s.random.next() < 0.15 { staff[k].noticeWeeks = 0; staff[k].happyUntilWeek = s.week + 12 }
                s.companies[i].staff = staff
            }
        }
        for key in boardKeys(s) {
            guard let sec = seats(s, key: key).first(where: { $0.role == "sec" }), let sn = s.people[sec.id] else { continue }
            var b = board(s, key: key)
            var mts = b["mts"].array, changed = false
            for k in mts.indices where !mts[k]["emg"].bool && mts[k]["rem13"].isNull && s.week - mts[k]["w"].int >= 1 {
                let open = mts[k]["items"].array.filter { !$0["act"].string.isEmpty && $0["st"].string.isEmpty }
                if open.isEmpty { continue }
                mts[k]["rem13"] = 1; changed = true
                s.addMessage(kind: "info", from: sn.name, title: "\(open.count) board points still open at \(boardName(s, key: key))", body: open.map { "• \($0["text"].string)" }.joined(separator: "\n"), tone: "n", status: "done")
            }
            if changed { b["mts"] = .array(mts); writeBoard(&s, key: key, b) }
        }
        ownersWeek(&s)
        if GameCalendar.isMonthEnd(week: s.week) { boardsMonthly(&s, data: data) }
        briefing(&s, data: data)
    }

    /// Fees of the seats, and regular meetings. Original: `boardsWeek`.
    static func boardsMonthly(_ s: inout GameState, data: GameData) {
        let mi = GameCalendar.monthIndex(week: s.week) % 12
        for key in boardKeys(s) {
            let b = board(s, key: key), cos = boardCompanies(s, key: key)
            guard !cos.isEmpty else { continue }
            let fee = seats(s, key: key).reduce(0) { $0 + $1.monthlyFee }
            if fee > 0 { for c in cos { Payments.companyPays(&s, companyID: c.id, amount: fee / Double(cos.count), category: "oth") } }
            let freq = b["freq"].isNull ? 4 : b["freq"].int
            if boardActive(s, key: key), b["mode"].string == "regular", freq != 13 || mi % 3 == 2, s.week - (b["last"].isNull ? -99 : b["last"].int) >= 2,
               !seats(s, key: key).isEmpty || Headquarters.rightHand(s) != nil { holdBoardMeeting(&s, key: key, data: data, why: "Regular meeting") }
        }
    }

    /// The right hand's briefing. Original: `briefing`.
    static func briefing(_ s: inout GameState, data: GameData) {
        guard let lh = Headquarters.rightHand(s), lh.briefing != "off", let n = s.people[lh.personID] else { return }
        if lh.briefing == "month" && !GameCalendar.isMonthEnd(week: s.week) { return }
        let open = s.inbox.filter { $0.status == "open" }.count
        let live = s.companies.filter { $0.status == .open }
        let losers = live.filter { $0.num("wkD") < 0 }.prefix(3).map { $0.name }
        let so = live.filter { $0.value("dlast")["so"].double > 0 }.prefix(2).map { $0.name }
        let cur = playerCurrency(s, data)
        let lines = [open > 0 ? "\(open) thing\(open > 1 ? "s" : "") wait\(open > 1 ? "" : "s") for you." : "Nothing waits for you.",
                     losers.isEmpty ? "Every company made money last week." : "Losing money last week: \(losers.joined(separator: ", ")).",
                     so.isEmpty ? "" : "Sold out: \(so.joined(separator: ", ")).", "Your cash: \(cur.display(jsRound(s.cash)))."].filter { !$0.isEmpty }
        s.addMessage(kind: "info", from: n.name, title: "\(lh.briefing == "week" ? "Weekly" : "Monthly") briefing", body: lines.joined(separator: "\n"), tone: "n", status: "done")
    }

    /// Big owners take a board seat as director. Original: `ownersWeek`.
    static func ownersWeek(_ s: inout GameState) {
        for key in boardKeys(s) where boardActive(s, key: key) {
            for x in holders(s, key: key) where x.h["pct"].double >= 20 && x.h["dir15"].isNull {
                guard seats(s, key: key).filter({ $0.role == "director" }).count < 4, let ci = s.companyIndex(x.co.id) else { continue }
                var H = s.companies[ci].value("holders").array
                guard let hi = H.firstIndex(where: { $0["name"].string == x.h["name"].string }) else { continue }
                var npcID = H[hi]["npc"].isNull ? 0 : H[hi]["npc"].int
                if npcID == 0 || s.people[npcID] == nil {
                    var p = Person(raw: [:]); p.id = s.makeID(); p.name = x.h["name"].string; p.age = 50; p.role = "manager"
                    p.set("stats", .object(["ops": 60, "people": 60, "sales": 60, "fin": 60, "risk": 60, "ethic": 60])); s.people[p.id] = p; npcID = p.id
                    H[hi]["npc"] = .number(Double(npcID))
                }
                H[hi]["dir15"] = 1
                s.companies[ci].set("holders", .array(H))
                var n = s.people[npcID]!
                let wasHired = n.employerID != 0
                if !wasHired { n.employerID = -4; s.people[npcID] = n }
                addSeat(&s, boardKey: key, seat: ["id": .number(Double(npcID)), "kind": .string(wasHired ? "exec" : "adv"), "r": "director", "t": "Director", "owner": true])
                s.addMessage(kind: "info", from: x.h["name"].string, title: "Taking a board seat at \(boardName(s, key: key))",
                             body: "With \(Int(jsRound(x.h["pct"].double)))% of the shares I want a say. I will sit on the board as a director.", companyID: x.co.id, tone: "n", status: "done")
            }
        }
    }

    // MARK: Meetings with managers

    public static let meetingGoals: [(key: String, label: String)] = [("review", "Go through the results"), ("growth", "Push for growth"), ("costs", "Cut costs"),
                                                                       ("quality", "Raise quality"), ("morale", "Boost morale"), ("pay", "Talk about pay")]
    public static let meetingTones: [(key: String, label: String)] = [("casual", "A casual chat"), ("serious", "A serious talk"), ("final", "A final warning")]

    public enum MeetingResult: Equatable, Sendable { case ok(Int), wait, none }

    /// Meet one manager (`companyID`) or all of them (nil). Companies met in the last three weeks are skipped. Original: `callMeeting`, `meetOne`.
    public static func callMeeting(_ s: inout GameState, companyID: Int?, goal: String, tone: String, data: GameData, marketing: MarketingTables) -> MeetingResult {
        let cos = s.companies.filter { c in
            c.status.isLive && c.managerID != nil && s.people[c.managerID!] != nil && (companyID == nil || c.id == companyID)
        }
        if cos.isEmpty { return .none }
        let fresh = cos.filter { !CounterpartMeeting.isCoolingDown(lastWeek: $0.value("meetW").isNull ? nil : $0.num("meetW"), now: s.week, weeks: 3) }
        if fresh.isEmpty { return .wait }
        for c in fresh { meetOne(&s, companyID: c.id, goal: goal, tone: tone, data: data, marketing: marketing) }
        return .ok(fresh.count)
    }

    static func quietAsk(_ s: inout GameState, _ id: Int, _ key: String, data: GameData, marketing: MarketingTables) {
        let n0 = s.inbox.count
        if let i = s.companyIndex(id) { s.companies[i].set("askW", .null) }
        _ = ask(&s, companyID: id, key: key, data: data, marketing: marketing)
        if s.inbox.count > n0 { s.inbox.removeFirst(s.inbox.count - n0) }
    }

    static func meetOne(_ s: inout GameState, companyID: Int, goal: String, tone: String, data: GameData, marketing: MarketingTables) {
        guard let ci = s.companyIndex(companyID), let mid = s.companies[ci].managerID, let n = s.people[mid] else { return }
        let t = tone == "casual" ? 0 : tone == "serious" ? 1 : 2
        let steps = t > 0 ? 2 : 1
        let co = s.companies[ci]
        let cur = World(state: s, data: data).currency(co)
        s.companies[ci].set("mood", mood(co)); s.companies[ci].set("meetW", s.week)
        func run(_ k: String) { for _ in 0..<steps { quietAsk(&s, companyID, k, data: data, marketing: marketing) } }
        var say = ""
        switch goal {
        case "review":
            let m = co.monthlyHistory.last
            let rev = m?.revenue ?? 0, pr = m?.profit ?? 0
            let u = co.value("lastW")["util"]
            say = "Last month we took in \(cur.short(rev)) and \(pr >= 0 ? "made \(cur.short(pr))" : "lost \(cur.short(-pr))"). " + (u.isNull ? "" : "We are running at about \(Int(jsRound(u.double * 100)))% of what we can deliver. ") + (pr < 0 ? "I know it needs to turn around." : "I will keep it on track.")
        case "growth":
            run("mkt_more"); say = "Understood. I will push harder for customers" + (t > 0 ? " and I know you expect results" : "") + ". It will cost more in marketing first."
            if t == 2 { s.companies[ci].priceLevel = max(-2, s.companies[ci].priceLevel - 1) }
        case "costs":
            run("save"); if t > 0 { run("mkt_less") }; if t == 2 { quietAsk(&s, companyID, "cut", data: data, marketing: marketing) }
            say = t == 2 ? "I will cut where I can, including staff. Quality may suffer." : "I will look for savings without hurting the service."
        case "quality": run("quality"); say = "I will spend more on upkeep and standards. Costs go up a little, complaints should go down."
        case "morale":
            s.companies[ci].set("mood", min(100, mood(s.companies[ci]) + (t == 0 ? 10 : 4)))
            say = t == 2 ? "I would rather hear that in a different way, but I will try." : "Thank you. It means something to the team to hear that."
        case "pay":
            s.companies[ci].managerMonthlyWage = t == 2 ? jsRound(co.managerMonthlyWage * 0.95) : jsRound(co.managerMonthlyWage * (t == 1 ? 1.03 : 1.05))
            say = t == 2 ? "A pay cut. I will remember that." : "Thank you, that is fair."
            s.companies[ci].set("mood", min(100, mood(s.companies[ci]) + (t == 2 ? -15 : 8)))
        default: break
        }
        if t == 1 { s.companies[ci].set("mood", mood(s.companies[ci]) - 3) }
        if t == 2 { s.companies[ci].set("mood", mood(s.companies[ci]) - 10) }
        var quit = false
        if t == 2 && mood(s.companies[ci]) < 30 && s.random.chance(0.3) { quit = true; resign(&s, companyIndex: ci, why: "after the final warning I do not see a future here") }
        s.addMessage(kind: "info", from: n.name, title: quit ? "I resign" : "After the meeting: \(co.name)", body: quit ? "After that meeting I cannot continue. I am handing in my notice." : "\(firstName(n.name)): \(say)",
                     companyID: co.id, tone: quit ? "bad" : "n", status: "done")
    }

    // MARK: The data analyst's report

    public struct AnalystLine: Equatable, Sendable { public var companyID: Int; public var name: String; public var lines: [String]; public var history: [Double] }

    /// A report from your data analyst on one company or all (nil). Needs a data analyst at the main office. Original: `analystReport`.
    @discardableResult
    public static func analystReport(_ s: inout GameState, companyID: Int?, data: GameData) -> [AnalystLine]? {
        guard Headquarters.has(s, "ana") else { return nil }
        let cos = s.companies.filter { $0.status == .open && (companyID == nil || $0.id == companyID) }
        guard !cos.isEmpty else { return nil }
        var out: [AnalystLine] = []
        for co in cos {
            let h = co.value("trf").array.map { $0.double }
            var l: [String] = []
            if h.count >= 6 {
                let a = h.suffix(4).reduce(0, +) / 4, rest = Array(h.suffix(8).prefix(max(0, min(4, h.count - 4))))
                let b = rest.isEmpty ? 0 : rest.reduce(0, +) / Double(rest.count)
                if b > 0 { l.append("Sales over the last four weeks are \(a >= b ? "up" : "down") \(Int(jsRound(abs(a / b - 1) * 100)))% on the four before.") }
            }
            if let u = co.value("lastW")["util"].isNull ? nil : co.value("lastW")["util"].double {
                l.append(u > 0.95 ? "We are at the limit of what we can deliver and turn people away." : u < 0.5 ? "We use less than half our capacity." : "We use about \(Int(jsRound(u * 100)))% of our capacity.")
            }
            if let bd = data.catalog[co.type] {
                let c = CapacityModel.compute(co, bd, World(state: s, data: data))
                if let bot = c.bottleneck { l.append("The weakest link is \(bot.label).") }
            }
            if h.count >= 4, let last = h.last, last > 0 {
                let e = h.suffix(4).reduce(0, +) / 4
                l.append("In two months I expect weekly sales \(e >= last ? "around \(Int(jsRound((e / last - 1) * 100)))% higher" : "around \(Int(jsRound((1 - e / last) * 100)))% lower").")
            }
            out.append(AnalystLine(companyID: co.id, name: co.name, lines: l, history: h))
        }
        var reports = s.rest["areports"]?.array ?? []
        reports.insert(.object(["w": .number(Double(s.week)), "who": companyID.map { .number(Double($0)) } ?? "all", "items": .array(out.map { .object(["co": .number(Double($0.companyID)), "name": .string($0.name), "lines": .array($0.lines.map { .string($0) })]) })]), at: 0)
        s.rest["areports"] = .array(Array(reports.prefix(6)))
        s.addMessage(kind: "info", from: Headquarters.staff(s).first { $0["role"].string == "ana" }?["name"].string ?? "Data analyst", title: companyID == nil ? "Report: all companies" : "Report: \(cos[0].name)",
                     body: out.map { "\($0.name): \($0.lines.joined(separator: " "))" }.joined(separator: "\n"), tone: "n", status: "done")
        return out
    }

    // MARK: A manager nobody meets slips

    /// How much worse a left-alone manager works, 0 to 0.12. A boss above the manager halves the pace. Original: `OA59.drift`.
    public static func attentionDrift(_ co: Company, week: Int) -> Double {
        guard co.managerID != nil, co.status == .open, co.type != "hold" else { return 0 }
        let lastMeeting = co.value("meetW").isNull ? -1e9 : co.num("meetW")
        let started = co.value("mgrW0").isNull ? Double(co.openedWeek ?? 0) : co.num("mgrW0")
        let w = Double(week) - max(lastMeeting, started) - 8
        return w <= 0 ? 0 : min(0.12, w * 0.005 * (co.flag("boss56") ? 0.5 : 1))
    }
    public static func weeksSinceMeeting(_ co: Company, week: Int) -> Int {
        let lastMeeting = co.value("meetW").isNull ? -1e9 : co.num("meetW")
        let started = co.value("mgrW0").isNull ? Double(co.openedWeek ?? 0) : co.num("mgrW0")
        return week - Int(max(lastMeeting, started))
    }
    /// Companies whose manager is due a meeting.
    public static func managersDueMeeting(_ s: GameState) -> [Company] { s.companies.filter { attentionDrift($0, week: s.week) > 0 || ($0.managerID != nil && $0.status == .open && weeksSinceMeeting($0, week: s.week) >= 8) } }
}
