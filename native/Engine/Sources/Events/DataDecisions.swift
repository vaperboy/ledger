import Foundation
import GameCore
import Countries
import Finance
import Businesses

public struct DecisionSpec: Sendable {
    public struct Choice: Sendable {
        public let label: String
        public let detail: String
        public let effects: JSONValue
    }
    public let id: String
    public let cls: String
    public let stages: [String]
    public let weight: Double
    public let tone: String
    public let expiryWeeks: Int
    public let defaultChoice: Int
    public let title: String
    public let body: String
    public let choices: [Choice]
    public let variables: [(name: String, expression: String)]
    public let category: String
    public let families: Set<String>
    public let trades: Set<String>
    public let excludedTrades: Set<String>
    public let countries: Set<String>
    public let months: Set<Int>
    public let needsGoods: Bool
    public let minBusinessShare: Double
    public let minStaff: Int
    public let managerRule: Bool?
    public let needsPremises: Bool
    public let needsEquipment: Bool
    public let minAgeWeeks: Int
    public let minWeeklyRevenue: Double
    public let minNetWorth: Double
    public let isTrap: Bool

    init(id: String, json e: JSONValue) {
        func set(_ k: String) -> Set<String> { Set(e[k].array.map { $0.string }) }
        self.id = id
        cls = e["cls"].string
        stages = e["stages"].array.map { $0.string }
        weight = e["w"].double
        tone = e["tone"].isNull ? "n" : e["tone"].string
        expiryWeeks = max(1, e["exp"].int)
        defaultChoice = e["def"].int
        title = e["t"].string
        body = e["b"].string
        choices = e["opts"].array.map { Choice(label: $0["l"].string, detail: $0["d"].string, effects: $0["fx"]) }
        variables = e["vars"].object.sorted { $0.key < $1.key }.map { (name: $0.key, expression: $0.value.string) }
        category = e["cat"].isNull ? "none" : e["cat"].string
        families = set("fam")
        trades = set("tr")
        excludedTrades = set("notTr")
        countries = set("cc")
        months = Set(e["mo"].array.map { $0.string }.compactMap { Int($0) })
        needsGoods = e["goods"].bool
        minBusinessShare = e["b2b"].double
        minStaff = e["staff"].int
        managerRule = e["mgr"].isNull ? nil : e["mgr"].bool
        needsPremises = e["prem"].bool
        needsEquipment = e["eq"].bool
        minAgeWeeks = e["minAge"].int
        minWeeklyRevenue = e["minWk"].double
        minNetWorth = e["minNW"].double
        isTrap = e["trap"].bool
    }
}

enum DataDecisions {
    static let specs: [DecisionSpec] = {
        guard let url = Bundle.module.url(forResource: "decisions", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [] }
        return json["decisions"].object.sorted { $0.key < $1.key }.map { DecisionSpec(id: $0.key, json: $0.value) }
    }()

    static let companyGapWeeks = 4

    static func currency(_ s: GameState, _ co: Company, data: GameData) -> Currency {
        Currency(country: World(state: s, data: data).country(co), rates: ExchangeRates(drift: s.exchangeRates.values))
    }

    static func context(_ s: GameState, _ co: Company, data: GameData, country: Country, currency cur: Currency, extra d: JSONValue) -> EventEngine.Context {
        var c = EventEngine.context(for: co, data: data, country: country)
        c.variables["k"] = cur.scaledPrice(1000) / 1000
        c.variables["staff"] = Double(co.staff.count)
        c.variables["yr"] = c.wk * 52
        for (key, v) in d.object { if case .number(let n) = v { c.variables[key] = n } }
        return c
    }

    static func applies(_ spec: DecisionSpec, _ s: GameState, _ co: Company, _ data: GameData) -> Bool {
        guard let bd = data.catalog[co.type] else { return false }
        if !spec.families.isEmpty && !spec.families.contains(bd.family) { return false }
        if !spec.trades.isEmpty && !spec.trades.contains(bd.id) { return false }
        if spec.excludedTrades.contains(bd.id) { return false }
        if !spec.countries.isEmpty && !spec.countries.contains(co.countryCode) { return false }
        if spec.needsGoods && bd.costOfSales <= 0.08 { return false }
        if spec.minBusinessShare > 0 && bd.businessShare <= spec.minBusinessShare { return false }
        if co.staff.count < spec.minStaff { return false }
        if let m = spec.managerRule, m != (co.managerID != nil) { return false }
        if spec.needsPremises && !(co.value("prem")["m2"].double > 0) { return false }
        if spec.needsEquipment && co.value("eq").object.isEmpty && co.value("veh").array.isEmpty { return false }
        if spec.minAgeWeeks > 0 && s.week - (co.openedWeek ?? co.foundedWeek) < spec.minAgeWeeks { return false }
        if !spec.months.isEmpty && !spec.months.contains(GameCalendar.month(week: s.week) + 1) { return false }
        if spec.minWeeklyRevenue > 0 {
            let cur = currency(s, co, data: data)
            let wk = EventEngine.context(for: co, data: data, country: World(state: s, data: data).country(co)).wk
            if wk < cur.scaledPrice(spec.minWeeklyRevenue) { return false }
        }
        if spec.minNetWorth > 0 {
            let cur = currency(s, co, data: data)
            if Valuation.netWorth(s, trades: data.catalog).total < cur.scaledPrice(spec.minNetWorth) { return false }
        }
        return true
    }

