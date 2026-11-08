import Foundation
import GameCore
import Countries
import Employees
import Finance

/// What a manager does in a week, what they ask the owner, and what the owner can ask of them.
/// Originals: `managerWeek`, `decideProposal`, `execProposal`, `askManager` (engine/management/managers.js), `mgrStaffWork` (engine/people/staff_extras.js).
/// The store work (prices, stock, marketing) is `ManagerStore`, the department heads' decisions are `ManagerHeads`.
extension ManagerModel {
    /// Called once a week for every company, after the staff routine.
    public static func weekly(_ s: inout GameState, companyIndex ci: Int, _ bd: Trade, data: GameData, revenue rev: Double, utilisation util: Double, demand D: Double, capacity cap: Double) {
        noticeWeek(&s, companyIndex: ci, data: data)
        assistantWeek(&s, companyIndex: ci, data: data)
        retireLegacyProposals(&s, companyID: s.companies[ci].id)
        let co = s.companies[ci]
        guard let mid = co.managerID, let n = s.people[mid] else { return }
        let q = quality(co, bd, people: s.people)
        s.companies[ci].set("mgrQ", q)
        var fl = co.value("flags")
        fl["mgrCool"] = .number(max(0, fl["mgrCool"].double - 1))
        s.companies[ci].set("flags", fl)
        // Honesty problems
        let ethic = n.value("stats")["ethic"].double
        if ethic < 45 && s.random.chance(0.004 * (1 - ethic / 100)) {
            let steal = jsRound(rev * s.random.range(0.01, 0.04))
            Payments.companyPays(&s, companyID: co.id, amount: steal, category: "loss", label: "Unexplained expense")
            var f2 = s.companies[ci].value("flags"); f2["fraud"] = .number(f2["fraud"].double + steal); s.companies[ci].set("flags", f2)
            if s.random.chance(0.35) { s.note("An audit flags unexplained expenses at \(co.name). Check your manager.", tone: "bad", companyID: co.id) }
        }
        let started = co.value("mgrW0").isNull ? 0 : co.int("mgrW0")
        let cur = World(state: s, data: data).currency(co)
        // A year in the role: a raise is asked for
        if (s.week - started) % 52 == 51 && s.random.chance(0.7) {
            // Salary follows results: a strong year asks for more, a poor one for less.
            let pct = q > 0.7 ? 0.08 : q < 0.4 ? 0.04 : 0.06
            let ask = cur.roundedStep(co.managerMonthlyWage * pct, about: 100)
            var request = ContractTalk.Talk(opener: .employee, proposal: ContractTalk.Proposal(.payRise, amount: pct), week: s.week)
            request.ask = pct; request.reason = "A year in the role."
            let raiseSay = ManagerVoice.say(&s, companyIndex: ci, manager: n, bd: bd, situation: .raise, vars: ["up": cur.display(ask), "pct": "\(Int(pct * 100))%"])
            ContractTalk.store(request, &s, personID: mid)
            s.addMessage(kind: "ask", from: n.name, title: "\(n.name) asks for a raise at \(co.name)", body: raiseSay,
                         companyID: co.id, tone: "n", status: "open",
                         options: [.option("Grant the raise", "+\(cur.display(ask))/month"), .option("Delay \(ContractTalk.delayWeeks) weeks", "If you do not answer, they feel turned down."), .option("Decline", "They may leave")],
                         action: "mgrraise", data: .object(["ask": .number(ask), "npc": .number(Double(mid))]), expiresWeek: s.week + 3)
        }
        // Unhappy managers and rival offers
        if s.companies[ci].value("mgrNotice").isNull && mood(s.companies[ci]) < 25 && s.random.chance(0.02) {
            resign(&s, companyIndex: ci, why: "I have not felt valued here for a long time")
        }
        rivalOffer(&s, companyIndex: ci, data: data)
        staffWork(&s, ci, bd, n, q, data: data, revenue: rev)
        PremisesProposals.managerWeek(&s, ci, n, data: data)   // demand-limited by the premises: propose a bigger place (PremisesProposals.swift)
        ManagerStore.week(&s, ci, manager: n, quality: q, bd, utilisation: util, data: data)
        ManagerHeads.week(&s, ci, bd, manager: n, quality: q, utilisation: util, demand: D, capacity: cap, data: data)
        ManagerVoice.digestWeek(&s, companyIndex: ci, manager: n, bd: bd, utilisation: util)
        guard s.week % 3 == 0, s.companies[ci].value("flags")["mgrCool"].double <= 0 else { return }
        if let dp = decideProposal(s, ci, bd, data: data, quality: q, utilisation: util, demand: D, capacity: cap) { propose(&s, ci, dp, n, q, data: data) }
    }

