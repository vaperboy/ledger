import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum Shipments {
    public enum OrderResult: Equatable, Sendable {
        case ok(landed: Double, shipment: Int?)
        case unknownCompany, notOpen, badOrder, noCash
    }

    static let holdChance = 0.15
    static let inspectionChance = 0.08
    static let damageChance = 0.03

    public static func inTransit(_ s: GameState, companyID: Int? = nil) -> [JSONValue] {
        (s.rest["lg"]?["ship"].array ?? []).filter { companyID == nil || $0["co"].int == companyID! }
    }

    public struct Row: Identifiable, Equatable, Sendable {
        public var id: Int
        public var companyID: Int
        public var supplier: String
        public var from: String
        public var goods: Double
        public var arrivesWeek: Int
        public var weeksLeft: Int
        public var delayedWeeks: Int
        public var crossesBorder: Bool
        public var perishable: Bool
    }

    public static func rows(_ s: GameState, companyID: Int? = nil) -> [Row] {
        inTransit(s, companyID: companyID).map { j in
            Row(id: j["id"].int, companyID: j["co"].int, supplier: j["nm"].string.isEmpty ? j["sup"].string : j["nm"].string, from: j["from"].string, goods: j["goods"].double,
                arrivesWeek: j["eta"].int, weeksLeft: max(0, j["eta"].int - s.week), delayedWeeks: j["delay"].int, crossesBorder: j["border"].bool, perishable: j["perish"].bool)
        }.sorted { $0.arrivesWeek != $1.arrivesWeek ? $0.arrivesWeek < $1.arrivesWeek : $0.id < $1.id }
    }

    static func tell(_ s: inout GameState, companyID: Int, title: String, body: String, tone: String = "bad") {
        s.note(body, tone: tone, companyID: companyID)
        s.addMessage(kind: "info", from: "Deliveries", title: title, body: body, companyID: companyID, tone: tone)
    }

    @discardableResult
    public static func order(_ s: inout GameState, companyID: Int, offer: TransportCost.Offer, units: Double, cargo: TransportCost.Cargo = .standard, supplierName: String = "", data: GameData) -> OrderResult {
        guard let i = s.companyIndex(companyID) else { return .unknownCompany }
        guard s.companies[i].status == .open else { return .notOpen }
        guard units > 0, units.isFinite, offer.unitPrice > 0, offer.unitPrice.isFinite else { return .badOrder }
        let co = s.companies[i]
        let w = World(state: s, data: data)
        let q = TransportCost.quote(goodsValue: jsRound(offer.unitPrice * units), from: offer.country, to: co.countryCode, cargo: cargo, priceLevel: w.country(co).costIndex)
        guard q.goodsValue > 0 else { return .badOrder }
        guard co.cash >= q.landed else { return .noCash }
        AccountingLedger.note(category: "cogs", label: "Stock and supplier purchases", ref: "supplier:\(offer.id)")
        Ledger.moveRaw(&s, .company(companyID), -q.goodsValue)
        if q.transport > 0 { Payments.companyPays(&s, companyID: companyID, amount: q.transport, category: "cogs", label: "Freight") }
        if q.customs > 0 { Payments.companyPays(&s, companyID: companyID, amount: q.customs, category: "cogs", label: "Customs duty") }
        if !q.crossesBorder && q.transitWeeks == 0 {
            s.companies[i].inventory += q.goodsValue
            return .ok(landed: q.landed, shipment: nil)
        }
        var lg = s.rest["lg"] ?? .object([:])
        let n = lg["n"].int + 1
        lg["n"] = .number(Double(n))
        var ships = lg["ship"].array
        ships.append(.object(["id": .number(Double(n)), "co": .number(Double(companyID)), "sup": .string(offer.id), "nm": .string(supplierName), "from": .string(offer.country),
                              "goods": .number(q.goodsValue), "eta": .number(Double(s.week + q.transitWeeks)), "perish": .bool(cargo == .perishable),
                              "border": .bool(q.crossesBorder), "chk": .bool(false), "delay": .number(0)]))
        lg["ship"] = .array(ships)
        s.rest["lg"] = lg
        return .ok(landed: q.landed, shipment: n)
    }

    public static func weekly(_ s: inout GameState, data: GameData) {
        guard var lg = s.rest["lg"], !lg["ship"].array.isEmpty else { return }
        var keep: [JSONValue] = []
        for var sh in lg["ship"].array {
            if sh["eta"].int > s.week { keep.append(sh); continue }
            let cid = sh["co"].int
            guard let i = s.companyIndex(cid), s.companies[i].status.isLive else { continue }
            var r = HashedRandom("\(s.seed):ship:\(sh["id"].int):\(s.week)")
            let cur = World(state: s, data: data).currency(s.companies[i])
            let name = s.companies[i].name
            var goods = sh["goods"].double
            if sh["border"].bool && !sh["chk"].bool {
                sh["chk"] = .bool(true)
                if r.next() < holdChance {
                    let weeks = 1 + Int(r.next() * 3)
                    let fee = jsRound(goods * 0.004 * Double(weeks) + cur.scaledPrice(300) * Double(weeks))
                    Payments.companyPays(&s, companyID: cid, amount: fee, category: "cogs", label: "Border storage fees")
                    sh["eta"] = .number(Double(s.week + weeks))
                    sh["delay"] = .number(sh["delay"].double + Double(weeks))
                    tell(&s, companyID: cid, title: "Delivery held at the border", body: "Border control is holding a delivery for \(name): it now arrives in \(weeks) week\(weeks == 1 ? "" : "s"). Storage fees: \(cur.display(fee)).")
                    keep.append(sh)
                    continue
                }
                if r.next() < inspectionChance {
                    let fee = jsRound(goods * 0.015)
                    Payments.companyPays(&s, companyID: cid, amount: fee, category: "cogs", label: "Customs inspection fee")
                    tell(&s, companyID: cid, title: "Customs inspected a delivery", body: "Customs inspected a delivery for \(name): extra fee \(cur.display(fee)).")
                }
            }
            let delay = sh["delay"].int
            if r.next() < damageChance {
                let share = 0.1 + 0.3 * r.next()
                let st = StockInsurance.settle(&s, companyID: cid, amount: goods * share, fromInventory: false, data: data)
                goods -= st.loss
                tell(&s, companyID: cid, title: "A delivery was damaged", body: "A delivery for \(name) was damaged on the way: \(cur.display(st.loss)) of goods lost\(st.paid > 0 ? ", \(cur.display(st.paid)) paid by the insurance" : "").")
            }
            if sh["perish"].bool && delay > 0 && goods > 0 {
                let spoiled = min(goods, jsRound(goods * min(0.7, 0.12 * Double(delay))))
                if spoiled > 0 {
                    Payments.book(&s, companyID: cid, category: "loss", amount: spoiled)
                    goods -= spoiled
                    tell(&s, companyID: cid, title: "Goods spoiled in a delay", body: "Part of a delayed delivery for \(name) spoiled: \(cur.display(spoiled)) lost.")
                }
            }
            if delay > 0, let bd = data.catalog[s.companies[i].type] {
                let cover = StockHandling.policyTarget(s.companies[i], bd)
                if let target = cover, s.companies[i].inventory < target * 0.5 {
                    EventEngine.addModifier(&s, i, key: "dem", multiplier: 0.88, weeks: Double(min(4, delay + 1)))
                    tell(&s, companyID: cid, title: "Shelves ran short", body: "\(name) ran short of stock while the delivery was held: fewer sales for a few weeks.")
                }
            }
            s.companies[i].inventory += max(0, goods)
        }
        lg["ship"] = .array(keep)
        s.rest["lg"] = lg
    }
}