    static func text(_ t: String, _ co: Company, _ d: JSONValue, _ cur: Currency) -> String {
        var out = t.replacingOccurrences(of: "{n}", with: co.name)
        for (key, v) in d.object {
            guard case .number(let n) = v else { continue }
            out = out.replacingOccurrences(of: "{$\(key)}", with: cur.display(n))
            out = out.replacingOccurrences(of: "{\(key)}", with: String(Int(saturating: n.rounded())))
        }
        return out
    }

    static func outflow(_ fx: JSONValue) -> Double {
        var out = 0.0
        if fx["cash"].double < 0 { out += -fx["cash"].double }
        if !fx["tied"].isNull { out += fx["tied"]["a"].double }
        return out
    }

    static func definition(_ spec: DecisionSpec) -> StrategicDecisions.Def {
        let opts: [StrategicDecisions.Opt] = spec.choices.map { c in
            StrategicDecisions.Opt(label: c.label, detail: c.detail) { s, x in run(&s, x, fx: c.effects, category: spec.category, id: spec.id) }
        }
        return StrategicDecisions.Def(
            id: spec.id, cls: spec.cls, stages: spec.stages, w: spec.weight, tone: spec.tone, exp: spec.expiryWeeks, def: spec.defaultChoice,
            cond: { s, co, data in applies(spec, s, co, data) },
            make: { s, i, data, fc in
                let co = s.companies[i]
                let cur = fc.currency(co.countryCode, s)
                var d: JSONValue = .object([:])
                var c = context(s, co, data: data, country: fc.country(of: co, s), currency: cur, extra: .null)
                for v in spec.variables {
                    let n = cur.tidy(jsRound(Formula(v.expression).evaluate(c.variables)))
                    d[v.name] = .number(n)
                    c.variables[v.name] = n
                }
                return d
            },
            title: { co, d, cur in text(spec.title, co, d, cur) },
            body: { co, d, cur in text(spec.body, co, d, cur) },
            opts: opts,
            dyn: { s, i, d, data, fc in
                let co = s.companies[i]
                let cur = fc.currency(co.countryCode, s)
                let ctx = context(s, co, data: data, country: fc.country(of: co, s), currency: cur, extra: d)
                return spec.choices.map { c -> (String, String) in
                    let fx = EventEngine.resolve(c.effects, ctx, currency: cur)
                    var parts: [String] = []
                    let prose = text(c.detail, co, d, cur)
                    if !prose.isEmpty { parts.append(prose) }
                    let lines = EffectPreview.lines(fx, currency: cur)
                    if !lines.isEmpty { parts.append(lines.joined(separator: ". ") + ".") }
                    if outflow(fx) > max(0, co.cash) { parts.append("You do not have enough cash for this now.") }
                    return (c.label, parts.joined(separator: " "))
                }
            })
    }

    static func run(_ s: inout GameState, _ x: StrategicDecisions.X, fx: JSONValue, category: String, id: String) {
        let co = s.companies[x.i]
        let country = x.fc.country(of: co, s)
        let ctx = context(s, co, data: x.data, country: country, currency: x.cur, extra: x.d)
        let resolved = EventEngine.resolve(fx, ctx, currency: x.cur)
        if outflow(resolved) > max(0, co.cash) {
            s.note("You did not have the cash for it, so nothing was done.", tone: "n", companyID: co.id)
            return
        }
        let event = GameEvent(id: id, json: .object(["cat": .string(category)]))
        if !resolved["tied"].isNull {
            StrategicDecisions.tiedUp(&s, x, resolved["tied"]["a"].double, weeks: max(1, resolved["tied"]["w"].int))
        }
        for entry in resolved["later"].array {
            let payload: JSONValue = .object(["fx": entry["fx"], "note": entry["note"], "tone": entry["tone"]])
            StrategicDecisions.later(&s, max(1, entry["w"].int), "dfx", x.i, payload)
        }
        EventEngine.apply(&s, companyIndex: x.i, resolved, ctx: ctx, event: event, data: x.data, context: x.fc)
    }

    static func finish(_ s: inout GameState, _ x: StrategicDecisions.X) {
        let co = s.companies[x.i]
        let country = x.fc.country(of: co, s)
        let ctx = context(s, co, data: x.data, country: country, currency: x.cur, extra: .null)
        let resolved = x.d["fx"]
        if outflow(resolved) > max(0, co.cash) {
            s.note("\(co.name) could not pay a later instalment in full, so it was dropped.", tone: "bad", companyID: co.id)
            return
        }
        let event = GameEvent(id: "dfx", json: .object(["cat": .string("none")]))
        EventEngine.apply(&s, companyIndex: x.i, resolved, ctx: ctx, event: event, data: x.data, context: x.fc)
        let note = x.d["note"].string
        if note.isEmpty { return }
        let tone = x.d["tone"].isNull ? "n" : x.d["tone"].string
        let lines = EffectPreview.story(resolved, currency: x.cur, money: true)
        s.addMessage(from: co.name, title: note, body: lines.isEmpty ? "For your information. Nothing needs doing." : lines.joined(separator: " "), companyID: co.id, tone: tone)
        s.note(note, tone: tone, companyID: co.id)
    }
}

extension StrategicDecisions {
    static func dataDecisions() -> [Def] { DataDecisions.specs.map { DataDecisions.definition($0) } }

    public static func defaultOption(of message: Message) -> Int {
        byID[message.value("data")["id"].string]?.def ?? 0
    }

    static func companyBusy(_ s: GameState, _ co: Company) -> Bool {
        let last = (s.rest["e27"] ?? .null)["lastCo"][String(co.id)]
        if !last.isNull && s.week - last.int < DataDecisions.companyGapWeeks { return true }
        return s.inbox.contains { $0.status == "open" && $0.actionID == action && $0.value("data")["co"].int == co.id }
    }
}
