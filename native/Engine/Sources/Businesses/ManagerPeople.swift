import Foundation
import GameCore
import Countries
import Employees
import Finance

extension ManagerModel {

    public static let skillKeys: [(key: String, label: String)] = [
        ("ops", "Day-to-day operations"), ("people", "Leading people"), ("sales", "Winning customers"),
        ("fin", "Numbers and cost control"), ("risk", "Compliance and risk"), ("ethic", "Integrity")]
    public static let typeTitles: [String: String] = [
        "gen": "General manager", "ops": "Operations manager", "host": "Restaurant and kitchen manager", "site": "Site foreman",
        "sales": "Sales-driven manager", "tech": "Technical manager", "fin": "Financial / compliance manager", "ind": "Industrial plant manager",
        "fleet": "Fleet manager", "prop": "Property manager", "fund": "Investment manager", "energy": "Energy / asset manager",
        "pro": "Professional-services partner", "retail": "Store manager", "game": "Gaming and licence manager", "clin": "Clinic manager"]
    public static func title(_ bd: Trade) -> String { typeTitles[bd.managerType] ?? "General manager" }

    static let resumes = ["Previously ran a business unit.", "Former operations lead at a regional chain.", "Started as staff and rose to manager.",
                          "Consultant turned operator.", "Managed a competitor for years."]

    static func payBase(heads: Double) -> Double { 40000 + min(60000, heads * 2200) }

    static func askingPay(heads: Double, skill: Double, tier: String, experience exp: Double, cityWage: Double, inflation: Double) -> Double {
        var pay = payBase(heads: heads) * (0.85 + skill / 400) * cityWage * inflation
        pay *= 0.82 + 0.18 * min(1, exp / 9)
        return pay
    }

    public static func managerGoingRate(company co: Company?, state s: GameState, data: GameData) -> Double {
        let w = World(state: s, data: data)
        let country = co.map { w.country($0) } ?? w.countries[s.homeCountryCode]!
        let cityWage = (co.flatMap { w.city($0) }?.wage) ?? 1
        let cur = Currency(country: country, rates: w.rates)
        return cur.roundedStep(payBase(heads: Double(co?.staff.count ?? 3)) * cityWage * w.inflationIndex, about: 500)
    }
    static let assistantPayShare = 0.5
    public static func assistantGoingRate(company co: Company?, state s: GameState, data: GameData) -> Double {
        let w = World(state: s, data: data)
        let country = co.map { w.country($0) } ?? w.countries[s.homeCountryCode]!
        return Currency(country: country, rates: w.rates).roundedStep(managerGoingRate(company: co, state: s, data: data) * assistantPayShare, about: 500)
    }
    static func teamPayFactor(_ key: String) -> Double {
        key == "ceo" ? 2.4 : key == "reg" ? 1.6 : teamRoles.first { $0.key == key }?.payFactor ?? 1
    }

