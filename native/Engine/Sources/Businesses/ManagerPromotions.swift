import Foundation
import GameCore
import Countries
import Employees
import Finance

/// Promotions: a worker or a manager moves up. The talk covers pay, a bonus, shares in the company, the duties they take, how much they decide
/// themselves and how they report. Posts: a better role, manager of a company without one, chain manager or regional manager of a chain, and a
/// job at your main office. A promoted person who leaves a company has their successor appointed. Executives then do their duties each week.
/// Originals: features/people/worker_roles_and_promotions.js (`postsFor`, `p11offer`, `applyPost`, `execWeek`, `V.anrep11`),
/// features/company/shareholders_and_board.js (`R15give`), features/company/shelf_stock_chains_boards.js (`R12chiefPosts`, `R12hireChief`).
extension ManagerModel {
    // MARK: Types

    public struct PromotionPost: Identifiable, Equatable {
        public var id: String           // "role:<role>", "mgr@<companyID>", "chain:<chainID>[:<city>]", "hq:<role>"
        public var title: String
        public var place: String
        public var kind: String         // "role", "mgr", "exec"
        public var companyID: Int
        public var base: Double
        public var ask: Double
        /// Why the post cannot be taken now ("" when it can).
        public var blocked: String = ""
    }

    public enum PromotionOutcome: Equatable {
        case accepted(String)
        case counter(Double, String)     // "Make it ..." (they ask for more, never less)
        case unavailable(String)
    }

    /// What is on the table besides pay. Original: `ui.p11`.
    public struct PromotionTerms: Equatable, Sendable {
        public var duties: [String] = []
        /// 0 ask me first, 1 within limits, 2 full control
        public var authority: Int = 1
        /// week, month, need
        public var report: String = "month"
        /// Share of the yearly pay as a yearly bonus (0, 0.05, 0.1, 0.2)
        public var bonus: Double = 0
        /// Percent of the company's shares (limited companies only)
        public var sharesPercent: Double = 0
        public init(duties: [String] = [], authority: Int = 1, report: String = "month", bonus: Double = 0, sharesPercent: Double = 0) {
            self.duties = duties; self.authority = authority; self.report = report; self.bonus = bonus; self.sharesPercent = sharesPercent
        }
    }

    public static let managerDuties: [(key: String, label: String)] = [("hire", "Hiring staff"), ("buy", "Buying equipment and space")]
    public static let executiveDuties: [(key: String, label: String)] = [("quality", "Quality checks"), ("coach", "Coaching managers"), ("hire", "Finding managers")]
    public static let reportChoices: [(key: String, label: String)] = [("week", "Weekly update"), ("month", "Monthly report"), ("need", "Only when needed")]
    static let hqForRole: [String: String] = ["hr": "hr", "acct": "acc", "lawyer": "law", "analyst2": "ana", "analyst": "ana", "marketer": "mkt", "buyer": "proc", "consult": "strat", "designer": "mkt"]
    static let hqForManager = ["perf", "strat", "proc", "hr"]

    // MARK: Who is being promoted

    struct Candidate { var co: Company; var n: Person; var isManager: Bool; var pay: Double; var role: String; var skill: Double }

    static func skillOf(_ s: GameState, _ m: StaffMember, _ n: Person, data: GameData) -> Double { StaffTalks.skill(m, n, salesRoles: data.catalog.tables.salesRoles) }

    static func candidate(_ s: GameState, companyID: Int, personID: Int, data: GameData) -> Candidate? {
        guard let co = s.company(companyID), let n = s.people[personID] else { return nil }
        if co.managerID == personID, let bd = data.catalog[co.type] { return Candidate(co: co, n: n, isManager: true, pay: co.managerMonthlyWage, role: "mgr", skill: jsRound(quality(co, bd, people: s.people) * 100)) }
        guard let m = co.staff.first(where: { $0.id == personID }) else { return nil }
        return Candidate(co: co, n: n, isManager: false, pay: m.monthlyWage, role: m.role, skill: skillOf(s, m, n, data: data))
    }

