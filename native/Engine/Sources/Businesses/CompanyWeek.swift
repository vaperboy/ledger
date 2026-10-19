import Foundation
import GameCore
import Countries
import Employees
import Finance

/// One company's week: customers, sales, costs, and everything that follows. Original: `weekCoCore`,
/// `book`, `weekEnd` (engine/company/model.js) and the standard family models (family_basic.js).
///
/// Supported here: service, venue, retail, production and logistics businesses. Project, rental, finance, energy,
/// holding and football businesses have their own models in the original and are not yet part of the native
/// engine (see docs/KNOWN_GAPS.md): `isSupported` says which.
public enum CompanyWeek {
    public static func isSupported(_ bd: Trade) -> Bool {
        ["svc", "venue", "retail", "prod", "logi"].contains(bd.family) && bd.id != "salmon"
    }

    /// Run the week for the company at `index`. Called once per company per week, after the week counter moved on.
    public static func run(_ s: inout GameState, companyIndex i: Int, data: GameData, marketing: MarketingTables) {
        let co = s.companies[i]
        guard co.status.isLive, let bd = data.catalog[co.type], isSupported(bd) else { return }

        // This week's books start empty; temporary effects count down.
        var books = co.books; books.week = [:]
        s.companies[i].books = books
        s.companies[i].set("mods", .array(co.value("mods").array.compactMap {
            var m = $0; m["w"] = .number($0["w"].double - 1); return m["w"].double > 0 ? m : nil
        }))
        Documents.weekly(&s, companyIndex: i, data: data)
        Satisfaction.closeIfNobodyWorks(&s, i, bd)

        switch s.companies[i].status {
        case .setup: setupWeek(&s, i, bd, data)
        case .closed: closedWeek(&s, i, bd, data)
        case .open: openWeek(&s, i, bd, data, marketing)
        default: break
        }
        // After the week: complaints, word of mouth (weekCo.after), then buzz and the limit of a local name (chainWeek).
        Satisfaction.complaintsWeek(&s, i, bd, data: data)
        Satisfaction.wordOfMouth(&s, i, bd)
        if s.companies[i].status == .open {
            Satisfaction.buzzWeek(&s, i)
            Satisfaction.reachCap(&s, i, data: data)
        }
    }

    // MARK: Setup and closed

    static func accountantFee(_ s: inout GameState, _ i: Int, data: GameData) {
        let w = World(state: s, data: data)
        let amt = CompanyCosts.accountant(s.companies[i], w)
        Payments.companyPays(&s, companyID: s.companies[i].id, amount: amt, category: "oth")
    }

    static func setupWeek(_ s: inout GameState, _ i: Int, _ bd: Trade, _ data: GameData) {
        CompanyCosts.rent(&s, companyIndex: i, data: data)
        accountantFee(&s, i, data: data)
        OpeningChecklist.tryAutoOpen(&s, companyIndex: i, data: data)
    }

    static func closedWeek(_ s: inout GameState, _ i: Int, _ bd: Trade, _ data: GameData) {
        CompanyCosts.rent(&s, companyIndex: i, data: data)
        accountantFee(&s, i, data: data)
        let w = World(state: s, data: data)
        let fixed = bd.fixedWeekly * pow(s.companies[i].size, 0.6) * 0.5
        _ = w
        Payments.companyPays(&s, companyID: s.companies[i].id, amount: fixed, category: "oth")
        let total = s.companies[i].num("closeTot", s.companies[i].num("closeW"))
        let left = s.companies[i].num("closeW")
        CompanyCosts.wages(&s, companyIndex: i, bd, data: data, factor: (total - left) < 2 ? 1 : 0.4)
        s.companies[i].set("closeW", left - 1)
        if left - 1 <= 0 {
            s.companies[i].status = .open
            s.note("\(s.companies[i].name) reopens.", tone: "good", companyID: s.companies[i].id)
        }
    }

    // MARK: Open

