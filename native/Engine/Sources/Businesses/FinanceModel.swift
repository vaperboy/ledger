import Foundation
import GameCore
import Countries
import Employees
import Finance

/// One kind of insurance a company can sell. Original: `INS_PRODS` entries (engine/company/sales_insurance.js).
public struct InsuranceProduct: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// How much business the product brings, relative to the average.
    public var volume: Double
    /// Premium level against the standard premium.
    public var premium: Double
    /// Claims against premiums (loss ratio factor).
    public var lossFactor: Double
    /// The approval the regulator requires.
    public var documentID: String
    /// What it costs to verify one salesperson for this product.
    public var verificationCost: Double
}

/// A finance company's own book, with the numbers the screen shows. Original: `co.fm` of `FAM.fin`.
public struct FinanceBook: Equatable, Sendable {
    public enum Kind: String, Sendable { case insurer, bank, fund }
    public var kind: Kind
    // Insurer
    public var policies = 0.0, weeklyPremium = 0.0, lossRatio = 0.0, solvency = 0.0, claimsPaidByStorms = 0.0
    // Bank
    public var deposits = 0.0, loans = 0.0, groupLoans = 0.0, capitalRatio = 0.0, requiredRatio = 0.0, equity = 0.0, centralBankLoan = 0.0
    // Fund
    public var assetsUnderManagement = 0.0, unitValue = 1.0, highWaterMark = 1.0, managementFee = 0.0, performanceFee = 0.0
    /// The regulator is restricting the company.
    public var underRegulator = false
}

/// Insurance company, bank and investment fund. Original: `FAM.fin` (engine/company/family_finance.js), the insurance
/// products (sales_insurance.js), the finance events `f_storm`, `f_run`, `f_default` (events/engine.js, people/before_hiring.js)
/// and the central bank's liquidity facility (world/bank_liquidity.js).
public enum FinanceModel {
    /// The order the original lists them in (sums are taken in this order).
    public static let productOrder = ["life", "property", "motor", "home", "travel", "business"]
    /// What `autoIns` switches on and verifies: the original's car, home and property products.
    public static let starterProducts = ["motor", "home", "property"]

    public static func products(_ tables: TradeTables) -> [InsuranceProduct] {
        let raw = tables.raw["INS_PRODS"]
        return productOrder.compactMap { k in
            let e = raw[k]
            if e.isNull { return nil }
            let p = e[1]
            return InsuranceProduct(id: k, name: e[0].string, volume: p["vol"].double, premium: p["prem"].double, lossFactor: p["lr"].double,
                                    documentID: p["doc"].string, verificationCost: p["ver"].double)
        }
    }

    // MARK: Staff

    /// How fully the standard team is in place: the average of each role's cover. Original: `finStaffCover`.
    static func staffCover(_ co: Company, _ bd: Trade, _ w: World, people: [Int: Person]) -> Double {
        if bd.standardStaff.isEmpty { return 1 }
        var q = 0.0
        for s in bd.standardStaff {
            let have = fte(co, s.role, w, people)
            q += min(1, have / max(0.5, s.count * co.size))
        }
        return q / Double(bd.standardStaff.count)
    }

    static func fte(_ co: Company, _ role: String, _ w: World, _ people: [Int: Person]) -> Double {
        StaffModel.fullTimeEquivalents(role: role, staff: co.staff, people: people, week: w.week, salesRoles: w.catalog.tables.salesRoles)
    }

    /// Verified salespeople for a product. Original: `verAgents`.
    public static func verifiedAgents(_ co: Company, product k: String, week: Int, people: [Int: Person], salesRoles: Set<String>) -> Double {
        var t = 0.0
        for s in co.staff where s.role == "agent" {
            let v = s.value("ver")[k]
            if !v.isNull && v["done"].double <= Double(week) { t += 0.92 * (0.75 + 0.5 * StaffModel.skill(s, person: people[s.id], salesRoles: salesRoles) / 100) }
        }
        return t
    }

