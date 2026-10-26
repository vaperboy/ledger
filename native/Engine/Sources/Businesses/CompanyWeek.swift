import Foundation
import GameCore
import Countries
import Employees
import Finance

/// One company's week: customers, sales, costs, and everything that follows. Original: `weekCoCore`,
/// `book`, `weekEnd` (engine/company/model.js) and the standard family models (family_basic.js).
///
/// Supported here: service, venue, retail, production, logistics and project businesses (the project model is in
/// `ProjectWeek` / `ProjectDeveloper`), rental and finance businesses (`RentalModel`, `FinanceModel`), and the ones with a
/// model of their own (energy, the salmon farm, the holding company and the football club: see `SpecialFamilies`).
/// `isSupported` says which.
public enum CompanyWeek {
    public static func isSupported(_ bd: Trade) -> Bool {
        if RentalFinance.handles(bd) { return true }   // property and finance families: RentalModel, FinanceModel
        return ["svc", "venue", "retail", "prod", "logi", "project", "energy", "hold", "club"].contains(bd.family)
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
        Development.weekly(&s, i, bd, data: data)
        Satisfaction.wordOfMouth(&s, i, bd)
        Satisfaction.knownByUse(&s, i, bd, data: data)
        if s.companies[i].status == .open {
            Satisfaction.buzzWeek(&s, i)
            Satisfaction.reachCap(&s, i, data: data)
            Reviews.weekly(&s, i, bd, data: data)                              // customers write reviews (all trades share one system)
            KeyAccounts.weekly(&s, i, bd, data: data)              // business customers: relationships, offers
            SalesWays.weekly(&s, i, bd, data: data)                // platform fees, memberships, referrals, call-out, add-ons, peak seasons
            VolumeContracts.weekly(&s, i, bd, data: data)          // volume contracts: discount, payment delay, delivery, customer risk, offers
            if bd.family == "project" { ProjectWeek.afterWeek(&s, i, bd, data: data) }
        }
    }

    // MARK: Setup and closed

