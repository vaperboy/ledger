import Foundation
import GameCore
import Countries
import Finance
import Businesses

extension EventEngine {
    /// Add a temporary effect on a company (demand, capacity, price ... multiplied for some weeks). Original: `addMod`.
    static func addModifier(_ s: inout GameState, _ i: Int, key: String, multiplier m: Double, weeks: Double) {
        var mods = s.companies[i].value("mods").array
        mods.append(.object(["k": .string(key), "m": .number(m), "w": .number(jsRound(weeks))]))
        s.companies[i].set("mods", .array(mods))
    }

    /// Apply the effects of an answer to a company. Original: `applyFx`.
    static func apply(_ s: inout GameState, companyIndex i: Int, _ fx: JSONValue, ctx: Context, event e: GameEvent, data: GameData, context fc: FinanceContext) {
        if fx.isNull { return }
        let id = s.companies[i].id
        let country = fc.country(of: s.companies[i], s)
        let currency = Currency(country: country, rates: fc.rates(s))
        if !fx["gamble"].isNull {
            let g = fx["gamble"]
            apply(&s, companyIndex: i, s.random.chance(g["p"].double) ? g["ok"] : g["bad"], ctx: ctx, event: e, data: data, context: fc)
        }
        // Whole thousands are written at the reference price level and scaled to the company's country.
        func scaled(_ v: Double) -> Double { v == v.rounded() && abs(v).truncatingRemainder(dividingBy: 1000) == 0 ? (v < 0 ? -1 : 1) * currency.scaledPrice(abs(v)) : v }
        if fx["cash"].double != 0 {
            let fc2 = scaled(fx["cash"].double)
            if fc2 < 0 { Payments.companyPays(&s, companyID: id, amount: -fc2, category: "oth", label: "Event cost") }
            else { Payments.companyReceives(&s, companyID: id, amount: fc2, category: "rev", label: "Event income") }
        }
        if fx["loss"].double != 0 {
            let amt = abs(fx["loss"].double)
            let cat = e.category
            let covered = cat != "none" && s.companies[i].value("ins")[cat].bool
            if covered {
                let deductible = currency.scaledPrice(10000)
                let net = min(amt, deductible)
                var paid = amt - net
                if paid > 0 {
                    paid = jsRound(paid * (s.random.chance(0.15) ? s.random.range(0.3, 0.7) : 1))
                    if paid > 0 {
                        Payments.companyReceives(&s, companyID: id, amount: paid, category: nil, label: "Insurance payout")
                        Payments.book(&s, companyID: id, category: "loss", amount: -paid)
                    }
                }
            }
            Payments.companyPays(&s, companyID: id, amount: amt, category: "loss", label: "Loss: incident")
        }
        if fx["coord"].bool {
            var flags = s.companies[i].value("flags"); flags["coll"] = 1; s.companies[i].set("flags", flags)
            s.companies[i].priceLevel = clamp(s.companies[i].priceLevel + 1, -3, 3)
            let key = s.companies[i].type + "|" + s.companies[i].cityID
            if var mm = s.rest["mk"]?[key], !mm.isNull {
                mm["pi"] = .number(min(1.4, mm["pi"].double + 0.04)); var mk = s.rest["mk"]!; mk[key] = mm; s.rest["mk"] = mk
            }
        }
        if fx["warn"].bool { addModifier(&s, i, key: "dem", multiplier: 0.93, weeks: 6) }
        if fx["fine"].double != 0 {
            Payments.companyPays(&s, companyID: id, amount: scaled(fx["fine"].double), category: "fine", label: "Fine")
        }
        var co = s.companies[i]
        if fx["rep"].double != 0 { co.reputation = clamp(co.reputation + fx["rep"].double * 1.5, 0, 100) }
        if fx["aware"].double != 0 { co.awareness = clamp(co.awareness + fx["aware"].double, 0, 100) }
        if fx["q"].double != 0 { co.quality = clamp(co.quality + fx["q"].double, 0, 100) }
        s.companies[i] = co
        if !fx["dem"].isNull {
            var dm = fx["dem"][0].double
            if fx["needCap"].bool && co.value("lastW")["util"].double > 0.9 { dm = 1 + (dm - 1) * 0.35 }
            addModifier(&s, i, key: "dem", multiplier: dm, weeks: fx["dem"][1].double)
        }
        if !fx["cap"].isNull { addModifier(&s, i, key: "cap", multiplier: fx["cap"][0].double, weeks: fx["cap"][1].double) }
        if !fx["price"].isNull { addModifier(&s, i, key: "price", multiplier: fx["price"][0].double, weeks: fx["price"][1].double) }
        if !fx["cogsUp"].isNull { addModifier(&s, i, key: "cogsup", multiplier: fx["cogsUp"][0].double, weeks: fx["cogsUp"][1].double) }
        if fx["pr"].double != 0 { s.companies[i].priceLevel = clamp(s.companies[i].priceLevel + fx["pr"].double, -3, 3) }
        if fx["fixeq"].double != 0 { repairWorstEquipment(&s, i, level: fx["fixeq"].double) }
        if fx["brk"].bool { breakEquipment(&s, i) }
        if fx["quit"].bool && !s.companies[i].staff.isEmpty {
            let sorted = s.companies[i].staff.sorted { $0.monthlyWage > $1.monthlyWage }
            let leaver = sorted[s.random.int(0, sorted.count - 1)]
            s.note("\(s.people[leaver.id]?.name ?? "A team member") left \(s.companies[i].name).", tone: "bad", companyID: id)
            s.companies[i].staff = s.companies[i].staff.filter { $0.id != leaver.id }
            if var p = s.people[leaver.id] { p.employerID = 0; s.people[leaver.id] = p }
        }
        if fx["raise"].double != 0 { giveRaise(&s, i, fx: fx, country: country, currency: currency) }
        if fx["bonus"].double != 0 { Payments.companyPays(&s, companyID: id, amount: fx["bonus"].double, category: "wages", label: "Bonus") }
        if fx["close"].double != 0 && s.companies[i].status == .open {
            let weeks = fx["close"].double
            if s.companies[i].value("ins")["bi"].bool {
                let pay = ctx.wk * 0.6 * weeks
                Payments.companyReceives(&s, companyID: id, amount: pay, category: nil, label: "Business-interruption cover")
                Payments.book(&s, companyID: id, category: "rev", amount: pay)
            }
            s.companies[i].status = .closed
            s.companies[i].set("closeW", weeks)
            s.companies[i].set("closeTot", weeks)
        }
        if fx["stock"].double != 0 {
            let l = jsRound(s.companies[i].inventory * fx["stock"].double)
            s.companies[i].inventory -= l
            Payments.book(&s, companyID: id, category: "loss", amount: l)
        }
        if !fx["collect"].isNull { collectInvoice(&s, i, chance: fx["collect"].double, data: data) }
        if fx["loseR"].double != 0, var r = s.companies[i].receivables.first {
            let cut = jsRound(r.amount * fx["loseR"].double)
            writeOffInvoice(&s, i, amount: cut, data: data)
            r.amount -= cut; r.willDefault = false; r.dueWeek = s.week
            var list = s.companies[i].receivables
            if !list.isEmpty { list[0] = r; s.companies[i].receivables = list }
        }
        if fx["writeoff"].bool {
            var list = s.companies[i].receivables
            if let k = list.firstIndex(where: { $0.willDefault }) ?? (list.isEmpty ? nil : 0) {
                let r = list.remove(at: k)
                s.companies[i].receivables = list
                writeOffInvoice(&s, i, amount: r.amount, data: data)
            }
        }
        if !fx["doc"].isNull {
            var docs = s.companies[i].value("docs")
            if !docs[fx["doc"].string].isNull { docs[fx["doc"].string]["st"] = "lapsed"; s.companies[i].set("docs", docs) }
        }
        var flags = s.companies[i].value("flags")
        if fx["secure"].bool { flags["secure"] = 1 }
        if fx["riskUp"].bool { flags["riskUp"] = 1 }
        if fx["riskDown"].bool { flags["riskDown"] = 1 }
        if fx["licRisk"].bool { flags["licRisk"] = .number(flags["licRisk"].double + 1) }
        s.companies[i].set("flags", flags)
        if fx["owner"].double != 0 {
            if fx["owner"].double > 0 { Payments.playerReceives(&s, fx["owner"].double, label: "Event") } else { Payments.playerPays(&s, -fx["owner"].double, label: "Event") }
        }
        if !fx["news"].isNull { s.news("\(s.companies[i].name): \(fx["news"].string)") }
        if fx["memb"].double != 0, !s.companies[i].value("fm")["memb"].isNull {
            var fm = s.companies[i].value("fm"); fm["memb"] = .number(fm["memb"].double * fx["memb"].double); s.companies[i].set("fm", fm)
        }
        if let bd = data.catalog[s.companies[i].type], bd.family == "project" { ProjectModel.applyEffect(&s, i, fx, bd: bd) }
        if fx["sell"].bool {
            s.addMessage(from: s.companies[i].name, title: "You may consider selling \(s.companies[i].name).",
                         body: "Selling is under the company's Ownership and value section.", companyID: id)
        }
    }

