import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

public enum EventEngine {
    struct Context {
        var wk: Double
        var pay: Double
        var eqv: Double
        var variables: [String: Double]
    }

    static func context(for co: Company, data: GameData, country: Country) -> Context {
        let costIndex = country.costIndex
        let h = co.monthlyHistory.suffix(3)
        let wk: Double = !h.isEmpty ? max(h.reduce(0) { $0 + $1.revenue } / (Double(h.count) * 4.35), 1000 * costIndex)
                                    : (co.value("lastW").isNull ? 3000 * costIndex : max(co.lastWeekRevenue, 1000 * costIndex))
        let pay = Payroll.weeklyCost(co, country: country)
        let eqv = co.num("eqv") != 0 ? co.num("eqv") : (CompanyFigures.equipmentBookValue(co) != 0 ? CompanyFigures.equipmentBookValue(co) : 50000 * costIndex)
        let v: [String: Double] = ["wk": wk, "pay": pay, "eqv": eqv, "co.eqc": co.num("eqc", 1), "co.q": co.quality, "co.mgrQ": co.num("mgrQ"),
                                   "co.payGap": co.num("payGap"), "co.books": co.num("books", 0.5), "co.rep": co.reputation]
        return Context(wk: wk, pay: pay, eqv: eqv, variables: v.merging(situation(co, wk: wk)) { (a: Double, _: Double) -> Double in a })
    }

    /// The company's situation, so an answer's odds can depend on it: staff mood (0-100), weeks of sales held as cash, how full it runs, team size.
    static func situation(_ co: Company, wk: Double) -> [String: Double] {
        let mood: Double = co.value("mood").isNull ? 60 : co.num("mood")
        let cashWeeks: Double = clamp(co.cash / max(1, wk), -20, 52)
        let util: Double = co.value("lastW")["util"].isNull ? 0.7 : clamp(co.value("lastW")["util"].double, 0, 1.5)
        return ["co.mood": mood, "co.cashWk": cashWeeks, "co.util": util, "co.staffN": Double(co.staff.count)]
    }

    static let moneyKeys: Set<String> = ["cash", "fine", "loss", "bonus", "owner"]
    /// Odds between 0 and 1: a formula for them is kept as it is, not rounded like an amount.
    static let oddsKeys: Set<String> = ["p", "stay"]

    static func resolve(_ fx: JSONValue, _ ctx: Context, currency: Currency? = nil, key: String? = nil) -> JSONValue {
        switch fx {
        case .object(let o):
            if let e = o["expr"], o.count == 1 {
                let x: Double = Formula(e.string).evaluate(ctx.variables)
                return .number(key.map { oddsKeys.contains($0) } == true ? x : jsRound(x))
            }
            var out: [String: JSONValue] = [:]
            for (k, v) in o {
                if let cur = currency, moneyKeys.contains(k), case .number(let n) = v { out[k] = .number(cur.scaledPrice(n)) }
                else { out[k] = resolve(v, ctx, currency: currency, key: k) }
            }
            return .object(out)
        case .array(let a): return .array(a.map { resolve($0, ctx, currency: currency, key: key) })
        default: return fx
        }
    }