    public static func isOffered(_ co: Company, _ k: String) -> Bool { co.value("fm")["prods"][k].bool }

    // MARK: Weekly

    /// The week of an insurance company, bank or fund. Original: `FAM.fin.custom`.
    static func weekly(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData) -> CompanyWeek.WeekContext {
        if bd.hasTrait("bank") { bankLiquidity(&s, i) }
        if bd.hasTrait("ins") { return insurance(&s, i, bd, data: data) }
        if bd.hasTrait("bank") { return bank(&s, i, bd, data: data) }
        return fund(&s, i, bd, data: data)
    }

    static func insurance(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData) -> CompanyWeek.WeekContext {
        var co = s.companies[i]
        var fm = co.value("fm")
        let w = World(state: s, data: data)
        let people = s.people
        let tables = w.catalog.tables
        let policiesBase = bd.trait("policies") ?? 30000, premiumBase = bd.trait("premium") ?? 5200, lossBase = bd.trait("lossR") ?? 0.66
        var pol = fm["pol"].double
        let cover = staffCover(co, bd, w, people: people)
        let uw = fte(co, "underw", w, people) / max(0.5, 3 * co.size)
        var W = 0.0, Wp = 0.0, Wl = 0.0
        for p in products(tables) {
            // A product counts once it is switched on and approved.
            guard fm["prods"][p.id].bool, Knobs.documentOK(co, p.documentID) else { continue }
            let cv = clamp(verifiedAgents(co, product: p.id, week: w.week, people: people, salesRoles: tables.salesRoles) / max(0.8, 1.2 * co.size), 0, 1)
            let wt = p.volume * (0.15 + 0.85 * cv)
            W += wt; Wp += wt * p.premium; Wl += wt * p.lossFactor
        }
        let pm = W != 0 ? Wp / W : 1, lmx = W != 0 ? Wl / W : 1, volF = W / 3
        let price = premiumBase * pm * Knobs.effect(co, bd, "t", w) * (1 + 0.08 * co.priceLevel) * w.inflationIndex
        let rm = Competition.rivalFactor(co, w)
        var target = volF * policiesBase * co.size * DemandModel.awarenessFactor(co) * (0.6 + 0.8 * co.reputation / 100) * Knobs.effect(co, bd, "d", w)
            * Pricing.demandEffect(co, bd, w) * rm * DemandModel.modifier(co, "dem") * (1 + (w.economy.demand - 1) * 0.4)
        let sol0 = fm["sol"].isNull ? 1.5 : fm["sol"].double
        if sol0 < 1 { target *= 0.5 }
        let cap = policiesBase * co.size * 1.3 * min(1, cover + 0.15)
        target = min(target, cap)
        pol += (target - pol) * 0.025
        pol = clamp(pol, 0, cap)
        let prem = pol * price / 52
        let catW = co.value("flags")["catW"].double
        let claimsStaff = fte(co, "claims", w, people)
        let noise = 1 + s.random.gauss() * 0.14 / sqrt(max(1, pol / 1000))
        let lr = lossBase * lmx * Knobs.effect(co, bd, "r", w) * (1.12 - 0.3 * clamp(uw, 0, 1.2))
            * (1 + (1 - min(1, claimsStaff / max(0.5, 5 * co.size))) * 0.12) * noise * (catW > 0 ? 1.5 : 1)
        let claims = prem * (lr + 0.12 * (0.8 + 0.2 * min(1, cover)))
        // Only the float (reserves and solvency capital) earns investment income; idle owner cash does not.
        let invInc = min(max(0, co.cash), prem * 52 * 2.5) * max(0, s.economy.policyRate - 0.008) / 52
        fm["pol"] = .number(pol)
        fm["premW"] = .number(prem)
        fm["lossR"] = .number(lr)
        let annual = prem * 52 + 1
        let sol = (co.cash - (co.payables["other"] ?? 0)) / (annual * 0.4)
        fm["sol"] = .number(sol)
        fm["assets"] = 0
        fm["cover"] = .number(cover)
        co.set("fm", fm)
        var flags = co.value("flags")
        if sol < 0.8 && !flags["reg"].bool {
            flags["reg"] = 1
            s.note("{auth:fin} restricts \(co.name): solvency too low. Add capital.", tone: "bad", companyID: co.id)
        }
        if sol > 1.0 { flags["reg"] = 0 }
        if catW > 0 { flags["catW"] = .number(catW - 1) }
        co.set("flags", flags)
        s.companies[i] = co
        return CompanyWeek.WeekContext(units: pol, rev: prem + invInc, cogs: claims, D: target, cap: cap, util: cap != 0 ? pol / cap : 0, price: price, paidDuringWeek: 0)
    }

