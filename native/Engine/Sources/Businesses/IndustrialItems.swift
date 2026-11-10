import Foundation
import GameCore
import Countries
import Finance

public enum IndustrialItems {
    public struct Input: Equatable, Sendable { public var name: String; public var share: Double }

    public struct Spec: Equatable, Sendable {
        public var name: String
        public var model: ItemModels.Model
        public var share: Double
        public var rel: Double
        public var mat: Double
        public var dir: Double
        public var scrap: Double
        public var lead: Int
        public var batch: Int
        public var minutes: Int
        public var madeToOrder: Bool
        public var minQty: Int
        public var unitLabel: String
        public var inputs: [Input]
        public var period: Int
        public var churn: Double
        public var contract: Bool
        public var seats: Int
        public var hours: Double
        public var overrun: Double
        public var devHours: Double
        public var halfLife: Double
        public var yieldRatio: Double
        public var retention: Double
        public var milestones: Int
        public var isGoods: Bool { model == .made }
        public var isDigital: Bool { devHours > 0 }
    }

    public struct TradeSpec: Equatable, Sendable {
        public var trade: String
        public var unit: String
        public var skill: String
        public var resource: String
        public var items: [Spec]
        public var extra: [Spec]
    }

    static func decodeSpec(_ j: JSONValue) -> Spec {
        Spec(name: j["n"].string, model: ItemModels.Model(rawValue: j["m"].string) ?? .made, share: j["share"].double, rel: j["rel"].double,
             mat: j["mat"].double, dir: j["dir"].double, scrap: min(0.5, max(0, j["scrap"].double)), lead: j["lead"].int, batch: max(1, j["batch"].int),
             minutes: j["min"].int, madeToOrder: j["mto"].bool, minQty: j["minQty"].int, unitLabel: j["unitLabel"].string,
             inputs: j["inputs"].array.map { Input(name: $0[0].string, share: $0[1].double) }, period: max(1, j["period"].int), churn: j["churn"].double,
             contract: j["contract"].bool, seats: max(1, j["seats"].int), hours: j["hours"].double, overrun: j["over"].double, devHours: j["dev"].double,
             halfLife: j["half"].double, yieldRatio: j["yield"].isNull ? 1 : max(0.001, j["yield"].double), retention: j["retention"].double, milestones: j["milestones"].int)
    }

    static let file: JSONValue = {
        guard let url = Bundle.module.url(forResource: "industrial_items", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return .null }
        return j
    }()

    static let specs: [String: TradeSpec] = {
        var out: [String: TradeSpec] = [:]
        for (k, j) in file["trades"].object {
            out[k] = TradeSpec(trade: k, unit: j["unit"].string, skill: j["skill"].string, resource: j["res"].string,
                               items: j["items"].array.map(decodeSpec), extra: j["extra"].array.map(decodeSpec))
        }
        return out
    }()

    public static func tradeSpec(_ trade: String) -> TradeSpec? { specs[trade] }
    public static var tradeIDs: [String] { specs.keys.sorted() }
    public static var fteHours: Double { 36 }

    public static func spec(trade: String, itemName: String) -> Spec? {
        guard let t = specs[trade] else { return nil }
        let n = itemName.lowercased()
        return (t.items + t.extra).first { $0.name.lowercased() == n }
    }

    public static func mix(_ items: [Spec]) -> (q: [Double], ratio: [Double]) {
        let total = items.reduce(0.0) { $0 + $1.share }
        guard total > 0 else { return ([], []) }
        let q = items.map { $0.share / total }
        let norm = zip(items, q).reduce(0.0) { $0 + $1.0.rel * $1.1 }
        return (q, items.map { norm > 0 ? $0.rel / norm : 1 })
    }

    static func rawCostShare(_ s: Spec) -> Double { (s.mat + s.dir) / (1 - s.scrap) }

