import Foundation
import GameCore
import Countries
import Finance
import Businesses

public struct PackEvent: Sendable {
    public let id: String
    public let area: String
    public let severity: Int
    public let weight: Double
    public let cooldown: Int
    public let body: String
    public let families: Set<String>
    public let trades: Set<String>
    public let excludedTrades: Set<String>
    public let countries: Set<String>
    public let weather: Set<String>
    public let months: Set<Int>
    public let needsStaff: Bool
    public let needsGoods: Bool
    public let needsBusinessCustomers: Bool
    public let needsPremises: Bool
    public let needsInvoices: Bool
    public let needsLoan: Bool
    public let countryWide: Bool
    public let event: GameEvent

    init(id: String, json e: JSONValue) {
        func set(_ k: String) -> Set<String> { Set(e[k].array.map { $0.string }) }
        self.id = id
        area = e["area"].string
        severity = max(1, min(3, e["sev"].int))
        weight = e["w"].double
        cooldown = max(1, e["cool"].int)
        body = e["b"].string
        families = set("fam")
        trades = set("tr")
        excludedTrades = set("notTr")
        countries = set("cc")
        weather = set("wx")
        months = Set(e["mo"].array.map { $0.string }.compactMap { Int($0) })
        needsStaff = e["staff"].bool
        needsGoods = e["goods"].bool
        needsBusinessCustomers = e["b2b"].bool
        needsPremises = e["prem"].bool
        needsInvoices = e["recv"].bool
        needsLoan = e["loan"].bool
        countryWide = e["macro"].bool
        var raw = e.object
        raw["auto"] = e["opts"].array.isEmpty ? .number(1) : .number(0)
        raw["minWeek"] = .number(0)
        event = GameEvent(id: id, json: .object(raw))
    }

    public var title: String { event.text }
    public var tone: String { event.tone }
    public var hasOptions: Bool { !event.options.isEmpty }
    public var minimumAgeWeeks: Int { severity >= 3 ? 40 : (severity == 2 ? 12 : 4) }
    public var maximumOutflowWeeks: Double { severity >= 3 ? 3.0 : (severity == 2 ? 1.5 : 0.6) }
}

public enum EventPack {
    public static let gapWeeks = 3

    public static let events: [PackEvent] = {
        guard let url = Bundle.module.url(forResource: "events_pack", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [] }
        return json["events"].object.sorted { $0.key < $1.key }.map { PackEvent(id: $0.key, json: $0.value) }
    }()

    public static let byID: [String: PackEvent] = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    public static func appliesTo(_ e: PackEvent, trade bd: Trade, country cc: String) -> Bool {
        if !e.families.isEmpty && !e.families.contains(bd.family) { return false }
        if !e.trades.isEmpty && !e.trades.contains(bd.id) { return false }
        if e.excludedTrades.contains(bd.id) { return false }
        if !e.countries.isEmpty && !e.countries.contains(cc) { return false }
        if e.needsGoods && bd.costOfSales <= 0.08 { return false }
        if e.needsBusinessCustomers && bd.businessShare <= 0.3 { return false }
        if e.needsPremises && bd.premisesKind == nil { return false }
        return true
    }

    static let weatherShare: [String: Double] = ["heat": 0.06, "cold": 0.07, "snow": 0.05, "rain": 0.25, "storm": 0.04, "sun": 0.25]

    public static func expectedPerYear(trade bd: Trade, country cc: String) -> Double {
        var total = 0.0
        for e in events where appliesTo(e, trade: bd, country: cc) {
            var p = e.weight
            if !e.weather.isEmpty { p *= e.weather.reduce(0) { $0 + (weatherShare[$1] ?? 0) } }
            var weeks = 52.0
            if !e.months.isEmpty { weeks = 52.0 * Double(e.months.count) / 12.0 }
            if e.needsInvoices || e.needsLoan { p *= 0.5 }
            total += min(p * weeks, 52.0 / Double(e.cooldown))
        }
        return total
    }

    static func amount(_ v: JSONValue, _ vars: [String: Double]) -> Double {
        if case .object(let o) = v, let e = o["expr"] { return Formula(e.string).evaluate(vars) }
        return v.double
    }

    static func outflow(_ fx: JSONValue, _ vars: [String: Double], worst: Bool) -> Double {
        if fx.isNull { return 0 }
        var out = max(0, -amount(fx["cash"], vars))
        for key in ["loss", "fine", "bonus"] { out += abs(amount(fx[key], vars)) }
        out += max(0, amount(fx["tied"]["a"], vars))
        let g = fx["gamble"]
        if !g.isNull {
            let ok = outflow(g["ok"], vars, worst: worst), bad = outflow(g["bad"], vars, worst: worst)
            let chance: Double = clamp(amount(g["p"], vars), 0, 1)
            out += worst ? max(ok, bad) : chance * ok + (1 - chance) * bad
        }
        return out
    }