    static func bank(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData) -> CompanyWeek.WeekContext {
        let id = s.companies[i].id
        var co = s.companies[i]
        var fm = co.value("fm")
        let w = World(state: s, data: data)
        let people = s.people
        let capital = bd.trait("capital") ?? 400_000_000, capReq = bd.trait("capitalReq") ?? 0.16, nim = bd.trait("nim") ?? 0.031
        let policy = s.economy.policyRate
        var dep = fm["dep"].double, book = fm["book"].double
        let gb = fm["gb"].double
        let cover = staffCover(co, bd, w, people: people)
        let equity = co.cash + book + gb - dep
        let wholesale = co.value("knob")["liq"].int == 1
        let depT = capital * 5 * co.size * DemandModel.awarenessFactor(co) * (0.6 + 0.8 * co.reputation / 100) * (wholesale ? 0.7 : 1)
            * Competition.rivalFactor(co, w) * DemandModel.modifier(co, "dem")
        // A bank only pays for the deposits it can lend out (plus a liquidity reserve); beyond that it lowers its deposit rate and the money goes elsewhere.
        let depNeed = max(0, equity) / capReq * 0.85 / 0.9 + max(0, equity) * 0.3
        // Wholesale money comes faster, but is only raised for loans actually made.
        let depTarget = min(min(depT * (wholesale ? 1.3 : 1), depNeed), wholesale ? book * 1.15 + max(0, equity) * 0.25 + 1e7 : Double.infinity)
        dep += (depTarget - dep) * (wholesale ? 0.05 : 0.02)
        let room = min(min(equity / capReq * 0.85 - book - gb, max(0, dep * 0.9 - book - gb + equity * 0.5)), (co.cash > 0 ? co.cash : 0) * 0.9)
        let demand = max(0, (depT / (wholesale ? 0.7 : 1) * 0.85 - book) * (wholesale ? 0.06 : 0.04) * Knobs.effect(co, bd, "d", w) * (w.economy.demand * 1.0) * min(1, cover + 0.2))
        let add = min(room, demand)
        book += max(0, add)
        let loanM = (nim + 0.012) * Knobs.effect(co, bd, "t", w)
        let rIn = book * (policy + loanM * 0.62) / 52
        let dr = dep * max(0, policy - 0.006 + (wholesale ? 0.012 : 0)) / 52
        let creditStaff = fte(co, "credit", w, people) / max(0.5, 3 * co.size)
        let baseLoss = 0.0035 * Knobs.effect(co, bd, "r", w) * (1 + max(0, 1 - w.economy.demand) * 8) * (1.1 - 0.4 * (creditStaff > 1 ? 1 : creditStaff))
        let loss = book * baseLoss / 52 * (1 + s.random.gauss() * 0.3)
        book = max(0, book - loss)
        fm["dep"] = .number(dep); fm["book"] = .number(book); fm["gb"] = .number(gb)
        co.set("fm", fm)
        s.companies[i] = co
        Ledger.moveRaw(&s, .company(id), -max(0, add))
        // Liquidity reserves earn interest; surplus owner cash does not.
        let cashInt = min(max(0, s.companies[i].cash), dep * 0.35) * max(0, policy - 0.004) / 52
        Payments.book(&s, companyID: id, category: "loss", amount: loss)
        // Deposits flow in as cash: the change in deposits.
        let dd = dep - fm["depPrev"].double
        Ledger.moveRaw(&s, .company(id), dd)
        co = s.companies[i]
        fm["depPrev"] = .number(dep)
        let cr = equity / max(1, book + gb)
        fm["cr"] = .number(cr)
        fm["equity"] = .number(equity)
        fm["assets"] = .number(book + gb)
        fm["liab"] = .number(dep)
        fm["cover"] = .number(cover)
        co.set("fm", fm)
        var flags = co.value("flags")
        if cr < capReq * 0.5 && !flags["reg"].bool {
            flags["reg"] = 1
            s.note("{auth:fin} warns \(co.name): capital ratio \(Currency.percent(cr, decimals: 1)). Add capital or shrink.", tone: "bad", companyID: id)
        }
        if cr > capReq * 0.7 { flags["reg"] = 0 }
        co.set("flags", flags)
        s.companies[i] = co
        let util = depT != 0 ? dep / depT : 0
        return CompanyWeek.WeekContext(units: book / 1e6, rev: rIn + cashInt, cogs: dr, D: depT, cap: depT, util: util, price: 0, paidDuringWeek: 0)
    }

