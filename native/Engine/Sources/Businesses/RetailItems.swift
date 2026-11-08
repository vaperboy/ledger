import Foundation
import GameCore
import Countries
import Finance

/// STK resale and parts: kiosk, boutique, grocery, hardware, webshop, pets, carrepair sell real things. The catalogue is
/// `Resources/retail_items.json`: per trade the items it really sells, with the margin each has in real life. At install a company gets
/// its items (`items27`, names as in the add-item popup) and one record per item (`itemsv2`, `ItemModels`): unit cost, extra cost, lead time,
/// capacity, supplier. The buy cost of every item is its real-life margin, scaled once per company (`w2.k`) so that the revenue-weighted cost of
/// the default list equals the trade's cost of sales: the books stay where they were, the mix and the price slider now decide the margin.
/// Stock per item is the company's real inventory (the ledger) shared out by what each item sells; nothing is invented.
/// Keys: `w2` = { k, nm } on a company (only written for an opted-in trade). Old saves and other trades are untouched.
public enum RetailItems {
    public static let trades: Set<String> = ["kiosk", "boutique", "grocery", "hardware", "webshop", "pets", "carrepair"]
    static let marker = "w2"
    /// Weekly cost of holding stock, as a share of its cost (the middle storage policy of `CompanyWeek`).
    static let holdingShare = 0.0008

    public struct Def: Equatable, Sendable {
        public var id: String
        public var name: String
        public var isService: Bool
        public var model: ItemModels.Model
        public var share: Double
        public var price: Double
        /// Buy cost as a share of the price in real life, before the company scale.
        public var costShare: Double
        /// Extra cost share of the price, never scaled (commission pass-through, fulfilment, consumables).
        public var fix: Double
        public var fixIsCost: Bool
        public var leadDays: Int
        public var shelfDays: Int
        public var returns: Double
        public var season: String
        public var seasonSensitivity: Double
        public var supplyKind: String
        public var needs: String
        public var hours: Double
        public var onSaleAtStart: Bool
        public var needsDevelopment: Bool
        public var note: String
    }

    // MARK: Catalogue

    struct Table {
        var defs: [String: [Def]] = [:]
        var labourPerHour = 0.0
        var partsMarkup = 0.0
        var kinds: [RepairKind] = []
    }

    static let table: Table = {
        var t = Table()
        guard let url = Bundle.module.url(forResource: "retail_items", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return t }
        for (trade, rows) in j["trades"].object {
            t.defs[trade] = rows.array.map { r in
                let m: ItemModels.Model
                switch r["md"].string {
                case "svc": m = .svc
                case "sub": m = .sub
                case "rent": m = .rent
                default: m = .stk
                }
                return Def(id: r["id"].string, name: r["n"].string, isService: r["svc"].bool, model: m, share: r["q"].double, price: r["r"].double,
                           costShare: r["mc"].double, fix: r["fix"].double, fixIsCost: r["ft"].string != "prep", leadDays: r["lead"].int,
                           shelfDays: r["shelf"].int, returns: r["ret"].double, season: r["seas"].string, seasonSensitivity: r["sg"].double,
                           supplyKind: r["src"].string, needs: r["needs"].string, hours: r["hrs"].double, onSaleAtStart: r["base"].bool,
                           needsDevelopment: r["dev"].bool, note: r["note"].string)
            }
        }
        let rj = j["repairs"]
        t.labourPerHour = rj["labourPerHour"].double
        t.partsMarkup = rj["partsMarkup"].double
        for (id, k) in rj["kinds"].object.sorted(by: { $0.value["hrs"].double < $1.value["hrs"].double }) {
            t.kinds.append(RepairKind(id: id, name: k["n"].string, hours: k["hrs"].double, parts: k["parts"].double, days: k["days"].int))
        }
        return t
    }()

    public static func catalogue(_ trade: String) -> [Def] { table.defs[trade] ?? [] }

    static func def(_ trade: String, name: String) -> Def? {
        let n = name.lowercased()
        return catalogue(trade).first { $0.name.lowercased() == n }
    }

    /// True when the knob option a licensed item needs is switched on ("cat:tob").
    static func needsMet(_ co: Company, _ bd: Trade, _ d: Def) -> Bool {
        guard !d.needs.isEmpty else { return true }
        let p = d.needs.split(separator: ":").map(String.init)
        guard p.count == 2, let knob = bd.knobs.first(where: { $0.id == p[0] }) else { return true }
        return Knobs.activeOptions(co, knob).contains { $0.id == p[1] }
    }