    static func weekCost(_ s: GameState, _ co: Company, data: GameData) -> Double {
        FinanceContext(countries: data.countries, trades: data.catalog).weeklyCost(co, s)
    }

    static func marketWage(_ s: GameState, _ co: Company, role: String, data: GameData) -> Double {
        let w = World(state: s, data: data)
        guard let base = data.catalog.tables.roles[role]?.baseMonthlyWage, let city = w.city(co) else { return 0 }
        return Wages.market(baseMonthlyWage: base, country: w.country(co), city: city, economy: s.economy, rates: w.rates)
    }

    /// Paperwork, mistakes of the inexperienced, and the monthly pay review. Original: `mgrStaffWork`.
    static func staffWork(_ s: inout GameState, _ ci: Int, _ bd: Trade, _ n: Person, _ q: Double, data: GameData, revenue: Double) {
        var co = s.companies[ci]
        let actsAlone = budget(of: co).actsAlone
        let doesAll = co.value("flags")["onbAll"].bool || n.num("exp") >= 5
        let risk = n.value("stats")["risk"].double
        var staff = co.staff
        for k in staff.indices {
            let miss = StaffExtras.missing(staff[k])
            if miss.isEmpty { continue }
            if doesAll { miss.forEach { StaffExtras.tick(&staff[k], key: $0.key) } }
            else if s.random.chance(0.25 + risk * 0.003) { StaffExtras.tick(&staff[k], key: miss[0].key) }
        }
        co.staff = staff
        s.companies[ci] = co
        let cur = World(state: s, data: data).currency(co)
        // Inexperience: costly mistakes
        let expF = clamp(1 - n.num("exp") / 8, 0, 1)
        if s.random.chance(0.0025 + 0.011 * expF) {
            let r = co.value("lastW")["rev"].isNull ? 3000 : max(1, co.value("lastW")["rev"].double)
            if s.random.chance(2.0 / 3) {
                let c = jsRound(r * s.random.range(0.02, 0.07))
                Payments.companyPays(&s, companyID: co.id, amount: c, category: "loss", label: "Manager mistake")
                s.note("\(n.name) made a costly mistake at \(co.name) (\(cur.display(c))).", tone: "bad", companyID: co.id)
            } else {
                s.companies[ci].priceLevel = clamp(co.priceLevel + (s.random.chance(0.5) ? 1 : -1), -2, 2)
                s.note("\(n.name) mis-set prices at \(co.name).", tone: "bad", companyID: co.id)
            }
        }
        // Monthly pay review: the manager (or the HR head) closes the pay talks the owner would otherwise hold (staff do not ask the owner while a manager is in charge)
        guard s.week % 4 == 0 else { return }
        let rv = ManagerHeads.reviewer(s, co, manager: n)
        let rq = ManagerHeads.reviewQuality(s, co, manager: q)
        let salesRoles = data.catalog.tables.salesRoles
        for m in s.companies[ci].staff {
            guard let nn = s.people[m.id] else { continue }
            co = s.companies[ci]
            let mk0 = cur.roundedStep(marketWage(s, co, role: m.role, data: data) * m.partTimeShare * (0.7 + nn.skill / 160), about: 100)
            let ten = s.week - m.hiredWeek
            let lrW = s.week - (m.raw["lr"].map { $0.isNull ? m.hiredWeek : $0.int } ?? m.hiredWeek)
            let sk = StaffTalks.skill(m, nn, salesRoles: salesRoles)
            if m.payBasis == "hour", (m.weeklyHours ?? 0) == 0, !m.flag("seas"), ten >= 26, sk >= 60, m.raw["flag"] == nil || m.raw["flag"]!.isNull,
               StaffTalks.wantsFixedSalary(nn), actsAlone {
                StaffTalks.setFixedPay(&s, companyIndex: ci, staffID: m.id, data: data)
                if let k = s.companies[ci].staff.firstIndex(where: { $0.id == m.id }) { var st = s.companies[ci].staff; st[k].happyUntilWeek = max(st[k].happyUntilWeek, s.week + 26); s.companies[ci].staff = st }
                s.note("\(rv.name) moved \(nn.name) to a fixed salary at \(co.name).", tone: "n", companyID: co.id)
            }
            let paid = m.monthlyWage + StaffPerks.worthMonthly(co, m, currency: cur)   // perks that cover them count as pay
            let why: String? = m.noticeWeeks > 0 ? "has handed in notice" : (mk0 > paid * 1.25 ? "is paid far below market and may leave"
                : (lrW >= 52 && ten >= 52 ? "has had no raise for \(lrW >= 104 ? "\(lrW / 52) years" : "a year")"
                   : (sk >= 68 && ten >= 26 && mk0 > paid * 1.04 ? "is one of your best and paid below market" : nil)))
            let yearOn = lrW >= 52 && ten >= 52 && m.noticeWeeks == 0
            let askW = m.raw["askW"].flatMap { $0.isNull ? nil : $0.int }
            guard let reason = why, yearOn || mk0 > paid * 1.03, askW == nil || askW == 0 || s.week - askW! >= 12 else { continue }
            let felt = StaffTalks.raiseNeeded(role: m.role, age: nn.age, tables: data.catalog.tables)
            let target = yearOn && mk0 <= m.monthlyWage * (1 + felt) ? cur.roundedStep(m.monthlyWage * (1 + felt + (1 - rq) * 0.01), about: 100)
                : max(m.monthlyWage + 100, cur.roundedStep(m.monthlyWage + (mk0 - m.monthlyWage) * (1 - 0.55 * rq), about: 100))
            let d = target - m.monthlyWage
            if ContractTalk.managerMayDecide(co, extraMonthly: d, s, data: data) {
                let had = m.noticeWeeks > 0
                StaffTalks.raise(&s, companyIndex: ci, staffID: m.id, percent: target / m.monthlyWage - 1, data: data)
                if had { s.note("\(nn.name) withdrew the notice after the raise.", tone: "good", companyID: co.id) }
                s.note("\(rv.name) raised \(nn.name)'s pay at \(co.name) to \(cur.display(target)).", tone: "n", companyID: co.id)
            } else if let k = s.companies[ci].staff.firstIndex(where: { $0.id == m.id }) {
                var st = s.companies[ci].staff; st[k].set("askW", s.week); s.companies[ci].staff = st
                let roleName = data.catalog.tables.roles[m.role]?.name ?? m.role
                s.addMessage(kind: "ask", from: rv.name, title: "Pay review: \(nn.name) at \(co.name)",
                             body: "\(nn.name) (\(roleName)) \(reason). I negotiated it down to \(cur.display(target)) per month (+\(cur.display(d))).",
                             companyID: co.id, tone: "n", status: "open",
                             options: [.option("Approve", "+\(cur.display(d))/month"), .option("Not now", "May leave")],
                             action: "staffx", data: .object(["t": "raise", "sid": .number(Double(m.id)), "w": .number(target)]), expiresWeek: s.week + 3)
            }
        }
    }

