import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Misconduct and political influence as optional, high-risk decisions. They use the strategic-decision engine
/// (`StrategicDecisions`: inbox message, defaults, `later` follow-ups); nothing runs beside it.
///
/// Misconduct (class "mis") pays now and bills later. Every act is a "case" kept on the company (`mis.cases`). Each week a case
/// can be found: the chance grows with the size of the business, with every repeat, and with how strict the country is
/// (`CountryTraits.politics`). The tax audit and inspection events (`g_audit`, `g_inspect`) also look for open cases.
/// When found: back taxes (if the tax year is closed), interest, a fine scaled to the gain, lost reputation and reviews,
/// worse loan terms, sometimes a stop to trading, and part of the fine falls on the owner personally.
///
/// Political influence (class "pol") costs real money up front, may do nothing, shifts one regulation-related cost by a few
/// percent for a set time at best, and can end in a scandal and a fine. It never guarantees a law.
///
/// All money moves through `Payments` (so the `Ledger` stays balanced). Concealed profit is kept in `evade` and read by
/// `MonthEnd.accrueTax`, which is the only place tax is worked out; the tax is therefore never paid twice.
public enum Misconduct {
    // MARK: Country strictness

    /// How strict enforcement is here (1 = average). Data: `country_traits.json` -> `politics`.
    static func enforcement(_ cc: String) -> Double { CountryTraits.politics(cc, "enforcement") }
    /// How open the country is to influence (1 = average).
    static func openness(_ cc: String) -> Double { CountryTraits.politics(cc, "openness") }

    // MARK: State on the company

    static func state(_ co: Company) -> JSONValue { co.value("mis").isNull ? .object([:]) : co.value("mis") }
    static func cases(_ co: Company) -> [JSONValue] { state(co)["cases"].array }
    public static func hasCases(_ co: Company, kinds: [String]? = nil) -> Bool {
        cases(co).contains { kinds == nil || kinds!.contains($0["k"].string) }
    }
    static func uses(_ co: Company) -> Int { state(co)["n"].int }

    static func setState(_ s: inout GameState, _ i: Int, _ st: JSONValue) { s.companies[i].set("mis", st) }

    /// Register an act. `gain` is what the company kept (tax saved, cost cut, interest saved, business won).
    static func register(_ s: inout GameState, _ i: Int, kind: String, gain: Double, extra: [String: JSONValue] = [:]) {
        var st = state(s.companies[i])
        var list = st["cases"].array
        var c: [String: JSONValue] = ["w": .number(Double(s.week)), "k": .string(kind), "g": .number(gain),
                                      "y": .number(Double(GameCalendar.year(week: s.week)))]
        for (k, v) in extra { c[k] = v }
        list.append(.object(c))
        st["cases"] = .array(list)
        st["n"] = .number(Double(st["n"].int + 1))
        setState(&s, i, st)
    }

    /// Profit kept out of this year's tax base (illegal `c` plus legal `l`). Read by `MonthEnd.accrueTax`.
    static func addConcealed(_ s: inout GameState, _ i: Int, legal: Bool, amount: Double) {
        let year = Double(GameCalendar.year(week: s.week))
        var ev = s.companies[i].value("evade").isNull ? JSONValue.object([:]) : s.companies[i].value("evade")
        if ev["y"].double != year { ev = .object(["y": .number(year), "c": 0, "l": 0]) }
        let k = legal ? "l" : "c"
        ev[k] = .number(ev[k].double + amount)
        s.companies[i].set("evade", ev)
    }

    // MARK: Risk

    static func yearRevenue(_ s: GameState, _ i: Int, data: GameData, context fc: FinanceContext) -> Double {
        let co = s.companies[i], k = fc.country(of: co, s)
        return EventEngine.context(for: co, data: data, employerFactor: k.employerCostFactor, costIndex: k.costIndex).wk * 52
    }