    public static func spawn(_ s: inout GameState, companyIndex i: Int, library: EventLibrary, data: GameData, context fc: FinanceContext) {
        guard let bd = data.catalog[s.companies[i].type] else { return }
        var cooldown = s.companies[i].value("flags")["evCool"].double
        if cooldown > 0 {
            cooldown -= 1
            setFlag(&s, i, "evCool", cooldown)
        }
        fireDeferred(&s, companyIndex: i, library: library, data: data, context: fc)
        let w = World(state: s, data: data)
        let risk = Knobs.effect(s.companies[i], bd, "r", w)
        let c = context(for: s.companies[i], data: data, country: w.country(s.companies[i]))
        for id in bd.eventIDs {
            let co = s.companies[i]
            guard let e = library[id], e.appliesTo(bd) else { continue }
            if e.minimumCompanyAgeWeeks > 0 && s.week - co.foundedWeek < e.minimumCompanyAgeWeeks { continue }
            if (e.tone == "good" || id == "g_press" || id == "g_offer") && !(co.lastWeekUnits > 0.5 && co.openedWeek != nil && s.week - co.openedWeek! >= goodEventMinimumWeeks(s, companyIndex: i)) { continue }
            if co.staff.isEmpty && mentionsStaff(e) { continue }
            if co.staff.isEmpty && co.managerID == nil && !soloAllowed(id, co) { continue }
            var p = e.weight * risk * 0.6 * (e.condition?.evaluate(c.variables) ?? 1)
            if e.tone == "bad" { p *= FairRules.eventRamp(data.balance, week: s.week) }
            if !(p > 0) { p = 0 }
            if p <= 0 || !s.random.chance(p) { continue }
            if Sourcing.shields(s, companyID: co.id, eventID: id) {
                if e.tone == "bad" {
                    Threat.survived(&s, companyID: co.id, text: "supplier trouble at \(co.name) never reached it: its own supply chain absorbed it.")
                    s.addMessage(from: co.name, title: "Supplier trouble did not reach \(co.name)", body: "Its own supply chain absorbed it. Nothing needs doing.", companyID: co.id, tone: "good")
                }
                continue
            }
            if !e.options.isEmpty && s.companies[i].value("flags")["evCool"].double > 0 { continue }
            if !e.options.isEmpty && !decisionRoom(s) { continue }
            if e.tone == "bad" && !takeBadSlot(&s, companyID: co.id, eventID: id) { continue }
            if !e.options.isEmpty { setFlag(&s, i, "evCool", cooldownWeeks(s, companyID: co.id, event: e)) }
            fire(&s, companyIndex: i, e, ctx: c, data: data, context: fc)
        }
        EventPack.spawn(&s, companyIndex: i, data: data, context: fc)
        SupplyNews.spawn(&s, companyIndex: i, data: data)
    }

    static func goodEventMinimumWeeks(_ s: GameState, companyIndex i: Int) -> Int {
        s.companies.prefix(i).isEmpty ? 12 : 6
    }

    static func cooldownWeeks(_ s: GameState, companyID: Int, event e: GameEvent) -> Double {
        var h = HashedRandom("\(s.seed):evcool:\(s.week):\(companyID):\(e.id)")
        let base: Double = e.tone == "good" ? 3 : (e.tone == "bad" ? 6 : 4)
        return base + Double(min(2, Int(h.next() * 3)))
    }

    static func takeBadSlot(_ s: inout GameState, companyID: Int, eventID: String) -> Bool {
        guard s.week <= FairRules.badEventCapWeeks else { return true }
        var st = s.rest["evBad"] ?? .object([:])
        if st["week"].int != s.week { st["week"] = .number(Double(s.week)); st["n"] = .number(0) }
        if st["n"].int >= 1 {
            var later = st["later"].array
            if !later.contains(where: { $0["c"].int == companyID && $0["e"].string == eventID }) {
                later.append(.object(["c": .number(Double(companyID)), "e": .string(eventID)]))
                st["later"] = .array(later)
            }
            s.rest["evBad"] = st
            return false
        }
        st["n"] = .number(1)
        s.rest["evBad"] = st
        return true
    }