    @discardableResult
    public static func generateCandidate(company co: Company?, type: String, faces: Bool = true, state s: inout GameState, data: GameData) -> Person {
        let w = World(state: s, data: data)
        let tier = s.random.weightedPick([("mid", 6.0), ("senior", 6.0), ("young", 3.0)], weight: { $0.1 })!.0
        let T = Hiring.tiers[tier]!
        var st: [String: Double] = [:]
        for q in skillKeys { st[q.key] = clamp(jsRound(s.random.range(35, 90)) + (tier == "senior" ? 4 : tier == "young" ? -8 : 0), 5, 99) }
        let liar = s.random.chance(0.25)
        var claimed = st
        for q in skillKeys where liar && q.key != "ethic" { claimed[q.key] = clamp(st[q.key]! + Double(s.random.int(6, 24)), 0, 99) }
        if liar { claimed["ethic"] = clamp(st["ethic"]! + Double(s.random.int(8, 25)), 0, 99) }
        let exp = jsRound(s.random.range(T.exp.0, T.exp.1) * 2) / 2
        let country = co.map { w.country($0) } ?? w.countries[s.homeCountryCode]!
        let cityWage = (co.flatMap { w.city($0) }?.wage) ?? 1
        let heads = Double(co?.staff.count ?? 3)
        let skill = (st["ops"]! + st["people"]! + st["sales"]! + st["fin"]!) / 4
        let pay = askingPay(heads: heads, skill: skill, tier: tier, experience: exp, cityWage: cityWage, inflation: w.inflationIndex)
        let cur = Currency(country: country, rates: w.rates)
        var p = Person(raw: [:])
        p.id = s.makeID()
        p.name = Hiring.uniqueName(Hiring.personName(country, &s.random), state: s)
        p.age = s.random.int(T.age.0 + (tier == "young" ? 6 : 0), T.age.1)
        p.role = "manager"
        p.set("mtype", type); p.set("tier", tier)
        p.set("stats", .object(st.mapValues { .number($0) })); p.set("claimed", .object(claimed.mapValues { .number($0) }))
        p.set("lie", liar); p.skill = skill
        p.claimedSkill = (claimed["ops"]! + claimed["people"]! + claimed["sales"]! + claimed["fin"]!) / 4
        p.askingMonthlyWage = cur.roundedStep(pay, about: 500)
        p.set("exp", exp); p.employerID = 0; p.set("q", .object([:])); p.set("qLeft", 3)
        p.set("pers", s.random.pick(Hiring.personalities)); p.set("resume", s.random.pick(resumes))
        p.set("golden", exp < 3 && s.random.chance(0.12))
        s.people[p.id] = p
        if faces { FaceBook.assign(personID: p.id, countryCode: country.code, style: .suit, state: &s) }
        return p
    }

    public static func searchFee(currency cur: Currency) -> Double { cur.scaledPrice(15000) }

    public static func search(_ s: inout GameState, companyID: Int, data: GameData) -> [Person]? {
        guard let ci = s.companyIndex(companyID), let bd = data.catalog[s.companies[ci].type] else { return nil }
        let cur = World(state: s, data: data).currency(s.companies[ci])
        let fee = searchFee(currency: cur)
        guard s.companies[ci].cash >= fee || Payments.liquid(s) >= fee else { return nil }
        Payments.companyPays(&s, companyID: companyID, amount: fee, category: "oth", label: "Executive search")
        let co = s.companies[ci]
        var out = (0..<3).map { _ in generateCandidate(company: co, type: bd.managerType, state: &s, data: data) }
        out.append(generateCandidate(company: co, type: "gen", state: &s, data: data))
        return out
    }

    @discardableResult
    public static func findSuccessor(_ s: inout GameState, companyID: Int, data: GameData) -> [Person]? {
        guard let ci = s.companyIndex(companyID), s.companies[ci].managerID != nil else { return nil }
        let waiting = successorCandidates(s, companyID: companyID)
        if !waiting.isEmpty { return waiting }
        guard let list = search(&s, companyID: companyID, data: data) else {
            s.addMessage(kind: "info", from: "Your management", title: "No search at \(s.companies[ci].name)", body: "There is not enough cash to pay the executive search.", companyID: companyID, tone: "bad", status: "done")
            return nil
        }
        s.companies[ci].set("succ", .array(list.map { .number(Double($0.id)) })); s.companies[ci].set("succW", s.week)
        let cur = World(state: s, data: data).currency(s.companies[ci])
        let lines = list.map { "\($0.name), \($0.age), asks \(cur.display($0.askingMonthlyWage)) a month" }.joined(separator: "; ")
        s.addMessage(kind: "info", from: "Your management", title: "Candidates to run \(s.companies[ci].name)",
                     body: "The search found \(list.count): \(lines). Interview them and hire one on the Team page.", companyID: companyID, tone: "good", status: "done")
        return list
    }
    public static func successorCandidates(_ s: GameState, companyID: Int) -> [Person] {
        guard let co = s.company(companyID), s.week - co.int("succW") <= 26 else { return [] }
        return co.value("succ").array.compactMap { s.people[$0.int] }.filter { $0.employerID == 0 }
    }

