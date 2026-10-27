import Foundation
import GameCore
import Countries
import Finance

/// What changing one of "how you sell" (a trade's knobs) costs and commits you to. Nothing here promises a gain: the
/// lines under `onPaper` are what the option's data says, and what customers do with it depends on the trade, the place,
/// competition and how well you deliver.
public struct KnobChangeQuote: Equatable, Sendable {
    public struct Doc: Equatable, Sendable {
        public var id: String
        public var name: String
        public var fee: Double
        public var weeks: Int
    }
    public var knobID: String
    public var optionName: String
    /// Weeks of reduced capacity while the business changes over (0 = none, e.g. an add-on or a business not open yet)
    public var transitionWeeks: Int
    /// Share of capacity lost during those weeks
    public var capacityLoss: Double
    /// One-off refit and retraining cost
    public var changeoverCost: Double
    /// Licences the new option needs that the company does not hold yet
    public var documents: [Doc]
    public var onPaper: [String]
    /// Why it cannot be done now (chain standard, franchise agreement, still changing over, nothing to change)
    public var blocked: String?
    public var cashShort: Bool
    /// What the change adds to the running costs each month (negative = saves). An estimate: the weekly overhead the turn charges
    /// (`CompanyCosts.fixedOverhead`, the "w" effect of the options, at today's prices) times 52/12. Zero for most options.
    public var monthlyRunningCost: Double = 0
    public var documentFees: Double { documents.reduce(0) { $0 + $1.fee } }
    public var totalCost: Double { changeoverCost + documentFees }
}

public enum KnobChangeOutcome: Equatable, Sendable {
    case done(KnobChangeQuote)
    case refused(String)
}

/// The one path for changing a knob while a company is open: changeover cost, a few weeks of lower capacity, the licences
/// the new option needs, and the rules of whoever governs the business (a chain's standard, a franchise agreement).
/// Effects on customers, prices, quality and costs still flow only through `Knobs.effect`; this adds a one-off payment and a
/// temporary capacity modifier, no second demand path. Original: `changeover`, `hysGo`, `hysTog` (features/sales/how_you_sell.js).
public enum KnobChange {
    public static let capacityDuringChangeover = 0.75

    /// Transition weeks from how far the method moves: price level (t), demand pull (d) and quality (q). Original: `changeover`.
    static func transitionWeeks(from old: KnobOption?, to new: KnobOption) -> (weeks: Int, qualityUp: Bool) {
        func f(_ o: KnobOption?, _ k: String, _ d: Double) -> Double { o?.effects[k] ?? d }
        let shift = abs(log(f(new, "t", 1) / f(old, "t", 1))) + abs(log(f(new, "d", 1) / f(old, "d", 1))) + abs(f(new, "q", 0) - f(old, "q", 0)) / 10
        let weeks = shift < 0.15 ? 1 : shift < 0.5 ? 2 : shift < 1 ? 3 : 4
        return (weeks, f(new, "q", 0) > f(old, "q", 0))
    }

    /// Who governs this knob for the company, if anyone: its chain's standard or its franchise agreement. Nil = the owner decides.
    /// A holding imposes nothing on its subsidiaries.
    public static func governedBy(_ s: GameState, _ co: Company, knob id: String) -> String? {
        if let ch = Chains.chain(s, of: co), !ch["rules"]["knob"][id].isNull {
            return "\(ch["name"].string) sets this for all its stores."
        }
        let f = co.value("franchise")
        if f["fran"].bool, !f["knobStd"][id].isNull {
            return "Your franchise agreement with \(f["brandName"].isNull ? "the franchisor" : f["brandName"].string) fixes this: the brand dictates how its units sell."
        }
        return nil
    }

    public static func currentValue(_ co: Company, _ k: Knob) -> Int {
        co.value("knob")[k.id].isNull ? k.defaultIndex : co.value("knob")[k.id].int
    }