    static func fireDeferred(_ s: inout GameState, companyIndex i: Int, library: EventLibrary, data: GameData, context fc: FinanceContext) {
        guard var st = s.rest["evBad"], !st["later"].array.isEmpty else { return }
        let id = s.companies[i].id
        guard let k = st["later"].array.firstIndex(where: { $0["c"].int == id }) else { return }
        let evID = st["later"].array[k]["e"].string
        guard let e = library[evID], s.companies[i].status == .open else {
            var l = st["later"].array; l.remove(at: k); st["later"] = .array(l); s.rest["evBad"] = st; return
        }
        if !takeBadSlot(&s, companyID: id, eventID: evID) { return }
        st = s.rest["evBad"] ?? st
        var l = st["later"].array; l.removeAll(where: { $0["c"].int == id && $0["e"].string == evID }); st["later"] = .array(l); s.rest["evBad"] = st
        let c = context(for: s.companies[i], data: data, country: World(state: s, data: data).country(s.companies[i]))
        fire(&s, companyIndex: i, e, ctx: c, data: data, context: fc)
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

    static let soloCustomerEvents: Set<String> = ["g_late", "g_review", "g_lawsuit", "g_offer", "c_scope", "c_clientloss", "c_damage", "c_wedding", "c_malprac", "c_patient",
                                                  "v_critic", "v_poison", "v_overbook", "v_injury", "v_churn", "v_bigwin", "v_cheat", "v_addict"]
    static let soloMarketingEvents: Set<String> = ["g_press", "g_award", "v_ota"]
    static let packTrades: Set<String> = ["cons", "tutor", "carclean", "photo", "handy", "cleaning", "webdev", "mktg", "law", "acctfirm", "staffing", "barber"]
    static func soloAllowed(_ id: String, _ co: Company) -> Bool {
        if soloCustomerEvents.contains(id) { return true }
        if soloMarketingEvents.contains(id) { return co.value("mkt").object.values.contains { $0["b"].double > 0 } }
        if let trade = id.split(separator: "_").first, id.contains("_"), packTrades.contains(String(trade)) { return true }
        return false
    }

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
        let optionsRunSpecial = e.options.contains { !$0.effects["special"].isNull }
        if !optionsRunSpecial {
            let topBefore: Int = s.inbox.first?.id ?? -1
            let notesBefore: Int = lastNote(s).count
            if SpecialEvents.handle(&s, companyIndex: i, e, ctx: ctx, data: data, context: fc) {
                ensureNotice(&s, company: co, topBefore: topBefore, notesBefore: notesBefore)
                return
            }
        }
        var title = e.text.replacingOccurrences(of: "{n}", with: co.name)
        let machine = pickEquipmentName(&s, companyIndex: i, data: data)
        title = title.replacingOccurrences(of: "{eq}", with: machine)
        title = TextTokens.resolve(title, country: fc.country(of: co, s), currency: cur)
        if e.id == "g_break", EquipmentWarranty.repairIfCovered(&s, companyIndex: i, itemName: machine, data: data) {
            Threat.survived(&s, companyID: co.id, text: "\(title) at \(co.name), covered by the warranty.")
            return
        }
        if e.automatic {
            let effects: JSONValue = resolve(e.automaticEffects, ctx, currency: cur)
            apply(&s, companyIndex: i, effects, ctx: ctx, event: e, data: data, context: fc)
            s.addMessage(from: co.name, title: title, body: summary(effects, currency: cur, tone: e.tone), companyID: co.id, tone: e.tone)
            s.note(title, tone: e.tone, companyID: co.id)
            return
        }
        if e.options.isEmpty {
            s.addMessage(from: co.name, title: title, body: plainLine(tone: e.tone), companyID: co.id, tone: e.tone)
            s.note(title, tone: e.tone, companyID: co.id)
            return
        }
        if e.lawyerHelps && co.value("law")["own"].bool { title += " Your law firm handles it, costs drop." }
        let options = e.options.map { JSONValue.option($0.label, $0.detail, effects: resolve($0.effects, ctx, currency: cur).object) }
        let decision = decider(co, options: options, state: s, data: data)
        if decision == .manager {
            let pick = choose(co, options: options, ctx: ctx, quality: ManagerModel.quality(co, bd(data, co), people: s.people), random: &s.random)
            let who = s.people[co.managerID ?? 0]?.name ?? "The manager"
            // The manager answered: one line for the day and the report, no message.
            s.feedLine("\(title) \(who) chose: \(options[pick]["l"].string).", tone: e.tone, companyID: co.id)
            apply(&s, companyIndex: i, options[pick]["fx"], ctx: ctx, event: e, data: data, context: fc)
            if e.tone == "bad" { Threat.survived(&s, companyID: co.id, text: "\"\(title)\" at \(co.name). \(who) handled it: \(options[pick]["l"].string).") }
            else { s.note("\(co.name): \(who) handled \"\(title)\" by choosing: \(options[pick]["l"].string).", tone: "n", companyID: co.id) }
        } else {
            var shown = options
            if let extra = lateGameOption(e, options: options, ctx: ctx, company: co, state: s) { shown.append(extra) }
            let id = s.addMessage(kind: "decision", from: co.name, title: title, body: decisionBody(co, e, currency: cur), companyID: co.id, tone: e.tone,
                                  status: "open", options: shown, expiresWeek: s.week + e.expiresAfterWeeks)
            if let k = s.inbox.firstIndex(where: { $0.id == id }) {
                s.inbox[k].set("ev", e.id)
                s.inbox[k].set("cat", e.category)
            }
        }
    }