    @discardableResult
    public static func interview(_ s: inout GameState, personID: Int, key: String) -> Double? {
        guard var n = s.people[personID], skillKeys.contains(where: { $0.key == key }) else { return nil }
        var q = n.value("q")
        if !q[key].isNull { return q[key].double }
        let left = n.value("qLeft").isNull ? 3 : n.int("qLeft")
        guard left > 0 else { return nil }
        let claim = n.value("claimed")[key].double, truth = n.value("stats")[key].double
        let said = clamp(claim + s.random.gauss() * 3, 0, 100)
        let slip = n.flag("lie") && s.random.chance(0.2) ? truth : said
        q[key] = .number(jsRound(slip))
        n.set("q", q); n.set("qLeft", left - 1)
        s.people[personID] = n
        return jsRound(slip)
    }

    public static func referenceCheck(_ s: inout GameState, personID: Int, companyID: Int, data: GameData) -> Bool {
        guard let ci = s.companyIndex(companyID), var n = s.people[personID] else { return false }
        let fee = World(state: s, data: data).currency(s.companies[ci]).scaledPrice(2500)
        guard s.companies[ci].cash >= fee || Payments.liquid(s) >= fee else { return false }
        Payments.companyPays(&s, companyID: companyID, amount: fee, category: "oth", label: "Reference check")
        n.set("ref", true); s.people[personID] = n
        return true
    }

    public static func overall(_ n: Person) -> Double {
        let st = n.value("stats")
        return (st["ops"].double + st["people"].double + st["sales"].double + st["fin"].double + st["risk"].double) / 5
    }

    public enum HireResult: Equatable { case ok, taken, refused, needsPremises, countered(Negotiation.Counter), walkedAway }

    static func appoint(_ s: inout GameState, companyIndex ci: Int, person n: Person, wage: Double, data: GameData) {
        var co = s.companies[ci]
        if let old = co.managerID, old != n.id, var o = s.people[old] { o.employerID = 0; s.people[old] = o }
        var roles: [String: JSONValue] = [:]
        for m in co.staff where m.noticeWeeks <= 0 && !m.flag("seas") { roles[m.role] = .number((roles[m.role]?.double ?? 0) + 1) }
        let hist = co.monthlyHistory.suffix(3)
        let rev = hist.isEmpty ? 0 : hist.reduce(0) { $0 + $1.revenue } / Double(hist.count)
        let prof = hist.isEmpty ? 0 : hist.reduce(0) { $0 + $1.profit } / Double(hist.count)
        co.set("mgrBase", .object(["roles": .object(roles), "rev": .number(rev), "prof": .number(prof), "w": .number(Double(s.week))]))
        co.set("mgrNotice", .null)
        co.managerID = n.id
        co.managerMonthlyWage = wage
        co.set("mgrW0", s.week)
        co.ownerHours = 0
        co.set("mood", 60)
        var fl = co.value("flags"); fl["fraud"] = 0; co.set("flags", fl)
        let cur = World(state: s, data: data).currency(co)
        let chosen = Budget.isChosen(co.value("auth"))
        let b: Budget = chosen ? Budget.of(co.value("auth")) : max(Budget.of(co.value("auth")), .normal)
        co.set("auth", Budget.authRecord(b, spend: b.spendLimit(cur, monthlyRevenue: rev), chosen: chosen))
        if co.status == .closed, co.flag("idle") { co.status = .open; co.set("idle", 0); co.set("closeW", 0) }
        s.companies[ci] = co
        var p = n; p.employerID = co.id; s.people[n.id] = p
    }

    public static func bonusWorth(_ co: Company, _ share: Double) -> Double {
        guard share > 0 else { return 0 }
        let h = co.monthlyHistory.suffix(3)
        return max(0, h.reduce(0) { $0 + $1.profit } / Double(max(1, min(3, h.count)))) * share * 0.7
    }