    public static func expectedOutflowWeeksPerYear(trade bd: Trade, country cc: String) -> Double {
        let vars: [String: Double] = typicalSituation.merging(["wk": 1, "pay": 0.5, "eqv": 20, "k": 1]) { (_: Double, b: Double) -> Double in b }
        var total = 0.0
        for e in events where appliesTo(e, trade: bd, country: cc) && e.tone != "good" {
            var p = e.weight
            if !e.weather.isEmpty { p *= e.weather.reduce(0) { $0 + (weatherShare[$1] ?? 0) } }
            var weeks = 52.0
            if !e.months.isEmpty { weeks = 52.0 * Double(e.months.count) / 12.0 }
            if e.needsInvoices || e.needsLoan { p *= 0.5 }
            let n = min(p * weeks, 52.0 / Double(e.cooldown))
            let cost = e.hasOptions
                ? e.event.options.reduce(0.0) { $0 + outflow($1.effects, vars, worst: false) } / Double(e.event.options.count)
                : outflow(e.event.automaticEffects, vars, worst: false)
            total += n * cost
        }
        return total
    }

    /// A middling company, for reading odds that depend on the situation when no company is at hand.
    public static let typicalSituation: [String: Double] = ["co.eqc": 0.8, "co.q": 55, "co.mgrQ": 0.5, "co.payGap": 0, "co.books": 0.5, "co.rep": 50,
                                                            "co.mood": 60, "co.cashWk": 6, "co.util": 0.75, "co.staffN": 4]

    static func lastFired(_ co: Company, _ id: String) -> Int {
        let v = co.value("pkc")["ev"][id]
        return v.isNull ? Int.min / 2 : v.int
    }

    static func remember(_ s: inout GameState, _ i: Int, _ id: String) {
        var st = s.companies[i].value("pkc")
        var ev = st["ev"].object
        ev[id] = .number(Double(s.week))
        st["ev"] = .object(ev)
        st["last"] = .number(Double(s.week))
        s.companies[i].set("pkc", st)
    }

    static func extendedContext(_ s: GameState, _ co: Company, data: GameData, country: Country, currency: Currency) -> EventEngine.Context {
        var c = EventEngine.context(for: co, data: data, country: country)
        c.variables["k"] = currency.scaledPrice(1000) / 1000
        return c
    }

    static func spawn(_ s: inout GameState, companyIndex i: Int, data: GameData, context fc: FinanceContext) {
        let co = s.companies[i]
        guard co.status == .open, let opened = co.openedWeek, let bd = data.catalog[co.type] else { return }
        let last = co.value("pkc")["last"]
        if !last.isNull && s.week - last.int < gapWeeks { return }
        let age = s.week - opened
        let w = World(state: s, data: data)
        let country = w.country(co)
        let ramp = FairRules.eventRamp(data.balance, week: s.week)
        let risk = Knobs.effect(co, bd, "r", w)
        let month = GameCalendar.month(week: s.week) + 1
        let kind = Weather.draw(country: co.countryCode, week: s.week, seed: s.seed, tables: data.balance.weather).kind
        let solo = co.staff.isEmpty && co.managerID == nil
        let trading = co.lastWeekUnits > 0.5 && age >= 8
        let hasInvoices = !co.receivables.isEmpty
        let hasLoan = s.loans.contains { $0.companyID == co.id && $0.balance > 0 }
        let hasPremises = co.value("prem")["m2"].double > 0
        let cooling = co.value("flags")["evCool"].double > 0
        for e in events {
            if age < e.minimumAgeWeeks || !appliesTo(e, trade: bd, country: co.countryCode) { continue }
            if !e.weather.isEmpty && !e.weather.contains(kind) { continue }
            if !e.months.isEmpty && !e.months.contains(month) { continue }
            if e.needsStaff && co.staff.isEmpty { continue }
            if solo && EventEngine.mentionsStaff(e.event) { continue }
            if e.needsInvoices && !hasInvoices { continue }
            if e.needsLoan && !hasLoan { continue }
            if e.needsPremises && !hasPremises { continue }
            if e.tone == "good" && !trading { continue }
            if s.week - lastFired(co, e.id) < e.cooldown { continue }
            var p = e.weight
            if e.tone == "bad" { p *= ramp * risk }
            if !(p > 0) { continue }
            let key = e.countryWide ? co.countryCode : String(co.id)
            var h = HashedRandom("\(s.seed):evp:\(s.week):\(key):\(e.id)")
            if h.next() >= p { continue }
            if e.hasOptions && (cooling || !EventEngine.decisionRoom(s)) { continue }
            remember(&s, i, e.id)
            if e.hasOptions { EventEngine.setFlag(&s, i, "evCool", EventEngine.cooldownWeeks(s, companyID: co.id, event: e.event)) }
            fire(&s, companyIndex: i, e, data: data, context: fc)
            return
        }
    }