    static func managerBase(_ s: GameState, _ c: Company, data: GameData) -> Double {
        marketWage(s, c, role: data.catalog[c.type]?.standardStaff.first?.role ?? "helper", data: data) * 1.55
    }

    /// Posts above the person's present one. Original: `postsFor`.
    public static func promotionPosts(_ s: GameState, companyID: Int, personID: Int, data: GameData) -> [PromotionPost] {
        guard let c = candidate(s, companyID: companyID, personID: personID, data: data), let bd = data.catalog[c.co.type] else { return [] }
        let tables = data.catalog.tables, co = c.co
        var out: [PromotionPost] = []
        func ask(_ base: Double) -> Double { World(state: s, data: data).currency(co).roundedStep(max(c.pay * 1.12, base * (0.85 + c.skill / 300)), about: 500) }
        if !c.isManager {
            let curBase = tables.roles[c.role]?.baseMonthlyWage ?? 0
            var seen = Set<String>()
            for r in (bd.standardStaff.map { $0.role } + ["lead"]) where seen.insert(r).inserted {
                guard r != c.role, let role = tables.roles[r], role.baseMonthlyWage > curBase * 1.04 else { continue }
                let base = marketWage(s, co, role: r, data: data) * (0.8 + c.skill / 200)
                out.append(PromotionPost(id: "role:\(r)", title: role.name, place: co.name, kind: "role", companyID: co.id, base: base, ask: ask(base)))
            }
        }
        let candidates = s.companies.filter { ($0.status == .open || $0.status == .setup) && $0.managerID == nil && $0.type != "hold" && data.catalog[$0.type]?.family != "club" }
        for x in ([co] + candidates.filter { $0.id != co.id }.prefix(4)) where x.managerID == nil && !(x.id == co.id && c.isManager) {
            guard let t = data.catalog[x.type], x.type != "hold" else { continue }
            let base = managerBase(s, x, data: data)
            out.append(PromotionPost(id: "mgr@\(x.id)", title: title(t), place: x.name, kind: "mgr", companyID: x.id, base: base, ask: ask(base)))
        }
        // chain chiefs
        if let ch = Chains.chain(s, of: co) {
            let L = Chains.stores(s, ch), id = ch["id"].int, regs = regionals(s)
            if !regs.contains(where: { $0["scope"].string == "chain:\(id)" }) && L.count >= 2 {
                let base = managerBase(s, co, data: data) * 1.5
                out.append(PromotionPost(id: "chain:\(id)", title: "Chain manager", place: "\(ch["name"].string) · \(L.count) stores", kind: "exec", companyID: co.id, base: base, ask: ask(base)))
            }
            if L.count >= 8 { for city in Set(L.map { $0.cityID }).sorted() where !regs.contains(where: { $0["scope"].string == "chain:\(id):\(city)" }) {
                let base = managerBase(s, co, data: data) * 1.5
                out.append(PromotionPost(id: "chain:\(id):\(city)", title: "Regional manager", place: "\(ch["name"].string) · \(cityName(s, city, data))", kind: "exec", companyID: co.id, base: base, ask: ask(base)))
            } }
        }
        // main office
        let hk = c.isManager ? hqForManager : (hqForRole[c.role].map { [$0] } ?? [])
        for k in hk {
            guard let r = Headquarters.role(k, data) else { continue }
            let room = Headquarters.room(s, role: k, data: data)
            let off = room == .ok ? "" : room == .have ? "Already filled" : room == .office ? "Needs an office" : room == .homeoffice ? "Needs a bigger main office" : room == .desks ? "No free desk" : room == .locked ? "Opens when you run \(Headquarters.unlockText(k))" : "Not possible"
            let base = playerBase(s, data, r.monthlyPay)
            var p = PromotionPost(id: "hq:\(k)", title: r.title, place: "Your main office", kind: "exec", companyID: co.id, base: base, ask: ask(base))
            p.blocked = off
            out.append(p)
        }
        return out
    }
    static func playerBase(_ s: GameState, _ data: GameData, _ v: Double) -> Double { playerCurrency(s, data).scaledPrice(v) }