    static func openWeek(_ s: inout GameState, _ i: Int, _ bd: Trade, _ data: GameData, _ marketing: MarketingTables) {
        // Customers and capacity for the week
        let (dm, cp, ticketPrice, vat, goods): (DemandResult, CapacityResult, Double, Double, (m: Double, q: Double)) = {
            let w = World(state: s, data: data)
            let co = s.companies[i]
            return (DemandModel.compute(co, bd, w), CapacityModel.compute(co, bd, w), Pricing.ticket(co, bd, w), Vat.rate(co, bd, w),
                    goodsEffect(co, bd, marketing))
        }()
        var D = dm.customers
        let cap = cp.capacity
        var price = ticketPrice
        if bd.hasTrait("rateIdx") { price *= s.economy.freight }
        // Sales: summed from the days if the company trades daily, otherwise worked out for the whole week.
        var units: Double
        var paidDuringWeek = 0.0
        if DailyTrade.tradesDaily(s.companies[i], bd) {
            let close = DailyTrade.closeWeek(&s, companyIndex: i, bd, demand: D, capacity: cap, price: price, data: data)
            units = close.units
            price = close.averagePrice
            paidDuringWeek = close.cashAlreadyTaken
        } else {
            units = min(D, cap)
            units = max(0, min(cap, units * (1 + s.random.gauss() * 0.045)))
            units = unitsForSpecialModels(&s, i, bd, demand: D, capacity: cap, units: units, data: data)
            units = jsRound(min(units, cap) * 10) / 10
        }
        D = max(D, 0)
        let util = cap > 0 ? units / cap : 0
        var rev = units * price
        var co = s.companies[i]
        let managerQ = co.managerID != nil ? ManagerModel.quality(co, bd, people: s.people) : 0.5
        let w = World(state: s, data: data)
        var costRate = (bd.costOfSales + Knobs.effect(co, bd, "c", w, sum: true)) * (co.managerID != nil ? 1.04 - 0.08 * managerQ : 1) * goods.m
            * DemandModel.modifier(co, "price") * DemandModel.modifier(co, "cogsup")
        if bd.family == "project" { costRate /= (w.balance.priceLevelByTrade[bd.id] ?? 1).squareRoot() }
        if bd.family != "prod" && bd.family != "project" { costRate *= 0.7 + 0.3 * s.economy.materials }
        if let fuel = bd.trait("fuel") { costRate += fuel * (s.economy.fuel - 1) }
        costRate = max(0.01, costRate)
        var cogs = rev * costRate
        if let loc = co.value("prem")["loc"].isNull ? nil : co.value("prem")["loc"].double, loc < 1, !Competition.isFootTraffic(co.value("prem")["kind"].string) {
            cogs += rev * (1 - loc) * 0.6
        }
        if let perish = bd.trait("perish") { cogs += rev * perish * (1 + max(0, 0.85 - util) * 2.2) * (co.managerID != nil ? 1.2 - 0.5 * managerQ : 1) }
        if let shrink = bd.trait("shrink") {
            cogs += rev * shrink * (co.value("flags")["secure"].bool ? 0.5 : 1) * (1 + co.value("flags")["shrinkUp"].double)
        }
        if let ota = bd.trait("ota") { cogs += rev * ota * Knobs.effect(co, bd, "ota", w) }
        if bd.hasTrait("excise") { cogs += units * 8.5 * w.country(co).costIndex * w.inflationIndex }
        var ctx = WeekContext(units: units, rev: rev, cogs: cogs, D: D, cap: cap, util: util, price: price, paidDuringWeek: paidDuringWeek)
        // Family-specific adjustments (stock, returns, casino luck, subsidies)
        applyFamilyPost(&s, i, bd, &ctx, data: data)
        rev = ctx.rev; cogs = ctx.cogs
        co = s.companies[i]
        book(&s, i, bd, ctx, vat: vat, data: data)
        weekEnd(&s, i, bd, ctx, data: data, marketing: marketing)
    }

    struct WeekContext {
        var units: Double, rev: Double, cogs: Double, D: Double, cap: Double, util: Double, price: Double
        var paidDuringWeek: Double
    }

    /// Supplier class: cost and quality of goods. Original: `goodsEff` (default class; vendor choice not yet ported).
    static func goodsEffect(_ co: Company, _ bd: Trade, _ m: MarketingTables) -> (m: Double, q: Double) {
        if bd.costOfSales < 0.03 || ["fin", "energy", "rent", "club", "svc"].contains(bd.family) || bd.id.hasPrefix("engcons") || bd.id.hasPrefix("event") { return (1, 0) }
        let cls = co.value("src")["c"].isNull ? 1 : co.value("src")["c"].int
        let c = m.goodsClasses.indices.contains(cls) ? m.goodsClasses[cls] : m.goodsClasses[1]
        return (c.cost, c.quality)
    }

