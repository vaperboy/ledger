import Foundation
import GameCore
import Countries
import Finance

/// SVC appointment and crew model: barber, driving school, physio, dental, car cleaning and cleaning company sell real services.
/// A service is an item with a price per job (appointment, lesson, car, cleaning hour), a duration, the skill and the room, chair, car or crew it
/// needs, consumables or lab cost per job, a no-show and rebooking rate, recurring customers (membership, recall plan, fleet and office contracts)
/// and, for retail products, stock with a reorder cycle. The data is `Resources/appointment_services.json`; nothing is stored beyond the item records
/// (`itemsv2`) and the item list (`items27`) that already exist, so the save format does not change.
/// Money: the books keep the trade's cost-of-sales share (`trades.json`). The per-item costs are scaled on install so the whole menu weighs
/// exactly that share (a crown costs more than a check-up, the average is the trade's own), and the revenue weights add up to 1 as before, so a
/// company that never touches a price plays as it did. Nothing here moves cash: retail stock is a shelf and a reorder cycle whose cost is already in
/// the cost of sales.
public enum AppointmentServices {
    // MARK: Spec

    public struct Spec: Equatable, Sendable {
        public var name: String
        public var model: ItemModels.Model
        /// Relative customers and relative price (normalised per menu on install).
        public var share: Double
        public var rel: Double
        /// Chair, bay, car, room or crew minutes of one job.
        public var minutes: Int
        /// Consumables and other direct cost (lab fee, car running, implant part) as shares of the price, before scaling to the trade's cost of sales.
        public var cons: Double
        public var dir: Double
        /// Jobs priced and sold together (block of 10 lessons, course of 6).
        public var pack: Int
        /// Recurring: jobs per billing period of `period` weeks, share of members leaving per period.
        public var visits: Double
        public var period: Int
        public var churn: Double
        public var lead: Int
        /// The room or machine this job needs when it is not the trade's main one ("room", "sim").
        public var resource: String
        /// Customers served at once (theory classroom, class).
        public var seats: Int
        public var travel: Int
        /// The skill this job needs when it is not the trade's main one (the hygienist).
        public var skill: String
        public var contract: Bool
        public var skillLabel: String
        public var resourceLabel: String
        public var isRetail: Bool { model == .stk }
    }

    public struct TradeSpec: Equatable, Sendable {
        public var trade: String
        public var skill: String
        public var skillLabel: String
        public var resource: String
        public var resourceEquipment: String
        public var resourceLabel: String
        public var noShow: Double
        public var rebook: Double
        public var reminderEquipment: String
        public var reminderCut: Double
        public var travelMinutes: Int
        public var crew: Int
        public var items: [Spec]
        public var extra: [Spec]
    }

    static func decodeSpec(_ j: JSONValue) -> Spec {
        let m = ItemModels.Model(rawValue: j["m"].string) ?? .svc
        return Spec(name: j["n"].string, model: m, share: j["share"].double, rel: j["rel"].double, minutes: j["min"].int, cons: j["cons"].double,
                    dir: j["dir"].double, pack: max(1, j["pack"].int), visits: j["visits"].double, period: max(1, j["period"].int), churn: j["churn"].double,
                    lead: j["lead"].int, resource: j["res"].string, seats: max(1, j["seats"].int), travel: j["travel"].int, skill: j["skill"].string,
                    contract: j["contract"].bool, skillLabel: j["skillLabel"].string, resourceLabel: j["resLabel"].string)
    }

    static let file: JSONValue = {
        guard let url = Bundle.module.url(forResource: "appointment_services", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return .null }
        return j
    }()

    /// Hours one full-time person works in a week.
    public static var fteHours: Double { file["fteHours"].double > 0 ? file["fteHours"].double : 36 }

    static let specs: [String: TradeSpec] = {
        var out: [String: TradeSpec] = [:]
        for (k, j) in file["trades"].object {
            out[k] = TradeSpec(trade: k, skill: j["skill"].string, skillLabel: j["skillLabel"].string, resource: j["res"].string,
                               resourceEquipment: j["resEq"].string, resourceLabel: j["resLabel"].string, noShow: j["noShow"].double,
                               rebook: j["rebook"].double, reminderEquipment: j["remindEq"].string, reminderCut: j["remindCut"].double,
                               travelMinutes: j["travelMin"].int, crew: max(1, j["crew"].int), items: j["items"].array.map(decodeSpec),
                               extra: j["extra"].array.map(decodeSpec))
        }
        return out
    }()