    static func startList(_ co: Company, _ bd: Trade) -> [Def] { catalogue(bd.id).filter { $0.onSaleAtStart || ($0.needs.isEmpty == false && needsMet(co, bd, $0)) } }

    /// The company scale: the cost shares are multiplied by `k` so that the revenue-weighted cost of this list equals the trade's cost of sales,
    /// and `nm` turns relative prices into price ratios (the same normalisation as `SalesItems.defaults`).
    static func scale(_ list: [Def], _ bd: Trade) -> (k: Double, nm: Double) {
        let total = list.reduce(0.0) { $0 + $1.share }
        guard total > 0 else { return (1, 1) }
        let nm = list.reduce(0.0) { $0 + $1.share / total * $1.price }
        guard nm > 0 else { return (1, 1) }
        var fixed = 0.0, vary = 0.0
        for d in list {
            let w = d.share / total * d.price / nm
            fixed += w * d.fix
            vary += w * d.costShare
        }
        guard vary > 0 else { return (1, nm) }
        let k = (bd.costOfSales - fixed) / vary
        return (k.isFinite && k > 0 ? k : 1, nm)
    }

    // MARK: Install

    static func buildRecord(_ d: Def, id: String, market: Double, k: Double, vendor: String?) -> ItemModels.Record {
        var r = ItemModels.Record(id: id, model: d.model)
        let bought = market * k * d.costShare, extra = market * d.fix
        if d.fixIsCost { r.cost = bought + extra } else { r.cost = bought; r.prep = extra }
        r.leadDays = d.leadDays
        if d.model == .stk {
            r.supplierID = vendor
            r.holdingPerWeek = r.cost * holdingShare
        }
        if d.isService && d.hours > 0 && d.leadDays == 0 { r.leadDays = Int((d.hours / 8).rounded(.up)) }
        return r
    }

    /// Give one company its real items and records. Idempotent; does nothing for a trade outside `trades` or a company that has the marker.
    /// A company whose item list the player has already changed keeps it: only the items that match a catalogue name get a real record.
    @discardableResult
    public static func install(_ s: inout GameState, companyID: Int, data: GameData, trades: Set<String> = ItemTradeGroups.retail) -> Int {
        guard let i = s.companyIndex(companyID), trades.contains(s.companies[i].type), let bd = data.catalog[s.companies[i].type],
              s.companies[i].value(marker).isNull else { return 0 }
        let co = s.companies[i]
        let list = startList(co, bd)
        guard !list.isEmpty else { return 0 }
        let (k, nm) = scale(list, bd)
        s.companies[i].set(marker, .object(["k": .number(k), "nm": .number(nm)]))
        if co.value("items27").isNull {
            let total = list.reduce(0.0) { $0 + $1.share }
            let items = list.map { d in
                SalesItems.Item(id: "w2_\(d.id)", name: d.name, isService: d.isService, unitShare: d.share / total, ratio: d.price / nm,
                                priceMultiplier: 1, discountPercent: 0, discountWeeks: 0, listedForGroup: false)
            }
            SalesItems.store(&s, i, items)
        }
        return adopt(&s, i, data: data)
    }

    /// Items without a record get one: a catalogue item a real record at its real margin, any other item the generic one of `ItemModels`.
    @discardableResult
    static func adopt(_ s: inout GameState, _ i: Int, data: GameData) -> Int {
        guard let bd = data.catalog[s.companies[i].type] else { return 0 }
        let id = s.companies[i].id
        let w = World(state: s, data: data)
        let k = s.companies[i].value(marker)["k"].double, nm = max(1e-9, s.companies[i].value(marker)["nm"].double)
        let ticket = SalesItems.marketTicket(s.companies[i], bd, w)
        let vendor = Suppliers.goodsVendor(s, company: s.companies[i], data: data)?.id
        var n = 0
        for it in SalesItems.items(s.companies[i], bd) where ItemModels.record(s.companies[i], itemID: it.id) == nil {
            if let d = def(bd.id, name: it.name) {
                // an item added from the popup is created with a ratio of 1: it takes the ratio of its real price
                if !it.id.hasPrefix("w2_"), it.ratio == 1 { SalesItems.mutate(&s, companyID: id, data: data) { list in
                    if let x = list.firstIndex(where: { $0.id == it.id }) { list[x].ratio = d.price / nm }
                } }
                let ratio = it.id.hasPrefix("w2_") || it.ratio != 1 ? it.ratio : d.price / nm
                ItemModels.put(&s, i, buildRecord(d, id: it.id, market: ticket * ratio, k: k, vendor: vendor))
                n += 1
            } else if ItemModels.migrateItem(&s, companyID: id, itemID: it.id, data: data) { n += 1 }
        }
        return n
    }