    static func accountantFee(_ s: inout GameState, _ i: Int, data: GameData) {
        let w = World(state: s, data: data)
        let amt = CompanyCosts.accountant(s.companies[i], w)
        Payments.companyPays(&s, companyID: s.companies[i].id, amount: amt, category: "oth")
        Advisers.weekly(&s, i, accountantFee: amt)
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
        if RentalFinance.handles(bd) {
            // Property and finance companies have their own weekly model instead of customers and capacity (original: `FAM.rent.custom`, `FAM.fin.custom`).
            let ctx = RentalFinance.week(&s, i, bd, data: data)
            let w = World(state: s, data: data)
            book(&s, i, bd, ctx, vat: Vat.rate(s.companies[i], bd, w), data: data)
            weekEnd(&s, i, bd, ctx, data: data, marketing: marketing)
            return
        }
        // Project businesses (the week's figures come from what happened on the days, or from the developments), and energy, the
        // salmon farm, a holding company and a football club (SpecialFamilies) work out their own week.
        if bd.family == "project" || SpecialFamilies.handles(bd) {
            let ctx = bd.family != "project" ? SpecialFamilies.week(&s, i, bd, data)
                : ProjectModel.isDeveloper(bd)
                ? ProjectDeveloper.week(&s, i, bd, data: data, context: FinanceContext(countries: data.countries, trades: data.catalog))
                : ProjectWeek.closeWeek(&s, i, bd, data: data)
            let vat = Vat.rate(s.companies[i], bd, World(state: s, data: data))
            book(&s, i, bd, ctx, vat: vat, data: data)
            weekEnd(&s, i, bd, ctx, data: data, marketing: marketing)
            return
        }
        // Customers and capacity for the week
        let (dm, cp, ticketPrice, vat, goods): (DemandResult, CapacityResult, Double, Double, (m: Double, q: Double)) = {
            let w = World(state: s, data: data)
            let co = s.companies[i]
            return (DemandModel.compute(co, bd, w), CapacityModel.compute(co, bd, w), Pricing.ticket(co, bd, w), Vat.rate(co, bd, w),
                    goodsEffect(co, bd, marketing, w.state, data))
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
            units = max(0, min(cap, units * (1 + s.random.gauss() * salesNoise)))
            units = unitsForSpecialModels(&s, i, bd, demand: D, capacity: cap, units: units, data: data)
            units = jsRound(min(units, cap) * 10) / 10
        }
        D = max(D, 0)
        var util = cap > 0 ? units / cap : 0
        var ctx0Util = util
        var rev = units * price
        var co = s.companies[i]
        let managerQ = co.managerID != nil ? ManagerModel.quality(co, bd, people: s.people) : 0.5
        let w = World(state: s, data: data)
        let costRate = costRate(co, bd, w, state: s, goods: goods)
        // Business customers share the shop with the walk-ins (key_accounts.js: acctDemand, acctRev).
        let acctOrders = KeyAccounts.orders(co, bd, privateDemand: D, capacity: cap, units: units, price: price, costRate: costRate)
        var walkInRev = rev
        if acctOrders.units > 0 {
            // A full shop is shared: the walk-ins give up what the accounts take (KeyAccounts.orders).
            let keep = units > 0 ? acctOrders.walkInUnits / units : 1
            walkInRev = rev * keep
            units = acctOrders.walkInUnits + acctOrders.units; rev = walkInRev + acctOrders.revenue; D += acctOrders.demand
            ctx0Util = cap > 0 ? units / cap : 0
            KeyAccounts.record(&s, i, acctOrders, price: price)
        }
        var cogs = (acctOrders.units > 0 ? walkInRev + acctOrders.units * price : rev) * costRate
        if acctOrders.units > 0 { cogs *= 1 - 0.05 * acctOrders.units / max(1, units) }
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
        ctx.acct = acctOrders.perAccount.filter { $0.units > 0 }.map { (id: $0.id, rev: $0.units * price * $0.pm) }
        // Family-specific adjustments (stock, returns, casino luck, subsidies)
        applyFamilyPost(&s, i, bd, &ctx, data: data)
        rev = ctx.rev; cogs = ctx.cogs
        co = s.companies[i]
        book(&s, i, bd, ctx, vat: vat, data: data)
        Suppliers.recordGoods(&s, companyIndex: i, cogs: ctx.cogs, data: data)
        weekEnd(&s, i, bd, ctx, data: data, marketing: marketing)
    }

    /// The share of sales that goes on goods and direct costs this week: the trade's cost of sales plus its choices, the manager,
    /// the supplier class, the economy and events. One function for the week itself and for the "how you sell" preview.
    static func costRate(_ co: Company, _ bd: Trade, _ w: World, state s: GameState, goods: (m: Double, q: Double)) -> Double {
        let managerQ = co.managerID != nil ? ManagerModel.quality(co, bd, people: s.people) : 0.5
        var costRate = (bd.costOfSales + Knobs.effect(co, bd, "c", w, sum: true)) * (co.managerID != nil ? 1.04 - 0.08 * managerQ : 1) * goods.m
            * DemandModel.modifier(co, "price") * DemandModel.modifier(co, "cogsup")
        if bd.family == "project" { costRate /= (w.balance.priceLevelByTrade[bd.id] ?? 1).squareRoot() }
        if bd.family != "prod" && bd.family != "project" { costRate *= 0.7 + 0.3 * s.economy.materials }
        if let fuel = bd.trait("fuel") { costRate += fuel * (s.economy.fuel - 1) }
        return max(0.01, costRate)
    }

    /// Week-to-week spread of what a shop really sells around what demand and capacity allow (one standard deviation, as a share).
    static let salesNoise = 0.045
    /// Weeks after a job is complete before the retention is paid (the defect period).
    static let defectWeeks = 26