    public static func tradeSpec(_ trade: String) -> TradeSpec? { specs[trade] }
    public static var tradeIDs: [String] { specs.keys.sorted() }

    /// The spec of an item by name (the menu, then the add-item catalogue), nil for an item that is not a real service of these trades.
    public static func spec(trade: String, itemName: String) -> Spec? {
        guard let t = specs[trade] else { return nil }
        let n = itemName.lowercased()
        return (t.items + t.extra).first { $0.name.lowercased() == n }
    }

    // MARK: Menu weights and cost calibration

    /// Unit shares and price ratios of a menu: shares add up to 1, share x ratio adds up to 1 (the same convention as `SalesItems.defaults`).
    public static func mix(_ items: [Spec]) -> (q: [Double], ratio: [Double]) {
        let total = items.reduce(0.0) { $0 + $1.share }
        guard total > 0 else { return ([], []) }
        let q = items.map { $0.share / total }
        let norm = zip(items, q).reduce(0.0) { $0 + $1.0.rel * $1.1 }
        return (q, items.map { norm > 0 ? $0.rel / norm : 1 })
    }

    /// Factor on the service costs that makes the weighted cost of the whole menu equal the trade's cost-of-sales share (`cogs`).
    /// Retail stock keeps its own buy share. 1 means the data already agreed with the books.
    public static func calibration(_ t: TradeSpec, cogs: Double) -> Double {
        let m = mix(t.items)
        var retail = 0.0, service = 0.0
        for (i, s) in t.items.enumerated() {
            let w = m.q[i] * m.ratio[i]
            if s.isRetail { retail += w * s.cons } else { service += w * (s.cons + s.dir) }
        }
        return service > 0 ? max(0, cogs - retail) / service : 0
    }

    /// Cost of one job as a share of its price after calibration.
    public static func costShare(_ s: Spec, calibration k: Double) -> Double { s.isRetail ? s.cons : k * (s.cons + s.dir) }

    /// Average job length of the menu in minutes, weighted by customers (retail excluded).
    static func averageMinutes(_ t: TradeSpec) -> Double {
        let rows = t.items.filter { !$0.isRetail && $0.minutes > 0 }
        let total = rows.reduce(0.0) { $0 + $1.share }
        return total > 0 ? rows.reduce(0.0) { $0 + $1.share * Double($1.minutes) } / total : 0
    }

    // MARK: Install

    /// An item list nobody has changed: the default list, every price at market, no discount.
    static func isUntouched(_ co: Company, _ bd: Trade) -> Bool {
        let raw = co.value("items27")
        return raw.isNull || SalesItems.items(co, bd) == SalesItems.defaults(co, bd)
    }

    static func capacityPerWeek(_ co: Company, _ bd: Trade, _ w: World) -> Double { CapacityModel.compute(co, bd, w).capacity }

    /// Most jobs of this kind a week if the whole company did only that.
    static func maxPerWeek(_ spec: Spec, _ t: TradeSpec, capacity: Double) -> Double {
        guard spec.minutes > 0, capacity > 0 else { return 0 }
        return capacity * averageMinutes(t) / Double(spec.minutes)
    }

    static func weeklyCustomers(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        let lw = co.value("lastW")
        return lw["units"].isNull ? DemandModel.compute(co, bd, w).customers : lw["units"].double
    }

    /// Weeks of retail stock kept on the shelf once a reorder arrives, and the weeks of cover at which a new order is placed (plus the lead time).
    static let stockCoverWeeks = 3.0
    static let reorderCoverWeeks = 1.0

    static func makeRecord(_ co: Company, _ bd: Trade, _ t: TradeSpec, spec sp: Spec, item: SalesItems.Item, k: Double, mt: Double, capacity: Double,
                           customers: Double, week: Int) -> ItemModels.Record {
        var r = ItemModels.Record(id: item.id, model: sp.model)
        r.cost = mt * item.ratio * costShare(sp, calibration: k)
        r.leadDays = sp.lead
        if sp.isRetail {
            let perWeek = customers * item.unitShare
            r.stock = Int(saturating: (perWeek * stockCoverWeeks).rounded(.up))
            r.since = week
        } else {
            r.capacity = maxPerWeek(sp, t, capacity: capacity)
        }
        return r
    }