    /// Chance per week that open cases are found. Grows with size, with each repeat and with the country's strictness.
    static func weeklyRisk(_ s: GameState, _ i: Int, data: GameData, context fc: FinanceContext, extraActs: Int = 0) -> Double {
        let co = s.companies[i]
        let cur = fc.currency(co.countryCode, s)
        let rev = yearRevenue(s, i, data: data, context: fc)
        let size = clamp(0.6 + 0.35 * log10(max(1, rev / max(1, cur.scaledPrice(1_000_000)))), 0.6, 2.0)
        let n = uses(co) + extraActs
        let repeats = 1 + 0.5 * Double(max(0, n - 1))
        let watched = state(co)["watch"].int > s.week ? 1.5 : 1
        return min(0.04, 0.0025 * size * enforcement(co.countryCode) * repeats * watched)
    }

    static func yearlyRisk(_ s: GameState, _ i: Int, data: GameData, context fc: FinanceContext, extraActs: Int = 0) -> Double {
        1 - pow(1 - weeklyRisk(s, i, data: data, context: fc, extraActs: extraActs), 52)
    }

    static func pct(_ p: Double) -> String { "\(Int((p * 100).rounded()))%" }

    // MARK: The weekly turn

    /// Called every week from `StrategicDecisions.weekly`. Uses `HashedRandom`, so a game with no open case draws nothing.
    static func weekly(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        for i in s.companies.indices where s.companies[i].status == .open {
            var st = state(s.companies[i])
            guard !st["cases"].array.isEmpty else { continue }
            // Cases that nobody found in three years are closed.
            let live = st["cases"].array.filter { s.week - $0["w"].int < 156 }
            if live.count != st["cases"].array.count { st["cases"] = .array(live); setState(&s, i, st) }
            guard !live.isEmpty else { continue }
            let p = weeklyRisk(s, i, data: data, context: fc)
            if HashedRandom.first("mis:\(s.week):\(s.companies[i].id)") < p {
                investigate(&s, i, data: data, context: fc, cause: "A tip-off led to an investigation")
            }
        }
    }

    // MARK: Being found out

