import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Bigger stories with real stakes: an answer now, and the consequence a week or two later.
/// At most two in four weeks, at least two weeks apart, and only for companies past their first weeks.
public enum StakeStories {
    static let key = "stk"
    public static let windowWeeks = 4
    public static let perWindow = 2
    public static let gapWeeks = 2
    static let weeklyChance = 0.35
    public static let minimumAgeWeeks = 12
    /// Existing stories that carry real stakes join the new ones in the draw.
    public static let pool: Set<String> = ["st_inspect", "st_viral", "st_contract", "st_poach", "e_reputation", "s_bigcust"]

    /// Weeks in which a stake story fired, most recent last.
    public static func firedWeeks(_ s: GameState) -> [Int] { (s.rest[key]?["w"].array ?? []).map { (v: JSONValue) -> Int in v.int } }

    /// True when the cap and the gap leave room for another story this week.
    public static func room(_ s: GameState) -> Bool {
        let recent: [Int] = firedWeeks(s).filter { (w: Int) -> Bool in s.week - w < windowWeeks }
        return recent.count < perWindow && recent.allSatisfy { (w: Int) -> Bool in s.week - w >= gapWeeks }
    }

    static func eligible(_ s: GameState, data: GameData) -> [Int] {
        StrategicDecisions.liveCompanies(s, data).filter { (i: Int) -> Bool in
            let co: Company = s.companies[i]
            return s.week - (co.openedWeek ?? co.foundedWeek) >= minimumAgeWeeks && co.lastWeekUnits > 0.5
        }
    }

    /// The weekly draw. Uses a hashed roll, so the game's own random sequence is untouched on weeks without a story.
    static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        guard room(s), EventEngine.decisionRoom(s) else { return }
        let cos: [Int] = eligible(s, data: data)
        guard !cos.isEmpty else { return }
        var h = HashedRandom("\(s.seed):stake:\(s.week)")
        guard h.next() < weeklyChance else { return }
        let i: Int = cos[min(cos.count - 1, Int(h.next() * Double(cos.count)))]
        _ = fire(&s, companyIndex: i, data: data, context: fc)
    }

    /// Fires one story from the pool at a company and records it against the cap.
    @discardableResult
    static func fire(_ s: inout GameState, companyIndex i: Int, data: GameData, context fc: FinanceContext) -> Bool {
        let list: [StrategicDecisions.Def] = StrategicDecisions.definitions.filter { (d: StrategicDecisions.Def) -> Bool in pool.contains(d.id) }
        guard StrategicDecisions.fireOne(&s, from: list, companyIndex: i, data: data, context: fc) else { return false }
        record(&s)
        return true
    }

    static func record(_ s: inout GameState) {
        var st: JSONValue = s.rest[key] ?? .object([:])
        let kept: [Int] = firedWeeks(s).filter { (w: Int) -> Bool in s.week - w < windowWeeks * 3 } + [s.week]
        st["w"] = .array(kept.map { (w: Int) -> JSONValue in .number(Double(w)) })
        s.rest[key] = st
    }
}

extension StrategicDecisions {
    static func moodOf(_ s: GameState, _ i: Int) -> Double { s.companies[i].value("mood").isNull ? 60 : s.companies[i].num("mood") }
    static func utilOf(_ s: GameState, _ i: Int) -> Double { s.companies[i].value("lastW")["util"].isNull ? 0.7 : s.companies[i].value("lastW")["util"].double }