    // MARK: Proposals

    struct Proposal { var kind: String; var role: String = ""; var cost: Double = 0; var id: String = "" }

    /// What the manager would like to do about the state of the business. Original: `decideProposal` (cutting, advertising, cash, equipment, vehicles and
    /// space; see `bottleneckProposal`). Headcount is the staffing plan's, not a proposal.
    static func decideProposal(_ s: GameState, _ ci: Int, _ bd: Trade, data: GameData, quality q: Double, utilisation util: Double, demand D: Double, capacity cap: Double) -> Proposal? {
        let co = s.companies[ci]
        guard cap > 0, util > 0 else { return nil }
        let sense = 1 + (HashedRandom.first("sense:\(co.id):\(s.week)") - 0.5) * 0.5 * (1 - q)
        let cur = World(state: s, data: data).currency(co)
        // with an operations head, capacity is theirs to raise (ManagerHeads.operations)
        if D * sense > cap * 1.12 && util > 0.9, ManagerHeads.head(s, co, "ops") == nil, let p = bottleneckProposal(s, co, bd, data: data) { return p }
        if util < 0.5 && co.staff.count > 2 && co.cash > 0 && D < cap * 0.62 { return Proposal(kind: "cut") }
        let wk = weekCost(s, co, data: data)
        if co.awareness < 26 && co.cash > wk * 6 { return Proposal(kind: "ad", cost: cur.scaledPrice(2500)) }
        if co.cash < wk * 2 && co.cash < cur.scaledPrice(50000) { return Proposal(kind: "cash") }
        return nil
    }