    /// Settle every open case of the company at once. Returns the total paid by the company.
    @discardableResult
    static func investigate(_ s: inout GameState, _ i: Int, data: GameData, context fc: FinanceContext, cause: String, kinds: [String]? = nil) -> Double {
        let co0 = s.companies[i]
        var st = state(co0)
        let all = st["cases"].array
        let hit = all.filter { kinds == nil || kinds!.contains($0["k"].string) }
        guard !hit.isEmpty else { return 0 }
        let cc = co0.countryCode, enf = enforcement(cc)
        let cur = fc.currency(cc, s), year = GameCalendar.year(week: s.week)
        let repeat0 = 1 + 0.2 * Double(min(4, max(0, st["n"].int - 1)))
        var back = 0.0, interest = 0.0, fine = 0.0, repLoss = 0.0, bank = false, closed = false
        var lines: [String] = []
        for c in hit {
            let g = c["g"].double
            switch c["k"].string {
            case "tax":
                let same = c["y"].int == year
                if same {
                    // This year's tax has not been paid yet: the concealment is removed and the ordinary accrual picks it up.
                    var ev = s.companies[i].value("evade")
                    if !ev.isNull { ev["c"] = .number(max(0, ev["c"].double - c["c"].double)); s.companies[i].set("evade", ev) }
                } else {
                    back += c["c"].double * c["r"].double
                }
                let yrs = max(0.25, Double(s.week - c["w"].int) / 52)
                interest += same ? g * 0.04 : g * 0.08 * yrs
                fine += g * (0.5 + 0.7 * enf)
                repLoss += 6
                lines.append("hidden takings")
            case "quality":
                fine += g * (0.8 + 0.6 * enf)
                repLoss += 8
                addMod(&s, i, "dem", 0.9, 12)
                addMod(&s, i, "cogsup", 1.04, 26)
                lines.append("cheaper, lower-grade inputs")
            case "bank":
                fine += max(g * (2 + enf), cur.scaledPrice(8000) * enf)
                repLoss += 5
                bank = true
                lines.append("flattering accounts shown to the bank")
            case "bribe":
                fine += (c["cost"].double * 3 + g * 2) * (0.6 + 0.6 * enf)
                repLoss += 15
                closed = true
                lines.append("payments to an official")
            default: break
            }
        }
        fine = jsRound(fine * repeat0)
        back = jsRound(back); interest = jsRound(interest)
        let id = co0.id
        let cash0 = s.companies[i].cash
        if back > 0 { _ = Payments.companyPays(&s, companyID: id, amount: back, category: "tax", label: "Back taxes") }
        if interest > 0 { _ = Payments.companyPays(&s, companyID: id, amount: interest, category: "int", label: "Interest on back taxes") }
        if fine > 0 { _ = Payments.companyPays(&s, companyID: id, amount: fine, category: "fine", label: "Penalty: misconduct") }
        // A good lawyer or a legal team can cut the penalty (`Payments.companyPays`): what was really paid is what is reported.
        let paidNow = max(0, cash0 - s.companies[i].cash)
        fine = max(0, paidNow - back - interest)
        s.companies[i].reputation = clamp(s.companies[i].reputation - repLoss, 0, 100)
        if bank {
            for l in s.loans.indices where s.loans[l].companyID == id && s.loans[l].kind != "start" && s.loans[l].balance > 0 { s.loans[l].margin += 0.02 }
            s.credit = clamp(s.credit - 12, 0, 100)
        }
        // A repeat offender, or a bribe, can lose the licence to trade for a while.
        if closed || st["n"].int >= 3 { addMod(&s, i, "cap", closed ? 0.5 : 0.3, 6); closed = true }
        // The owner answers personally for part of the penalty.
        var personal = 0.0
        if fine > 0 {
            personal = jsRound(fine * (co0.form == .soleTrader ? 0.35 : 0.2))
            if personal > 0 { Payments.playerPays(&s, personal, label: "Personal liability: \(co0.name)", companyID: id) }
        }
        st["cases"] = .array(all.filter { c in !hit.contains { $0["w"].int == c["w"].int && $0["k"].string == c["k"].string && $0["g"].double == c["g"].double } })
        st["caught"] = .number(Double(st["caught"].int + 1))
        st["watch"] = .number(Double(s.week + 104))
        setState(&s, i, st)
        let authority = fc.country(of: s.companies[i], s).pack["authorities"]["tax"].string
        var body = "\(cause) at \(co0.name): \(lines.joined(separator: ", ")). "
        if back > 0 { body += "Back taxes \(cur.display(back)). " }
        if interest > 0 { body += "Interest \(cur.display(interest)). " }
        body += "Penalty \(cur.display(fine)). "
        if personal > 0 { body += "You are personally liable for \(cur.display(personal)). " }
        if closed { body += "Trading is restricted for six weeks. " }
        body += "Reputation falls by \(Int(repLoss))" + (bank ? " and the bank raises your loan margins and marks your credit." : ".")
        s.addMessage(from: authority.isEmpty ? "Authorities" : authority, title: "Investigation at \(co0.name)", body: body, companyID: id, tone: "bad")
        s.note("Investigation at \(co0.name): \(cur.display(paidNow)) paid.", tone: "bad", companyID: id)
        return paidNow + personal
    }

    static func addMod(_ s: inout GameState, _ i: Int, _ k: String, _ m: Double, _ w: Double) { EventEngine.addModifier(&s, i, key: k, multiplier: m, weeks: w) }

    // MARK: Follow-ups (delayed outcomes)

