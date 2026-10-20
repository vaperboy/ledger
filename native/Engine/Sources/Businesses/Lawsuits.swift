import Foundation
import GameCore
import Countries
import Finance

/// Losses that insurance can cover, shared by lawsuits and cyber attacks. Original: `applyFx(co, { loss }, null, { cat })`.
enum Incidents {
    /// A loss with a deductible: insurance for this category pays most of it (now and then it pays only part).
    static func loss(_ s: inout GameState, companyID: Int, amount amt: Double, category cat: String, label: String, data: GameData) {
        guard let i = s.companyIndex(companyID), amt > 0 else { return }
        if cat != "none", s.companies[i].value("ins")[cat].bool {
            let cur = World(state: s, data: data).currency(s.companies[i])
            var paid = amt - min(amt, cur.scaledPrice(10000))
            if paid > 0 {
                var h = HashedRandom("\(s.seed):insloss:\(s.week):\(companyID):\(Int(amt))")
                paid = jsRound(paid * (h.next() < 0.15 ? 0.3 + 0.4 * h.next() : 1))
                if paid > 0 {
                    Payments.companyReceives(&s, companyID: companyID, amount: paid, category: nil, label: "Insurance payout")
                    Payments.book(&s, companyID: companyID, category: "loss", amount: -paid)
                }
            }
        }
        Payments.companyPays(&s, companyID: companyID, amount: amt, category: "loss", label: label)
    }
}

/// Customer lawsuits: a reason, a claim, a choice between settling and going to court, and for big cases a court date weeks away.
/// Originals: `SUE`, `SPEC.g_lawsuit`, `sue`, `ACTS.sue16`, `courtWeek` (features/sales/price_moves_and_lawsuits.js).
public enum Lawsuits {
    // (reason, chance of winning, size of the claim relative to a week's revenue)
    static let reasons: [String: [(String, Double, Double)]] = [
        "svc": [("says your work damaged their property", 0.55, 1), ("claims they were billed for hours nobody worked", 0.6, 0.5), ("says your advice cost them money", 0.5, 1.6)],
        "venue": [("slipped on a wet floor and broke a wrist", 0.45, 1.4), ("got food poisoning after a visit", 0.5, 1), ("says a member of staff hurt them during an argument", 0.4, 1.8)],
        "retail": [("was hurt by a faulty product you sold", 0.5, 1.5), ("says you refused a legal return or warranty claim", 0.35, 0.3), ("slipped in the shop and was injured", 0.45, 1.2)],
        "logi": [("says you lost or destroyed their goods", 0.45, 0.8), ("was hurt in one of your vehicles", 0.4, 2), ("says a late delivery cost them a contract", 0.6, 1.2)],
        "project": [("says your work has serious defects", 0.45, 2.2), ("claims the job ran far over the agreed price", 0.55, 0.9), ("says your crew damaged the neighbouring property", 0.5, 1.3)],
        "prod": [("says a faulty batch damaged their production", 0.5, 2), ("claims you broke a supply contract", 0.55, 1.4)],
        "other": [("says you broke the terms of your agreement", 0.55, 1)],
    ]

    public static func chanceWord(_ p: Double) -> String { p >= 0.65 ? "good" : p >= 0.5 ? "fair" : p >= 0.35 ? "weak" : "poor" }