    static func stakeDecisions() -> [Def] {
        var L: [Def] = []
        L.append(Def(id: "st_inspect", cls: "stake", w: 3, tone: "bad", exp: 1, def: 0,
                     title: { co, _, _ in "Inspectors are coming to \(co.name)" },
                     body: { _, _, _ in "A full inspection is booked for next week: safety, hygiene and the books. A bad result means a fine and a mark on your record." },
                     opts: [
                        Opt(label: "Carry on as usual", detail: "No cost now. The result depends on how well the place already runs.") { s, x in
                            later(&s, 1, "st_inspect_go", x.i, .object(["m": "own"])) },
                        Opt(label: "Hire a consultant to prepare", detail: "Costs about a third of a week's sales. They know what inspectors look for.") { s, x in
                            pay(&s, x, x.wk(s) * 0.35, "oth", "Inspection consultant")
                            later(&s, 1, "st_inspect_go", x.i, .object(["m": "pro"])) },
                        Opt(label: "Close a day to check everything", detail: "Lose about a day of sales and go through it all yourself.") { s, x in
                            cap(&s, x, 0.85, 1)
                            later(&s, 1, "st_inspect_go", x.i, .object(["m": "shut"])) }]))
        L.append(Def(id: "st_viral", cls: "stake", w: 3, tone: "n", exp: 1, def: 0,
                     cond: { _, co, _ in co.awareness >= 15 },
                     title: { co, _, _ in "A post about \(co.name) is spreading fast" },
                     body: { _, _, _ in "A customer's video about you has thousands of views. The comments are split: some love the place, some do not." },
                     opts: [
                        Opt(label: "Stay out of it", detail: "Let it run its course. A well-liked place usually comes out ahead.") { s, x in
                            later(&s, 1, "st_viral_go", x.i, .object(["m": "quiet"])) },
                        Opt(label: "Reply with an offer for viewers", detail: "A discount for anyone who mentions the post. Costs a tenth of a week's sales.") { s, x in
                            pay(&s, x, x.wk(s) * 0.1, "oth", "Offer for viewers")
                            later(&s, 1, "st_viral_go", x.i, .object(["m": "offer"])) },
                        Opt(label: "Invite the poster back for free", detail: "A small cost. Whether they post again depends on what they find.") { s, x in
                            pay(&s, x, x.wk(s) * 0.03, "oth", "Invited guest")
                            later(&s, 1, "st_viral_go", x.i, .object(["m": "invite"])) }]))
        L.append(Def(id: "st_contract", cls: "stake", w: 3, tone: "good", exp: 1, def: 0,
                     make: { s, i, data, fc in
                         let k = fc.country(of: s.companies[i], s)
                         let wk = EventEngine.context(for: s.companies[i], data: data, country: k).wk
                         return .object(["v": num(r1000(wk * 13 * 0.25))]) },
                     title: { co, _, _ in "A large customer offers \(co.name) a three-month contract" },
                     body: { _, d, cur in "The work is worth about \(cur.display(d["v"].double)) over three months. Late or short deliveries cost a penalty and they talk about it." },
                     opts: [
                        Opt(label: "Turn it down", detail: "Nothing changes.") { _, _ in },
                        Opt(label: "Sign for the full volume", detail: "About a quarter more work for three months. Needs room in the schedule.") { s, x in
                            dem(&s, x, 1.25, 13)
                            later(&s, 2, "st_contract_go", x.i, .object(["m": "full", "v": num(x.d["v"].double)])) },
                        Opt(label: "Sign for half the volume", detail: "Smaller gain, and easier to deliver on time.") { s, x in
                            dem(&s, x, 1.12, 13)
                            later(&s, 2, "st_contract_go", x.i, .object(["m": "half", "v": num(x.d["v"].double)])) }]))
        L.append(Def(id: "st_poach", cls: "stake", w: 3, tone: "bad", exp: 1, def: 0,
                     cond: { _, co, _ in co.staff.count >= 2 },
                     make: { s, i, _, _ in
                         guard let m = bestPaid(s, i, 1).first else { return nil }
                         return .object(["sid": num(Double(m.id)), "n": .string(s.people[m.id]?.name ?? "Your best worker")]) },
                     title: { co, d, _ in "A rival wants \(d["n"].string) from \(co.name)" },
                     body: { _, d, _ in "\(d["n"].string) has an offer from a competitor with more pay. They have a week to decide." },
                     opts: [
                        Opt(label: "Let them decide", detail: "No cost. Whether they stay depends on the mood in the team.") { s, x in
                            later(&s, 1, "st_poach_go", x.i, .object(["m": "free", "sid": num(x.d["sid"].double)])) },
                        Opt(label: "Match the offer: +15% pay", detail: "They stay. The rest of the team notices the raise.") { s, x in
                            raiseOne(&s, x.i, staffID: x.d["sid"].int, by: 1.15)
                            later(&s, 1, "st_poach_go", x.i, .object(["m": "match", "sid": num(x.d["sid"].double)])) },
                        Opt(label: "Pay a one-off bonus", detail: "A month's pay now. It helps, but it is not a raise.") { s, x in
                            let wage: Double = s.companies[x.i].staff.first { (m: StaffMember) -> Bool in m.id == x.d["sid"].int }?.monthlyWage ?? 0
                            pay(&s, x, wage, "wages", "Retention bonus")
                            later(&s, 1, "st_poach_go", x.i, .object(["m": "bonus", "sid": num(x.d["sid"].double)])) }]))
        return L
    }

