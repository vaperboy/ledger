import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Random events and the decisions they put in the inbox. Original: engine/events/engine.js.
///
/// Each week every open company may have an event, weighted by its trade's list, its own risk (some choices make a
/// business riskier), its condition (broken kit makes breakdowns likelier) and how long it has been open. Events that
/// need a decision wait in the inbox with a deadline and a preview of what each answer costs; unanswered ones take
/// the cheapest answer. A manager with authority decides for you.
public enum EventEngine {
    /// The numbers an event's formulas can use. Original: `evCtx`.
    struct Context {
        var wk: Double      // typical weekly revenue
        var pay: Double     // weekly payroll
        var eqv: Double     // equipment value
        var variables: [String: Double]
    }

    static func context(for co: Company, data: GameData, employerFactor: Double, costIndex: Double = 1) -> Context {
        let h = co.monthlyHistory.suffix(3)
        let wk: Double = !h.isEmpty ? max(h.reduce(0) { $0 + $1.revenue } / (Double(h.count) * 4.35), 1000 * costIndex)
                                    : (co.value("lastW").isNull ? 3000 * costIndex : max(co.lastWeekRevenue, 1000 * costIndex))
        let pay = co.staff.reduce(0) { $0 + $1.monthlyWage } * 12 / 52 * employerFactor
        let eqv = co.num("eqv") != 0 ? co.num("eqv") : (CompanyFigures.equipmentBookValue(co) != 0 ? CompanyFigures.equipmentBookValue(co) : 50000 * costIndex)
        let v: [String: Double] = ["wk": wk, "pay": pay, "eqv": eqv, "co.eqc": co.num("eqc", 1), "co.q": co.quality, "co.mgrQ": co.num("mgrQ"),
                                   "co.payGap": co.num("payGap"), "co.books": co.num("books", 0.5), "co.rep": co.reputation]
        return Context(wk: wk, pay: pay, eqv: eqv, variables: v)
    }

    /// Replace formulas in an effects object by their rounded numbers. Original: `resolveFx`.
    ///
    /// Money amounts written as plain numbers (`cash`, `fine`, `loss`, `bonus`, `owner`) are at the reference price level and are
    /// scaled here to the company's country (`currency.scaledPrice`). Amounts from a formula are already in the company's money
    /// (they come from its own weekly figures) and are not scaled again.
    static let moneyKeys: Set<String> = ["cash", "fine", "loss", "bonus", "owner"]
    static func resolve(_ fx: JSONValue, _ ctx: Context, currency: Currency? = nil) -> JSONValue {
        switch fx {
        case .object(let o):
            if let e = o["expr"], o.count == 1 { return .number(jsRound(Formula(e.string).evaluate(ctx.variables))) }
            var out: [String: JSONValue] = [:]
            for (k, v) in o {
                if let cur = currency, moneyKeys.contains(k), case .number(let n) = v { out[k] = .number(cur.scaledPrice(n)) }
                else { out[k] = resolve(v, ctx, currency: currency) }
            }
            return .object(out)
        case .array(let a): return .array(a.map { resolve($0, ctx, currency: currency) })
        default: return fx
        }
    }

    // MARK: Weekly roll

