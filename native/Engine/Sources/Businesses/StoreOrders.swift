import Foundation
import GameCore
import Countries
import Finance

/// The TechPro Store checkout: a basket of equipment, software, subscriptions and vehicles is paid for at checkout and DELIVERED on a
/// real date. The goods reach the company on the delivery day (`runDay`, called by the daily step); digital goods (software licences,
/// subscriptions) arrive at once. It reuses the equipment market for what is bought (`EquipmentMarket.buyNew` and friends, with
/// `prepaid: true` because the money was taken at checkout) and `Payments` for the money, so nothing is priced or booked twice.
///
/// Delivery days come from the goods: a kind-based lead time (a till is quicker than a machine), longer for dearer items, a vehicle takes
/// longest, with one day either way from a hashed roll. Express shipping halves the wait (rounded up) for a higher fee; a company of
/// yours that runs a delivery business (a logistics trade, open) delivers your orders itself, free and a day quicker.
/// An order lives in its store company's record under `ord` (set only when the first order is placed).
public enum StoreOrders {
    static let key = "ord"
    static let keepOrders = 40

    // MARK: Lines and quotes

    /// One thing in the basket.
    public struct Line: Equatable, Sendable, Identifiable {
        public enum Kind: String, Sendable { case new, vehicle, used, plan }
        public var kind: Kind
        public var equipmentID: String
        public var quantity: Int
        /// New equipment and subscriptions: `EquipmentMarket.Offer.index`.
        public var offerIndex: Int
        /// New vehicles: `EquipmentMarket.VehicleOffer.id`.
        public var vehicleOfferID: String
        /// Subscriptions: the plan (0 to 2).
        public var plan: Int
        public var payment: EquipmentMarket.Payment
        /// Second-hand items: the listing as shown.
        public var used: EquipmentMarket.UsedOffer?

        public init(kind: Kind, equipmentID: String, quantity: Int = 1, offerIndex: Int = 0, vehicleOfferID: String = "", plan: Int = 0,
                    payment: EquipmentMarket.Payment = .cash, used: EquipmentMarket.UsedOffer? = nil) {
            self.kind = kind; self.equipmentID = equipmentID; self.quantity = quantity; self.offerIndex = offerIndex
            self.vehicleOfferID = vehicleOfferID; self.plan = plan; self.payment = payment; self.used = used
        }

        public var id: String {
            kind.rawValue + ":" + equipmentID + ":" + String(offerIndex) + ":" + vehicleOfferID + ":" + (used?.id ?? "-") + ":" + String(plan) + ":" + payment.rawValue
        }
    }

    public enum Delivery: String, Sendable, CaseIterable { case own, standard, express }

