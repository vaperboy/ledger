import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// The 'strategic' decisions of the original (round 27e, features/world/business_events.js): about one a quarter for a small
/// business, rare big opportunities, crises weighted by debt, corporate events for groups, and events that belong to one
/// country. They sit beside the data-driven weekly events of `EventEngine` and use the same inbox, deadlines and defaults.
/// A decision is an inbox message with action "e27"; its answers run code here, because their effects depend on the company.
///
/// The 13 that need rivals, listings, private equity, groups or new sites (s_acqoffer, g_location, g_franinq, e_merger, e_distress, t_ipo, t_pe,
/// t_hostile, t_antitrust, t_activist, t_auction, c_JP_succ, c_US_vc) are in `StrategicDecisionsCorporate.swift`. They work on the rivals and groups
/// in `rest["mk"]` and `rest["g27"]` (the Competition port's data), so those that need a rival or a group wait for them.
public enum StrategicDecisions {
    public static let action = "e27"

    /// What an answer can use. `i` is the company's index, `d` the numbers drawn when the decision was made.
    struct X {
        var i: Int
        var d: JSONValue
        let data: GameData
        let fc: FinanceContext
        let cur: Currency
        func wk(_ s: GameState) -> Double {
            let c = s.companies[i], k = fc.country(of: c, s)
            return EventEngine.context(for: c, data: data, country: k).wk
        }
        func yr(_ s: GameState) -> Double { wk(s) * 52 }
        func payroll(_ s: GameState) -> Double { s.companies[i].staff.reduce(0) { $0 + $1.monthlyWage } }
        func kc(_ v: Double) -> Double { cur.scaledPrice(v) }
    }
    typealias Run = (inout GameState, X) -> Void
    typealias Txt = (Company, JSONValue, Currency) -> String
    struct Opt { let label: String; let detail: String; let run: Run }
    struct Def {
        let id: String
        let cls: String
        var stages: [String] = []
        var cc: String? = nil
        var w: Double = 2
        var tone = "n"
        var from: String? = nil
        var exp = 3
        var def = 0
        /// Not about one company (the credit rating, inflation); the first live company only lends its currency.
        var global = false
        var cond: (GameState, Company, GameData) -> Bool = { _, _, _ in true }
        /// Numbers drawn when the event fires; nil = it does not apply right now.
        var make: ((inout GameState, Int, GameData, FinanceContext) -> JSONValue?)? = nil
        var pre: Run? = nil
        /// The event happens at once and sends no message (the original's `handle`): `make` does the work.
        var silent = false
        let title: Txt
        var body: Txt = { _, _, _ in "" }
        var opts: [Opt] = []
        var auto: Run? = nil
    }

    // MARK: Helpers

    static func r1000(_ v: Double) -> Double { (v / 1000).rounded() * 1000 }
    static func num(_ n: Double) -> JSONValue { .number(n) }
    static func addMod(_ s: inout GameState, _ i: Int, _ k: String, _ m: Double, _ w: Double) { EventEngine.addModifier(&s, i, key: k, multiplier: m, weeks: w) }
    static func dem(_ s: inout GameState, _ x: X, _ m: Double, _ w: Double) { addMod(&s, x.i, "dem", m, w) }
    static func cap(_ s: inout GameState, _ x: X, _ m: Double, _ w: Double) { addMod(&s, x.i, "cap", m, w) }
    static func cost(_ s: inout GameState, _ x: X, _ m: Double, _ w: Double) { addMod(&s, x.i, "cogsup", m, w) }
    static func rep(_ s: inout GameState, _ x: X, _ d: Double) { s.companies[x.i].reputation = clamp(s.companies[x.i].reputation + d, 0, 100) }
    static func pay(_ s: inout GameState, _ x: X, _ amount: Double, _ category: String?, _ label: String) {
        let a = jsRound(max(0, amount))
        if a > 0 { _ = Payments.companyPays(&s, companyID: s.companies[x.i].id, amount: a, category: category, label: label) }
    }
    static func mood(_ s: inout GameState, _ i: Int, _ d: Double) {
        let m = s.companies[i].value("mood").isNull ? 60 : s.companies[i].num("mood")
        s.companies[i].set("mood", clamp(m + d, 0, 100))
    }
    static func raiseAll(_ s: inout GameState, _ i: Int, _ f: Double) {
        var st = s.companies[i].staff
        for k in st.indices { st[k].monthlyWage = jsRound(st[k].monthlyWage * f) }
        s.companies[i].staff = st
    }
    static func removeStaff(_ s: inout GameState, _ i: Int, id: Int) {
        s.companies[i].staff = s.companies[i].staff.filter { $0.id != id }
        if var p = s.people[id] { p.employerID = 0; s.people[id] = p }
    }
    static func bestPaid(_ s: GameState, _ i: Int, _ n: Int) -> [StaffMember] {
        Array(s.companies[i].staff.sorted { $0.monthlyWage > $1.monthlyWage }.prefix(n))
    }
    static func trade(_ x: X, _ s: GameState) -> Trade? { x.data.catalog[s.companies[x.i].type] }
    static func ebit12(_ co: Company, _ s: GameState) -> Double { CompanyFigures.yearlyProfitEstimate(co, currentWeek: s.week) }
    static func value(_ co: Company, _ s: GameState, _ data: GameData) -> Double { Valuation.companyValue(co, state: s, trades: data.catalog) }
    static func hasGoods(_ bd: Trade) -> Bool { bd.costOfSales > 0.08 }

    /// Company stage: start (young or tiny), grow, est (established). Original: `stage`.
    static func stage(_ s: GameState, _ co: Company, _ data: GameData, _ fc: FinanceContext) -> String {
        let n = co.staff.count, age = s.week - (co.openedWeek ?? co.foundedWeek)
        if age < 52 || (n <= 3 && co.managerID == nil) { return "start" }
        let k = fc.country(of: co, s)
        let wk = EventEngine.context(for: co, data: data, country: k).wk
        if n > 15 || (co.managerID != nil && wk * 52 > fc.currency(co.countryCode, s).scaledPrice(20e6)) { return "est" }
        return "grow"
    }

    // MARK: The decisions

