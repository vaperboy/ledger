import Foundation
import GameCore
import Countries
import Finance

/// People you care about: staff stories (anniversaries, thank-you notes, life events, retirement), the one rival owner who makes it
/// personal (the nemesis, with a running score) and the Top 50 every January.
/// Original: features/people/staff_stories_and_nemesis.js (`staffWeek`, `nemWeek`, `top50`). The business paper and the interviews are `Press`.
/// Not ported: promoting a junior worker from the bottom up (`st28pro`).
public enum Stories {
    public static let annAction = "st28ann", retAction = "st28ret", lifeAction = "st28life"
    public static func handlesAnswer(_ action: String) -> Bool { [annAction, retAction, lifeAction].contains(action) }

    // MARK: Helpers

    /// A draw that does not touch the game's shared random stream (so these stories never move the rest of the simulation).
    static func roll(_ s: GameState, _ tag: String) -> Double { var h = HashedRandom("\(s.seed):st28:\(tag):\(s.week)"); return h.next() }

    static func mood(_ co: Company) -> Double { co.value("mood").isNull ? 60 : co.num("mood") }
    static func bumpMood(_ s: inout GameState, _ ci: Int, _ d: Double) { s.companies[ci].set("mood", clamp(mood(s.companies[ci]) + d, 0, 100)) }
    static func first(_ name: String) -> String { name.split(separator: " ").first.map(String.init) ?? name }
    static func roleName(_ s: GameState, _ data: GameData, _ role: String) -> String { (data.catalog.tables.roles[role]?.name ?? "worker").lowercased() }

    /// A line in a worker's story, at most 20 (the second is dropped first). Original: `story`.
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

    // MARK: Every week

    public static func weekly(_ s: inout GameState, data: GameData) {
        for ci in s.companies.indices where s.companies[ci].status == .open { staffWeek(&s, ci, data: data) }
        quietDefaults(&s, data: data)
        nemesisWeek(&s, data: data)
        if GameCalendar.year(week: s.week) != GameCalendar.year(week: s.week - 1) { top50(&s, data: data) }
    }

