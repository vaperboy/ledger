import Foundation
import GameCore
import Countries
import Finance

/// IT security and cyber attacks. Every company chooses a protection level (none, basic, managed, a security team), offline backups
/// and staff training; they cost a monthly fee. Attacks follow the UK Cyber Security Breaches Survey: a fake invoice, ransomware, a data
/// leak, a website knocked offline. Losses go through `Incidents.loss` with category "cyber", so cyber insurance pays them.
/// Original: features/world/cyber_attacks.js (`LV`, `ODDS`, `yearOdds`, `fraud`, `ransom`, `leak`, `down`, `ACTS.cy56r`, `ACTS.cy56l`, weekly step, screen).
/// A manager looks after the level: at each month end, unless you picked one yourself (then yours stands until you hand it back),
/// they choose the level that fits the size and the risk, keep offline backups on and book the yearly training (`managerKeeps`,
/// original `secNeed`/`doSec` in features/people/manager_duties.js).
/// Not ported: the chain override, the data-protection authority's local name.
public enum Cyber {
    public static let levels: [(name: String, monthly: Double, text: String)] = [
        ("None", 0, "Only what came with the computers."),
        ("Basic", 600, "Updates, antivirus, strong passwords and two-step login."),
        ("Managed", 3500, "An IT firm watches the systems, patches them and helps when something happens."),
        ("Security team", 18000, "Monitoring day and night, regular tests and an incident plan."),
    ]
    static let odds = [1, 0.5, 0.25, 0.1]
    static let exposureByTrade: [String: Double] = ["webshop": 1.6, "webdev": 1.4, "mktg": 1.3, "law": 1.4, "acctfirm": 1.5, "staffing": 1.2, "estate": 1.2, "hotel": 1.3,
                                                    "airline": 1.5, "wh3pl": 1.3, "courier": 1.1, "cardealer": 1.1, "foodtruck": 0.4, "carclean": 0.5, "handy": 0.5,
                                                    "barber": 0.6, "farm": 0.5, "salmon": 0.7, "kiosk": 0.6]
    static let exposureByFamily: [String: Double] = ["fin": 1.6, "energy": 1.3, "svc": 1, "retail": 1, "venue": 0.8, "project": 0.8, "prod": 0.9, "logi": 1.1, "rent": 0.6]
    static let online: Set<String> = ["webshop", "hotel", "airline", "wh3pl", "webdev", "mktg", "courier", "fun", "indoorski", "skires"]

    public struct Status: Equatable {
        public var level: Int, backups: Bool, trainedUntil: Int?, blocked: Int, log: [(week: Int, text: String)], managerPicks: Bool = false
        public static func == (a: Status, b: Status) -> Bool { a.level == b.level && a.backups == b.backups && a.trainedUntil == b.trainedUntil && a.blocked == b.blocked }
    }

    public static func status(_ co: Company) -> Status {
        let c = co.value("cy56")
        return Status(level: c["lvl"].int, backups: c["bk"].bool, trainedUntil: c["tr"].isNull ? nil : c["tr"].int + 52, blocked: c["blocked"].int,
                      log: c["log"].array.map { ($0["w"].int, $0["t"].string) }, managerPicks: managerPicks(co))
    }

    public static func heads(_ co: Company) -> Int { co.staff.filter { !$0.isOffSeason }.count + (co.managerID != nil ? 1 : 0) }
    static func sizeFactor(_ co: Company) -> Double { pow(max(1, Double(heads(co)) / 6), 0.6) }
    static func trained(_ co: Company, week: Int) -> Bool { let t = co.value("cy56")["tr"]; return !t.isNull && week - t.int < 52 }
    static func exposure(_ co: Company, _ bd: Trade?) -> Double { exposureByTrade[co.type] ?? exposureByFamily[bd?.family ?? ""] ?? 1 }

