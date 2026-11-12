import Foundation
import GameCore
import Countries
import Finance

public struct SupplyOrderRecord: Identifiable, Equatable, Sendable {
    public var id: String
    public var listingID: String
    public var buyerName: String
    public var units: Int
    public var delivered: Int
    public var late: Bool
    public var day: Int
    public var revenue: Double

    public init(id: String, listingID: String, buyerName: String, units: Int, delivered: Int, late: Bool, day: Int, revenue: Double) {
        self.id = id; self.listingID = listingID; self.buyerName = buyerName; self.units = units; self.delivered = delivered
        self.late = late; self.day = day; self.revenue = revenue
    }
}

public enum PlayerSupply {
    public struct Contract: Identifiable, Equatable, Sendable {
        public var base: SupplyContract
        public var priceTier: Int
        public var qualityTier: Int
        public var reliability: Double
        public var termsDays: Int
        public var leadDays: Int
        public var country: String
        public var landedFactor: Double
        public var friend: Bool = false
        public var orderValue: Double = 0
        public var id: String { base.id }
    }

    public static let cancelFeeWeeks = 2.0

    public static func cancelFee(_ c: Contract) -> Double { c.orderValue * cancelFeeWeeks }

    public static func priceFactor(_ c: Contract) -> Double { FriendTies.price(SupplyCatalogue.tierPrice[min(2, max(0, c.priceTier))] * max(1, c.landedFactor), friend: c.friend) }

    public static func reliability(of r: DeliveryRecord) -> Double {
        if SupplyRecordRules.isUnproven(r) { return 0.93 }
        return min(0.995, max(0.8, 0.5 * r.deliveredShare + 0.5 * r.onTimeShare))
    }

    static func record(_ s: GameState) -> JSONValue { s.rest["psup"] ?? .object([:]) }

    static func contract(_ j: JSONValue) -> Contract {
        Contract(base: SupplyContract(id: j["id"].string, buyerCompanyID: j["b"].int, lineID: j["ln"].string, listingID: j["li"].string, supplierOwnerID: j["ow"].string,
                                      supplierName: j["nm"].string, unitsPerWeek: j["u"].int, startDay: j["d0"].int),
                 priceTier: j["pt"].int, qualityTier: j["qt"].int, reliability: j["rel"].isNull ? 0.93 : j["rel"].double, termsDays: j["tm"].int, leadDays: j["ld"].int,
                 country: j["cc"].string, landedFactor: j["lf"].isNull ? 1 : j["lf"].double, friend: j["fr"].bool, orderValue: j["ov"].double)
    }

    static func json(_ c: Contract) -> JSONValue {
        .object(["id": .string(c.base.id), "b": .number(Double(c.base.buyerCompanyID)), "ln": .string(c.base.lineID), "li": .string(c.base.listingID), "ow": .string(c.base.supplierOwnerID),
                 "nm": .string(c.base.supplierName), "u": .number(Double(c.base.unitsPerWeek)), "d0": .number(Double(c.base.startDay)), "pt": .number(Double(c.priceTier)),
                 "qt": .number(Double(c.qualityTier)), "rel": .number(c.reliability), "tm": .number(Double(c.termsDays)), "ld": .number(Double(c.leadDays)),
                 "cc": .string(c.country), "lf": .number(c.landedFactor), "ov": .number(c.orderValue), "fr": .bool(c.friend)])
    }

    public static func contracts(_ s: GameState) -> [Contract] { record(s)["c"].array.map { contract($0) } }

    public static func contract(_ s: GameState, buyer: Int, line: String) -> Contract? {
        contracts(s).first { $0.base.buyerCompanyID == buyer && $0.base.lineID == line }
    }

    static func isCatalogueLine(_ line: SupplyCatalogue.Line) -> Bool { line.tiers && line.input != "goods" && line.input != "repair" }

