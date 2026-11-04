import Foundation
import GameCore
import Countries
import Finance

/// Wave 7 (PROJ and job-contract model): construction, electrician, plumber, handyman, engineering office and security firm sell real jobs.
/// A job type is an item with a quoted price per job or per hour, materials at cost plus a markup, labour hours and the crew and vehicle it needs, a
/// lead time before the crew can start, call-outs (arrive within a day, jump the queue) against scheduled jobs (wait in the backlog), a warranty
/// callback rate, phases with subcontractors (construction), and contracts (guard hours per site per month, consultancy retainers, monitoring,
/// maintenance and inspection plans). Data: `Resources/wave7_jobs.json`. Only `items27` and `itemsv2` (both existing) are written.
///
/// Money: the books keep the trade's cost of sales (`mat` + `sub` traits for the job trades, `cogs` for handyman and security). Item materials costs are
/// scaled on install so the weighted menu equals that share and the revenue weights add up to 1, so a company that never touches a price plays as
/// before. The labour of the crew and the expected warranty callbacks are the item's `prep`: they make the live profit and loss real, but they are
/// not booked twice (wages are already in the weekly costs). Nothing here moves cash.
public enum Wave7 {
    public struct Phase: Equatable, Sendable {
        public var name: String
        public var share: Double
        public var sub: Double
    }

    public struct Spec: Equatable, Sendable {
        public var name: String
        public var model: ItemModels.Model
        public var share: Double
        public var rel: Double
        /// Person-hours of labour in one job (before the trade's hour scale), and the people who do it (roles).
        public var hours: Double
        public var crew: [String]
        public var mat: Double
        public var sub: Double
        public var markup: Double
        public var lead: Int
        public var callout: Bool
        public var warrantyRate: Double
        public var warrantyMonths: Int
        public var van: Bool
        public var phases: [Phase]
        public var visits: Double
        public var period: Int
        public var churn: Double
        public var contract: Bool
        public var doc: String
        public var buy: Double
        public var note: String
        public var isStock: Bool { model == .stk }
    }

    public struct TradeSpec: Equatable, Sendable {
        public var trade: String
        public var skill: String
        public var skillLabel: String
        /// Hours are real time and are not scaled to the books (handyman, security).
        public var fixedHours: Bool
        public var items: [Spec]
        public var extra: [Spec]
    }

    static func decodeSpec(_ j: JSONValue) -> Spec {
        Spec(name: j["n"].string, model: ItemModels.Model(rawValue: j["m"].string) ?? .svc, share: j["share"].double, rel: j["rel"].double,
             hours: j["h"].double, crew: j["crew"].array.map { $0.string }, mat: j["mat"].double, sub: j["sub"].double, markup: j["mk"].double,
             lead: j["lead"].int, callout: j["co"].bool, warrantyRate: j["wr"].double, warrantyMonths: j["wm"].int, van: j["van"].bool,
             phases: j["ph"].array.map { Phase(name: $0[0].string, share: $0[1].double, sub: $0[2].double) }, visits: j["visits"].double,
             period: max(1, j["period"].int), churn: j["churn"].double, contract: j["contract"].bool, doc: j["doc"].string, buy: j["buy"].double,
             note: j["note"].string)
    }

    static let file: JSONValue = {
        guard let url = Bundle.module.url(forResource: "wave7_jobs", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return .null }
        return j
    }()

    public static var fteHours: Double { file["fteHours"].double > 0 ? file["fteHours"].double : 36 }
    /// Share of a job's hours a warranty callback takes, and of its materials.
    public static var callbackHours: Double { file["callbackHours"].double > 0 ? file["callbackHours"].double : 0.4 }
    static let callbackMaterials = 0.25
    /// Employer cost on top of pay.
    public static var onCost: Double { file["onCost"].double > 0 ? file["onCost"].double : 1.2 }

    static let specs: [String: TradeSpec] = {
        var out: [String: TradeSpec] = [:]
        for (k, j) in file["trades"].object {
            out[k] = TradeSpec(trade: k, skill: j["skill"].string, skillLabel: j["skillLabel"].string, fixedHours: j["fixed"].bool, items: j["items"].array.map(decodeSpec),
                               extra: j["extra"].array.map(decodeSpec))
        }
        return out
    }()

    public static func tradeSpec(_ trade: String) -> TradeSpec? { specs[trade] }
    public static var tradeIDs: [String] { specs.keys.sorted() }

