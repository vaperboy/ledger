import Foundation
import GameCore
import Countries
import Finance
import Employees

public enum Stories {
    public static let annAction = "st28ann", retAction = "st28ret", lifeAction = "st28life", proAction = "st28pro"
    public static func handlesAnswer(_ action: String) -> Bool { [annAction, retAction, lifeAction, proAction].contains(action) }

    static let juniorRoles: Set<String> = ["helper", "cleaner", "cashier", "waiter", "barista", "housek", "labour", "fworker", "usher", "waiterB", "carwash", "courier", "recept", "groom", "seaman", "farmh", "teller"]

    static func nextRole(_ co: Company, _ m: StaffMember, data: GameData) -> String? {
        guard let bd = data.catalog[co.type] else { return nil }
        let roles = data.catalog.tables.roles
        let w0 = roles[m.role]?.baseMonthlyWage ?? 40000
        let up = bd.standardStaff.map { $0.role }.filter { r in
            guard let b = roles[r]?.baseMonthlyWage else { return false }
            return !juniorRoles.contains(r) && r != m.role && b > w0 * 1.08
        }
        return up.min { (roles[$0]?.baseMonthlyWage ?? 0) < (roles[$1]?.baseMonthlyWage ?? 0) }
    }

    static func roll(_ s: GameState, _ tag: String) -> Double { var h = HashedRandom("\(s.seed):st28:\(tag):\(s.week)"); return h.next() }

    static func mood(_ co: Company) -> Double { co.value("mood").isNull ? 60 : co.num("mood") }
    static func bumpMood(_ s: inout GameState, _ ci: Int, _ d: Double) { s.companies[ci].set("mood", clamp(mood(s.companies[ci]) + d, 0, 100)) }
    static func first(_ name: String) -> String { name.split(separator: " ").first.map(String.init) ?? name }
    static func roleName(_ s: GameState, _ data: GameData, _ role: String) -> String { (data.catalog.tables.roles[role]?.name ?? "worker").lowercased() }

    static func addStory(_ m: inout StaffMember, week: Int, _ text: String) {
        var l = m.value("st28").array
        l.append(.object(["w": .number(Double(week)), "t": .string(text)]))
        if l.count > 20 { l.remove(at: 1) }
        m.set("st28", .array(l))
    }
    static func addStory(_ s: inout GameState, company ci: Int, staff id: Int, _ text: String) {
        guard let k = s.companies[ci].staff.firstIndex(where: { $0.id == id }) else { return }
        var m = s.companies[ci].staff[k]
        addStory(&m, week: s.week, text)
        s.companies[ci].staff[k] = m
    }

    public static func story(_ s: GameState, companyID: Int, staffID: Int) -> [(week: Int, text: String)] {
        guard let m = s.company(companyID)?.staff.first(where: { $0.id == staffID }) else { return [] }
        return m.value("st28").array.reversed().map { ($0["w"].int, $0["t"].string) }
    }
    public static func hall(_ s: GameState) -> [(name: String, text: String, week: Int)] {
        (s.rest["hof28"]?.array ?? []).map { ($0["n"].string, $0["t"].string, $0["w"].int) }
    }

    public static func weekly(_ s: inout GameState, data: GameData) {
        for ci in s.companies.indices where s.companies[ci].status == .open { staffWeek(&s, ci, data: data) }
        quietDefaults(&s, data: data)
        if GameCalendar.year(week: s.week) != GameCalendar.year(week: s.week - 1) { top50(&s, data: data) }
    }