    /// The running cost one option adds each month, from the same "w" effect `CompanyCosts.fixedOverhead` charges every week
    /// (at today's prices), times 52/12. An estimate: prices move with inflation.
    public static func monthlyRunningCost(_ s: GameState, _ data: GameData, option: KnobOption) -> Double {
        let weekly = (option.effects["w"] ?? 0) * World(state: s, data: data).inflationIndex
        return weekly * 52 / 12
    }

    /// The quote for setting the knob to `value` (an option index, or the bit mask of a multi-choice knob).
    /// `byChain`: the chain's own standard is being applied, so the chain's lock does not block it.
    public static func quote(_ s: GameState, _ data: GameData, companyID: Int, knob knobID: String, value: Int, byChain: Bool = false) -> KnobChangeQuote? {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type], let k = bd.knobs.first(where: { $0.id == knobID }) else { return nil }
        let co = s.companies[i]
        let valid = k.isMulti ? (value >= 0 && value < (1 << k.options.count)) : k.options.indices.contains(value)
        guard valid else { return nil }
        let w = World(state: s, data: data)
        let cur = w.currency(co)
        let old = currentValue(co, k)
        let isOpen = co.status == .open

        var q = KnobChangeQuote(knobID: knobID, optionName: "", transitionWeeks: 0, capacityLoss: 0, changeoverCost: 0, documents: [], onPaper: [], blocked: nil, cashShort: false)
        // The options that switch on, and what the change means on paper.
        var gained: [KnobOption] = []
        if k.isMulti {
            let added = value & ~old, removed = old & ~value
            gained = k.options.enumerated().filter { added & (1 << $0.offset) != 0 }.map { $0.element }
            let lost = k.options.enumerated().filter { removed & (1 << $0.offset) != 0 }.map { $0.element }
            q.optionName = (gained + lost).map { $0.name }.joined(separator: ", ")
            q.onPaper = lines(gained: gained, lost: lost)
            q.monthlyRunningCost = gained.reduce(0) { $0 + monthlyRunningCost(s, data, option: $1) } - lost.reduce(0) { $0 + monthlyRunningCost(s, data, option: $1) }
        } else {
            let oldO = k.options.indices.contains(old) ? k.options[old] : nil
            let newO = k.options[value]
            gained = [newO]
            q.optionName = newO.name
            q.onPaper = lines(gained: [newO], lost: oldO.map { [$0] } ?? [])
            q.monthlyRunningCost = monthlyRunningCost(s, data, option: newO) - (oldO.map { monthlyRunningCost(s, data, option: $0) } ?? 0)
            if isOpen && value != old {
                let t = transitionWeeks(from: oldO, to: newO)
                q.transitionWeeks = t.weeks
                q.capacityLoss = 1 - capacityDuringChangeover
                let base = max(cur.scaledPrice(8000), 0.6 * co.lastWeekRevenue)
                q.changeoverCost = cur.roundedStep(base * Double(t.weeks) * (t.qualityUp ? 1.4 : 1), about: 1000)
            }
        }
        // Licences the new option needs and the company does not hold.
        if isOpen {
            for o in gained {
                for id in o.requiredDocs where !q.documents.contains(where: { $0.id == id }) {
                    let st = co.value("docs")[id]["st"].string
                    guard st.isEmpty || st == "lapsed", !Documents.isSkipped(id, country: w.country(co)),
                          let dd = Documents.definition(id, country: w.country(co), tables: data.catalog.tables) else { continue }
                    q.documents.append(.init(id: id, name: dd.name, fee: Documents.cost(id, company: co, bd, w), weeks: Documents.waitWeeks(id, definition: dd, company: co, w)))
                }
            }
        }
        // Why not.
        if value == old { q.blocked = "That is already the way you sell." }
        else if !byChain, let why = governedBy(s, co, knob: knobID) { q.blocked = why }
        else if !k.isMulti, isOpen, !co.value("hys56c").isNull, co.value("hys56c")["k"].string == knobID, Double(s.week) < co.value("hys56c")["end"].double {
            q.blocked = "Still changing over: wait until week \(co.value("hys56c")["end"].int) before changing this again."
        }
        else if co.cash < q.totalCost { q.cashShort = true; q.blocked = "Not enough cash: this needs \(cur.short(q.totalCost))." }
        return q
    }

    /// What the option's data says it does. Not a forecast: real results depend on the trade, place, competition and delivery.
    static func lines(gained: [KnobOption], lost: [KnobOption]) -> [String] {
        func product(_ key: String) -> Double {
            gained.reduce(1) { $0 * ($1.effects[key] ?? 1) } / lost.reduce(1) { $0 * ($1.effects[key] ?? 1) }
        }
        func sum(_ key: String) -> Double { gained.reduce(0) { $0 + ($1.effects[key] ?? 0) } - lost.reduce(0) { $0 + ($1.effects[key] ?? 0) } }
        func pct(_ x: Double) -> String { String(format: "%+.0f%%", (x - 1) * 100) }
        var out: [String] = []
        let d = product("d"), t = product("t"), k = product("k"), q = sum("q"), c = sum("c"), w = sum("w")
        if abs(d - 1) >= 0.005 { out.append("Pull on customers: \(pct(d)) on paper") }
        if abs(t - 1) >= 0.005 { out.append("Average sale: \(pct(t)) on paper") }
        if abs(k - 1) >= 0.005 { out.append("Capacity: \(pct(k))") }
        if abs(q) >= 0.5 { out.append(String(format: "Quality: %+.0f points", q)) }
        if c > 0.0005 { out.append("Higher cost of sales") } else if c < -0.0005 { out.append("Lower cost of sales") }
        if w > 0 { out.append("Adds running costs every week") } else if w < 0 { out.append("Cuts running costs") }
        return out
    }

    /// Change the knob now. Pays the changeover and the licences, starts the transition weeks, writes the choice.
    /// All or nothing: a refusal leaves the state exactly as it was.
    public static func apply(_ s: inout GameState, _ data: GameData, companyID: Int, knob knobID: String, value: Int, byChain: Bool = false) -> KnobChangeOutcome {
        guard let q = quote(s, data, companyID: companyID, knob: knobID, value: value, byChain: byChain), let i = s.companyIndex(companyID) else { return .refused("not a choice of this business") }
        if let why = q.blocked { return .refused(why) }
        var t = s
        let name = q.optionName
        if q.changeoverCost > 0 { Payments.companyPays(&t, companyID: companyID, amount: q.changeoverCost, category: "oth", label: "Changeover to \(name)") }
        for d in q.documents {
            let r = Documents.apply(d.id, companyID: companyID, state: &t, data: data)
            if r != .ok && r != .alreadyHeld { return .refused(r == .notEnoughCash ? "Not enough cash for the licence." : "A licence for this could not be applied for.") }
        }
        var knobs = t.companies[i].value("knob")
        knobs[knobID] = .number(Double(value))
        t.companies[i].set("knob", knobs)
        if q.transitionWeeks > 0 {
            // The record counts down before the week is run, so one extra tick gives the full number of reduced weeks.
            PriceMoves.addModifier(&t, i, key: "cap", multiplier: capacityDuringChangeover, weeks: Double(q.transitionWeeks + 1))
            t.companies[i].set("hys56c", .object(["n": .number(Double(q.transitionWeeks)), "end": .number(Double(t.week + q.transitionWeeks)), "k": .string(knobID), "to": .string(name)]))
        }
        if t.companies[i].status == .open {
            t.note("\(t.companies[i].name) now sells by \(name)\(q.transitionWeeks > 0 ? ": \(q.transitionWeeks) week\(q.transitionWeeks == 1 ? "" : "s") of reduced capacity while it settles" : "").", tone: "n", companyID: companyID)
        }
        s = t
        return .done(q)
    }
}