    /// A customer sues. The manager decides if there is one; otherwise the owner gets three weeks. Original: `SPEC.g_lawsuit`.
    public static func begin(_ s: inout GameState, companyIndex i: Int, weeklyRevenue wk0: Double, data: GameData) {
        let co = s.companies[i]
        guard let bd = data.catalog[co.type] else { return }
        let cur = World(state: s, data: data).currency(co)
        let list = reasons[bd.family] ?? reasons["other"]!
        let pick = s.random.pick(list.indices.map { $0 })
        let why = list[pick]
        let country = data.countries[co.countryCode] ?? data.countries.countries[0]
        let who = s.random.pick(country.firstNames) + " " + s.random.pick(country.lastNames)
        let wk = max(cur.scaledPrice(3000), wk0)
        let claim = (max(cur.scaledPrice(25000), wk * 0.9 * why.2) / 1000).rounded() * 1000
        let big = claim >= cur.scaledPrice(150000) || why.2 >= 1.5
        let law = s.hasHeadOffice("law") || co.value("law")["own"].bool
        let p = clamp(why.1 + (co.quality - 60) / 200 + (law ? 0.08 : 0), 0.15, 0.85)
        let fee = (max(big ? cur.scaledPrice(25000) : cur.scaledPrice(8000), claim * (big ? 0.18 : 0.12)) * (law ? 0.6 : 1) / 1000).rounded() * 1000
        let settle = (claim * s.random.range(0.35, 0.55) / 1000).rounded() * 1000
        let weeks = big ? s.random.int(6, 12) : 0
        let d: JSONValue = .object(["who": .string(who), "why": .string(why.0), "claim": .number(claim), "big": .bool(big), "p": .number(p), "fee": .number(fee),
                                    "settle": .number(settle), "wks": .number(Double(weeks)), "done": false])
        let body = "\(who) \(why.0) and claims \(cur.display(claim)). \(big ? "A big case: it goes to the district court." : "A small case: settled at one hearing.") Your chances in court look \(chanceWord(p))."
        if let mid = co.managerID, let mgr = s.people[mid] {
            let choice = p >= 0.5 ? 1 : 0
            let result = resolve(&s, companyIndex: i, d: d, choice: choice, data: data)
            s.addMessage(from: co.name, title: "A customer is suing \(co.name)", body: "\(body) \(mgr.name) chose: \(choice == 0 ? "settle" : "go to court"). \(result.text)", companyID: co.id, tone: "bad")
            return
        }
        s.addMessage(kind: "ask", from: co.name, title: "A customer is suing \(co.name)", body: body, companyID: co.id, tone: "bad", status: "open",
                     options: [.option("Settle · \(cur.display(settle))", "Pay now and the case is closed."),
                               .option("Go to court · \(cur.display(fee)) lawyer", big ? "Ruling in \(weeks) weeks." : "Decided at one hearing.")],
                     action: "sue16", data: d, expiresWeek: s.week + 3)
        s.note("Decision needed: \(who) is suing \(co.name).", tone: "bad", companyID: co.id)
    }

    /// Settle or go to court. Returns what happened in words. Original: `sue`.
    @discardableResult
    static func resolve(_ s: inout GameState, companyIndex i: Int, d: JSONValue, choice: Int, data: GameData) -> (text: String, done: Bool) {
        if d["done"].bool { return ("", true) }
        let co = s.companies[i]
        let cur = World(state: s, data: data).currency(co)
        let id = co.id
        if choice == 0 {
            Incidents.loss(&s, companyID: id, amount: d["settle"].double, category: "liab", label: "Settlement: \(d["who"].string)", data: data)
            return ("Settled for \(cur.display(d["settle"].double)).", true)
        }
        Payments.companyPays(&s, companyID: id, amount: d["fee"].double, category: "oth", label: "Lawyer fees")
        if d["big"].bool {
            var court = s.rest["court16"]?.array ?? []
            court.append(.object(["id": .number(Double(s.makeID())), "co": .number(Double(id)), "w": .number(Double(s.week + d["wks"].int)), "d": d]))
            s.rest["court16"] = .array(court)
            return ("Court date: \(GameCalendar.dateString(week: s.week + d["wks"].int, dayOffset: 0)).", false)
        }
        var h = HashedRandom("\(s.seed):court:\(s.week):\(id):\(Int(d["claim"].double))")
        if h.next() < d["p"].double {
            let back = jsRound(d["fee"].double * 0.5)
            Payments.companyReceives(&s, companyID: id, amount: back, category: "rev", label: "Legal costs awarded")
            return ("You won. The claim was rejected and they pay \(cur.display(back)) of your costs.", true)
        }
        lose(&s, id, d, extra: jsRound(d["fee"].double * 0.4), data: data)
        return ("You lost. You pay the \(cur.display(d["claim"].double)) claim and part of their costs.", true)
    }