    public static func calibration(_ t: TradeSpec, cogs: Double) -> Double {
        guard cogs > 0 else { return 1 }
        let m = mix(t.items)
        var raw = 0.0
        for (i, s) in t.items.enumerated() { raw += m.q[i] * m.ratio[i] * rawCostShare(s) }
        return raw > 0 ? cogs / raw : 1
    }

    public static func costShare(_ s: Spec, calibration k: Double) -> Double { k * rawCostShare(s) }

    public static func wagePerHour(_ co: Company) -> Double {
        let n = Double(co.staff.count)
        return n > 0 ? co.lastWages / (n * fteHours) : 0
    }

    static func averageMinutes(_ t: TradeSpec) -> Double {
        let rows = t.items.filter { $0.minutes > 0 }
        let total = rows.reduce(0.0) { $0 + $1.share }
        return total > 0 ? rows.reduce(0.0) { $0 + $1.share * Double($1.minutes) } / total : 0
    }

    static func capacityPerWeek(_ co: Company, _ bd: Trade, _ w: World) -> Double { CapacityModel.compute(co, bd, w).capacity }

    static func maxPerWeek(_ s: Spec, _ t: TradeSpec, capacity: Double) -> Double {
        guard s.minutes > 0, capacity > 0, !s.isDigital else { return 0 }
        return capacity * averageMinutes(t) / Double(s.minutes)
    }

    static func weeklyCustomers(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        let lw = co.value("lastW")
        return lw["units"].isNull ? DemandModel.compute(co, bd, w).customers : lw["units"].double
    }

    static let kilosToTonnes = 0.001

    public static func harvestTonnesPerWeek(_ co: Company, _ bd: Trade) -> Double {
        let grow = max(1, bd.trait("grow") ?? 78)
        return co.value("fm")["coh"].array.reduce(0.0) { $0 + $1["n"].double * 5.1 * 0.88 * kilosToTonnes } / grow
    }

    static func rate(_ co: Company, _ bd: Trade, spec sp: Spec, q: Double, qTotal: Double, row: SalesItem) -> Double {
        guard bd.id == "salmon", sp.isGoods, qTotal > 0 else { return row.weeklyUnits }
        return harvestTonnesPerWeek(co, bd) * q / qTotal * sp.yieldRatio
    }

    static let stockCoverWeeks = 3.0
    static let reorderCoverWeeks = 1.0

    static func isUntouched(_ co: Company, _ bd: Trade) -> Bool {
        let raw = co.value("items27")
        return raw.isNull || SalesItems.items(co, bd) == SalesItems.defaults(co, bd)
    }

    static func holdsFinishedStock(_ sp: Spec) -> Bool { sp.model == .made && !sp.isDigital && !sp.madeToOrder }

    static func makeRecord(_ sp: Spec, item: SalesItems.Item, k: Double, mt: Double, capacity: Double, t: TradeSpec, perWeek: Double, week: Int) -> ItemModels.Record {
        var r = ItemModels.Record(id: item.id, model: sp.isDigital && sp.model == .made ? .proj : sp.model)
        r.cost = mt * item.ratio * costShare(sp, calibration: k)
        r.leadDays = sp.lead
        r.capacity = maxPerWeek(sp, t, capacity: capacity)
        if holdsFinishedStock(sp) {
            r.stock = Int(saturating: (perWeek * stockCoverWeeks).rounded(.up))
            r.since = week
        }
        return r
    }