    @discardableResult
    public static func sign(_ s: inout GameState, contract base: SupplyContract, listing l: SupplyListing, weeklyMarketSpend: Double, data: GameData) -> Bool {
        guard let bi = s.companyIndex(base.buyerCompanyID), s.companies[bi].status.isLive, let bd = data.catalog[s.companies[bi].type],
              let line = SupplyCatalogue.lines(s.companies[bi], bd).first(where: { $0.id == base.lineID }), base.unitsPerWeek > 0 else { return false }
        let co = s.companies[bi]
        let level = World(state: s, data: data).country(co).costIndex
        let spend = max(0, weeklyMarketSpend.isFinite ? weeklyMarketSpend : 0)
        let row = SupplyLanded.compare([l], buyerCountry: co.countryCode, marketUnitPrice: spend / Double(base.unitsPerWeek), units: base.unitsPerWeek, priceLevel: level).first
        let c = Contract(base: base, priceTier: l.priceTier, qualityTier: l.qualityTier, reliability: reliability(of: l.record), termsDays: l.termsDays, leadDays: l.leadDays,
                         country: l.country, landedFactor: max(1, row?.landedFactor ?? 1), friend: l.isFriend, orderValue: (row?.unitPrice ?? 0) * Double(base.unitsPerWeek))
        var rec = record(s)
        var list = rec["c"].array.filter { !($0["b"].int == base.buyerCompanyID && $0["ln"].string == base.lineID) }
        list.append(json(c))
        rec["c"] = .array(list)
        var rw = rec["rw"].object
        rw[base.id] = .number(Double(s.week))
        rec["rw"] = .object(rw)
        s.rest["psup"] = rec
        if isCatalogueLine(line) { setChoice(&s, companyIndex: bi, line: line.id, offer: "P:" + base.id) }
        return true
    }

    public static func end(_ s: inout GameState, buyer: Int, line: String) {
        guard var rec = s.rest["psup"], let c = contract(s, buyer: buyer, line: line) else { return }
        rec["c"] = .array(rec["c"].array.filter { !($0["b"].int == buyer && $0["ln"].string == line) })
        var miss = rec["miss"].object
        miss.removeValue(forKey: c.base.id)
        rec["miss"] = .object(miss)
        var dr = rec["dr"].object
        dr.removeValue(forKey: c.base.id)
        rec["dr"] = .object(dr)
        var rw = rec["rw"].object
        rw.removeValue(forKey: c.base.id)
        rec["rw"] = .object(rw)
        s.rest["psup"] = rec
        if let i = s.companyIndex(buyer), SupplyCatalogue.chosenID(s.companies[i], line: line)?.hasPrefix("P:") == true { setChoice(&s, companyIndex: i, line: line, offer: "market") }
    }

    @discardableResult
    public static func cancel(_ s: inout GameState, buyer: Int, line: String, bySupplier: Bool) -> String? {
        guard let c = contract(s, buyer: buyer, line: line), let co = s.company(buyer) else { return "There is no supplier to end." }
        let fee = cancelFee(c)
        if bySupplier {
            Payments.companyReceives(&s, companyID: buyer, amount: fee, category: "oth", label: "Fee from \(c.base.supplierName) for ending the supply")
        } else {
            if co.cash < fee { return "Not enough cash for the cancellation fee." }
            Payments.companyPays(&s, companyID: buyer, amount: fee, category: "oth", label: "Fee to \(c.base.supplierName) for ending the supply")
        }
        end(&s, buyer: buyer, line: line)
        s.addMessage(kind: "info", from: c.base.supplierName, title: bySupplier ? "Supplier ended the supply" : "Supply ended",
                     body: bySupplier ? "\(c.base.supplierName) stopped supplying and paid the fee of two weeks of the order. This line goes back to your usual supplier."
                                      : "You ended the supply from \(c.base.supplierName) and paid the fee of two weeks of the order. This line goes back to your usual supplier.",
                     companyID: buyer, tone: bySupplier ? "bad" : "n")
        return nil
    }

    private static func setChoice(_ s: inout GameState, companyIndex i: Int, line: String, offer: String) {
        var o = s.companies[i].value("sc").object
        if offer == "market" { o.removeValue(forKey: line) } else { o[line] = .string(offer) }
        s.companies[i].set("sc", .object(o))
    }

    @discardableResult
    public static func recordMiss(_ s: inout GameState, listingID: String) -> [Contract] {
        let hit = contracts(s).filter { $0.base.listingID == listingID && s.company($0.base.buyerCompanyID)?.status.isLive == true }
        guard !hit.isEmpty else { return [] }
        var rec = record(s)
        var miss = rec["miss"].object
        for c in hit {
            miss[c.base.id] = .number(Double(s.week))
            s.addMessage(kind: "info", from: c.base.supplierName, title: "A delivery arrived short",
                         body: "\(c.base.supplierName) delivered less than promised this week. If this is a line your sales depend on, fewer customers were served.",
                         companyID: c.base.buyerCompanyID, tone: "bad")
        }
        rec["miss"] = .object(miss)
        s.rest["psup"] = rec
        return hit
    }