    static func fund(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData) -> CompanyWeek.WeekContext {
        let id = s.companies[i].id
        var co = s.companies[i]
        var fm = co.value("fm")
        let w = World(state: s, data: data)
        let people = s.people
        let mgmt = bd.trait("mgmt") ?? 0.015, perf = bd.trait("perf") ?? 0.2
        var aum = fm["aum"].double
        let hwm = fm["hwm"].double == 0 ? 1 : fm["hwm"].double
        var nav = fm["nav"].double == 0 ? 1 : fm["nav"].double
        let an = fte(co, "analyst", w, people) / max(0.5, 2 * co.size)
        let mgrQ = co.managerID != nil ? ManagerModel.quality(co, bd, people: people) : 0
        let aq = clamp(0.4 + 0.6 * min(1, an), 0.3, 1.2) * (co.managerID != nil ? 0.8 + 0.4 * mgrQ : 0.85 + co.ownerSkill / 400)
        let strat = min(2, max(0, co.value("knob")["strat"].int))
        let mret = s.rest["idxRet"]?.double ?? 0
        let beta = [0.9, 1.0, 0.7][strat]
        let alpha = [0.0005, 0.0018, 0.0022][strat] * (aq - 0.6) * 4 + (strat == 2 ? s.random.gauss() * 0.01 : s.random.gauss() * 0.003)
        let r = mret * beta + alpha - mgmt / 52
        nav *= (1 + r)
        aum *= (1 + r)
        let nav52 = fm["nav52"].double == 0 ? 1 : fm["nav52"].double
        let target = 650e6 * co.size * (co.awareness / 50 + 0.2) * (co.reputation / 50) * Knobs.effect(co, bd, "d", w) * min(1.6, max(0.4, nav / nav52)) * w.economy.demand
        aum += (target - aum) * 0.055
        aum = max(0, aum)
        if w.week % 52 == 0 { fm["nav52"] = .number(nav) }
        // The fee level (the fees knob).
        let fee = aum * mgmt / 52 * Knobs.effect(co, bd, "t", w)
        fm["aum"] = .number(aum); fm["nav"] = .number(nav); fm["hwm"] = .number(hwm); fm["aq"] = .number(aq)
        var performanceFee = 0.0
        if GameCalendar.isYearEnd(week: w.week) {
            if nav > hwm * 1.04 {
                let gain = (nav - hwm * 1.04) / hwm * aum / (nav / hwm)
                performanceFee = max(0, gain * perf)
                fm["hwm"] = .number(nav)
            } else {
                fm["hwm"] = .number(max(hwm, nav * 0.99))
            }
        }
        co.set("fm", fm)
        s.companies[i] = co
        if performanceFee > 0 {
            Payments.companyReceives(&s, companyID: id, amount: performanceFee, category: "rev", label: "Performance fee")
            s.note("Performance fee earned at \(co.name): {m:\(Int(jsRound(performanceFee)))}.", tone: "good", companyID: id)
        }
        return CompanyWeek.WeekContext(units: aum / 1e6, rev: fee, cogs: 0, D: target, cap: target, util: 0.7, price: 0, paidDuringWeek: 0)
    }