    // MARK: Add from the catalogue

    /// Catalogue items this company does not sell yet.
    public static func addable(_ s: GameState, companyID: Int, data: GameData) -> [Def] {
        guard let co = s.company(companyID), let bd = data.catalog[co.type], trades.contains(co.type) else { return [] }
        let have = SalesItems.onSaleNames(co, bd)
        return catalogue(co.type).filter { !have.contains($0.name.lowercased()) }
    }

    /// nil when added, else why not. A licensed item needs its business choice switched on first.
    public static func addRefusal(_ s: GameState, companyID: Int, defID: String, data: GameData) -> String? {
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return "That company no longer exists." }
        guard co.status == .open else { return "Only an open company adds items." }
        guard let d = catalogue(co.type).first(where: { $0.id == defID }) else { return "This trade does not sell that." }
        if SalesItems.onSaleNames(co, bd).contains(d.name.lowercased()) { return "There is already an item with that name." }
        if SalesItems.items(co, bd).count >= SalesItems.maxItems { return "That is as many items as one company can sell." }
        if !needsMet(co, bd, d) {
            let opt = d.needs.split(separator: ":").last.map(String.init) ?? ""
            let name = bd.knobs.flatMap { $0.options }.first { $0.id == opt }?.name ?? "the licence"
            return "Switch on \"\(name)\" under business choices first."
        }
        return nil
    }

    @discardableResult
    public static func add(_ s: inout GameState, companyID: Int, defID: String, data: GameData) -> String? {
        if let why = addRefusal(s, companyID: companyID, defID: defID, data: data) { return why }
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type],
              let d = catalogue(bd.id).first(where: { $0.id == defID }) else { return "That company no longer exists." }
        if s.companies[i].value(marker).isNull {
            let (k, nm) = scale(startList(s.companies[i], bd), bd)
            s.companies[i].set(marker, .object(["k": .number(k), "nm": .number(nm)]))
        }
        SalesItems.add(&s, companyID: companyID, name: d.name, isService: d.isService, data: data)
        adopt(&s, i, data: data)
        return nil
    }

    // MARK: Season

    /// How much the season moves what customers think an item is worth now: 1 = the average month.
    static func seasonFactor(_ d: Def, week: Int, data: GameData) -> Double {
        guard !d.season.isEmpty, let c = data.catalog.tables.seasons[d.season], c.count == 12 else { return 1 }
        let mean = c.reduce(0, +) / 12
        guard mean > 0 else { return 1 }
        return pow(c[GameCalendar.month(week: week)] / mean, d.seasonSensitivity)
    }

    // MARK: Weekly

    /// Weekly: a company of an opted-in trade is installed on first sight; then every item's cost follows its market price, its season sets what
    /// customers think it is worth, and stock is the real inventory shared out by what sells. Writes no money.
    public static func weekly(_ s: inout GameState, _ i: Int, data: GameData, trades: Set<String> = ItemTradeGroups.retail) {
        guard s.companies.indices.contains(i), s.companies[i].status == .open, trades.contains(s.companies[i].type), let bd = data.catalog[s.companies[i].type] else { return }
        if s.companies[i].value(marker).isNull { install(&s, companyID: s.companies[i].id, data: data, trades: trades) }
        guard !s.companies[i].value(marker).isNull else { return }
        let id = s.companies[i].id
        adopt(&s, i, data: data)
        let rows = SalesItems.rows(s, companyID: id, data: data)
        let co = s.companies[i]
        let k = co.value(marker)["k"].double
        let items = SalesItems.items(co, bd)
        var recs: [(ItemModels.Record, Def, SalesItem)] = []
        for r in ItemModels.records(co) {
            guard let it = items.first(where: { $0.id == r.id }), let d = def(bd.id, name: it.name), let row = rows.first(where: { $0.id == r.id }) else { continue }
            recs.append((r, d, row))
        }
        // stock: the real inventory shared out by what each stocked item sells (weeks of cover is the same for all)
        var flow = 0.0
        for (r, _, row) in recs where r.model == .stk { flow += row.weeklyUnits * ItemModels.unitCost(r) }
        let cover = flow > 0 ? co.inventory / flow : 0
        let week = s.week
        let tradeRef = RetailItemsOwn.words(s, co, bd)
        for (r0, d, row) in recs {
            var r = r0
            let market = row.marketPrice
            let bought = market * k * d.costShare, extra = market * d.fix
            if d.fixIsCost { r.cost = bought + extra; r.prep = 0 } else { r.cost = bought; r.prep = extra }
            if d.model == .stk { r.holdingPerWeek = r.cost * holdingShare }
            let f = seasonFactor(d, week: week, data: data)
            r.fair = d.season.isEmpty ? 0 : market * f
            var lines: [String] = d.note.isEmpty ? [] : [d.note]
            if d.model == .stk {
                let raw = row.weeklyUnits * cover
                r.stock = Int(raw.rounded())
                r.onOrder = d.leadDays > 0 && row.weeklyUnits > 0 ? Int((row.weeklyUnits * Double(d.leadDays) / 7).rounded()) : 0
                if r.stock > 0 { if r.since == nil { r.since = week } } else { r.since = nil }
                if d.shelfDays > 0 && d.shelfDays <= 30 {
                    let fresh = row.weeklyUnits * Double(d.shelfDays) / 7
                    lines.append("Shelf life \(d.shelfDays) day\(d.shelfDays == 1 ? "" : "s"), delivery in \(max(1, d.leadDays)) day\(max(1, d.leadDays) == 1 ? "" : "s").")
                    if raw > fresh * 1.05 && fresh > 0 { lines.append("About \(Int((raw - fresh).rounded())) units sit past their shelf life: they are thrown away. Order less.") }
                } else if d.leadDays > 0 {
                    lines.append("Delivery takes \(d.leadDays) days.")
                }
            }
            if d.hours > 0 { lines.append("Takes \(d.hours == d.hours.rounded() ? String(Int(d.hours)) : String(d.hours)) hour\(d.hours == 1 ? "" : "s") of work.") }
            if d.returns > 0 { lines.append("About \(Int((d.returns * 100).rounded()))% of the units come back.") }
            if !d.season.isEmpty && abs(f - 1) > 0.1 {
                lines.append(f < 1 ? "Out of season: customers think it is worth \(Int((f * 100).rounded()))% of the in-season price. Mark it down." : "In season: customers pay up to \(Int((f * 100).rounded()))% of the average price.")
            }
            if !d.supplyKind.isEmpty, let line = tradeRef(d.supplyKind) { lines.append(line) }
            if d.model == .rent { r.capacity = RetailItemsOwn.fleet(co, bd, d) }
            r.plans.removeAll { $0.kind == "w2" }
            r.plans.append(contentsOf: lines.map { ItemModels.Plan(kind: "w2", text: $0, week: week) })
            if r != r0 { ItemModels.put(&s, i, r) }
        }
        CarRepairJobs.weekly(&s, i, data: data)
    }

    // MARK: Margin by item

    /// The factor on the week's cost of sales that the real items give: what the items sold cost (their own buy and extra costs) against what the
    /// trade's cost-of-sales share of the same takings would be. Exactly 1 at the default prices and mix; below 1 when the player prices above the
    /// market, above 1 when below. 1 for a company without records. The hook in `CompanyWeek` multiplies the week's cost of sales by it.
    public static func cogsFactor(_ s: GameState, companyID: Int, data: GameData) -> Double {
        guard let co = s.company(companyID), !co.value(marker).isNull, let bd = data.catalog[co.type] else { return 1 }
        let rows = SalesItems.rows(s, companyID: companyID, data: data)
        var cost = 0.0, rev = 0.0
        for r in ItemModels.records(co) {
            guard let row = rows.first(where: { $0.id == r.id }) else { continue }
            cost += row.weeklyUnits * (r.cost + r.prep)
            rev += row.weeklyRevenue
        }
        guard rev > 0, bd.costOfSales > 0, cost > 0 else { return 1 }
        return cost / (rev * bd.costOfSales)
    }
}

/// Helpers that read your other companies and the garage's fleet for the item notes.
enum RetailItemsOwn {
    /// A closure telling whether one of the owner's own companies supplies a kind of goods to this company.
    static func words(_ s: GameState, _ co: Company, _ bd: Trade) -> (String) -> String? {
        let linked = Set(IntercompanySupply.links(s).filter { $0.buyerID == co.id }.map { $0.kindID })
        return { kind in
            guard let k = IntercompanySupply.kind(kind) else { return nil }
            return linked.contains(kind) ? "Supplied by your own company (\(k.name.lowercased()))." : "One of your own companies could supply this (\(k.name.lowercased()))."
        }
    }

    /// Units a week a rentable item can supply: kennels by the night, or the hire fleet by the day.
    static func fleet(_ co: Company, _ bd: Trade, _ d: RetailItems.Def) -> Double {
        if bd.id == "pets", let e = bd.allEquipment.first(where: { $0.id == "kennel" }) { return CapacityModel.equipmentCount(co, e) * 7 }
        return (6 * max(1, co.size)).rounded() * 7
    }
}