    public static func hire(_ s: inout GameState, personID: Int, companyID: Int, monthlyWage proposed: Double, profitBonus bonus: Double = 0, data: GameData) -> HireResult {
        guard let ci = s.companyIndex(companyID), let n0 = s.people[personID], let bd = data.catalog[s.companies[ci].type] else { return .refused }
        if n0.employerID != 0 { return .taken }
        let w = World(state: s, data: data)
        let wage = max(proposed, w.minimumWage(s.companies[ci]))
        let share = clamp(bonus, 0, 0.3)
        let worth = bonusWorth(s.companies[ci], share)
        let offered = wage + worth
        switch Hiring.answer(personID: personID, employer: companyID, rank: "manager", offer: offered, currency: w.currency(s.companies[ci]), about: 500, state: &s).answer {
        case .refuse: return .refused
        case .walkAway: return .walkedAway
        case .counter(let c): return .countered(Negotiation.Counter(amount: max(c.amount - worth, 0), isFinal: c.isFinal))
        case .accept: break
        }
        guard let n = s.people[personID] else { return .refused }
        appoint(&s, companyIndex: ci, person: n, wage: wage, data: data)
        s.companies[ci].managerProfitBonus = share
        s.note("\(n.name) is now \(title(bd).lowercased()) of \(s.companies[ci].name).", tone: "good", companyID: companyID)
        return .ok
    }

    @discardableResult
    public static func fire(_ s: inout GameState, companyID: Int, data: GameData) -> Double {
        Dismissal.dismissManager(&s, companyID: companyID, data: data)?.total ?? 0
    }

    static func stepDown(_ s: inout GameState, _ ci: Int) {
        s.companies[ci].managerID = nil
        s.companies[ci].managerMonthlyWage = 0
        s.companies[ci].set("mgrNotice", .null)
        s.companies[ci].managerProfitBonus = 0
        s.companies[ci].ownerHours = 40
    }

    public static func raiseManager(_ s: inout GameState, companyID: Int, percent: Double = 0.08, data: GameData) {
        guard let ci = s.companyIndex(companyID), s.companies[ci].managerID != nil, percent > 0 else { return }
        let cur = World(state: s, data: data).currency(s.companies[ci])
        s.companies[ci].managerMonthlyWage = cur.roundedStep(s.companies[ci].managerMonthlyWage * (1 + percent), about: 100)
        s.companies[ci].set("mood", min(100, mood(s.companies[ci]) + 8 * min(1, percent / 0.08)))
    }

    static func mood(_ co: Company) -> Double { co.value("mood").isNull ? 60 : co.num("mood") }

    public static func moveFactor(from a: Company, to b: Company, data: GameData) -> Double {
        if a.type == b.type { return 1 }
        return data.catalog[a.type]?.family == data.catalog[b.type]?.family ? 0.9 : 0.7
    }

    public static func move(_ s: inout GameState, fromCompanyID a: Int, toCompanyID b: Int, data: GameData) -> Bool {
        guard let ai = s.companyIndex(a), let bi = s.companyIndex(b), let mid = s.companies[ai].managerID, s.companies[bi].managerID == nil,
              var n = s.people[mid], let tb = data.catalog[s.companies[bi].type], tb.family != "club" else { return false }
        let f = moveFactor(from: s.companies[ai], to: s.companies[bi], data: data)
        n.set("exp", jsRound(n.num("exp") * f * 2) / 2)
        s.people[mid] = n
        let wage = s.companies[ai].managerMonthlyWage, md = mood(s.companies[ai]), bonus = s.companies[ai].managerProfitBonus
        stepDown(&s, ai)
        appoint(&s, companyIndex: bi, person: n, wage: wage, data: data)
        s.companies[bi].managerProfitBonus = bonus
        s.companies[bi].set("mood", md)
        s.note("\(n.name) now manages \(s.companies[bi].name).", tone: "n", companyID: b)
        GrowthPaths.installSuccessor(&s, companyID: a, data: data)
        return true
    }

