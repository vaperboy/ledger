import Foundation
import GameCore
import Countries
import Employees
import Finance

/// Managers as people: finding, hiring, authority, leaving; assistant managers; promotions. These extend `ManagerModel`.
/// Originals: `genManager`, `hireManager`, `mgrResign`, `fireManager` (engine/people/people.js), `ACT.mgr*` (ui/company/people.js),
/// the assistant manager (features/people/owner_hours_clients_assistants.js) and the promotion talk (worker_roles_and_promotions.js).
extension ManagerModel {
    // MARK: Who they are

    /// The six things a manager is judged on. Original: `MQ`.
    public static let skillKeys: [(key: String, label: String)] = [
        ("ops", "Day-to-day operations"), ("people", "Leading people"), ("sales", "Winning customers"),
        ("fin", "Numbers and cost control"), ("risk", "Compliance and risk"), ("ethic", "Integrity")]
    /// Job titles by manager type. Original: `MGR_TYPES`.
    public static let typeTitles: [String: String] = [
        "gen": "General manager", "ops": "Operations manager", "host": "Hospitality manager", "site": "Site / construction manager",
        "sales": "Sales-driven manager", "tech": "Technical manager", "fin": "Financial / compliance manager", "ind": "Industrial plant manager",
        "fleet": "Fleet and logistics manager", "prop": "Property manager", "fund": "Investment manager", "energy": "Energy / asset manager",
        "pro": "Professional-services partner", "retail": "Retail manager", "game": "Gaming and licence manager", "clin": "Clinical lead"]
    public static func title(_ bd: Trade) -> String { typeTitles[bd.managerType] ?? "General manager" }

    static let resumes = ["Previously ran a business unit.", "Former operations lead at a regional chain.", "Started as staff and rose to manager.",
                          "Consultant turned operator.", "Managed a competitor for years."]

    /// What a manager's job starts from at the reference economy: it grows with the people they run. Candidates ask a multiple of it by skill,
    /// age and experience (`generateCandidate`); the going rate is what the job pays before anything about the person.
    static func payBase(heads: Double) -> Double { 40000 + min(60000, heads * 2200) }

    /// What a manager of this skill, age group and experience asks: the base for the company's size by skill, age group and experience, in this
    /// city and economy. Candidates are made with it; whoever weighs them (`AutoHire`) uses it to judge what a given skill is worth.
    static func askingPay(heads: Double, skill: Double, tier: String, experience exp: Double, cityWage: Double, inflation: Double) -> Double {
        var pay = payBase(heads: heads) * (0.85 + skill / 400) * (tier == "senior" ? 1.1 : tier == "young" ? 0.86 : 1) * cityWage * inflation
        pay *= 0.82 + 0.18 * min(1, exp / 9)
        return pay
    }

    /// The going monthly rate for a store manager at this company: its size, its city and the economy, and nothing about the person.
    /// This is where a manager's pay discussion starts, from the employer's side.
    public static func managerGoingRate(company co: Company?, state s: GameState, data: GameData) -> Double {
        let w = World(state: s, data: data)
        let country = co.map { w.country($0) } ?? w.countries[s.homeCountryCode]!
        let cityWage = (co.flatMap { w.city($0) }?.wage) ?? 1
        let cur = Currency(country: country, rates: w.rates)
        return cur.roundedStep(payBase(heads: Double(co?.staff.count ?? 3)) * cityWage * w.inflationIndex, about: 500)
    }
    /// An assistant manager is paid this share of what a manager asks.
    static let assistantPayShare = 0.5
    public static func assistantGoingRate(company co: Company?, state s: GameState, data: GameData) -> Double {
        let w = World(state: s, data: data)
        let country = co.map { w.country($0) } ?? w.countries[s.homeCountryCode]!
        return Currency(country: country, rates: w.rates).roundedStep(managerGoingRate(company: co, state: s, data: data) * assistantPayShare, about: 500)
    }
    /// What a post on the management team pays relative to a manager: the managing director, a regional manager, or a department head.
    static func teamPayFactor(_ key: String) -> Double {
        key == "ceo" ? 2.4 : key == "reg" ? 1.6 : teamRoles.first { $0.key == key }?.payFactor ?? 1
    }