    static func lose(_ s: inout GameState, _ id: Int, _ d: JSONValue, extra: Double = 0, data: GameData) {
        Incidents.loss(&s, companyID: id, amount: d["claim"].double + extra, category: "liab", label: "Court: \(d["who"].string)", data: data)
        if let i = s.companyIndex(id) { s.companies[i].reputation = clamp(s.companies[i].reputation - (d["big"].bool ? 4.5 : 3), 0, 100) }
    }

    /// The owner answers the lawsuit message. Original: `ACTS.sue16`.
    public static func answer(_ s: inout GameState, message m: Message, option: Int, data: GameData) {
        guard let i = s.companyIndex(m.companyID) else { return }
        let r = resolve(&s, companyIndex: i, d: m.value("data"), choice: option, data: data)
        markDone(&s, messageID: m.id)
        if !r.text.isEmpty {
            let name = s.companies[i].name
            s.addMessage(from: name, title: option == 1 && !m.value("data")["big"].bool ? "Court ruling: \(m.value("data")["who"].string)" : "Lawsuit: \(m.value("data")["who"].string)",
                         body: r.text, companyID: m.companyID, tone: r.text.hasPrefix("You lost") ? "bad" : "n")
        }
    }

    static func markDone(_ s: inout GameState, messageID: Int) {
        guard let k = s.inbox.firstIndex(where: { $0.id == messageID }) else { return }
        var d = s.inbox[k].value("data"); d["done"] = true; s.inbox[k].set("data", d)
    }

    /// Unanswered lawsuits are lost by default; cases with a court date are decided on the day. Original: `courtWeek`.
    public static func weekly(_ s: inout GameState, data: GameData) {
        for k in s.inbox.indices {
            let m = s.inbox[k]
            guard m.actionID == "sue16", m.status == "done", m.int("pick") == -1 || m.flag("auto"), !m.value("data")["done"].bool, let i = s.companyIndex(m.companyID) else { continue }
            var d = m.value("data"); d["done"] = true; s.inbox[k].set("data", d)
            lose(&s, m.companyID, d, data: data)
            let cur = World(state: s, data: data).currency(s.companies[i])
            s.addMessage(from: s.companies[i].name, title: "Lost by default: \(d["who"].string)",
                         body: "Nobody answered the lawsuit, so the court ruled for \(d["who"].string). You pay \(cur.display(d["claim"].double)).", companyID: m.companyID, tone: "bad")
        }
        var keep: [JSONValue] = []
        for x in s.rest["court16"]?.array ?? [] {
            if s.week < x["w"].int { keep.append(x); continue }
            guard let i = s.companyIndex(x["co"].int), s.companies[i].status.isLive else { continue }
            let d = x["d"], id = s.companies[i].id
            let cur = World(state: s, data: data).currency(s.companies[i])
            var h = HashedRandom("\(s.seed):ruling:\(x["id"].int)")
            if h.next() < d["p"].double {
                let back = jsRound(d["fee"].double * 0.6)
                Payments.companyReceives(&s, companyID: id, amount: back, category: "rev", label: "Legal costs awarded")
                s.addMessage(from: "District court", title: "You won against \(d["who"].string)",
                             body: "The court rejected the claim that \(d["who"].string) \(d["why"].string). They pay \(cur.display(back)) of your legal costs.", companyID: id, tone: "good")
            } else {
                lose(&s, id, d, extra: jsRound(d["fee"].double * 0.5), data: data)
                s.addMessage(from: "District court", title: "You lost against \(d["who"].string)",
                             body: "The court found for \(d["who"].string), who \(d["why"].string). You pay \(cur.display(d["claim"].double)) plus part of their costs.", companyID: id, tone: "bad")
            }
        }
        s.rest["court16"] = .array(keep)
    }
}
