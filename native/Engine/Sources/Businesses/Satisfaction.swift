import Foundation
import GameCore
import Countries
import Finance

/// Customers' mood: complaints, word of mouth, buzz, and the limit of a local name.
/// Originals: `complaintsWeek`, `resolveC`, `mgrRefund` (small_team_and_rewards / complaints), the 'happy customers tell others'
/// step (local_prices), `hypeWeek`, `chainWeek` and `reachOf`, and the 'nobody working' step.
public enum Satisfaction {
    static let complaintTexts: [String: [String]] = [
        "svc": ["The job took far longer than promised.", "Nobody called me back about my booking.", "The invoice was higher than the quote.", "The work was sloppy and had to be redone."],
        "venue": ["The food was cold and we waited forever.", "We were charged for things we never ordered.", "A member of staff was rude to us.", "It was far too loud and crowded."],
        "retail": ["The product broke after a week.", "The shop refused my return.", "The price on the shelf was not what I paid.", "Nobody could help me find anything."],
        "logi": ["My parcel arrived damaged.", "The driver was two hours late.", "The car was dirty and smelled of smoke.", "I was charged twice for one trip."],
        "project": ["The site was left in a mess.", "You are weeks behind schedule.", "The finish is not what we agreed.", "Your workers blocked my driveway all week."],
        "prod": ["A delivery came with faulty units.", "The order was short.", "It arrived a week late."],
    ]

    public enum Answer: String, Sendable { case refund, sorry, ignore }

    // MARK: Complaints

    /// A week of complaints: new ones arrive when quality slips or the place is overrun; a manager answers them; unanswered ones
    /// older than two weeks turn into bad reviews.
    static func complaintsWeek(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData) {
        guard s.companies[i].status == .open, !Pricing.noWorkFamilies.contains(bd.family) else { return }
        var list = s.companies[i].value("compl").array
        let q = s.companies[i].quality
        let util = s.companies[i].value("lastW")["util"].double
        if s.random.chance(clamp(0.035 + (62 - q) * 0.004 + (util > 0.97 ? 0.03 : 0), 0.008, 0.22)) {
            let sev = (q < 45 && s.random.chance(0.4)) ? 3 : (s.random.chance(0.35) ? 2 : 1)
            let country = data.countries[s.companies[i].countryCode] ?? data.countries.countries[0]
            let who = s.random.pick(country.firstNames) + " " + s.random.pick(country.lastNames)
            let text = s.random.pick(complaintTexts[bd.family] ?? complaintTexts["svc"]!)
            list.insert(.object(["id": .number(Double(s.makeID())), "w": .number(Double(s.week)), "who": .string(who), "t": .string(text), "sev": .number(Double(sev)), "st": "open"]), at: 0)
        }
        s.companies[i].set("compl", .array(list))
        let mgrID = s.companies[i].managerID
        for k in 0..<list.count {
            guard list[k]["st"].string == "open" else { continue }
            let c = list[k]
            if let mgr = mgrID {
                let sk = s.people[mgr].map { $0.value("stats")["ops"].double / 100 } ?? 0.6
                let refund = managerRefunds(&s, i, bd, severity: c["sev"].int, data: data)
                let good = s.random.chance(0.55 + sk * 0.4)
                resolve(&s, i, bd, complaintAt: k, refund ? .refund : .sorry, good: good, data: data)
                var l = s.companies[i].value("compl").array; l[k]["by"] = "mgr"; s.companies[i].set("compl", .array(l))
            } else if let sk = ManagerModel.assistantSkill(s.companies[i], duty: "comp", people: s.people) {
                // An assistant manager with the complaints job answers them.
                let refund = managerRefunds(&s, i, bd, severity: c["sev"].int, data: data)
                resolve(&s, i, bd, complaintAt: k, refund ? .refund : .sorry, good: s.random.chance(0.55 + sk * 0.4), data: data)
                var l = s.companies[i].value("compl").array; l[k]["by"] = "asst"; s.companies[i].set("compl", .array(l))
            } else if s.policy.autoComplaints && c["sev"].int <= 2 {
                // The owner's standing instruction: staff deal with routine complaints the way a sensible manager would.
                let refund = managerRefunds(&s, i, bd, severity: c["sev"].int, data: data)
                resolve(&s, i, bd, complaintAt: k, refund ? .refund : .sorry, good: s.random.chance(0.75), data: data)
                var l = s.companies[i].value("compl").array; l[k]["by"] = "staff"; s.companies[i].set("compl", .array(l))
            } else if s.week - c["w"].int >= 2 {
                resolve(&s, i, bd, complaintAt: k, .ignore, good: nil, data: data)
                s.note("A complaint at \(s.companies[i].name) went unanswered. The customer left a bad review.", tone: "bad", companyID: s.companies[i].id)
            }
        }
        var l = s.companies[i].value("compl").array
        if l.count > 30 { l.removeLast(l.count - 30); s.companies[i].set("compl", .array(l)) }
    }