    /// Monthly fee for a level (and backups). Original: `monthly`.
    public static func monthly(_ co: Company, level: Int, backups: Bool, cur: Currency) -> Double {
        cur.scaledPrice(levels[level].monthly) * sizeFactor(co) + (backups ? cur.scaledPrice(400) * sizeFactor(co) : 0)
    }

    public static func trainingCost(_ co: Company, cur: Currency) -> Double { (cur.scaledPrice(450) * Double(max(1, heads(co))) / 100).rounded() * 100 }

    /// The chance of a serious incident in a year. Original: `yearOdds`.
    public static func yearOdds(_ co: Company, week: Int, trade bd: Trade?) -> Double {
        let c = co.value("cy56")
        let size = clamp((Double(heads(co)) + 1) / 5, 0.6, 4).squareRoot()
        var p = 0.08 * exposure(co, bd) * size * odds[min(3, max(0, c["lvl"].int))]
        if trained(co, week: week) { p *= 0.75 }
        if !c["target"].isNull, c["target"].int > week { p *= 1.8 }
        return clamp(p, 0.002, 0.6)
    }

    static func log(_ s: inout GameState, _ i: Int, _ text: String) {
        var c = s.companies[i].value("cy56")
        var l = c["log"].array
        l.insert(.object(["w": .number(Double(s.week)), "t": .string(text)]), at: 0)
        if l.count > 10 { l.removeLast(l.count - 10) }
        c["log"] = .array(l)
        s.companies[i].set("cy56", c)
    }

    static func weeklyRevenue(_ co: Company, _ cur: Currency) -> Double { max(cur.scaledPrice(10000), co.value("lastW")["rev"].double) }

    // MARK: Attacks

    static func fraud(_ s: inout GameState, _ i: Int, _ h: inout HashedRandom, cur: Currency, data: GameData) {
        let co = s.companies[i]
        let amt = (clamp(weeklyRevenue(co, cur) * (0.4 + 1.4 * h.next()), cur.scaledPrice(15000), cur.scaledPrice(600000)) / 1000).rounded() * 1000
        let catchP = clamp(0.25 + (trained(co, week: s.week) ? 0.5 : 0) + 0.1 * Double(co.value("cy56")["lvl"].int), 0, 0.95)
        if h.next() < catchP {
            var c = co.value("cy56"); c["blocked"] = .number(c["blocked"].double + 1); s.companies[i].set("cy56", c)
            log(&s, i, "Fake invoice for \(cur.display(amt)) spotted")
            s.note("Someone at \(co.name) spotted a fake invoice for \(cur.display(amt)) that looked like it came from a supplier. Nothing was paid.", tone: "good", companyID: co.id)
            return
        }
        Incidents.loss(&s, companyID: co.id, amount: amt, category: "cyber", label: "Fake invoice paid", data: data)
        log(&s, i, "Paid a fake invoice: \(cur.display(amt))")
        s.addMessage(from: co.name, title: "\(co.name) paid a fake invoice",
                     body: "An email that looked like it came from a supplier asked us to pay \(cur.display(amt)) to a new bank account. It was a fraud and the money is gone."
                         + (co.value("ins")["cyber"].bool ? " The cyber insurance covers most of it." : " There is no cyber insurance to cover it.")
                         + (trained(co, week: s.week) ? "" : " Staff training teaches people to check a new bank account by phone."),
                     companyID: co.id, tone: "bad")
    }

