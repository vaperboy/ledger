import Foundation
import GameCore
import Businesses

public enum SupplyNews {
    public enum Kind: String, Sendable, CaseIterable { case price, capacity, ended }

    public struct Source: Equatable, Sendable {
        public var line: String
        public var item: String
        public var vendorID: String
        public var vendorName: String
        public var share: Double
        public var goods: Bool
    }

    public struct Roll: Equatable, Sendable {
        public var source: Source
        public var kind: Kind
        public var rise: Double
        public var weeks: Int
    }

    public static let weeklyChance = 0.02
    static let cooldownWeeks = 12
    static let minAgeWeeks = 8
    static let lapseWeeks = 26
    static let linkWarnWeeks = 8

    public static func sources(_ s: GameState, _ co: Company, _ bd: Trade, data: GameData) -> [Source] {
        var out: [Source] = []
        if Suppliers.hasGoods(bd, co), PlayerSupply.contract(s, buyer: co.id, line: "goods") == nil, SupplyDeals.governedBy(s, co, input: "goods") == nil,
           let v = Suppliers.goodsVendor(s, company: co, data: data) {
            out.append(Source(line: "goods", item: "goods", vendorID: v.id, vendorName: v.name, share: 1, goods: true))
        }
        for line in SupplyCatalogue.lines(co, bd) where line.isCogs && line.id != "goods" && line.tiers && !line.automatic && line.input != "goods" && line.input != "repair" {
            let id = SupplyCatalogue.chosenID(co, line: line.id)
            guard id.hasPrefix("V-"), let v = Suppliers.vendor(s, id: id, data: data) else { continue }
            out.append(Source(line: line.id, item: line.name.lowercased(), vendorID: v.id, vendorName: v.name, share: line.share, goods: false))
        }
        return out
    }

    public static func roll(_ s: GameState, _ co: Company, sources: [Source], chance: Double = weeklyChance) -> Roll? {
        guard !sources.isEmpty else { return nil }
        var h = HashedRandom("\(s.seed):sn:\(s.week):\(co.id)")
        guard h.next() < chance else { return nil }
        let src = sources[Int(h.next() * Double(sources.count)) % sources.count]
        let k = h.next()
        let kind: Kind = k < 0.45 ? .price : (k < 0.8 ? .capacity : .ended)
        let size = h.next()
        let spread = h.next()
        switch kind {
        case .price: return Roll(source: src, kind: kind, rise: 0.03 + size * 0.05, weeks: 6 + Int(spread * 5))
        case .capacity: return Roll(source: src, kind: kind, rise: 0.04 + size * 0.04, weeks: 2 + Int(spread * 2))
        case .ended: return Roll(source: src, kind: kind, rise: 0.03 + size * 0.03, weeks: 4 + Int(spread * 3))
        }
    }

    static func lastWeek(_ co: Company, _ key: String) -> Int {
        let v = co.value("snw")[key]
        return v.isNull ? Int.min / 2 : v.int
    }

    static func remember(_ s: inout GameState, _ i: Int, _ key: String) {
        var o = s.companies[i].value("snw")
        if o.isNull { o = .object([:]) }
        o[key] = .number(Double(s.week))
        s.companies[i].set("snw", o)
    }

    public static func spawn(_ s: inout GameState, companyIndex i: Int, data: GameData) {
        guard s.companies.indices.contains(i), s.companies[i].status == .open, let opened = s.companies[i].openedWeek, s.week - opened >= minAgeWeeks,
              let bd = data.catalog[s.companies[i].type], bd.family != "hold" else { return }
        let co = s.companies[i]
        let difficulty = Difficulty.of(s)
        let chance = s.week > difficulty.badEventCapWeeks ? weeklyChance * difficulty.eventRamp(data.balance, week: s.week) : 0
        var gate = HashedRandom("\(s.seed):sn:\(s.week):\(co.id)")
        if gate.next() < chance, !Sourcing.suppliedFromInside(s, companyID: co.id) {
            if let r = roll(s, co, sources: sources(s, co, bd, data: data), chance: chance),
               s.week - lastWeek(co, r.source.vendorID) >= cooldownWeeks {
                apply(&s, companyIndex: i, r, data: data)
            }
        }
        supplierSide(&s, companyIndex: i)
    }