    public static func spec(trade: String, itemName: String) -> Spec? {
        guard let t = specs[trade] else { return nil }
        let n = itemName.lowercased()
        return (t.items + t.extra).first { $0.name.lowercased() == n }
    }

    // MARK: Menu weights and cost calibration

    public static func mix(_ items: [Spec]) -> (q: [Double], ratio: [Double]) {
        let total = items.reduce(0.0) { $0 + $1.share }
        guard total > 0 else { return ([], []) }
        let q = items.map { $0.share / total }
        let norm = zip(items, q).reduce(0.0) { $0 + $1.0.rel * $1.1 }
        return (q, items.map { norm > 0 ? $0.rel / norm : 1 })
    }

    /// What the books charge as cost of sales: materials and subcontractors for the job trades (as `ProjectModel` does), `cogs` for the others.
    public static func targetCostShare(_ bd: Trade) -> Double {
        ProjectModel.sellsHours(bd) ? (bd.traits["mat"] ?? 0) + (bd.traits["sub"] ?? 0) : bd.costOfSales
    }

    /// Factor on the materials and subcontract costs that makes the weighted menu equal the books' share. 0 when the books charge none (engineering office).
    public static func calibration(_ t: TradeSpec, target: Double) -> Double {
        let m = mix(t.items)
        var stock = 0.0, direct = 0.0
        for (i, s) in t.items.enumerated() {
            let w = m.q[i] * m.ratio[i]
            if s.isStock { stock += w * s.buy } else { direct += w * (s.mat + s.sub) }
        }
        return direct > 0 ? max(0, target - stock) / direct : 0
    }

    public static func costShare(_ s: Spec, calibration k: Double) -> Double { s.isStock ? s.buy : k * (s.mat + s.sub) }

    // MARK: Hours and labour

    static func meanHours(_ t: TradeSpec) -> Double {
        let rows = t.items.filter { !$0.isStock && $0.hours > 0 }
        let total = rows.reduce(0.0) { $0 + $1.share }
        return total > 0 ? rows.reduce(0.0) { $0 + $1.share * $1.hours } / total : 0
    }

    /// Factor on the data's job hours. Job trades: a job is worth its hours at the books' hour value (`ProjectModel.hourValue`), so the menu's average
    /// job takes the hours its going ticket pays for. Handyman and security sell real time (a guard hour is an hour): hours stay as in the data.
    static func hourScale(_ co: Company, _ bd: Trade, _ t: TradeSpec, _ w: World) -> Double {
        guard ProjectModel.sellsHours(bd), !t.fixedHours else { return 1 }
        let mh = meanHours(t), hv = ProjectModel.hourValue(co, bd, w), mt = SalesItems.marketTicket(co, bd, w)
        return mh > 0 && hv > 0 && mt > 0 ? mt / (hv * mh) : 1
    }

    /// Person-hours the firm can work in a week: the going volume of average jobs for the job trades, the full-time people for the others.
    static func hoursPerWeek(_ t: TradeSpec, scale: Double, _ bd: Trade, _ cap: CapacityResult) -> Double {
        if ProjectModel.sellsHours(bd), !t.fixedHours { return cap.capacity * meanHours(t) * scale }
        return cap.parts.filter { $0.kind == .staff }.reduce(0.0) { $0 + $1.have } * fteHours
    }

    /// Cost of one person-hour of this crew: market pay of its roles, a year over its working hours, plus employer cost.
    static func hourlyCost(_ s: GameState, _ co: Company, crew: [String], data: GameData) -> Double {
        guard !crew.isEmpty else { return 0 }
        let monthly = crew.reduce(0.0) { $0 + ManagerModel.marketWage(s, co, role: $1, data: data) } / Double(crew.count)
        return monthly * 12 / (52 * fteHours) * onCost
    }

    /// Labour plus the expected warranty callbacks of one job (the item's `prep`).
    static func prepCost(labour: Double, materials: Double, _ sp: Spec) -> Double {
        labour + sp.warrantyRate * (labour * callbackHours + materials * callbackMaterials)
    }

    // MARK: Install

    static func isUntouched(_ co: Company, _ bd: Trade) -> Bool {
        let raw = co.value("items27")
        return raw.isNull || SalesItems.items(co, bd) == SalesItems.defaults(co, bd)
    }

    static func weeklyCustomers(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        let lw = co.value("lastW")
        return lw["units"].isNull ? DemandModel.compute(co, bd, w).customers : lw["units"].double
    }

    static let stockCoverWeeks = 3.0
    static let reorderCoverWeeks = 1.0