    static func missed(_ s: GameState, buyer: Int, line: String, week: Int) -> Bool {
        guard let c = contract(s, buyer: buyer, line: line) else { return false }
        let w = record(s)["miss"][c.base.id]
        return !w.isNull && w.int >= week - 1 && w.int <= week
    }

    static func offer(_ c: Contract, line: SupplyCatalogue.Line) -> SupplyCatalogue.Offer {
        SupplyCatalogue.Offer(id: "P:" + c.base.id, name: c.base.supplierName, owner: c.base.supplierName, tier: min(2, max(0, c.qualityTier)), priceFactor: priceFactor(c),
                              reliability: c.reliability, termsDays: c.termsDays, leadDays: line.leadDays + c.leadDays, relationshipWord: c.friend ? "Friend supplier" : "Player supplier")
    }

    static func recordJSON(_ r: DeliveryRecord) -> JSONValue {
        var o: [String: JSONValue] = ["wt": .number(Double(r.weeksTrading)), "ot": .number(Double(r.ordersTotal)), "oo": .number(Double(r.ordersOnTime)), "up": .number(Double(r.unitsPromised)),
                                      "ud": .number(Double(r.unitsDelivered)), "cp": .number(Double(r.complaints)), "dp": .number(Double(r.disputes)), "pc": .number(Double(r.priceChanges)),
                                      "cw": .number(Double(r.cleanWeeks)), "lu": .number(Double(r.lifetimeUnits))]
        if let d = r.deliveredTrend { o["dt"] = .number(d) }
        if let d = r.onTimeTrend { o["ott"] = .number(d) }
        return .object(o)
    }

    static func recordFrom(_ r: JSONValue) -> DeliveryRecord {
        DeliveryRecord(weeksTrading: r["wt"].int, ordersTotal: r["ot"].int, ordersOnTime: r["oo"].int, unitsPromised: r["up"].int, unitsDelivered: r["ud"].int,
                       complaints: r["cp"].int, disputes: r["dp"].int, priceChanges: r["pc"].int, cleanWeeks: r["cw"].int,
                       deliveredTrend: r["dt"].isNull ? nil : r["dt"].double, onTimeTrend: r["ott"].isNull ? nil : r["ott"].double, lifetimeUnits: r["lu"].int)
    }

    public static func deliveryRecord(_ s: GameState, buyer: Int, line: String) -> DeliveryRecord? {
        guard let c = contract(s, buyer: buyer, line: line) else { return nil }
        let j = record(s)["dr"][c.base.id]
        return j.isNull ? DeliveryRecord() : recordFrom(j)
    }

    @discardableResult
    public static func recordDelivery(_ s: inout GameState, listingID: String, promised: Int, delivered: Int, orders: Int = 1, late: Int = 0, complaints: Int = 0) -> [Contract] {
        let hit = contracts(s).filter { $0.base.listingID == listingID && s.company($0.base.buyerCompanyID)?.status.isLive == true }
        guard !hit.isEmpty, promised > 0 else { return [] }
        let got = max(0, min(delivered, promised))
        let n = max(1, orders)
        let lateOrders = max(0, min(late, n))
        let short = got < promised
        var rec = record(s)
        var dr = rec["dr"].object
        var rw = rec["rw"].object
        var list = rec["c"].array
        for c in hit {
            rw[c.base.id] = .number(Double(s.week))
            let before: DeliveryRecord = dr[c.base.id].map { recordFrom($0) } ?? DeliveryRecord()
            let next = SupplyRecordRules.applying(before, promised: promised, delivered: got, orders: n, late: lateOrders, complaints: max(complaints, short ? 1 : 0))
            dr[c.base.id] = recordJSON(next)
            if let k = list.firstIndex(where: { $0["id"].string == c.base.id }) { list[k]["rel"] = .number(reliability(of: next)) }
        }
        rec["dr"] = .object(dr)
        rec["rw"] = .object(rw)
        rec["c"] = .array(list)
        s.rest["psup"] = rec
        if short { recordMiss(&s, listingID: listingID) }
        return hit
    }