    static func ransom(_ s: inout GameState, _ i: Int, _ h: inout HashedRandom, cur: Currency) {
        let co = s.companies[i]
        let c = co.value("cy56")
        let demand = (clamp(weeklyRevenue(co, cur) * (1 + 2 * h.next()), cur.scaledPrice(40000), cur.scaledPrice(5e6)) / 1000).rounded() * 1000
        let team = (cur.scaledPrice(60000) * sizeFactor(co) / 1000).rounded() * 1000
        PriceMoves.addModifier(&s, i, key: "cap", multiplier: 0.3, weeks: 1)
        log(&s, i, "Ransomware: systems locked")
        let bk = c["bk"].bool
        s.addMessage(kind: "ask", from: co.managerID.flatMap { s.people[$0]?.name } ?? co.name, title: "Ransomware has locked the systems at \(co.name)",
                     body: "Nothing works: bookings, tills, files and email are encrypted. The attackers want \(cur.display(demand)) to unlock them. "
                         + (bk ? "We have offline backups, so we can rebuild without them." : "We have no offline backups.") + (co.value("ins")["cyber"].bool ? " The cyber insurance covers most of the costs." : ""),
                     companyID: co.id, tone: "bad", status: "open",
                     options: [.option("Pay the ransom · \(cur.display(demand))", "Usually works, not always. Those who pay get attacked again more often."),
                               .option(bk ? "Restore from the backups" : "Rebuild without backups", bk ? "About a week at reduced capacity." : "Weeks of trouble, and some data is lost for good."),
                               .option("Bring in an incident team · \(cur.display(team))", "Experts clean the systems and get you running fast.")],
                     action: "cy56r", data: .object(["demand": .number(demand), "team": .number(team)]), expiresWeek: s.week + 1)
    }

    static func leak(_ s: inout GameState, _ i: Int, _ h: inout HashedRandom, cur: Currency, bd: Trade?) {
        let co = s.companies[i]
        let f = CountryTraits.hasDataProtectionLaw(co.countryCode) ? 1.0 : 0.5
        let fine = (cur.scaledPrice(25000) * sizeFactor(co) * (0.6 + h.next()) * f * exposure(co, bd) / 1000).rounded() * 1000
        log(&s, i, "Customer data leaked")
        s.addMessage(kind: "ask", from: co.managerID.flatMap { s.people[$0]?.name } ?? co.name, title: "Customer data has leaked from \(co.name)",
                     body: "Someone got into our systems and copied names, emails and some payment details of our customers. The law says we must tell the data protection authority within 72 hours and warn the customers.",
                     companyID: co.id, tone: "bad", status: "open",
                     options: [.option("Tell them now", "A fine of about \(cur.display(fine)) and some lost trust."), .option("Keep it quiet", "Nothing now. If it comes out, the fine is far larger and customers leave.")],
                     action: "cy56l", data: .object(["fine": .number(fine)]), expiresWeek: s.week + 1)
    }

    static func down(_ s: inout GameState, _ i: Int) {
        let co = s.companies[i]
        if co.value("cy56")["lvl"].int >= 2 {
            var c = co.value("cy56"); c["blocked"] = .number(c["blocked"].double + 1); s.companies[i].set("cy56", c)
            log(&s, i, "Attack on the website stopped")
            return
        }
        PriceMoves.addModifier(&s, i, key: "dem", multiplier: 0.6, weeks: 1)
        log(&s, i, "Website knocked offline")
        s.note("\(co.name)'s website and online sales were knocked offline by an attack for several days. Managed IT security would have stopped it.", tone: "bad", companyID: co.id)
    }

    /// Force an attack (for tests). Kinds: fraud, ransom, leak, down.
    public static func hit(_ s: inout GameState, companyID: Int, kind: String, data: GameData) {
        guard let i = s.companyIndex(companyID) else { return }
        let cur = World(state: s, data: data).currency(s.companies[i])
        var h = HashedRandom("\(s.seed):cyhit:\(s.week):\(companyID):\(kind)")
        switch kind {
        case "fraud": fraud(&s, i, &h, cur: cur, data: data)
        case "ransom": ransom(&s, i, &h, cur: cur)
        case "leak": leak(&s, i, &h, cur: cur, bd: data.catalog[s.companies[i].type])
        default: down(&s, i)
        }
    }

    // MARK: Answers

