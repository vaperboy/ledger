import Foundation
import GameCore
import Countries
import Employees
import Finance

extension ManagerModel {
    public struct MeetingRow: Equatable, Sendable { public var companyID: Int; public var name: String; public var revenue: Double; public var profit: Double; public var previous: Double; public var cash: Double }
    public struct EmergencyVote: Equatable, Sendable { public var personID: Int?; public var name: String; public var title: String; public var pick: Int; public var isRightHand: Bool }
    public struct BoardMeeting: Identifiable, Equatable, Sendable {
        public var id: Int
        public var week: Int
        public var isEmergency: Bool
        public var title: String
        public var why: String
        public var rows: [MeetingRow]
        public var options: [String]
        public var votes: [EmergencyVote]
        public var rightHandPick: Int?
        public var status: String
        public var picked: Int?
        public var companyID: Int
        public var kind: String
        public var closedWeek: Int? = nil
        public var isOpen: Bool { status.isEmpty }
        public var minutes: [String] {
            guard let p = picked, options.indices.contains(p) else { return [] }
            return ["Decision: \(options[p])" + (status == "lh" ? " (your right hand decided)" : "")]
        }
    }
    public static func meetings(_ s: GameState, key: String) -> [BoardMeeting] {
        board(s, key: key)["mts"].array.filter { $0["emg"].bool }.map { meetingFrom($0) }
    }
    public static func meeting(_ s: GameState, key: String, id: Int) -> BoardMeeting? { meetings(s, key: key).first { $0.id == id } }
    static func meetingFrom(_ m: JSONValue) -> BoardMeeting {
        var x = BoardMeeting(id: m["id"].int, week: m["w"].int, isEmergency: m["emg"].bool, title: m["title"].string, why: m["why"].string,
                     rows: m["rows"].array.map { MeetingRow(companyID: $0["id"].int, name: $0["name"].string, revenue: $0["rev"].double, profit: $0["prof"].double, previous: $0["prev"].double, cash: $0["cash"].double) },
                     options: m["opts"].array.map { $0.string },
                     votes: m["votes"].array.map { EmergencyVote(personID: $0["id"].isNull ? nil : $0["id"].int, name: $0["name"].string, title: $0["t"].string, pick: $0["pick"].int, isRightHand: $0["lh"].bool) },
                     rightHandPick: m["lhPick"].isNull ? nil : m["lhPick"].int, status: m["st"].string, picked: m["pickI"].isNull ? nil : m["pickI"].int, companyID: m["co"].int, kind: m["kind"].string)
        x.closedWeek = m["cw"].isNull ? nil : m["cw"].int
        return x
    }

    static func dismissForBoard(_ s: inout GameState, companyID: Int, data: GameData) { fire(&s, companyID: companyID, data: data) }

    public struct EmergencyKind: Sendable { public var title: String; public var options: [(String, String)] }
    public static let emergencyKinds: [String: EmergencyKind] = [
        "drop": EmergencyKind(title: "Revenue fell sharply", options: [("Cut prices one step", "price-"), ("Marketing push, +50%", "mkt+"), ("Wait and watch", "wait")]),
        "cash": EmergencyKind(title: "Cash is running out", options: [("Move money in from you", "cashin"), ("Stop all marketing", "mkt0"), ("Wait and watch", "wait")]),
        "mgr": EmergencyKind(title: "The manager has left", options: [("Find a new manager now", "hire"), ("Run it yourself, 20 h", "self"), ("Wait and watch", "wait")]),
        "loss": EmergencyKind(title: "Three months of losses", options: [("Put it up for sale", "sell"), ("Cut costs: stop marketing", "mkt0"), ("Give it three more months", "wait")]),
        "stock": EmergencyKind(title: "Selling out again and again", options: [("Order plenty from now on", "stock"), ("Give stock to the assistant", "asst"), ("Wait and watch", "wait")]),
        "rating": EmergencyKind(title: "Reviews are falling fast", options: [("Train the staff", "course"), ("Raise pay 5%", "raise"), ("Wait and watch", "wait")]),
    ]

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

    @discardableResult
    public static func pickEmergency(_ s: inout GameState, key: String, meetingID: Int, option idx: Int, by who: String = "you", data: GameData) -> String? {
        var b = board(s, key: key)
        var mts = b["mts"].array
        guard let k = mts.firstIndex(where: { $0["id"].int == meetingID }), mts[k]["emg"].bool, mts[k]["st"].string.isEmpty || mts[k]["st"].string == "late",
              let E = emergencyKinds[mts[k]["kind"].string], E.options.indices.contains(idx) else { return nil }
        mts[k]["st"] = .string(who); mts[k]["pickI"] = .number(Double(idx))
        b["mts"] = .array(mts)
        writeBoard(&s, key: key, b)
        if let mi = s.inbox.firstIndex(where: { $0.actionID == "emg12" && $0.value("data")["id"].int == meetingID && $0.status == "open" }) {
            s.inbox[mi].set("status", "done"); s.inbox[mi].set("pick", idx); s.inbox[mi].isRead = true
        }
        return doEmergency(&s, companyID: mts[k]["co"].int, code: E.options[idx].1, data: data)
    }

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

    static func boardsWeekly(_ s: inout GameState, data: GameData) {
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
        ownersWeek(&s)
        briefing(&s, data: data)
    }

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
                             body: "With \(Int(saturating: jsRound(x.h["pct"].double)))% of the shares I want a say. I will sit on the board as a director.", companyID: x.co.id, tone: "n", status: "done")
            }
        }
    }

    public struct AnalystLine: Equatable, Sendable { public var companyID: Int; public var name: String; public var lines: [String]; public var history: [Double] }

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
                if b > 0 { l.append("Sales over the last four weeks are \(a >= b ? "up" : "down") \(Int(saturating: jsRound(abs(a / b - 1) * 100)))% on the four before.") }
            }
            if let u = co.value("lastW")["util"].isNull ? nil : co.value("lastW")["util"].double {
                l.append(u > 0.95 ? "We are at the limit of what we can deliver and turn people away." : u < 0.5 ? "We use less than half our capacity." : "We use about \(Int(saturating: jsRound(u * 100)))% of our capacity.")
            }
            if let bd = data.catalog[co.type] {
                let c = CapacityModel.compute(co, bd, World(state: s, data: data))
                if let bot = c.bottleneck { l.append("The weakest link is \(bot.label).") }
            }
            if h.count >= 4, let last = h.last, last > 0 {
                let e = h.suffix(4).reduce(0, +) / 4
                l.append("In two months I expect weekly sales \(e >= last ? "around \(Int(saturating: jsRound((e / last - 1) * 100)))% higher" : "around \(Int(saturating: jsRound((1 - e / last) * 100)))% lower").")
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
    public static func managersDueMeeting(_ s: GameState) -> [Company] { s.companies.filter { attentionDrift($0, week: s.week) > 0 || ($0.managerID != nil && $0.status == .open && weeksSinceMeeting($0, week: s.week) >= 8) } }
}