    static func bounded(_ fx: JSONValue, cap: Double) -> JSONValue {
        guard case .object(var o) = fx else { return fx }
        for key in ["cash", "loss", "fine", "bonus"] {
            if let v = o[key], case .number(let n) = v { o[key] = .number(max(-cap, min(cap, n))) }
        }
        if let v = o["close"], case .number(let n) = v { o["close"] = .number(min(2, n)) }
        if let g = o["gamble"], !g.isNull {
            o["gamble"] = .object(["p": g["p"], "ok": bounded(g["ok"], cap: cap), "bad": bounded(g["bad"], cap: cap)])
        }
        return .object(o)
    }

    static func hasLoss(_ fx: JSONValue) -> Bool {
        if fx.isNull { return false }
        return !fx["loss"].isNull || hasLoss(fx["gamble"]["ok"]) || hasLoss(fx["gamble"]["bad"])
    }

    static func coverLine(_ co: Company, _ e: PackEvent, currency: Currency) -> String {
        guard let name = EventEngine.insuranceNames[e.event.category] else { return "" }
        let risky = hasLoss(e.event.automaticEffects) || e.event.options.contains { hasLoss($0.effects) }
        if !risky { return "" }
        if co.value("ins")[e.event.category].bool {
            return "Your \(name) insurance covers most of a loss, after an excess of \(currency.display(currency.scaledPrice(10000)))."
        }
        return "You have no \(name) insurance, so a loss comes out of your account."
    }

    static func detail(_ text: String, _ fx: JSONValue, currency: Currency) -> String {
        let lines = EffectPreview.lines(fx, currency: currency)
        let tail = lines.isEmpty ? "" : lines.joined(separator: ". ") + "."
        if text.isEmpty { return tail }
        return tail.isEmpty ? text : text + " " + tail
    }

    static func mark(_ s: inout GameState, _ id: Int, _ e: PackEvent) {
        if let k = s.inbox.firstIndex(where: { $0.id == id }) {
            s.inbox[k].set("ev", e.id)
            s.inbox[k].set("cat", e.event.category)
            s.inbox[k].set("pk", 1)
        }
    }

    static func fire(_ s: inout GameState, companyIndex i: Int, _ e: PackEvent, data: GameData, context fc: FinanceContext) {
        let co = s.companies[i]
        let country = fc.country(of: co, s)
        let cur = Currency(country: country, rates: fc.rates(s))
        let ctx = extendedContext(s, co, data: data, country: country, currency: cur)
        let cap = ctx.wk * e.maximumOutflowWeeks
        func words(_ t: String) -> String { TextTokens.resolve(t.replacingOccurrences(of: "{n}", with: co.name), country: country, currency: cur) }
        let title = words(e.title)
        let story = words(e.body)
        let cover = coverLine(co, e, currency: cur)
        if !e.hasOptions {
            let fx = bounded(EventEngine.resolve(e.event.automaticEffects, ctx, currency: cur), cap: cap)
            EventEngine.apply(&s, companyIndex: i, fx, ctx: ctx, event: e.event, data: data, context: fc)
            var parts = [story]
            let lines = EffectPreview.lines(fx, currency: cur)
            if !lines.isEmpty { parts.append(lines.joined(separator: ". ") + ".") }
            if !cover.isEmpty { parts.append(cover) }
            let id = s.addMessage(from: co.name, title: title, body: parts.joined(separator: " "), companyID: co.id, tone: e.tone)
            mark(&s, id, e)
            s.note(title, tone: e.tone, companyID: co.id)
            return
        }
        let options: [JSONValue] = e.event.options.map { o in
            let fx = bounded(EventEngine.resolve(o.effects, ctx, currency: cur), cap: cap)
            return JSONValue.option(o.label, detail(o.detail, fx, currency: cur), effects: fx.object)
        }
        if EventEngine.decider(co, options: options, state: s, data: data) == .manager, let bdTrade = data.catalog[co.type] {
            let pick = EventEngine.choose(co, options: options, ctx: ctx, quality: ManagerModel.quality(co, bdTrade, people: s.people), random: &s.random)
            let who = s.people[co.managerID ?? 0]?.name ?? "The manager"
            let id = s.addMessage(from: co.name, title: title, body: "\(who) chose: \(options[pick]["l"].string).", companyID: co.id, tone: e.tone, options: options)
            if let k = s.inbox.firstIndex(where: { $0.id == id }) {
                s.inbox[k].set("status", "done"); s.inbox[k].set("pick", pick); s.inbox[k].set("mgrName", who)
            }
            mark(&s, id, e)
            EventEngine.apply(&s, companyIndex: i, options[pick]["fx"], ctx: ctx, event: e.event, data: data, context: fc)
            s.note("\(co.name): \(who) handled \"\(title)\" by choosing: \(options[pick]["l"].string).", tone: "n", companyID: co.id)
            return
        }
        var body = story
        if !cover.isEmpty { body += " " + cover }
        let weeks = max(1, e.event.expiresAfterWeeks)
        body += " Answer within \(weeks) week\(weeks == 1 ? "" : "s"), or the cheapest answer is taken."
        let id = s.addMessage(kind: "decision", from: co.name, title: title, body: body, companyID: co.id, tone: e.tone,
                              status: "open", options: options, expiresWeek: s.week + weeks)
        mark(&s, id, e)
    }
}