    /// Open complaints of a company, newest first, for the list on the company screen.
    public static func openComplaints(_ co: Company) -> [JSONValue] { co.value("compl").array.filter { $0["st"].string == "open" } }

    /// What a refund costs: the price of the job for small tickets, goodwill for big ones. Original: `refundOf`.
    static func refundAmount(ticket tk: Double, severity: Int, _ cur: Currency) -> Double {
        Double(severity) * min(tk * 1.5, cur.scaledPrice(1500) + tk * 0.06)
    }

    /// Managers refund when it is cheap relative to the business and the complaint is serious. Original: `mgrRefund`.
    static func managerRefunds(_ s: inout GameState, _ i: Int, _ bd: Trade, severity sev: Int, data: GameData) -> Bool {
        let w = World(state: s, data: data)
        let co = s.companies[i]
        let cur = w.currency(co)
        let amt = refundAmount(ticket: Pricing.ticket(co, bd, w), severity: sev, cur)
        let h = co.monthlyHistory.suffix(4)
        let weekly = h.isEmpty ? co.value("lastW")["rev"].double : h.reduce(0) { $0 + $1.revenue } / Double(h.count) / 4.33
        if amt > max(cur.scaledPrice(500), weekly * 0.15) {
            return sev >= 3 && amt < weekly * 0.4 && s.random.chance(0.5)
        }
        return sev >= 3 || (sev == 2 && s.random.chance(0.5))
    }

    /// Answer a complaint. `good` is the outcome of an apology if already decided. Original: `resolveC`.
    @discardableResult
    static func resolve(_ s: inout GameState, _ i: Int, _ bd: Trade, complaintAt k: Int, _ answer: Answer, good: Bool?, data: GameData) -> Bool? {
        var list = s.companies[i].value("compl").array
        guard list.indices.contains(k) else { return nil }
        let sev = list[k]["sev"].int
        list[k]["st"] = .string(answer.rawValue)
        list[k]["wd"] = .number(Double(s.week))
        var outcome: Bool? = nil
        switch answer {
        case .refund:
            let w = World(state: s, data: data)
            let co = s.companies[i]
            let cur = w.currency(co)
            let tk = Pricing.ticket(co, bd, w)
            let big = sev >= 3 && tk > cur.scaledPrice(4000)
            Payments.companyPays(&s, companyID: co.id, amount: jsRound(refundAmount(ticket: tk, severity: sev, cur)), category: "loss",
                                 label: big ? "Goodwill compensation to a customer" : "Refund to a customer")
            s.companies[i].reputation = clamp(s.companies[i].reputation + 0.3 * Double(sev), 0, 100)
        case .sorry:
            let ok = good ?? s.random.chance(sev == 1 ? 0.8 : sev == 2 ? 0.55 : 0.25)
            list[k]["ok"] = .bool(ok)
            outcome = ok
            s.companies[i].reputation = clamp(s.companies[i].reputation + (ok ? 0.2 : -0.6 * Double(sev)), 0, 100)
        case .ignore:
            s.companies[i].reputation = clamp(s.companies[i].reputation - 0.9 * Double(sev), 0, 100)
            if sev >= 3 { s.companies[i].awareness = clamp(s.companies[i].awareness - 1, 0, 100) }
        }
        // `Payments` may have rewritten the company; keep our list edits.
        s.companies[i].set("compl", .array(list))
        return outcome
    }

    // MARK: Word of mouth, buzz and reach

    /// Happy customers tell others, and a shop on a busy street is seen. Original: weekCo.after step 'happy customers tell others'.
    static func wordOfMouth(_ s: inout GameState, _ i: Int, _ bd: Trade) {
        let co = s.companies[i]
        guard co.status == .open, bd.normalDemand != 0, !Pricing.noWorkFamilies.contains(bd.family) else { return }
        let ref = bd.normalCapacity * co.size
        let served = ref > 0 ? min(1, co.lastWeekUnits / ref) : 0
        let qf = clamp((co.quality - 40) / 35, 0, 1.4)
        var g = 0.45 * served * qf
        let prem = co.value("prem")
        if !prem.isNull, prem["m2"].double != 0, Competition.isFootTraffic(prem["kind"].string) { g += 0.35 * (prem["loc"].isNull ? 1 : prem["loc"].double) }
        s.companies[i].awareness = clamp(co.awareness + g, 0, 100)
    }