    @discardableResult
    public static func supplierEnded(_ s: inout GameState, listingID: String? = nil, ownerID: String? = nil, reason: SupplyEnd) -> [SupplyFallback] {
        let gone = contracts(s).filter { (listingID != nil && $0.base.listingID == listingID) || (ownerID != nil && $0.base.supplierOwnerID == ownerID) }
        var out: [SupplyFallback] = []
        for c in gone {
            end(&s, buyer: c.base.buyerCompanyID, line: c.base.lineID)
            let f = SupplyFallback(contract: c.base, reason: reason)
            SupplyMarketBooks.tellBuyer(&s, fallback: f)
            out.append(f)
        }
        return out
    }

    public static func applyFallback(_ s: inout GameState, _ f: SupplyFallback) {
        end(&s, buyer: f.contract.buyerCompanyID, line: f.contract.lineID)
        SupplyMarketBooks.tellBuyer(&s, fallback: f)
    }

    public static func noticeOfStop(_ s: inout GameState, listingID: String, endsDay: Int) {
        for c in contracts(s) where c.base.listingID == listingID && s.company(c.base.buyerCompanyID)?.status.isLive == true {
            s.addMessage(kind: "info", from: c.base.supplierName, title: "Your supplier will stop supplying",
                         body: "\(c.base.supplierName) has announced it will stop supplying on \(GameCalendar.dateString(week: endsDay / 7, dayOffset: endsDay % 7)). Until then it still delivers. After that this line goes back to your usual supplier.",
                         companyID: c.base.buyerCompanyID, tone: "bad")
        }
    }

    public static let silentWeeksLimit = 3

    public static func weekly(_ s: inout GameState) {
        for c in contracts(s) where s.company(c.base.buyerCompanyID)?.status.isLive != true { end(&s, buyer: c.base.buyerCompanyID, line: c.base.lineID) }
        for c in contracts(s) {
            var stamps = record(s)
            let seen = stamps["rw"][c.base.id]
            if seen.isNull {
                var rw = stamps["rw"].object
                rw[c.base.id] = .number(Double(s.week))
                stamps["rw"] = .object(rw)
                s.rest["psup"] = stamps
                continue
            }
            let quiet = s.week - seen.int
            if quiet >= silentWeeksLimit {
                let f = SupplyFallback(contract: c.base, reason: .silent)
                end(&s, buyer: c.base.buyerCompanyID, line: c.base.lineID)
                SupplyMarketBooks.tellBuyer(&s, fallback: f)
            } else if quiet == silentWeeksLimit - 1 {
                s.addMessage(kind: "info", from: c.base.supplierName, title: "Your supplier has gone quiet",
                             body: "\(c.base.supplierName) has not reported a delivery for \(quiet) weeks. If nothing arrives next week the contract ends and this line goes back to your usual supplier.",
                             companyID: c.base.buyerCompanyID, tone: "bad")
            }
        }
        var rec = record(s)
        var ls = rec["l"].array
        var changed = false
        for k in ls.indices where !ls[k]["st"].bool && s.company(ls[k]["co"].int)?.status != .open {
            ls[k]["st"] = .bool(true)
            changed = true
        }
        if changed { rec["l"] = .array(ls); s.rest["psup"] = rec }
    }

    public static func isOwnListing(_ s: GameState, _ l: SupplyListing) -> Bool {
        guard let id = l.companyID else { return false }
        return s.company(id) != nil
    }

