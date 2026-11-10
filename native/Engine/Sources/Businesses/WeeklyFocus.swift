import Foundation
import GameCore
import Countries
import Finance

public enum WeeklyFocus {
    public static let action = "wfoc"
    public static let effect = 0.03
    public static let perkEvery = 4, perkTiers = 3
    public static let perkStep = 0.25
    static let historyKept = 12, baseWeeks = 4

    public struct Option: Identifiable, Equatable, Sendable {
        public var id: String, title: String, detail: String
    }
    public static let all: [Option] = [
        Option(id: "push", title: "Push sales", detail: "A small promotion: a few more customers next week, paid for with a little marketing."),
        Option(id: "lean", title: "Cut costs", detail: "Tighter buying and rota: costs run a touch lower, the service a touch thinner."),
        Option(id: "train", title: "Train the team", detail: "Time and money on skills: the team feels it and customers notice a little."),
    ]

    public struct Result: Identifiable, Equatable, Sendable {
        public var id: Int { week }
        public var week: Int, companyID: Int, pick: String
        public var revenue: Double, usualRevenue: Double, gross: Double, usualGross: Double
        public var revenueChange: Double? { usualRevenue > 0 ? revenue / usualRevenue - 1 : nil }
        public var grossChange: Double? { usualGross > 0 ? gross / usualGross - 1 : nil }
    }

    public struct Summary: Equatable, Sendable {
        public var planned: Int
        public var tier: Int
        public var toNext: Int?
        public var openMessageID: Int?
        public var perkText: String
    }

    static func tier(_ planned: Int) -> Int { min(perkTiers, planned / perkEvery) }
    static func strength(_ planned: Int) -> Double { effect * (1 + perkStep * Double(tier(planned))) }

    public static func summary(_ s: GameState) -> Summary {
        let n = s.rest["wfoc"]?["n"].int ?? 0
        let t = tier(n)
        let msg = s.inbox.first { $0.status == "open" && $0.actionID == action }
        let text = t == 0 ? "Plan a few weeks and your routine starts to pay a little more."
            : "Your routine is settled: plans land about \(Int(jsRound(perkStep * Double(t) * 100)))% better."
        return Summary(planned: n, tier: t, toNext: t >= perkTiers ? nil : (t + 1) * perkEvery - n, openMessageID: msg?.id, perkText: text)
    }

    public static func results(_ s: GameState) -> [Result] {
        (s.rest["wfoc"]?["hist"].array ?? []).reversed().map {
            Result(week: $0["w"].int, companyID: $0["co"].int, pick: $0["pick"].string, revenue: $0["rev"].double, usualRevenue: $0["bRev"].double,
                   gross: $0["g"].double, usualGross: $0["bG"].double)
        }
    }

    public static func option(_ id: String) -> Option? { all.first { $0.id == id } }

    public static func weekly(_ s: inout GameState, data: GameData) {
        guard Unlocks.isOpen(s, "focus") else { return }
        recordWeek(&s)
        if let cur = s.rest["wfoc"]?["cur"], !cur.isNull {
            if cur["w"].int == s.week - 1, !cur["pick"].string.isEmpty { report(&s, cur: cur) }
            else if cur["w"].int < s.week { s.rest["wfoc"]?["cur"] = .null }
        }
        offer(&s, data: data)
    }

    static func recordWeek(_ s: inout GameState) {
        var f = s.rest["wfoc"] ?? .object([:])
        var revs = f["revs"]
        for co in s.companies where co.status == .open {
            var l = revs["\(co.id)"].array
            let rev = Engagement.lastWeekRevenue(co)
            l.append(.object(["r": .number(rev), "g": .number(rev - max(0, co.value("lastW")["cogs"].double))]))
            if l.count > 8 { l.removeFirst(l.count - 8) }
            revs["\(co.id)"] = .array(l)
        }
        f["revs"] = revs
        s.rest["wfoc"] = f
    }

    static func usual(_ s: GameState, companyID: Int, excludingLast n: Int) -> (rev: Double, gross: Double)? {
        let l = s.rest["wfoc"]?["revs"]["\(companyID)"].array ?? []
        let base = Array(l.dropLast(n).suffix(baseWeeks))
        guard base.count >= 2 else { return nil }
        let c = Double(base.count)
        return (base.reduce(0) { $0 + $1["r"].double } / c, base.reduce(0) { $0 + $1["g"].double } / c)
    }