    /// Roll this week's events for one open company. Original: `spawnEvents`.
    public static func spawn(_ s: inout GameState, companyIndex i: Int, library: EventLibrary, data: GameData, context fc: FinanceContext) {
        guard let bd = data.catalog[s.companies[i].type] else { return }
        var cooldown = s.companies[i].value("flags")["evCool"].double
        if cooldown > 0 {
            cooldown -= 1
            setFlag(&s, i, "evCool", cooldown)
        }
        let w = World(state: s, data: data)
        let risk = Knobs.effect(s.companies[i], bd, "r", w)
        let employerFactor = w.country(s.companies[i]).employerCostFactor
        let c = context(for: s.companies[i], data: data, employerFactor: employerFactor, costIndex: w.country(s.companies[i]).costIndex)
        for id in bd.eventIDs {
            let co = s.companies[i]
            guard let e = library[id] else { continue }
            if e.minimumCompanyAgeWeeks > 0 && s.week - co.foundedWeek < e.minimumCompanyAgeWeeks { continue }
            // Praise, awards and big orders need real customers.
            if (e.tone == "good" || id == "g_press" || id == "g_offer") && !(co.lastWeekUnits > 0.5 && co.openedWeek != nil && s.week - co.openedWeek! >= 12) { continue }
            if co.staff.isEmpty && mentionsStaff(e) { continue }
            if co.staff.isEmpty && co.managerID == nil && !soloAllowed(id, co) { continue }
            var p = e.weight * risk * 0.6 * (e.condition?.evaluate(c.variables) ?? 1)
            if !(p > 0) { p = 0 }
            if p <= 0 || !s.random.chance(p) { continue }
            if Sourcing.shields(s, companyID: co.id, eventID: id) { continue }   // supplied from inside: outside supplier trouble does not reach it
            if !e.options.isEmpty && s.companies[i].value("flags")["evCool"].double > 0 { continue }
            if !e.options.isEmpty { setFlag(&s, i, "evCool", 6) }
            fire(&s, companyIndex: i, e, ctx: c, data: data, context: fc)
        }
    }

    static func setFlag(_ s: inout GameState, _ i: Int, _ key: String, _ v: Double) {
        var flags = s.companies[i].value("flags")
        flags[key] = .number(v)
        s.companies[i].set("flags", flags)
    }

    static func mentionsStaff(_ e: GameEvent) -> Bool {
        let t = e.text.lowercased()
        if ["employee", "staff", "worker", "colleague"].contains(where: { t.contains($0) }) { return true }
        return e.options.contains { o in o.effects["quit"].bool || !o.effects["raise"].isNull || !o.effects["sick"].isNull }
    }

    /// A one-person business with no staff can still have customer-side events. Original: `SOLO_CUST`, `SOLO_MKT`.
    static let soloCustomerEvents: Set<String> = ["g_late", "g_review", "g_lawsuit", "g_offer", "c_scope", "c_clientloss", "c_damage", "c_wedding", "c_malprac", "c_patient",
                                                  "v_critic", "v_poison", "v_overbook", "v_injury", "v_churn", "v_bigwin", "v_cheat", "v_addict"]
    static let soloMarketingEvents: Set<String> = ["g_press", "g_award", "v_ota"]
    static func soloAllowed(_ id: String, _ co: Company) -> Bool {
        if soloCustomerEvents.contains(id) { return true }
        if soloMarketingEvents.contains(id) { return co.value("mkt").object.values.contains { $0["b"].double > 0 } }
        return false
    }

    // MARK: Firing

    /// A machine the company owns, for texts like "{eq} has broken down". Original: `pickEqName`.
    static func pickEquipmentName(_ s: inout GameState, companyIndex i: Int, data: GameData) -> String {
        let co = s.companies[i]
        guard let bd = data.catalog[co.type] else { return "A key machine" }
        let vehicles = co.value("veh").array.map { $0["eq"].string }
        let names = bd.equipment.filter { $0.vehicleModels != nil ? vehicles.contains($0.id) : !co.value("eq")[$0.id].isNull }.map { $0.name }
        return names.isEmpty ? "A key machine" : s.random.pick(names)
    }