    @discardableResult
    public static func install(_ s: inout GameState, companyID: Int, data: GameData, trades: Set<String> = ItemTradeGroups.industrial) -> Int {
        guard let i = s.companyIndex(companyID), s.companies[i].status.isLive, trades.contains(s.companies[i].type),
              let t = specs[s.companies[i].type], let bd = data.catalog[s.companies[i].type] else { return 0 }
        if isUntouched(s.companies[i], bd) {
            let m = mix(t.items)
            let svc = SalesItems.isService(bd)
            let list: [SalesItems.Item] = t.items.indices.map { k in
                SalesItems.Item(id: "d\(k)", name: t.items[k].name, isService: svc || t.items[k].model == .svc || t.items[k].model == .sub,
                                unitShare: m.q[k], ratio: m.ratio[k], priceMultiplier: 1, discountPercent: 0, discountWeeks: 0, listedForGroup: false)
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
        let qTotal = list.reduce(0.0) { $0 + $1.unitShare }
        var made = 0
        for it in missing {
            if let sp = spec(trade: co.type, itemName: it.name) {
                let per = bd.id == "salmon" ? harvestTonnesPerWeek(co, bd) * it.unitShare / max(1e-9, qTotal) * sp.yieldRatio : customers * it.unitShare
                ItemModels.put(&s, i, makeRecord(sp, item: it, k: k, mt: mt, capacity: capacity, t: t, perWeek: per, week: s.week))
                made += 1
            } else if ItemModels.migrateItem(&s, companyID: companyID, itemID: it.id, data: data) {
                made += 1
            }
        }
        return made
    }

    public static func weekly(_ s: inout GameState, _ i: Int, data: GameData, trades: Set<String> = ItemTradeGroups.industrial) {
        guard s.companies.indices.contains(i), trades.contains(s.companies[i].type) else { return }
        let id = s.companies[i].id
        install(&s, companyID: id, data: data, trades: trades)
        guard let bd = data.catalog[s.companies[i].type] else { return }
        let co = s.companies[i]
        let list = SalesItems.items(co, bd)
        let qTotal = list.reduce(0.0) { $0 + $1.unitShare }
        let rows = SalesItems.rows(s, companyID: id, data: data)
        let week = s.week
        for r in ItemModels.records(co) where r.model == .made {
            guard let row = rows.first(where: { $0.id == r.id }), let it = list.first(where: { $0.id == r.id }),
                  let sp = spec(trade: co.type, itemName: it.name), holdsFinishedStock(sp) else { continue }
            let perWeek = rate(co, bd, spec: sp, q: it.unitShare, qTotal: qTotal, row: row)
            ItemModels.mutate(&s, companyID: id, itemID: r.id) { rec in
                var arriving = 0
                rec.plans.removeAll { p in
                    guard p.kind.hasPrefix("batch:"), p.week <= week else { return false }
                    arriving += Int(p.kind.dropFirst(6)) ?? 0
                    return true
                }
                if arriving > 0 {
                    rec.onOrder = max(0, rec.onOrder - arriving)
                    if rec.stock == 0 { rec.since = week }
                    rec.stock += arriving
                }
                let sold = min(rec.stock, max(0, Int(saturating: (perWeek * Double(week + 1)).rounded(.down)) - Int(saturating: (perWeek * Double(week)).rounded(.down))))
                rec.stock -= sold
                if rec.stock == 0 { rec.since = nil }
                let lead = Double(rec.leadDays) / 7
                let level = Int(saturating: (perWeek * (lead + reorderCoverWeeks)).rounded(.up))
                let target = Int(saturating: (perWeek * (lead + stockCoverWeeks)).rounded(.up))
                if rec.stock + rec.onOrder <= level, target > rec.stock + rec.onOrder {
                    let need = target - rec.stock - rec.onOrder
                    let n = Int(saturating: (Double(need) / Double(sp.batch)).rounded(.up)) * sp.batch
                    let due = week + Int(saturating: lead.rounded(.up))
                    rec.onOrder += n
                    rec.plans.append(ItemModels.Plan(kind: "batch:\(n)", text: "Batch of \(n) is ready in week \(due).", week: due))
                }
            }
        }
    }

    public struct StartupLive: Equatable, Sendable {
        public var phase: String
        public var customers: Double
        public var quality: Double
        public var weeklyChurn: Double
    }

    public static func startupLive(_ s: GameState, companyID: Int) -> StartupLive? {
        guard let k = StartupModel.recordIndex(s, companyID: companyID), let list = s.rest["founded"]?.array, list.indices.contains(k) else { return nil }
        let f = list[k], w = f["sw16"]
        guard !w.isNull else { return nil }
        let q = f["q"].isNull ? 0.45 : f["q"].double
        return StartupLive(phase: w["phase"].string, customers: w["cust"].double, quality: q, weeklyChurn: 0.005 + (1 - q) * 0.02)
    }

    public enum Kind: String, Sendable { case stock, order, project, service, subscription, title, fish }

    public struct Line: Equatable, Sendable { public var name: String; public var amount: Double }

    public struct Facts: Equatable, Sendable {
        public var itemID: String
        public var name: String
        public var kind: Kind
        public var unitLabel: String
        public var price: Double
        public var unitCost: Double
        public var lines: [Line]
        public var scrapCost: Double
        public var scrap: Double
        public var labourMinutes: Int
        public var labourCost: Double
        public var leadDays: Int
        public var batch: Int
        public var minQty: Int
        public var paymentTermsWeeks: Int
        public var weeklyUnits: Double
        public var maxPerWeek: Double
        public var utilisation: Double
        public var stock: Int
        public var onOrder: Int
        public var weeksOfCover: Double?
        public var subscribers: Double
        public var periodWeeks: Int
        public var churnPerPeriod: Double
        public var leavingPerPeriod: Double
        public var mrr: Double
        public var lifetimeValue: Double
        public var isContract: Bool
        public var hours: Double
        public var bid: Double
        public var bidLabour: Double
        public var marginAtBid: Double
        public var overrunRisk: Double
        public var marginIfOverrun: Double
        public var retention: Double
        public var milestones: Int
        public var devHours: Double
        public var devCost: Double
        public var halfLifeWeeks: Double
        public var remainingProfit: Double
        public var paybackWeeks: Double?
        public var cycleWeeks: Double
        public var tonnesInWater: Double
        public var fishInWater: Double
        public var averageKilos: Double
        public var weeksToHarvest: Double?
        public var mortalityPerWeek: Double
        public var yieldRatio: Double
        public var spotPerKilo: Double
    }

    public static func kind(_ sp: Spec, trade: String) -> Kind {
        switch sp.model {
        case .sub: return .subscription
        case .svc: return .service
        case .proj: return sp.isDigital ? .title : (sp.hours > 0 ? .project : .order)
        default: return trade == "salmon" ? .fish : (sp.isDigital ? .title : (sp.madeToOrder ? .order : .stock))
        }
    }

    public static func facts(_ s: GameState, companyID: Int, itemID: String, data: GameData, trades: Set<String> = ItemTradeGroups.industrial) -> Facts? {
        guard let co = s.company(companyID), trades.contains(co.type), let bd = data.catalog[co.type], let t = specs[co.type],
              let it = SalesItems.items(co, bd).first(where: { $0.id == itemID }), let sp = spec(trade: co.type, itemName: it.name),
              let row = SalesItems.rows(s, companyID: companyID, data: data).first(where: { $0.id == itemID }) else { return nil }
        let list = SalesItems.items(co, bd)
        let qTotal = list.reduce(0.0) { $0 + $1.unitShare }
        let rec = ItemModels.record(co, itemID: itemID)
        let cost = rec.map { ItemModels.unitCost($0, weeksHeld: $0.since.map { s.week - $0 } ?? 0, supplierDiscount: ItemModels.supplierDiscount(s, $0)) }
            ?? ItemModels.fallbackCost(market: row.marketPrice, bd)
        let wage = wagePerHour(co)
        let perWeek = rate(co, bd, spec: sp, q: it.unitShare, qTotal: qTotal, row: row)
        let capacity = capacityPerWeek(co, bd, World(state: s, data: data))
        let maxWeek = maxPerWeek(sp, t, capacity: capacity)
        let k = kind(sp, trade: co.type)
        let scrapCost = cost * sp.scrap
        let net = cost - scrapCost
        let base = sp.mat + sp.dir
        var lines: [Line] = []
        if base > 0 {
            let inputTotal = net * sp.mat / base
            let shareSum = max(1e-9, sp.inputs.reduce(0.0) { $0 + $1.share })
            lines = sp.inputs.map { Line(name: $0.name, amount: inputTotal * $0.share / shareSum) }
            if sp.dir > 0 { lines.append(Line(name: "Other direct cost", amount: net * sp.dir / base)) }
        }
        let labourMinutes = sp.minutes
        let labourCost = Double(labourMinutes) / 60 * wage
        var subs = 0.0
        if sp.model == .sub {
            subs = perWeek * Double(sp.period)
            if co.type == StartupModel.tradeID, let live = startupLive(s, companyID: companyID) {
                let subShare = list.reduce(0.0) { $0 + (spec(trade: co.type, itemName: $1.name)?.model == .sub ? $1.unitShare : 0) }
                subs = subShare > 0 ? live.customers * it.unitShare / subShare : 0
            }
        }
        let perMonth = 52.0 / 12 / Double(sp.period)
        let mrr = subs * row.price * perMonth
        let contribution = row.price - cost
        let ltv = sp.churn > 0 ? contribution / sp.churn : 0
        let bid = sp.hours * row.price
        let bidLabour = sp.hours * wage
        let marginAtBid = bid - bidLabour - sp.hours * cost
        let marginOver = bid - bidLabour * (1 + sp.overrun) - sp.hours * cost
        let devCost = sp.devHours * wage
        let profitWeek = perWeek * contribution
        let remaining = sp.halfLife > 0 ? profitWeek * sp.halfLife / log(2) : 0
        let cohorts = SalmonModel.cohorts(co)
        let grow = bd.trait("grow") ?? 78
        let fishN = cohorts.reduce(0.0) { $0 + $1.fish }
        let oldest = cohorts.map { Double($0.age) }.max()
        let mort = 0.0016 * (Knobs.effect(co, bd, "r", World(state: s, data: data)))
        return Facts(itemID: itemID, name: it.name, kind: k, unitLabel: sp.unitLabel.isEmpty ? t.unit : sp.unitLabel, price: row.price, unitCost: cost, lines: lines,
                     scrapCost: scrapCost, scrap: sp.scrap, labourMinutes: labourMinutes, labourCost: labourCost, leadDays: rec?.leadDays ?? sp.lead, batch: sp.batch,
                     minQty: sp.minQty, paymentTermsWeeks: bd.paymentTermsWeeks, weeklyUnits: perWeek, maxPerWeek: maxWeek, utilisation: maxWeek > 0 ? perWeek / maxWeek : 0,
                     stock: rec?.stock ?? 0, onOrder: rec?.onOrder ?? 0, weeksOfCover: holdsFinishedStock(sp) && perWeek > 0 ? Double(rec?.stock ?? 0) / perWeek : nil,
                     subscribers: subs, periodWeeks: sp.period, churnPerPeriod: sp.churn, leavingPerPeriod: subs * sp.churn, mrr: mrr, lifetimeValue: ltv, isContract: sp.contract,
                     hours: sp.hours, bid: bid, bidLabour: bidLabour, marginAtBid: marginAtBid, overrunRisk: sp.overrun, marginIfOverrun: marginOver, retention: sp.retention,
                     milestones: sp.milestones, devHours: sp.devHours, devCost: devCost, halfLifeWeeks: sp.halfLife, remainingProfit: remaining,
                     paybackWeeks: devCost > 0 && profitWeek > 0 ? devCost / profitWeek : nil, cycleWeeks: grow, tonnesInWater: co.value("fm")["bio"].double, fishInWater: fishN,
                     averageKilos: fishN > 0 ? cohorts.reduce(0.0) { $0 + $1.fish * $1.kilosEach } / fishN : 0, weeksToHarvest: oldest.map { max(0, grow - $0) },
                     mortalityPerWeek: mort, yieldRatio: sp.yieldRatio, spotPerKilo: co.value("fm")["price"].double)
    }
}