    // MARK: Staff stories

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
            // anniversaries: one year is a story line; every fifth year asks what the team does
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
            // retirement
            if Double(n.age) + Double(s.week - hired) / 52 >= 67 && m.value("ret28").isNull && fresh {
                m.set("ret28", s.week); fresh = false
                s.companies[ci].set("sl28", s.week)
                s.addMessage(kind: "ask", from: n.name, title: "\(n.name) is retiring",
                             body: "After \(max(1, y)) year\(y > 1 ? "s" : "") at \(co.name), \(first(n.name)) is retiring. How do you say goodbye?", companyID: co.id, tone: "n", status: "open",
                             options: [.option("A farewell party", "\(cur.display(cur.scaledPrice(8000))). The whole team comes."), .option("A gift and a speech", "\(cur.display(cur.scaledPrice(3000)))."), .option("A card", "")],
                             action: retAction, data: .object(["co": .number(Double(co.id)), "s": .number(Double(id)), "y": .number(Double(max(1, y)))]), expiresWeek: s.week + 2)
            }
            // thank-you notes after a raise or a course
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
            // life
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
        // the manager
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
            Hiring.fire(id, from: co.id, state: &s, data: data, withCause: true)
            s.note("\(n?.name ?? "A colleague") has retired from \(co.name). You need to hire a replacement.", tone: "n", companyID: co.id)
        default: break
        }
    }

    /// Nobody answered a farewell: the quiet default is a card, and the person still goes. Original: the `m.auto` pass.
    static func quietDefaults(_ s: inout GameState, data: GameData) {
        for k in s.inbox.indices where s.inbox[k].actionID == retAction && s.inbox[k].status == "done" && s.inbox[k].value("auto").double != 0 && s.inbox[k].value("done28").isNull {
            s.inbox[k].set("done28", 1)
            let msg = s.inbox[k]
            answer(&s, message: msg, option: 2, data: data)
        }
    }

    // MARK: The nemesis

    public struct Nemesis: Equatable, Sendable {
        public var owner: String, groupID: String, groupName: String, since: Int, wins: Int, losses: Int, bankrupt: Bool
        public var log: [(week: Int, kind: String, text: String)]
        public static func == (a: Nemesis, b: Nemesis) -> Bool { a.groupID == b.groupID && a.wins == b.wins && a.losses == b.losses && a.log.count == b.log.count }
    }
    public static func nemesis(_ s: GameState) -> Nemesis? {
        guard let nm = s.rest["nem28"], !nm.isNull else { return nil }
        let g = RivalGroups.group(s, id: nm["g"].string)
        return Nemesis(owner: nm["n"].string, groupID: nm["g"].string, groupName: g?.name ?? "", since: nm["since"].int, wins: nm["w"].int, losses: nm["l"].int,
                       bankrupt: g?.gone ?? !nm["gone"].isNull, log: nm["log"].array.map { ($0["w"].int, $0["k"].string, $0["t"].string) })
    }

    static let lossLines = ["Better luck next time, {me}.", "{city} is my town. You will learn.", "Nothing personal. Just business.", "You make it easy for me, {me}."]
    static let winLines = ["Fine. You held on this time.", "Not bad, {me}. Not bad at all.", "Enjoy it while it lasts.", "I underestimated you. It will not happen twice.", "Well played. See you next round."]

    static func pickNemesis(_ s: inout GameState, data: GameData) {
        guard (s.rest["nem28"] ?? .null).isNull, s.week >= 10 else { return }
        let live = s.companies.filter { $0.status == .open }
        guard !live.isEmpty else { return }
        // nobody picks a fight with a newcomer; you have to matter first
        let w = World(state: s, data: data)
        let matters = live.count >= 3 || live.contains { c in data.catalog[c.type].map { MarketMap.noticed(s, c, $0, w) } ?? false }
        guard matters else { return }
        func score(_ g: RivalGroups.Group) -> Double {
            Double(RivalGroups.members(s, groupID: g.id).count) * 3 + (live.contains { g.trades.contains($0.type) } ? 2 : 0)
                + (["acq", "expand", "cost"].contains(g.strategy) ? 1.5 : 0) + log10(max(1e6, g.revenue)) / 4
        }
        let pool = RivalGroups.groups(s, country: s.homeCountryCode).filter { !$0.inTrouble }
        guard let g = pool.max(by: { score($0) < score($1) }), score(g) >= 3 else { return }
        s.rest["nem28"] = .object(["g": .string(g.id), "n": .string(g.owner), "since": .number(Double(s.week)), "w": 0, "l": 0, "log": .array([]), "pend": .array([]), "msg": -99, "seen": .number(Double(s.week))])
        let co = live.first { g.trades.contains($0.type) } ?? live[0]
        let trade = (data.catalog[co.type]?.name ?? "business").lowercased()
        let city = w.city(co)?.name ?? "this town"
        s.addMessage(kind: "info", from: "\(g.owner), \(g.name)", title: "A message from \(g.owner)",
                     body: "\"I hear you are in \(trade) in \(city) now. Welcome to my market. Most newcomers do not last a year.\"", tone: "bad")
        Press.add(&s, priority: 5, head: "\(g.owner) takes aim at \(s.player.name)", deck: "The owner of \(g.name) has a new rival.")
    }

    /// Score a round. Kind: "w" you, "l" them, "d" a draw that only goes in the log. Original: `tally`.
    static func tally(_ s: inout GameState, _ kind: String, _ text: String, data: GameData) {
        guard var nm = s.rest["nem28"], !nm.isNull else { return }
        if kind == "w" { nm["w"] = .number(nm["w"].double + 1) } else if kind == "l" { nm["l"] = .number(nm["l"].double + 1) }
        var log = nm["log"].array
        log.insert(.object(["w": .number(Double(s.week)), "k": .string(kind), "t": .string(text)]), at: 0)
        if log.count > 30 { log.removeLast(log.count - 30) }
        nm["log"] = .array(log)
        let owner = nm["n"].string, score = "\(nm["w"].int)\u{2013}\(nm["l"].int)"
        let talk = kind != "d" && s.week - nm["msg"].int >= 6 && roll(s, "nem:\(nm["w"].int):\(nm["l"].int)") < 0.7
        if talk { nm["msg"] = .number(Double(s.week)) }
        s.rest["nem28"] = nm
        guard kind != "d" else { return }
        Press.add(&s, priority: 4, head: kind == "w" ? "\(s.player.name) gets the better of \(owner)" : "\(owner) wins another round against \(s.player.name)", deck: "\(text) The score: \(score).")
        if talk {
            let g = RivalGroups.group(s, id: nm["g"].string)
            let w = World(state: s, data: data)
            let city = s.companies.first { $0.status == .open }.flatMap { c in w.city(c)?.name } ?? "This town"
            let lines = kind == "w" ? winLines : lossLines
            let line = lines[min(lines.count - 1, Int(roll(s, "line") * Double(lines.count)))].replacingOccurrences(of: "{me}", with: first(s.player.name)).replacingOccurrences(of: "{city}", with: city)
            s.addMessage(kind: "info", from: owner + (g.map { ", " + $0.name } ?? ""), title: kind == "w" ? "\(owner) is not pleased" : "\(owner) has something to say", body: "\"\(line)\"",
                         tone: kind == "w" ? "good" : "bad")
        }
    }

    static func nemesisWeek(_ s: inout GameState, data: GameData) {
        pickNemesis(&s, data: data)
        guard var nm = s.rest["nem28"], !nm.isNull, let g = RivalGroups.group(s, id: nm["g"].string) else { return }
        var rounds: [(String, String)] = []
        if g.gone && nm["gone"].isNull { nm["gone"] = .number(Double(s.week)); rounds.append(("w", "\(g.name) went bankrupt. You outlasted \(nm["n"].string).")) }
        func byName(_ t: String) -> Company? { s.companies.first { !$0.name.isEmpty && t.contains($0.name) && ($0.status == .open || $0.status == .sold) } }
        var pend = nm["pend"].array
        let seen = nm["seen"].int
        for mv in g.moves where mv.week > seen && mv.week <= s.week {
            let t = mv.text
            if t.hasPrefix("Hired ") { rounds.append(("l", "They hired your manager away.")) }
            else if t.hasPrefix("Tried to hire "), let co = byName(t) { pend.append(.object(["k": "poach", "co": .number(Double(co.id)), "mgr": .number(Double(co.managerID ?? 0)), "w": .number(Double(s.week + 3))])) }
            else if t.hasPrefix("Cut prices"), let co = s.companies.first(where: { $0.status == .open && g.trades.contains($0.type) }) {
                pend.append(.object(["k": "uc", "co": .number(Double(co.id)), "r0": .number(co.lastWeekRevenue), "w": .number(Double(s.week + 8))]))
            }
            else if t.hasPrefix("Opened "), let co = byName(t) { pend.append(.object(["k": "beside", "co": .number(Double(co.id)), "r0": .number(co.lastWeekRevenue), "w": .number(Double(s.week + 26))])) }
            else if t.hasPrefix("Bid "), let co = byName(t) { pend.append(.object(["k": "bid", "co": .number(Double(co.id)), "w": .number(Double(s.week + 4))])) }
            else if t.hasPrefix("Bought the supplier") { rounds.append(("l", "They bought one of your suppliers.")) }
            else if t.hasPrefix("Sold ") && t.hasSuffix(" to you") { rounds.append(("w", "You bought one of their sites.")) }
            else if t.hasPrefix("Bought ") && t.hasSuffix(" from you") { rounds.append(("d", "You sold them a company.")) }
            else if t.hasPrefix("Bought ") { rounds.append(("l", "They bought a business in your market before you did.")) }
        }
        // how earlier rounds ended
        var keep: [JSONValue] = []
        for p in pend {
            if s.week < p["w"].int { keep.append(p); continue }
            guard let co = s.company(p["co"].int) else { continue }
            let now = co.lastWeekRevenue
            switch p["k"].string {
            case "poach": if co.managerID != nil && co.managerID == p["mgr"].int { rounds.append(("w", "Your manager at \(co.name) turned them down.")) }
            case "uc": let ok = now >= p["r0"].double * 0.93; rounds.append((ok ? "w" : "l", ok ? "\(co.name) kept its customers through their price cut." : "Their price cut took customers from \(co.name)."))
            case "beside": let ok = now >= p["r0"].double * 0.95; rounds.append((ok ? "w" : "l", ok ? "\(co.name) is doing fine with them next door." : "Their new site next to \(co.name) hurts."))
            case "bid": if co.status == .sold { rounds.append(("d", "You sold \(co.name) to them.")) } else { rounds.append(("w", "You turned down their bid for \(co.name).")) }
            default: break
            }
        }
        nm["pend"] = .array(keep)
        nm["seen"] = .number(Double(s.week))
        s.rest["nem28"] = nm
        // each new year: who ranks higher
        if GameCalendar.year(week: s.week) != GameCalendar.year(week: s.week - 1) {
            let b = CompanyRanking.board(s, data: data, scope: .country, metric: .revenue)
            if let me = b.you, let them = b.entries.first(where: { $0.groupID == g.id }) {
                rounds.append(me.rank < them.rank ? ("w", "You finished the year ahead of \(g.name) (No. \(me.rank) against No. \(them.rank)).")
                                                   : ("l", "\(g.name) finished the year ahead of you (No. \(them.rank) against No. \(me.rank))."))
            }
        }
        for r in rounds { tally(&s, r.0, r.1, data: data) }
    }

    // MARK: The Top 50

    public struct TopFifty: Equatable, Sendable {
        public struct Row: Equatable, Sendable { public var name: String, revenue: Double, isYou: Bool, groupID: String?, trades: String }
        public var year: Int, rows: [Row], yourRank: Int?, of: Int
    }
    public static func topFifty(_ s: GameState) -> TopFifty? {
        guard let t = s.rest["pr28"]?["top"], !t.isNull else { return nil }
        return TopFifty(year: t["y"].int, rows: t["list"].array.map { TopFifty.Row(name: $0["n"].string, revenue: $0["r"].double, isYou: $0["me"].double != 0, groupID: $0["g"].isNull || $0["g"].string.isEmpty ? nil : $0["g"].string, trades: $0["t"].string) },
                        yourRank: t["rk"].isNull ? nil : t["rk"].int, of: t["of"].int)
    }

    /// Every January the paper prints the 50 biggest companies by sales. Original: `top50`.
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