    /// Membership clubs (gyms) work with members, not walk-ins. Original: `FAM.venue.units`.
    static func unitsForSpecialModels(_ s: inout GameState, _ i: Int, _ bd: Trade, demand D: Double, capacity cap: Double, units u: Double, data: GameData) -> Double {
        var co = s.companies[i]
        if bd.family == "venue" && bd.hasTrait("sub") {
            var fm = co.value("fm")
            let churn0 = (bd.trait("churn") ?? 0)
            if !(cap > 0) {
                let M0 = fm["memb"].isNull ? 0 : fm["memb"].double
                let flagChurn = co.value("flags")["churnUp"].isNull ? 1 : co.value("flags")["churnUp"].double
                fm["memb"] = .number(max(0, M0 * (1 - churn0 * (1.5 - co.quality / 100) * flagChurn * 2)))
                co.set("fm", fm); s.companies[i] = co
                return 0
            }
            let t = min(D, cap)
            var M = fm["memb"].isNull ? t * 0.2 : fm["memb"].double
            let flagChurn = co.value("flags")["churnUp"].isNull ? 1 : co.value("flags")["churnUp"].double
            let churn = churn0 * (1.5 - co.quality / 100) * flagChurn
            M += (t - M) * 0.065 - M * churn
            M = max(0, min(M, cap))
            fm["memb"] = .number(M)
            co.set("fm", fm); s.companies[i] = co
            return M
        }
        if bd.hasTrait("stock") && (bd.family == "retail" || bd.family == "prod") {
            let w = World(state: s, data: data)
            return StockHandling.unitsAvailable(co, bd, demand: D, capacity: cap, units: u, w: w)
        }
        return u
    }

    static func applyFamilyPost(_ s: inout GameState, _ i: Int, _ bd: Trade, _ ctx: inout WeekContext, data: GameData) {
        var co = s.companies[i]
        let w = World(state: s, data: data)
        let costIndex = w.country(co).costIndex
        switch bd.family {
        case "retail", "prod":
            if bd.family == "retail", bd.hasTrait("ecom") {
                let ret = (bd.trait("returns") ?? 0) * Knobs.effect(co, bd, "r", w) * (co.quality < 50 ? 1.2 : 1)
                let lost = ctx.rev * ret * 0.7
                ctx.rev -= lost
                ctx.cogs += ctx.units * 52 * costIndex * DemandModel.modifier(co, "cogsup") + ctx.units * ret * 28 * costIndex
            }
            if bd.hasTrait("stock") { stockHandle(&s, i, bd, &ctx, data: data) }
            if bd.family == "prod", let subsidy = bd.trait("subsidy"), ctx.rev > 0 {
                Payments.companyReceives(&s, companyID: co.id, amount: ctx.rev * subsidy, category: "rev", label: "Agricultural support")
            }
        case "venue":
            if let variance = bd.trait("variance") {
                let risk = Knobs.effect(co, bd, "risk", w)
                let sd = variance * (risk == 0 ? 1 : risk) / max(0.2, ctx.units / 100).squareRoot()
                let f = clamp(1 + s.random.gauss() * sd, 0.05, 3)
                var fm = co.value("fm"); fm["vol"] = .number(risk == 0 ? 1 : risk); fm["lastHold"] = .number(f)
                co.set("fm", fm)
                s.companies[i] = co
                ctx.rev *= f
            }
        default: break
        }
    }