    /// People who used you tell others: a busy business becomes known in its area, but not famous (the floor is at most 32). The
    /// floor follows how busy the last 26 weeks were (a young business has fewer weeks to average, so it rises over months), how
    /// good the work is and how cheap. Original: week.after step 'trades_in_hours weekly' (features/sales/trades_in_hours.js).
    /// Not ported: the review-score factor (reviews are not a native screen yet) and the hour-priced trades (plumber, electrician...).
    static func knownByUse(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData) {
        var co = s.companies[i]
        guard co.status == .open, !["fin", "energy", "hold", "club", "rent"].contains(bd.family) else { return }
        let x = bd.normalCapacity > 0 ? co.lastWeekUnits / (bd.normalCapacity * 0.6) : 0
        let history = (co.value("cu41").array.map { $0.double } + [min(4, x)]).suffix(26)
        co.set("cu41", .array(history.map { .number($0) }))
        let ratio = history.reduce(0, +) / 26
        let w = World(state: s, data: data)
        var qf = clamp(0.75 + (co.quality - 45) / 80, 0.6, 1.2)
        qf *= clamp(1 + (1 - w.balance.priceMultiplier(level: co.priceLevel)) * 0.8, 0.75, 1.3)
        let floor = min(32, 28 * min(1.2, ratio).squareRoot() * qf)
        if co.awareness < floor { co.awareness = clamp(co.awareness + (floor - co.awareness) * 0.08, 0, 100) }
        s.companies[i] = co
    }

    /// How much people sold to by a viral moment tell their friends, and what they think of the place afterwards. Original: `hypeWeek`.
    static func buzzWeek(_ s: inout GameState, _ i: Int) {
        var co = s.companies[i]
        let h = co.num("hype")
        if h < 0.5 { co.set("hype", 0); s.companies[i] = co; return }
        var dv = clamp((co.quality - 45) / 40, 0, 1) * 0.6 + clamp((co.reputation - 45) / 40, 0, 1) * 0.4
        let util = co.value("lastW")["util"]
        if !util.isNull, util.double > 0.97, h > 15 { dv *= 0.65 }
        if dv >= 0.45 {
            co.awareness = min(100, co.awareness + h * 0.1 * dv)
            co.reputation = min(100, co.reputation + h * 0.012 * dv)
        } else {
            co.reputation = max(0, co.reputation - h * 0.012 * (0.45 - dv))
            if h > 25, !co.value("flags")["hypeBad"].bool || co.value("flags")["hypeBad"].double == 0, s.random.chance(0.4) {
                var f = co.value("flags"); f["hypeBad"] = .number(Double(s.week)); co.set("flags", f)
                s.note("Crowds came to \(co.name) after the buzz, and left disappointed.", tone: "bad", companyID: co.id)
            }
        }
        co.set("hype", h * 0.86 < 1 ? 0 : h * 0.86)
        s.companies[i] = co
    }

    /// One shop is a local name; many outlets build a known brand. Original: `reachOf(co).cap` in `chainWeek`.
    static func reachCap(_ s: inout GameState, _ i: Int, data: GameData) {
        let w = World(state: s, data: data)
        let n = Double(Competition.chainOutlets(s.companies[i], w))
        let cap = clamp(36 + 17 * log2(n), 36, 100)
        s.companies[i].awareness = min(s.companies[i].awareness, cap)
    }

    // MARK: Nobody works there

    /// A company with no owner hours, no manager and no staff on duty closes until someone turns up. Original: weekCo.before 10.
    static func closeIfNobodyWorks(_ s: inout GameState, _ i: Int, _ bd: Trade) {
        let co = s.companies[i]
        if !Pricing.noWorkFamilies.contains(bd.family), co.status == .open, co.managerID == nil, !(co.ownerHours > 0), !co.staff.contains(where: { $0.noticeWeeks <= 0 }) {
            s.companies[i].status = .closed
            s.companies[i].set("closeW", 9999); s.companies[i].set("closeTot", 9999); s.companies[i].set("idle", 1)
            s.note("\(co.name) is closed: nobody works there. Rent, software and other running costs continue.", tone: "bad", companyID: co.id)
        } else if co.status == .closed, co.flag("idle"), co.managerID != nil || co.ownerHours > 0 || !co.staff.isEmpty {
            s.companies[i].status = .open
            s.companies[i].set("idle", 0)
            s.companies[i].set("closeW", 0)
        }
    }
}