    public static func resign(_ s: inout GameState, companyIndex ci: Int, why: String, to rival: String = "") {
        let co = s.companies[ci]
        guard let mid = co.managerID, let n = s.people[mid], co.value("mgrNotice").isNull else { return }
        let wk = 13 + Int(HashedRandom.first("notice:\(n.id):\(s.week)") * 14)
        s.companies[ci].set("mgrNotice", .object(["w": .number(Double(s.week + wk)), "npc": .number(Double(mid)), "why": .string(why), "to": .string(rival)]))
        s.companies[ci].set("mood", max(0, mood(co) - 5))
        let said = ManagerVoice.say(&s, companyIndex: ci, manager: n, bd: nil, situation: .resign, vars: ["why": why.isEmpty ? "" : why.prefix(1).uppercased() + why.dropFirst() + "."])
        s.addMessage(kind: "info", from: n.name, title: "\(n.name) has resigned from \(co.name)",
                     body: "\(said) I will work my notice and leave on \(GameCalendar.dateString(week: s.week + wk, dayOffset: 0))\(rival.isEmpty ? "" : ", when I start at \(rival)"). That gives you about \(Int(saturating: jsRound(Double(wk) / 4.33))) months to find someone. Hire my successor before then and I will hand over and go.",
                     companyID: co.id, tone: "bad", status: "open",
                     options: [.option("Find a successor", "Pays for an executive search now."), .option("I will handle it", "")],
                     action: ManagerTargets.successorAction, data: .object(["co": .number(Double(co.id))]), expiresWeek: s.week + wk)
    }

    static func noticeWeek(_ s: inout GameState, companyIndex ci: Int, data: GameData) {
        let t = s.companies[ci].value("mgrNotice")
        if t.isNull { return }
        guard s.companies[ci].managerID == t["npc"].int else { s.companies[ci].set("mgrNotice", .null); return }
        guard Double(s.week) >= t["w"].double else { return }
        let n = s.people[t["npc"].int]
        Dismissal.dismissManager(&s, companyID: s.companies[ci].id, reason: .resignation, noticeServed: true, data: data)
        s.companies[ci].set("mood", 60)
        let to = t["to"].string
        s.note("\(n?.name ?? "Your manager") has left \(s.companies[ci].name)\(to.isEmpty ? "" : " for \(to)"). You run it yourself until you hire a new manager.", tone: "bad", companyID: s.companies[ci].id)
    }

    static func rivalOffer(_ s: inout GameState, companyIndex ci: Int, data: GameData) {
        let co = s.companies[ci]
        guard let mid = co.managerID, let n = s.people[mid], co.value("mgrNotice").isNull, s.week - co.int("mgrW0") > 26 else { return }
        let open = s.inbox.contains { $0.companyID == co.id && $0.status == "open" && $0.actionID == "mgrpoach" }
        let underpaid = co.managerMonthlyWage < managerGoingRate(company: co, state: s, data: data) * 0.9
        guard !open, s.random.chance(0.0015 + (mood(co) < 45 ? 0.003 : 0) + (overall(n) > 70 ? 0.0015 : 0) + (underpaid ? 0.004 : 0)) else { return }
        let cur = World(state: s, data: data).currency(co)
        let up = cur.roundedStep(co.managerMonthlyWage * 0.15, about: 100)
        let pitch = ManagerVoice.say(&s, companyIndex: ci, manager: n, bd: data.catalog[co.type], situation: .poach, vars: ["up": cur.display(up)]) + (co.managerMonthlyWage < managerGoingRate(company: co, state: s, data: data) * 0.9 ? " I am paid under the going rate." : "")
        s.addMessage(kind: "ask", from: n.name, title: "A rival wants to hire \(n.name) away from \(co.name)",
                     body: pitch, companyID: co.id, tone: "bad", status: "open",
                     options: [.option("Match it", "+\(cur.display(up))/month. Most stay."), .option("Let them go", "They work their notice.")],
                     action: "mgrpoach", data: .object(["up": .number(up), "npc": .number(Double(n.id))]), expiresWeek: s.week + 2)
    }