    /// Keep stock near what the shelves need: buy, write off what spoils, pay for storage. Original: `stockHandle`.
    static func stockHandle(_ s: inout GameState, _ i: Int, _ bd: Trade, _ ctx: inout WeekContext, data: GameData) {
        guard let stockWeeks = bd.trait("stock"), stockWeeks != 0 else { return }
        var co = s.companies[i]
        let pol = min(2, max(0, co.int("stockPol", 1)))
        let mult = [0.75, 1, 1.4][pol]
        let target = ctx.cogs * stockWeeks / 7 * mult
        let d = target - co.inventory
        let q = co.managerID != nil ? ManagerModel.quality(co, bd, people: s.people) : 0
        let step = d * (0.25 + (co.managerID != nil ? 0.15 * q : 0))
        var books = co.books
        if co.inventory > target * 1.8 && target > 0 {
            let obsolete = (co.inventory - target * 1.8) * 0.03
            co.inventory -= obsolete
            books.add("loss", obsolete)
        }
        co.inventory += step
        s.companies[i] = co
        Ledger.moveRaw(&s, .company(co.id), -step)
        co = s.companies[i]
        let hold = co.inventory * [0.0004, 0.0008, 0.0016][pol]
        books.add("cogs", hold)
        co.addPayable("other", hold)
        if bd.hasTrait("floor") {
            let interest = co.inventory * (s.economy.policyRate + 0.025) / 52
            books.add("int", interest)
            s.companies[i] = co
            Ledger.moveRaw(&s, .company(co.id), -interest)
            co = s.companies[i]
        }
        let month = GameCalendar.month(week: s.week)
        if bd.hasTrait("season"), [2, 8].contains(month), s.week % 4 == 0 {
            let md = co.inventory * 0.06 * (co.managerID != nil ? 1.2 - q * 0.7 : 0.9)
            co.inventory -= md
            books.add("cogs", md)
        }
        co.books = books
        s.companies[i] = co
    }

    // MARK: Book the week

    /// Revenue, cost of sales, VAT and customer invoices. Original: `book`.
    static func book(_ s: inout GameState, _ i: Int, _ bd: Trade, _ ctx: WeekContext, vat vr: Double, data: GameData) {
        var co = s.companies[i]
        let w = World(state: s, data: data)
        let country = w.country(co)
        let rev = jsRound(ctx.rev), cogs = jsRound(ctx.cogs)
        var books = co.books
        books.add("rev", rev)
        books.add("cogs", cogs)
        co.set("lastW", .object(["units": .number(ctx.units), "rev": .number(rev), "cogs": .number(cogs), "D": .number(ctx.D), "cap": .number(ctx.cap), "util": .number(ctx.util)]))
        let cashShare = 1 - bd.businessShare
        let gross = rev * (1 + vr)
        let grossB2B = country.usesSalesTax ? rev : gross
        co.books = books
        s.companies[i] = co
        Payments.companyReceives(&s, companyID: co.id, amount: gross * cashShare - ctx.paidDuringWeek, category: nil, label: nil)
        co = s.companies[i]
        if bd.businessShare > 0 && rev > 0 {
            let extra = s.random.chance(0.18) ? s.random.int(1, 4) : 0
            let t = bd.paymentTermsWeeks + extra
            let defaultOdds = 0.012 * (s.economy.demand < 0.97 ? 2 : 1) * (co.value("flags")["ccheck"].bool ? 0.3 : 1)
            var recv = co.receivables
            recv.append(Receivable(amount: jsRound(grossB2B * bd.businessShare), dueWeek: s.week + t, willDefault: s.random.chance(defaultOdds)))
            co.receivables = recv
            if co.value("flags")["ccheck"].bool {
                s.companies[i] = co
                Payments.companyPays(&s, companyID: co.id, amount: grossB2B * bd.businessShare * 0.004, category: "oth")
                co = s.companies[i]
            }
        }
        let salesTax = country.usesSalesTax
        let vBase = country.vat.rate(for: bd.vatCategory)
        let exempt = vr == 0 && vBase > 0 && Vat.isExempt(co, w)
        let vatIn = (vr > 0 && !salesTax) ? min(vr, 0.25) * 0.9 : 0
        co.vatBalance += rev * vr * (salesTax ? 1 - bd.businessShare : 1)
        if exempt {
            // Below the VAT threshold: input VAT on purchases cannot be reclaimed and becomes a cost.
            let extra = cogs * min(vBase, 0.25) * 0.9
            co.addPayable("other", cogs + extra)
            var b = co.books; b.add("oth", extra); co.books = b
        } else {
            co.addPayable("other", cogs * (1 + vatIn))
            co.vatBalance -= vatIn * cogs
        }
        s.companies[i] = co
    }

    // MARK: Week end