    static func listingJSON(_ l: SupplyListing) -> JSONValue {
        let r = l.record
        var rec: [String: JSONValue] = ["wt": .number(Double(r.weeksTrading)), "ot": .number(Double(r.ordersTotal)), "oo": .number(Double(r.ordersOnTime)), "up": .number(Double(r.unitsPromised)),
                                        "ud": .number(Double(r.unitsDelivered)), "cp": .number(Double(r.complaints)), "dp": .number(Double(r.disputes)), "pc": .number(Double(r.priceChanges)),
                                        "cw": .number(Double(r.cleanWeeks)), "lu": .number(Double(r.lifetimeUnits))]
        if let d = r.deliveredTrend { rec["dt"] = .number(d) }
        if let d = r.onTimeTrend { rec["ott"] = .number(d) }
        var o: [String: JSONValue] = ["id": .string(l.id), "ow": .string(l.ownerID), "on": .string(l.ownerName), "pc": .string(l.profileCode), "cn": .string(l.companyName),
                                      "co": .number(Double(l.companyID ?? 0)), "td": .string(l.tradeID), "tn": .string(l.tradeName), "ci": .string(l.city), "rg": .string(l.region),
                                      "cc": .string(l.country), "ln": .string(l.lineID), "lnm": .string(l.lineName), "pt": .number(Double(l.priceTier)), "qt": .number(Double(l.qualityTier)),
                                      "cap": .number(Double(l.capacityPerWeek)), "ld": .number(Double(l.leadDays)), "mo": .number(Double(l.minOrder)), "tm": .number(Double(l.termsDays)),
                                      "lk": .string(l.linkKey), "rec": .object(rec), "pa": .bool(l.paused), "st": .bool(l.stopped), "cm": .number(Double(l.committedUnits)), "lg": .string(l.logoID)]
        if let e = l.expiresDay { o["ex"] = .number(Double(e)) }
        if let d = l.stopsDay { o["sd"] = .number(Double(d)) }
        return .object(o)
    }

    static func listing(_ j: JSONValue) -> SupplyListing {
        let r = j["rec"]
        let record = DeliveryRecord(weeksTrading: r["wt"].int, ordersTotal: r["ot"].int, ordersOnTime: r["oo"].int, unitsPromised: r["up"].int, unitsDelivered: r["ud"].int,
                                    complaints: r["cp"].int, disputes: r["dp"].int, priceChanges: r["pc"].int, cleanWeeks: r["cw"].int,
                                    deliveredTrend: r["dt"].isNull ? nil : r["dt"].double, onTimeTrend: r["ott"].isNull ? nil : r["ott"].double, lifetimeUnits: r["lu"].int)
        var made = SupplyListing(id: j["id"].string, ownerID: j["ow"].string, ownerName: j["on"].string, profileCode: j["pc"].string, companyName: j["cn"].string,
                             companyID: j["co"].int == 0 ? nil : j["co"].int, tradeID: j["td"].string, tradeName: j["tn"].string, city: j["ci"].string, region: j["rg"].string,
                             lineID: j["ln"].string, lineName: j["lnm"].string, priceTier: j["pt"].int, qualityTier: j["qt"].int, capacityPerWeek: j["cap"].int,
                             leadDays: j["ld"].int, minOrder: j["mo"].int, termsDays: j["tm"].int, linkKey: j["lk"].string, record: record, paused: j["pa"].bool,
                             stopped: j["st"].bool, expiresDay: j["ex"].isNull ? nil : j["ex"].int, committedUnits: j["cm"].int, country: j["cc"].string,
                             stopsDay: j["sd"].isNull ? nil : j["sd"].int)
        made.logoID = j["lg"].string
        return made
    }

    public static func listings(_ s: GameState) -> [SupplyListing] {
        record(s)["l"].array.map { listing($0) }.filter { l in l.companyID.map { s.company($0)?.status.isLive == true } ?? false }
    }

    public static func orders(_ s: GameState) -> [String: [SupplyOrderRecord]] {
        var out: [String: [SupplyOrderRecord]] = [:]
        for (k, v) in record(s)["o"].object {
            out[k] = v.array.map { SupplyOrderRecord(id: $0["id"].string, listingID: k, buyerName: $0["b"].string, units: $0["u"].int, delivered: $0["dl"].int, late: $0["lt"].bool,
                                                      day: $0["d"].int, revenue: $0["r"].double) }
        }
        return out
    }

    public static func saveListings(_ s: inout GameState, listings: [SupplyListing], orders: [String: [SupplyOrderRecord]]) {
        var rec = record(s)
        rec["l"] = .array(listings.filter { $0.companyID != nil }.map { listingJSON($0) })
        var o: [String: JSONValue] = [:]
        for l in listings where l.companyID != nil {
            let list = (orders[l.id] ?? []).prefix(20).map { r -> JSONValue in
                .object(["id": .string(r.id), "b": .string(r.buyerName), "u": .number(Double(r.units)), "dl": .number(Double(r.delivered)), "lt": .bool(r.late),
                         "d": .number(Double(r.day)), "r": .number(r.revenue)])
            }
            if !list.isEmpty { o[l.id] = .array(Array(list)) }
        }
        rec["o"] = .object(o)
        s.rest["psup"] = rec
    }
}