    static func fire(_ s: inout GameState, companyIndex i: Int, _ e: GameEvent, ctx: Context, data: GameData, context fc: FinanceContext) {
        let co = s.companies[i]
        let cur = Currency(country: fc.country(of: co, s), rates: fc.rates(s))
        if SpecialEvents.handle(&s, companyIndex: i, e, ctx: ctx, data: data, context: fc) { return }
        var title = e.text.replacingOccurrences(of: "{n}", with: co.name)
        // The original always draws the equipment name, even when the text has no {eq}; keep the same number of random draws.
        let machine = pickEquipmentName(&s, companyIndex: i, data: data)
        title = title.replacingOccurrences(of: "{eq}", with: machine)
        if e.automatic {
            apply(&s, companyIndex: i, resolve(e.automaticEffects, ctx, currency: cur), ctx: ctx, event: e, data: data, context: fc)
            s.addMessage(from: co.name, title: title, body: "", companyID: co.id, tone: e.tone)
            s.note(title, tone: e.tone, companyID: co.id)
            return
        }
        if e.options.isEmpty { s.note(title, tone: e.tone, companyID: co.id); return }
        if e.lawyerHelps && co.value("law")["own"].bool { title += " Your law firm handles it, costs drop." }
        let options = e.options.map { JSONValue.option($0.label, $0.detail, effects: resolve($0.effects, ctx, currency: cur).object) }
        let decision = decider(co, options: options, state: s)
        if decision == .manager {
            let pick = choose(co, options: options, ctx: ctx, quality: ManagerModel.quality(co, bd(data, co), people: s.people), random: &s.random)
            let who = s.people[co.managerID ?? 0]?.name ?? "The manager"
            s.addMessage(from: co.name, title: title, body: "", companyID: co.id, tone: e.tone, options: options)
            if let k = s.inbox.indices.first, true { s.inbox[k].set("status", "done"); s.inbox[k].set("pick", pick); s.inbox[k].set("mgrName", who); s.inbox[k].set("ev", e.id) }
            apply(&s, companyIndex: i, options[pick]["fx"], ctx: ctx, event: e, data: data, context: fc)
            s.note("\(co.name): \(who) handled \"\(title)\" by choosing: \(options[pick]["l"].string).", tone: "n", companyID: co.id)
        } else {
            let id = s.addMessage(kind: "decision", from: co.name, title: title, body: "", companyID: co.id, tone: e.tone, status: "open", options: options,
                                  expiresWeek: s.week + e.expiresAfterWeeks)
            if let k = s.inbox.firstIndex(where: { $0.id == id }) {
                s.inbox[k].set("ev", e.id)
                s.inbox[k].set("cat", e.category)
            }
            s.note("Decision needed: \(title)", tone: e.tone, companyID: co.id)
        }
    }

    static func bd(_ data: GameData, _ co: Company) -> Trade { data.catalog[co.type]! }

    enum Decider { case owner, manager }

    /// Who decides: you, or a manager with authority for this size of decision. Original: `decider`.
    static func decider(_ co: Company, options: [JSONValue], state s: GameState) -> Decider {
        guard co.managerID != nil, s.people[co.managerID!] != nil else { return .owner }
        let cost = options.map { max(abs($0["fx"]["cash"].double), abs($0["fx"]["loss"].double), $0["fx"]["fine"].double) }.max() ?? 0
        let auth = co.value("auth")
        let level = auth["lvl"].int
        let big = s.rest["group"]?["big"].double ?? 5_000_000
        if cost > big { return .owner }
        if level >= 2 || (level == 1 && cost <= auth["buy"].double) { return .manager }
        return .owner
    }

    /// A manager's pick: the option that scores best for the business, with some noise that shrinks with quality.
    /// Original: `chooseOpt`, `scoreFx`.
    static func choose(_ co: Company, options: [JSONValue], ctx: Context, quality q: Double, random r: inout DeterministicRandom) -> Int {
        let scores = options.map { score($0["fx"], ctx) + r.gauss() * ctx.wk * (1.2 - q) * 0.4 }
        var best = 0
        for i in 1..<max(1, scores.count) where scores[i] > scores[best] { best = i }
        return best
    }

    static func score(_ fx: JSONValue, _ c: Context) -> Double {
        func one(_ f: JSONValue) -> Double {
            var s = f["cash"].double - abs(f["loss"].double) - f["fine"].double
            s += f["rep"].double * c.wk * 0.5 + f["aware"].double * c.wk * 0.15
            if !f["dem"].isNull { s += (f["dem"][0].double - 1) * c.wk * f["dem"][1].double * 0.45 }
            if !f["cap"].isNull { s += (f["cap"][0].double - 1) * c.wk * f["cap"][1].double * 0.5 }
            s -= c.wk * f["close"].double * 0.8
            s -= c.pay * f["raise"].double * 20
            if f["quit"].bool { s -= c.wk * 0.8 }
            if !f["pr"].isNull { s -= c.wk * 0.3 }
            return s
        }
        var s = one(fx)
        if !fx["gamble"].isNull {
            let g = fx["gamble"]
            s += g["p"].double * one(g["ok"]) + (1 - g["p"].double) * one(g["bad"])
        }
        return s
    }