    /// Ransom: pay, restore, or call the team. Original: `ACTS.cy56r`.
    public static func answerRansom(_ s: inout GameState, message m: Message, option: Int, data: GameData) {
        guard let i = s.companyIndex(m.companyID) else { return }
        let co = s.companies[i], d = m.value("data"), id = co.id
        let bk = co.value("cy56")["bk"].bool
        let cur = World(state: s, data: data).currency(co)
        var h = HashedRandom("\(s.seed):ransom:\(m.id)")
        if option == 0 {
            Incidents.loss(&s, companyID: id, amount: d["demand"].double, category: "cyber", label: "Ransom paid", data: data)
            var c = s.companies[i].value("cy56"); c["target"] = .number(Double(s.week + 52)); s.companies[i].set("cy56", c)
            if h.next() < 0.2 {
                PriceMoves.addModifier(&s, i, key: "cap", multiplier: 0.45, weeks: 2)
                s.note("The key the attackers sent only unlocked part of the systems at \(co.name). It takes weeks to rebuild the rest.", tone: "bad", companyID: id)
            } else { s.note("The ransom was paid and the systems at \(co.name) are unlocked.", companyID: id) }
        } else if option == 1 {
            if bk {
                PriceMoves.addModifier(&s, i, key: "cap", multiplier: 0.65, weeks: 1)
                Incidents.loss(&s, companyID: id, amount: (cur.scaledPrice(10000) * sizeFactor(co) / 1000).rounded() * 1000, category: "cyber", label: "Restoring systems", data: data)
                s.note("\(co.name) is rebuilt from the backups. A slow week, nothing lost.", companyID: id)
            } else {
                PriceMoves.addModifier(&s, i, key: "cap", multiplier: 0.3, weeks: 3)
                s.companies[i].reputation = clamp(s.companies[i].reputation - 3, 0, 100)
                Incidents.loss(&s, companyID: id, amount: (cur.scaledPrice(35000) * sizeFactor(co) / 1000).rounded() * 1000, category: "cyber", label: "Rebuilding systems", data: data)
                s.note("\(co.name) rebuilds without backups: weeks of trouble, and some customer records are gone for good.", tone: "bad", companyID: id)
            }
        } else {
            Incidents.loss(&s, companyID: id, amount: d["team"].double, category: "cyber", label: "Incident team", data: data)
            PriceMoves.addModifier(&s, i, key: "cap", multiplier: bk ? 0.85 : 0.6, weeks: 1)
            s.note("An incident team cleaned the systems at \(co.name). It is running again.", companyID: id)
        }
    }

    /// Leak: tell them or keep quiet. Original: `ACTS.cy56l`.
    public static func answerLeak(_ s: inout GameState, message m: Message, option: Int, data: GameData) {
        guard let i = s.companyIndex(m.companyID) else { return }
        let fine = m.value("data")["fine"].double
        if option == 0 {
            let cur = World(state: s, data: data).currency(s.companies[i])
            Payments.companyPays(&s, companyID: s.companies[i].id, amount: fine, category: "fine", label: "Data protection fine")
            if let j = s.companyIndex(m.companyID) {
                s.companies[j].reputation = clamp(s.companies[j].reputation - 1, 0, 100)
                PriceMoves.addModifier(&s, j, key: "dem", multiplier: 0.95, weeks: 6)
                s.note("\(s.companies[j].name) told its customers and the authority about the leak. A fine of \(cur.display(fine)); most customers stay.", companyID: m.companyID)
            }
        } else {
            var c = s.companies[i].value("cy56"); c["hide"] = .object(["w": .number(Double(s.week)), "fine": .number(fine)]); s.companies[i].set("cy56", c)
        }
    }

    // MARK: Player actions

    public static func setLevel(_ s: inout GameState, companyID: Int, level: Int) {
        guard let i = s.companyIndex(companyID) else { return }
        var c = s.companies[i].value("cy56"); c["lvl"] = .number(Double(min(3, max(0, level))))
        if s.companies[i].managerID != nil { c["own"] = 1 }
        s.companies[i].set("cy56", c)
    }