    // MARK: Central bank liquidity facility

    /// A solvent bank hit by a run borrows from the central bank against its loans, and repays as deposits come back.
    /// Original: `R24.bankLiquidity` (world/bank_liquidity.js).
    static func bankLiquidity(_ s: inout GameState, _ i: Int) {
        let co = s.companies[i]
        guard co.status == .open || co.status == .closed else { return }
        let fm = co.value("fm")
        guard !fm.isNull, !fm.object.isEmpty else { return }
        let dep = fm["dep"].double, book = fm["book"].double
        let eq = fm["equity"].isNull ? co.cash + book - dep : fm["equity"].double
        let facility = s.loans.filter { $0.companyID == co.id && $0.flag("cb") }
        let have = facility.reduce(0) { $0 + $1.balance }
        if co.cash < dep * 0.03 && eq > 0 {
            let want = dep * 0.08 - co.cash, room = book * 0.5 - have
            let amt = jsRound(min(want, room) / 1e5) * 1e5
            if amt > 0 {
                var l = Loan(raw: [:])
                l.id = s.makeID(); l.kind = "biz"; l.name = "Central bank liquidity facility"
                l.balance = amt; l.originalAmount = amt; l.margin = 0.01
                l.termMonths = 12; l.companyID = co.id; l.startWeek = s.week + 26; l.graceUntilWeek = s.week + 26
                l.isGuaranteed = false; l.bankCompanyID = 0
                l.set("cb", 1)
                l.monthlyPayment = Loans.annuity(principal: amt, yearlyRate: s.economy.policyRate + 0.01, months: 12)
                s.loans.append(l)
                Payments.companyReceives(&s, companyID: co.id, amount: amt, category: nil, label: "Loan drawn")
                let last = co.value("flags")["cb24"]
                if last.isNull || Double(s.week) - last.double > 26 {
                    var flags = s.companies[i].value("flags"); flags["cb24"] = .number(Double(s.week)); s.companies[i].set("flags", flags)
                    s.note("\(co.name) borrows {m:\(Int(amt))} from the central bank to meet withdrawals. It is repaid as deposits return.", tone: "bad", companyID: co.id)
                }
            }
        } else if have > 0 && co.cash > dep * 0.15 {
            var x = min(have, co.cash - dep * 0.12)
            for l in facility {
                let p = min(l.balance, x)
                if p > 0 {
                    Payments.companyPays(&s, companyID: co.id, amount: p, category: nil, label: "Central bank facility repaid")
                    if let k = s.loans.firstIndex(where: { $0.id == l.id }) { s.loans[k].balance -= p }
                    x -= p
                }
            }
            s.loans.removeAll { $0.flag("cb") && $0.balance < 1 }
        }
    }

    // MARK: Products

    public enum ProductResult: Equatable { case ok, notEnoughCash, unknown }

    /// Start or stop selling a product; starting applies for the regulator's approval. Original: `setProd`.
    @discardableResult
    public static func setProduct(_ s: inout GameState, companyID: Int, product k: String, on: Bool, data: GameData) -> ProductResult {
        guard let i = s.companyIndex(companyID), let p = products(data.catalog.tables).first(where: { $0.id == k }) else { return .unknown }
        var fm = s.companies[i].value("fm")
        var prods = fm["prods"].object
        if on {
            prods[k] = 1
            fm["prods"] = .object(prods)
            s.companies[i].set("fm", fm)
            let r = Documents.apply(p.documentID, companyID: companyID, state: &s, data: data)
            if r == .notEnoughCash {
                var f2 = s.companies[i].value("fm"); var pr = f2["prods"].object; pr[k] = nil; f2["prods"] = .object(pr); s.companies[i].set("fm", f2)
                return .notEnoughCash
            }
            return .ok
        }
        prods[k] = nil
        fm["prods"] = .object(prods)
        s.companies[i].set("fm", fm)
        return .ok
    }