    public static let assistantDuties: [(key: String, title: String, text: String)] = [
        ("comp", "Customer complaints", "Answers complaints before they become reviews"),
        ("insure", "Insurance", "Keeps basic insurance in place"),
        ("equip", "Equipment and stock", "Services worn equipment and keeps stock up")]

    public static func searchAssistants(_ s: inout GameState, companyID: Int, data: GameData) -> [Person]? {
        guard let ci = s.companyIndex(companyID) else { return nil }
        let cur = World(state: s, data: data).currency(s.companies[ci])
        let fee = cur.scaledPrice(2500)
        guard s.companies[ci].cash >= fee || Payments.liquid(s) >= fee else { return nil }
        Payments.companyPays(&s, companyID: companyID, amount: fee, category: "oth", label: "Job ad: assistant manager")
        return (0..<3).map { _ in
            var n = generateCandidate(company: s.companies[ci], type: "gen", state: &s, data: data)
            let st = n.value("stats")
            n.set("asst", true)
            n.skill = jsRound((st["ops"].double + st["people"].double) / 2)
            n.askingMonthlyWage = cur.roundedStep(n.askingMonthlyWage * assistantPayShare, about: 500)
            n.set("exp", max(0, jsRound(n.num("exp") * 0.6)))
            s.people[n.id] = n
            return n
        }
    }

    public enum OfferResult: Equatable { case ok, refused, taken, countered(Negotiation.Counter), walkedAway }

    static func offerResult(_ a: Negotiation.Answer) -> OfferResult? {
        switch a {
        case .accept: return nil
        case .refuse: return .refused
        case .walkAway: return .walkedAway
        case .counter(let c): return .countered(c)
        }
    }

    public static func hireAssistant(_ s: inout GameState, personID: Int, companyID: Int, monthlyWage w: Double, data: GameData) -> OfferResult {
        guard let ci = s.companyIndex(companyID), let n0 = s.people[personID] else { return .refused }
        if n0.employerID != 0 { return .taken }
        let reply = Hiring.answer(personID: personID, employer: companyID, rank: "assistant", offer: w, currency: World(state: s, data: data).currency(s.companies[ci]), about: 500, state: &s)
        if let r = offerResult(reply.answer) { return r }
        guard var n = s.people[personID] else { return .refused }
        n.employerID = companyID
        s.people[personID] = n
        s.companies[ci].set("asst", .object(["npc": .number(Double(personID)), "wage": .number(w), "duties": .array([]), "w0": .number(Double(s.week))]))
        return .ok
    }

    public static func toggleAssistantDuty(_ s: inout GameState, companyID: Int, duty: String) -> Bool {
        guard let ci = s.companyIndex(companyID), s.companies[ci].value("asst")["npc"].int != 0 else { return false }
        var a = s.companies[ci].value("asst")
        var d = a["duties"].array
        if let i = d.firstIndex(where: { $0.string == duty }) { d.remove(at: i) }
        else if d.count >= 2 { return false }
        else { d.append(.string(duty)) }
        a["duties"] = .array(d)
        s.companies[ci].set("asst", a)
        return true
    }

    public static func fireAssistant(_ s: inout GameState, companyID: Int, data: GameData) {
        guard let ci = s.companyIndex(companyID) else { return }
        let a = s.companies[ci].value("asst")
        guard a["npc"].int != 0 else { return }
        let social = World(state: s, data: data).country(s.companies[ci]).employerOnCost(monthlyWage: a["wage"].double)
        Dismissal.book(&s, payer: .company(companyID), notice: Dismissal.monthOfPay(wage: a["wage"].double, employerSocial: social))
        if var n = s.people[a["npc"].int] { n.employerID = 0; s.people[n.id] = n }
        s.companies[ci].set("asst", .null)
    }