    /// Most jobs of this kind a week if the whole firm did only that.
    static func maxPerWeek(_ sp: Spec, scale: Double, hoursWeek: Double) -> Double {
        let h = sp.hours * scale
        return h > 0 && hoursWeek > 0 ? hoursWeek / h : 0
    }

    static func makeRecord(_ s: GameState, _ co: Company, _ bd: Trade, _ t: TradeSpec, spec sp: Spec, item: SalesItems.Item, k: Double, mt: Double,
                           scale: Double, hoursWeek: Double, customers: Double, data: GameData) -> ItemModels.Record {
        var r = ItemModels.Record(id: item.id, model: sp.model)
        r.cost = mt * item.ratio * costShare(sp, calibration: k)
        r.leadDays = sp.lead
        if sp.isStock {
            r.stock = Int((customers * item.unitShare * stockCoverWeeks).rounded(.up))
            r.since = s.week
        } else {
            r.prep = prepCost(labour: sp.hours * scale * hourlyCost(s, co, crew: sp.crew, data: data), materials: r.cost, sp)
            r.capacity = maxPerWeek(sp, scale: scale, hoursWeek: hoursWeek)
        }
        return r
    }

    /// Put a company of an opted-in trade on real jobs: an untouched list becomes the trade's real menu, every item without a record gets one.
    /// Idempotent. Returns how many records were made.
    @discardableResult
    public static func install(_ s: inout GameState, companyID: Int, data: GameData, trades: Set<String> = ItemWaves.w7) -> Int {
        guard let i = s.companyIndex(companyID), s.companies[i].status.isLive, trades.contains(s.companies[i].type),
              let t = specs[s.companies[i].type], let bd = data.catalog[s.companies[i].type] else { return 0 }
        if isUntouched(s.companies[i], bd) {
            let m = mix(t.items)
            let svc = SalesItems.isService(bd)
            let list: [SalesItems.Item] = t.items.indices.map { k in
                SalesItems.Item(id: "d\(k)", name: t.items[k].name, isService: svc && !t.items[k].isStock, unitShare: m.q[k], ratio: m.ratio[k],
                                priceMultiplier: 1, discountPercent: 0, discountWeeks: 0, listedForGroup: false)
            }
            SalesItems.store(&s, i, list)
        }
        let co = s.companies[i]
        let list = SalesItems.items(co, bd)
        let missing = list.filter { ItemModels.record(co, itemID: $0.id) == nil }
        guard !missing.isEmpty else { return 0 }
        let w = World(state: s, data: data)
        let mt = SalesItems.marketTicket(co, bd, w)
        let k = calibration(t, target: targetCostShare(bd))
        let cap = CapacityModel.compute(co, bd, w), scale = hourScale(co, bd, t, w), hw = hoursPerWeek(t, scale: scale, bd, cap)
        let customers = weeklyCustomers(co, bd, w)
        var made = 0
        for it in missing {
            if let sp = spec(trade: co.type, itemName: it.name) {
                ItemModels.put(&s, i, makeRecord(s, co, bd, t, spec: sp, item: it, k: k, mt: mt, scale: scale, hoursWeek: hw, customers: customers, data: data))
                made += 1
            } else if ItemModels.migrateItem(&s, companyID: companyID, itemID: it.id, data: data) {
                made += 1
            }
        }
        return made
    }

    // MARK: Weekly