    public static func toggleBackups(_ s: inout GameState, companyID: Int) {
        guard let i = s.companyIndex(companyID) else { return }
        var c = s.companies[i].value("cy56"); c["bk"] = .bool(!c["bk"].bool)
        if s.companies[i].managerID != nil { c["own"] = 1 }
        s.companies[i].set("cy56", c)
    }

    /// Does the manager pick the level here (no choice of yours standing)?
    public static func managerPicks(_ co: Company) -> Bool { co.managerID != nil && !co.value("cy56")["own"].bool }

    /// Give the choice back to the manager. Original: `md56` switch.
    public static func leaveToManager(_ s: inout GameState, companyID: Int) {
        guard let i = s.companyIndex(companyID) else { return }
        var c = s.companies[i].value("cy56"); c["own"] = 0; s.companies[i].set("cy56", c)
    }

    /// The level a manager would pick: 3 for 40+ heads or a high risk, 2 from 8 heads, else 1; never more than 3% of the month's sales. Original: `secNeed`.
    public static func levelNeeded(_ co: Company, week: Int, trade bd: Trade?, cur: Currency) -> Int {
        let o0 = yearOdds(co, week: week, trade: bd) / odds[min(3, max(0, co.value("cy56")["lvl"].int))]
        let hd = heads(co)
        var lvl = hd >= 40 || o0 >= 0.3 ? 3 : hd >= 8 || o0 >= 0.12 ? 2 : 1
        let revM = co.value("lastW")["rev"].double * 4.33
        while lvl > 1 && monthly(co, level: lvl, backups: true, cur: cur) > revM * 0.03 { lvl -= 1 }
        return lvl
    }

    /// The manager's month: level, backups and training. Original: `doSec`.
    static func managerKeeps(_ s: inout GameState, _ i: Int, trade bd: Trade, data: GameData) {
        let co = s.companies[i]
        guard co.managerID != nil, let mgr = s.people[co.managerID!] else { return }
        let cur = World(state: s, data: data).currency(co)
        var c = co.value("cy56"), notes: [String] = []
        if !c["own"].bool {
            let lvl = levelNeeded(co, week: s.week, trade: bd, cur: cur)
            if lvl != c["lvl"].int { notes.append("\(lvl > c["lvl"].int ? "raised" : "lowered") IT security to \(levels[lvl].name.lowercased())"); c["lvl"] = .number(Double(lvl)) }
            if lvl >= 1 && !c["bk"].bool { c["bk"] = true; notes.append("turned on offline backups") }
        }
        s.companies[i].set("cy56", c)
        let tc = trainingCost(co, cur: cur)
        if !trained(co, week: s.week), heads(co) >= 3, co.cash > tc * 3 + co.lastWeekRevenue * 0.5 * 4 {
            Payments.companyPays(&s, companyID: co.id, amount: tc, category: "oth", label: "Security training")
            if let j = s.companyIndex(co.id) { var cc = s.companies[j].value("cy56"); cc["tr"] = .number(Double(s.week)); s.companies[j].set("cy56", cc) }
            notes.append("booked security training for the team")
        }
        if !notes.isEmpty { s.note("\(mgr.name) \(notes.joined(separator: ", ")) at \(co.name).", tone: "n", companyID: co.id) }
    }

    public static func train(_ s: inout GameState, companyID: Int, data: GameData) -> String? {
        guard let i = s.companyIndex(companyID) else { return "Gone." }
        let co = s.companies[i]
        if trained(co, week: s.week) { return "The team is already trained." }
        let cost = trainingCost(co, cur: World(state: s, data: data).currency(co))
        if co.cash < cost { return "Not enough cash in \(co.name)." }
        Payments.companyPays(&s, companyID: co.id, amount: cost, category: "oth", label: "Security training")
        if let j = s.companyIndex(companyID) { var c = s.companies[j].value("cy56"); c["tr"] = .number(Double(s.week)); s.companies[j].set("cy56", c) }
        return nil
    }