    // MARK: The talk

    /// What this person asks for the post as offered: pay, with the extra duties, the authority and the reporting counted. The price the shared
    /// `Negotiation` works from.
    static func promotionNeed(_ post: PromotionPost, terms: PromotionTerms) -> Double {
        var need = post.ask * (1 + Double(max(0, terms.duties.count - 1)) * 0.03)
        if post.kind != "role" { need *= 1 + (terms.authority == 2 ? -0.03 : terms.authority == 0 && post.kind == "exec" ? 0.03 : 0) }
        if post.kind == "exec" && terms.report == "week" { need *= 1.02 }
        return need
    }

    /// What the extras in the package are worth a month to the person: the yearly bonus at 60% and the shares spread over three years.
    static func promotionExtras(_ s: GameState, _ c: Candidate, wage w: Double, terms: PromotionTerms, data: GameData) -> Double {
        let eq: Double = terms.sharesPercent > 0 && c.co.form == .limited ? max(0, Valuation.companyValue(c.co, state: s, trades: data.catalog)) * terms.sharesPercent / 100 / 36 : 0
        return w * terms.bonus * 0.6 + eq
    }

    /// Offer the post. At or above what the person asks they accept. Below it they ask for more through the shared `Negotiation` (patience by the level of
    /// the post and the person's temperament, now and then an unrealistic figure); they never turn down more pay: when their patience is gone they take the
    /// post at what is on the table, and are not happy about it. Original: `ACT.p11offer` (the answer is now `Negotiation`). The talk is kept by the caller.
    public static func offerPromotion(_ s: inout GameState, companyID: Int, personID: Int, post key: String, monthlyWage w: Double, terms: PromotionTerms = PromotionTerms(),
                                      negotiation talk: inout Negotiation.State, data: GameData) -> PromotionOutcome {
        guard let c = candidate(s, companyID: companyID, personID: personID, data: data), let post = promotionPosts(s, companyID: companyID, personID: personID, data: data).first(where: { $0.id == key }) else { return .unavailable("This post is not open.") }
        if !post.blocked.isEmpty { return .unavailable(post.blocked) }
        let first = firstName(c.n.name)
        let need = promotionNeed(post, terms: terms)
        let extras = promotionExtras(s, c, wage: w, terms: terms, data: data)
        let cur = World(state: s, data: data).currency(c.co)
        func accept(grudging: Bool) -> PromotionOutcome {
            talk = Negotiation.State()
            var msg = applyPromotion(&s, c, post: post, wage: w, terms: terms, data: data)
            if grudging, let ci = s.companyIndex(companyID) {
                msg += " \(first) takes it, but feels underpaid for the job."
                if c.isManager { s.companies[ci].set("mood", max(0, mood(s.companies[ci]) - 5)) }
                else if let k = s.companies[ci].staff.firstIndex(where: { $0.id == personID }) { var st = s.companies[ci].staff; st[k].happyUntilWeek = 0; s.companies[ci].staff = st }
            }
            return .accepted(msg)
        }
        if w + extras >= need { return accept(grudging: false) }
        let t = Hiring.temperament(of: c.n)
        let position = Negotiation.position(reservation: need, direction: .higher, temperament: t, key: "promo:\(personID):\(key)")
        let reply = Negotiation.respond(offer: w + extras, position: position, temperament: t, rank: post.kind == "role" && !c.isManager ? "worker" : "manager",
                                        state: &talk, week: s.week, step: cur.stepSize(about: 500), random: &s.random)
        func wage(for figure: Double) -> Double { max(w, cur.roundedStep(figure - extras, about: 500)) }
        switch reply.answer {
        case .accept: return accept(grudging: false)
        case .counter(let k):
            let ask = wage(for: k.amount)
            return .counter(ask, k.isFinal ? "That is my last word on this: \(cur.display(ask)) a month." : "I was hoping for more for this job. Make it \(cur.display(ask)) and we have a deal.")
        case .refuse:
            let ask = wage(for: position.opening)
            return .counter(ask, "That is not much for this much responsibility. I would want \(cur.display(ask)) a month.")
        case .walkAway: return accept(grudging: true)
        }
    }

