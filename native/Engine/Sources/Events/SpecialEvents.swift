import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Events with their own logic rather than plain effects. Original: `SPEC` (engine/events/engine.js).
/// Insurance, banking and energy events (f_*, e_*) belong to families not yet in the native engine.
enum SpecialEvents {
    /// Returns true if the event was handled here.
    static func handle(_ s: inout GameState, companyIndex i: Int, _ e: GameEvent, ctx c: EventEngine.Context, data: GameData, context fc: FinanceContext) -> Bool {
        let co = s.companies[i]
        let cur = fc.currency(co.countryCode, s)
        switch e.id {
        case "g_review", "v_critic":
            let d = (co.quality - 55) / 18 + s.random.gauss() * 0.9
            let r = clamp(jsRound(d), -3, 3)
            if r == 0 { return true }
            s.companies[i].reputation = clamp(co.reputation + r * 0.8, 0, 100)
            s.companies[i].awareness = clamp(co.awareness + r * 2, 0, 100)
            s.note(r > 0 ? "Good reviews boost \(co.name) (+\(Int(r)))." : "Bad reviews hurt \(co.name) (\(Int(r))).", tone: r > 0 ? "good" : "bad", companyID: co.id)
        case "g_award":
            s.companies[i].reputation = clamp(co.reputation + 3, 0, 100)
            s.companies[i].awareness = clamp(co.awareness + 6, 0, 100)
            s.note("\(co.name) wins a local business award!", tone: "good", companyID: co.id)
            s.addMessage(from: co.name, title: "Award won", body: "Your reputation rises.", companyID: co.id, tone: "good")
        case "g_audit":
            let y = co.books.year
            let weekOfYear = max(8, Double(GameCalendar.date(week: s.week).month * 4 + 1))
            let yearProfit = max(0, (y["rev"] ?? 0) - Books.expenses(y)) * (52 / weekOfYear)
            let aq = co.value("acc").isNull ? 0.45 : co.value("acc")["q"].double
            let err = co.value("acc").isNull ? 0.15 : co.value("acc")["err"].double
            let authority = fc.country(of: co, s).pack["authorities"]["tax"].string
            if s.random.chance(err * 1.8 + (1 - aq) * 0.25) {
                let pen = jsRound(max(6000, yearProfit * 0.04) * (1.3 - aq))
                Payments.companyPays(&s, companyID: co.id, amount: pen, category: "fine", label: "Tax audit adjustment")
                s.addMessage(from: authority, title: "Audit finished for \(co.name)", body: "The auditors found errors. Adjustment and penalty: \(cur.format(pen)).", companyID: co.id, tone: "bad")
                s.note("Tax audit at \(co.name): errors found, \(cur.format(pen)) to pay.", tone: "bad", companyID: co.id)
            } else {
                s.addMessage(from: authority, title: "Audit finished for \(co.name)", body: "No issues. " + (co.value("acc").isNull ? "" : co.value("acc")["name"].string + " kept the books clean."), companyID: co.id, tone: "good")
                s.note("Tax audit at \(co.name): all clear.", tone: "good", companyID: co.id)
            }
        case "g_inspect":
            guard let bd = data.catalog[co.type] else { return true }
            let missing = !Knobs.documentOK(co, "hms") && bd.documents.contains("hms")
            let mq = co.managerID != nil ? ManagerModel.quality(co, bd, people: s.people) : 0.55
            let p = 0.18 + (1 - mq) * 0.25 + (1 - co.quality / 100) * 0.2 + (missing ? 0.5 : 0) + (co.value("flags")["shrinkUp"].bool ? 0.05 : 0)
            if s.random.chance(p) {
                let f = jsRound(max(8000, c.wk * 0.2))
                Payments.companyPays(&s, companyID: co.id, amount: f, category: "fine", label: "Inspection fine")
                s.note("Inspectors found issues at \(co.name): fine \(cur.format(f)).", tone: "bad", companyID: co.id)
                s.addMessage(from: fc.country(of: co, s).pack["authorities"]["lab"].string, title: "Inspection at \(co.name)", body: "Deviations were found. Fine \(cur.format(f)). Improve routines and training.", companyID: co.id, tone: "bad")
            } else { s.note("Inspection at \(co.name): passed.", tone: "good", companyID: co.id) }
        case "v_health":
            guard let bd = data.catalog[co.type] else { return true }
            let hq = co.quality / 100 + (Knobs.documentOK(co, "haccp") ? 0.12 : -0.2) + (co.managerID != nil ? ManagerModel.quality(co, bd, people: s.people) * 0.1 : 0) + (co.maintenance == 0 ? -0.08 : 0)
            let food = fc.country(of: co, s).pack["authorities"]["food"].string
            if s.random.chance(clamp(0.5 - hq, 0.02, 0.8)) {
                let f = jsRound(max(12000, c.wk * 0.25))
                Payments.companyPays(&s, companyID: co.id, amount: f, category: "fine", label: "Food safety fine")
                s.companies[i].reputation = clamp(co.reputation - 3, 0, 100)
                s.note("\(food) found hygiene deviations at \(co.name): fine \(cur.format(f)).", tone: "bad", companyID: co.id)
                s.addMessage(from: food, title: "Inspection at \(co.name)", body: "Deviations in hygiene routines. Fine \(cur.format(f)).", companyID: co.id, tone: "bad")
            } else {
                s.companies[i].reputation = clamp(co.reputation + 0.5, 0, 100)
                s.note("\(food) visits \(co.name): passed.", tone: "good", companyID: co.id)
            }
        case "v_bigwin":
            guard let bd = data.catalog[co.type] else { return true }
            let w = World(state: s, data: data)
            let hi = Knobs.effect(co, bd, "risk", w)
            let m = s.random.range(0.25, 1.4) * (hi == 0 ? 1 : hi) * (co.value("fm")["vol"].isNull ? 1 : co.value("fm")["vol"].double)
            let amt = jsRound(c.wk * m)
            Payments.companyPays(&s, companyID: co.id, amount: amt, category: "loss", label: "Big payout")
            s.note("A lucky player wins big at \(co.name): \(cur.format(amt)) paid out.", tone: "bad", companyID: co.id)
        case "c_market":
            let h = s.economy.housing
            if h < 0.98 { EventEngine.addModifier(&s, i, key: "dem", multiplier: clamp(0.8 + (h - 0.9) * 1.2, 0.6, 1), weeks: 12) }
        case "d_market":
            if s.random.chance(0.5) {
                let h = s.economy.housing
                s.economy.housing = clamp(h * (1 + s.random.gauss() * 0.012), 0.7, 1.5)
                s.note("The housing market moves: price index \(String(format: "%.2f", s.economy.housing)).", tone: s.economy.housing > h ? "good" : "bad", companyID: co.id)
            }
        default:
            // f_storm, f_run, f_default (finance), e_price, e_geo (energy): their families are not simulated natively yet.
            return e.id.hasPrefix("f_") || e.id.hasPrefix("e_") || e.id == "g_lawsuit" ? true : false
        }
        return true
    }
}