    static func offer(_ s: inout GameState, data: GameData) {
        guard let co = Engagement.mainCompany(s), !s.inbox.contains(where: { $0.status == "open" && $0.actionID == action }) else { return }
        let opts = all.filter { $0.id != "train" || !co.staff.isEmpty }
        let strong = strength(s.rest["wfoc"]?["n"].int ?? 0)
        var options: [JSONValue] = []
        for o in opts {
            var fx: [String: JSONValue] = [:]
            if o.id != "lean" { fx["cash"] = .number(-Engagement.spend(s, co, share: strong, data: data)) }
            options.append(.option(o.title, o.detail, effects: fx))
        }
        options.append(.option("Leave it this week", "No plan. Nothing is lost."))
        let body = "\(co.name): pick one thing to lean on for the week ahead. A small, bounded nudge of about \(Int(jsRound(strong * 100)))%."
        s.addMessage(kind: "ask", from: "Weekly plan", title: "Weekly plan for \(co.name)", body: body, companyID: co.id, tone: "n", status: "open", options: options,
                     action: action, data: .object(["ids": .array(opts.map { .string($0.id) })]), expiresWeek: s.week + 1, sev: 1)
        var f = s.rest["wfoc"] ?? .object([:])
        f["cur"] = .object(["w": .number(Double(s.week)), "co": .number(Double(co.id)), "pick": ""])
        s.rest["wfoc"] = f
    }

    public static func answer(_ s: inout GameState, message m: Message, option idx: Int, data: GameData) {
        let ids = m.value("data")["ids"].array.map { $0.string }
        guard ids.indices.contains(idx), let ci = s.companyIndex(m.companyID), s.companies[ci].status == .open else { return }
        let pick = ids[idx]
        var f = s.rest["wfoc"] ?? .object([:])
        let n = f["n"].int
        let e = strength(n)
        let co = s.companies[ci]
        switch pick {
        case "push":
            Engagement.addModifier(&s, ci, key: "dem", multiplier: 1 + e, weeks: 2)
            _ = Payments.companyPays(&s, companyID: co.id, amount: Engagement.spend(s, co, share: e, data: data), category: "mkt", label: "Weekly plan: sales push")
        case "lean":
            Engagement.addModifier(&s, ci, key: "cogsup", multiplier: 1 - e, weeks: 2)
            Engagement.addModifier(&s, ci, key: "dem", multiplier: 1 - e / 2, weeks: 2)
        default:
            _ = Payments.companyPays(&s, companyID: co.id, amount: Engagement.spend(s, co, share: e, data: data), category: "oth", label: "Weekly plan: team training")
            s.companies[ci].set("mood", min(100, (co.value("mood").isNull ? 60 : co.num("mood")) + 3))
            Engagement.addModifier(&s, ci, key: "dem", multiplier: 1 + e / 2, weeks: 2)
        }
        f["n"] = .number(Double(n + 1))
        let base = usual(s, companyID: co.id, excludingLast: 0)
        f["cur"] = .object(["w": .number(Double(s.week)), "co": .number(Double(co.id)), "pick": .string(pick),
                            "bRev": .number(base?.rev ?? 0), "bG": .number(base?.gross ?? 0)])
        s.rest["wfoc"] = f
        if tier(n + 1) > tier(n) {
            s.addMessage(from: "Weekly plan", title: "Your routine is settling in",
                         body: "\(n + 1) planned weeks. Plans now land a little better, and missing a week never takes that away.", tone: "good")
        }
    }

    static func report(_ s: inout GameState, cur: JSONValue) {
        let cid = cur["co"].int, pick = cur["pick"].string
        guard let co = s.company(cid), let o = option(pick) else { return }
        let rev = Engagement.lastWeekRevenue(co)
        let gross = rev - max(0, co.value("lastW")["cogs"].double)
        let r = Result(week: s.week, companyID: cid, pick: pick, revenue: rev, usualRevenue: cur["bRev"].double, gross: gross, usualGross: cur["bG"].double)
        var f = s.rest["wfoc"] ?? .object([:])
        var h = f["hist"].array
        h.append(.object(["w": .number(Double(r.week)), "co": .number(Double(cid)), "pick": .string(pick), "rev": .number(rev), "bRev": .number(r.usualRevenue),
                          "g": .number(gross), "bG": .number(r.usualGross)]))
        if h.count > historyKept { h.removeFirst(h.count - historyKept) }
        f["hist"] = .array(h)
        f["cur"] = .null
        s.rest["wfoc"] = f
        let line: String
        if let c = r.revenueChange, let g = r.grossChange {
            line = "Takings were \(Engagement.percentText(c)) and gross profit \(Engagement.percentText(g)) against a usual week. Other things move a week too, so read it as a hint, not a verdict."
        } else {
            line = "It is too early to compare with a usual week. The numbers will be there next time."
        }
        let good = (r.revenueChange ?? 0) + (r.grossChange ?? 0) >= 0
        s.addMessage(from: "Weekly plan", title: "Last week's plan: \(o.title.lowercased())", body: "\(co.name). \(line)", companyID: cid,
                     tone: r.revenueChange == nil ? "n" : good ? "good" : "n")
    }
}