    /// Weekly: records for new items, labour and callback cost at today's pay and hours, capacity, and the stock cycle of stocked items.
    /// Called next to `ItemModels.weeklyTick`. Without an opted-in trade or a record it does nothing.
    public static func weekly(_ s: inout GameState, _ i: Int, data: GameData, trades: Set<String> = ItemWaves.w7) {
        guard s.companies.indices.contains(i), trades.contains(s.companies[i].type) else { return }
        let id = s.companies[i].id
        install(&s, companyID: id, data: data, trades: trades)
        guard let bd = data.catalog[s.companies[i].type], let t = specs[s.companies[i].type] else { return }
        let co = s.companies[i]
        let w = World(state: s, data: data)
        let cap = CapacityModel.compute(co, bd, w), scale = hourScale(co, bd, t, w), hw = hoursPerWeek(t, scale: scale, bd, cap)
        let list = SalesItems.items(co, bd)
        var rate: [String: Double] = [:]
        for r in ItemModels.records(co) where !r.model.holdsStock || r.model == .made {
            guard let it = list.first(where: { $0.id == r.id }), let sp = spec(trade: co.type, itemName: it.name), !sp.isStock else { continue }
            let key = sp.crew.joined(separator: ",")
            let hc = rate[key] ?? hourlyCost(s, co, crew: sp.crew, data: data)
            rate[key] = hc
            let prep = prepCost(labour: sp.hours * scale * hc, materials: r.cost, sp), capNow = maxPerWeek(sp, scale: scale, hoursWeek: hw)
            if abs(prep - r.prep) > 1e-9 || abs(capNow - r.capacity) > 1e-9 {
                ItemModels.mutate(&s, companyID: id, itemID: r.id) { $0.prep = prep; $0.capacity = capNow }
            }
        }
        let rows = SalesItems.rows(s, companyID: id, data: data)
        let week = s.week
        for r in ItemModels.records(s.companies[i]) where r.model == .stk {
            guard let row = rows.first(where: { $0.id == r.id }) else { continue }
            let perWeek = row.weeklyUnits
            ItemModels.mutate(&s, companyID: id, itemID: r.id) { rec in
                var arriving = 0
                rec.plans.removeAll { p in
                    guard p.kind.hasPrefix("order:"), p.week <= week else { return false }
                    arriving += Int(p.kind.dropFirst(6)) ?? 0
                    return true
                }
                if arriving > 0 {
                    rec.onOrder = max(0, rec.onOrder - arriving)
                    if rec.stock == 0 { rec.since = week }
                    rec.stock += arriving
                }
                let sold = min(rec.stock, Int((perWeek * Double(week + 1)).rounded(.down)) - Int((perWeek * Double(week)).rounded(.down)))
                rec.stock -= sold
                if rec.stock == 0 { rec.since = nil }
                let lead = Double(rec.leadDays) / 7
                let level = Int((perWeek * (lead + reorderCoverWeeks)).rounded(.up))
                let target = Int((perWeek * (lead + stockCoverWeeks)).rounded(.up))
                if rec.stock + rec.onOrder <= level, target > rec.stock + rec.onOrder {
                    let n = target - rec.stock - rec.onOrder
                    let due = week + Int(lead.rounded(.up))
                    rec.onOrder += n
                    rec.plans.append(ItemModels.Plan(kind: "order:\(n)", text: "Reorder of \(n) arrives in week \(due).", week: due))
                }
            }
        }
    }

    // MARK: Facts for the item page

    public struct PhaseFact: Equatable, Sendable {
        public var name: String
        public var amount: Double
        public var subcontract: Double
        public var weeks: Double
    }

    public struct Facts: Equatable, Sendable {
        public var itemID: String
        public var name: String
        public var model: ItemModels.Model
        public var price: Double
        public var marketPrice: Double
        /// Materials and subcontractors at cost, what the quote charges for them (cost plus markup) and the markup.
        public var materialsCost: Double
        public var markup: Double
        public var materialsCharge: Double
        /// Labour in the job: person-hours, the crew, cost of it, and what is left of the price for labour after materials.
        public var hours: Double
        public var crew: [String]
        public var crewSize: Int
        public var needsVehicle: Bool
        public var labourCost: Double
        public var labourCharge: Double
        public var chargePerHour: Double
        public var costPerHour: Double
        /// Price against the real cost (materials, labour, expected callbacks) and the profit per person-hour.
        public var fullCost: Double
        public var profit: Double
        public var profitPerHour: Double?
        public var isCallout: Bool
        public var leadDays: Int
        /// Weeks of booked work ahead of a new scheduled job, and when a new job of this kind would really start.
        public var backlogWeeks: Double
        public var startInDays: Double
        public var weeklyJobs: Double
        public var maxPerWeek: Double
        public var utilisation: Double
        public var crewHoursPerWeek: Double
        public var crewFTE: Double
        public var warrantyRate: Double
        public var warrantyMonths: Int
        public var callbacksPerWeek: Double
        public var callbackCostPerWeek: Double
        public var phases: [PhaseFact]
        public var jobWeeks: Double
        public var retention: Double
        public var document: String
        public var note: String
        public var isRecurring: Bool
        public var isContract: Bool
        public var members: Double
        public var periodWeeks: Int
        public var visitsPerPeriod: Double
        public var churnPerPeriod: Double
        public var leavingPerPeriod: Double
        public var recurringPerPeriod: Double
        public var stock: Int
        public var onOrder: Int
        public var weeksOfCover: Double?
    }