    /// Verify one salesperson for one product (a few weeks). Original: `verifyAgent`.
    @discardableResult
    public static func verifyAgent(_ s: inout GameState, companyID: Int, staffID: Int, product k: String, data: GameData) -> ProductResult {
        guard let i = s.companyIndex(companyID), let p = products(data.catalog.tables).first(where: { $0.id == k }),
              let n = s.companies[i].staff.firstIndex(where: { $0.id == staffID }) else { return .unknown }
        if s.companies[i].cash < p.verificationCost { return .notEnoughCash }
        Payments.companyPays(&s, companyID: companyID, amount: p.verificationCost, category: "oth", label: "Verification: \(p.name)")
        var staff = s.companies[i].staff
        var ver = staff[n].value("ver")
        ver[k] = .object(["done": .number(Double(s.week + s.random.int(2, 4)))])
        staff[n].set("ver", ver)
        s.companies[i].staff = staff
        return .ok
    }

    /// Switch on the starter products and verify every salesperson for them. Original: `autoIns`.
    static func startInsurer(_ s: inout GameState, companyID: Int, data: GameData) {
        for k in starterProducts { setProduct(&s, companyID: companyID, product: k, on: true, data: data) }
        guard let i = s.companyIndex(companyID) else { return }
        for m in s.companies[i].staff where m.role == "agent" {
            for k in starterProducts {
                let cur = s.company(companyID)?.staff.first(where: { $0.id == m.id })
                if cur?.value("ver")[k].isNull ?? true { verifyAgent(&s, companyID: companyID, staffID: m.id, product: k, data: data) }
            }
        }
    }

    // MARK: Events

    /// Events with their own logic. Returns true if handled. Original: `SPEC.f_storm`, `SPEC.f_run`, `SPEC.f_default`.
    public static func specialEvent(_ id: String, _ s: inout GameState, _ i: Int, data: GameData) -> Bool {
        guard let bd = data.catalog[s.companies[i].type] else { return false }
        let co = s.companies[i]
        let fm = co.value("fm")
        let w = World(state: s, data: data)
        switch id {
        case "f_storm":
            if fm["pol"].double == 0 { return true }
            let prem = fm["premW"].double != 0 ? fm["premW"].double : (co.value("lastW")["rev"].double != 0 ? co.value("lastW")["rev"].double : 50000)
            let amt = jsRound(prem * s.random.range(2, 7) * Knobs.effect(co, bd, "r", w))
            Payments.companyPays(&s, companyID: co.id, amount: amt, category: "loss", label: "Storm claims")
            var f = s.companies[i].value("fm"); f["claims"] = .number(f["claims"].double + amt); s.companies[i].set("fm", f)
            s.news("A winter storm triggers insurance claims across the region.", tone: "bad")
            s.note("Storm claims hit \(co.name): {m:\(Int(amt))}.", tone: "bad", companyID: co.id)
        case "f_run":
            if fm["dep"].double == 0 { return true }
            let mgrQ = co.managerID != nil ? ManagerModel.quality(co, bd, people: s.people) : 0
            let out = fm["dep"].double * s.random.range(0.04, 0.16) * (bd.hasTrait("bank") && co.value("knob")["liq"].int == 1 ? 1.5 : 1) * (1.1 - mgrQ * 0.2)
            var f = fm; f["dep"] = .number(fm["dep"].double - out); f["depPrev"] = .number(fm["depPrev"].double - out)
            s.companies[i].set("fm", f)
            Ledger.moveRaw(&s, .company(co.id), -out)
            s.note("Rumours trigger withdrawals at \(co.name): {m:\(Int(out))} of deposits leave.", tone: "bad", companyID: co.id)
        case "f_default":
            if fm["book"].double == 0 { return true }
            let loss = fm["book"].double * s.random.range(0.0015, 0.006) * Knobs.effect(co, bd, "r", w) * (1 + max(0, 1 - s.economy.demand) * 4)
            var f = fm; f["book"] = .number(fm["book"].double - loss)
            s.companies[i].set("fm", f)
            Payments.book(&s, companyID: co.id, category: "loss", amount: loss)
            s.note("Loan losses at \(co.name): {m:\(Int(loss))} written off.", tone: "bad", companyID: co.id)
        default: return false
        }
        return true
    }

