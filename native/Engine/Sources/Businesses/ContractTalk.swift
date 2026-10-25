import Foundation
import GameCore
import Countries
import Employees
import Finance

/// ONE contract discussion per employee: the single door for everything that changes the terms of a person who already works for you.
/// Either side can open it (you from the profile, or the person with a request that reaches the Inbox). The topics are
///  - pay rise, promotion (title, duties, authority), hours, pay basis (fixed / mix / commission with a rate, a fixed salary for an hourly worker),
///  - bonus (a manager's profit share, a seller's commission rate), benefits (the company's perks, an own car with mileage),
///  - notice (extra contractual weeks, both ways), and moving to another store of the chain (a manager: to a company without one).
/// Nothing here is a second copy of a rule. The last step of every topic is the engine action that always existed (`StaffTalks.raise`,
/// `ManagerModel.offerPromotion`, `StaffProfile.setPayModel`, `StaffTalks.setStaffHours`, `StaffPerks.toggle`, `Chains.lendWorker` ...), and the answer to an
/// ask is the shared `Negotiation` (patience, temperament, now and then an unrealistic figure, from `negotiation.json`).
///
/// Two rules are binding:
///  - Nobody who works for you ever refuses MORE pay for the same job. A rise is always taken. A person's counter can only ask for more than what is
///    on the table; when their patience is gone they take what is offered (and are not happy about it), they do not walk away. Hours, a commission-only
///    pay basis and moving are not "more pay", so a person may be unwilling there, and the preview says so beforehand.
///  - You may decline, or delay, a fair request. That has real consequences, shown before you confirm: the chance that they hand in notice within a year
///    (`StaffWeek.quitOdds`, through the `denied` mark), the mood, and what it costs a month.
///
/// An open talk is kept on the person under the key `ctalk`, so a saved game keeps it; the key exists only while a talk is open.
public enum ContractTalk {
    public enum Topic: String, CaseIterable, Sendable {
        case payRise, promotion, hours, payBasis, bonus, benefits, notice, move
        public var title: String {
            switch self {
            case .payRise: return "Pay rise"
            case .promotion: return "Promotion"
            case .hours: return "Hours"
            case .payBasis: return "Pay basis"
            case .bonus: return "Bonus plan"
            case .benefits: return "Benefits"
            case .notice: return "Notice"
            case .move: return "Move"
            }
        }
    }

    public enum Opener: String, Sendable { case employer, employee }

    // MARK: Data

    struct Rules {
        var delayWeeks = 4
        var noticeExtra: [Int] = []
        var promotionTenure = 52, promotionSkill = 60.0, promotionEvery = 26
        var promotionPersonalities: Set<String> = []
        var tired = 60.0, hoursEvery = 26, keepShare = 0.75, minHours = 10.0
        var yearWeeks = 52
    }

    static let rules: Rules = {
        let j = Negotiation.data["contract"]
        var r = Rules()
        guard !j.isNull else { return r }
        r.delayWeeks = j["delayWeeks"].int
        r.noticeExtra = j["noticeExtraWeeks"].array.map { $0.int }
        r.promotionTenure = j["promotionAsk"]["tenureWeeks"].int; r.promotionSkill = j["promotionAsk"]["skill"].double; r.promotionEvery = j["promotionAsk"]["everyWeeks"].int
        r.promotionPersonalities = Set(j["promotionAsk"]["personalities"].array.map { $0.string })
        r.tired = j["hoursAsk"]["tired"].double; r.hoursEvery = j["hoursAsk"]["everyWeeks"].int; r.keepShare = j["hoursAsk"]["keepShare"].double; r.minHours = j["hoursAsk"]["minHours"].double
        r.yearWeeks = max(1, j["yearWeeks"].int)
        return r
    }()

    /// The extra notice weeks a contract can agree.
    public static var noticeExtraChoices: [Int] { rules.noticeExtra }
    public static var delayWeeks: Int { rules.delayWeeks }

    // MARK: What is on the table

    /// One thing proposed: a topic, a figure and a choice inside the topic.
    ///  - payRise: `amount` = the rise as a share (0.05 = +5 %).
    ///  - promotion: `choice` = the post (`PromotionPost.id`), `amount` = the monthly pay offered, `terms` = duties, authority, reporting, bonus, shares.
    ///  - hours: `choice` "hours" (`amount` = hours a week), "full", "part" (part time all year for a seasonal worker) or "season:<id>".
    ///  - payBasis: `choice` "fix", "mix", "com" (`amount` = the commission share, 0 = the usual one) or "salary" (an hourly worker's fixed salary).
    ///  - bonus: `amount` = a manager's profit share (0 to 0.3) or a seller's commission share.
    ///  - benefits: `choice` "perk:<id>" or "ownCar", `amount` 1 = on, 0 = off.
    ///  - notice: `amount` = extra weeks of notice, both ways.
    ///  - move: `choice` = the company id they move to.
    public struct Proposal: Equatable, Sendable {
        public var topic: Topic
        public var amount: Double
        public var choice: String
        public var terms: ManagerModel.PromotionTerms
        public init(_ topic: Topic, amount: Double = 0, choice: String = "", terms: ManagerModel.PromotionTerms = .init()) {
            self.topic = topic; self.amount = amount; self.choice = choice; self.terms = terms
        }

        var json: JSONValue {
            .object(["t": .string(topic.rawValue), "a": .number(amount), "c": .string(choice), "du": .array(terms.duties.map { .string($0) }), "au": .number(Double(terms.authority)),
                     "rp": .string(terms.report), "bo": .number(terms.bonus), "sh": .number(terms.sharesPercent)])
        }
        init?(json j: JSONValue) {
            guard let t = Topic(rawValue: j["t"].string) else { return nil }
            self.init(t, amount: j["a"].double, choice: j["c"].string,
                      terms: .init(duties: j["du"].array.map { $0.string }, authority: j["au"].int, report: j["rp"].string, bonus: j["bo"].double, sharesPercent: j["sh"].double))
        }
    }

    /// An open discussion with one person.
    public struct Talk: Equatable, Sendable {
        public var opener: Opener
        /// For a request of theirs: what they ask, then (after a counter of yours) what they ask now. For yours: their latest counter.
        public var proposal: Proposal
        /// Their first ask (a request), as a share for a rise and as pay for a promotion; 0 when you opened the talk.
        public var ask = 0.0
        /// Your last offer, 0 if none.
        public var offered = 0.0
        public var week = 0
        /// A delay you gave: the week by which an answer is due (0 = none).
        public var delayUntil = 0
        public var reason = ""
        public var neg = Negotiation.State()
        /// Their latest counter is the last word (the next offer that falls short ends the rounds: they settle).
        public var isFinal = false