    /// Give a person shares as part of the contract. Original: `R15give`.
    @discardableResult
    static func giveShares(_ s: inout GameState, companyID: Int, personID: Int, percent: Double) -> String {
        guard let i = s.companyIndex(companyID), let n = s.people[personID] else { return "" }
        let pct = min(percent, s.companies[i].ownership - 1)
        if pct <= 0 { return "" }
        s.companies[i].ownership -= pct
        var H = s.companies[i].value("holders").array
        if let k = H.firstIndex(where: { $0["npc"].int == personID && !$0["npc"].isNull }) { H[k]["pct"] = .number(H[k]["pct"].double + pct) }
        else { H.append(.object(["name": .string(n.name), "pct": .number(pct), "in": 0, "npc": .number(Double(personID)), "mood": 70])) }
        s.companies[i].set("holders", .array(H))
        return " \(firstName(n.name)) now owns \(Int(pct))% of \(s.companies[i].name)."
    }

    /// Give the person a new job. Original: `applyPost`, `promoteStaff`.
    static func applyPromotion(_ s: inout GameState, _ c: Candidate, post: PromotionPost, wage w: Double, terms u: PromotionTerms, data: GameData) -> String {
        guard var n = s.people[c.n.id], let ci = s.companyIndex(c.co.id) else { return "Something went wrong." }
        let co = s.companies[ci]
        let first = firstName(n.name)
        let cur = World(state: s, data: data).currency(co)
        n.set("promoPost", post.id)
        let k11: JSONValue = .object(["post": .string(post.id), "t": .string(post.title), "wage": .number(w), "bonus": .number(u.bonus), "duties": .array(u.duties.map { .string($0) }), "auth": .number(Double(u.authority)),
                                      "rep": .string(u.report), "w0": .number(Double(s.week)), "from": .object(["co": .number(Double(co.id)), "role": .string(c.role)])])
        let shares = u.sharesPercent > 0 && co.form == .limited && co.ownership > u.sharesPercent
        if post.kind == "role" {
            let role = String(post.id.dropFirst(5))
            guard let k = co.staff.firstIndex(where: { $0.id == n.id }) else { return "Something went wrong." }
            var staff = co.staff
            staff[k].set("role", role); staff[k].monthlyWage = w; staff[k].set("nr", 8); staff[k].set("promo", staff[k].num("promo") + 1); staff[k].lastRaiseWeek = s.week
            s.companies[ci].staff = staff
            n.role = role; n.set("k11", k11); n.set("p11", .null)
            s.people[n.id] = n
            return "\(first) is now \(post.title.lowercased()) at \(co.name)." + (shares ? giveShares(&s, companyID: co.id, personID: n.id, percent: u.sharesPercent) : "")
        }
        if post.id.hasPrefix("mgr@") {
            guard let ti = s.companyIndex(post.companyID), s.companies[ti].managerID == nil else { return "That company already has a manager." }
            if n.value("stats").isNull { ensureStats(&n, role: c.role) }
            n.role = "manager"; n.set("k11", k11); n.set("p11", .null)
            leaveJob(&s, c)
            appoint(&s, companyIndex: ti, person: n, wage: w, data: data)
            s.companies[ti].managerProfitBonus = u.bonus > 0 ? min(0.3, u.bonus * 0.5) : 0
            var a = s.companies[ti].value("auth"); a["lvl"] = .number(Double(u.authority)); a["set22"] = true; s.companies[ti].set("auth", a)
            s.companies[ti].set("mood", max(mood(s.companies[ti]), 62))
            s.note("\(first) now manages \(s.companies[ti].name) on \(cur.display(w)) a month.", tone: "good", companyID: post.companyID)
            return "\(first) now manages \(s.companies[ti].name)." + (shares ? giveShares(&s, companyID: post.companyID, personID: n.id, percent: u.sharesPercent) : "")
        }
        // a chief post or a job at the main office
        if n.value("stats").isNull { ensureStats(&n, role: c.role) }
        n.set("k11", k11); n.set("p11", .null)
        s.people[n.id] = n
        let had = c.isManager ? co.name : nil
        leaveJob(&s, c)
        var ok = false
        if post.id.hasPrefix("chain:") {
            let parts = post.id.dropFirst(6).split(separator: ":").map(String.init)
            if let chainID = Int(parts[0]) {
                let level: ExecLevel = parts.count > 1 ? .region : .chainmgr
                let cur0 = playerCurrency(s, data)
                let rec: JSONValue = .object(["id": .number(Double(s.makeID())), "npc": .number(Double(n.id)), "scope": .string("chain:\(post.id.dropFirst(6))"), "wage": .number(w), "lvl": .number(Double(u.authority)),
                                              "buy": .number([0, cur0.scaledPrice(level.buy), 1e9][min(2, max(0, u.authority))]), "payCo": "chain", "w0": .number(Double(s.week))])
                updateGroup(&s) { g in var l = g["regional"].array; l.append(rec); g["regional"] = .array(l) }
                var nn = s.people[n.id]!; nn.employerID = -1; s.people[n.id] = nn
                assignRegions(&s, chainID: chainID)
                addSeat(&s, boardKey: "ch:\(chainID)", seat: ["id": .number(Double(n.id)), "kind": "exec", "t": .string(post.title)])
                ok = true
            }
        } else if post.id.hasPrefix("hq:") {
            let role = String(post.id.dropFirst(3))
            if Headquarters.room(s, role: role, data: data) == .ok {
                var nn = s.people[n.id]!; nn.employerID = -3; s.people[n.id] = nn
                var o = s.rest["office"] ?? .null
                var l = o["staff"].array
                l.append(.object(["id": .number(Double(n.id)), "role": .string(role), "name": .string(n.name), "wage": .number(w), "w0": .number(Double(s.week)), "onb": .object([:])]))
                o["staff"] = .array(l); s.rest["office"] = o
                ok = true
            }
        }
        if !ok {
            var nn = s.people[n.id]!; nn.employerID = 0; s.people[n.id] = nn
            return "Something blocked the move. Check that your office has a free desk."
        }
        var tail = ""
        // someone who moves up appoints their own successor
        if let had = had {
            if fillManager(&s, companyID: co.id, by: n.name, why: "\(first) moved up to \(post.title.lowercased())", boss: n, data: data) == nil { s.note("\(had) has no manager now. Find one, or run it yourself.", tone: "bad", companyID: co.id) }
        }
        if shares { tail = giveShares(&s, companyID: co.id, personID: n.id, percent: u.sharesPercent) }
        return "\(first) is now \(post.title)." + tail
    }