    public static func assistantSkill(_ co: Company, duty: String, people: [Int: Person]) -> Double? {
        let a = co.value("asst")
        guard a["npc"].int != 0, a["duties"].array.contains(where: { $0.string == duty }), let n = people[a["npc"].int] else { return nil }
        return (n.skill.isZero ? 55 : n.skill) / 100
    }

    static func assistantWeek(_ s: inout GameState, companyIndex ci: Int, data: GameData) {
        let co = s.companies[ci]
        let a = co.value("asst")
        guard a["npc"].int != 0 else { return }
        guard let n = s.people[a["npc"].int] else { s.companies[ci].set("asst", .null); return }
        let social = World(state: s, data: data).country(co).employerOnCost(monthlyWage: a["wage"].double)
        Payments.companyPays(&s, companyID: co.id, amount: a["wage"].double * 12 / 52 * (1 + social), category: "wages")
        guard co.status == .open else { return }
        let sk = (n.skill.isZero ? 55 : n.skill) / 100
        let duties = a["duties"].array.map { $0.string }
        if duties.contains("equip") {
            var eq = s.companies[ci].value("eq")
            for (id, r) in eq.object.sorted(by: { $0.key < $1.key }) where id != "fit" && r["sub"].isNull && !r["soft"].bool && !r["cond"].isNull {
                let cost = r["cost"].double
                if r["cond"].double < 0.55 + sk * 0.1 && s.companies[ci].cash > cost * 0.1 {
                    Payments.companyPays(&s, companyID: co.id, amount: jsRound(cost * 0.04), category: "oth", label: "Equipment service")
                    eq[id]["cond"] = .number(min(1, r["cond"].double + 0.3))
                }
            }
            s.companies[ci].set("eq", eq)
        }
    }

    static func ensureStats(_ n: inout Person, role: String) {
        let b = n.skill
        func z(_ k: String) -> Double { (HashedRandom.first("st11:\(n.id):\(k)") - 0.5) * 20 }
        var st: [String: Double] = ["ops": b + z("ops"), "people": b + z("people"), "sales": b + z("sales"), "fin": b - 6 + z("fin"), "risk": b + z("risk"), "ethic": 55 + z("ethic")]
        if ["sales", "agent", "estate", "cardealer", "broker"].contains(role) { st["sales", default: 0] += 12 }
        if role == "acct" { st["fin", default: 0] += 15 }
        if role == "hr" { st["people", default: 0] += 12 }
        if role == "lead" { st["people", default: 0] += 6; st["ops", default: 0] += 6 }
        if role == "lawyer" { st["risk", default: 0] += 12 }
        if role == "consult" { st["ops", default: 0] += 8; st["fin", default: 0] += 6 }
        n.set("stats", .object(st.mapValues { .number(jsRound(clamp($0, 5, 98))) }))
        n.set("claimed", n.value("stats"))
        n.set("mtype", "gen"); n.set("exp", max(n.num("exp"), 1))
    }
}

extension ManagerModel {
    public static func managerWarning(_ s: GameState, companyID: Int, data: GameData) -> String? {
        guard let co = s.company(companyID), co.managerID == nil, co.staff.count <= 1 else { return nil }
        let h = co.monthlyHistory.suffix(3)
        guard !h.isEmpty else { return nil }
        let profit = h.reduce(0) { $0 + $1.profit } / Double(h.count)
        let wage = managerGoingRate(company: co, state: s, data: data)
        guard profit < wage * warningCover else { return nil }
        let cur = World(state: s, data: data).currency(co)
        return "A manager costs about \(cur.display(wage)) a month; this company earns about \(cur.display(max(0, profit))): you would likely lose money."
    }
    static let warningCover = 1.5
}