        public var json: JSONValue {
            .object(["o": .string(opener.rawValue), "p": proposal.json, "k": .number(ask), "f": .number(offered), "w": .number(Double(week)), "d": .number(Double(delayUntil)),
                     "r": .string(reason), "n": neg.json, "l": .bool(isFinal)])
        }
        init?(json j: JSONValue) {
            guard !j.isNull, let p = Proposal(json: j["p"]) else { return nil }
            opener = Opener(rawValue: j["o"].string) ?? .employer; proposal = p; ask = j["k"].double; offered = j["f"].double; week = j["w"].int
            delayUntil = j["d"].int; reason = j["r"].string; neg = Negotiation.State(json: j["n"]); isFinal = j["l"].bool
        }
        init(opener: Opener, proposal: Proposal, week: Int) { self.opener = opener; self.proposal = proposal; self.week = week }

        public var isRequest: Bool { opener == .employee }
    }

    static let key = "ctalk"

    /// The talk kept on this person, if one is open.
    static func talk(of n: Person) -> Talk? { Talk(json: n.value(key)) }
    static func store(_ t: Talk, _ s: inout GameState, personID: Int) {
        guard var n = s.people[personID] else { return }
        n.set(key, t.json); s.people[personID] = n
    }
    public static func close(_ s: inout GameState, personID: Int) {
        guard var n = s.people[personID], !n.value(key).isNull else { return }
        n.raw.removeValue(forKey: key); s.people[personID] = n
    }

    public static func openTalk(_ s: GameState, personID: Int) -> Talk? { s.people[personID].flatMap { talk(of: $0) } }

    // MARK: Who the talk is with

    struct Subject {
        var ci: Int
        var person: Person
        var member: StaffMember?
        var isManager: Bool { member == nil }
        var rank: String { isManager ? "manager" : "worker" }
    }

    static func subject(_ s: GameState, companyID: Int, personID: Int) -> Subject? {
        guard let ci = s.companyIndex(companyID), let n = s.people[personID] else { return nil }
        if s.companies[ci].managerID == personID { return Subject(ci: ci, person: n, member: nil) }
        guard let m = s.companies[ci].staff.first(where: { $0.id == personID }) else { return nil }
        return Subject(ci: ci, person: n, member: m)
    }

    // MARK: What can be discussed

    public struct TopicInfo: Equatable, Sendable, Identifiable {
        public var topic: Topic
        public var available: Bool
        /// Why not (empty when available).
        public var why: String
        public var id: String { topic.rawValue }
    }