    struct WeekContext {
        var units: Double, rev: Double, cogs: Double, D: Double, cap: Double, util: Double, price: Double
        var paidDuringWeek: Double
        /// The cost of sales is only an accounting entry (a developer pays for land and building as they fall due).
        var cogsIsAccounting = false
        /// Part of the week's purchases (`cogs`) that went into stock instead of the cost of sales, or, when negative, stock used up and expensed (salmon).
        var stockChange = 0.0
        /// Project retention: what clients held back this week on milestone payments (job id: net), and the jobs completed this week whose
        /// held-back money now starts its defect period.
        var retentionHeld: [Int: Double] = [:]
        var retentionReleased: [Int] = []
        /// What each business customer ordered this week at the prices they pay (net of VAT): they pay on the trade's terms, some of them late.
        var acct: [(id: Int, rev: Double)] = []
    }

    /// Supplier class: cost and quality of goods. Original: `goodsEff` (default class; vendor choice not yet ported).
    static func goodsEffect(_ co: Company, _ bd: Trade, _ m: MarketingTables, _ s: GameState, _ data: GameData) -> (m: Double, q: Double) {
        let r = Suppliers.goodsEffect(s, company: co, bd, data: data, classes: m.goodsClasses)
        return (r.m, r.q)
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
        var step = d * (0.25 + (co.managerID != nil ? 0.15 * q : 0))
        // Suppliers cut off after repeated missed bills (see `Payday.payBills`): stock only against cash in the account, then none at all.
        let supCut = co.int("supCut")
        if step > 0 && supCut > 0 { step = supCut >= 2 ? 0 : min(step, max(0, co.cash)) }
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
        books.add("cogs", cogs - jsRound(ctx.stockChange))
        if ctx.stockChange != 0 { co.inventory += jsRound(ctx.stockChange) }
        co.set("lastW", .object(["units": .number(ctx.units), "rev": .number(rev), "cogs": .number(cogs), "D": .number(ctx.D), "cap": .number(ctx.cap), "util": .number(ctx.util)]))
        let cashShare = 1 - bd.businessShare
        let gross = rev * (1 + vr)
        let grossB2B = country.usesSalesTax ? rev : gross
        co.books = books
        s.companies[i] = co
        // Business customers are invoiced one by one: their orders are not paid at the till. The part the trade would have taken in cash
        // and the part it would have invoiced both wait for the customer (trade terms, and late when the customer is slow).
        var acctInvoices: [(id: Int, amount: Double, due: Int, late: Int, bad: Bool)] = []
        var acctCash = 0.0, acctCredit = 0.0
        if !ctx.acct.isEmpty && rev > 0 {
            let list = co.value("accts").array
            let gRatio = gross / rev, bRatio = grossB2B / rev
            for a in ctx.acct {
                let relationship = list.first { $0["id"].int == a.id }?["rel"].double ?? 0
                let late = SupplyTerms.customerLateness(s, companyID: co.id, accountID: a.id, relationship: relationship)
                var h = HashedRandom("\(s.seed):cbad:\(s.week):\(co.id):\(a.id)")
                let odds = 0.012 * (s.economy.demand < 0.97 ? 2 : 1) * (co.value("flags")["ccheck"].bool ? 0.3 : 1)
                let cashPart = a.rev * gRatio * cashShare, creditPart = a.rev * bRatio * bd.businessShare
                acctCash += cashPart; acctCredit += creditPart
                acctInvoices.append((a.id, jsRound(cashPart + creditPart), s.week + bd.paymentTermsWeeks + late, late, h.next() < odds))
            }
        }
        // Retention the clients held back: part of the week's takings that is not received now. It waits as a receivable of the job until the
        // job is complete and the defect period has passed.
        var heldCash = 0.0, heldCredit = 0.0
        for (_, net) in ctx.retentionHeld.sorted(by: { $0.key < $1.key }) {
            heldCash += net * (1 + vr) * cashShare
            heldCredit += net * (country.usesSalesTax ? 1 : 1 + vr) * bd.businessShare
        }
        Payments.companyReceives(&s, companyID: co.id, amount: gross * cashShare - ctx.paidDuringWeek - acctCash - heldCash, category: nil, label: nil)
        co = s.companies[i]
        for (job, net) in ctx.retentionHeld.sorted(by: { $0.key < $1.key }) where net > 0 {
            let part = jsRound(net * (1 + vr) * cashShare + net * (country.usesSalesTax ? 1 : 1 + vr) * bd.businessShare)
            var recv = co.receivables
            if let k = recv.firstIndex(where: { $0.int("pj") == job && $0.flag("held") }) { recv[k].amount += part }
            else { var r = Receivable(amount: part, dueWeek: s.week + 1000, willDefault: false); r.set("pj", job); r.set("held", true); recv.append(r) }
            co.receivables = recv
        }
        for job in ctx.retentionReleased {
            var recv = co.receivables
            for k in recv.indices where recv[k].int("pj") == job && recv[k].flag("held") {
                recv[k].raw.removeValue(forKey: "held")
                recv[k].dueWeek = s.week + Self.defectWeeks
            }
            co.receivables = recv
        }
        for inv in acctInvoices where inv.amount > 0 {
            var r = Receivable(amount: inv.amount, dueWeek: inv.due, willDefault: inv.bad)
            r.set("ac", inv.id); r.set("ld", inv.late)
            var recv = co.receivables; recv.append(r); co.receivables = recv
        }
        if bd.businessShare > 0 && rev > 0 {
            let extra = s.random.chance(0.18) ? s.random.int(1, 4) : 0
            let t = bd.paymentTermsWeeks + extra
            let defaultOdds = 0.012 * (s.economy.demand < 0.97 ? 2 : 1) * (co.value("flags")["ccheck"].bool ? 0.3 : 1)
            var recv = co.receivables
            recv.append(Receivable(amount: max(0, jsRound(grossB2B * bd.businessShare - acctCredit - heldCredit)), dueWeek: s.week + t, willDefault: s.random.chance(defaultOdds)))
            co.receivables = recv
            if co.value("flags")["ccheck"].bool {
                s.companies[i] = co
                Payments.companyPays(&s, companyID: co.id, amount: grossB2B * bd.businessShare * 0.004, category: "oth")
                co = s.companies[i]
            }
        }
        let goodsTerm = ctx.cogsIsAccounting ? nil : SupplyTerms.goodsTerm(s, co, data: data)
        var termOwed = 0.0
        let salesTax = country.usesSalesTax
        let vBase = country.vat.rate(for: bd.vatCategory)
        let exempt = vr == 0 && vBase > 0 && Vat.isExempt(co, w)
        let vatIn = (vr > 0 && !salesTax) ? min(vr, 0.25) * 0.9 : 0
        co.vatBalance += rev * vr * (salesTax ? 1 - bd.businessShare : 1)
        if ctx.cogsIsAccounting {
            // Land and building costs were paid in cash as they fell due; the cost of sales here is only an accounting entry.
        } else if exempt {
            // Below the VAT threshold: input VAT on purchases cannot be reclaimed and becomes a cost.
            let extra = cogs * min(vBase, 0.25) * 0.9
            if goodsTerm != nil { termOwed = cogs + extra } else { co.addPayable("other", cogs + extra) }
            var b = co.books; b.add("oth", extra); co.books = b
        } else {
            if goodsTerm != nil { termOwed = cogs * (1 + vatIn) } else { co.addPayable("other", cogs * (1 + vatIn)) }
            co.vatBalance -= vatIn * cogs
        }
        s.companies[i] = co
        // Goods bought on agreed terms (`SupplyTerms`): paid on delivery or owed on an invoice instead of the monthly bill.
        if let t = goodsTerm, termOwed > 0 { SupplyTerms.buyGoods(&s, companyIndex: i, amount: termOwed, term: t, data: data) }
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
        var customersPaid: [(account: Int, late: Int, amount: Double)] = []
        for r in co.receivables {
            if r.flag("held") { remaining.append(r); continue }   // retention on a job still in hand
            if r.int("ic") != 0 { remaining.append(r); continue }   // an invoice to one of your own companies: settled with `SupplyTerms`
            if s.week >= r.dueWeek {
                if r.int("ac") != 0 && !r.willDefault { customersPaid.append((r.int("ac"), r.int("ld"), r.amount)) }
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
        SupplyTerms.customersPaid(&s, companyIndex: i, paid: customersPaid, country: w0.country(co))

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
        if premium > 0, co2.value("flags")["premUntil"].double > Double(s.week) { premium *= 1 + co2.value("flags")["premUp"].double }   // repriced after a lost lawsuit (Aftermath)
        if premium > 0 { Payments.companyPays(&s, companyID: id, amount: premium, category: "ins"); Advisers.premiumsPaid(&s, i, total: premium) }
        // Leased vehicles
        for v in s.companies[i].value("veh").array where v["mode"].string == "lease" {
            let instalment = v["lease"].double * 12 / 52
            Payments.companyPays(&s, companyID: id, amount: instalment, category: "oth")
            Vat.input(&s, companyIndex: i, net: instalment, data: data)
        }
        CompanyCosts.premisesValue(&s, companyIndex: i, data: data)
        Marketing.weekly(&s, companyIndex: i, bd, data: data, tables: marketing)
        EquipmentUnits.before(&s, companyIndex: i, bd, data: data)
        CompanyCosts.equipmentWeek(&s, companyIndex: i, utilisation: ctx.util == 0 ? 0.6 : ctx.util, bd, data: data)
        EquipmentUnits.after(&s, companyIndex: i, bd, utilisation: ctx.util == 0 ? 0.6 : ctx.util, data: data)
        PersonalEquipment.weeklyCosts(&s, companyIndex: i, bd, data: data)

        // Quality and reputation follow how well the company does its job.
        co = s.companies[i]
        let w3 = World(state: s, data: data)
        // the hidden champion ambition perk lifts the target (original: step 'window.qualityTarget:10', after the target's own steps)
        let target = min(99, QualityModel.target(co, bd, utilisation: ctx.util == 0 ? 0.5 : ctx.util, w3, goods: goodsEffect(co, bd, marketing, w3.state, data)) + Ambitions.qualityBonus(s, data))
        co.quality += (target - co.quality) * 0.18
        co.reputation = clamp(co.reputation + (co.quality - co.reputation) * 0.025 - ((ctx.D > ctx.cap * 1.25 && ctx.cap > 0) ? 0.08 : 0), 0, 100)
        if co.managerID == nil && co.ownerHours >= 20 { co.ownerSkill = clamp(co.ownerSkill + 0.035 * (1 - co.ownerSkill / 120), 0, 100) }
        s.companies[i] = co
        StaffRoutine.weekly(&s, companyIndex: i, bd, data: data, utilisation: ctx.util)
        ManagerModel.weekly(&s, companyIndex: i, bd, data: data, revenue: ctx.rev, utilisation: ctx.util, demand: ctx.D, capacity: ctx.cap)
        co = s.companies[i]
        if co.cash < 0 {
            co.weeksNegative += 1
            let interest = -co.cash * Banking.overdraftRate(state: s, country: w3.country(co), home: w3.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode)) / 52
            s.companies[i] = co
            Ledger.moveRaw(&s, .company(id), -interest)
            var b = s.companies[i].books; b.add("int", interest); s.companies[i].books = b
            co = s.companies[i]
        } else { co.weeksNegative = 0 }
        co.set("unitsW", ctx.units)
        s.companies[i] = co
    }
}