    /// Money missing before a hire costing `cost` a year is safe (the staffing plan's growth rule). Original: `hireShort`.
    static func hireShort(_ s: GameState, _ co: Company, cost: Double, data: GameData) -> Double {
        let wk = cost / 52
        let wkProfit = (co.monthlyHistory.last?.profit ?? 0) / 4.33
        let need = wkProfit >= wk * 0.8 ? wk * 6 + weekCost(s, co, data: data) * 2 : cost * 0.5 + weekCost(s, co, data: data) * 6
        return max(0, jsRound(need - co.cash))
    }

    static func propose(_ s: inout GameState, _ ci: Int, _ dp: Proposal, _ n: Person, _ q: Double, data: GameData) {
        let co = s.companies[ci]
        let key = dp.kind + dp.role
        var fl = co.value("flags")
        var last = fl["propLast"]
        if s.inbox.contains(where: { $0.companyID == co.id && $0.status == "open" && $0.actionID == "prop" && $0.value("data")["t"].string == dp.kind }) { return }
        guard Double(s.week) - (last[key].isNull ? -99 : last[key].double) >= 20 else { return }
        last[key] = .number(Double(s.week)); fl["propLast"] = last; fl["mgrCool"] = 3; s.companies[ci].set("flags", fl)
        let cur = World(state: s, data: data).currency(co)
        let bd = data.catalog[co.type]
        let utilText = "\(Int(max(0, min(1.5, co.value("lastW")["util"].double)) * 100))"
        // A manager promoted with only some duties leaves the other decisions to you.
        let mayDecide = dutyAllows(n, dp.kind)
        // Within the budget the owner gave, a manager buys what the business is short of without waiting for an answer.
        let affordable = co.cash > dp.cost * 0.5 + weekCost(s, co, data: data) * 6
        // A quarter more space in the same premises is routine: within the manager's budget like a vehicle. A cautious manager uses less of it.
        let amount = dp.cost / ManagerVoice.budgetUse(n)
        if ["eq", "veh", "space"].contains(dp.kind), mayDecide, affordable, withinBudget(co, amount: amount, s, data: data) {
            exec(&s, ci, dp, n, q, data: data)
            ManagerVoice.record(&s, companyIndex: ci, "\(dp.kind == "veh" ? "Added a vehicle" : dp.kind == "space" ? "Took more space" : "Bought equipment") within the budget because customers were being turned away.")
            return
        }
        // Someone above the manager judges it first and only passes on what is above their budget or a close call.
        var view = ""
        if hierarchyDecide(&s, ci, dp, n, affordable: affordable, view: &view, data: data) { return }
        let title: String, body: String, opts: [JSONValue]
        switch dp.kind {
        case "eq", "veh", "space":
            let eqName = data.catalog[co.type]?.equipment.first { $0.id == dp.id }?.name ?? "equipment"
            title = dp.kind == "eq" ? "Buy \(eqName) for \(co.name)" : dp.kind == "veh" ? "Add a vehicle at \(co.name)" : "Expand the premises of \(co.name)"
            body = ManagerVoice.say(&s, companyIndex: ci, manager: n, bd: bd, situation: .equip, vars: ["role": dp.kind == "space" ? "space" : eqName.lowercased(), "util": utilText, "cost": cur.display(dp.cost)]) + (view.isEmpty ? "" : " " + view)
            opts = [.option("Approve", "About \(cur.display(dp.cost))"), .option("Decline")]
        case "cut":
            title = "Reduce staffing at \(co.name)"; body = ManagerVoice.say(&s, companyIndex: ci, manager: n, bd: bd, situation: .cut, vars: ["util": utilText])
            opts = [.option("Approve: let someone go", "Cut payroll; severance applies."), .option("Keep staff")]
        case "ad":
            title = "Start advertising at \(co.name)"; body = ManagerVoice.say(&s, companyIndex: ci, manager: n, bd: bd, situation: .ad, vars: ["cost": cur.display(dp.cost)])
            opts = [.option("Approve", "About \(cur.display(dp.cost))"), .option("Decline")]
        default:
            title = "Cash is running low at \(co.name)"
            body = ManagerVoice.say(&s, companyIndex: ci, manager: n, bd: bd, situation: .cash, vars: ["cash": "\(Int(max(0, jsRound(co.cash / max(1, weekCost(s, co, data: data))))))"])
            opts = [.option("Inject \(cur.display(cur.scaledPrice(100000)))", "From your personal account."), .option("Inject \(cur.display(cur.scaledPrice(30000)))"), .option("Not now", "Cash may run out.")]
        }
        s.addMessage(kind: "ask", from: n.name, title: title, body: body, companyID: co.id, tone: "n", status: "open", options: opts, action: "prop",
                     data: .object(["t": .string(dp.kind), "role": .string(dp.role), "cost": .number(dp.cost), "id": .string(dp.id)]), expiresWeek: s.week + 3)
    }