    public struct LineQuote: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var subtitle: String
        public var quantity: Int
        /// The value of the goods.
        public var goods: Double
        /// What leaves the account at checkout for this line (the whole price, a down payment, a first month, nothing for a lease).
        public var chargeNow: Double
        public var payment: EquipmentMarket.Payment
        public var digital: Bool
        public var isVehicle: Bool
        public var days: Int
        /// A lease or a subscription plan: what it costs each month after checkout (0 for anything else).
        public var monthly: Double
    }

    public struct Quote: Equatable, Sendable {
        public var lines: [LineQuote]
        public var delivery: Delivery
        public var goods: Double
        public var shipping: Double
        /// Goods charges plus shipping: what leaves the account at checkout.
        public var chargeNow: Double
        /// Days until the last item arrives (0 = all digital).
        public var days: Int
        public var deliveryText: String
        /// "Own delivery (Fleet Co)", "Standard shipping", "Express shipping" or "Digital delivery".
        public var carrier: String
        public var needsShipping: Bool
    }

    public struct ShippingOptions: Equatable, Sendable {
        public var ownCompanyID: Int?
        public var ownCompanyName: String?
    }

    /// A company of yours that runs a delivery business and is open: it delivers the store's orders itself.
    public static func ownCarrier(_ s: GameState, data: GameData) -> (id: Int, name: String)? {
        for co in s.companies where co.status == .open {
            if data.catalog[co.type]?.family == "logi" { return (co.id, co.name) }
        }
        return nil
    }

    public static func shippingOptions(_ s: GameState, data: GameData) -> ShippingOptions {
        let own = ownCarrier(s, data: data)
        return ShippingOptions(ownCompanyID: own?.id, ownCompanyName: own?.name)
    }

    static func today(_ s: GameState) -> Int { s.week * 7 + s.day }

    static func dateText(_ absoluteDay: Int) -> String { GameCalendar.dateString(week: absoluteDay / 7, dayOffset: absoluteDay % 7) }

    // MARK: Pricing one line

    private struct Priced {
        var name: String
        var subtitle: String
        var goods: Double
        var chargeNow: Double
        var payment: EquipmentMarket.Payment
        var digital: Bool
        var isVehicle: Bool
        var baseDays: Int
        var monthly: Double = 0
    }

    /// Lead time in days for one physical item, before shipping speed.
    static func leadDays(kind: String, vehicleKind: String?, used: Bool, goods: Double, currency: Currency) -> Int {
        if let vk = vehicleKind {
            if used { return 3 }
            switch vk {
            case "bike": return 4
            case "van", "car": return 9
            case "bus", "truck", "plant": return 16
            default: return 30
            }
        }
        if used { return 3 }
        let base: Int
        switch kind {
        case "it", "pos": base = 2
        case "tool": base = 3
        case "furn": base = 5
        default: base = 6
        }
        let ref = max(1, currency.scaledPrice(5000))
        let ratio = goods / ref
        let extra = ratio > 1 ? min(7, Int(log2(ratio))) : 0
        return base + extra
    }

    private static func price(_ s: GameState, companyID: Int, line: Line, data: GameData) -> Priced? {
        guard let co = s.company(companyID), let c = EquipmentMarket.ctx(s, co, data: data),
              let e = c.bd.allEquipment.first(where: { $0.id == line.equipmentID }) else { return nil }
        let k = EquipmentMarket.kind(e, tradeID: c.bd.id, tables: c.tables)
        let cur = c.w.currency(co)
        switch line.kind {
        case .new:
            guard e.vehicleModels == nil, let offer = EquipmentMarket.offers(s, companyID: companyID, equipmentID: e.id, data: data).first(where: { $0.index == line.offerIndex }) else { return nil }
            let one = k == "soft" || k == "svc"
            if one && EquipmentMarket.softwareMode(e, tradeID: c.bd.id, company: co, c.w) == .subscription { return nil }
            let q = one ? 1 : max(1, min(50, line.quantity))
            let unit = EquipmentMarket.price(e, company: co, c.w, factor: offer.priceFactor, vendor: offer.vendorID, dealWeek: s.week)
            let total = unit * Double(q)
            var pay = line.payment
            if one { pay = .cash }
            if pay == .lease && !EquipmentMarket.canLease(e, tradeID: c.bd.id, unitPrice: unit, company: co, c.w, tables: c.tables) { return nil }
            if pay == .finance && !EquipmentMarket.canFinance(e, tradeID: c.bd.id, total: total, company: co, c.w, tables: c.tables) { return nil }
            let now: Double = pay == .finance ? total * 0.2 : pay == .lease ? 0 : total
            return Priced(name: offer.name + (q > 1 ? " x\(q)" : ""), subtitle: e.name, goods: total, chargeNow: now, payment: pay, digital: one, isVehicle: false,
                          baseDays: one ? 0 : leadDays(kind: k, vehicleKind: nil, used: false, goods: total, currency: cur),
                          monthly: pay == .lease ? EquipmentMarket.leaseMonthly(price: total) : 0)
        case .plan:
            guard let offer = EquipmentMarket.offers(s, companyID: companyID, equipmentID: e.id, data: data).first(where: { $0.index == line.offerIndex }),
                  line.plan >= 0, line.plan < 3 else { return nil }
            let plans = EquipmentMarket.plans(e, company: co, c.w, factor: offer.priceFactor)
            guard line.plan < plans.count else { return nil }
            let p = plans[line.plan]
            return Priced(name: offer.name + " " + p.name, subtitle: e.name + " \u{00B7} monthly plan", goods: p.monthlyFee, chargeNow: p.monthlyFee, payment: .cash, digital: true, isVehicle: false, baseDays: 0, monthly: p.monthlyFee)
        case .vehicle:
            guard e.vehicleModels != nil, let offer = EquipmentMarket.vehicleOffers(s, companyID: companyID, equipmentID: e.id, data: data).first(where: { $0.id == line.vehicleOfferID }),
                  let vm = c.tables.vehicles[offer.modelID] else { return nil }
            let base = EquipmentMarket.vehiclePrice(vm, factor: offer.priceFactor, c.w, dealWeek: s.week)
            let now: Double = line.payment == .finance ? base * 0.2 : line.payment == .lease ? 0 : base
            return Priced(name: offer.name + ", new", subtitle: offer.modelName, goods: base, chargeNow: now, payment: line.payment, digital: false, isVehicle: true,
                          baseDays: leadDays(kind: "veh", vehicleKind: vm.kind, used: false, goods: base, currency: cur),
                          monthly: line.payment == .lease ? EquipmentMarket.vehicleLeaseMonthly(price: base) : 0)
        case .used:
            guard let u = line.used,
                  EquipmentMarket.canBuyUsed(e, tradeID: c.bd.id, tables: c.tables),
                  usedStillListed(s, companyID: companyID, equipmentID: e.id, listing: u, data: data) else { return nil }
            var pay = line.payment
            if pay == .lease { return nil }
            if pay == .finance && !EquipmentMarket.canFinance(e, tradeID: c.bd.id, total: u.price, company: co, c.w, tables: c.tables) { pay = .cash }
            let now: Double = pay == .finance ? u.price * 0.2 : u.price
            let vk: String? = e.vehicleModels != nil ? "car" : nil
            return Priced(name: u.name + " \u{00B7} " + String(u.year) + ", used", subtitle: e.name, goods: u.price, chargeNow: now, payment: pay, digital: false, isVehicle: e.vehicleModels != nil,
                          baseDays: leadDays(kind: k, vehicleKind: vk, used: true, goods: u.price, currency: cur))
        }
    }

    private static func usedStillListed(_ s: GameState, companyID: Int, equipmentID: String, listing: EquipmentMarket.UsedOffer, data: GameData) -> Bool {
        let vehicle = s.company(companyID).flatMap { data.catalog[$0.type] }?.allEquipment.first { $0.id == equipmentID }?.vehicleModels != nil
        let list: [EquipmentMarket.UsedOffer] = vehicle
            ? EquipmentMarket.usedVehicles(s, companyID: companyID, equipmentID: equipmentID, data: data)
            : EquipmentMarket.usedEquipment(s, companyID: companyID, equipmentID: equipmentID, data: data)
        return list.contains { $0.id == listing.id }
    }

    // MARK: Quote

    /// Shipping speed applied to a line's lead time.
    static func days(base: Int, digital: Bool, delivery: Delivery, roll: Double) -> Int {
        if digital { return 0 }
        let varied = max(1, base + Int((roll * 3).rounded(.down)) - 1)
        switch delivery {
        case .standard: return varied
        case .express: return max(1, (varied + 1) / 2)
        case .own: return max(1, varied - 1)
        }
    }

    /// What the basket costs now, what shipping costs and when it arrives. Nil when a line cannot be bought (not on offer any more, not allowed)
    /// or "own delivery" is chosen without a delivery company of your own.
    public static func quote(_ s: GameState, companyID: Int, lines: [Line], delivery: Delivery, data: GameData) -> Quote? {
        guard let co = s.company(companyID), co.status.isLive, !lines.isEmpty else { return nil }
        if delivery == .own && ownCarrier(s, data: data) == nil { return nil }
        let w = World(state: s, data: data)
        let cur = w.currency(co)
        let day0 = today(s)
        var out: [LineQuote] = []
        var physicalGoods = 0.0
        var shipPercent = 0.0
        for (n, line) in lines.enumerated() {
            guard let p = price(s, companyID: companyID, line: line, data: data) else { return nil }
            var r = HashedRandom("\(s.seed):ship:\(companyID):\(day0):\(line.equipmentID):\(n)")
            let d = days(base: p.baseDays, digital: p.digital, delivery: delivery, roll: r.next())
            out.append(LineQuote(id: line.id, name: p.name, subtitle: p.subtitle, quantity: max(1, line.quantity), goods: p.goods, chargeNow: p.chargeNow,
                                 payment: p.payment, digital: p.digital, isVehicle: p.isVehicle, days: d, monthly: p.monthly))
            if !p.digital {
                physicalGoods += p.goods
                shipPercent += p.goods * (p.isVehicle ? (delivery == .express ? 0.012 : 0.005) : (delivery == .express ? 0.04 : 0.015))
            }
        }
        var shipping = 0.0
        if physicalGoods > 0 {
            let minimumFee = delivery == .express ? cur.scaledPrice(70) : cur.scaledPrice(25)
            shipping = cur.tidy(max(minimumFee, shipPercent))
            // Your own delivery company charges a fee (revenue for it) a little under the open market, and none to itself.
            if delivery == .own { shipping = ownCarrier(s, data: data)?.id == companyID ? 0 : cur.tidy(shipping * 0.7) }
        }
        let goods = out.reduce(0) { $0 + $1.goods }
        let now = out.reduce(0) { $0 + $1.chargeNow } + shipping
        let last = out.map { $0.days }.max() ?? 0
        let needs = physicalGoods > 0
        let carrier: String
        if !needs { carrier = "Digital delivery" }
        else if delivery == .own, let own = ownCarrier(s, data: data) { carrier = "Own delivery (\(own.name))" }
        else { carrier = delivery == .express ? "Express shipping" : "Standard shipping" }
        return Quote(lines: out, delivery: delivery, goods: goods, shipping: shipping, chargeNow: now, days: last, deliveryText: dateText(day0 + last),
                     carrier: carrier, needsShipping: needs)
    }

    // MARK: Placing the order

    public enum PlaceOutcome: Equatable, Sendable {
        case placed(number: String, deliveryText: String, total: Double)
        case notEnoughCash(missing: Double)
        case notPossible
    }

    /// Pay for the basket from `companyID`'s account, file the receipt with `receiptCompanyID` and set the delivery. Items due today
    /// (digital goods) arrive straight away.
    @discardableResult
    public static func place(_ s: inout GameState, companyID: Int, lines: [Line], delivery: Delivery, receiptCompanyID: Int, data: GameData) -> PlaceOutcome {
        guard let q = quote(s, companyID: companyID, lines: lines, delivery: delivery, data: data),
              let i = s.companyIndex(companyID), s.companyIndex(receiptCompanyID) != nil else { return .notPossible }
        let cash = s.companies[i].cash
        if cash < q.chargeNow { return .notEnoughCash(missing: q.chargeNow - cash) }
        let storeName = s.companies[i].name
        let id = s.makeID()
        let year = GameCalendar.year(week: s.week)
        let number = Receipts.reference(prefix: "TS", year: year, id: id)
        let day0 = today(s)
        var rows: [JSONValue] = []
        for (n, line) in lines.enumerated() {
            let lq = q.lines[n]
            rows.append(encode(line, quote: lq, eta: day0 + lq.days))
        }
        let goodsNow = q.lines.reduce(0) { $0 + $1.chargeNow }
        if goodsNow > 0 { Payments.companyPays(&s, companyID: companyID, amount: goodsNow, category: nil, label: "Order \(number)") }
        if q.shipping > 0 { Payments.companyPays(&s, companyID: companyID, amount: q.shipping, category: "oth", label: "Shipping: order \(number)") }
        if q.shipping > 0, delivery == .own, let own = ownCarrier(s, data: data) {
            Payments.companyReceives(&s, companyID: own.id, amount: q.shipping, category: "rev", label: "Delivery fee: order \(number)")
        }
        let order: JSONValue = .object(["no": .string(number), "w": .number(Double(s.week)), "d": .number(Double(s.day)), "del": .string(delivery.rawValue), "car": .string(q.carrier),
                                        "goods": .number(q.goods), "ship": .number(q.shipping), "paid": .number(q.chargeNow), "rc": .number(Double(receiptCompanyID)),
                                        "eta": .number(Double(day0 + q.days)), "lines": .array(rows), "st": "transit", "dl": .bool(true)])
        var list: [JSONValue] = s.companies[i].value(key).array
        list.insert(order, at: 0)
        if list.count > keepOrders { list.removeLast(list.count - keepOrders) }
        s.companies[i].set(key, .array(list))
        let names = q.lines.map { $0.name }.joined(separator: ", ")
        Receipts.add(&s, receiptCompanyID: receiptCompanyID, number: number, kind: "order", title: "TechPro Store order " + number,
                     detail: storeName + ": " + names + " \u{00B7} " + q.carrier, amount: q.chargeNow, payer: storeName)
        deliverDue(&s, companyID: companyID, data: data)
        return .placed(number: number, deliveryText: q.deliveryText, total: q.chargeNow)
    }

    // MARK: Delivery

    /// Called every day: every order whose date has come hands over its goods.
    public static func runDay(_ s: inout GameState, data: GameData) {
        for i in s.companies.indices where s.companies[i].status.isLive && !s.companies[i].value(key).isNull {
            deliverDue(&s, companyID: s.companies[i].id, data: data)
        }
    }

    static func deliverDue(_ s: inout GameState, companyID: Int, data: GameData) {
        guard let i = s.companyIndex(companyID) else { return }
        let day0 = today(s)
        var orders: [JSONValue] = s.companies[i].value(key).array
        var anyChange = false
        for o in orders.indices where orders[o]["st"].string == "transit" {
            var changed = false
            var order = orders[o]
            var lines: [JSONValue] = order["lines"].array
            var arrived: [String] = []
            for l in lines.indices where !lines[l]["done"].bool && lines[l]["eta"].int <= day0 {
                var line = lines[l]
                line["done"] = .bool(true)
                if grant(&s, companyID: companyID, line: line, dealWeek: order["dl"].bool ? order["w"].int : nil, data: data) { arrived.append(line["nm"].string) }
                else {
                    // The goods cannot be delivered (the company changed too much): the charge for them comes back.
                    let back = line["c"].double
                    if back > 0 { Payments.companyReceives(&s, companyID: companyID, amount: back, category: nil, label: "Order \(order["no"].string): refund") }
                    line["refund"] = .bool(true)
                }
                lines[l] = line
                changed = true
            }
            if changed {
                order["lines"] = .array(lines)
                if lines.allSatisfy({ $0["done"].bool }) { order["st"] = .string("done"); order["dd"] = .number(Double(day0)) }
                orders[o] = order
                anyChange = true
                if !arrived.isEmpty, let ci = s.companyIndex(companyID) {
                    s.note("Order \(order["no"].string) has arrived at \(s.companies[ci].name): " + arrived.joined(separator: ", ") + ".", tone: "good", companyID: companyID)
                }
            }
        }
        if anyChange, let ci = s.companyIndex(companyID) { s.companies[ci].set(key, .array(orders)) }
    }

    /// Put one delivered line into the company (the money was taken at checkout).
    private static func grant(_ s: inout GameState, companyID: Int, line j: JSONValue, dealWeek: Int?, data: GameData) -> Bool {
        guard let line = decode(j) else { return false }
        let r: EquipmentMarket.Result
        switch line.kind {
        case .new:
            guard let offer = EquipmentMarket.offers(s, companyID: companyID, equipmentID: line.equipmentID, data: data).first(where: { $0.index == line.offerIndex }) else { return false }
            r = EquipmentMarket.buyNew(&s, companyID: companyID, equipmentID: line.equipmentID, offer: offer, quantity: line.quantity, payment: line.payment, prepaid: true, dealWeek: dealWeek, data: data)
        case .plan:
            guard let offer = EquipmentMarket.offers(s, companyID: companyID, equipmentID: line.equipmentID, data: data).first(where: { $0.index == line.offerIndex }) else { return false }
            r = EquipmentMarket.subscribe(&s, companyID: companyID, equipmentID: line.equipmentID, plan: line.plan, offer: offer, prepaid: true, data: data)
        case .vehicle:
            guard let offer = EquipmentMarket.vehicleOffers(s, companyID: companyID, equipmentID: line.equipmentID, data: data).first(where: { $0.id == line.vehicleOfferID }) else { return false }
            r = EquipmentMarket.buyNewVehicle(&s, companyID: companyID, equipmentID: line.equipmentID, offer: offer, payment: line.payment, prepaid: true, dealWeek: dealWeek, data: data)
        case .used:
            guard let u = line.used else { return false }
            r = EquipmentMarket.buyUsed(&s, companyID: companyID, equipmentID: line.equipmentID, listing: u, payment: line.payment, prepaid: true, data: data)
        }
        return r == .ok
    }

    // MARK: Records

    static func encode(_ line: Line, quote q: LineQuote, eta: Int) -> JSONValue {
        var o: [String: JSONValue] = ["k": .string(line.kind.rawValue), "eq": .string(line.equipmentID), "nm": .string(q.name), "q": .number(Double(max(1, line.quantity))),
                                      "i": .number(Double(line.offerIndex)), "v": .string(line.vehicleOfferID), "pl": .number(Double(line.plan)), "pay": .string(q.payment.rawValue),
                                      "g": .number(q.goods), "c": .number(q.chargeNow), "eta": .number(Double(eta)), "done": .bool(false)]
        if let u = line.used { o["u"] = encodeUsed(u) }
        return .object(o)
    }

    static func decode(_ j: JSONValue) -> Line? {
        guard let kind = Line.Kind(rawValue: j["k"].string), let pay = EquipmentMarket.Payment(rawValue: j["pay"].string) else { return nil }
        return Line(kind: kind, equipmentID: j["eq"].string, quantity: max(1, j["q"].int), offerIndex: j["i"].int, vehicleOfferID: j["v"].string, plan: j["pl"].int,
                    payment: pay, used: j["u"].isNull ? nil : decodeUsed(j["u"]))
    }

    static func encodeUsed(_ u: EquipmentMarket.UsedOffer) -> JSONValue {
        .object(["key": .string(u.key), "slot": .number(Double(u.slot)), "bi": .number(Double(u.brandIndex)), "mid": .string(u.modelID), "nm": .string(u.name),
                 "cls": .number(Double(u.cls)), "age": .number(Double(u.age)), "yr": .number(Double(u.year)), "tc": .number(u.trueCondition), "vc": .number(u.visibleCondition),
                 "kl": .bool(u.knownToLast), "pr": .number(u.price), "sl": .string(u.seller), "sy": .string(u.says), "rel": .number(u.reliability), "rt": .number(u.rating),
                 "pf": .number(u.performance), "km": .number(Double(u.kilometres)), "rk": .string(u.risk), "fu": .string(u.fuel)])
    }

    static func decodeUsed(_ j: JSONValue) -> EquipmentMarket.UsedOffer {
        EquipmentMarket.UsedOffer(key: j["key"].string, slot: j["slot"].int, brandIndex: j["bi"].int, modelID: j["mid"].string, name: j["nm"].string, cls: j["cls"].int,
                                  age: j["age"].int, year: j["yr"].int, trueCondition: j["tc"].double, visibleCondition: j["vc"].double, knownToLast: j["kl"].bool,
                                  price: j["pr"].double, seller: j["sl"].string, says: j["sy"].string, reliability: j["rel"].double, rating: j["rt"].double,
                                  performance: j["pf"].double, kilometres: j["km"].int, risk: j["rk"].string, fuel: j["fu"].string)
    }

    /// One placed order as the screens show it.
    public struct Record: Equatable, Sendable, Identifiable {
        public var id: String { number }
        public var number: String
        public var placedText: String
        public var deliveryText: String
        public var delivered: Bool
        public var items: [String]
        public var total: Double
        public var carrier: String
        public var receiptCompanyID: Int
    }

    public static func records(_ co: Company) -> [Record] {
        co.value(key).array.map { o in
            let lines = o["lines"].array
            let placed = GameCalendar.dateString(week: o["w"].int, dayOffset: o["d"].int)
            return Record(number: o["no"].string, placedText: placed, deliveryText: dateText(o["eta"].int), delivered: o["st"].string == "done",
                          items: lines.map { $0["nm"].string }, total: o["paid"].double, carrier: o["car"].string, receiptCompanyID: o["rc"].int)
        }
    }
}
