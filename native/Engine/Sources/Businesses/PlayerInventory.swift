import Foundation
import GameCore
import Countries
import Finance

public struct InventoryItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var title: String
    public var family: String
    public var ref: String
    public var age: Int
    public var km: Int
    public var seen: Double
    public var cond: Double
    public var base: Double
    public var paid: Double
    public var luxury: Bool
    public var lock: String
    public var repairDue: Int
    public var repairTo: Double
    public var repairShop: Int

    public var value: Double { PlayerInventory.value(base: base, cond: cond) }
    public var seenValue: Double { PlayerInventory.value(base: base, cond: seen) }
    public var isListed: Bool { lock.hasPrefix(PlayerInventory.listedPrefix) }
    public var listingID: String { isListed ? String(lock.dropFirst(PlayerInventory.listedPrefix.count)) : "" }
    public var inRepair: Bool { lock == PlayerInventory.repairLock }
    public var isFree: Bool { lock.isEmpty }
    public var canMoveToCompany: Bool { kind == "car" || kind == "van" }
}

public struct InventoryRepairOffer: Equatable, Sendable, Identifiable {
    public var id: Int { shopID }
    public var shopID: Int
    public var shopName: String
    public var price: Double
    public var weeks: Int
    public var targetCondition: Double
    public var valueGain: Double
}

public enum InventoryResult: Equatable, Sendable {
    case ok
    case refused(String)
    public var reason: String? { if case .refused(let why) = self { return why } else { return nil } }
}

public enum PlayerInventory {
    public static let key = "inv"
    public static let holdKey = "invHold"
    public static let listedPrefix = "L:"
    public static let repairLock = "repair"
    public static let kinds = ["car", "van", "plane", "boat", "equipment", "luxury"]
    public static let repairTarget = 0.92
    static let maxItems = 60
    static let ownShopShare = 0.75
    static let partsShare = 0.35

    public static func kindTitle(_ k: String) -> String {
        switch k {
        case "car": return "Cars"
        case "van": return "Vans and trucks"
        case "plane": return "Planes"
        case "boat": return "Boats"
        case "equipment": return "Equipment"
        default: return "Luxury"
        }
    }

    public static func value(base: Double, cond: Double) -> Double { base * (0.5 + 0.5 * clamp(cond, 0, 1)) }

    static func decode(_ j: JSONValue) -> InventoryItem {
        InventoryItem(id: j["id"].string, kind: j["k"].string, title: j["t"].string, family: j["f"].string, ref: j["r"].string, age: j["a"].int, km: j["km"].int,
                      seen: j["seen"].double, cond: j["c"].double, base: j["b"].double, paid: j["p"].double, luxury: j["lux"].bool, lock: j["lk"].string,
                      repairDue: j["rp"]["due"].int, repairTo: j["rp"]["to"].double, repairShop: j["rp"]["shop"].int)
    }

    static func encode(_ i: InventoryItem) -> JSONValue {
        var o: [String: JSONValue] = ["id": .string(i.id), "k": .string(i.kind), "t": .string(i.title), "f": .string(i.family), "r": .string(i.ref),
                                      "a": .number(Double(i.age)), "km": .number(Double(i.km)), "seen": .number(i.seen), "c": .number(i.cond), "b": .number(i.base),
                                      "p": .number(i.paid), "lux": .bool(i.luxury)]
        if !i.lock.isEmpty { o["lk"] = .string(i.lock) }
        if i.inRepair { o["rp"] = .object(["due": .number(Double(i.repairDue)), "to": .number(i.repairTo), "shop": .number(Double(i.repairShop))]) }
        return .object(o)
    }

    public static func items(_ s: GameState) -> [InventoryItem] { (s.rest[key]?.array ?? []).map(decode) }
    public static func item(_ s: GameState, id: String) -> InventoryItem? { items(s).first { $0.id == id } }