    static func weekEnd(_ s: inout GameState, _ i: Int, _ bd: Trade, _ ctx: WeekContext, data: GameData, marketing: MarketingTables) {
        let id = s.companies[i].id
        // Customers' invoices fall due (or are never paid).
        var co = s.companies[i]
        var remaining: [Receivable] = []
        var received = 0.0
        var lostNet = 0.0, lostVAT = 0.0
        let w0 = World(state: s, data: data)
        for r in co.receivables {
            if s.week >= r.dueWeek {
                if !r.willDefault { received += r.amount }
                else {
                    let vr = w0.country(co).usesSalesTax ? 0 : Vat.rate(co, bd, w0)
                    let net = r.amount / (1 + vr)
                    lostNet += net; lostVAT += r.amount - net
                }
            } else { remaining.append(r) }
        }
        co.receivables = remaining
        if lostNet > 0 { var b = co.books; b.add("loss", lostNet); co.books = b; co.vatBalance -= lostVAT }
        s.companies[i] = co
        if received != 0 { Payments.companyReceives(&s, companyID: id, amount: received, category: nil, label: nil) }

        CompanyCosts.wages(&s, companyIndex: i, bd, data: data)
        CompanyCosts.rent(&s, companyIndex: i, data: data)
        let w = World(state: s, data: data)
        co = s.companies[i]
        let fixed = CompanyCosts.fixedOverhead(co, bd, w)
        Payments.companyPays(&s, companyID: id, amount: fixed, category: "oth")
        // VAT on purchases of overhead (half of the overhead is VAT-bearing)
        let vr = Vat.rate(co, bd, w)
        let country = w.country(co)
        if fixed > 0 && vr > 0 && !country.usesSalesTax {
            let vf = vr * fixed * 0.5
            Ledger.moveRaw(&s, .company(id), -jsRound(vf))
            s.companies[i].vatBalance -= vf
        } else if fixed > 0 && Vat.isExempt(co, w) {
            let vf = country.vat.rate(for: bd.vatCategory) * fixed * 0.5
            Ledger.moveRaw(&s, .company(id), -jsRound(vf))
            var b = s.companies[i].books; b.add("oth", vf); s.companies[i].books = b
        }
        accountantFee(&s, i, data: data)
        // Insurance
        let w2 = World(state: s, data: data)
        let co2 = s.companies[i]
        var premium = 0.0
        for (k, on) in co2.value("ins").object.sorted(by: { $0.key < $1.key }) where on.bool {
            if let p = marketing.insuranceProducts[k], p.count > 3 { premium += CompanyCosts.insurancePremium(co2, product: k, rate: p[3].double, w2) }
        }
        if premium > 0 { Payments.companyPays(&s, companyID: id, amount: premium, category: "ins") }
        // Leased vehicles
        for v in s.companies[i].value("veh").array where v["mode"].string == "lease" {
            Payments.companyPays(&s, companyID: id, amount: v["lease"].double * 12 / 52, category: "oth")
        }
        CompanyCosts.premisesValue(&s, companyIndex: i)
        Marketing.weekly(&s, companyIndex: i, bd, data: data, tables: marketing)
        EquipmentUnits.before(&s, companyIndex: i, bd, data: data)
        CompanyCosts.equipmentWeek(&s, companyIndex: i, utilisation: ctx.util == 0 ? 0.6 : ctx.util, bd, data: data)
        EquipmentUnits.after(&s, companyIndex: i, bd, utilisation: ctx.util == 0 ? 0.6 : ctx.util, data: data)

        // Quality and reputation follow how well the company does its job.
        co = s.companies[i]
        let w3 = World(state: s, data: data)
        let target = QualityModel.target(co, bd, utilisation: ctx.util == 0 ? 0.5 : ctx.util, w3, goods: goodsEffect(co, bd, marketing))
        co.quality += (target - co.quality) * 0.18
        co.reputation = clamp(co.reputation + (co.quality - co.reputation) * 0.025 - ((ctx.D > ctx.cap * 1.25 && ctx.cap > 0) ? 0.08 : 0), 0, 100)
        if co.managerID == nil && co.ownerHours >= 20 { co.ownerSkill = clamp(co.ownerSkill + 0.035 * (1 - co.ownerSkill / 120), 0, 100) }
        s.companies[i] = co
        StaffRoutine.weekly(&s, companyIndex: i, bd, data: data, utilisation: ctx.util)
        co = s.companies[i]
        if co.cash < 0 {
            co.weeksNegative += 1
            let interest = -co.cash * 0.14 / 52
            s.companies[i] = co
            Ledger.moveRaw(&s, .company(id), -interest)
            var b = s.companies[i].books; b.add("int", interest); s.companies[i].books = b
            co = s.companies[i]
        } else { co.weeksNegative = 0 }
        co.set("unitsW", ctx.units)
        s.companies[i] = co
    }
}