    /// The person leaves the job they had. Original: `leaveJob`.
    static func leaveJob(_ s: inout GameState, _ c: Candidate) {
        guard let ci = s.companyIndex(c.co.id) else { return }
        if c.isManager {
            s.companies[ci].managerID = nil; s.companies[ci].managerMonthlyWage = 0; s.companies[ci].managerProfitBonus = 0
            var a = s.companies[ci].value("auth"); a["lvl"] = 0; s.companies[ci].set("auth", a)
            s.companies[ci].ownerHours = 40
        } else { s.companies[ci].staff = s.companies[ci].staff.filter { $0.id != c.n.id } }
        if var n = s.people[c.n.id] { n.employerID = 0; s.people[n.id] = n }
    }

    // MARK: A report on a person

    public struct PersonReport: Equatable, Sendable {
        public var preparedByAnalyst: Bool
        public var sections: [(title: String, lines: [(label: String, value: String)])]
        public var verdict: String
        public static func == (a: PersonReport, b: PersonReport) -> Bool { a.preparedByAnalyst == b.preparedByAnalyst && a.verdict == b.verdict && a.sections.count == b.sections.count }
    }

    /// Your own notes, or with a data analyst a full report with a verdict. Original: `V.anrep11`.
    public static func personReport(_ s: GameState, companyID: Int, personID: Int, data: GameData) -> PersonReport? {
        guard let c = candidate(s, companyID: companyID, personID: personID, data: data) else { return nil }
        let ana = Headquarters.has(s, "ana")
        let co = c.co, cur = World(state: s, data: data).currency(co)
        var sections: [(String, [(String, String)])] = []
        var score = 0.0
        if c.isManager {
            let h = co.monthlyHistory, mi = GameCalendar.monthIndex(week: co.int("mgrW0"))
            let bef = Array(h.filter { $0.monthIndex < mi }.suffix(3)), aft = Array(h.filter { $0.monthIndex >= mi }.suffix(3))
            func av(_ L: [MonthRecord], _ f: (MonthRecord) -> Double) -> Double? { L.isEmpty ? nil : L.reduce(0) { $0 + f($1) } / Double(L.count) }
            let rb = av(bef) { $0.revenue }, ra = av(aft) { $0.revenue }, pb = av(bef) { $0.profit }, pa = av(aft) { $0.profit }
            sections.append(("Results", [("Revenue before", rb.map { cur.short($0) } ?? "-"), ("Revenue now", ra.map { cur.short($0) } ?? "-"), ("Profit before", pb.map { cur.short($0) } ?? "-"), ("Profit now", pa.map { cur.short($0) } ?? "-"),
                                          ("Customer rating", String(format: "%.1f", Pricing.rating(co))), ("Staff mood", "\(Int(jsRound(mood(co)))) / 100"), ("Staff", "\(co.staff.count) people")]))
            score = c.skill + (h.suffix(3).allSatisfy { $0.profit > 0 } && !h.isEmpty ? 8 : -8)
        } else if let m = co.staff.first(where: { $0.id == personID }) {
            sections.append(("Work", [("Costs you", cur.short(m.monthlyWage) + "/mo"), ("Performance now", "\(Int(jsRound(c.skill)))"), ("Better since they started", String(format: "%+.0f points", m.skillGain)),
                                      ("Warnings", "\(m.int("warn"))"), ("Late this quarter", "\(m.int("late"))")]))
            score = c.skill * 0.6 + leadership(c.n) * 40
        }
        var verdict = ""
        if ana {
            var n = c.n
            if n.value("stats").isNull { ensureStats(&n, role: c.role) }
            let st = n.value("stats")
            func range(_ v: Double, _ i: Int) -> String {
                let e = 10.0, r = HashedRandom.first("ar11:\(n.id):\(i):\(s.week / 13)")
                let c0 = v + (r - 0.5) * e
                return "\(Int(clamp(c0 - e / 2, 0, 100)))-\(Int(clamp(c0 + e / 2, 0, 100)))"
            }
            sections.append(("Leadership estimate", ["ops", "people", "sales", "fin", "risk"].enumerated().map { (teamStatNames[$0.element] ?? $0.element, range(st[$0.element].double, $0.offset)) }))
            if let pot = c.n.potential { sections[sections.count - 1].1.append(("Could reach", range(pot, 9))) }
            verdict = score >= 72 ? "Ready for a bigger job. Strong across the board." : score >= 58 ? "Could grow into a bigger job with support." : score >= 45 ? "Better kept where they are for now." : "Not ready. Results and skills point the other way."
        }
        return PersonReport(preparedByAnalyst: ana, sections: sections.map { ($0.0, $0.1.map { (label: $0.0, value: $0.1) }) }, verdict: verdict)
    }