    /// Put a company of an opted-in trade on real services: an untouched item list becomes the trade's real menu, every item without a record gets
    /// one (a known service from its spec, any other item from the old cost-of-sales share). Idempotent. Returns how many records were made.
    @discardableResult
    public static func install(_ s: inout GameState, companyID: Int, data: GameData, trades: Set<String> = ItemTradeGroups.appointments) -> Int {
        guard let i = s.companyIndex(companyID), s.companies[i].status.isLive, trades.contains(s.companies[i].type),
              let t = specs[s.companies[i].type], let bd = data.catalog[s.companies[i].type] else { return 0 }
        if isUntouched(s.companies[i], bd) {
            let m = mix(t.items)
            let svc = SalesItems.isService(bd)
            let list: [SalesItems.Item] = t.items.indices.map { k in
                SalesItems.Item(id: "d\(k)", name: t.items[k].name, isService: svc && !t.items[k].isRetail, unitShare: m.q[k], ratio: m.ratio[k],
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
        let k = calibration(t, cogs: bd.costOfSales)
        let capacity = capacityPerWeek(co, bd, w), customers = weeklyCustomers(co, bd, w)
        var made = 0
        for it in missing {
            if let sp = spec(trade: co.type, itemName: it.name) {
                ItemModels.put(&s, i, makeRecord(co, bd, t, spec: sp, item: it, k: k, mt: mt, capacity: capacity, customers: customers, week: s.week))
                made += 1
            } else if ItemModels.migrateItem(&s, companyID: companyID, itemID: it.id, data: data) {
                made += 1
            }
        }
        return made
    }

    // MARK: Weekly

    /// Weekly for a company of an opted-in trade: records for new items, then retail stock: arrivals, what was sold, a new order when cover runs short.
    /// Called next to `ItemModels.weeklyTick`. Without an opted-in trade or a record it does nothing.
    public static func weekly(_ s: inout GameState, _ i: Int, data: GameData, trades: Set<String> = ItemTradeGroups.appointments) {
        guard s.companies.indices.contains(i), trades.contains(s.companies[i].type) else { return }
        let id = s.companies[i].id
        install(&s, companyID: id, data: data, trades: trades)
        let rows = SalesItems.rows(s, companyID: id, data: data)
        let week = s.week
        for r in ItemModels.records(s.companies[i]) where r.model == .stk {
            guard let row = rows.first(where: { $0.id == r.id }) else { continue }
            let perWeek = row.weeklyUnits
            // A small shop sells a fraction of a unit a week: the fraction is carried (company key `w6frac:<item>`) so stock still runs down.
            let owed = s.companies[i].num("w6frac:" + r.id) + perWeek
            var carry = owed
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
                let sold = min(rec.stock, Int(saturating: owed.rounded(.down)))
                carry = sold < Int(saturating: owed.rounded(.down)) ? 0 : owed - Double(sold)
                rec.stock -= sold
                if rec.stock == 0 { rec.since = nil }
                let lead = Double(rec.leadDays) / 7
                let level = Int(saturating: (perWeek * (lead + reorderCoverWeeks)).rounded(.up))
                let target = Int(saturating: (perWeek * (lead + stockCoverWeeks)).rounded(.up))
                if rec.stock + rec.onOrder <= level, target > rec.stock + rec.onOrder {
                    let n = target - rec.stock - rec.onOrder
                    let due = week + Int(saturating: lead.rounded(.up))
                    rec.onOrder += n
                    rec.plans.append(ItemModels.Plan(kind: "order:\(n)", text: "Reorder of \(n) arrives in week \(due).", week: due))
                }
            }
            s.companies[i].set("w6frac:" + r.id, carry)
        }
    }

    // MARK: Facts for the item page

    public struct Facts: Equatable, Sendable {
        public var itemID: String
        public var name: String
        public var model: ItemModels.Model
        public var minutes: Int
        public var skill: String
        public var resource: String
        public var seats: Int
        public var pack: Int
        public var travelMinutes: Int
        public var price: Double
        public var unitCost: Double
        /// Price less cost of one job per hour of the room, chair, car or crew it occupies; nil for retail.
        public var profitPerResourceHour: Double?
        public var weeklyUnits: Double
        public var maxPerWeek: Double
        public var utilisation: Double
        public var noShowRate: Double
        public var noShowsPerWeek: Double
        public var rebookRate: Double
        public var lostRevenuePerWeek: Double
        /// A reminder system (booking system, patient journal) is in place and cuts no-shows.
        public var remindersOn: Bool
        public var isRecurring: Bool
        public var members: Double
        public var periodWeeks: Int
        public var visitsPerPeriod: Double
        public var churnPerPeriod: Double
        public var leavingPerPeriod: Double
        public var recurringPerPeriod: Double
        public var isContract: Bool
        /// Contract hours a week the rota must cover, and the full-time people that takes.
        public var contractHoursPerWeek: Double
        public var crewFTE: Double
        public var stock: Int
        public var onOrder: Int
        public var weeksOfCover: Double?
    }

    static func ownedCount(_ co: Company, _ equipmentID: String) -> Double {
        guard !equipmentID.isEmpty else { return 0 }
        return co.value("eq")[equipmentID]["n"].double + co.value("lease")[equipmentID].double
    }

    public static func facts(_ s: GameState, companyID: Int, itemID: String, data: GameData, trades: Set<String> = ItemTradeGroups.appointments) -> Facts? {
        guard let co = s.company(companyID), trades.contains(co.type), let bd = data.catalog[co.type], let t = specs[co.type],
              let it = SalesItems.items(co, bd).first(where: { $0.id == itemID }), let sp = spec(trade: co.type, itemName: it.name),
              let row = SalesItems.rows(s, companyID: companyID, data: data).first(where: { $0.id == itemID }) else { return nil }
        let rec = ItemModels.record(co, itemID: itemID)
        let cost = rec.map { ItemModels.unitCost($0, weeksHeld: $0.since.map { s.week - $0 } ?? 0, supplierDiscount: ItemModels.supplierDiscount(s, $0)) }
            ?? ItemModels.fallbackCost(market: row.marketPrice, bd)
        let hours = Double(sp.minutes) / 60
        let perHour: Double? = sp.isRetail || hours <= 0 ? nil : (row.price - cost) * Double(sp.seats) / hours
        let reminders = ownedCount(co, t.reminderEquipment) >= 1
        let ns = sp.isRetail ? 0 : t.noShow * (reminders ? 1 - t.reminderCut : 1)
        let served = row.weeklyUnits
        let noShows = ns < 1 ? served / (1 - ns) * ns : 0
        let maxWeek = sp.isRetail ? 0 : maxPerWeek(sp, t, capacity: capacityPerWeek(co, bd, World(state: s, data: data)))
        let recurring = sp.model == .sub && sp.visits > 0
        let members = recurring ? served * Double(sp.period) / sp.visits : 0
        let siteHours = recurring && sp.contract ? served : 0
        return Facts(itemID: itemID, name: it.name, model: sp.model, minutes: sp.minutes, skill: sp.skillLabel.isEmpty ? t.skillLabel : sp.skillLabel,
                     resource: sp.resourceLabel.isEmpty ? t.resourceLabel : sp.resourceLabel, seats: sp.seats, pack: sp.pack,
                     travelMinutes: sp.travel > 0 ? sp.travel : t.travelMinutes, price: row.price, unitCost: cost, profitPerResourceHour: perHour,
                     weeklyUnits: served, maxPerWeek: maxWeek, utilisation: maxWeek > 0 ? served / maxWeek : 0, noShowRate: ns,
                     noShowsPerWeek: noShows, rebookRate: t.rebook, lostRevenuePerWeek: noShows * row.price * (1 - t.rebook), remindersOn: reminders,
                     isRecurring: recurring, members: members, periodWeeks: sp.period, visitsPerPeriod: sp.visits, churnPerPeriod: sp.churn,
                     leavingPerPeriod: members * sp.churn, recurringPerPeriod: members * sp.visits * row.price, isContract: sp.contract,
                     contractHoursPerWeek: siteHours, crewFTE: siteHours / fteHours, stock: rec?.stock ?? 0, onOrder: rec?.onOrder ?? 0,
                     weeksOfCover: sp.isRetail && served > 0 ? Double(rec?.stock ?? 0) / served : nil)
    }
}