    static func staffWeek(_ s: inout GameState, _ ci: Int, data: GameData) {
        let co0 = s.companies[ci]
        let w = World(state: s, data: data)
        let cur = w.currency(co0)
        var fresh = s.week - (co0.value("sl28").isNull ? -99 : co0.int("sl28")) >= 6
        let teamSize = co0.staff.count
        for id in co0.staff.map({ $0.id }) {
            guard let n = s.people[id], let k = s.companies[ci].staff.firstIndex(where: { $0.id == id }) else { continue }
            var m = s.companies[ci].staff[k]
            let co = s.companies[ci]
            let hired = m.value("w0").isNull ? s.week : m.hiredWeek
            let role = roleName(s, data, m.role)
            if m.value("st28").isNull { m.set("st28", .array([.object(["w": .number(Double(hired)), "t": .string("Joined \(co.name) as \(role)")])])) }
            let y = (s.week - hired) / 52
            if y > m.int("an28") && y >= 1 {
                if y == 1 { m.set("an28", y); addStory(&m, week: s.week, "One year at \(co.name)"); bumpMood(&s, ci, 0.5) }
                else if ![5, 10, 15, 20, 25, 30].contains(y) { m.set("an28", y) }
                else if fresh {
                    m.set("an28", y); fresh = false
                    s.companies[ci].set("sl28", s.week)
                    let party = cur.scaledPrice(4000) + Double(teamSize) * cur.scaledPrice(400)
                    s.addMessage(kind: "ask", from: co.name, title: "\(n.name): \(y) years at \(co.name)",
                                 body: "\(n.name) started here \(y) years ago. The team wants to mark it.", companyID: co.id, tone: "good", status: "open",
                                 options: [.option("A party for the team", "\(cur.display(party)). Everyone remembers it."), .option("A bonus of a month's pay", "\(cur.display(m.monthlyWage))."),
                                           .option("A card and a thank-you", "Free.")],
                                 action: annAction, data: .object(["co": .number(Double(co.id)), "s": .number(Double(id)), "y": .number(Double(y))]), expiresWeek: s.week + 2)
                }
            }
            if juniorRoles.contains(m.role) && y >= 1 && m.value("pr28").isNull && fresh,
               StaffModel.skill(m, person: n, salesRoles: data.catalog.tables.salesRoles) >= 66, roll(s, "pro:\(id)") < 0.04,
               let to = nextRole(co, m, data: data) {
                m.set("pr28", s.week); fresh = false
                s.companies[ci].set("sl28", s.week)
                let wage = roundTo(max(m.monthlyWage * 1.15, ManagerModel.marketWage(s, co, role: to, data: data) * 0.95), step: 100)
                s.addMessage(kind: "ask", from: co.name, title: "Promote \(n.name) to \(roleName(s, data, to))?",
                             body: "\(n.name) started as \(role) \(y) year\(y > 1 ? "s" : "") ago and has learned the job next door. \(first(n.name)) would earn \(cur.display(wage)) a month.",
                             companyID: co.id, tone: "good", status: "open",
                             options: [.option("Promote \(first(n.name))", "Loyal, motivated, and already knows the place."), .option("Not yet", "\(first(n.name)) may look elsewhere.")],
                             action: proAction, data: .object(["co": .number(Double(co.id)), "s": .number(Double(id)), "to": .string(to), "wage": .number(wage)]), expiresWeek: s.week + 3)
            }
            if Double(n.age) + Double(s.week - hired) / 52 >= 67 && m.value("ret28").isNull && fresh {
                m.set("ret28", s.week); fresh = false
                s.companies[ci].set("sl28", s.week)
                s.addMessage(kind: "ask", from: n.name, title: "\(n.name) is retiring",
                             body: "After \(max(1, y)) year\(y > 1 ? "s" : "") at \(co.name), \(first(n.name)) is retiring. How do you say goodbye?", companyID: co.id, tone: "n", status: "open",
                             options: [.option("A farewell party", "\(cur.display(cur.scaledPrice(8000))). The whole team comes."), .option("A gift and a speech", "\(cur.display(cur.scaledPrice(3000)))."), .option("A card", "")],
                             action: retAction, data: .object(["co": .number(Double(co.id)), "s": .number(Double(id)), "y": .number(Double(max(1, y)))]), expiresWeek: s.week + 2)
            }
            let raised = m.num("wl28") > 0 && m.monthlyWage >= m.num("wl28") * 1.04, trained = m.num("crs") > m.num("cr28")
            if (raised || trained) && s.week - (m.value("ty28").isNull ? -99 : m.int("ty28")) > 26 && fresh && roll(s, "ty:\(id)") < 0.5 {
                m.set("ty28", s.week); fresh = false
                s.companies[ci].set("sl28", s.week)
                s.addMessage(kind: "info", from: n.name, title: "A note from \(n.name)",
                             body: raised ? "Thank you for the raise. It came at a good time for my family. I won't forget it." : "Thank you for sending me on the course. I already do the job better.",
                             companyID: co.id, tone: "good")
                addStory(&m, week: s.week, raised ? "Got a raise" : "Took a course")
                bumpMood(&s, ci, 1)
            }
            m.set("wl28", m.monthlyWage); m.set("cr28", m.num("crs"))
            if fresh && teamSize <= 40 && roll(s, "life:\(id)") < 0.0025 {
                let events = [("is getting married", "Married"), ("has become a parent", "Became a parent"), ("bought a first home", "Bought a home")]
                let e = events[min(2, Int(roll(s, "ev:\(id)") * 3))]
                fresh = false
                s.companies[ci].set("sl28", s.week)
                s.addMessage(kind: "ask", from: co.name, title: "\(n.name) \(e.0)", body: "Good news from \(first(n.name)), \(role) at \(co.name).", companyID: co.id, tone: "good", status: "open",
                             options: [.option("Send a gift from the company", "\(cur.display(cur.scaledPrice(1500)))."), .option("Congratulate them", "")],
                             action: lifeAction, data: .object(["co": .number(Double(co.id)), "s": .number(Double(id)), "t": .string(e.1)]), expiresWeek: s.week + 2)
            }
            if let k2 = s.companies[ci].staff.firstIndex(where: { $0.id == id }) { s.companies[ci].staff[k2] = m }
        }
        let co = s.companies[ci]
        if let mid = co.managerID, let mn = s.people[mid], !co.value("mgrW0").isNull {
            let y = (s.week - co.int("mgrW0")) / 52
            if [5, 10, 15, 20].contains(y) && co.int("ma28") < y {
                s.companies[ci].set("ma28", y)
                s.addMessage(kind: "info", from: co.name, title: "\(mn.name): \(y) years running \(co.name)",
                             body: (y >= 10 ? "Few managers stay this long. " : "") + "Under \(first(mn.name)), \(co.name) has become what it is.", companyID: co.id, tone: "good")
                bumpMood(&s, ci, 4)
            }
        }
    }