    /// Effects of events that only a fund understands (`aum`). Original: `FAM.fin.fx`.
    public static func applyEffects(_ s: inout GameState, _ i: Int, fx: JSONValue) {
        let f = fx["aum"].double
        var fm = s.companies[i].value("fm")
        if f != 0 && fm["aum"].double != 0 {
            fm["aum"] = .number(fm["aum"].double * f)
            s.companies[i].set("fm", fm)
        }
    }

    // MARK: Insolvency (not in the original)

    /// A bank whose capital is gone, or an insurer far below its solvency limit, for eight weeks in a row is closed by the
    /// regulator. The original had no such rule (a bank or insurer could only fail by running out of cash).
    /// Returns the companies to be wound up.
    public static func insolventCompanies(_ s: inout GameState, data: GameData) -> [Int] {
        var out: [Int] = []
        for i in s.companies.indices {
            let co = s.companies[i]
            guard co.status == .open, let bd = data.catalog[co.type], bd.family == "fin", bd.hasTrait("bank") || bd.hasTrait("ins") else { continue }
            let fm = co.value("fm")
            if fm.isNull || fm.object.isEmpty { continue }
            let broke: Bool
            if bd.hasTrait("bank") { broke = fm["equity"].double < 0 && fm["cr"].double < 0 }
            else { broke = !fm["sol"].isNull && fm["sol"].double < 0.05 && co.cash < 0 }
            var weeks = co.int("insolvW")
            weeks = broke ? weeks + 1 : 0
            s.companies[i].set("insolvW", weeks)
            if weeks >= 8 { out.append(co.id) }
        }
        return out
    }

    // MARK: Reading

    public static func book(_ co: Company, _ bd: Trade, state s: GameState) -> FinanceBook? {
        guard bd.family == "fin" else { return nil }
        let fm = co.value("fm")
        let under = co.value("flags")["reg"].bool
        if bd.hasTrait("ins") {
            var b = FinanceBook(kind: .insurer)
            b.policies = fm["pol"].double; b.weeklyPremium = fm["premW"].double; b.lossRatio = fm["lossR"].double
            b.solvency = fm["sol"].double; b.claimsPaidByStorms = fm["claims"].double; b.underRegulator = under
            return b
        }
        if bd.hasTrait("bank") {
            var b = FinanceBook(kind: .bank)
            b.deposits = fm["dep"].double; b.loans = fm["book"].double; b.groupLoans = fm["gb"].double
            b.capitalRatio = fm["cr"].double; b.requiredRatio = bd.trait("capitalReq") ?? 0.16; b.equity = fm["equity"].double
            b.centralBankLoan = s.loans.filter { $0.companyID == co.id && $0.flag("cb") }.reduce(0) { $0 + $1.balance }
            b.underRegulator = under
            return b
        }
        var b = FinanceBook(kind: .fund)
        b.assetsUnderManagement = fm["aum"].double; b.unitValue = fm["nav"].double == 0 ? 1 : fm["nav"].double
        b.highWaterMark = fm["hwm"].double == 0 ? 1 : fm["hwm"].double
        b.managementFee = bd.trait("mgmt") ?? 0.015; b.performanceFee = bd.trait("perf") ?? 0.2
        return b
    }
}