    static let definitions: [Def] = build()
    static let byID: [String: Def] = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })

    static func build() -> [Def] {
        var L: [Def] = []

        // Startup stage
        L.append(Def(id: "s_bigcust", cls: "strat", stages: ["start", "grow"], w: 3, def: 2,
                     cond: { s, co, data in (data.catalog[co.type]?.businessShare ?? 0) > 0.15 && co.value("lastW")["util"].double < 0.85 },
                     make: { s, i, data, fc in
                         let k = fc.country(of: s.companies[i], s)
                         let wk = EventEngine.context(for: s.companies[i], data: data, country: k).wk
                         return .object(["v": num(r1000(wk * 52 * 0.3))]) },
                     title: { co, _, _ in "A big customer wants a contract with \(co.name)" },
                     body: { _, d, cur in "A large customer offers work worth about \(cur.display(d["v"].double)) a year, about 30% of what you sell today. They want 10% off and 60 days to pay." },
                     opts: [
                        Opt(label: "Accept their terms", detail: "More volume, thinner margin, and cash tied up waiting for them to pay.") { s, x in
                            dem(&s, x, 1.3, 52); cost(&s, x, 1.035, 52); tiedUp(&s, x, x.d["v"].double / 6, weeks: 9)
                            s.note("\(s.companies[x.i].name) signed the contract. The first invoices are paid in two months.", tone: "good", companyID: s.companies[x.i].id) },
                        Opt(label: "Negotiate: 5% off and 30 days", detail: "They might accept, or go elsewhere.") { s, x in
                            if s.random.chance(0.55) { dem(&s, x, 1.3, 52); cost(&s, x, 1.017, 52); tiedUp(&s, x, x.d["v"].double / 12, weeks: 5); s.note("They agreed: 5% off, 30 days.", tone: "good", companyID: s.companies[x.i].id) }
                            else { s.note("They signed with someone else.", tone: "bad", companyID: s.companies[x.i].id) } },
                        Opt(label: "Decline, stay with smaller customers", detail: "No risk of depending on one buyer.") { _, _ in }]))
        L.append(Def(id: "s_breakdown", cls: "strat", stages: ["start", "grow", "est"], w: 3, def: 2,
                     cond: { _, co, _ in !co.value("eq").object.isEmpty },
                     make: { s, i, data, fc in
                         let k = fc.country(of: s.companies[i], s)
                         let wk = EventEngine.context(for: s.companies[i], data: data, country: k).wk
                         return .object(["c": num(jsRound(max(fc.currency(s.companies[i].countryCode, s).scaledPrice(8000), wk * 0.15))), "eq": .string(EventEngine.pickEquipmentName(&s, companyIndex: i, data: data))]) },
                     title: { co, _, _ in "Essential equipment breaks down at \(co.name)" },
                     body: { _, d, cur in "The \(d["eq"].string) is out. A fast repair costs about \(cur.display(d["c"].double * 1.6)); the normal one about \(cur.display(d["c"].double)) but takes two weeks." },
                     opts: [
                        Opt(label: "Repair now, at a premium", detail: "Back in a day or two.") { s, x in pay(&s, x, x.d["c"].double * 1.6, "oth", "Emergency repair"); cap(&s, x, 0.9, 1) },
                        Opt(label: "Rent a replacement", detail: "Keeps you going while the normal repair is done.") { s, x in
                            pay(&s, x, x.d["c"].double * 0.5 + x.wk(s) * 0.04, "oth", "Rented equipment"); pay(&s, x, x.d["c"].double, "oth", "Repair"); cap(&s, x, 0.95, 2) },
                        Opt(label: "Wait for the cheaper repair", detail: "Lost sales for two weeks, and some customers may not come back.") { s, x in
                            pay(&s, x, x.d["c"].double, "oth", "Repair"); cap(&s, x, 0.55, 2); rep(&s, x, -1) }]))
        L.append(Def(id: "s_burnout", cls: "strat", stages: ["start", "grow"], w: 3, def: 2,
                     cond: { _, co, _ in co.managerID == nil && co.ownerHours >= 50 },
                     title: { co, _, _ in "You are running on empty at \(co.name)" },
                     body: { co, _, _ in "\(Int(co.ownerHours))-hour weeks are catching up with you. Mistakes are creeping in and customers wait longer." },
                     opts: [
                        Opt(label: "Hire part-time help", detail: "Half a worker's pay for 20 hours a week. Opens Find workers.") { s, x in
                            s.companies[x.i].ownerHours = min(s.companies[x.i].ownerHours, 45); rep(&s, x, 1) },
                        Opt(label: "Cut opening hours", detail: "Fewer hours, less money, but you get your life back.") { s, x in s.companies[x.i].ownerHours = 40; dem(&s, x, 0.93, 26) },
                        Opt(label: "Keep going", detail: "No cost now. Slower service, more mistakes.") { s, x in
                            cap(&s, x, 0.9, 8); rep(&s, x, -2); s.companies[x.i].ownerSkill = max(0, s.companies[x.i].ownerSkill - 1) }]))
        L.append(Def(id: "s_quit", cls: "strat", stages: ["start", "grow"], w: 2, def: 2,
                     cond: { _, co, _ in co.staff.count >= 2 },
                     make: { s, i, _, _ in
                         guard let m = bestPaid(s, i, 1).first, let p = s.people[m.id] else { return nil }
                         return .object(["s": num(Double(m.id)), "n": .string(p.name), "r": .string(m.role)]) },
                     title: { co, d, _ in "\(d["n"].string) is leaving \(co.name) for a competitor" },
                     body: { _, d, _ in "\(d["n"].string), your best \(d["r"].string.lowercased()), has an offer elsewhere and leaves in two weeks." },
                     opts: [
                        Opt(label: "Recruit a replacement", detail: "An agency finds someone in a few weeks.") { s, x in
                            pay(&s, x, x.kc(12000), "oth", "Recruiting"); removeStaff(&s, x.i, id: x.d["s"].int); cap(&s, x, 0.92, 3) },
                        Opt(label: "Promote someone from the team", detail: "A raise for them, and one person short.") { s, x in
                            removeStaff(&s, x.i, id: x.d["s"].int)
                            if !s.companies[x.i].staff.isEmpty { var st = s.companies[x.i].staff; st[0].monthlyWage = jsRound(st[0].monthlyWage * 1.1); s.companies[x.i].staff = st }
                            cap(&s, x, 0.9, 6) },
                        Opt(label: "Run short-handed", detail: "Saves the wage. Slower and more tired staff.") { s, x in removeStaff(&s, x.i, id: x.d["s"].int); mood(&s, x.i, -5) }]))
        L.append(Def(id: "s_supprice", cls: "strat", stages: ["start", "grow", "est"], w: 3, def: 3,
                     cond: { _, co, data in data.catalog[co.type].map(hasGoods) ?? false },
                     title: { co, _, _ in "The main supplier of \(co.name) raises prices 12%" },
                     body: { _, _, _ in "Goods cost 12% more from next month. How much your customers will put up with depends on your prices and theirs." },
                     opts: [
                        Opt(label: "Negotiate", detail: "You might get it down to 4%. Or not.") { s, x in cost(&s, x, s.random.chance(0.5) ? 1.04 : 1.12, 26) },
                        Opt(label: "Find another supplier", detail: "A week of disruption while you switch.") { s, x in cap(&s, x, 0.9, 1); cost(&s, x, 1.02, 26) },
                        Opt(label: "Raise your prices", detail: "Keep the margin, lose some price-sensitive customers.") { s, x in
                            cost(&s, x, 1.12, 26); dem(&s, x, 0.95, 26); s.companies[x.i].priceLevel = clamp(s.companies[x.i].priceLevel + 0.5, -3, 3) },
                        Opt(label: "Accept the lower margin", detail: "") { s, x in cost(&s, x, 1.12, 26) }]))
        L.append(Def(id: "s_campaign", cls: "strat", stages: ["start", "grow"], w: 2, def: 1,
                     cond: { _, co, _ in co.value("mkt").object.values.contains { $0["b"].double > 0 } },
                     title: { co, _, _ in "A campaign is working for \(co.name)" },
                     body: { _, _, _ in "Early numbers look good: new customers are coming in at a reasonable cost. Whether it pays depends on how long they stay." },
                     opts: [
                        Opt(label: "Double the budget", detail: "More customers now, but returns usually fall as you spend more.") { s, x in
                            var m = s.companies[x.i].value("mkt")
                            for (k, v) in m.object where v["b"].double > 0 { m[k]["b"] = num(jsRound(v["b"].double * 2)) }
                            s.companies[x.i].set("mkt", m) },
                        Opt(label: "Keep it as it is", detail: "") { _, _ in },
                        Opt(label: "Stop while it is ahead", detail: "Saves the money. The effect fades over a few months.") { s, x in
                            var m = s.companies[x.i].value("mkt")
                            for (k, v) in m.object where v["b"].double > 0 { m[k]["b"] = num(0) }
                            s.companies[x.i].set("mkt", m) }]))
        L.append(Def(id: "s_latepay", cls: "strat", stages: ["start", "grow"], w: 2, def: 2,
                     cond: { _, co, data in (data.catalog[co.type]?.businessShare ?? 0) > 0.25 && !co.receivables.isEmpty },
                     make: { s, i, _, _ in
                         guard let r = s.companies[i].receivables.max(by: { $0.amount < $1.amount }) else { return nil }
                         return .object(["a": num(r.amount)]) },
                     title: { co, _, _ in "A customer of \(co.name) has not paid" },
                     body: { _, d, cur in "An invoice of \(cur.display(d["a"].double)) is past due. The customer says it is coming." },
                     opts: [
                        Opt(label: "Send a reminder and a fee", detail: "Most pay within weeks.") { s, x in
                            pay(&s, x, x.kc(800), "oth", "Collection"); let bad = s.random.chance(0.08); chaseInvoice(&s, x, due: 3, bad: bad) },
                        Opt(label: "Agree a payment plan", detail: "You get it, slowly.") { s, x in let bad = s.random.chance(0.04); chaseInvoice(&s, x, due: 10, bad: bad) },
                        Opt(label: "Wait", detail: "Free, but they may never pay.") { s, x in let bad = s.random.chance(0.25); chaseInvoice(&s, x, due: 6, bad: bad, keepBad: true) }]))

        // Growth stage
        L.append(Def(id: "g_overcap", cls: "strat", stages: ["grow", "est"], w: 3, def: 3,
                     cond: { _, co, _ in let w = co.value("lastW"); return w["cap"].double > 0 && w["D"].double > w["cap"].double * 1.12 },
                     title: { co, _, _ in "More orders than \(co.name) can handle" },
                     body: { co, _, _ in let w = co.value("lastW"); return "Demand runs about \(Int(((w["D"].double / max(1, w["cap"].double)) - 1) * 100))% above what you can deliver. Growing costs money before the extra sales are certain." },
                     opts: [
                        Opt(label: "Add an evening shift", detail: "Overtime pay for two months, more output now.") { s, x in cap(&s, x, 1.15, 8); pay(&s, x, x.payroll(s) * 0.25 * 2, "wages", "Overtime") },
                        Opt(label: "Hire more people", detail: "Go to Find workers. Permanent cost, permanent capacity.") { _, _ in },
                        Opt(label: "Outsource part of the work", detail: "More output at a higher cost per unit.") { s, x in cap(&s, x, 1.2, 12); cost(&s, x, 1.08, 12) },
                        Opt(label: "Turn customers away", detail: "No cost. Some will not come back, and reviews suffer a little.") { s, x in rep(&s, x, -1) }]))
        L.append(Def(id: "g_mgrraise", cls: "strat", stages: ["grow", "est"], w: 3, def: 2,
                     cond: { s, co, _ in co.managerID != nil && s.people[co.managerID!] != nil && s.week - co.foundedWeek > 40 },
                     make: { s, i, _, _ in
                         guard let id = s.companies[i].managerID, let p = s.people[id] else { return nil }
                         return .object(["n": .string(p.name), "w": num(s.companies[i].managerMonthlyWage)]) },
                     title: { _, d, _ in "\(d["n"].string) asks for a raise" },
                     body: { co, d, cur in "\(d["n"].string), who runs \(co.name), wants 12% more: \(cur.display(d["w"].double * 1.12)) a month. Good managers are hard to find." },
                     opts: [
                        Opt(label: "Approve it", detail: "") { s, x in s.companies[x.i].managerMonthlyWage = jsRound(s.companies[x.i].managerMonthlyWage * 1.12); mood(&s, x.i, 6) },
                        Opt(label: "Offer pay for results", detail: "5% more, plus a bonus if profit grows.") { s, x in
                            s.companies[x.i].managerMonthlyWage = jsRound(s.companies[x.i].managerMonthlyWage * 1.05)
                            s.companies[x.i].managerProfitBonus = max(s.companies[x.i].managerProfitBonus, 0.05); mood(&s, x.i, 2) },
                        Opt(label: "Refuse", detail: "They may look elsewhere.") { s, x in
                            mood(&s, x.i, -10)
                            if s.random.chance(0.3) { managerResigns(&s, x.i, "refused the raise") } }]))
        L.append(Def(id: "g_volume", cls: "strat", stages: ["grow", "est"], w: 2, def: 2,
                     cond: { _, co, data in (data.catalog[co.type].map(hasGoods) ?? false) && (co.books.month["cogs"] ?? 0) > 0 },
                     make: { s, i, _, fc in
                         let co = s.companies[i]
                         let y = co.books.year["cogs"] ?? 0, m = co.books.month["cogs"] ?? 0
                         let weeksIn = Double(max(1, s.week % 52))
                         return .object(["c": num(r1000(max(fc.currency(co.countryCode, s).scaledPrice(20000), (y > 0 ? y : m * 4) / weeksIn * 8)))]) },
                     title: { co, _, _ in "A volume discount for \(co.name)" },
                     body: { _, d, cur in "Your supplier offers 6% off if you order about \(cur.display(d["c"].double)) up front (two months' worth). The stock has to sit somewhere, and the cash is gone until it sells." },
                     opts: [
                        Opt(label: "Commit to the volume", detail: "6% cheaper goods for half a year.") { s, x in tiedUp(&s, x, x.d["c"].double * 0.5, weeks: 9); cost(&s, x, 0.94, 26) },
                        Opt(label: "Ask for flexible deliveries", detail: "3% off, no big order.") { s, x in cost(&s, x, 0.97, 26) },
                        Opt(label: "Decline", detail: "") { _, _ in }]))
        L.append(Def(id: "g_quality", cls: "strat", stages: ["grow", "est"], w: 3, def: 2,
                     cond: { _, co, _ in co.quality < 62 || co.reputation < 45 },
                     title: { co, _, _ in "Complaints are rising at \(co.name)" },
                     body: { _, _, _ in "More customers complain about quality. Left alone, reviews will follow." },
                     opts: [
                        Opt(label: "Fix the work and refund", detail: "Costs now, protects reviews.") { s, x in pay(&s, x, x.wk(s) * 0.4, "oth", "Corrective work and refunds"); rep(&s, x, 1) },
                        Opt(label: "Retrain the team", detail: "A week of lower output, better quality afterwards.") { s, x in
                            cap(&s, x, 0.85, 1); pay(&s, x, Double(s.companies[x.i].staff.count) * x.kc(3000), "oth", "Training")
                            s.companies[x.i].quality = min(100, s.companies[x.i].quality + 5) },
                        Opt(label: "Ignore it", detail: "No cost. Reviews will get worse.") { s, x in later(&s, 4, "g_quality_bad", x.i, .null) }]))
        L.append(Def(id: "g_loan", cls: "strat", stages: ["grow", "est"], w: 2, def: 2,
                     cond: { s, co, _ in co.form == .limited && ebit12(co, s) > 0 },
                     make: { s, i, data, fc in
                         let co = s.companies[i], k = fc.country(of: co, s)
                         let wk = EventEngine.context(for: co, data: data, country: k).wk
                         let nw = Valuation.netWorth(s, trades: data.catalog).total
                         let off = Banking.offer(kind: "biz", amount: 1000, company: co, state: s, netWorth: nw, context: fc)
                         let a = r1000(min(off.maximum, wk * 52 * 0.4))
                         if a < fc.currency(co.countryCode, s).scaledPrice(100000) { return nil }
                         return .object(["a": num(a), "r": num(s.economy.policyRate + off.margin)]) },
                     title: { co, _, _ in "Your bank offers \(co.name) an expansion loan" },
                     body: { _, d, cur in "Up to \(cur.display(d["a"].double)) over five years at about \(String(format: "%.1f", d["r"].double * 100))%. Debt lets you grow without giving away shares, but the payments come every month, good or bad." },
                     opts: [
                        Opt(label: "Take it all", detail: "") { s, x in drawLoan(&s, x, x.d["a"].double) },
                        Opt(label: "Take half", detail: "") { s, x in drawLoan(&s, x, (x.d["a"].double / 2000).rounded() * 1000) },
                        Opt(label: "No thanks", detail: "Grow from your own profits, or sell shares instead.") { _, _ in }]))
        L.append(Def(id: "g_teampoach", cls: "strat", stages: ["grow", "est"], w: 2, def: 2,
                     cond: { _, co, _ in co.staff.count >= 5 },
                     make: { s, i, _, _ in .object(["n": num(Double(min(3, s.companies[i].staff.count / 4 + 1)))]) },
                     title: { _, _, _ in "A competitor is hiring away your people" },
                     body: { co, d, _ in "\(Int(d["n"].double)) experienced people at \(co.name) have offers from a competitor." },
                     opts: [
                        Opt(label: "Retention bonuses", detail: "A month's pay each. Most stay.") { s, x in
                            let L = bestPaid(s, x.i, x.d["n"].int)
                            pay(&s, x, L.reduce(0) { $0 + $1.monthlyWage }, "wages", "Retention bonuses")
                            if s.random.chance(0.25), let f = L.first { removeStaff(&s, x.i, id: f.id) } },
                        Opt(label: "Reorganise around it", detail: "Let them go and spread the work.") { s, x in
                            for m in bestPaid(s, x.i, x.d["n"].int) { removeStaff(&s, x.i, id: m.id) }
                            cap(&s, x, 0.9, 6); mood(&s, x.i, -6) },
                        Opt(label: "Let them go and recruit", detail: "Recruiting costs, and new people need time.") { s, x in
                            for m in bestPaid(s, x.i, x.d["n"].int) { removeStaff(&s, x.i, id: m.id) }
                            pay(&s, x, x.kc(10000) * x.d["n"].double, "oth", "Recruiting") }]))
        L.append(Def(id: "g_bigcustgo", cls: "strat", stages: ["grow", "est"], w: 2, def: 2,
                     cond: { _, co, data in (data.catalog[co.type]?.businessShare ?? 0) > 0.35 },
                     title: { co, _, _ in "A big customer of \(co.name) changes its buying rules" },
                     body: { _, _, _ in "A customer worth about a quarter of your sales moves to a new procurement process. You have to bid again, against everyone." },
                     opts: [
                        Opt(label: "Bid hard to keep it", detail: "Keep the work at a lower price.") { s, x in cost(&s, x, 1.05, 52) },
                        Opt(label: "Win new customers instead", detail: "Marketing and sales effort, and the old customer goes.") { s, x in
                            dem(&s, x, 0.85, 20); pay(&s, x, x.wk(s) * 0.6, "mkt", "Sales push"); s.companies[x.i].awareness = min(100, s.companies[x.i].awareness + 6) },
                        Opt(label: "Cut costs and accept the loss", detail: "") { s, x in dem(&s, x, 0.78, 40) }]))

        // Established
        L.append(Def(id: "e_execleave", cls: "strat", stages: ["est"], w: 2, def: 0,
                     cond: { s, co, _ in co.managerID != nil && s.people[co.managerID!] != nil },
                     make: { s, i, _, _ in s.companies[i].managerID.flatMap { s.people[$0] }.map { .object(["n": .string($0.name)]) } },
                     title: { co, d, _ in "\(d["n"].string) resigns from \(co.name)" },
                     body: { _, d, _ in "\(d["n"].string) has accepted a job elsewhere and leaves at the end of the month." },
                     opts: [
                        Opt(label: "Promote from inside", detail: "Cheaper and knows the place, but untested.") { s, x in
                            s.companies[x.i].managerMonthlyWage = jsRound(s.companies[x.i].managerMonthlyWage * 0.9); cap(&s, x, 0.95, 8); mood(&s, x.i, 2) },
                        Opt(label: "Hire an outside executive", detail: "Expensive, experienced, needs time to settle.") { s, x in
                            pay(&s, x, s.companies[x.i].managerMonthlyWage * 3, "oth", "Executive search")
                            s.companies[x.i].managerMonthlyWage = jsRound(s.companies[x.i].managerMonthlyWage * 1.2); cap(&s, x, 0.95, 4) },
                        Opt(label: "Run it yourself for now", detail: "Your hours, your time.") { s, x in
                            if let id = s.companies[x.i].managerID, var p = s.people[id] { p.employerID = 0; s.people[id] = p }
                            s.companies[x.i].managerID = nil; s.companies[x.i].managerMonthlyWage = 0; s.companies[x.i].ownerHours = 45 }]))
        L.append(Def(id: "e_automation", cls: "strat", stages: ["est", "grow"], w: 2, def: 2,
                     cond: { _, co, data in ["prod", "retail", "logi"].contains(data.catalog[co.type]?.family ?? "") && co.staff.count >= 6 },
                     make: { s, i, _, _ in .object(["c": num(r1000(s.companies[i].staff.reduce(0) { $0 + $1.monthlyWage } * 10))]) },
                     title: { co, _, _ in "Automation could cut costs at \(co.name)" },
                     body: { _, d, cur in "New equipment for about \(cur.display(d["c"].double)) would do the work of two people and speed things up. Training takes a month." },
                     opts: [
                        Opt(label: "Invest now", detail: "Pay up front, lower costs for years.") { s, x in
                            let c = x.d["c"].double
                            if s.companies[x.i].cash < c { s.note("Not enough cash in \(s.companies[x.i].name).", tone: "bad", companyID: s.companies[x.i].id); return }
                            pay(&s, x, c, nil, "Automation equipment"); cap(&s, x, 0.85, 4); later(&s, 5, "e_auto_done", x.i, .object(["n": num(2)])) },
                        Opt(label: "Phase it in", detail: "Half now, half next year. Half the gain.") { s, x in
                            let c = x.d["c"].double / 2
                            if s.companies[x.i].cash < c { return }
                            pay(&s, x, c, nil, "Automation, phase one"); later(&s, 5, "e_auto_done", x.i, .object(["n": num(1)])) },
                        Opt(label: "Keep the team as it is", detail: "") { _, _ in }]))
        L.append(Def(id: "e_audit", cls: "crisis", stages: ["grow", "est"], w: 2, def: 0,
                     make: { s, i, data, fc in
                         let co = s.companies[i], k = fc.country(of: co, s)
                         let wk = EventEngine.context(for: co, data: data, country: k).wk
                         return .object(["c": num(jsRound(max(fc.currency(co.countryCode, s).scaledPrice(15000), wk * 0.3)))]) },
                     title: { co, _, _ in "Inspectors find problems at \(co.name)" },
                     body: { _, d, cur in "A compliance audit lists several deficiencies. Fixing them costs about \(cur.display(d["c"].double)). Serious ones can mean fines or closure." },
                     opts: [
                        Opt(label: "Fix everything", detail: "") { s, x in pay(&s, x, x.d["c"].double, "oth", "Compliance work") },
                        Opt(label: "Pause the affected work", detail: "Fix it while part of the business stands still.") { s, x in pay(&s, x, x.d["c"].double * 0.6, "oth", "Compliance work"); cap(&s, x, 0.7, 2) },
                        Opt(label: "Contest the findings", detail: "Legal costs; you may be right, or fined.") { s, x in
                            pay(&s, x, x.d["c"].double * 0.3, "oth", "Legal costs")
                            if s.random.chance(0.45) { pay(&s, x, x.d["c"].double * 2, "fine", "Compliance fine") } }]))
        L.append(Def(id: "e_refi", cls: "strat", stages: ["grow", "est"], w: 2, def: 2,
                     cond: { s, co, data in
                         let floor = Currency(country: data.countries.resolve(co.countryCode, orHome: s.homeCountryCode), rates: ExchangeRates(drift: s.exchangeRates.values)).scaledPrice(150_000)
                         return s.loans.contains { $0.companyID == co.id && $0.kind != "start" && $0.balance > floor } },
                     make: { s, i, _, fc in
                         let co = s.companies[i]
                         let b = s.loans.filter { $0.companyID == co.id && $0.kind != "start" }.reduce(0) { $0 + $1.balance }
                         if b < fc.currency(co.countryCode, s).scaledPrice(200000) { return nil }
                         return .object(["b": num(jsRound(b))]) },
                     title: { co, _, _ in "A lender offers to refinance \(co.name)'s debt" },
                     body: { _, d, cur in "Your \(cur.display(d["b"].double)) of loans could move to a new lender at about 0.6 points lower interest, for a 1% fee. A shorter term saves more interest but raises the monthly payment." },
                     opts: [
                        Opt(label: "Refinance at the lower rate", detail: "1% fee now.") { s, x in refinance(&s, x, margin: 0.006, shorten: false) },
                        Opt(label: "Refinance and pay off faster", detail: "Lower rate, higher payments.") { s, x in refinance(&s, x, margin: 0.008, shorten: true) },
                        Opt(label: "Keep things as they are", detail: "") { _, _ in }]))
        L.append(Def(id: "e_reputation", cls: "crisis", stages: ["grow", "est"], w: 2, def: 2,
                     title: { co, _, _ in "A complaint about \(co.name) goes viral" },
                     body: { _, _, _ in "A customer's angry post is everywhere. People want to know what you will do." },
                     opts: [
                        Opt(label: "Respond openly and make it right", detail: "Costs a little, contains it.") { s, x in pay(&s, x, x.wk(s) * 0.2, "oth", "Making it right"); rep(&s, x, -2) },
                        Opt(label: "Order an independent review", detail: "Takes weeks; credible if it clears you.") { s, x in
                            pay(&s, x, x.kc(40000), "oth", "Independent review"); rep(&s, x, -3); later(&s, 6, "e_rep_review", x.i, .null) },
                        Opt(label: "Say nothing", detail: "It may blow over. Or not.") { s, x in
                            if s.random.chance(0.5) { rep(&s, x, -1) } else { rep(&s, x, -8); dem(&s, x, 0.9, 12) } }]))
        L.append(Def(id: "e_wages", cls: "strat", stages: ["est", "grow"], w: 2, def: 1,
                     cond: { _, co, _ in co.staff.count >= 8 },
                     title: { co, _, _ in "Wage talks at \(co.name)" },
                     body: { _, _, _ in "The staff want 6% more and a better pension." },
                     opts: [
                        Opt(label: "Agree", detail: "Higher payroll, good morale.") { s, x in raiseAll(&s, x.i, 1.06); mood(&s, x.i, 8) },
                        Opt(label: "3% now, 3% next year", detail: "Spreads the cost.") { s, x in raiseAll(&s, x.i, 1.03); later(&s, 52, "e_wages_2", x.i, .null) },
                        Opt(label: "Refuse", detail: "Risk a strike and people leaving.") { s, x in
                            mood(&s, x.i, -12)
                            if s.random.chance(0.4) { cap(&s, x, 0.4, 2); rep(&s, x, -2); s.note("Staff at \(s.companies[x.i].name) went on strike for two weeks.", tone: "bad", companyID: s.companies[x.i].id) } }]))

        // Groups
        L.append(Def(id: "t_restructure", cls: "corp", w: 2, def: 2, global: true,
                     cond: { s, _, _ in losers(s).count >= 2 },
                     make: { s, _, _, _ in .object(["L": .array(losers(s).map { num(Double($0)) })]) },
                     title: { _, _, _ in "Several of your companies keep losing money" },
                     body: { _, d, _ in "Your advisors want a decision: \(d["L"].array.count) companies have lost money for six months." },
                     opts: [
                        Opt(label: "Sell the weakest", detail: "It goes at a low price, but stops the bleeding.") { s, x in
                            let ids = x.d["L"].array.map { $0.int }
                            let open = ids.compactMap { s.companyIndex($0) }.filter { s.companies[$0].status == .open }
                            if let w = open.min(by: { ebit12(s.companies[$0], s) < ebit12(s.companies[$1], s) }) {
                                let v = value(s.companies[w], s, x.data)
                                _ = CompanySale.complete(&s, companyIndex: w, buyer: "Quick buyer", price: jsRound(v * 0.6), data: x.data, context: x.fc)
                            } },
                        Opt(label: "New management where there is a manager", detail: "") { s, x in
                            for id in x.d["L"].array.map({ $0.int }) { if let k = s.companyIndex(id), s.companies[k].managerID != nil { s.companies[k].managerMonthlyWage = jsRound(s.companies[k].managerMonthlyWage * 1.15); cap(&s, X(i: k, d: .null, data: x.data, fc: x.fc, cur: x.cur), 0.95, 4) } } },
                        Opt(label: "Keep funding them", detail: "They may support the rest of the group.") { _, _ in }]))
        L.append(Def(id: "t_downgrade", cls: "crisis", w: 2, tone: "bad", global: true,
                     make: { s, _, data, fc in
                         let nw = max(1, Valuation.netWorth(s, trades: data.catalog).total), debt = Banking.totalDebt(s)
                         return debt > nw * 0.8 && debt > fc.homeCurrency(s).scaledPrice(5e6) ? .object([:]) : nil },
                     title: { _, _, _ in "Your credit rating has been cut" },
                     body: { _, _, _ in "With this much debt against what you own, lenders see more risk. New loans will cost more until the debt comes down or profits go up. Selling assets or paying down debt helps." },
                     auto: { s, _ in s.credit = clamp(s.credit - 10, 0, 100) }))

        // Any company
        L.append(Def(id: "x_infl", cls: "gen", w: 2, tone: "bad", from: "Economy", global: true,
                     cond: { s, _, _ in s.economy.inflation > 0.03 },
                     title: { _, _, _ in "Prices are rising faster than expected" },
                     body: { _, _, _ in "Inflation is running well above normal. Costs and wage demands creep up over the coming months. Businesses that can raise prices protect their margins; fixed-price contracts suffer." },
                     auto: { s, x in
                         for k in s.companies.indices where s.companies[k].status == .open && s.companies[k].countryCode == s.homeCountryCode { addMod(&s, k, "cogsup", 1.025, 13) } }))
        L.append(Def(id: "x_tech", cls: "gen", w: 2, def: 2,
                     cond: { _, co, data in ["svc", "retail", "logi", "prod"].contains(data.catalog[co.type]?.family ?? "") },
                     make: { s, i, data, fc in
                         let co = s.companies[i], k = fc.country(of: co, s)
                         let wk = EventEngine.context(for: co, data: data, country: k).wk
                         return .object(["c": num(r1000(max(fc.currency(co.countryCode, s).scaledPrice(50000), wk * 52 * 0.03)))]) },
                     title: { co, _, _ in "New technology changes \(co.name)'s trade" },
                     body: { _, d, cur in "A new kind of software and equipment is spreading through the trade. Early users cut costs and win customers who expect it. Getting it costs about \(cur.display(d["c"].double))." },
                     opts: [
                        Opt(label: "Invest now", detail: "Lower costs and a small edge for two years.") { s, x in pay(&s, x, x.d["c"].double, nil, "New technology"); cost(&s, x, 0.95, 104); dem(&s, x, 1.03, 52) },
                        Opt(label: "Partner with a provider", detail: "A monthly fee instead of a big bill.") { s, x in pay(&s, x, x.d["c"].double * 0.15, "oth", "Technology partner"); cost(&s, x, 0.98, 104) },
                        Opt(label: "Wait and see", detail: "No cost now. Customers may drift to those who have it.") { s, x in dem(&s, x, 0.96, 52) }]))
        L.append(Def(id: "x_claim", cls: "crisis", w: 2, def: 0,
                     make: { s, i, data, fc in
                         let co = s.companies[i], k = fc.country(of: co, s)
                         let wk = EventEngine.context(for: co, data: data, country: k).wk
                         let who = s.random.pick(["a former employee", "a supplier", "a customer", "a competitor"])
                         return .object(["c": num(r1000(max(fc.currency(co.countryCode, s).scaledPrice(30000), wk * 52 * 0.01))), "who": .string(who)]) },
                     pre: { s, x in pay(&s, x, x.d["c"].double * 0.2, "oth", "Lawyers") },
                     title: { co, d, _ in "\(co.name) is sued by \(d["who"].string)" },
                     body: { _, d, cur in "They claim about \(cur.display(d["c"].double * 3)). Legal costs have started. Settling is cheaper and certain; defending may clear you, or cost more." },
                     opts: [
                        Opt(label: "Settle", detail: "Pay a third of the claim.") { s, x in pay(&s, x, x.d["c"].double, "oth", "Settlement") },
                        Opt(label: "Defend it", detail: "") { s, x in
                            pay(&s, x, x.d["c"].double * 0.5, "oth", "Lawyers")
                            if s.random.chance(0.45) { pay(&s, x, x.d["c"].double * 3, "oth", "Damages awarded") }
                            else { s.note("\(s.companies[x.i].name) won the case.", tone: "good", companyID: s.companies[x.i].id) } }]))

        L.append(contentsOf: countryEvents())
        return L
    }

    // MARK: Pieces used by several answers

    /// Cash tied up for some weeks (goods bought up front, invoices to wait for): paid now, handed back later. Original: `wc`.
    static func tiedUp(_ s: inout GameState, _ x: X, _ amount: Double, weeks: Int) {
        let a = jsRound(amount)
        if a <= 0 { return }
        _ = Payments.companyPays(&s, companyID: s.companies[x.i].id, amount: a, category: nil, label: "Cash tied up in the deal")
        later(&s, weeks, "wc_back", x.i, .object(["a": num(a)]))
    }

    static func chaseInvoice(_ s: inout GameState, _ x: X, due: Int, bad: Bool, keepBad: Bool = false) {
        var list = s.companies[x.i].receivables
        guard let k = list.firstIndex(where: { abs($0.amount - x.d["a"].double) < 1 }) else { return }
        list[k].dueWeek = s.week + due
        list[k].willDefault = keepBad ? (list[k].willDefault || bad) : bad
        s.companies[x.i].receivables = list
    }

    static func drawLoan(_ s: inout GameState, _ x: X, _ amount: Double) {
        let nw = Valuation.netWorth(s, trades: x.data.catalog).total
        let co = s.companies[x.i]
        switch Banking.take(kind: "biz", amount: amount, termMonths: 60, company: co, state: &s, netWorth: nw, context: x.fc) {
        case .ok: break
        default: s.note("The loan fell through.", tone: "bad", companyID: co.id)
        }
    }

    static func refinance(_ s: inout GameState, _ x: X, margin: Double, shorten: Bool) {
        let id = s.companies[x.i].id
        pay(&s, x, x.d["b"].double * 0.01, "int", "Refinancing fee")
        for k in s.loans.indices where s.loans[k].companyID == id && s.loans[k].kind != "start" {
            s.loans[k].margin = max(0.005, s.loans[k].margin - margin)
            if shorten { s.loans[k].termMonths = max(24, Int((Double(s.loans[k].termMonths == 0 ? 120 : s.loans[k].termMonths) * 0.6).rounded())) }
            let rate = s.economy.policyRate + s.loans[k].margin
            let left = max(12, s.loans[k].termMonths - max(0, (s.week - s.loans[k].startWeek) * 12 / 52))
            s.loans[k].monthlyPayment = Loans.annuity(principal: s.loans[k].balance, yearlyRate: rate, months: Double(left))
        }
    }

    static func managerResigns(_ s: inout GameState, _ i: Int, _ why: String) {
        guard let id = s.companies[i].managerID else { return }
        let name = s.people[id]?.name ?? "The manager"
        if var p = s.people[id] { p.employerID = 0; s.people[id] = p }
        s.companies[i].managerID = nil; s.companies[i].managerMonthlyWage = 0; s.companies[i].ownerHours = 45
        s.addMessage(from: name, title: "\(name) resigns from \(s.companies[i].name)", body: "I \(why), so I am taking another job.", companyID: s.companies[i].id, tone: "bad")
    }

    /// Companies that lost money for six months. Original: `t_restructure` condition.
    static func losers(_ s: GameState) -> [Int] {
        s.companies.filter { $0.status == .open && $0.type != "hold" && $0.monthlyHistory.suffix(6).count >= 6 && $0.monthlyHistory.suffix(6).reduce(0, { $0 + $1.profit }) < 0 }.map { $0.id }
    }

    // MARK: Country events


    static func countryEvents() -> [Def] {
        var L: [Def] = []
        for (n, e) in CountryEvents.table.enumerated() {
            L.append(Def(id: "c_\(e.cc)\(n)", cls: "cty", cc: e.cc, w: 2, from: "Economy",
                         title: { _, _, _ in e.head }, body: { _, _, _ in e.text },
                         auto: { s, x in
                             for k in s.companies.indices where s.companies[k].status == .open && s.companies[k].countryCode == e.cc {
                                 guard let bd = x.data.catalog[s.companies[k].type] else { continue }
                                 let eff = e.fx[s.companies[k].type] ?? e.fx[bd.family] ?? e.fx["all"]
                                 switch eff {
                                 case .dem(let m)?: addMod(&s, k, "dem", m, 26)
                                 case .cost(let m, let w)?: addMod(&s, k, "cogsup", m, w)
                                 case .cap(let m, let w)?: addMod(&s, k, "cap", m, w)
                                 case nil: break
                                 }
                                 if e.wage > 0 { raiseAll(&s, k, e.wage) }
                                 if e.rate > 0 {
                                     var ids: [JSONValue] = []
                                     for l in s.loans.indices where s.loans[l].companyID == s.companies[k].id && s.loans[l].kind != "start" { s.loans[l].margin += e.rate; ids.append(num(Double(s.loans[l].id))) }
                                     if !ids.isEmpty { later(&s, 39, "rate_back", k, .object(["ids": .array(ids), "add": num(e.rate)])) }
                                 }
                             } }))
        }
        func choice(_ id: String, w: Double = 2, def: Int, cond: @escaping (GameState, Company, GameData) -> Bool, make: ((inout GameState, Int, GameData, FinanceContext) -> JSONValue?)? = nil, title: @escaping Txt, body: @escaping Txt, opts: [Opt], from: String? = nil) {
            L.append(Def(id: "c_\(id)", cls: "cty", cc: CountryEvents.country(ofDecision: id), w: w, from: from, def: def, cond: cond, make: make, title: title, body: body, opts: opts))
        }
        choice("NO_wage", def: 2, cond: { _, co, _ in co.staff.count >= 4 }, title: { co, _, _ in "A tight labour market squeezes \(co.name)" },
               body: { _, _, _ in "Norwegian employers compete hard for people. Your staff hear about better offers every week." },
               opts: [Opt(label: "Raise pay 4%", detail: "") { s, x in raiseAll(&s, x.i, 1.04); mood(&s, x.i, 5) },
                      Opt(label: "Invest in productivity", detail: "Better tools so fewer people do more.") { s, x in pay(&s, x, x.payroll(s) * 1.5, nil, "Productivity tools"); cap(&s, x, 1.06, 52) },
                      Opt(label: "Hire less and accept vacancies", detail: "Slower growth.") { s, x in
                          mood(&s, x.i, -6)
                          if s.random.chance(0.3), s.companies[x.i].staff.count > 1, let last = s.companies[x.i].staff.last { removeStaff(&s, x.i, id: last.id) } }])
        choice("LT_eu", def: 2, cond: { _, co, _ in co.form == .limited }, title: { co, _, _ in "EU money for modernising \(co.name)" },
               body: { _, _, _ in "An EU programme co-finances new equipment and technology. Applying takes work and there is no guarantee." },
               opts: [Opt(label: "Apply", detail: "Paperwork costs now; about half of applicants get support.") { s, x in pay(&s, x, x.kc(8000), "oth", "EU application"); later(&s, 10, "c_LT_eu_res", x.i, .null) },
                      Opt(label: "Invest without support", detail: "Faster, full price.") { s, x in pay(&s, x, x.yr(s) * 0.03, nil, "Modernisation"); cost(&s, x, 0.96, 104) },
                      Opt(label: "Skip it", detail: "") { _, _ in }])
        choice("PL_contract", def: 2, cond: { _, co, data in ["prod", "logi"].contains(data.catalog[co.type]?.family ?? "") }, title: { co, _, _ in "A foreign manufacturer wants \(co.name) as a supplier" },
               body: { _, _, _ in "A big contract, but one customer would be a large part of your business." },
               opts: [Opt(label: "Take it all", detail: "") { s, x in dem(&s, x, 1.35, 104); later(&s, 60, "c_dep_risk", x.i, .null) },
                      Opt(label: "Take part, subcontract the rest", detail: "Less risk, less margin.") { s, x in dem(&s, x, 1.15, 104); cost(&s, x, 1.02, 104) },
                      Opt(label: "Decline", detail: "Too much eggs in one basket.") { _, _ in }])
        choice("KR_cust", def: 0, cond: { _, co, data in (data.catalog[co.type]?.businessShare ?? 0) > 0.2 }, title: { co, _, _ in "A large corporate customer squeezes \(co.name)" },
               body: { _, _, _ in "They want 8% lower prices and stricter delivery terms, or they will take their business elsewhere." },
               opts: [Opt(label: "Accept for the volume", detail: "") { s, x in cost(&s, x, 1.05, 52) },
                      Opt(label: "Negotiate service levels", detail: "") { s, x in if s.random.chance(0.5) { cost(&s, x, 1.02, 52) } else { dem(&s, x, 0.9, 26) } },
                      Opt(label: "Diversify to smaller customers", detail: "") { s, x in dem(&s, x, 0.88, 26); pay(&s, x, x.wk(s) * 0.4, "mkt", "Finding new customers") }])
        choice("UK_rent", def: 2, cond: { _, co, data in data.catalog[co.type]?.premisesKind != nil && !co.value("prem")["owned"].bool }, title: { co, _, _ in "The landlord of \(co.name) wants 20% more rent" },
               body: { _, _, _ in "The lease is up for renewal." },
               opts: [Opt(label: "Negotiate", detail: "You may get 8%.") { s, x in cost(&s, x, s.random.chance(0.6) ? 1.02 : 1.05, 260) },
                      Opt(label: "Move somewhere cheaper", detail: "A month of disruption, and some regulars lose track of you.") { s, x in cap(&s, x, 0.75, 3); dem(&s, x, 0.95, 26) },
                      Opt(label: "Accept", detail: "The location is worth it.") { s, x in cost(&s, x, 1.05, 260) }])
        choice("US_fed", def: 2, cond: { _, co, data in (data.catalog[co.type]?.businessShare ?? 0) > 0.2 && co.staff.count >= 5 }, title: { co, _, _ in "A federal contract that fits \(co.name)" },
               body: { _, _, _ in "Steady work for years, with heavy compliance requirements." },
               opts: [Opt(label: "Bid", detail: "") { s, x in
                          pay(&s, x, x.kc(20000), "oth", "Federal bid")
                          if s.random.chance(0.3) { dem(&s, x, 1.25, 156); cost(&s, x, 1.03, 156); s.note("\(s.companies[x.i].name) won the federal contract.", tone: "good", companyID: s.companies[x.i].id) } },
                      Opt(label: "Partner with an established contractor", detail: "") { s, x in if s.random.chance(0.5) { dem(&s, x, 1.1, 156) } },
                      Opt(label: "Pass", detail: "") { _, _ in }])
        choice("ES_tax", w: 1, def: 2, cond: { _, _, _ in true }, make: { s, _, data, fc in Valuation.netWorth(s, trades: data.catalog).total > fc.homeCurrency(s).scaledPrice(10e6) ? .object([:]) : nil }, title: { _, _, _ in "The tax office asks you to review your tax position" },
               body: { _, _, _ in "A notice asks you to review your personal and company tax affairs." },
               opts: [Opt(label: "Pay for proper advice", detail: "") { s, x in Payments.playerPays(&s, x.kc(25000), label: "Tax advisor") },
                      Opt(label: "Reorganise where it is legal", detail: "Advice now, and a structure that may save tax later.") { s, x in Payments.playerPays(&s, x.kc(60000), label: "Tax restructuring") },
                      Opt(label: "Carry on as you are", detail: "") { s, x in if s.random.chance(0.2) { Payments.playerPays(&s, x.kc(40000), label: "Back taxes and interest") } }], from: "Tax office")
        choice("NL_wh", def: 1, cond: { _, co, _ in co.type == "webshop" || co.type == "grocery" || co.type == "wh3pl" || co.type == "courier" || co.type == "trucking" }, title: { co, _, _ in "Warehouse space for \(co.name) is getting scarce" },
               body: { _, _, _ in "Rents for storage near the ports are rising fast." },
               opts: [Opt(label: "Sign a long lease now", detail: "Lock in today's price for five years.") { s, x in pay(&s, x, x.wk(s) * 0.3, "rent", "Lease deposit"); cost(&s, x, 0.99, 260) },
                      Opt(label: "Use a logistics provider", detail: "Flexible, a bit dearer.") { s, x in cost(&s, x, 1.02, 104) },
                      Opt(label: "Hold less stock", detail: "Cheaper, but more stock-outs.") { s, x in cap(&s, x, 0.95, 52) }])
        choice("AU_freight", def: 2, cond: { _, co, data in data.catalog[co.type].map(hasGoods) ?? false }, title: { co, _, _ in "Long-distance freight costs hit \(co.name)" },
               body: { _, _, _ in "Moving goods across the country costs more this year." },
               opts: [Opt(label: "Consolidate deliveries", detail: "Fewer, bigger loads; sometimes slower.") { s, x in cost(&s, x, 1.01, 26); dem(&s, x, 0.98, 13) },
                      Opt(label: "Buy more locally", detail: "") { s, x in cost(&s, x, 1.015, 26) },
                      Opt(label: "Raise prices", detail: "") { s, x in cost(&s, x, 1.03, 26); dem(&s, x, 0.97, 26) }])
        choice("SE_wage", def: 0, cond: { _, co, _ in co.staff.count >= 5 }, title: { _, _, _ in "Industry-wide wage talks in Sweden" },
               body: { _, _, _ in "The unions and employers negotiate a new collective agreement. Labour costs will rise; how much is uncertain." },
               opts: [Opt(label: "Plan for a 4% rise", detail: "") { s, x in raiseAll(&s, x.i, 1.04) },
                      Opt(label: "Plan productivity gains", detail: "Training and tools, then a smaller rise.") { s, x in pay(&s, x, x.payroll(s) * 0.8, "oth", "Training"); raiseAll(&s, x.i, 1.025) },
                      Opt(label: "Hire less this year", detail: "") { s, x in raiseAll(&s, x.i, 1.03) }])
        choice("CA_proj", def: 1, cond: { _, co, data in ["project", "logi", "venue"].contains(data.catalog[co.type]?.family ?? "") }, title: { _, _, _ in "A big resource project nearby" },
               body: { _, _, _ in "A mine and pipeline project needs builders, trucks, rooms and meals for two years. It will end, though." },
               opts: [Opt(label: "Go after the work", detail: "More business, travel costs, and it ends.") { s, x in dem(&s, x, 1.25, 104); cost(&s, x, 1.03, 104) },
                      Opt(label: "Take some, keep your regulars first", detail: "") { s, x in dem(&s, x, 1.1, 104) },
                      Opt(label: "Stay out", detail: "") { _, _ in }])
        choice("DE_quality", def: 2, cond: { _, co, data in data.catalog[co.type]?.family == "prod" }, title: { co, _, _ in "A key part for \(co.name) fails quality checks" },
               body: { _, _, _ in "A batch from your main parts supplier does not meet spec." },
               opts: [Opt(label: "Stop production to inspect", detail: "A week lost; no faulty goods ship.") { s, x in cap(&s, x, 0.3, 1) },
                      Opt(label: "Switch supplier", detail: "Dearer, but safe.") { s, x in cost(&s, x, 1.04, 26) },
                      Opt(label: "Controlled delay and claim compensation", detail: "") { s, x in
                          cap(&s, x, 0.8, 2)
                          if s.random.chance(0.6) { Payments.companyReceives(&s, companyID: s.companies[x.i].id, amount: jsRound(x.wk(s) * 0.2), category: "rev", label: "Compensation from supplier") } }])
        L += corporateDecisions()
        L += misconductDecisions()
        return L
    }

    // MARK: Follow-ups and the scheduler

    static func later(_ s: inout GameState, _ weeks: Int, _ id: String, _ i: Int, _ d: JSONValue) {
        var st = s.rest["e27"] ?? .object([:])
        var q = st["q"].array
        q.append(.object(["w": num(Double(s.week + weeks)), "id": .string(id), "co": num(Double(s.companies[i].id)), "d": d]))
        st["q"] = .array(q)
        s.rest["e27"] = st
    }

    static func followUp(_ s: inout GameState, id: String, companyID: Int, d: JSONValue, data: GameData, context fc: FinanceContext) {
        guard let k = s.companyIndex(companyID), s.companies[k].status == .open else { return }
        let x = X(i: k, d: d, data: data, fc: fc, cur: fc.currency(s.companies[k].countryCode, s))
        let name = s.companies[k].name
        switch id {
        case "wc_back": Payments.companyReceives(&s, companyID: companyID, amount: d["a"].double, category: nil, label: "Cash freed from the deal")
        case "g_quality_bad": rep(&s, x, -4); dem(&s, x, 0.93, 12); s.note("The complaints at \(name) have reached the review sites.", tone: "bad", companyID: companyID)
        case "e_auto_done":
            let n = max(1, d["n"].int)
            for _ in 0..<n {
                let pool = s.companies[k].staff.filter { ["fworker", "helper", "cashier", "operator", "labour"].contains($0.role) }.sorted { $0.monthlyWage < $1.monthlyWage }
                if let w = pool.first, s.companies[k].staff.count > 2 { removeStaff(&s, k, id: w.id) }
            }
            cap(&s, x, 1 + 0.06 * Double(n), 260)
            s.note("The new equipment at \(name) is running.", tone: "good", companyID: companyID)
        case "e_rep_review":
            if s.random.chance(0.65) { rep(&s, x, 6); s.note("The independent review cleared \(name).", tone: "good", companyID: companyID) }
            else { rep(&s, x, -3); s.note("The review found real problems at \(name).", tone: "bad", companyID: companyID) }
        case "e_wages_2": raiseAll(&s, k, 1.03)
        case "c_LT_eu_res":
            if s.random.chance(0.5) { cost(&s, x, 0.95, 156); s.note("The EU programme will co-finance new equipment at \(name).", tone: "good", companyID: companyID) }
            else { s.note("The EU application for \(name) was turned down.", tone: "n", companyID: companyID) }
        case "c_dep_risk":
            if s.random.chance(0.3) { dem(&s, x, 0.7, 26); s.note("The big foreign customer of \(name) moved production elsewhere.", tone: "bad", companyID: companyID) }
        case "rate_back":
            for v in d["ids"].array { if let l = s.loans.firstIndex(where: { $0.id == v.int }) { s.loans[l].margin = max(0.005, s.loans[l].margin - d["add"].double) } }
        default: followUpCorporate(&s, id: id, index: k, d: d, data: data, context: fc)
        }
    }

    static func liveCompanies(_ s: GameState, _ data: GameData) -> [Int] {
        s.companies.indices.filter { s.companies[$0].status == .open && s.companies[$0].type != "hold" && data.catalog[s.companies[$0].type] != nil }
    }

    static func lastFired(_ st: JSONValue, _ id: String) -> Int { st["last"][id].isNull ? -999 : st["last"][id].int }

    /// The weekly turn: follow-ups that are due, and once a month the rolls for each class of event. Original: 'business_events weekly'.
    public static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        var st = s.rest["e27"] ?? .object([:])
        let due = st["q"].array.filter { s.week >= $0["w"].int }
        st["q"] = .array(st["q"].array.filter { s.week < $0["w"].int })
        s.rest["e27"] = st
        for f in due { followUp(&s, id: f["id"].string, companyID: f["co"].int, d: f["d"], data: data, context: fc) }
        Misconduct.weekly(&s, data: data, context: fc)
        guard GameCalendar.isMonthEnd(week: s.week) else { return }
        monthly(&s, data: data, context: fc)
    }

    static func monthly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        let cos = liveCompanies(s, data)
        if cos.isEmpty { return }
        func st() -> JSONValue { s.rest["e27"] ?? .object([:]) }
        func get(_ k: String) -> Int { st()[k].isNull ? -99 : st()[k].int }
        func set(_ k: String, _ v: Int) { var o = st(); o[k] = num(Double(v)); s.rest["e27"] = o }
        let nw = max(1, Valuation.netWorth(s, trades: data.catalog).total)
        let lev = Banking.totalDebt(s) / nw
        let tycoon = s.companies.contains { $0.type == "hold" && $0.status.isLive } || cos.count >= 5
        func attempt(_ cls: String, _ co: Int?) -> Bool {
            let list = definitions.filter { $0.cls == cls }
            return fireOne(&s, from: list, companyIndex: co, data: data, context: fc)
        }
        if s.week - get("lastS") >= 5 && s.random.chance(min(0.55, 0.3 + 0.05 * Double(cos.count))) {
            if attempt("strat", s.random.pick(cos)) { set("lastS", s.week) }
        }
        if s.week - get("lastO") >= 20 && s.random.chance(0.12) {
            if attempt("opp", s.random.pick(cos)) { set("lastO", s.week) }
        }
        if s.week - get("lastC") >= 26 && s.random.chance(0.05 + min(0.12, lev * 0.08) + (tycoon ? 0.03 : 0)) {
            if attempt("crisis", s.random.pick(cos)) { set("lastC", s.week) }
        }
        if tycoon && s.week - get("lastT") >= 26 && s.random.chance(0.12) {
            if attempt("corp", s.random.pick(cos)) { set("lastT", s.week) }
        }
        // Misconduct and political offers: gated by hashed rolls, so a game that never sees one draws nothing extra.
        for cls in ["mis", "pol"] where s.week - get("last_" + cls) >= 20 && Misconduct.gate(s, cls, 0.08) {
            let who = cos[Int(HashedRandom.first("misco:\(cls):\(s.week)") * Double(cos.count)) % cos.count]
            if attempt(cls, who) { set("last_" + cls, s.week) }
        }
        if s.random.chance(0.12) { _ = attempt("gen", s.random.pick(cos)) }
        for cc in Set(cos.map { s.companies[$0].countryCode }).sorted() {
            if !s.random.chance(0.08) { continue }
            let here = cos.filter { s.companies[$0].countryCode == cc }
            let list = definitions.filter { $0.cls == "cty" && $0.cc == cc }
            _ = fireOne(&s, from: list, companyIndex: s.random.pick(here), data: data, context: fc)
        }
    }

    /// Pick one of the definitions that fits this company (stage, country, cooldown, condition), weighted. Original: `pickDef` + `tryFire`.
    static func fireOne(_ s: inout GameState, from list: [Def], companyIndex i: Int?, data: GameData, context fc: FinanceContext) -> Bool {
        guard let i = i else { return false }
        let co = s.companies[i]
        let stg = stage(s, co, data, fc)
        let st = s.rest["e27"] ?? .object([:])
        let ok = list.filter { d in
            (d.stages.isEmpty || d.stages.contains(stg)) && (d.cc == nil || d.cc == co.countryCode) && s.week - lastFired(st, d.id) > 52 && d.cond(s, co, data)
        }
        guard !ok.isEmpty else { return false }
        let tot = ok.reduce(0) { $0 + $1.w }
        var r = s.random.range(0, tot)
        var chosen = ok[0]
        for d in ok { if r < d.w { chosen = d; break }; r -= d.w }
        return fire(&s, chosen, companyIndex: i, data: data, context: fc)
    }

    static func fire(_ s: inout GameState, _ def: Def, companyIndex i: Int, data: GameData, context fc: FinanceContext, given: JSONValue? = nil) -> Bool {
        var d: JSONValue = .object([:])
        if let g = given { d = g } else if let make = def.make { guard let made = make(&s, i, data, fc) else { return false }; d = made }
        let cur = fc.currency(s.companies[i].countryCode, s)
        let x = X(i: i, d: d, data: data, fc: fc, cur: cur)
        var st = s.rest["e27"] ?? .object([:])
        var last = st["last"].object; last[def.id] = num(Double(s.week)); st["last"] = .object(last)
        s.rest["e27"] = st
        def.pre?(&s, x)
        if def.silent { return true }
        let co = s.companies[i]
        let title = def.title(co, d, cur), body = def.body(co, d, cur)
        let from = def.from ?? (def.global ? "News" : co.name)
        let cid = def.global ? 0 : co.id
        if def.opts.isEmpty {
            def.auto?(&s, x)
            s.addMessage(from: from, title: title, body: body, companyID: cid, tone: def.tone)
            s.note(title, tone: def.tone, companyID: cid)
            return true
        }
        let options = def.opts.map { JSONValue.option($0.label, $0.detail) }
        s.addMessage(kind: "ask", from: from, title: title, body: body, companyID: cid, tone: def.tone, status: "open", options: options,
                     action: action, data: .object(["id": .string(def.id), "co": num(Double(co.id)), "d": d]), expiresWeek: s.week + def.exp)
        s.note("Decision needed: \(title)", tone: def.tone, companyID: cid)
        return true
    }

    // MARK: Answers

    static func run(_ s: inout GameState, message m: Message, option idx: Int, data: GameData, context fc: FinanceContext) {
        let payload = m.value("data")
        guard let def = byID[payload["id"].string], def.opts.indices.contains(idx), let i = s.companyIndex(payload["co"].int), s.companies[i].status.isLive else { return }
        let x = X(i: i, d: payload["d"], data: data, fc: fc, cur: fc.currency(s.companies[i].countryCode, s))
        def.opts[idx].run(&s, x)
    }

    /// The player picked an answer. Called from `GameEngine.answer`.
    public static func answer(_ s: inout GameState, message m: Message, option idx: Int, data: GameData, context fc: FinanceContext) {
        run(&s, message: m, option: idx, data: data, context: fc)
    }

    /// Nobody answered in time: the decision's default happens. Returns the option used.
    @discardableResult
    public static func expired(_ s: inout GameState, message m: Message, data: GameData, context fc: FinanceContext) -> Int {
        let def = byID[m.value("data")["id"].string]
        let idx = def?.def ?? 0
        run(&s, message: m, option: idx, data: data, context: fc)
        return idx
    }
}