    public static func answer(_ s: inout GameState, message m: Message, option idx: Int, data: GameData) {
        let d = m.value("data")
        guard let ci = s.companyIndex(d["co"].int), let k = s.companies[ci].staff.firstIndex(where: { $0.id == d["s"].int }) else { return }
        let co = s.companies[ci], st = co.staff[k], id = st.id
        let cur = World(state: s, data: data).currency(co)
        func pay(_ amount: Double, _ cat: String, _ label: String) { Payments.companyPays(&s, companyID: co.id, amount: amount, category: cat, label: label) }
        func loyal(_ weeks: Int) {
            if let k2 = s.companies[ci].staff.firstIndex(where: { $0.id == id }) { s.companies[ci].staff[k2].happyUntilWeek = max(s.companies[ci].staff[k2].happyUntilWeek, s.week + weeks) }
        }
        switch m.actionID {
        case annAction:
            let y = d["y"].int
            if idx == 0 { pay(cur.scaledPrice(4000) + Double(co.staff.count) * cur.scaledPrice(400), "oth", "Anniversary party"); bumpMood(&s, ci, 6); loyal(26); addStory(&s, company: ci, staff: id, "\(y) years: a party with the whole team") }
            else if idx == 1 { pay(st.monthlyWage, "wages", "Anniversary bonus"); bumpMood(&s, ci, 3); loyal(26); addStory(&s, company: ci, staff: id, "\(y) years: a bonus") }
            else { bumpMood(&s, ci, 1); addStory(&s, company: ci, staff: id, "\(y) years: a card") }
        case proAction:
            let to = d["to"].string
            guard juniorRoles.contains(st.role), data.catalog.tables.roles[to] != nil else { break }
            if idx == 0 {
                let from = roleName(s, data, st.role)
                s.companies[ci].staff[k].set("role", to); s.companies[ci].staff[k].monthlyWage = d["wage"].double
                s.companies[ci].staff[k].skillGain += 5; s.companies[ci].staff[k].noticeWeeks = 0; s.companies[ci].staff[k].lastRaiseWeek = s.week
                s.people[id]?.role = to
                addStory(&s, company: ci, staff: id, "Promoted from \(from) to \(roleName(s, data, to))")
                bumpMood(&s, ci, 4)
                s.note("\(s.people[id]?.name ?? "A colleague") is now \(roleName(s, data, to)) at \(co.name).", tone: "good", companyID: co.id)
            } else if roll(s, "prono:\(id)") < 0.25 { s.companies[ci].staff[k].noticeWeeks = 4 }
        case lifeAction:
            if idx == 0 { pay(cur.scaledPrice(1500), "oth", "Gift to \(s.people[id]?.name ?? "a colleague")"); bumpMood(&s, ci, 1.5); loyal(13); addStory(&s, company: ci, staff: id, "\(d["t"].string) (the company sent a gift)") }
            else { addStory(&s, company: ci, staff: id, d["t"].string) }
        case retAction:
            if idx == 0 { pay(cur.scaledPrice(8000), "oth", "Farewell party"); bumpMood(&s, ci, 5); s.companies[ci].reputation = clamp(s.companies[ci].reputation + 1, 0, 100) }
            else if idx == 1 { pay(cur.scaledPrice(3000), "oth", "Farewell gift"); bumpMood(&s, ci, 2) }
            let n = s.people[id], years = max(1, d["y"].int)
            let stories = st.value("st28").array
            let started = (stories.first?["t"].string ?? "").replacingOccurrences(of: "Joined ", with: "Started at ")
            let text = (stories.count > 2 ? "\(started), retired as \(roleName(s, data, st.role))" : "\(roleName(s, data, st.role)) at \(co.name)") + " · \(years) years · \(GameCalendar.year(week: s.week))"
            var hof = s.rest["hof28"]?.array ?? []
            hof.insert(.object(["n": .string(n?.name ?? "A colleague"), "t": .string(text), "w": .number(Double(s.week))]), at: 0)
            if hof.count > 40 { hof.removeLast(hof.count - 40) }
            s.rest["hof28"] = .array(hof)
            Dismissal.dismiss(&s, companyID: co.id, staffID: id, reason: .resignation, data: data)
            s.note("\(n?.name ?? "A colleague") has retired from \(co.name). You need to hire a replacement.", tone: "n", companyID: co.id)
        default: break
        }
    }

