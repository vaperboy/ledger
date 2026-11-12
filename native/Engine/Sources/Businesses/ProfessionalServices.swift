import Foundation
import GameCore
import Countries
import Finance

public enum ProfessionalServices {
    static let seedKey = "w5seed"
    static let resourceName = "professional_services"

    public static func applies(_ trade: String) -> Bool { ItemTradeGroups.professional.contains(trade) && specs[trade] != nil }

    struct Goods { var materials: Double; var hours: Double; var batch: Int; var restockWeeks: Double }

    struct Spec {
        var id: String
        var name: String
        var unit: String
        var hours: Double
        var rate: Double
        var share: Double
        var roles: [(role: String, weight: Double)]
        var consumables: Double
        var writeOff: Double
        var leadDays: Int
        var client: String
        var model: ItemModels.Model
        var churn: Double
        var start: Bool
        var isService: Bool
        var goods: Goods?
        var text: String
        var itemID: String { "w5-" + id }
    }

    struct TradeSpec {
        var hoursPerBlock: Double
        var labourShare: Double
        var plannedUtilisation: Double
        var fixedShare: Double
        var items: [Spec]
    }

    static let specs: [String: TradeSpec] = {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return [:] }
        var out: [String: TradeSpec] = [:]
        for (trade, t) in j["trades"].object {
            let items: [Spec] = t["items"].array.map { x in
                let g = x["goods"]
                return Spec(id: x["id"].string, name: x["n"].string, unit: x["u"].string, hours: x["h"].double, rate: x["f"].double, share: x["q"].double,
                            roles: x["roles"].array.map { (role: $0[0].string, weight: $0[1].double) },
                            consumables: x["c"].double, writeOff: x["wo"].double, leadDays: x["lead"].int, client: x["cl"].string,
                            model: ItemModels.Model(rawValue: x["m"].string) ?? .svc, churn: x["churn"].double, start: x["start"].bool,
                            isService: x["svc"].bool,
                            goods: g.isNull ? nil : Goods(materials: g["mat"].double, hours: g["hrs"].double, batch: g["batch"].int, restockWeeks: g["restock"].double),
                            text: x["d"].string)
            }
            out[trade] = TradeSpec(hoursPerBlock: max(0.1, t["hpu"].double), labourShare: t["L"].double, plannedUtilisation: t["u0"].double, fixedShare: t["fix"].double, items: items)
        }
        return out
    }()

    public static func serviceNames(_ trade: String) -> [String] { specs[trade]?.items.map { $0.name } ?? [] }
    public static func startNames(_ trade: String) -> [String] { specs[trade]?.items.filter { $0.start }.map { $0.name } ?? [] }

    static func spec(_ ts: TradeSpec, item: SalesItems.Item) -> Spec? {
        if let s = ts.items.first(where: { $0.itemID == item.id }) { return s }
        let n = item.name.lowercased()
        return ts.items.first { $0.name.lowercased() == n } ?? ts.items.first { n.contains($0.name.lowercased()) }
    }

    static func labourFactor(_ sp: Spec, _ bd: Trade, _ data: GameData) -> Double {
        let roles = data.catalog.tables.roles
        func wage(_ r: String) -> Double { roles[r]?.baseMonthlyWage ?? 0 }
        let staff = bd.standardStaff
        let n = staff.reduce(0.0) { $0 + $1.1 }
        let avg = n > 0 ? staff.reduce(0.0) { $0 + wage($1.0) * $1.1 } / n : 0
        let total = sp.roles.reduce(0.0) { $0 + $1.weight }
        guard avg > 0, total > 0 else { return 1 }
        return sp.roles.reduce(0.0) { $0 + wage($1.role) * $1.weight } / total / avg
    }

    static func roleLabel(_ sp: Spec, _ data: GameData) -> String {
        let names: [String] = sp.roles.filter { $0.weight > 0 }.map { (data.catalog.tables.roles[$0.role]?.name ?? $0.role).lowercased() }
        guard let first = names.first else { return "" }
        let s = names.count > 1 ? names.joined(separator: " and ") : first
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    static func utilisation(_ co: Company) -> Double? {
        let lw = co.value("lastW")
        guard !lw.isNull, lw["cap"].double > 0 else { return nil }
        return lw["util"].double
    }

    static func costs(_ co: Company, _ bd: Trade, _ ts: TradeSpec, _ sp: Spec, market: Double, ticket: Double, data: GameData) -> (cost: Double, prep: Double) {
        if let g = sp.goods {
            let hourly = ts.labourShare * ticket / ts.hoursPerBlock * labourFactor(sp, bd, data)
            return (g.materials * market, g.hours * hourly)
        }
        let util = utilisation(co).map { min(1, max(0.01, $0)) } ?? ts.plannedUtilisation
        let quiet = ts.fixedShare * ts.plannedUtilisation / util + (1 - ts.fixedShare)
        let labour = ts.labourShare * ticket * labourFactor(sp, bd, data) * quiet
        return (labour, (sp.consumables + sp.writeOff) * market)
    }

    public struct Economics: Equatable, Sendable {
        public var name: String
        public var text: String
        public var unit: String
        public var model: ItemModels.Model
        public var isGoods: Bool
        public var hoursPerJob: Double
        public var hoursPerBlock: Double
        public var blockPrice: Double
        public var hourlyRate: Double
        public var jobPrice: Double
        public var fairHourly: Double
        public var priceVsFair: Double
        public var unitCost: Double
        public var costPerHour: Double
        public var breakEvenHourly: Double
        public var live: ItemModels.LiveProfit
        public var profitPerHour: Double
        public var weeklyUnits: Double
        public var weeklyProfit: Double
        public var weeklyWriteOff: Double
        public var billedHours: Double
        public var jobsPerWeek: Double
        public var consumablesShare: Double
        public var writeOffShare: Double
        public var roleLabel: String
        public var clientLabel: String
        public var clients: Double?
        public var churn: Double
        public var leadDays: Int
        public var utilisation: Double?
        public var plannedUtilisation: Double
        public var capacityHours: Double
        public var saleProbability: Double
        public var stock: Int
        public var onOrder: Int
        public var sliderLow: Double
        public var sliderHigh: Double
    }

    static func clientLabel(_ c: String) -> String {
        switch c {
        case "retainer": return "Retainer clients"
        case "b2c": return "Households"
        default: return "Business clients"
        }
    }

    public static func economics(_ s: GameState, companyID: Int, itemID: String, price: Double? = nil, data: GameData) -> Economics? {
        guard let co = s.company(companyID), applies(co.type), let bd = data.catalog[co.type], let ts = specs[co.type],
              let it = SalesItems.items(co, bd).first(where: { $0.id == itemID }), let sp = spec(ts, item: it),
              let row = SalesItems.rows(s, companyID: companyID, data: data).first(where: { $0.id == itemID }) else { return nil }
        let w = World(state: s, data: data)
        let ticket = SalesItems.marketTicket(co, bd, w)
        let c = costs(co, bd, ts, sp, market: row.marketPrice, ticket: ticket, data: data)
        let rec = ItemModels.record(co, itemID: itemID)
        let held = rec.flatMap { r in r.since.map { s.week - $0 } } ?? 0
        let unit = c.cost * (1 - (rec.map { ItemModels.supplierDiscount(s, $0) } ?? 0)) + c.prep + (rec?.holdingPerWeek ?? 0) * Double(max(0, held))
        let p = price ?? row.price
        let live = ItemModels.liveProfit(price: p, cost: unit)
        let hpb = ts.hoursPerBlock
        let fair = (rec?.fair ?? 0) > 0 ? rec!.fair : row.marketPrice
        let f = SalesItems.forecast(s, companyID: companyID, itemID: itemID, price: p, discountPercent: row.discountPercent, data: data)
        let goods = sp.goods != nil
        let perHour = goods ? 1.0 : hpb
        let hours = goods ? 0 : f.units * hpb
        let jobs = goods ? f.units : (sp.hours > 0 ? hours / sp.hours : 0)
        let util = utilisation(co)
        let cap = co.value("lastW")["cap"].double * hpb
        let low = row.marketPrice * SalesItems.range(for: bd).lowerBound / perHour, high = row.marketPrice * SalesItems.range(for: bd).upperBound / perHour
        let rate = p / perHour
        return Economics(name: sp.name, text: sp.text, unit: sp.unit, model: sp.model, isGoods: goods, hoursPerJob: sp.hours, hoursPerBlock: hpb,
                         blockPrice: p, hourlyRate: rate, jobPrice: goods ? p : rate * sp.hours, fairHourly: row.marketPrice / perHour,
                         priceVsFair: fair > 0 ? p / fair : 0, unitCost: unit, costPerHour: unit / perHour, breakEvenHourly: unit / perHour, live: live,
                         profitPerHour: live.amount / perHour, weeklyUnits: f.units, weeklyProfit: f.revenue - f.units * unit,
                         weeklyWriteOff: f.revenue * sp.writeOff, billedHours: hours, jobsPerWeek: jobs, consumablesShare: sp.consumables, writeOffShare: sp.writeOff,
                         roleLabel: roleLabel(sp, data), clientLabel: clientLabel(sp.client),
                         clients: sp.model == .sub && !goods ? jobs * 52.0 / 12.0 : nil, churn: sp.churn, leadDays: sp.leadDays, utilisation: util,
                         plannedUtilisation: ts.plannedUtilisation, capacityHours: cap, saleProbability: ItemModels.saleProbability(price: p, fair: fair),
                         stock: rec?.stock ?? 0, onOrder: rec?.onOrder ?? 0, sliderLow: low, sliderHigh: high)
    }

    public static func weekly(_ s: inout GameState, _ i: Int, data: GameData) {
        guard s.companies[i].status == .open, applies(s.companies[i].type), let bd = data.catalog[s.companies[i].type], let ts = specs[s.companies[i].type] else { return }
        if s.companies[i].value(seedKey).isNull { seed(&s, i, bd, ts) }
        adopt(&s, i, bd, ts, data: data)
        refresh(&s, i, bd, ts, data: data)
    }

    public static func prepare(_ s: inout GameState, companyID: Int, data: GameData) {
        if let i = s.companyIndex(companyID) { weekly(&s, i, data: data) }
    }

    static func seed(_ s: inout GameState, _ i: Int, _ bd: Trade, _ ts: TradeSpec) {
        s.companies[i].set(seedKey, 1)
        guard s.companies[i].value("items27").isNull else { return }
        let start = ts.items.filter { $0.start }
        let total = start.reduce(0.0) { $0 + $1.share }
        let mean = start.reduce(0.0) { $0 + $1.share / total * $1.rate }
        guard total > 0, mean > 0 else { return }
        let list = start.map { sp in
            SalesItems.Item(id: sp.itemID, name: sp.name, isService: sp.isService, unitShare: sp.share / total, ratio: sp.rate / mean, priceMultiplier: 1,
                            discountPercent: 0, discountWeeks: 0, listedForGroup: false)
        }
        SalesItems.store(&s, i, list)
        let old = s.companies[i].value(ItemModels.key)
        if !old.isNull {
            var o = old.object
            for k in Array(o.keys) where k.count >= 2 && k.hasPrefix("d") && Int(k.dropFirst()) != nil { o.removeValue(forKey: k) }
            s.companies[i].set(ItemModels.key, .object(o))
        }
    }

    static func adopt(_ s: inout GameState, _ i: Int, _ bd: Trade, _ ts: TradeSpec, data: GameData) {
        let id = s.companies[i].id
        for it in SalesItems.items(s.companies[i], bd) where ItemModels.record(s.companies[i], itemID: it.id) == nil {
            guard let sp = spec(ts, item: it) else { _ = ItemModels.migrateItem(&s, companyID: id, itemID: it.id, data: data); continue }
            var list = SalesItems.items(s.companies[i], bd)
            let others = list.filter { o in o.id != it.id && ItemModels.record(s.companies[i], itemID: o.id) != nil }
            let refShare = others.reduce(0.0) { $0 + $1.unitShare * $1.ratio }
            let refRate = others.reduce(0.0) { $0 + $1.unitShare * (spec(ts, item: $1)?.rate ?? 0) }
            if let k = list.firstIndex(where: { $0.id == it.id }), refShare > 0, refRate > 0, list[k].ratio == 1 {
                list[k].ratio = sp.rate * refShare / refRate
                let norm = list.reduce(0.0) { $0 + $1.unitShare * $1.ratio }
                if norm > 0 { for j in list.indices { list[j].ratio /= norm } }
                let ratios = Dictionary(list.map { ($0.id, $0.ratio) }, uniquingKeysWith: { a, _ in a })
                SalesItems.mutate(&s, companyID: id, data: data) { saved in
                    for j in saved.indices { if let r = ratios[saved[j].id] { saved[j].ratio = r } }
                }
            }
            var r = ItemModels.Record(id: it.id, model: sp.model)
            r.leadDays = sp.leadDays
            if sp.goods != nil, sp.model.holdsStock, let g = sp.goods { r.stock = g.batch; r.since = s.week }
            ItemModels.put(&s, i, r)
        }
    }

    static func refresh(_ s: inout GameState, _ i: Int, _ bd: Trade, _ ts: TradeSpec, data: GameData) {
        let co = s.companies[i]
        let id = co.id
        let w = World(state: s, data: data)
        let ticket = SalesItems.marketTicket(co, bd, w)
        let rows = SalesItems.rows(s, companyID: id, data: data)
        let cap = co.value("lastW")["cap"].double * ts.hoursPerBlock
        let week = s.week
        for it in SalesItems.items(co, bd) {
            guard let sp = spec(ts, item: it), let row = rows.first(where: { $0.id == it.id }) else { continue }
            let c = costs(co, bd, ts, sp, market: row.marketPrice, ticket: ticket, data: data)
            ItemModels.mutate(&s, companyID: id, itemID: it.id) { r in
                r.cost = c.cost; r.prep = c.prep
                r.leadDays = sp.leadDays
                r.capacity = sp.goods == nil ? cap : 0
                if let g = sp.goods, sp.model.holdsStock { goodsWeek(&r, g, sp, units: row.weeklyUnits, week: week) }
            }
        }
    }

    static func goodsWeek(_ r: inout ItemModels.Record, _ g: Goods, _ sp: Spec, units: Double, week: Int) {
        let due = r.plans.filter { $0.kind == "order" && $0.week <= week }
        for p in due {
            let n = Int(p.text.split(separator: " ").first.map(String.init) ?? "") ?? 0
            r.onOrder = max(0, r.onOrder - n)
            if r.stock == 0 { r.since = week }
            r.stock += n
        }
        r.plans.removeAll { $0.kind == "order" && $0.week <= week }
        let sold = min(r.stock, Int(saturating: units.rounded()))
        r.stock -= sold
        if r.stock == 0 { r.since = nil }
        let want = Int(saturating: (units * g.restockWeeks).rounded(.up))
        if r.stock + r.onOrder < want || (r.stock + r.onOrder == 0 && units > 0) {
            let qty = max(g.batch, want - r.stock - r.onOrder)
            let weeks = max(1, Int(saturating: (Double(sp.leadDays) / 7).rounded(.up)))
            r.onOrder += qty
            r.plans.append(ItemModels.Plan(kind: "order", text: "\(qty) units ordered, due in \(weeks) week\(weeks == 1 ? "" : "s")", week: week + weeks))
        }
    }
}