    static func bd(_ data: GameData, _ co: Company) -> Trade { data.catalog[co.type]! }

    static let decisionCap = 12

    static func decisionRoom(_ s: GameState) -> Bool {
        let waiting: Int = s.inbox.filter { (m: Message) -> Bool in m.status == "open" && m.kind == "decision" }.count
        let companies: Int = s.companies.filter { (c: Company) -> Bool in c.status == .open }.count
        return waiting < min(decisionCap, 4 + companies)
    }

    static func plainLine(tone: String) -> String {
        switch tone {
        case "good": return "Good news. Nothing needs doing."
        case "bad": return "Nothing needs deciding. It is in this week's report."
        default: return "For your information. Nothing needs doing."
        }
    }

    static func summary(_ fx: JSONValue, currency: Currency, tone: String) -> String {
        let lines: [String] = EffectPreview.lines(fx, currency: currency)
        return lines.isEmpty ? plainLine(tone: tone) : lines.joined(separator: ". ") + "."
    }

    static let insuranceNames: [String: String] = ["prop": "property", "liab": "liability", "prof": "professional", "cyber": "cyber", "bi": "business-interruption"]

    static func insuranceLine(_ co: Company, _ e: GameEvent, currency: Currency) -> String {
        guard let name = insuranceNames[e.category] else { return "" }
        func risks(_ fx: JSONValue) -> Bool {
            if fx.isNull { return false }
            return fx["loss"].double != 0 || (e.category == "bi" && fx["close"].double != 0) || risks(fx["gamble"]["ok"]) || risks(fx["gamble"]["bad"])
        }
        guard e.options.contains(where: { (o: GameEvent.Option) -> Bool in risks(o.effects) }) else { return "" }
        if co.value("ins")[e.category].bool {
            return "Your \(name) insurance covers most of a loss, after an excess of \(currency.display(currency.scaledPrice(10000)))."
        }
        return "You have no \(name) insurance, so a loss comes out of your account. Cover is switched on in Atlas Insurance."
    }

    static func decisionBody(_ co: Company, _ e: GameEvent, currency: Currency) -> String {
        var parts: [String] = []
        let line: String = insuranceLine(co, e, currency: currency)
        if !line.isEmpty { parts.append(line) }
        let weeks: Int = max(1, e.expiresAfterWeeks)
        parts.append("Answer within \(weeks) week\(weeks == 1 ? "" : "s"), or the cheapest answer is taken.")
        return parts.joined(separator: " ")
    }

    static func lastNote(_ s: GameState) -> (count: Int, text: String, tone: String) {
        let lines: [JSONValue] = s.rest["rep"]?["ev"].array ?? []
        return (lines.count, lines.last?["t"].string ?? "", lines.last?["tone"].string ?? "n")
    }

    static func ensureNotice(_ s: inout GameState, company co: Company, topBefore: Int, notesBefore: Int) {
        if (s.inbox.first?.id ?? -1) != topBefore { return }
        let now = lastNote(s)
        guard now.count > notesBefore, !now.text.isEmpty else { return }
        s.addMessage(from: co.name, title: now.text, body: plainLine(tone: now.tone), companyID: co.id, tone: now.tone)
    }

    enum Decider { case owner, manager }

    static func decider(_ co: Company, options: [JSONValue], state s: GameState, data: GameData) -> Decider {
        guard co.managerID != nil, s.people[co.managerID!] != nil else { return .owner }
        let cost = options.map { max(abs($0["fx"]["cash"].double), abs($0["fx"]["loss"].double), $0["fx"]["fine"].double) }.max() ?? 0
        let big = s.rest["group"]?["big"].double ?? 5_000_000
        if cost > big { return .owner }
        return ManagerModel.withinBudget(co, amount: cost, s, data: data) ? .manager : .owner
    }

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