    static func save(_ s: inout GameState, _ list: [InventoryItem]) { s.rest[key] = .array(list.map(encode)) }

    static func update(_ s: inout GameState, id: String, _ body: (inout InventoryItem) -> Void) {
        var list = items(s)
        guard let at = list.firstIndex(where: { $0.id == id }) else { return }
        body(&list[at])
        save(&s, list)
    }

    public static func value(_ s: GameState) -> Double { items(s).reduce(0) { $0 + $1.value } }

    static func newID(_ s: inout GameState) -> String { "i\(s.seed)-\(s.makeID())" }

    @discardableResult
    public static func add(_ s: inout GameState, _ item: InventoryItem, limited: Bool = true) -> Bool {
        var list = items(s)
        guard !limited || list.count < maxItems, !list.contains(where: { $0.id == item.id }) else { return false }
        list.append(item)
        save(&s, list)
        return true
    }

    public static func remove(_ s: inout GameState, id: String) {
        save(&s, items(s).filter { $0.id != id })
    }

    public static func lockForListing(_ s: inout GameState, id: String, listingID: String) {
        update(&s, id: id) { $0.lock = listedPrefix + listingID }
    }

    public static func unlock(_ s: inout GameState, id: String) {
        update(&s, id: id) { if $0.isListed { $0.lock = "" } }
    }