    /// Carry out a proposal. Original: `execProposal`.
    static func exec(_ s: inout GameState, _ ci: Int, _ dp: Proposal, _ n: Person, _ q: Double, data: GameData) {
        let co = s.companies[ci]
        switch dp.kind {
        case "eq", "veh", "space": buyForProposal(&s, ci, dp, n, data: data)
        case "cut":
            let weakest = co.staff.min { (s.people[$0.id]?.skill ?? 0) + $0.skillGain < (s.people[$1.id]?.skill ?? 0) + $1.skillGain }
            if let w = weakest { Dismissal.dismiss(&s, companyID: co.id, staffID: w.id, reason: .redundancy, data: data); s.note("\(n.name) reduced staffing at \(co.name).", tone: "n", companyID: co.id); ManagerVoice.record(&s, companyIndex: ci, "Let one person go because the load was under half.") }
        case "ad":
            let ch = (data.catalog[co.type]?.audience ?? 0) > 0.5 ? "google" : "meta"
            var mkt = co.value("mkt")
            if mkt[ch].isNull, FranchiseStandards.campaignRefusal(co, channel: ch) == nil {
                mkt[ch] = .object(["b": .number(World(state: s, data: data).currency(co).scaledPrice(1500)), "since": .number(Double(s.week)), "lock": .number(Double(s.week + 4))])
                s.companies[ci].set("mkt", mkt)
                s.note("\(n.name) started ads for \(co.name).", tone: "n", companyID: co.id)
            }
        default:
            s.addMessage(kind: "info", from: n.name, title: "Cash is low at \(co.name)", body: "Your manager \(n.name) recommends putting in money or taking a loan.", companyID: co.id, tone: "bad", status: "done", sev: 3, aud: "owner")
        }
    }