    // MARK: Executives at work

    static func scopeCompanies(_ s: GameState, person n: Person, data: GameData) -> [Company] {
        if let rg = regionals(s).first(where: { $0["npc"].int == n.id }) {
            return s.companies.filter { $0.status.isLive && ((!$0.value("region").isNull && $0.value("region").int == rg["id"].int) || rg["scope"].string == "all" || data.catalog[$0.type]?.category == rg["scope"].string) }
        }
        if s.rest["group"]?["ceo"]["npc"].int == n.id { return s.companies.filter { $0.status.isLive } }
        return []
    }

    /// What a chief does each week, and the reports and bonus they were promised. Original: `execWeek`.
    static func executivesWeekly(_ s: inout GameState, data: GameData) {
        var ex: [Int] = []
        if let g = s.rest["group"]?["ceo"], !g.isNull { ex.append(g["npc"].int) }
        for r in regionals(s) { ex.append(r["npc"].int) }
        for id in ex {
            guard let n = s.people[id], !n.value("k11").isNull else { continue }
            let q = leadership(n), L = scopeCompanies(s, person: n, data: data).filter { $0.status == .open }
            let d = n.value("k11")["duties"].array.map { $0.string }
            for c in L {
                guard let i = s.companyIndex(c.id) else { continue }
                if d.contains("quality") { s.companies[i].quality = clamp(c.quality + 0.4 * q, 0, 100) }
                if d.contains("coach") && c.managerID != nil { s.companies[i].set("mood", min(85, max(mood(c), mood(c) + 0.5 * q))) }
            }
            if d.contains("hire"), let need = L.first(where: { $0.managerID == nil && $0.staff.count >= 2 && !(Double(s.week) - $0.value("flags")["f11"].double < 8 && !$0.value("flags")["f11"].isNull) }), let bd = data.catalog[need.type] {
                var f = need.value("flags"); f["f11"] = .number(Double(s.week)); if let i = s.companyIndex(need.id) { s.companies[i].set("flags", f) }
                // the executive looks at a few people, bargains with each (AutoHire) and brings the owner the best deal, at the wage already agreed
                var found = (0..<3).map { _ in generateCandidate(company: need, type: bd.managerType, state: &s, data: data) }
                found.append(generateCandidate(company: need, type: "gen", state: &s, data: data))
                if let deal = AutoHire.bestManagerDeal(candidates: found, companyID: need.id, hirer: AutoHire.hirer(person: n), state: &s, data: data) {
                let m = deal.person
                let cur = World(state: s, data: data).currency(need)
                s.addMessage(kind: "ask", from: n.name, title: "I found a manager for \(need.name)", body: "\(m.name), \(m.age), \(String(format: "%g", m.num("exp"))) years of experience. I talked pay through and we agreed \(cur.display(deal.price)) a month. I checked the references.",
                             companyID: need.id, tone: "n", status: "open", options: [.option("Hire at \(cur.short(deal.price))"), .option("No thanks")], action: "mfind11", data: .object(["n": .number(Double(m.id)), "w": .number(deal.price)]), expiresWeek: s.week + 3)
                }
            }
            let rep = n.value("k11")["rep"].string, me = GameCalendar.isMonthEnd(week: s.week)
            let bad = L.filter { ($0.monthlyHistory.last?.profit ?? 0) < 0 }
            if rep == "week" || (rep == "month" && me) || (rep == "need" && me && !bad.isEmpty) {
                let lines = L.prefix(8).map { c -> String in let h = c.monthlyHistory.last; let cu = World(state: s, data: data).currency(c)
                    return "\(c.name): revenue \(cu.short(h?.revenue ?? 0)), profit \(cu.short(h?.profit ?? 0))" + (c.managerID == nil ? " (no manager)" : "") }
                s.addMessage(kind: "info", from: n.name, title: "\(rep == "week" ? "Weekly update" : "Monthly report") from your \(n.value("k11")["t"].string.isEmpty ? "manager" : n.value("k11")["t"].string.lowercased())", body: lines.isEmpty ? "Nothing to report." : lines.joined(separator: "\n"), tone: bad.isEmpty ? "n" : "bad", status: "done")
            }
            if GameCalendar.isYearEnd(week: s.week) && n.value("k11")["bonus"].double > 0 {
                let pr = L.reduce(0.0) { $0 + $1.monthlyHistory.suffix(12).reduce(0) { $0 + $1.profit } }
                if pr > 0 { Headquarters.payHeadOffice(&s, n.value("k11")["wage"].double * 12 * n.value("k11")["bonus"].double, label: "Bonus: \(n.name)") }
            }
        }
    }
}