    public static func homeCurrency(_ s: GameState, _ data: GameData) -> String {
        data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode).currencyCode
    }

    public static func toServer(_ amount: Double, currency: String, _ s: GameState, _ data: GameData) -> Double {
        let r = OnlineSettlements.rate(currency, s, data)
        return r > 0 ? amount / r : amount
    }

    public static func fromServer(_ amount: Double, currency: String, _ s: GameState, _ data: GameData) -> Double {
        amount * OnlineSettlements.rate(currency, s, data)
    }

    public static func suggestedPrice(_ s: GameState, id: String) -> Double {
        guard let i = item(s, id: id) else { return 0 }
        return Currency.nicePrice(i.seenValue * 1.05)
    }

    public static func listingPayload(_ s: GameState, id: String, data: GameData) -> JSONValue? {
        guard let i = item(s, id: id) else { return nil }
        let cur = homeCurrency(s, data)
        return .object(["id": .string(i.id), "kind": .string(i.kind), "title": .string(i.title), "family": .string(i.family), "ref": .string(i.ref), "lux": .bool(i.luxury),
                        "age": .number(Double(i.age)), "km": .number(Double(i.km)), "seen": .number(i.seen), "cond": .number(i.cond),
                        "base": .number(jsRound(toServer(i.base, currency: cur, s, data) * 100) / 100)])
    }

    public static func canList(_ s: GameState, id: String) -> String? {
        guard let i = item(s, id: id) else { return "That item is gone." }
        if i.inRepair { return "It is in repair until the work is done." }
        if i.isListed { return "It is already for sale." }
        return nil
    }

    public static func fromWire(_ s: GameState, wire j: JSONValue, price: Double, currency: String, data: GameData) -> InventoryItem {
        let paid = fromServer(price, currency: currency, s, data)
        let cond = clamp(j["cond"].isNull ? j["seen"].double : j["cond"].double, 0.05, 1)
        return InventoryItem(id: j["id"].string, kind: kinds.contains(j["kind"].string) ? j["kind"].string : "equipment", title: j["title"].string, family: j["family"].string,
                             ref: j["ref"].string, age: max(0, j["age"].int), km: max(0, j["km"].int), seen: clamp(j["seen"].isNull ? cond : j["seen"].double, 0.05, 1), cond: cond,
                             base: max(1, fromServer(j["base"].double, currency: currency, s, data)), paid: paid, luxury: j["lux"].bool, lock: "", repairDue: 0, repairTo: 0, repairShop: 0)
    }

    public static func holds(_ s: GameState) -> [String: Double] {
        (s.rest[holdKey]?.object ?? [:]).mapValues { $0.double }
    }

    public static func hold(_ s: inout GameState, dealID: String, amount: Double, label: String) -> InventoryResult {
        guard amount.isFinite, amount > 0 else { return .refused("That is not a price.") }
        guard holds(s)[dealID] == nil else { return .ok }
        guard s.cash >= amount else { return .refused("You do not have the cash for this.") }
        Payments.playerPays(&s, amount, label: label)
        var h = s.rest[holdKey] ?? .object([:])
        h[dealID] = .number(amount)
        s.rest[holdKey] = h
        return .ok
    }

    @discardableResult
    public static func release(_ s: inout GameState, dealID: String) -> Double {
        var h = s.rest[holdKey] ?? .object([:])
        let amount = h[dealID].double
        guard amount > 0 else { return 0 }
        h.removeKey(dealID)
        s.rest[holdKey] = h
        return amount
    }

    public static func heldTotal(_ s: GameState) -> Double { holds(s).values.reduce(0, +) }

    @discardableResult
    public static func takeDelivery(_ s: inout GameState, dealID: String, wire: JSONValue, price: Double, currency: String, data: GameData) -> InventoryItem? {
        var item = fromWire(s, wire: wire, price: price, currency: currency, data: data)
        let held = release(&s, dealID: dealID)
        let delta = item.paid - held
        if delta > 0 { Payments.playerPays(&s, delta, label: "Bought: \(item.title)") }
        else if delta < 0 { Payments.playerReceives(&s, -delta, label: "Price difference: \(item.title)") }
        if item.id.isEmpty || items(s).contains(where: { $0.id == item.id }) { item.id = newID(&s) }
        guard add(&s, item, limited: false) else { return nil }
        return item
    }

    public static func revealNote(_ i: InventoryItem) -> (text: String, tone: String)? {
        if i.cond < i.seen - 0.12 {
            return ("On a closer look \(i.title) is in worse shape than it was shown: about \(Int((i.cond * 100).rounded())) percent condition against the \(Int((i.seen * 100).rounded())) it looked. A repair would lift it again.", "bad")
        }
        if i.cond > i.seen + 0.06 { return ("\(i.title) turns out to be in better shape than it looked.", "good") }
        return nil
    }

    // MARK: repair

    static func kindFactor(_ k: String) -> Double {
        switch k {
        case "car": return 0.8
        case "van": return 0.85
        case "equipment": return 0.7
        case "boat": return 1.0
        case "plane": return 1.1
        default: return 1.0
        }
    }

    public static func ownShops(_ s: GameState) -> [Company] {
        s.companies.filter { $0.type == "carrepair" && $0.status == .open }.sorted { $0.id < $1.id }
    }

    public static func repairOffers(_ s: GameState, id: String) -> [InventoryRepairOffer] {
        guard let i = item(s, id: id), i.isFree, i.cond < repairTarget - 0.02 else { return [] }
        let gap = repairTarget - i.cond
        let gain = i.base * 0.5 * gap
        let market = gain * kindFactor(i.kind)
        var out: [InventoryRepairOffer] = [InventoryRepairOffer(shopID: 0, shopName: "An independent garage", price: jsRound(market), weeks: 2 + Int(gap * 6), targetCondition: repairTarget, valueGain: gain)]
        for shop in ownShops(s) {
            out.append(InventoryRepairOffer(shopID: shop.id, shopName: shop.name, price: jsRound(market * ownShopShare), weeks: 1 + Int(gap * 4), targetCondition: repairTarget, valueGain: gain))
        }
        return out
    }

    public static func startRepair(_ s: inout GameState, id: String, shopID: Int) -> InventoryResult {
        guard let i = item(s, id: id) else { return .refused("That item is gone.") }
        guard i.isFree else { return .refused(i.isListed ? "Take it off the market first." : "It is already in repair.") }
        guard let offer = repairOffers(s, id: id).first(where: { $0.shopID == shopID }) else { return .refused("It needs no repair.") }
        guard s.cash >= offer.price else { return .refused("You do not have the cash for this.") }
        if shopID != 0 {
            guard let shop = s.company(shopID), shop.type == "carrepair", shop.status == .open else { return .refused("That repair shop is not open.") }
            Payments.playerPays(&s, offer.price, label: "Repair of \(i.title) at \(shop.name)")
            Payments.companyReceives(&s, companyID: shopID, amount: offer.price, category: "rev", label: "Repair of \(i.title)")
            Payments.companyPays(&s, companyID: shopID, amount: offer.price * partsShare, category: "cogs", label: nil)
        } else {
            Payments.playerPays(&s, offer.price, label: "Repair of \(i.title)")
        }
        let due = s.week + offer.weeks
        update(&s, id: id) { it in
            it.lock = repairLock
            it.repairDue = due
            it.repairTo = offer.targetCondition
            it.repairShop = shopID
        }
        return .ok
    }

    public static func weekly(_ s: inout GameState) {
        let list = items(s)
        guard list.contains(where: { $0.inRepair && $0.repairDue <= s.week }) else { return }
        var out = list
        for k in out.indices where out[k].inRepair && out[k].repairDue <= s.week {
            out[k].cond = max(out[k].cond, out[k].repairTo)
            out[k].seen = max(out[k].seen, out[k].cond - 0.02)
            out[k].lock = ""
            out[k].repairDue = 0; out[k].repairTo = 0; out[k].repairShop = 0
            s.addMessage(kind: "info", from: "Repairs", title: "\(out[k].title) is repaired", body: "It is back in your inventory at about \(Int((out[k].cond * 100).rounded())) percent condition, worth about \(Int(out[k].value.rounded())) more or less on the market.", companyID: 0, tone: "good", app: "marketplace")
        }
        save(&s, out)
    }

    // MARK: sources

    static func vehicleKind(_ model: String, tables: TradeTables) -> String? {
        switch tables.raw["VEH_CLASS"][model].string {
        case "car": return "car"
        case "van", "boxvan", "truck", "bus": return "van"
        case "plane": return "plane"
        case "ship": return "boat"
        default: return nil
        }
    }

    public static func canMoveVehicle(_ s: GameState, companyID: Int, vehicleID: Int, data: GameData) -> String? {
        guard let co = s.company(companyID), let v = co.value("veh").array.first(where: { $0["id"].int == vehicleID }) else { return "That vehicle is gone." }
        if vehicleKind(v["model"].string, tables: data.catalog.tables) == nil { return "This kind of machine cannot be sold privately." }
        if v["mode"].string == "lease" { return "A leased vehicle goes back to the lessor." }
        if v["loan"].int != 0 { return "Pay off the loan on it first." }
        if v["down"].int > 0 { return "It is in repair now." }
        if !v["perk"].isNull { return "A company car given as a perk cannot be sold this way." }
        return nil
    }

    public static func takeVehicle(_ s: inout GameState, companyID: Int, vehicleID: Int, data: GameData) -> InventoryResult {
        if let why = canMoveVehicle(s, companyID: companyID, vehicleID: vehicleID, data: data) { return .refused(why) }
        guard let co = s.company(companyID), let v = co.value("veh").array.first(where: { $0["id"].int == vehicleID }),
              let kind = vehicleKind(v["model"].string, tables: data.catalog.tables) else { return .refused("That vehicle is gone.") }
        guard items(s).count < maxItems else { return .refused("Your inventory is full.") }
        let seen = EquipmentMarket.seen(v)
        let price = jsRound(v["bv"].double * 0.78)
        guard s.cash >= price else { return .refused("You do not have the cash to take it over.") }
        let year = GameCalendar.year(week: s.week)
        let it = InventoryItem(id: newID(&s), kind: kind, title: v["name"].string, family: v["model"].string, ref: v["model"].string, age: max(0, year - v["yr"].int), km: v["km"].int,
                               seen: seen, cond: seen, base: max(1, v["bv"].double / (0.5 + 0.5 * seen)), paid: price, luxury: false, lock: "", repairDue: 0, repairTo: 0, repairShop: 0)
        let got = EquipmentMarket.sellVehicle(&s, companyID: companyID, vehicleID: vehicleID)
        if got > 0 { Payments.playerPays(&s, got, label: "Took over \(it.title) from the company") }
        var fixed = it
        fixed.paid = got
        add(&s, fixed)
        return .ok
    }

    public static func canMoveUnit(_ s: GameState, companyID: Int, equipmentID: String, unitID: Int) -> String? {
        guard let co = s.company(companyID), !co.value("eq")[equipmentID].isNull else { return "That machine is gone." }
        if equipmentID == "fit" || !co.value("eq")[equipmentID]["sub"].isNull || !co.value("eq")[equipmentID]["soft"].isNull { return "Software and plans cannot be sold privately." }
        guard let u = co.value("units")[equipmentID].array.first(where: { $0["u"].int == unitID }) else { return "That machine is gone." }
        if u["down"].int > 0 { return "It is in repair now." }
        return nil
    }

    public static func takeUnit(_ s: inout GameState, companyID: Int, equipmentID: String, unitID: Int, name: String, data: GameData) -> InventoryResult {
        guard let i0 = s.companyIndex(companyID) else { return .refused("That company is gone.") }
        EquipmentUnits.ensureUnits(&s, companyIndex: i0, equipmentID: equipmentID)
        if let why = canMoveUnit(s, companyID: companyID, equipmentID: equipmentID, unitID: unitID) { return .refused(why) }
        guard items(s).count < maxItems else { return .refused("Your inventory is full.") }
        guard let co = s.company(companyID), let u = co.value("units")[equipmentID].array.first(where: { $0["u"].int == unitID }) else { return .refused("That machine is gone.") }
        let rec = co.value("eq")[equipmentID]
        let n = max(1, rec["n"].double)
        let bvU = rec["bv"].double / n
        let seen = EquipmentMarket.seen(u)
        let year = GameCalendar.year(week: s.week)
        let quote = jsRound(bvU * 0.7 * (0.6 + 0.4 * seen))
        guard s.cash >= quote else { return .refused("You do not have the cash to take it over.") }
        let title = u["nm"].string.isEmpty ? name : u["nm"].string
        let got = EquipmentMarket.sellUnit(&s, companyID: companyID, equipmentID: equipmentID, unitID: unitID)
        if got > 0 { Payments.playerPays(&s, got, label: "Took over \(title) from the company") }
        let it = InventoryItem(id: newID(&s), kind: "equipment", title: title, family: equipmentID, ref: equipmentID, age: u["yr"].int > 0 ? max(0, year - u["yr"].int) : 0, km: 0,
                               seen: seen, cond: seen, base: max(1, bvU / (0.5 + 0.5 * seen)), paid: got, luxury: false, lock: "", repairDue: 0, repairTo: 0, repairShop: 0)
        add(&s, it)
        return .ok
    }

    static func luxuryKind(_ category: String) -> String? {
        switch category {
        case "cars": return "car"
        case "yachts": return "boat"
        case "jets": return "plane"
        case "watches", "art": return "luxury"
        default: return nil
        }
    }

    public static func canMoveLuxury(_ s: GameState, pieceID: Int) -> String? {
        guard let x = (s.rest["lux"]?.array ?? []).first(where: { $0["id"].int == pieceID }), let it = Luxury.item(x["k"].string) else { return "That piece is gone." }
        if luxuryKind(it.category) == nil { return "Homes and estates are not sold through the Marketplace." }
        if x["co"].int != 0 { return "A company owns it. Sell it from the company." }
        if x["use"].string == "museum" && x["until"].int > s.week { return "It is on loan to a museum." }
        if items(s).count >= maxItems { return "Your inventory is full." }
        return nil
    }

    public static func takeLuxury(_ s: inout GameState, pieceID: Int) -> InventoryResult {
        if let why = canMoveLuxury(s, pieceID: pieceID) { return .refused(why) }
        var list = s.rest["lux"]?.array ?? []
        guard let at = list.firstIndex(where: { $0["id"].int == pieceID }), let it = Luxury.item(list[at]["k"].string), let kind = luxuryKind(it.category) else { return .refused("That piece is gone.") }
        let x = list.remove(at: at)
        s.rest["lux"] = .array(list)
        let age = max(0, (s.week - x["w"].int) / 52)
        add(&s, InventoryItem(id: newID(&s), kind: kind, title: it.name, family: it.id, ref: it.id, age: age, km: 0, seen: 1, cond: 1, base: max(1, x["val"].double), paid: x["price"].double,
                              luxury: true, lock: "", repairDue: 0, repairTo: 0, repairShop: 0))
        return .ok
    }

    public static func canKeepLuxury(_ s: GameState, id: String) -> Bool {
        guard let i = item(s, id: id) else { return false }
        return i.luxury && i.isFree && Luxury.item(i.ref) != nil
    }

    public static func keepLuxury(_ s: inout GameState, id: String) -> InventoryResult {
        guard canKeepLuxury(s, id: id), let i = item(s, id: id), let it = Luxury.item(i.ref) else { return .refused("This cannot go into your collection.") }
        var list = s.rest["lux"]?.array ?? []
        list.append(.object(["id": .number(Double(s.makeID())), "k": .string(it.id), "price": .number(i.paid), "val": .number(max(1, i.value)), "w": .number(Double(s.week))]))
        s.rest["lux"] = .array(list)
        remove(&s, id: id)
        return .ok
    }

    // MARK: dealership

    public static func canStock(_ s: GameState, id: String, companyID: Int) -> String? {
        guard let i = item(s, id: id) else { return "That item is gone." }
        guard let co = s.company(companyID), co.type == UsedCarDealer.tradeID, co.status == .open else { return "Only an open used car dealer can stock it." }
        guard i.canMoveToCompany else { return "A used car dealer sells cars and vans only." }
        guard i.isFree else { return i.isListed ? "Take it off the market first." : "It is in repair." }
        let lot = UsedCarDealer.lot(co)
        if lot.free <= 0 { return lot.spaces == 0 ? "These premises have no lot spaces for cars." : "The lot is full." }
        if co.cash < i.paid { return "The company does not have the cash to buy it from you." }
        return nil
    }

    public static func stockInDealer(_ s: inout GameState, id: String, companyID: Int) -> InventoryResult {
        if let why = canStock(s, id: id, companyID: companyID) { return .refused(why) }
        guard let i = item(s, id: id), let ci = s.companyIndex(companyID) else { return .refused("That item is gone.") }
        let stockID = s.makeID()
        AccountingLedger.note(category: "cogs", label: "Used car bought: \(i.title)")
        Ledger.moveRaw(&s, .company(companyID), -i.paid)
        s.companies[ci].inventory += i.paid
        Payments.playerReceives(&s, i.paid, label: "Sold \(i.title) to \(s.companies[ci].name)")
        var stock = s.companies[ci].value("stk").array
        stock.append(.object(["id": .number(Double(stockID)), "name": .string(i.title), "fam": .string(i.family), "cost": .number(i.paid), "rep": 0,
                              "fair": .number(i.value), "wear": .number(1 - i.cond), "vis": .number(1 - i.seen), "wk": .number(Double(s.week)), "done": .bool(false), "km": .number(Double(i.km))]))
        s.companies[ci].set("stk", .array(stock))
        UsedCarDealer.recordDeal(&s.companies[ci], who: "me", fair: i.value, paid: i.paid)
        remove(&s, id: id)
        return .ok
    }
}