    /// The player answers a message from a manager: "prop" (a proposal), "mgrraise" (the yearly raise), "mgrpoach" (a rival's offer).
    public static func answer(_ s: inout GameState, message m: Message, option idx: Int, data: GameData) {
        guard let ci = s.companyIndex(m.companyID) else { return }
        let co = s.companies[ci]
        let d = m.value("data")
        let cur = World(state: s, data: data).currency(co)
        switch m.actionID {
        case "mgrraise":
            if idx == 0 {
                s.companies[ci].managerMonthlyWage = co.managerMonthlyWage + d["ask"].double
                s.companies[ci].set("mood", min(100, mood(co) + 8))
                if let mid = co.managerID { ContractTalk.close(&s, personID: mid) }
            } else if idx == 1 {   // delay: an answer is due; the weekly contract pass counts a missed one as a decline
                if let mid = co.managerID, var talk = ContractTalk.openTalk(s, personID: mid) { talk.delayUntil = s.week + ContractTalk.delayWeeks; ContractTalk.store(talk, &s, personID: mid) }
            } else {
                declineManagerRaise(&s, companyIndex: ci)
                if let mid = co.managerID { ContractTalk.close(&s, personID: mid) }
            }
        case "mgrpoach":
            if idx == 0 {
                s.companies[ci].managerMonthlyWage = co.managerMonthlyWage + d["up"].double   // matching the offer: they stay (nobody turns down more pay for the same job)
                s.companies[ci].set("mood", min(100, mood(co) + 6))
            } else { resign(&s, companyIndex: ci, why: "a rival made me an offer", to: "a rival group") }
        default:
            let kind = d["t"].string
            if legacyProposalKinds.contains(kind) { return }   // asked before the staffing plan took over hiring: nothing to carry out
            if kind == "cash" {
                if idx == 0 { Payments.injectCash(&s, companyID: co.id, amount: cur.scaledPrice(100000)) }
                else if idx == 1 { Payments.injectCash(&s, companyID: co.id, amount: cur.scaledPrice(30000)) }
                return
            }
            if kind == PremisesProposals.kind { PremisesProposals.answer(&s, message: m, option: idx, data: data); return }
            guard idx == 0, let mid = co.managerID, let n = s.people[mid], let bd = data.catalog[co.type] else { return }
            let dp = Proposal(kind: kind, role: d["role"].string, cost: d["cost"].double, id: d["id"].string)
            exec(&s, ci, dp, n, quality(s.companies[ci], bd, people: s.people), data: data)
        }
    }

    /// The old consequence of turning a manager's raise down: the mood drops and they may resign.
    static func declineManagerRaise(_ s: inout GameState, companyIndex ci: Int) {
        s.companies[ci].set("mood", max(0, mood(s.companies[ci]) - 10))
        if s.random.chance(0.55) { resign(&s, companyIndex: ci, why: "without the raise I have to look elsewhere") }
    }

    // MARK: Asking the manager

    public static let askOptions: [(key: String, label: String)] = [
        ("price_up", "Raise prices a little"), ("price_down", "Lower prices a little"), ("cut", "Cut staff costs"),
        ("mkt_more", "Spend more on marketing"), ("mkt_less", "Spend less on marketing"), ("quality", "Improve maintenance and quality"), ("save", "Reduce running costs")]