    /// A manager on the labour market. Original: `genManager` with the round 22 pay step.
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
        if faces { FaceBook.assign(personID: p.id, countryCode: country.code, sheet: .suits, state: &s) }
        return p
    }

    /// What every executive search costs (manager, team role, chain or group executive; the App's button labels read this too).
    /// 15,000 at the reference level, scaled by the country's price level.
    public static func searchFee(currency cur: Currency) -> Double { cur.scaledPrice(15000) }

    /// Executive search: a fee, and four candidates, three of the trade's own type. Original: `ACT.mgrsearch`.
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

    /// "Find a successor": pay for the executive search for the company's manager's replacement and keep the candidates (`succ`) for the
    /// hiring page. Asked after a resignation or three bad months; a search already running is not paid twice. Original: the choice opens
    /// the hiring page (`UI.go('mgrhire')`), where `ACT.mgrsearch` starts the search.
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
    /// The people a successor search found who are still free to hire.
    public static func successorCandidates(_ s: GameState, companyID: Int) -> [Person] {
        guard let co = s.company(companyID), s.week - co.int("succW") <= 26 else { return [] }
        return co.value("succ").array.compactMap { s.people[$0.int] }.filter { $0.employerID == 0 }
    }

    /// What a candidate says about one skill: their claim, unless the answer slips. Three questions each. Original: `interview`.
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

    /// Pay for a reference check; it shows what the person is really like. Original: `ACT.mgrref`.
    public static func referenceCheck(_ s: inout GameState, personID: Int, companyID: Int, data: GameData) -> Bool {
        guard let ci = s.companyIndex(companyID), var n = s.people[personID] else { return false }
        let fee = World(state: s, data: data).currency(s.companies[ci]).scaledPrice(2500)
        guard s.companies[ci].cash >= fee || Payments.liquid(s) >= fee else { return false }
        Payments.companyPays(&s, companyID: companyID, amount: fee, category: "oth", label: "Reference check")
        n.set("ref", true); s.people[personID] = n
        return true
    }

    /// A rough overall mark for a manager (0-100). Original: `qOf`.
    public static func overall(_ n: Person) -> Double {
        let st = n.value("stats")
        return (st["ops"].double + st["people"].double + st["sales"].double + st["fin"].double + st["risk"].double) / 5
    }

    // MARK: Hiring, leaving, authority

    /// As `Hiring.HireResult`: `refused` is an insult with no figure named, `countered` names their own figure, `walkedAway` means the person took another job.
    public enum HireResult: Equatable { case ok, taken, refused, needsPremises, countered(Negotiation.Counter), walkedAway }

    /// Make a person the company's manager: they run it, the owner steps back to no hours. Original: `hireManagerCore` plus the round 22
    /// steps (a baseline to be measured against, routine authority from the first day).
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
        var auth = co.value("auth")
        if !auth["set22"].bool, auth["lvl"].double < 1 { auth["lvl"] = 1 }
        let cur = World(state: s, data: data).currency(co)
        auth["buy"] = .number(max(auth["buy"].double, cur.roundedStep(max(cur.scaledPrice(10000), rev * 0.08), about: 1000)))
        co.set("auth", auth)
        if co.status == .closed, co.flag("idle") { co.status = .open; co.set("idle", 0); co.set("closeW", 0) }
        s.companies[ci] = co
        var p = n; p.employerID = co.id; s.people[n.id] = p
    }

    /// What a profit share is worth to a manager each month: the recent monthly profit times the share, less 30% for the risk. Original: `bonusWorth`.
    public static func bonusWorth(_ co: Company, _ share: Double) -> Double {
        guard share > 0 else { return 0 }
        let h = co.monthlyHistory.suffix(3)
        return max(0, h.reduce(0) { $0 + $1.profit } / Double(max(1, min(3, h.count)))) * share * 0.7
    }

    /// Offer the job. At or above what the person would settle for (hidden) they accept; below it they counter, refuse an insult or walk away
    /// (the shared `Negotiation`; managers have more patience than workers). Original: `hireManager`.
    public static func hire(_ s: inout GameState, personID: Int, companyID: Int, monthlyWage proposed: Double, profitBonus bonus: Double = 0, data: GameData) -> HireResult {
        guard let ci = s.companyIndex(companyID), let n0 = s.people[personID], let bd = data.catalog[s.companies[ci].type] else { return .refused }
        if n0.employerID != 0 { return .taken }
        let w = World(state: s, data: data)
        let wage = max(proposed, w.minimumWage(s.companies[ci]))   // never below the minimum wage
        // a share of the profit counts towards the package (a manager weighs it at 70% of what the last months' profit would pay)
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

    /// Dismiss the manager: notice and severance by the country's labour law, and the owner runs it again. Original: `fireManager`.
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

    /// Give the manager a raise (the contract talk's pay rise; the original's button gave 8 %, which still lifts the mood by the full 8 points).
    /// Original: `ACT.mgrraise` in ui/company/people.js.
    public static func raiseManager(_ s: inout GameState, companyID: Int, percent: Double = 0.08, data: GameData) {
        guard let ci = s.companyIndex(companyID), s.companies[ci].managerID != nil, percent > 0 else { return }
        let cur = World(state: s, data: data).currency(s.companies[ci])
        s.companies[ci].managerMonthlyWage = cur.roundedStep(s.companies[ci].managerMonthlyWage * (1 + percent), about: 100)
        s.companies[ci].set("mood", min(100, mood(s.companies[ci]) + 8 * min(1, percent / 0.08)))
    }

    static func mood(_ co: Company) -> Double { co.value("mood").isNull ? 60 : co.num("mood") }

    /// How much the manager may decide: 0 asks you, 1 within limits, 2 full control. Original: `setAuth` and the limit buttons.
    public static func setAuthority(_ s: inout GameState, companyID: Int, level: Int? = nil, buy: Double? = nil, pay: Double? = nil, ad: Double? = nil) {
        guard let ci = s.companyIndex(companyID) else { return }
        var a = s.companies[ci].value("auth")
        if let l = level { a["lvl"] = .number(Double(min(2, max(0, l)))) }
        if let b = buy { a["buy"] = .number(b) }
        if let p = pay { a["hire"] = .number(p) }
        if let d = ad { a["ad"] = .number(d) }
        a["set22"] = true
        s.companies[ci].set("auth", a)
    }

    /// Meet the manager: they report, and a manager nobody checks on stops slipping. Original: `callMeeting` (casual review).
    public static func meet(_ s: inout GameState, companyID: Int, data: GameData) -> Bool {
        guard let ci = s.companyIndex(companyID), let mid = s.companies[ci].managerID, let n = s.people[mid] else { return false }
        let co = s.companies[ci]
        let last: Double? = co.value("meetW").isNull ? nil : co.num("meetW")
        return CounterpartMeeting.meet(&s, lastWeek: last, cost: nil, label: "") { t in
            t.companies[ci].set("meetW", t.week)
            let cur = World(state: t, data: data).currency(co)
            let line = co.monthlyHistory.last.map { "Last month: revenue \(cur.short($0.revenue)), profit \(cur.short($0.profit))." } ?? "It is too early to say how it is going."
            t.addMessage(kind: "info", from: n.name, title: "Re: \(co.name)",
                         body: "Thanks for taking the time. \(line) We are using \(Int(jsRound(co.value("lastW")["util"].double * 100)))% of our capacity.", companyID: co.id, tone: "n", status: "done")
        } == .ok
    }

    /// How much experience a manager keeps when moved from one business to another. Original: `moveLoss`.
    public static func moveFactor(from a: Company, to b: Company, data: GameData) -> Double {
        if a.type == b.type { return 1 }
        return data.catalog[a.type]?.family == data.catalog[b.type]?.family ? 0.9 : 0.7
    }

    /// Move the manager to another company without one. Original: `ACT.mgrmovego`.
    public static func move(_ s: inout GameState, fromCompanyID a: Int, toCompanyID b: Int, data: GameData) -> Bool {
        guard let ai = s.companyIndex(a), let bi = s.companyIndex(b), let mid = s.companies[ai].managerID, s.companies[bi].managerID == nil,
              var n = s.people[mid], let tb = data.catalog[s.companies[bi].type], tb.family != "club" else { return false }
        let f = moveFactor(from: s.companies[ai], to: s.companies[bi], data: data)
        n.set("exp", jsRound(n.num("exp") * f * 2) / 2)
        s.people[mid] = n
        let wage = s.companies[ai].managerMonthlyWage, md = mood(s.companies[ai]), bonus = s.companies[ai].managerProfitBonus
        stepDown(&s, ai)
        appoint(&s, companyIndex: bi, person: n, wage: wage, data: data)
        s.companies[bi].managerProfitBonus = bonus   // the profit share goes with the manager
        s.companies[bi].set("mood", md)
        s.note("\(n.name) now manages \(s.companies[bi].name).", tone: "n", companyID: b)
        return true
    }

    /// The manager resigns; they work three to six months of notice. Original: `mgrResign`.
    public static func resign(_ s: inout GameState, companyIndex ci: Int, why: String, to rival: String = "") {
        let co = s.companies[ci]
        guard let mid = co.managerID, let n = s.people[mid], co.value("mgrNotice").isNull else { return }
        let wk = 13 + Int(HashedRandom.first("notice:\(n.id):\(s.week)") * 14)
        s.companies[ci].set("mgrNotice", .object(["w": .number(Double(s.week + wk)), "npc": .number(Double(mid)), "why": .string(why), "to": .string(rival)]))
        s.companies[ci].set("mood", max(0, mood(co) - 5))
        let reason = why.isEmpty ? "" : why.prefix(1).uppercased() + why.dropFirst() + ". "
        s.addMessage(kind: "info", from: n.name, title: "\(n.name) has resigned from \(co.name)",
                     body: "\(reason)I will work my notice and leave on \(GameCalendar.dateString(week: s.week + wk, dayOffset: 0))\(rival.isEmpty ? "" : ", when I start at \(rival)"). That gives you about \(Int(jsRound(Double(wk) / 4.33))) months to find someone. Hire my successor before then and I will hand over and go.",
                     companyID: co.id, tone: "bad", status: "open",
                     options: [.option("Find a successor", "Pays for an executive search now."), .option("I will handle it", "")],
                     action: ManagerTargets.successorAction, data: .object(["co": .number(Double(co.id))]), expiresWeek: s.week + wk)
    }

    /// The last day of the notice: they go, and you run the company until there is a new manager. Original: `mgrNoticeWeek`.
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

    /// A rival group makes the manager an offer. Rare, and likelier when the manager is unhappy. The answers: match it, or let them go.
    static func rivalOffer(_ s: inout GameState, companyIndex ci: Int, data: GameData) {
        let co = s.companies[ci]
        guard let mid = co.managerID, let n = s.people[mid], co.value("mgrNotice").isNull, s.week - co.int("mgrW0") > 26 else { return }
        let open = s.inbox.contains { $0.companyID == co.id && $0.status == "open" && $0.actionID == "mgrpoach" }
        guard !open, s.random.chance(0.0015 + (mood(co) < 45 ? 0.003 : 0) + (overall(n) > 70 ? 0.0015 : 0)) else { return }
        let cur = World(state: s, data: data).currency(co)
        let up = cur.roundedStep(co.managerMonthlyWage * 0.15, about: 100)
        s.addMessage(kind: "ask", from: n.name, title: "A rival wants to hire \(n.name) away from \(co.name)",
                     body: "\(n.name) has an offer from a rival group and has come to you first.", companyID: co.id, tone: "bad", status: "open",
                     options: [.option("Match it", "+\(cur.display(up))/month. Most stay."), .option("Let them go", "They work their notice.")],
                     action: "mgrpoach", data: .object(["up": .number(up)]), expiresWeek: s.week + 2)
    }

    // MARK: Assistant managers

    public static let assistantDuties: [(key: String, title: String, text: String)] = [
        ("comp", "Customer complaints", "Answers complaints before they become reviews"),
        ("paper", "Paperwork and insurance", "Staff papers and documents"),
        ("equip", "Equipment and stock", "Services worn equipment and keeps stock up")]

    /// Job ad for an assistant: a fee and three candidates, paid more than a worker and less than a manager. Original: `ACT.asstsearch`.
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

    /// The answer to an offer for a management post: `refused` is an insult with no figure named, `countered` names their own figure,
    /// `walkedAway` means the person took another job.
    public enum OfferResult: Equatable { case ok, refused, taken, countered(Negotiation.Counter), walkedAway }

    /// Maps the shared answer of a pay talk to the result of a management offer; `.accept` is not mapped (the caller carries on).
    static func offerResult(_ a: Negotiation.Answer) -> OfferResult? {
        switch a {
        case .accept: return nil
        case .refuse: return .refused
        case .walkAway: return .walkedAway
        case .counter(let c): return .countered(c)
        }
    }

    /// Original: `hireAsst`.
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

    /// Up to two jobs. Original: `ACT.asstduty`.
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

    /// One month of pay as notice. Original: `ACT.asstfire`.
    public static func fireAssistant(_ s: inout GameState, companyID: Int, data: GameData) {
        guard let ci = s.companyIndex(companyID) else { return }
        let a = s.companies[ci].value("asst")
        guard a["npc"].int != 0 else { return }
        let social = World(state: s, data: data).country(s.companies[ci]).employerOnCost(monthlyWage: a["wage"].double)
        Dismissal.book(&s, payer: .company(companyID), notice: Dismissal.monthOfPay(wage: a["wage"].double, employerSocial: social))
        if var n = s.people[a["npc"].int] { n.employerID = 0; s.people[n.id] = n }
        s.companies[ci].set("asst", .null)
    }

    /// Skill (0-1) of the assistant if they look after this duty, else nil. The complaints step uses it.
    public static func assistantSkill(_ co: Company, duty: String, people: [Int: Person]) -> Double? {
        let a = co.value("asst")
        guard a["npc"].int != 0, a["duties"].array.contains(where: { $0.string == duty }), let n = people[a["npc"].int] else { return nil }
        return (n.skill.isZero ? 55 : n.skill) / 100
    }

    /// Weekly: pay, and the jobs they were given. Original: `asstWeek`.
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
        if duties.contains("paper") {
            var staff = s.companies[ci].staff
            for k in staff.indices { for it in StaffExtras.missing(staff[k]) where s.random.chance(0.7 + sk * 0.3) { StaffExtras.tick(&staff[k], key: it.key) } }
            s.companies[ci].staff = staff
        }
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

    /// Leadership numbers for a worker who becomes a manager, from their skill. Original: `ensureStats`.
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