    @discardableResult
    public static func apply(_ s: inout GameState, companyIndex i: Int, _ r: Roll, data: GameData) -> Double {
        let co = s.companies[i]
        let src = r.source
        let m = 1 + r.rise * (src.goods ? 1 : max(0.1, src.share))
        let pct = max(1, Int(saturating: ((m - 1) * 100).rounded()))
        EventEngine.addModifier(&s, i, key: "cogsup", multiplier: m, weeks: Double(r.weeks))
        remember(&s, i, src.vendorID)
        let title: String
        let body: String
        switch r.kind {
        case .price:
            title = "\(src.vendorName) raised its prices"
            body = "\(src.vendorName), your supplier of \(src.item), put its prices up. Your cost of sales runs about \(pct)% higher for \(r.weeks) weeks. You can pick another supplier in the supplier list."
        case .capacity:
            title = "\(src.vendorName) ran out of capacity"
            body = "\(src.vendorName) could not fill all of your \(src.item) order. The rest was bought at spot prices, so your cost of sales runs about \(pct)% higher for \(r.weeks) weeks."
        case .ended:
            release(&s, companyIndex: i, src, data: data)
            title = "\(src.vendorName) ended your supply deal"
            body = "\(src.vendorName) will no longer supply your \(src.item). You buy from the market for now, which costs about \(pct)% more for \(r.weeks) weeks while you switch. Pick a new supplier in the supplier list."
        }
        s.addMessage(kind: "info", from: src.vendorName, title: title, body: body, companyID: co.id, tone: "bad")
        s.note("\(co.name): \(title).", tone: "bad", companyID: co.id)
        return m
    }

    static func release(_ s: inout GameState, companyIndex i: Int, _ src: Source, data: GameData) {
        let id = s.companies[i].id
        if src.goods {
            if s.companies[i].value("src")["v"].string == src.vendorID { Suppliers.chooseGoodsVendor(&s, companyID: id, vendorID: "auto") }
            if Suppliers.agreement(s, scope: "goods") == src.vendorID {
                var a = s.rest["agree"] ?? .object([:])
                a["goods"] = .null
                s.rest["agree"] = a
            }
            var sdl = s.companies[i].value("sdl")
            if !sdl.isNull, sdl["goods"]["v"].string == src.vendorID {
                var o = sdl.object
                o.removeValue(forKey: "goods")
                sdl = .object(o)
                s.companies[i].set("sdl", sdl)
            }
            Sourcing.lapse(&s, companyIndex: i, vendorID: src.vendorID, until: s.week + lapseWeeks)
        } else {
            _ = SupplyCatalogue.choose(&s, companyID: id, line: src.line, offer: "market", data: data)
        }
    }

    static func supplierSide(_ s: inout GameState, companyIndex i: Int) {
        let co = s.companies[i]
        var seen = co.value("snl")
        var changed = false
        for l in PlayerSupply.listings(s) where l.companyID == co.id && !l.stopped && !l.paused {
            let cap = SupplyGuards.effectiveCapacity(l)
            let full = cap - l.committedUnits < max(1, l.minOrder)
            let prev = seen[l.id]
            let before = prev["c"].int
            if !prev.isNull {
                if full && !prev["f"].bool {
                    EventEngine.addModifier(&s, i, key: "cogsup", multiplier: 1.02, weeks: 2)
                    s.addMessage(kind: "info", from: co.name, title: "\(l.lineName) is fully booked",
                                 body: "All \(cap) units a week of your \(l.lineName.lowercased()) are taken, so new buyers are turned away. Running flat out costs about 2% more for 2 weeks. A higher price or more capacity would earn more.",
                                 companyID: co.id, tone: "good")
                } else if before > 0 && l.committedUnits * 4 <= before * 3 {
                    EventEngine.addModifier(&s, i, key: "cogsup", multiplier: 1.02, weeks: 4)
                    s.addMessage(kind: "info", from: co.name, title: "Buyers cut back on \(l.lineName.lowercased())",
                                 body: "Orders for your \(l.lineName.lowercased()) fell from \(before) to \(l.committedUnits) units a week, so a buyer ended or cut a contract. Fixed costs stay, so unit costs run about 2% higher for 4 weeks.",
                                 companyID: co.id, tone: "bad")
                }
            }
            seen[l.id] = .object(["c": .number(Double(l.committedUnits)), "f": .bool(full)])
            changed = true
        }
        if changed { s.companies[i].set("snl", seen) }
        for link in IntercompanySupply.links(s) where link.supplierID == co.id && link.lastShare < 0.9 {
            let key = "g\(link.id)"
            guard s.week - lastWeek(s.companies[i], key) >= linkWarnWeeks, let buyer = s.company(link.buyerID) else { continue }
            remember(&s, i, key)
            let what = IntercompanySupply.kind(link.kindID)?.name.lowercased() ?? "supplies"
            s.addMessage(kind: "info", from: co.name, title: "\(co.name) is short on capacity",
                         body: "\(co.name) could cover only \(Int(saturating: (link.lastShare * 100).rounded()))% of the \(what) that \(buyer.name) needs. \(buyer.name) bought the rest outside at higher prices.",
                         companyID: co.id, tone: "bad")
        }
    }
}