    /// The owner asks the manager for a change; the answer arrives in the inbox. Original: `askManager`.
    public static func ask(_ s: inout GameState, companyID: Int, key: String, data: GameData, marketing: MarketingTables) -> String? {
        guard let ci = s.companyIndex(companyID), let mid = s.companies[ci].managerID, let n = s.people[mid], let bd = data.catalog[s.companies[ci].type] else { return nil }
        let co = s.companies[ci]
        let q = quality(co, bd, people: s.people)
        var say = ""
        if !co.value("askW").isNull, s.week - co.int("askW") < 2 {
            say = "Give me a couple of weeks to see how the last change works out."
        } else {
            s.companies[ci].set("askW", s.week)
            let util = co.value("lastW")["util"].double
            let cur = World(state: s, data: data).currency(co)
            switch key {
            case "price_up":
                if co.priceLevel >= 2 { say = "We are already at the top of what the market accepts." }
                else { PriceMoves.managerStep(&s, ci, up: true, balance: data.balance); say = util < 0.6 ? "Done, but demand is soft, so we may lose some customers." : "Done. We have room for it." }
            case "price_down":
                if co.priceLevel <= -3 { say = "We are already the cheapest around. Going lower only eats the margin." }
                else { PriceMoves.managerStep(&s, ci, up: false, balance: data.balance); say = "Done. We should see more customers." }
            case "cut":
                if co.staff.count <= 1 { say = "We are down to the bone already." }
                else { exec(&s, ci, Proposal(kind: "cut"), n, q, data: data); say = "I let one person go. Expect a little less capacity." }
            case "mkt_more":
                let ch = bd.audience > 0.5 ? "google" : "meta"
                var mkt = co.value("mkt")
                let opts = marketing.channels[ch]?.budgets(in: cur) ?? []
                if let why = FranchiseStandards.campaignRefusal(co, channel: ch) { say = "We cannot: \(why)." }
                else if let next = opts.first(where: { $0 > mkt[ch]["b"].double }) {
                    if mkt[ch].isNull { mkt[ch] = .object(["b": .number(next), "since": .number(Double(s.week)), "lock": .number(Double(s.week + (marketing.channels[ch]?.minimumWeeks ?? 4)))]) }
                    else { mkt[ch]["b"] = .number(next) }
                    s.companies[ci].set("mkt", mkt)
                    say = "I raised the \(marketing.channels[ch]?.name ?? ch) budget to \(cur.display(next)) a week."
                } else { say = "We are already spending the most that channel makes sense for." }
            case "mkt_less":
                var mkt = co.value("mkt")
                if let ch = mkt.object.keys.sorted().first(where: { mkt[$0]["b"].double > 0 }) {
                    let lock = mkt[ch]["lock"].isNull ? 0 : mkt[ch]["lock"].double
                    if Double(s.week) < lock { say = "Some of it is locked in for now." }
                    else {
                        let lower = (marketing.channels[ch]?.budgets(in: cur) ?? []).reversed().first(where: { $0 < mkt[ch]["b"].double }) ?? 0
                        if lower > 0 { mkt[ch]["b"] = .number(lower) } else { mkt = Marketing.removing(mkt, ch) }
                        s.companies[ci].set("mkt", mkt)
                        say = "I cut \(marketing.channels[ch]?.name ?? ch) to " + (lower > 0 ? "\(cur.display(lower)) a week." : "nothing.")
                    }
                } else { say = "We are not spending anything on marketing." }
            case "quality":
                if co.maintenance >= 2 { say = "We already maintain everything thoroughly." }
                else { s.companies[ci].maintenance = co.maintenance + 1; say = "Done. It costs more, but breakdowns should drop." }
            case "save":
                if co.maintenance <= 0 { say = "There is nothing left to trim without hurting the business." }
                else { s.companies[ci].maintenance = co.maintenance - 1; say = "I will trim upkeep. Quality may slip a little." }
            default: return nil
            }
        }
        s.addMessage(kind: "info", from: n.name, title: "Re: \(co.name)", body: say, companyID: co.id, tone: "n", status: "done")
        return say
    }
}