    /// Runs the follow-ups queued with `StrategicDecisions.later`. Called from `followUpCorporate`'s default branch.
    static func followUp(_ s: inout GameState, id: String, index k: Int, d: JSONValue, data: GameData, context fc: FinanceContext) {
        let name = s.companies[k].name, cid = s.companies[k].id
        let cur = fc.currency(s.companies[k].countryCode, s)
        switch id {
        case "mis_bank_end":
            // The flattering accounts no longer count: the old margins come back.
            for v in d["ids"].array { if let l = s.loans.firstIndex(where: { $0.id == v.int }) { s.loans[l].margin += d["cut"].double } }
        case "mis_quality_leak":
            guard hasCases(s.companies[k], kinds: ["quality"]) else { return }
            if HashedRandom.first("misq:\(s.week):\(cid)") < 0.35 {
                s.companies[k].reputation = clamp(s.companies[k].reputation - 4, 0, 100)
                addMod(&s, k, "dem", 0.95, 12)
                s.note("Customers at \(name) say the food and goods have got worse; the reviews show it.", tone: "bad", companyID: cid)
            }
        case "pol_result":
            politicalResult(&s, k, d: d, cur: cur, data: data, context: fc)
        default: break
        }
    }

    /// The outcome of a donation or lobbying effort, some weeks after the money was spent. Never guaranteed.
    static func politicalResult(_ s: inout GameState, _ k: Int, d: JSONValue, cur: Currency, data: GameData, context fc: FinanceContext) {
        let co = s.companies[k], cc = co.countryCode, cid = co.id
        let tag = "pol:\(d["kind"].string):\(s.week):\(cid)"
        var r = HashedRandom(tag)
        let heat = state(co)["heat"].double
        // The scandal is rolled first: money in politics is news in every country, and more so where enforcement is strict.
        if r.next() < d["ps"].double {
            let fine = jsRound(d["spent"].double * d["fineMult"].double)
            _ = Payments.companyPays(&s, companyID: cid, amount: fine, category: "fine", label: "Penalty: political funding")
            s.companies[k].reputation = clamp(s.companies[k].reputation - 6, 0, 100)
            addMod(&s, k, "dem", 0.95, 8)
            var st = state(s.companies[k]); st["heat"] = .number(heat + 1); setState(&s, k, st)
            s.addMessage(from: "News", title: "Scandal: \(co.name) and political money", body: "The papers link \(co.name) to the \(d["what"].string). Penalty \(cur.display(fine)); reputation falls by 6 and sales dip for 8 weeks. Nothing was gained from the \(cur.display(d["spent"].double)) spent.", companyID: cid, tone: "bad")
            s.note("Political scandal at \(co.name): fined \(cur.display(fine)).", tone: "bad", companyID: cid)
            return
        }
        let pWin = d["pw"].double
        if r.next() < pWin {
            let m = d["m"].double, w = d["weeks"].double
            addMod(&s, k, "cogsup", m, w)
            s.addMessage(from: co.name, title: "The rules shift a little in \(co.name)'s favour", body: "A change to the compliance rules lowers your regulation-related costs by about \(Int(((1 - m) * 100).rounded()))% for \(Int(w)) weeks. It was not guaranteed, and it is not permanent.", companyID: cid, tone: "good")
            s.note("Political effort pays off for \(co.name): costs down \(Int(((1 - m) * 100).rounded()))% for \(Int(w)) weeks.", tone: "good", companyID: cid)
        } else {
            s.note("The \(d["what"].string) of \(co.name) changed nothing. The money is gone.", tone: "n", companyID: cid)
        }
    }

    // MARK: Gate for the monthly turn

    /// A hashed gate so that offering these decisions draws nothing from the main random stream. `chance` per attempt.
    static func gate(_ s: GameState, _ tag: String, _ chance: Double) -> Bool {
        HashedRandom.first("misgate:\(tag):\(s.week)") < chance
    }
}