    static func quietDefaults(_ s: inout GameState, data: GameData) {
        for k in s.inbox.indices where s.inbox[k].actionID == retAction && s.inbox[k].status == "done" && s.inbox[k].value("auto").double != 0 && s.inbox[k].value("done28").isNull {
            s.inbox[k].set("done28", 1)
            let msg = s.inbox[k]
            answer(&s, message: msg, option: 2, data: data)
        }
    }

    public struct TopFifty: Equatable, Sendable {
        public struct Row: Equatable, Sendable { public var name: String, revenue: Double, isYou: Bool, groupID: String?, trades: String }
        public var year: Int, rows: [Row], yourRank: Int?, of: Int
    }
    public static func topFifty(_ s: GameState) -> TopFifty? {
        guard let t = s.rest["pr28"]?["top"], !t.isNull else { return nil }
        return TopFifty(year: t["y"].int, rows: t["list"].array.map { TopFifty.Row(name: $0["n"].string, revenue: $0["r"].double, isYou: $0["me"].double != 0, groupID: $0["g"].isNull || $0["g"].string.isEmpty ? nil : $0["g"].string, trades: $0["t"].string) },
                        yourRank: t["rk"].isNull ? nil : t["rk"].int, of: t["of"].int)
    }

    static func top50(_ s: inout GameState, data: GameData) {
        let b = CompanyRanking.board(s, data: data, scope: .country, metric: .revenue)
        guard let me = b.you else { return }
        let year = GameCalendar.year(week: s.week) - 1
        let rows: [JSONValue] = b.entries.filter { $0.rank <= 50 }.sorted { $0.rank < $1.rank }.map { e -> JSONValue in
            JSONValue.object(["n": .string(e.name), "r": .number(jsRound(e.revenue)), "me": .number(e.isYou ? 1 : 0), "g": .string(e.groupID ?? ""),
                     "t": .string(e.trades.prefix(2).map { data.catalog[$0]?.name ?? $0 }.joined(separator: ", "))])
        }
        var p = Press.state(s)
        p["top"] = .object(["y": .number(Double(year)), "list": .array(rows), "rk": .number(Double(me.rank)), "of": .number(Double(b.total))])
        s.rest["pr28"] = p
        let on = me.rank <= 50, paper = Press.paperName(s, data: data)
        s.addMessage(kind: "info", from: paper, title: "The Top 50 of \(year)" + (on ? ": you are No. \(me.rank)" : " is out"),
                     body: on ? "You made the list of the 50 biggest companies in \(data.countries[s.homeCountryCode]?.name ?? "your country")." : "You are not on the list yet. You are No. \(me.rank) by sales.",
                     tone: on ? "good" : "n")
        Press.add(&s, priority: on ? 5 : 2, head: "The Top 50 of \(year) is out", deck: on ? "\(s.player.name) at No. \(me.rank)." : "")
    }
}