    static func raiseOne(_ s: inout GameState, _ i: Int, staffID: Int, by f: Double) {
        var st: [StaffMember] = s.companies[i].staff
        guard let k = st.firstIndex(where: { (m: StaffMember) -> Bool in m.id == staffID }) else { return }
        st[k].monthlyWage = jsRound(st[k].monthlyWage * f)
        s.companies[i].staff = st
    }

    /// The consequence of a stake story, a week or two after the answer. Returns false for ids it does not know.
    static func followUpStake(_ s: inout GameState, id: String, index k: Int, d: JSONValue, x: X) -> Bool {
        let co: Company = s.companies[k]
        let wk: Double = x.wk(s)
        let cur: Currency = x.cur
        func tell(_ title: String, _ body: String, _ tone: String) {
            s.addMessage(from: co.name, title: title, body: body, companyID: co.id, tone: tone)
            s.note(title, tone: tone, companyID: co.id)
        }
        switch id {
        case "st_inspect_go":
            let base: Double = clamp(0.3 + co.quality / 200 + co.num("books", 0.5) * 0.25, 0.2, 0.85)
            let pass: Double = d["m"].string == "pro" ? 0.88 : (d["m"].string == "shut" ? clamp(base + 0.2, 0.5, 0.92) : base)
            if s.random.chance(pass) {
                rep(&s, x, d["m"].string == "shut" ? 2 : 1)
                tell("Inspection passed at \(co.name)", "The inspectors found nothing to fine. Word gets around.", "good")
            } else {
                let fine: Double = jsRound(max(cur.scaledPrice(3000), wk * (d["m"].string == "own" ? 0.8 : 0.4)))
                pay(&s, x, fine, "fine", "Inspection fine")
                rep(&s, x, -3)
                tell("Inspection failed at \(co.name)", "Fine \(cur.display(fine)), and the report is public.", "bad")
            }
        case "st_viral_go":
            let m: String = d["m"].string
            let p: Double = m == "quiet" ? clamp(0.25 + co.reputation / 140, 0.25, 0.85) : (m == "offer" ? 0.75 : clamp(co.quality / 100, 0.2, 0.9))
            if s.random.chance(p) {
                if m == "invite" { rep(&s, x, 3); s.companies[k].awareness = clamp(s.companies[k].awareness + 4, 0, 100) }
                else { dem(&s, x, m == "offer" ? 1.15 : 1.1, 4); s.companies[k].awareness = clamp(s.companies[k].awareness + 6, 0, 100) }
                tell("The post did \(co.name) good", "New faces came in because of it. The buzz lasts a few weeks.", "good")
            } else {
                rep(&s, x, m == "invite" ? -1 : -3)
                if m == "quiet" { dem(&s, x, 0.92, 4) }
                tell("The post turned against \(co.name)", m == "offer" ? "People called the offer a bribe. It passes, slowly." : "The negative side won the comments. Fewer people come in for a while.", "bad")
            }
        case "st_contract_go":
            let full: Bool = d["m"].string == "full"
            let stretched: Bool = utilOf(s, k) > (full ? 0.9 : 1.0)
            if stretched {
                let fine: Double = jsRound(d["v"].double * (full ? 0.12 : 0.06))
                pay(&s, x, fine, "fine", "Contract penalty")
                rep(&s, x, -3)
                dem(&s, x, full ? 0.8 : 0.9, 11)
                tell("Late deliveries on the contract at \(co.name)", "The customer charged a penalty of \(cur.display(fine)) and cut the order back.", "bad")
            } else {
                rep(&s, x, full ? 2 : 1)
                tell("The contract at \(co.name) is going well", "Deliveries are on time. The customer is talking about renewing.", "good")
            }
        case "st_poach_go":
            let sid: Int = d["sid"].int
            let name: String = s.people[sid]?.name ?? "Your worker"
            guard s.companies[k].staff.contains(where: { (m: StaffMember) -> Bool in m.id == sid }) else { return true }
            let m: String = d["m"].string
            if m == "match" {
                mood(&s, k, -3)
                tell("\(name) stays at \(co.name)", "The raise kept them. A few others now ask about their own pay.", "n")
                return true
            }
            let leave: Double = clamp((m == "bonus" ? 0.4 : 0.75) - moodOf(s, k) / (m == "bonus" ? 300 : 160), 0.05, 0.8)
            if s.random.chance(leave) {
                removeStaff(&s, k, id: sid)
                cap(&s, x, 0.9, 4)
                tell("\(name) left \(co.name) for the rival", "Work slows for a few weeks while the others cover.", "bad")
            } else {
                mood(&s, k, 2)
                tell("\(name) turned the rival down", "They are staying at \(co.name).", "good")
            }
        default:
            return false
        }
        return true
    }
}