    // MARK: Weekly

    /// Fees, unanswered attacks, a leak coming out, and new attacks. Original: the 'IT security and cyber attacks' week.after step.
    public static func weekly(_ s: inout GameState, data: GameData) {
        for i in s.companies.indices where s.companies[i].status == .open && s.companies[i].type != "hold" {
            guard let bd = data.catalog[s.companies[i].type] else { continue }
            let co = s.companies[i]
            let cur = World(state: s, data: data).currency(co)
            let c = co.value("cy56")
            let mo = monthly(co, level: c["lvl"].int, backups: c["bk"].bool, cur: cur)
            if mo > 0 { Payments.companyPays(&s, companyID: co.id, amount: mo * 12 / 52, category: "oth", label: "IT security") }
            if GameCalendar.isMonthEnd(week: s.week) { managerKeeps(&s, i, trade: bd, data: data) }
            // An unanswered attack: the safe choice.
            for k in s.inbox.indices {
                let m = s.inbox[k]
                guard m.companyID == co.id, (m.actionID == "cy56r" || m.actionID == "cy56l"), m.status == "done", m.int("pick") == -1, !m.flag("cy56d") else { continue }
                s.inbox[k].set("cy56d", true)
                if m.actionID == "cy56r" { answerRansom(&s, message: m, option: c["bk"].bool ? 1 : 2, data: data) } else { answerLeak(&s, message: m, option: 0, data: data) }
            }
            guard let i2 = s.companyIndex(co.id) else { continue }
            var h = HashedRandom("\(s.seed):cyw:\(s.week):\(co.id)")
            let hide = s.companies[i2].value("cy56")["hide"]
            if !hide.isNull, s.week - hide["w"].int < 26, h.next() < 0.45 / 26 {
                let fine = hide["fine"].double * 4
                var cc = s.companies[i2].value("cy56"); cc["hide"] = .null; s.companies[i2].set("cy56", cc)
                Payments.companyPays(&s, companyID: co.id, amount: fine, category: "fine", label: "Data protection fine")
                if let j = s.companyIndex(co.id) { s.companies[j].reputation = clamp(s.companies[j].reputation - 6, 0, 100); PriceMoves.addModifier(&s, j, key: "dem", multiplier: 0.85, weeks: 12) }
                s.addMessage(from: "News", title: "\(co.name) hid a data leak", body: "Journalists found out that \(co.name) kept a leak of customer data quiet. The authority fines it \(cur.display(fine)), and many customers go elsewhere.", companyID: co.id, tone: "bad")
            } else if !hide.isNull, s.week - hide["w"].int >= 26 {
                var cc = s.companies[i2].value("cy56"); cc["hide"] = .null; s.companies[i2].set("cy56", cc)
            }
            if s.week - (co.openedWeek ?? co.foundedWeek) < 8 { continue }   // a brand new company is not on anyone's list yet
            guard h.next() < yearOdds(s.companies[i2], week: s.week, trade: bd) / 52 else { continue }
            let weights: [(String, Double)] = [("fraud", 0.5 * (trained(co, week: s.week) ? 0.5 : 1)), ("ransom", 0.15), ("leak", 0.2), ("down", online.contains(co.type) ? 0.25 : 0.03)]
            var r = h.next() * weights.reduce(0) { $0 + $1.1 }
            var kind = "fraud"
            for x in weights { r -= x.1; if r <= 0 { kind = x.0; break } }
            switch kind {
            case "fraud": fraud(&s, i2, &h, cur: cur, data: data)
            case "ransom": ransom(&s, i2, &h, cur: cur)
            case "leak": leak(&s, i2, &h, cur: cur, bd: bd)
            default: down(&s, i2)
            }
        }
    }
}