    // MARK: Pieces

    static func repairWorstEquipment(_ s: inout GameState, _ i: Int, level: Double) {
        var worst: (kind: String, key: String, index: Int)? = nil
        var worstCondition = 2.0
        let eq = s.companies[i].value("eq")
        for (id, r) in eq.object.sorted(by: { $0.key < $1.key }) where id != "fit" && r["cond"].double < worstCondition { worstCondition = r["cond"].double; worst = ("eq", id, 0) }
        for (n, v) in s.companies[i].value("veh").array.enumerated() where v["cond"].double < worstCondition { worstCondition = v["cond"].double; worst = ("veh", "", n) }
        guard let w = worst else { return }
        let newCondition = level >= 2 ? 1.0 : max(worstCondition, 0.75)
        if w.kind == "eq" {
            var e = s.companies[i].value("eq"); e[w.key]["cond"] = .number(newCondition); s.companies[i].set("eq", e)
        } else {
            var v = s.companies[i].value("veh").array; v[w.index]["cond"] = .number(newCondition); s.companies[i].set("veh", .array(v))
        }
    }

    static func breakEquipment(_ s: inout GameState, _ i: Int) {
        var keys: [(String, String, Int)] = []
        for (id, _) in s.companies[i].value("eq").object.sorted(by: { $0.key < $1.key }) where id != "fit" { keys.append(("eq", id, 0)) }
        for n in s.companies[i].value("veh").array.indices { keys.append(("veh", "", n)) }
        guard !keys.isEmpty else { return }
        let pick = s.random.pick(keys)
        if pick.0 == "eq" { var e = s.companies[i].value("eq"); e[pick.1]["cond"] = .number(e[pick.1]["cond"].double * 0.5); s.companies[i].set("eq", e) }
        else { var v = s.companies[i].value("veh").array; v[pick.2]["cond"] = .number(v[pick.2]["cond"].double * 0.5); s.companies[i].set("veh", .array(v)) }
    }