    // MARK: Answering and expiring

    /// The player answers a decision. Messages that carry an action (payroll, offers ...) are passed on to `actions`.
    @discardableResult
    public static func answer(_ s: inout GameState, messageID: Int, option idx: Int, data: GameData, context fc: FinanceContext,
                              actions: (inout GameState, Message, Int) -> Bool = { _, _, _ in true }) -> Bool {
        guard let k = s.inbox.firstIndex(where: { $0.id == messageID }), s.inbox[k].status == "open" else { return false }
        let m = s.inbox[k]
        guard m.options.indices.contains(idx) else { return false }
        if m.kind == "decision", let i = s.companyIndex(m.companyID) {
            let ctx = context(for: s.companies[i], data: data, employerFactor: fc.country(of: s.companies[i], s).employerCostFactor, costIndex: fc.country(of: s.companies[i], s).costIndex)
            let e = GameEvent(id: m.str("ev"), json: .object(["cat": .string(m.str("cat", "none"))]))
            apply(&s, companyIndex: i, m.options[idx]["fx"], ctx: ctx, event: e, data: data, context: fc)
        } else if !m.actionID.isEmpty {
            if !actions(&s, m, idx) { return false }
        }
        if let k2 = s.inbox.firstIndex(where: { $0.id == messageID }) {
            s.inbox[k2].set("status", "done"); s.inbox[k2].set("pick", idx); s.inbox[k2].isRead = true
        }
        return true
    }

    /// Unanswered decisions take the cheapest answer when time runs out. Original: `expireMsgs`.
    public static func expire(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        for k in s.inbox.indices {
            let m = s.inbox[k]
            guard m.status == "open", let exp = m.expiresWeek, s.week >= exp else { continue }
            let i = s.companyIndex(m.companyID)
            if m.kind == "decision" {
                guard let ci = i else { s.inbox[k].set("status", "done"); continue }
                var bestIndex = 0, best = -Double.infinity
                for (n, o) in m.options.enumerated() {
                    let v = -abs(o["fx"]["cash"].double)
                    if v > best { best = v; bestIndex = n }
                }
                let ctx = context(for: s.companies[ci], data: data, employerFactor: fc.country(of: s.companies[ci], s).employerCostFactor, costIndex: fc.country(of: s.companies[ci], s).costIndex)
                let e = GameEvent(id: m.str("ev"), json: .object(["cat": .string(m.str("cat", "none"))]))
                apply(&s, companyIndex: ci, m.options[bestIndex]["fx"], ctx: ctx, event: e, data: data, context: fc)
                s.inbox[k].set("status", "done"); s.inbox[k].set("pick", bestIndex); s.inbox[k].set("auto", 1)
                s.note("No answer in time on \"\(m.title)\". Default taken: \(m.options[bestIndex]["l"].string).", tone: "bad", companyID: m.companyID)
            } else if m.actionID == StrategicDecisions.action {
                let pick = StrategicDecisions.expired(&s, message: m, data: data, context: fc)
                s.inbox[k].set("status", "done"); s.inbox[k].set("pick", pick); s.inbox[k].set("auto", 1)
                s.note("No answer in time on \"\(m.title)\". Default taken: \(m.options.indices.contains(pick) ? m.options[pick]["l"].string : "").", tone: "bad", companyID: m.companyID)
            } else if m.actionID == Shareholders.action {
                Shareholders.expired(&s, message: m, data: data, context: fc)   // no answer = you refused
                s.inbox[k].set("status", "done"); s.inbox[k].set("pick", -1); s.inbox[k].set("auto", 1)
            } else if !m.actionID.isEmpty {
                s.inbox[k].set("status", "done"); s.inbox[k].set("pick", -1); s.inbox[k].set("auto", 1)
            }
        }
    }

    public static func openDecisionCount(_ s: GameState) -> Int { s.inbox.filter { $0.status == "open" }.count }
}