    /// Weeks of booked work in the order book (project trades keep real jobs) or, for the other trades, what demand above capacity piles up.
    static func backlogWeeks(_ co: Company, _ bd: Trade, _ cap: CapacityResult, utilisation: Double) -> Double {
        if ProjectModel.sellsHours(bd) {
            let hw = ProjectModel.hoursPerWeek(bd, capacity: cap.capacity)
            let open = ProjectModel.jobs(co.value("fm")).filter { $0.inHours }.reduce(0.0) { $0 + $1.remainingHours }
            return hw > 0 ? open / hw : 0
        }
        return utilisation > 1 ? (utilisation - 1) * 4 : 0
    }

    public static func facts(_ s: GameState, companyID: Int, itemID: String, data: GameData, trades: Set<String> = ItemWaves.w7) -> Facts? {
        guard let co = s.company(companyID), trades.contains(co.type), let bd = data.catalog[co.type], let t = specs[co.type],
              let it = SalesItems.items(co, bd).first(where: { $0.id == itemID }), let sp = spec(trade: co.type, itemName: it.name),
              let row = SalesItems.rows(s, companyID: companyID, data: data).first(where: { $0.id == itemID }) else { return nil }
        let w = World(state: s, data: data)
        let rec = ItemModels.record(co, itemID: itemID)
        let cap = CapacityModel.compute(co, bd, w), scale = hourScale(co, bd, t, w), hw = hoursPerWeek(t, scale: scale, bd, cap)
        let materials = rec?.cost ?? ItemModels.fallbackCost(market: row.marketPrice, bd)
        let hours = sp.isStock ? 0 : sp.hours * scale
        let hc = hourlyCost(s, co, crew: sp.crew, data: data)
        let labour = hours * hc
        let full = rec.map { ItemModels.unitCost($0, weeksHeld: $0.since.map { s.week - $0 } ?? 0, supplierDiscount: ItemModels.supplierDiscount(s, $0)) }
            ?? materials
        let charge = materials * (1 + sp.markup)
        let labourCharge = max(0, row.price - charge)
        let served = row.weeklyUnits
        let maxWeek = sp.isStock ? 0 : maxPerWeek(sp, scale: scale, hoursWeek: hw)
        let util = maxWeek > 0 ? served / maxWeek : 0
        let backlog = sp.isStock ? 0 : backlogWeeks(co, bd, cap, utilisation: hw > 0 ? served * hours / hw : 0)
        let crewHours = served * hours
        let callbacks = served * sp.warrantyRate
        let weeks = hours > 0 && !sp.crew.isEmpty ? hours / (Double(sp.crew.count) * fteHours) : 0
        let phases = sp.phases.map { PhaseFact(name: $0.name, amount: row.price * $0.share, subcontract: row.price * $0.share * $0.sub, weeks: weeks * $0.share) }
        let recurring = sp.model == .sub && sp.visits > 0
        let members = recurring ? served * Double(sp.period) / sp.visits : 0
        return Facts(itemID: itemID, name: it.name, model: sp.model, price: row.price, marketPrice: row.marketPrice, materialsCost: materials, markup: sp.markup,
                     materialsCharge: charge, hours: hours, crew: sp.crew, crewSize: sp.crew.count, needsVehicle: sp.van, labourCost: labour,
                     labourCharge: labourCharge, chargePerHour: hours > 0 ? labourCharge / hours : 0, costPerHour: hc, fullCost: full,
                     profit: row.price - full, profitPerHour: hours > 0 ? (row.price - full) / hours : nil, isCallout: sp.callout, leadDays: sp.lead,
                     backlogWeeks: backlog, startInDays: sp.callout ? Double(sp.lead) : max(Double(sp.lead), backlog * 7), weeklyJobs: served,
                     maxPerWeek: maxWeek, utilisation: util, crewHoursPerWeek: crewHours, crewFTE: crewHours / fteHours, warrantyRate: sp.warrantyRate,
                     warrantyMonths: sp.warrantyMonths, callbacksPerWeek: callbacks,
                     callbackCostPerWeek: callbacks * (labour * callbackHours + materials * callbackMaterials), phases: phases, jobWeeks: weeks,
                     retention: row.price * (bd.traits["retention"] ?? 0), document: sp.doc, note: sp.note, isRecurring: recurring, isContract: sp.contract,
                     members: members, periodWeeks: sp.period, visitsPerPeriod: sp.visits, churnPerPeriod: sp.churn, leavingPerPeriod: members * sp.churn,
                     recurringPerPeriod: members * sp.visits * row.price, stock: rec?.stock ?? 0, onOrder: rec?.onOrder ?? 0,
                     weeksOfCover: sp.isStock && served > 0 ? Double(rec?.stock ?? 0) / served : nil)
    }
}