    @discardableResult
    public static func answer(_ s: inout GameState, messageID: Int, option idx: Int, data: GameData, context fc: FinanceContext,
                              actions: (inout GameState, Message, Int) -> Bool = { _, _, _ in true }) -> Bool {
        guard let k = s.inbox.firstIndex(where: { $0.id == messageID }), s.inbox[k].status == "open" else { return false }
        let m = s.inbox[k]
        guard m.options.indices.contains(idx) else { return false }
        if m.kind == "decision", let i = s.companyIndex(m.companyID) {
            let ctx = context(for: s.companies[i], data: data, country: fc.country(of: s.companies[i], s))
            let e = GameEvent(id: m.str("ev"), json: .object(["cat": .string(m.str("cat", "none"))]))
            applyAnswer(&s, companyIndex: i, message: m, option: idx, ctx: ctx, event: e, data: data, context: fc)
        } else if !m.actionID.isEmpty {
            if !actions(&s, m, idx) { return false }
        }
        if let k2 = s.inbox.firstIndex(where: { $0.id == messageID }) {
            s.inbox[k2].set("status", "done"); s.inbox[k2].set("pick", idx); s.inbox[k2].isRead = true
        }
        return true
    }

    public static func expire(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        for due in s.inbox.filter({ $0.status == "open" && $0.expiresWeek.map { s.week >= $0 } == true }).map({ $0.id }) {
            guard var k = s.inbox.firstIndex(where: { $0.id == due }) else { continue }
            let m = s.inbox[k]
            let i = s.companyIndex(m.companyID)
            if m.kind == "decision" {
                guard let ci = i else { s.inbox[k].set("status", "done"); continue }
                var bestIndex = 0, best = -Double.infinity
                for (n, o) in m.options.enumerated() where o["fx"]["tier"].isNull {
                    let v = -abs(o["fx"]["cash"].double)
                    if v > best { best = v; bestIndex = n }
                }
                let ctx = context(for: s.companies[ci], data: data, country: fc.country(of: s.companies[ci], s))
                let e = GameEvent(id: m.str("ev"), json: .object(["cat": .string(m.str("cat", "none"))]))
                apply(&s, companyIndex: ci, m.options[bestIndex]["fx"], ctx: ctx, event: e, data: data, context: fc)
                if let k2 = s.inbox.firstIndex(where: { $0.id == due }) { k = k2 }
                s.inbox[k].set("status", "done"); s.inbox[k].set("pick", bestIndex); s.inbox[k].set("auto", 1)
                s.note("No answer in time on \"\(m.title)\". Default taken: \(m.options[bestIndex]["l"].string).", tone: "bad", companyID: m.companyID)
            } else if m.actionID == StrategicDecisions.action {
                let pick = StrategicDecisions.expired(&s, message: m, data: data, context: fc)
                if let k2 = s.inbox.firstIndex(where: { $0.id == due }) { k = k2 }
                s.inbox[k].set("status", "done"); s.inbox[k].set("pick", pick); s.inbox[k].set("auto", 1)
                s.note("No answer in time on \"\(m.title)\". Default taken: \(m.options.indices.contains(pick) ? m.options[pick]["l"].string : "").", tone: "bad", companyID: m.companyID)
            } else if m.actionID == Shareholders.action {
                Shareholders.expired(&s, message: m, data: data, context: fc)
                if let k2 = s.inbox.firstIndex(where: { $0.id == due }) { k = k2 }
                s.inbox[k].set("status", "done"); s.inbox[k].set("pick", -1); s.inbox[k].set("auto", 1)
            } else if !m.actionID.isEmpty {
                s.inbox[k].set("status", "done"); s.inbox[k].set("pick", -1); s.inbox[k].set("auto", 1)
            }
        }
    }

    public static func openDecisionCount(_ s: GameState) -> Int { s.inbox.filter { $0.status == "open" }.count }
}