extension StrategicDecisions {
    static func misconductDecisions() -> [Def] {
        var L: [Def] = []
        func scaledC(_ s: GameState, _ i: Int, _ fc: FinanceContext, _ v: Double) -> Double { fc.currency(s.companies[i].countryCode, s).scaledPrice(v) }
        func risk(_ s: GameState, _ i: Int, _ data: GameData, _ fc: FinanceContext) -> Double { Misconduct.yearlyRisk(s, i, data: data, context: fc, extraActs: 1) }

        // MARK: Tax: hidden takings (and the legal route)
        L.append(Def(id: "m_tax", cls: "mis", stages: ["grow", "est"], w: 2, tone: "n", from: "Your accountant", exp: 4, def: 2,
                     cond: { s, co, _ in co.form == .limited && ebit12(co, s) > 0 },
                     make: { s, i, data, fc in
                         let co = s.companies[i], profit = ebit12(co, s)
                         guard profit > scaledC(s, i, fc, 150_000) else { return nil }
                         let rate = fc.country(of: co, s).corporateTax
                         let conc = r1000(profit * 0.3), legal = r1000(profit * 0.12)
                         let save = conc * rate, lsave = legal * rate
                         return .object(["conc": num(conc), "save": num(save), "rate": num(rate), "legal": num(legal), "lsave": num(lsave),
                                         "fee": num(jsRound(lsave * 0.35)), "risk": num(risk(s, i, data, fc)),
                                         "fine": num(jsRound(save * (0.5 + 0.7 * Misconduct.enforcement(co.countryCode))))]) },
                     title: { co, _, _ in "Lower the tax bill of \(co.name)?" },
                     body: { _, d, cur in
                         "Your accountant sees a way to cut this year's company tax. "
                         + "1) Leave about \(cur.display(d["conc"].double)) of takings off the books: benefit about \(cur.display(d["save"].double)) less tax, felt at the next month end; cost nothing now; risk about \(Misconduct.pct(d["risk"].double)) a year of an investigation, rising with size and each repeat; if found you repay the tax with interest plus a penalty of about \(cur.display(d["fine"].double)), lose reputation and are personally liable for part of it. "
                         + "2) Use legal deductions: fee \(cur.display(d["fee"].double)), benefit about \(cur.display(d["lsave"].double)) less tax, no risk, effect at the next month end. "
                         + "3) Do nothing." },
                     opts: [
                        Opt(label: "Leave takings off the books", detail: "Saves tax now. Risk of investigation, back taxes and a penalty later.") { s, x in
                            Misconduct.addConcealed(&s, x.i, legal: false, amount: x.d["conc"].double)
                            Misconduct.register(&s, x.i, kind: "tax", gain: x.d["save"].double, extra: ["c": num(x.d["conc"].double), "r": num(x.d["rate"].double)])
                            s.note("\(s.companies[x.i].name) holds back \(x.cur.display(x.d["conc"].double)) of takings. Tax falls by about \(x.cur.display(x.d["save"].double)) at the next month end.", tone: "n", companyID: s.companies[x.i].id) },
                        Opt(label: "Use legal deductions", detail: "A fee now, a smaller but safe saving.") { s, x in
                            pay(&s, x, x.d["fee"].double, "acc", "Tax adviser")
                            Misconduct.addConcealed(&s, x.i, legal: true, amount: x.d["legal"].double)
                            s.note("Legal deductions cut the tax of \(s.companies[x.i].name) by about \(x.cur.display(x.d["lsave"].double)).", tone: "good", companyID: s.companies[x.i].id) },
                        Opt(label: "Keep the books as they are", detail: "No gain, no risk.") { _, _ in }]))

        // MARK: Quality shortcut
        L.append(Def(id: "m_quality", cls: "mis", stages: ["start", "grow", "est"], w: 2, from: "A supplier", exp: 4, def: 2,
                     cond: { _, co, data in (data.catalog[co.type].map(hasGoods) ?? false) && co.quality > 25 },
                     make: { s, i, data, fc in
                         let co = s.companies[i]
                         guard let bd = data.catalog[co.type] else { return nil }
                         let rev = Misconduct.yearRevenue(s, i, data: data, context: fc)
                         let cogs = rev * bd.costOfSales
                         let save = jsRound(cogs * 0.07)
                         guard save > scaledC(s, i, fc, 6000) else { return nil }
                         return .object(["save": num(save), "risk": num(risk(s, i, data, fc)), "lsave": num(jsRound(cogs * 0.015)),
                                         "fee": num(scaledC(s, i, fc, 3000)),
                                         "fine": num(jsRound(save * (0.8 + 0.6 * Misconduct.enforcement(co.countryCode))))]) },
                     title: { co, _, _ in "Cheaper inputs for \(co.name)" },
                     body: { _, d, cur in
                         "A supplier offers inputs that are cheaper and clearly below what you advertise. "
                         + "1) Switch quietly: benefit about \(cur.display(d["save"].double)) a year in lower costs (7%) for 52 weeks; cost: quality falls by 4 points at once; risk about \(Misconduct.pct(d["risk"].double)) a year of an inspection finding it, then a penalty of about \(cur.display(d["fine"].double)), reputation -8 and weaker reviews for 12 weeks; even unseen, customers may notice within about 26 weeks. "
                         + "2) Renegotiate with your current supplier: cost \(cur.display(d["fee"].double)), maybe 1.5% off (about \(cur.display(d["lsave"].double)) a year) for 26 weeks if they agree, no risk. "
                         + "3) Keep the quality." },
                     opts: [
                        Opt(label: "Switch quietly to cheaper inputs", detail: "Saves cost now; quality drops and an inspection could find it.") { s, x in
                            cost(&s, x, 0.93, 52)
                            s.companies[x.i].quality = clamp(s.companies[x.i].quality - 4, 0, 100)
                            Misconduct.register(&s, x.i, kind: "quality", gain: x.d["save"].double)
                            later(&s, 26, "mis_quality_leak", x.i, .null)
                            s.note("\(s.companies[x.i].name) buys cheaper inputs. Costs fall about 7% for a year.", tone: "n", companyID: s.companies[x.i].id) },
                        Opt(label: "Renegotiate with the supplier", detail: "A small, honest saving; they may say no.") { s, x in
                            pay(&s, x, x.d["fee"].double, "oth", "Supplier negotiation")
                            if HashedRandom.first("misneg:\(s.week):\(s.companies[x.i].id)") < 0.5 { cost(&s, x, 0.985, 26); s.note("The supplier agreed a small discount.", tone: "good", companyID: s.companies[x.i].id) }
                            else { s.note("The supplier would not move on price.", tone: "n", companyID: s.companies[x.i].id) } },
                        Opt(label: "Keep the quality", detail: "No saving, no risk.") { _, _ in }]))

        // MARK: Flattering accounts for the bank
        L.append(Def(id: "m_bank", cls: "mis", stages: ["grow", "est"], w: 2, from: "The bank", exp: 4, def: 2,
                     cond: { s, co, _ in s.loans.contains { $0.companyID == co.id && $0.kind != "start" && $0.balance > 150_000 } },
                     make: { s, i, data, fc in
                         let co = s.companies[i]
                         let ls = s.loans.filter { $0.companyID == co.id && $0.kind != "start" && $0.balance > 150_000 }
                         let bal = ls.reduce(0) { $0 + $1.balance }
                         guard bal > scaledC(s, i, fc, 150_000) else { return nil }
                         return .object(["bal": num(bal), "save": num(jsRound(bal * 0.006)), "lsave": num(jsRound(bal * 0.002)),
                                         "fee": num(scaledC(s, i, fc, 12000)), "ids": .array(ls.map { num(Double($0.id)) }),
                                         "risk": num(risk(s, i, data, fc)),
                                         "fine": num(jsRound(max(bal * 0.006 * (2 + Misconduct.enforcement(co.countryCode)), scaledC(s, i, fc, 8000))))]) },
                     title: { co, _, _ in "The bank reviews the loans of \(co.name)" },
                     body: { _, d, cur in
                         "The bank reviews your \(cur.display(d["bal"].double)) of loans and will price them by your latest figures. "
                         + "1) Present flattering accounts (costs pushed into next year, sales pulled forward): benefit about \(cur.display(d["save"].double)) a year in interest (0.6 points off) for 52 weeks; no cost now; risk about \(Misconduct.pct(d["risk"].double)) a year of being found out, then a penalty of about \(cur.display(d["fine"].double)), a 2 point higher margin, a lower credit score and reputation -5. "
                         + "2) Pay for audited accounts: cost \(cur.display(d["fee"].double)), 0.2 points off (about \(cur.display(d["lsave"].double)) a year) for 52 weeks, no risk. "
                         + "3) Show the accounts as they are." },
                     opts: [
                        Opt(label: "Present flattering accounts", detail: "Cheaper loans for a year; a risk of fraud findings.") { s, x in
                            let cut = 0.006
                            var ids: [JSONValue] = []
                            for v in x.d["ids"].array { if let l = s.loans.firstIndex(where: { $0.id == v.int }) { s.loans[l].margin = max(0.002, s.loans[l].margin - cut); ids.append(v) } }
                            Misconduct.register(&s, x.i, kind: "bank", gain: x.d["save"].double)
                            later(&s, 52, "mis_bank_end", x.i, .object(["ids": .array(ids), "cut": num(cut)]))
                            s.note("The bank cuts the loan margins of \(s.companies[x.i].name) by 0.6 points for a year.", tone: "n", companyID: s.companies[x.i].id) },
                        Opt(label: "Pay for audited accounts", detail: "A fee now and a small, safe cut in interest.") { s, x in
                            pay(&s, x, x.d["fee"].double, "acc", "Audit fee")
                            let cut = 0.002
                            var ids: [JSONValue] = []
                            for v in x.d["ids"].array { if let l = s.loans.firstIndex(where: { $0.id == v.int }) { s.loans[l].margin = max(0.002, s.loans[l].margin - cut); ids.append(v) } }
                            later(&s, 52, "mis_bank_end", x.i, .object(["ids": .array(ids), "cut": num(cut)])) },
                        Opt(label: "Show the accounts as they are", detail: "No gain, no risk.") { _, _ in }]))

        // MARK: A bribe
        L.append(Def(id: "m_bribe", cls: "mis", stages: ["grow", "est"], w: 1, from: "An official", exp: 3, def: 2,
                     cond: { _, co, data in (data.catalog[co.type]?.businessShare ?? 0) > 0.1 || co.staff.count >= 5 },
                     make: { s, i, data, fc in
                         let co = s.companies[i]
                         let rev = Misconduct.yearRevenue(s, i, data: data, context: fc)
                         let cost = jsRound(max(scaledC(s, i, fc, 15000), rev * 0.01))
                         let p = clamp(0.45 * Misconduct.openness(co.countryCode), 0.2, 0.7)
                         return .object(["cost": num(cost), "gain": num(jsRound(rev * 0.06 * 0.5)), "p": num(p), "risk": num(risk(s, i, data, fc)),
                                         "fine": num(jsRound((cost * 3 + rev * 0.06) * (0.6 + 0.6 * Misconduct.enforcement(co.countryCode))))]) },
                     title: { co, _, _ in "An official offers \(co.name) a favour" },
                     body: { _, d, cur in
                         "A public buyer's official hints that a big order for you is easier if a 'consulting fee' is paid. "
                         + "1) Pay: cost \(cur.display(d["cost"].double)) now, gone whatever happens; benefit: with \(Misconduct.pct(d["p"].double)) chance sales are 6% higher for 26 weeks (about \(cur.display(d["gain"].double))), otherwise nothing; risk about \(Misconduct.pct(d["risk"].double)) a year of a criminal investigation, then a penalty of about \(cur.display(d["fine"].double)), reputation -15, trading restricted for 6 weeks and personal liability for you. "
                         + "2) Report it: reputation +2 for integrity, nothing else. "
                         + "3) Decline quietly." },
                     opts: [
                        Opt(label: "Pay the 'fee'", detail: "May win the order. Bribery is prosecuted hard.") { s, x in
                            pay(&s, x, x.d["cost"].double, "oth", "Consulting fee")
                            let won = HashedRandom.first("misbribe:\(s.week):\(s.companies[x.i].id)") < x.d["p"].double
                            if won { dem(&s, x, 1.06, 26) }
                            Misconduct.register(&s, x.i, kind: "bribe", gain: won ? x.d["gain"].double : 0, extra: ["cost": num(x.d["cost"].double)])
                            s.note(won ? "The order comes through for \(s.companies[x.i].name)." : "The official takes the money and the order never comes.", tone: won ? "n" : "bad", companyID: s.companies[x.i].id) },
                        Opt(label: "Report it", detail: "No gain; a small boost to your name.") { s, x in rep(&s, x, 2) },
                        Opt(label: "Decline quietly", detail: "Nothing happens.") { _, _ in }]))

        // MARK: Political donation and lobbying
        func politics(_ id: String, title: String, from: String, what: String, kind: String, spendPct: Double, floor: Double, p: Double, m: Double, weeks: Double, scandal: Double, fineMult: Double, w: Double) -> Def {
            Def(id: id, cls: "pol", stages: ["grow", "est"], w: w, from: from, exp: 4, def: 1,
                cond: { s, co, _ in ebit12(co, s) > 0 },
                make: { s, i, data, fc in
                    let co = s.companies[i]
                    guard ebit12(co, s) > scaledC(s, i, fc, 100_000) else { return nil }
                    let rev = Misconduct.yearRevenue(s, i, data: data, context: fc)
                    let spent = jsRound(max(scaledC(s, i, fc, floor), rev * spendPct))
                    let pw = clamp(p * Misconduct.openness(co.countryCode), 0.05, 0.75)
                    let ps = clamp(scandal * Misconduct.enforcement(co.countryCode) * (1 + 0.15 * Misconduct.state(co)["heat"].double), 0, 0.5)
                    return .object(["spent": num(spent), "p": num(p), "pw": num(pw), "ps": num(ps), "m": num(m), "weeks": num(weeks),
                                    "scandal": num(scandal), "fineMult": num(fineMult), "what": .string(what), "kind": .string(kind),
                                    "fine": num(jsRound(spent * fineMult))]) },
                title: { _, _, _ in title },
                body: { co, d, cur in
                    "Cost: \(cur.display(d["spent"].double)) now, not refundable. "
                    + "Benefit: with about \(Misconduct.pct(d["pw"].double)) chance the rules shift and your regulation-related costs fall \(Int(((1 - d["m"].double) * 100).rounded()))% for \(Int(d["weeks"].double)) weeks; otherwise nothing. No law is guaranteed. "
                    + "Risk: about \(Misconduct.pct(d["ps"].double)) chance of a scandal: penalty about \(cur.display(d["fine"].double)), reputation -6, sales dip for 8 weeks, and more attention from the authorities. "
                    + "Timing: the answer comes in 8 weeks. Staying out costs nothing." },
                opts: [
                    Opt(label: "Go ahead", detail: "Real money, an uncertain and limited effect, a scandal risk.") { s, x in
                        pay(&s, x, x.d["spent"].double, "oth", what.prefix(1).uppercased() + String(what.dropFirst()))
                        var st = Misconduct.state(s.companies[x.i]); st["heat"] = .number(st["heat"].double + 0.5); Misconduct.setState(&s, x.i, st)
                        later(&s, 8, "pol_result", x.i, x.d) },
                    Opt(label: "Stay out of it", detail: "No cost, no risk, no effect.") { _, _ in }])
        }
        let donate = politics("m_pol_donate", title: "A party asks for a donation", from: "A party fundraiser", what: "party donation", kind: "donate",
                              spendPct: 0.004, floor: 20_000, p: 0.4, m: 0.985, weeks: 78, scandal: 0.10, fineMult: 2, w: 1)
        let lobby = politics("m_pol_lobby", title: "Join an industry lobbying group?", from: "Industry association", what: "lobbying fee", kind: "lobby",
                             spendPct: 0.006, floor: 30_000, p: 0.35, m: 0.99, weeks: 104, scandal: 0.05, fineMult: 1, w: 1)
        // "Stay out" is the last answer and the default when nobody answers in time.
        L.append(donate); L.append(lobby)
        return L
    }
}