    public struct Choice: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var detail: String
        /// Benefits only: whether it is on now.
        public var on: Bool?
        /// A promotion post: the pay they will ask for.
        public var amount: Double?
    }

    public static func topics(_ s: GameState, companyID: Int, personID: Int, data: GameData) -> [TopicInfo] {
        guard let sub = subject(s, companyID: companyID, personID: personID) else { return [] }
        let co = s.companies[sub.ci]
        func info(_ t: Topic, _ ok: Bool, _ why: String) -> TopicInfo { TopicInfo(topic: t, available: ok, why: ok ? "" : why) }
        let posts = ManagerModel.promotionPosts(s, companyID: companyID, personID: personID, data: data).filter { $0.blocked.isEmpty }
        var out = [info(.payRise, true, ""), info(.promotion, !posts.isEmpty, "No higher post fits right now.")]
        if let m = sub.member {
            let sales = data.catalog.tables.salesRoles.contains(m.role)
            let hourlyFullTime = m.payBasis == "hour" && m.weeklyHours == nil && !m.flag("seas")
            let onPlan = m.commissionMode == "mix" || m.commissionMode == "com"
            out.append(info(.hours, true, ""))
            out.append(info(.payBasis, sales || hourlyFullTime, "Already on a fixed salary, and not a selling job."))
            out.append(info(.bonus, onPlan, sales ? "Put them on salary and commission, or commission only, first." : "This job has no bonus plan."))
            out.append(info(.benefits, true, ""))
            out.append(info(.notice, true, ""))
            let sisters = Chains.chain(s, of: co).map { Chains.stores(s, $0).filter { $0.id != co.id && $0.status.isLive }.count } ?? 0
            out.append(info(.move, sisters > 0, "There is no other store in this chain."))
        } else {
            out.append(info(.hours, false, "A manager's hours are not set in a contract talk."))
            out.append(info(.payBasis, false, "A manager is paid a salary and a profit share."))
            out.append(info(.bonus, true, ""))
            out.append(info(.benefits, true, ""))
            out.append(info(.notice, false, "A manager's notice is set by the labour rules."))
            out.append(info(.move, !freeCompanies(s, except: companyID, data: data).isEmpty, "Every other company already has a manager."))
        }
        return out
    }

    static func freeCompanies(_ s: GameState, except id: Int, data: GameData) -> [Company] {
        s.companies.filter { $0.id != id && $0.managerID == nil && $0.status.isLive && $0.type != "hold" && data.catalog[$0.type]?.family != "club" }
    }

    /// The options inside a topic (posts, ways of paying, perks, places).
    public static func choices(_ s: GameState, companyID: Int, personID: Int, topic: Topic, data: GameData) -> [Choice] {
        guard let sub = subject(s, companyID: companyID, personID: personID) else { return [] }
        let co = s.companies[sub.ci]
        let cur = World(state: s, data: data).currency(co)
        switch topic {
        case .payRise, .bonus, .notice: return []
        case .promotion:
            return ManagerModel.promotionPosts(s, companyID: companyID, personID: personID, data: data).filter { $0.blocked.isEmpty }
                .map { Choice(id: $0.id, title: $0.title, detail: "\($0.place) · they will ask about \(cur.display($0.ask)) a month", amount: $0.ask) }
        case .hours:
            guard let m = sub.member else { return [] }
            var out = [Choice(id: "hours", title: "Set the hours a week", detail: "Pay follows the hours for people paid by the hour.")]
            if m.weeklyHours != nil { out.append(Choice(id: "full", title: "Offer full time", detail: "Only if that is the work they want.")) }
            if !m.value("seas").isNull {
                out.append(Choice(id: "part", title: "Part time all year", detail: "Yes unless they only want the season."))
                for sea in StaffTalks.seasons {
                    let on = sea.months.allSatisfy { m.value("seas").array.map { $0.int }.contains($0) }
                    out.append(Choice(id: "season:\(sea.id)", title: (on ? "Drop " : "Add ") + sea.name, detail: on ? "Works this season now." : "Does not work this season now."))
                }
            }
            return out
        case .payBasis:
            guard let m = sub.member else { return [] }
            var out: [Choice] = []
            if data.catalog.tables.salesRoles.contains(m.role) {
                out = [Choice(id: "fix", title: "Fixed salary", detail: "No commission."),
                       Choice(id: "mix", title: "Salary and commission", detail: "A lower salary with a share of their sales."),
                       Choice(id: "com", title: "Commission only", detail: "No base pay at all: they earn only their commission. Someone who wants security may refuse and resign.")]
            } else { out = [Choice(id: "salary", title: "Fixed monthly salary", detail: "Instead of pay by the hour.")] }
            return out
        case .benefits:
            var out = StaffPerks.all.map { p in
                Choice(id: "perk:\(p.id)", title: p.name + (StaffPerks.isOn(co, p.id) ? " (on)" : ""), detail: "For the whole company. " + p.detail, on: StaffPerks.isOn(co, p.id))
            }
            if let m = sub.member, let bd = data.catalog[co.type], PersonalEquipment.canUseOwnCar(role: m.role, bd, tables: data.catalog.tables) {
                out.append(Choice(id: "ownCar", title: m.flag("ownCar") ? "Give a company car" : "Own car and mileage", detail: "Mileage is paid each month for an own car.", on: m.flag("ownCar")))
            }
            return out
        case .move:
            if sub.isManager { return freeCompanies(s, except: companyID, data: data).map { Choice(id: "\($0.id)", title: $0.name, detail: "Takes their pay and profit share with them.") } }
            guard let ch = Chains.chain(s, of: co) else { return [] }
            return Chains.stores(s, ch).filter { $0.id != co.id && $0.status.isLive }.map { Choice(id: "\($0.id)", title: $0.name, detail: "Same chain.") }
        }
    }

    // MARK: Who decides (delegation)

    /// May the manager decide this on your behalf? Level 2 decides anything, level 1 up to the pay-and-promotions limit set on the manager's card
    /// (the same rule the manager already follows in `ManagerModel`'s pay reviews).
    public static func managerMayDecide(_ co: Company, extraMonthly: Double) -> Bool {
        guard co.managerID != nil else { return false }
        let a = co.value("auth"), lvl = Int(a["lvl"].double)
        return lvl >= 2 || (lvl == 1 && extraMonthly <= a["hire"].double)
    }

    public struct Handler: Equatable, Sendable { public var name: String; public var level: Int; public var payLimit: Double }

    /// The manager who may handle a company's contract talks (level 1 or 2 on their card), with the limit; nil when they all come to you.
    public static func handler(_ s: GameState, companyID: Int, data: GameData) -> Handler? {
        guard let co = s.company(companyID), let boss = ManagerModel.decisionChain(s, co, data: data).first(where: { $0.kind == "mgr" }), boss.level >= 1 else { return nil }
        return Handler(name: boss.name, level: boss.level, payLimit: co.value("auth")["hire"].double)
    }

    // MARK: Consequences

    public struct Consequences: Equatable, Sendable {
        /// Not possible, with the reason; the rest is empty then.
        public var blocked = ""
        public var costBefore = 0.0
        public var costAfter = 0.0
        /// The chance that they hand in notice within a year, now and if this is agreed (nil for a manager, who has no such model).
        public var quitYearBefore: Double?
        public var quitYearAfter: Double?
        /// For a request of theirs: the same chance if you decline it, and the mood word.
        public var quitYearIfDeclined: Double?
        /// What changes, in words.
        public var lines: [String] = []
        /// What the country's labour data requires or sets.
        public var labour: [String] = []
        /// Others the change reaches.
        public var peers: [String] = []
        /// Risks and who may refuse.
        public var risks: [String] = []
        public var costPerMonth: Double { costAfter - costBefore }
    }

    /// What the company pays a month for its people and perks: wages with the employer's charges, the manager and his profit share, perks, own-car mileage.
    static func employerCost(_ s: GameState, companyID: Int, data: GameData) -> Double {
        guard let co = s.company(companyID) else { return 0 }
        let w = World(state: s, data: data), c = w.country(co), cur = w.currency(co)
        var sum = co.staff.reduce(0.0) { $0 + $1.monthlyWage * (1 + c.employerSocialRate(monthlyWage: $1.monthlyWage)) }
        if co.managerID != nil { sum += co.managerMonthlyWage * (1 + c.employerSocialRate(monthlyWage: co.managerMonthlyWage)) + ManagerModel.bonusWorth(co, co.managerProfitBonus) }
        sum += StaffPerks.totalMonthlyCost(co, currency: cur)
        if let bd = data.catalog[co.type] { sum += PersonalEquipment.mileagePerMonth(cur, country: c, bd, tables: data.catalog.tables) * Double(co.staff.filter { $0.flag("ownCar") }.count) }
        return sum
    }

    /// The chance that this worker hands in notice within a year, from the weekly odds of `StaffWeek` (and the pay gap of `StaffRoutine`).
    static func quitYear(_ s: GameState, companyID: Int, personID: Int, data: GameData, declined: Bool = false) -> Double? {
        guard let co = s.company(companyID), var m = co.staff.first(where: { $0.id == personID }), let n = s.people[personID], let bd = data.catalog[co.type] else { return nil }
        if declined { m.set("denied", s.week); m.happyUntilWeek = 0 }
        let market = StaffProfile.marketPay(s, co, m, data: data)
        guard market > 0 else { return nil }
        let gap = StaffRoutine.payGap(market: market, person: n, member: m)
        let tenure = Double(s.week - (m.raw["w0"].map { $0.isNull ? s.week : $0.int } ?? s.week))
        let odds = StaffWeek.quitOdds(family: bd.family, tradeID: co.type, staff: m, person: n, payGap: gap, tenure: tenure, week: s.week,
                                      hasHRManager: s.hasHeadOffice("hr"), hasTeamLead: co.staff.contains { $0.role == "lead" })
        let p = min(1, max(0, StaffRoutine.quitChance(odds: odds, company: co, member: m)))
        return 1 - pow(1 - p, Double(rules.yearWeeks))
    }

    /// What agreeing to this would do, worked out by doing it on a copy of the game: the very engine action that runs when you confirm, so the preview
    /// cannot drift from the real thing. Nothing in `s` changes.
    public static func preview(_ s: GameState, companyID: Int, personID: Int, proposal p: Proposal, asRequest: Bool = false, data: GameData) -> Consequences {
        var c = Consequences()
        guard let sub = subject(s, companyID: companyID, personID: personID) else { c.blocked = "This person no longer works here."; return c }
        let w = World(state: s, data: data), co = s.companies[sub.ci], cur = w.currency(co), lab = w.labour(co)
        let first = ManagerModel.firstName(sub.person.name)
        c.costBefore = employerCost(s, companyID: companyID, data: data)
        c.quitYearBefore = quitYear(s, companyID: companyID, personID: personID, data: data)
        var t = s
        let done = applyFinal(&t, sub, p, data: data)
        switch done {
        case .notPossible(let why): c.blocked = why; return c
        case .unwilling(let why): c.risks.append(why)
        case .resigned(let why): c.risks.append(why)
        case .ok: break
        }
        var otherCost = 0.0
        if p.topic == .move, let to = Int(p.choice) { otherCost = employerCost(s, companyID: to, data: data); c.costAfter = employerCost(t, companyID: to, data: data) - otherCost + employerCost(t, companyID: companyID, data: data) }
        else { c.costAfter = employerCost(t, companyID: companyID, data: data) }
        if p.topic == .move, let to = Int(p.choice) { c.costBefore += otherCost; c.costAfter += otherCost; _ = to }
        c.quitYearAfter = quitYear(t, companyID: p.topic == .move ? (Int(p.choice) ?? companyID) : companyID, personID: personID, data: data)
        if asRequest { c.quitYearIfDeclined = quitYear(s, companyID: companyID, personID: personID, data: data, declined: true) }

        let after = subject(t, companyID: sub.isManager && p.topic == .move ? (Int(p.choice) ?? companyID) : companyID, personID: personID)
        let wageBefore = sub.member?.monthlyWage ?? co.managerMonthlyWage
        let wageAfter = after?.member?.monthlyWage ?? (after.map { t.companies[$0.ci].managerMonthlyWage } ?? wageBefore)
        if abs(wageAfter - wageBefore) > 0.5 { c.lines.append("Pay: \(cur.display(wageBefore)) -> \(cur.display(wageAfter)) a month (\(wageAfter >= wageBefore ? "+" : "")\(cur.display(wageAfter - wageBefore)))") }
        let hoursBefore = sub.member?.weeklyHours ?? StaffModel.fullWeekHours
        let hoursAfter = after?.member?.weeklyHours ?? StaffModel.fullWeekHours
        if abs(hoursAfter - hoursBefore) > 0.01 { c.lines.append("Hours: \(Int(hoursBefore.rounded())) -> \(Int(hoursAfter.rounded())) a week") }

        switch p.topic {
        case .payRise:
            if let m = sub.member {
                let need = StaffTalks.raiseNeeded(role: m.role, age: sub.person.age, tables: data.catalog.tables)
                c.lines.append(p.amount >= need ? "A raise they will notice: it reaches the \(Int((need * 100).rounded()))% people feel." : "They take it, but under \(Int((need * 100).rounded()))% does not feel like a raise and they stay unhappy.")
            }
        case .promotion:
            if let post = ManagerModel.promotionPosts(s, companyID: companyID, personID: personID, data: data).first(where: { $0.id == p.choice }) {
                c.lines.append("New post: \(post.title) at \(post.place). They ask about \(cur.display(post.ask)) a month for it.")
                if !p.terms.duties.isEmpty { c.lines.append("Duties: \(p.terms.duties.joined(separator: ", ")). Authority \(["asks you first", "within limits", "full control"][min(2, max(0, p.terms.authority))]).") }
                if post.kind != "role", sub.member != nil || sub.isManager { c.peers.append("They leave their present job; it is empty until it is filled.") }
            }
        case .hours:
            if let m = sub.member, p.choice == "hours" || p.choice == "full" {
                let hrs = after?.member?.weeklyHours ?? StaffModel.fullWeekHours
                if hrs > lab.stdHours { c.labour.append("Hours over the standard \(Int(lab.stdHours.rounded())) a week are overtime" + (lab.overtimePremium > 0 ? ", paid with +\(Int((lab.overtimePremium * 100).rounded()))%." : ".")) }
                if m.payBasis == "fix" { c.lines.append("They are on a fixed salary: pay does not change with the hours.") }
            }
        case .payBasis:
            if p.choice == "com" {
                c.lines.append("Commission only: no base pay; they earn only what they sell. Commission is paid on top of nothing, and it is not counted in the cost above.")
                if sub.person.num("sec") > 0.65 { c.risks.append("\(first) wants security: likely to refuse and resign (about 6 in 10).") }
            } else if p.choice == "mix" || p.choice == "fix" { c.lines.append("Commission is paid on their sales on top of the salary" + (p.choice == "fix" ? " only if they stay on a plan." : ", and is not counted in the cost above.")) }
        case .bonus:
            if sub.isManager { c.lines.append("Profit share: \(Int((p.amount * 100).rounded()))% of each month's profit, worth about \(cur.display(ManagerModel.bonusWorth(co, p.amount))) a month at the last three months' profit.") }
            else { c.lines.append("Commission: \(Int((p.amount * 100).rounded()))% of their sales (variable, not in the cost above).") }
        case .benefits:
            if p.choice.hasPrefix("perk:"), let perk = StaffPerks.perk(String(p.choice.dropFirst(5))) {
                let people = perk.keysOnly ? StaffPerks.keyPeople(co) : StaffPerks.headcount(co)
                c.peers.append("It covers everyone it applies to: \(people) \(people == 1 ? "person" : "people"), not just \(first).")
                c.peers.append("People leave about \(Int(((1 - perk.quitFactor) * 100).rounded()))% less while it is on.")
            } else if p.choice == "ownCar", let bd = data.catalog[co.type] { c.lines.append("Mileage is paid each month: \(cur.display(PersonalEquipment.mileagePerMonth(cur, country: World(state: s, data: data).country(co), bd, tables: data.catalog.tables))).") }
        case .notice:
            if let m = sub.member {
                let years = Double(s.week - m.hiredWeek)
                let t0 = lab.termination(tenureWeeks: years, reason: .unjustified, age: Double(sub.person.age))
                c.labour.append("Notice by law at their service: \(Int(t0.noticeWeeks.rounded())) weeks" + (t0.severanceWeeks > 0 ? ", severance \(Int(t0.severanceWeeks.rounded())) weeks of pay" : "") + " (if you let them go without cause).")
                if p.amount > 0 { c.lines.append("\(Int(p.amount)) weeks more notice on top, owed by both sides: if they resign they work it, if you let them go without cause you pay it.") }
            }
        case .move:
            if let to = Int(p.choice), let dest = s.company(to) {
                c.lines.append("Moves to \(dest.name). Their pay is the same; it is paid there from now on.")
                if let m = sub.member { let left = co.staff.filter { $0.role == m.role && $0.id != m.id }.count; c.peers.append("\(co.name) is left with \(left) other \(left == 1 ? "person" : "people") in that job.") }
            }
        }
        if let m = sub.member, lab.hasMinimum {
            let floor = w.minimumWage(co, hours: after?.member?.weeklyHours ?? m.weeklyHours ?? StaffModel.fullWeekHours)
            c.labour.append("The \(lab.statutory ? "legal" : "agreed") minimum pay is \(cur.display(floor)) a month for their hours; base pay never goes under it" + (p.topic == .payBasis && p.choice == "com" ? ", except commission only, which has no base." : "."))
        }
        let tenure = Double(s.week - (sub.member?.hiredWeek ?? s.week))
        if sub.member != nil, lab.probationWeeks > tenure { c.labour.append("They are still in probation for \(Int((lab.probationWeeks - tenure).rounded())) more weeks.") }
        if asRequest, let before = c.quitYearBefore, let declined = c.quitYearIfDeclined, declined > before {
            c.risks.append("If you decline: the chance they hand in notice within a year goes from \(Int((before * 100).rounded()))% to \(Int((declined * 100).rounded()))%, and they feel turned down for \(rules.yearWeeks / 2) weeks.")
        }
        return c
    }

    // MARK: The last step of every topic

    enum Done { case ok(String), notPossible(String), unwilling(String), resigned(String) }

    /// Do it: the engine action behind each topic. Used for the real thing and, on a copy, for the preview.
    static func applyFinal(_ s: inout GameState, _ sub: Subject, _ p: Proposal, data: GameData) -> Done {
        let co = s.companies[sub.ci], id = sub.person.id, name = sub.person.name
        let cur = World(state: s, data: data).currency(co)
        func edit(_ f: (inout StaffMember) -> Void) {
            guard let k = s.companies[sub.ci].staff.firstIndex(where: { $0.id == id }) else { return }
            var st = s.companies[sub.ci].staff; f(&st[k]); s.companies[sub.ci].staff = st
        }
        switch p.topic {
        case .payRise:
            guard p.amount > 0 else { return .notPossible("A raise has to be more than nothing.") }
            if sub.isManager { ManagerModel.raiseManager(&s, companyID: co.id, percent: p.amount, data: data); return .ok("\(name) now earns \(cur.display(s.companies[sub.ci].managerMonthlyWage)) a month.") }
            StaffTalks.raise(&s, companyIndex: sub.ci, staffID: id, percent: p.amount, data: data)
            return .ok("\(name) now earns \(cur.display(s.companies[sub.ci].staff.first { $0.id == id }?.monthlyWage ?? 0)) a month.")
        case .promotion:
            guard let c = ManagerModel.candidate(s, companyID: co.id, personID: id, data: data),
                  let post = ManagerModel.promotionPosts(s, companyID: co.id, personID: id, data: data).first(where: { $0.id == p.choice }) else { return .notPossible("This post is not open.") }
            if !post.blocked.isEmpty { return .notPossible(post.blocked) }
            return .ok(ManagerModel.applyPromotion(&s, c, post: post, wage: p.amount, terms: p.terms, data: data))
        case .hours:
            guard let m = sub.member else { return .notPossible("Not for a manager.") }
            func why(_ want: String) -> String { StaffTalks.wishWhy(m, name: name, want: want) }
            switch p.choice {
            case "hours":
                switch StaffTalks.setStaffHours(&s, companyID: co.id, staffID: id, hours: p.amount) {
                case .ok: return .ok("\(name) now works \(Int(p.amount.rounded())) hours a week.")
                case .student: return .notPossible(why("part"))
                default: return .notPossible("They no longer work here.")
                }
            case "full":
                switch StaffTalks.offerFullTime(&s, companyID: co.id, staffID: id, data: data) {
                case .ok: return .ok("\(name) works full time now.")
                case .already: return .notPossible("They already work full time.")
                case .student: return .notPossible(why("full"))
                case .refused: return .unwilling(why("full"))
                case .unknown: return .notPossible("They no longer work here.")
                }
            case "part":
                switch StaffTalks.offerPartTime(&s, companyID: co.id, staffID: id) {
                case .ok: return .ok("\(name) stays on part time all year.")
                case .already: return .notPossible("They are not a seasonal worker.")
                case .refused: return .unwilling(why("season"))
                default: return .notPossible("They no longer work here.")
                }
            default:
                if p.choice.hasPrefix("season:"), StaffTalks.toggleSeason(&s, companyID: co.id, staffID: id, season: String(p.choice.dropFirst(7))) { return .ok("The seasons are changed.") }
                return .notPossible("That season cannot be changed now.")
            }
        case .payBasis:
            guard sub.member != nil else { return .notPossible("Not for a manager.") }
            if p.choice == "salary" {
                guard sub.member?.payBasis == "hour", sub.member?.weeklyHours == nil else { return .notPossible("They are not paid by the hour for a full week.") }
                _ = StaffTalks.offerFixedSalary(&s, companyID: co.id, staffID: id, data: data)
                return .ok("\(name) is on a fixed salary now.")
            }
            switch StaffProfile.setPayModel(&s, companyID: co.id, staffID: id, mode: p.choice, data: data) {
            case .changed:
                if p.amount > 0, p.choice != "fix" { _ = StaffProfile.setCommissionRate(&s, companyID: co.id, staffID: id, rate: p.amount) }
                return .ok(p.choice == "com" ? "\(name) is on commission only: no base pay." : p.choice == "mix" ? "\(name) is on salary and commission." : "\(name) is on a fixed salary.")
            case .resigned: return .resigned("\(name) will not work on commission only and resigns.")
            case .notSales: return .notPossible("Only selling jobs have a commission plan.")
            case .unknown: return .notPossible("They no longer work here.")
            }
        case .bonus:
            if sub.isManager {
                guard p.amount >= s.companies[sub.ci].managerProfitBonus else { return .notPossible("A profit share is not cut in a contract talk.") }
                ManagerModel.setManagerProfitBonus(&s, companyID: co.id, share: p.amount)
                return .ok("\(name) now gets \(Int((min(0.3, p.amount) * 100).rounded()))% of each month's profit.")
            }
            guard StaffProfile.setCommissionRate(&s, companyID: co.id, staffID: id, rate: p.amount) else { return .notPossible("Not possible on this pay basis.") }
            return .ok("Commission is \(Int((p.amount * 100).rounded()))% of their sales.")
        case .benefits:
            if p.choice == "ownCar" {
                guard let bd = data.catalog[co.type], let role = sub.member?.role, PersonalEquipment.canUseOwnCar(role: role, bd, tables: data.catalog.tables) else { return .notPossible("This job does not use a car for work.") }
                _ = PersonalEquipment.toggleOwnCar(&s, companyID: co.id, staffID: id, set: p.amount != 0)
                return .ok(p.amount != 0 ? "\(name) uses their own car; mileage is paid." : "\(name) drives a company car.")
            }
            guard p.choice.hasPrefix("perk:"), let perk = StaffPerks.perk(String(p.choice.dropFirst(5))) else { return .notPossible("That is not a benefit.") }
            if StaffPerks.isOn(s.companies[sub.ci], perk.id) != (p.amount != 0) { _ = StaffPerks.toggle(&s, companyID: co.id, perk: perk.id, data: data) }
            return .ok("\(perk.name) is now \(p.amount != 0 ? "on" : "off") for the company.")
        case .notice:
            guard sub.member != nil else { return .notPossible("Not for a manager.") }
            let weeks = Int(max(0, p.amount))
            guard weeks == 0 || rules.noticeExtra.contains(weeks) else { return .notPossible("That is not a notice period you can agree.") }
            edit { m in if weeks == 0 { m.raw.removeValue(forKey: "nx") } else { m.set("nx", weeks) } }
            return .ok(weeks == 0 ? "\(name) is on the notice the law sets." : "\(name) now has \(weeks) weeks more notice, both ways.")
        case .move:
            guard let to = Int(p.choice), to != co.id else { return .notPossible("Choose where they go.") }
            if sub.isManager {
                guard ManagerModel.move(&s, fromCompanyID: co.id, toCompanyID: to, data: data) else { return .notPossible("They cannot move there.") }
                return .ok("\(name) now manages \(s.company(to)?.name ?? "the other company").")
            }
            guard let m = sub.member, Chains.lendWorker(&s, from: co.id, to: to, role: m.role, staffID: id, data: data) else { return .notPossible("They cannot move there.") }
            return .ok("\(name) moves to \(s.company(to)?.name ?? "the other store").")
        }
    }

    // MARK: Replies

    public enum Reply: Equatable, Sendable {
        /// Done: the engine action ran.
        case agreed(String)
        /// They ask for more than you offered; the figure is in the unit of the proposal (a share for a rise, pay for a promotion).
        case counter(amount: Double, isFinal: Bool, String)
        /// Their patience is gone: they take what you offered and are not happy about it. Done.
        case settled(String)
        /// You delayed an answer to their request.
        case delayed(untilWeek: Int, String)
        /// You declined their request.
        case declined(String)
        /// Unwilling (hours, commission only): not more pay, so a person may be.
        case unwilling(String)
        case resigned(String)
        case notPossible(String)

        /// Did the terms change?
        public var changedTerms: Bool {
            switch self { case .agreed, .settled, .resigned: return true; default: return false }
        }
    }


    // MARK: You propose

    /// You put something to them. A rise is taken at once. A promotion goes through `Negotiation` (they ask for more, never less). The rest is the
    /// engine action: the person may be unwilling about hours and commission only, not about pay.
    public static func propose(_ s: inout GameState, companyID: Int, personID: Int, proposal p: Proposal, data: GameData) -> Reply {
        guard let sub = subject(s, companyID: companyID, personID: personID) else { return .notPossible("This person no longer works here.") }
        let existing = openTalk(s, personID: personID).flatMap { $0.proposal.topic == p.topic && ($0.proposal.choice == p.choice || p.topic != .promotion) ? $0 : nil }
        var talk = existing ?? Talk(opener: .employer, proposal: p, week: s.week)
        func finish() { if existing != nil { close(&s, personID: personID) } }
        // A request of theirs for a rise that you answer with your own figure is a negotiation of the rise.
        if p.topic == .payRise, talk.isRequest, talk.ask > 0 { return negotiateRise(&s, sub, p.amount, talk: &talk, data: data) }
        if p.topic == .promotion {
            var neg = talk.neg
            let out = ManagerModel.offerPromotion(&s, companyID: companyID, personID: personID, post: p.choice, monthlyWage: p.amount, terms: p.terms, negotiation: &neg, data: data)
            switch out {
            case .accepted(let text): finish(); return .agreed(text)
            case .unavailable(let text): return .notPossible(text)
            case .counter(let ask, let text):
                talk.neg = neg; talk.week = s.week; talk.offered = p.amount; talk.proposal.amount = ask; talk.proposal.terms = p.terms; talk.proposal.choice = p.choice
                talk.isFinal = neg.round >= Negotiation.patience(rank: sub.rank, temperament: Hiring.temperament(of: sub.person))
                store(talk, &s, personID: personID)
                return .counter(amount: ask, isFinal: talk.isFinal, text)
            }
        }
        switch applyFinal(&s, sub, p, data: data) {
        case .ok(let text):
            var text = text
            if p.topic == .payRise, let m = sub.member {
                let need = StaffTalks.raiseNeeded(role: m.role, age: sub.person.age, tables: data.catalog.tables)
                if p.amount < need { text += " It is less than the \(Int((need * 100).rounded()))% people feel as a raise, so they stay unhappy." }
            }
            finish()
            return .agreed(text)
        case .notPossible(let why): return .notPossible(why)
        case .unwilling(let why): return .unwilling(why)
        case .resigned(let why): finish(); return .resigned(why)
        }
    }

    /// Your figure against the rise they asked for. They ask for more (never less) through the shared `Negotiation`; a figure at or above their ask is taken;
    /// when their patience is gone they take your last figure and stay unhappy.
    static func negotiateRise(_ s: inout GameState, _ sub: Subject, _ offer: Double, talk: inout Talk, data: GameData) -> Reply {
        let id = sub.person.id
        guard offer > 0 else { return .notPossible("A raise has to be more than nothing.") }
        let first = ManagerModel.firstName(sub.person.name)
        func take(_ settled: Bool) -> Reply {
            let done = applyFinal(&s, sub, Proposal(.payRise, amount: offer), data: data)
            close(&s, personID: id)
            if case .ok(let text) = done { return settled ? .settled("\(first) takes it, but it is not what they hoped for. \(text)") : .agreed(text) }
            if case .notPossible(let why) = done { return .notPossible(why) }
            return .notPossible("The raise could not be given.")
        }
        if offer >= talk.ask - 1e-9 { return take(false) }
        let t = Hiring.temperament(of: sub.person)
        let position = Negotiation.position(opening: talk.ask, direction: .higher, temperament: t, key: "raise:\(id)")
        let reply = Negotiation.respond(offer: offer, position: position, temperament: t, rank: sub.rank, state: &talk.neg, week: s.week, step: 0.005, random: &s.random)
        talk.offered = offer; talk.week = s.week
        func ask(_ amount: Double, final: Bool, _ text: String) -> Reply {
            talk.proposal.amount = amount; talk.isFinal = final
            store(talk, &s, personID: id)
            return .counter(amount: amount, isFinal: final, text)
        }
        func pct(_ x: Double) -> String { String(format: "%.1f", x * 100) }
        switch reply.answer {
        case .accept: return take(false)
        case .counter(let c):
            return ask(c.amount, final: c.isFinal, c.isFinal ? "\(first): that is the least I can accept, +\(pct(c.amount))%." : "\(first): I was hoping for more than that. Could we say +\(pct(c.amount))%?")
        case .refuse: return ask(position.opening, final: false, "\(first): that is far from what I hoped for. I am asking for +\(pct(position.opening))%.")
        case .walkAway: return take(true)
        }
    }

    // MARK: They ask

    /// A request of theirs reaches you: stored on the person and sent to the Inbox, where you can agree, delay or decline it (or open the discussion
    /// and answer with a figure of your own). Called from the weekly staff pass.
    static func employeeAsks(_ s: inout GameState, companyIndex i: Int, staffID: Int, topic: Topic, data: GameData) {
        guard let k = s.companies[i].staff.firstIndex(where: { $0.id == staffID }), let n = s.people[staffID] else { return }
        let co = s.companies[i], m = co.staff[k]
        let w = World(state: s, data: data), cur = w.currency(co)
        let roleName = data.catalog.tables.roles[m.role]?.name ?? m.role
        var talk: Talk
        var title = "", body = "", agree = "", kind = ""
        var st = s.companies[i].staff
        switch topic {
        case .payRise:
            st[k].set("askW", s.week)
            let lastRaise = m.raw["lr"].map { $0.isNull ? m.hiredWeek : $0.int } ?? m.hiredWeek
            let years = (s.week - lastRaise) / 52
            let big = max(StaffTalks.raiseNeeded(role: m.role, age: n.age, tables: data.catalog.tables), 0.06)
            let why = s.week - lastRaise >= 52 ? "It has been \(years > 1 ? "\(years) years" : "a year") since my last raise." : "I have looked around, and people doing my job earn more."
            talk = Talk(opener: .employee, proposal: Proposal(.payRise, amount: big), week: s.week); talk.ask = big; talk.reason = why
            title = "\(n.name) asks about pay at \(co.name)"; body = "\(why) I like it here and would like to stay. Could we look at my pay? (\(roleName))"
            agree = "+\(Int(jsRound(big * 100)))% · +\(cur.display(m.monthlyWage * big))/month"; kind = "payask"
        case .payBasis:
            st[k].set("fixAskW", s.week)
            talk = Talk(opener: .employee, proposal: Proposal(.payBasis, choice: "salary"), week: s.week)
            let months = Int(jsRound(Double(s.week - m.hiredWeek) / 4.35))
            talk.reason = "I have been here \(months) months and the work goes well. I would like a fixed monthly salary instead of being paid by the hour, so I know what comes in each month."
            title = "\(n.name) asks for a fixed salary at \(co.name)"; body = talk.reason
            agree = "\(cur.display(cur.roundedStep(m.monthlyWage, about: 100)))/month, a full week"; kind = "fixask"
        case .promotion:
            st[k].set("promAskW", s.week)
            guard let post = ManagerModel.promotionPosts(s, companyID: co.id, personID: staffID, data: data).first(where: { $0.kind == "role" && $0.blocked.isEmpty }) else { s.companies[i].staff = st; return }
            talk = Talk(opener: .employee, proposal: Proposal(.promotion, amount: post.ask, choice: post.id), week: s.week); talk.ask = post.ask
            talk.reason = "I have grown in this job and I am ready for more. I would like to be \(post.title.lowercased())."
            title = "\(n.name) asks for a promotion at \(co.name)"; body = talk.reason + " I would ask about \(cur.display(post.ask)) a month for it."
            agree = "\(post.title) · \(cur.display(post.ask))/month"; kind = "promoask"
        case .hours:
            st[k].set("hoursAskW", s.week)
            let now = m.weeklyHours ?? StaffModel.fullWeekHours
            let target = max(rules.minHours, (now * rules.keepShare).rounded())
            guard target < now else { s.companies[i].staff = st; return }
            talk = Talk(opener: .employee, proposal: Proposal(.hours, amount: target, choice: "hours"), week: s.week); talk.ask = target
            talk.reason = "The long weeks are wearing me down. Could I work \(Int(target)) hours instead of \(Int(now.rounded()))?"
            title = "\(n.name) asks for shorter hours at \(co.name)"; body = talk.reason
            agree = "\(Int(target)) hours a week" + (m.payBasis == "fix" ? ", same pay" : ", pay follows the hours"); kind = "hoursask"
        default: s.companies[i].staff = st; return
        }
        s.companies[i].staff = st
        store(talk, &s, personID: staffID)
        s.addMessage(kind: "ask", from: n.name, title: title, body: body, companyID: co.id, tone: "n", status: "open",
                     options: [.option("Agree", agree), .option("Delay \(rules.delayWeeks) weeks", "Say you will decide later. If you do not, they feel turned down."), .option("Decline", "Disappointed. They may start looking around.")],
                     action: "staffx", data: .object(["t": .string(kind), "sid": .number(Double(staffID)), "ask": .number(talk.proposal.amount), "post": .string(talk.proposal.choice)]), expiresWeek: s.week + 3)
    }

    /// Should this person raise a request of the new kinds this week? Deterministic (no random draw), from the person and the data.
    static func requestTrigger(_ m: StaffMember, _ n: Person, company co: Company, week: Int, salesRoles: Set<String>, tenure ten: Double) -> StaffEvent? {
        guard m.noticeWeeks == 0, m.value("flag").isNull, !m.flag("seas") else { return nil }
        func due(_ key: String, _ every: Int) -> Bool { let w = m.int(key); return w == 0 || week - w >= every }
        if Int(ten) >= rules.promotionTenure, rules.promotionPersonalities.contains(n.str("pers")), StaffTalks.skill(m, n, salesRoles: salesRoles) >= rules.promotionSkill,
           due("promAskW", rules.promotionEvery), n.num("promoNo") <= Double(week) { return .promotionAsk(staffID: m.id) }
        if m.tiredness >= rules.tired, due("hoursAskW", rules.hoursEvery), (m.weeklyHours ?? StaffModel.fullWeekHours) * rules.keepShare >= rules.minHours { return .hoursAsk(staffID: m.id) }
        return nil
    }

    // MARK: You answer

    public enum Decision: Equatable, Sendable {
        case accept
        /// Your own figure: a share for a rise, pay for a promotion, hours for hours.
        case counter(Double)
        case delay
        case decline
    }

    /// Answer a request of theirs: agree, counter, delay or decline. You, the employer, may decline; they never decline a rise.
    public static func respond(_ s: inout GameState, companyID: Int, personID: Int, decision: Decision, data: GameData) -> Reply {
        guard let sub = subject(s, companyID: companyID, personID: personID) else { return .notPossible("This person no longer works here.") }
        guard let talk = openTalk(s, personID: personID), talk.isRequest else { return .notPossible("There is no request from them to answer.") }
        return respond(&s, sub, talk, decision, data: data)
    }

    static func respond(_ s: inout GameState, _ sub: Subject, _ talk0: Talk, _ decision: Decision, data: GameData) -> Reply {
        var talk = talk0
        let id = sub.person.id, p = talk.proposal
        let first = ManagerModel.firstName(sub.person.name)
        switch decision {
        case .accept:
            var go = p
            if p.topic == .promotion { go.amount = max(p.amount, talk.ask) }
            let out: Reply
            if p.topic == .promotion {
                var neg = Negotiation.State()
                let r = ManagerModel.offerPromotion(&s, companyID: s.companies[sub.ci].id, personID: id, post: p.choice, monthlyWage: go.amount, terms: p.terms, negotiation: &neg, data: data)
                if case .accepted(let text) = r { out = .agreed(text) } else if case .unavailable(let text) = r { out = .notPossible(text) } else { out = .notPossible("They want more for this job.") }
            } else {
                switch applyFinal(&s, sub, go, data: data) {
                case .ok(let text): out = .agreed(text)
                case .notPossible(let why): out = .notPossible(why)
                case .unwilling(let why): out = .unwilling(why)
                case .resigned(let why): out = .resigned(why)
                }
            }
            if out.changedTerms { close(&s, personID: id) }
            if p.topic == .payRise || p.topic == .promotion, out.changedTerms, let k = s.companies[sub.ci].staff.firstIndex(where: { $0.id == id }) {
                var st = s.companies[sub.ci].staff; st[k].happyUntilWeek = max(st[k].happyUntilWeek, s.week + 26); s.companies[sub.ci].staff = st   // a request granted
            }
            return out
        case .counter(let x):
            var offer = p
            offer.amount = x
            if p.topic == .payRise { return negotiateRise(&s, sub, x, talk: &talk, data: data) }
            return propose(&s, companyID: s.companies[sub.ci].id, personID: id, proposal: offer, data: data)
        case .delay:
            talk.delayUntil = s.week + rules.delayWeeks
            store(talk, &s, personID: id)
            return .delayed(untilWeek: talk.delayUntil, "You told \(first) you will answer within \(rules.delayWeeks) weeks. If you do not, \(first) will feel turned down.")
        case .decline:
            let text = declineRequest(&s, sub, talk, data: data)
            close(&s, personID: id)
            return .declined(text)
        }
    }

    /// You turn a fair request down: the consequences that always existed for a refused raise (the `denied` mark: more quit risk for half a year, the mood
    /// line) and the end of their cheer; for a manager the old consequence of a refused raise.
    static func declineRequest(_ s: inout GameState, _ sub: Subject, _ talk: Talk, data: GameData) -> String {
        let first = ManagerModel.firstName(sub.person.name)
        if sub.isManager {
            ManagerModel.declineManagerRaise(&s, companyIndex: sub.ci)
            return "\(first) is disappointed. The mood drops, and they may look for another job."
        }
        StaffTalks.markDenied(&s, companyIndex: sub.ci, staffID: sub.person.id)
        if let k = s.companies[sub.ci].staff.firstIndex(where: { $0.id == sub.person.id }) {
            var st = s.companies[sub.ci].staff; st[k].happyUntilWeek = 0; s.companies[sub.ci].staff = st
        }
        let after = quitYear(s, companyID: s.companies[sub.ci].id, personID: sub.person.id, data: data)
        return "\(first) feels turned down" + (after.map { ": the chance they hand in notice within a year is now \(Int(($0 * 100).rounded()))%." } ?? ".")
    }

    /// Leave a request to the manager: they decide it if it is inside their limit (level 2: anything, level 1: up to the pay limit on their card),
    /// by agreeing a fair request; otherwise it stays with you.
    public static func leaveToManager(_ s: inout GameState, companyID: Int, personID: Int, data: GameData) -> Reply {
        guard let sub = subject(s, companyID: companyID, personID: personID), !sub.isManager else { return .notPossible("This person no longer works here.") }
        guard let talk = openTalk(s, personID: personID), talk.isRequest else { return .notPossible("There is no request from them to answer.") }
        let co = s.companies[sub.ci]
        guard let h = handler(s, companyID: companyID, data: data) else { return .notPossible("This company has no manager with authority to decide it. It stays with you.") }
        let before = sub.member?.monthlyWage ?? 0
        var t = s
        _ = applyFinal(&t, sub, talk.proposal, data: data)
        let extra = (subject(t, companyID: companyID, personID: personID)?.member?.monthlyWage ?? before) - before
        guard managerMayDecide(co, extraMonthly: max(0, extra)) else {
            return .notPossible("This is above \(h.name)'s limit of \(World(state: s, data: data).currency(co).display(h.payLimit)) a month for pay and promotions. It stays with you.")
        }
        let r = respond(&s, sub, talk, .accept, data: data)
        if r.changedTerms { s.note("\(h.name) agreed \(sub.person.name)'s request at \(co.name) within their authority.", tone: "n", companyID: co.id) }
        return r
    }

    /// Answer a request through its Inbox message (agree, delay, decline). The same engine path as answering in the discussion.
    static func answerMessage(_ s: inout GameState, message m: Message, option idx: Int, data: GameData) {
        guard let i = s.companyIndex(m.companyID) else { return }
        let d = m.value("data"), sid = d["sid"].int
        guard let sub = subject(s, companyID: s.companies[i].id, personID: sid) else { return }
        var talk = openTalk(s, personID: sid)
        if talk == nil {   // the talk was forgotten; the message still says what they asked
            let topic: Topic = d["t"].string == "fixask" ? .payBasis : d["t"].string == "promoask" ? .promotion : d["t"].string == "hoursask" ? .hours : .payRise
            var t = Talk(opener: .employee, proposal: Proposal(topic, amount: d["ask"].double, choice: topic == .payBasis ? "salary" : d["post"].string), week: s.week)
            t.ask = d["ask"].double
            if topic == .hours { t.proposal.choice = "hours" }
            talk = t
        }
        guard let tk = talk else { return }
        _ = respond(&s, sub, tk, idx == 0 ? .accept : idx == 1 ? .delay : .decline, data: data)
    }

    // MARK: Weekly

    /// Delays that ran out count as a decline (you promised an answer and did not give one); talks nobody has touched for a while are forgotten.
    public static func weekly(_ s: inout GameState, data: GameData) {
        for ci in s.companies.indices where s.companies[ci].status.isLive {
            var ids = s.companies[ci].staff.map { $0.id }
            if let mid = s.companies[ci].managerID { ids.append(mid) }
            for id in ids {
                guard let n = s.people[id], let talk = talk(of: n) else { continue }
                if talk.delayUntil > 0, s.week >= talk.delayUntil, talk.isRequest, let sub = subject(s, companyID: s.companies[ci].id, personID: id) {
                    let text = declineRequest(&s, sub, talk, data: data)
                    s.note("\(sub.person.name) waited for your answer and heard nothing: \(text)", tone: "bad", companyID: s.companies[ci].id)
                    close(&s, personID: id)
                } else if talk.delayUntil == 0, s.week - max(talk.week, talk.neg.week) > Negotiation.memoryWeeks {
                    close(&s, personID: id)
                }
            }
        }
    }
}