    static func giveRaise(_ s: inout GameState, _ i: Int, fx: JSONValue, country: Country, currency: Currency) {
        let raise = fx["raise"].double
        var staff = s.companies[i].staff
        var targets = Array(staff.indices)
        if !fx["stay"].isNull && !staff.isEmpty { targets = [s.random.int(0, staff.count - 1)] }
        for k in targets { staff[k].monthlyWage = currency.roundedStep(staff[k].monthlyWage * (1 + raise), about: 100) }
        s.companies[i].staff = staff
        if s.companies[i].managerID != nil && raise > 0.09 && fx["stay"].isNull {
            s.companies[i].managerMonthlyWage = currency.roundedStep(s.companies[i].managerMonthlyWage * (1 + raise), about: 100)
        }
        if !fx["stay"].isNull && !staff.isEmpty && !s.random.chance(fx["stay"].double) {
            let leaver = staff[targets[0]]
            s.companies[i].staff = s.companies[i].staff.filter { $0.id != leaver.id }
            if var p = s.people[leaver.id] { p.employerID = 0; s.people[leaver.id] = p }
            s.note("\(s.people[leaver.id]?.name ?? "A team member") left anyway.", tone: "bad", companyID: s.companies[i].id)
        }
    }

    /// Collect (or lose) the worst outstanding invoice. Original: the 'collect' effect.
    static func collectInvoice(_ s: inout GameState, _ i: Int, chance p: Double, data: GameData) {
        var list = s.companies[i].receivables
        guard let k = list.firstIndex(where: { $0.willDefault }) ?? list.indices.max(by: { list[$0].amount < list[$1].amount }) else { return }
        let r = list.remove(at: k)
        s.companies[i].receivables = list
        if s.random.chance(p) { Payments.companyReceives(&s, companyID: s.companies[i].id, amount: r.amount, category: nil, label: "Collected invoice") }
        else { writeOffInvoice(&s, i, amount: r.amount, data: data) }
    }

    /// An unpaid invoice (amount includes VAT): the net part is a loss, the VAT part is reclaimed. Original: `recvLoss`.
    static func writeOffInvoice(_ s: inout GameState, _ i: Int, amount gross: Double, data: GameData) {
        let w = World(state: s, data: data)
        let co = s.companies[i]
        guard let bd = w.trade(co) else { return }
        let vr = w.country(co).usesSalesTax ? 0 : Vat.rate(co, bd, w)
        let net = gross / (1 + vr)
        Payments.book(&s, companyID: co.id, category: "loss", amount: net)
        s.companies[i].vatBalance -= gross - net
    }
}
