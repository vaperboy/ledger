import Foundation
import GameCore
import Countries
import Finance

/// One used item for sale on the Marketplace (the Phone app). Everything here is what the buyer can see; the item's real condition (`wear`)
/// and what it is really worth (`fairValue`) stay inside the engine until the item is bought (`Marketplace.reveal`).
public struct MarketListing: Sendable, Identifiable, Equatable {
    public var id: String
    /// Art/item family: the vehicle model id (`car_s`, `van_box` ...) or the trade equipment id.
    public var family: String
    public var title: String
    /// What the ad says about the condition, for example "Good condition, 82,000 km".
    public var blurb: String
    public var sellerName: String
    public var city: String
    /// Unrounded, in the company's currency units.
    public var askingPrice: Double
    public var postedDay: Int

    public init(id: String, family: String, title: String, blurb: String, sellerName: String, city: String, askingPrice: Double, postedDay: Int) {
        self.id = id; self.family = family; self.title = title; self.blurb = blurb; self.sellerName = sellerName
        self.city = city; self.askingPrice = askingPrice; self.postedDay = postedDay
    }
}

/// A talk with the seller of one listing. (Named `MarketNegotiation` because `Negotiation` is the module that already decides pay and
/// price talks; this one reuses its patience and temperament tables.)
public struct MarketNegotiation: Sendable, Equatable {
    public enum Mood: String, Sendable { case open, reluctant, refusing }
    public var listingID: String
    public var price: Double
    public var canDiscuss: Bool
    public var patienceLeft: Int
    public var mood: Mood
    public var lastMessage: String

    public init(listingID: String, price: Double, canDiscuss: Bool, patienceLeft: Int, mood: Mood, lastMessage: String) {
        self.listingID = listingID; self.price = price; self.canDiscuss = canDiscuss; self.patienceLeft = patienceLeft
        self.mood = mood; self.lastMessage = lastMessage
    }
}

/// The used-goods marketplace: a deterministic pool of second-hand cars, vans, equipment and furniture, the haggling with the seller and the
/// buying. Nothing in the pool is stored: week by week "cohorts" of listings are drawn from the game seed, each living two to six weeks, so the pool
/// is the same every time it is read. What the game remembers (`rest["mkt"]`): open talks, listings already bought, listings whose seller refused
/// this buyer, and what was revealed after a purchase.
public enum Marketplace {
    public static let lemonShare = 0.12, bargainShare = 0.04, noTalkShare = 0.15
    static let cohortWeeks = 6

    struct Hidden {
        var wear: Double, visWear: Double, fair: Double, aware: Double
        var kind: Int   // 0 normal, 1 bargain, 2 lemon
        var noTalk: Bool, vehicle: Bool
        var equipmentID: String, modelID: String
        var year: Int, km: Int, age: Int
        var brand: String, cls: Int
        var reliability: Double, rating: Double, performance: Double
        var seller: String
    }
    struct Entry { var l: MarketListing; var h: Hidden }

    struct Family { var key: String; var e: EquipmentSpec?; var model: String?; var weight: Double }

    // MARK: Pool

    static func families(_ co: Company, _ bd: Trade, _ tables: TradeTables) -> [Family] {
        var out: [Family] = []
        let own = Set(bd.equipment.map { $0.id })
        for e in bd.allEquipment where EquipmentMarket.canBuyUsed(e, tradeID: bd.id, tables: tables) {
            let wt = own.contains(e.id) ? 3.0 : 0.8
            if let models = e.vehicleModels {
                for m in models where tables.vehicles[m] != nil { out.append(Family(key: m, e: e, model: m, weight: wt * 0.7)) }
            } else {
                out.append(Family(key: e.id, e: e, model: nil, weight: wt))
            }
        }
        if bd.id == UsedCarDealer.tradeID {
            let carVans = tables.vehicles.keys.sorted().filter { ["car", "van"].contains(tables.raw["VEH_CLASS"][$0].string) }
            let total = out.reduce(0) { $0 + $1.weight }
            for m in carVans { out.append(Family(key: m, e: nil, model: m, weight: max(1, total) * 2.2 / Double(max(1, carVans.count)))) }
        }
        return out
    }

    static func group(_ n: Int) -> String {
        var s = String(n), out = ""
        while s.count > 3 { out = "," + s.suffix(3) + out; s = String(s.dropLast(3)) }
        return s + out
    }

    static func conditionWord(_ visWear: Double) -> String {
        visWear < 0.2 ? "Excellent condition" : visWear < 0.35 ? "Good condition" : visWear < 0.5 ? "Normal wear for its age" : "Used hard, but runs"
    }

    /// Everything live this week for this company (bought, refused and expired listings are left out).
    static func pool(_ s: GameState, companyID: Int, data: GameData) -> [Entry] {
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return [] }
        let w = World(state: s, data: data)
        let tables = data.catalog.tables
        let fams = families(co, bd, tables)
        guard !fams.isEmpty else { return [] }
        let totalW = fams.reduce(0) { $0 + $1.weight }
        let sellers = EquipmentMarket.book["sellers"].array.map { $0.string }
        let cities = (data.countries[co.countryCode]?.cities.map { $0.name }) ?? []
        let state = s.rest["mkt"] ?? .null
        let brands = EquipmentMarket.brandCount(co, state: s)
        var out: [Entry] = []
        for c in (s.week - cohortWeeks + 1)...s.week {
            var cr = HashedRandom("\(s.seed):mkc:\(co.id):\(c)")
            let n = 11 + Int(cr.next() * 4)
            for k in 0..<n {
                var r = HashedRandom("\(s.seed):mk:\(co.id):\(c):\(k)")
                let life = 2 + Int(r.next() * 5)
                if c + life <= s.week { continue }
                let id = "L\(co.id)_\(c)_\(k)"
                if state["sold"][id].bool { continue }
                if state["ref"][id].array.contains(where: { $0.int == co.id }) { continue }
                var pick = r.next() * totalW
                var f = fams[fams.count - 1]
                for x in fams { if pick < x.weight { f = x; break }; pick -= x.weight }
                guard let entry = make(id: id, c: c, r: &r, family: f, co: co, bd: bd, w: w, tables: tables, brands: brands, seed: s.seed, sellers: sellers, cities: cities, countries: data.countries) else { continue }
                out.append(entry)
            }
        }
        return out
    }

    static func make(id: String, c: Int, r: inout HashedRandom, family f: Family, co: Company, bd: Trade, w: World, tables: TradeTables, brands: Int, seed: Int,
                     sellers: [String], cities: [String], countries: CountryBook) -> Entry? {
        let year = GameCalendar.year(week: max(0, c))
        var name = "", cls = 1, base = 0.0, age = 1, km = 0, rel = 1.0, rating = 3.5, perf = 1.0
        let vehicle = f.model != nil
        if let m = f.model, let vm = tables.vehicles[m] {
            let vc = EquipmentMarket.vehicleOffers(model: m, modelName: vm.name, countryCode: co.countryCode, seed: seed, countries: countries)
            guard !vc.isEmpty else { return nil }
            let o = vc[Int(r.next() * Double(vc.count))]
            let cl = tables.raw["VEH_CLASS"][m].string
            age = 1 + Int(r.next() * (["plant", "ship", "plane"].contains(cl) ? 14 : 11))
            let kmY: Double = (cl == "truck" || cl == "bus") ? 90000 : (cl == "bike" || cl == "scooter") ? 4000 : 18000
            km = Int(roundTo(Double(age) * kmY * (0.6 + r.next() * 0.8), step: 1000))
            base = EquipmentMarket.vehiclePrice(vm, factor: o.priceFactor, w) * 0.8 * pow(0.87, Double(age - 1))
            name = o.name; rel = o.reliability; rating = o.rating
        } else if let e = f.e {
            let cat = EquipmentMarket.offers(for: e, tradeID: bd.id, family: bd.family, brands: brands, countryCode: co.countryCode, seed: seed, countries: countries, tables: tables)
            guard !cat.isEmpty else { return nil }
            let o = cat[Int(r.next() * Double(cat.count))]
            age = 1 + Int(r.next() * Double(min(8, Int(e.lifeYears) + 2)))
            base = EquipmentMarket.price(e, company: co, w, factor: o.priceFactor, vendor: o.vendorID) * 0.78 * pow(0.86, Double(age))
            name = o.name; cls = o.cls; rel = o.reliability; rating = o.rating; perf = o.performance
        } else { return nil }
        let roll = r.next()
        let kind = roll < bargainShare ? 1 : roll < bargainShare + lemonShare ? 2 : 0
        let noise = (r.next() + r.next() - 1) * 0.16
        var wear = min(0.7, max(0.02, 0.06 + Double(age) * 0.035 + Double(km) / 900_000 + noise))
        var vis = min(0.95, max(0.02, wear + (r.next() - 0.5) * 0.12))
        if kind == 2 { wear = 0.58 + r.next() * 0.3; vis = min(wear, 0.1 + r.next() * 0.22) }
        let fair = max(1, base * (0.85 + 0.3 * (1 - vis)))
        let price: Double
        switch kind {
        case 1: price = fair * (1 - (0.20 + 0.15 * r.next()))
        case 2: price = fair * (1 + (r.next() * 2 - 1) * 0.12)
        default: price = fair * (1 + (r.next() * 2 - 1) * 0.12)
        }
        let aware = r.next()
        let noTalk = r.next() < noTalkShare
        let seller = sellers.isEmpty ? "Private seller" : sellers[Int(r.next() * Double(sellers.count))]
        let city = cities.isEmpty ? "" : cities[Int(r.next() * Double(cities.count))]
        let word = conditionWord(vis)
        let blurb = vehicle ? "\(word), \(group(km)) km" : "\(word), \(age) \(age == 1 ? "year" : "years") old"
        let title = vehicle ? "\(name) \(year - age)" : name
        let h = Hidden(wear: wear, visWear: vis, fair: fair, aware: aware, kind: kind, noTalk: noTalk, vehicle: vehicle, equipmentID: f.e?.id ?? "", modelID: f.model ?? "",
                       year: year - age, km: km, age: age, brand: name, cls: cls, reliability: rel, rating: rating, performance: perf, seller: seller)
        let day = max(0, c * 7)
        return Entry(l: MarketListing(id: id, family: f.key, title: title, blurb: blurb, sellerName: seller, city: city, askingPrice: price, postedDay: day), h: h)
    }

    public static func listings(_ s: GameState, companyID: Int, data: GameData) -> [MarketListing] {
        pool(s, companyID: companyID, data: data).map { $0.l }
    }

    static func entry(_ s: GameState, listingID: String, companyID: Int, data: GameData) -> Entry? {
        pool(s, companyID: companyID, data: data).first { $0.l.id == listingID }
    }

    /// What it would cost to put right what the seller did not say about.
    static func repairEstimate(_ h: Hidden, mechanic: Bool) -> Double {
        h.fair * 0.3 * max(0, h.wear - 0.15) * (mechanic ? 0.75 : 1)
    }

    // MARK: Memory

    static func state(_ s: GameState) -> JSONValue { s.rest["mkt"] ?? .object([:]) }
    static func negKey(_ companyID: Int, _ id: String) -> String { "\(companyID):\(id)" }

    static func read(_ s: GameState, _ k: String) -> MarketNegotiation? {
        let v = state(s)["neg"][k]
        guard !v.isNull else { return nil }
        let mood: MarketNegotiation.Mood = v["mood"].int == 0 ? .open : v["mood"].int == 1 ? .reluctant : .refusing
        return MarketNegotiation(listingID: v["id"].string, price: v["price"].double, canDiscuss: v["left"].int > 0 && !v["no"].bool, patienceLeft: v["left"].int, mood: mood, lastMessage: v["msg"].string)
    }

    static func write(_ s: inout GameState, _ k: String, _ n: MarketNegotiation, noTalk: Bool) {
        var m = state(s)
        var neg = m["neg"]; if neg.isNull { neg = .object([:]) }
        neg[k] = .object(["id": .string(n.listingID), "price": .number(n.price), "left": .number(Double(n.patienceLeft)), "no": .bool(noTalk),
                          "mood": .number(n.mood == .open ? 0 : n.mood == .reluctant ? 1 : 2), "msg": .string(n.lastMessage), "w": .number(Double(s.week))])
        m["neg"] = neg
        s.rest["mkt"] = m
    }

    // MARK: Talking

    static let openWords = ["The seller is open to a sensible offer.", "The seller says the price can move a little.", "The seller is in no hurry, but is listening."]
    static let noTalkWords = ["The seller says the price is the price.", "The seller will not discuss the price.", "The seller has had other offers and will not haggle."]
    static let dropWords = ["The seller thinks about it and comes down.", "The seller sighs and takes a little off.", "The seller agrees to a lower price."]
    static let stuckWords = ["The seller will not go lower.", "The seller shakes their head: that is the least they can take."]
    static let lastWords = ["That is my last word.", "The seller says this is as low as they will go, and the talk is over."]
    static let goneWords = ["The seller has had enough and will not sell to you any more.", "The seller does not want to hear from you again."]

    static func word(_ a: [String], _ key: String) -> String { a[Int(HashedRandom.first(key) * Double(a.count)) % a.count] }

    public static func begin(_ s: inout GameState, listingID: String, companyID: Int, data: GameData) -> MarketNegotiation? {
        guard let e = entry(s, listingID: listingID, companyID: companyID, data: data) else { return nil }
        let k = negKey(companyID, listingID)
        if let n = read(s, k) { return n }
        let n: MarketNegotiation
        if e.h.noTalk {
            n = MarketNegotiation(listingID: listingID, price: e.l.askingPrice, canDiscuss: false, patienceLeft: 0, mood: .refusing, lastMessage: word(noTalkWords, "nt:\(listingID)"))
        } else {
            let t = Negotiation.temperament(personality: nil, key: "mk:" + listingID)
            n = MarketNegotiation(listingID: listingID, price: e.l.askingPrice, canDiscuss: true, patienceLeft: Negotiation.patience(rank: "deal", temperament: t), mood: .open, lastMessage: word(openWords, "op:\(listingID)"))
        }
        write(&s, k, n, noTalk: e.h.noTalk)
        return n
    }

    /// Ask for a lower price. Each push costs a unit of patience; a seller who knows of faults gives more, one who sits on a bargain gives little.
    /// Pushing a seller who has given up ends it: the listing is closed to this buyer for good.
    public static func push(_ s: inout GameState, listingID: String, companyID: Int, data: GameData) -> MarketNegotiation {
        let blank = MarketNegotiation(listingID: listingID, price: 0, canDiscuss: false, patienceLeft: 0, mood: .refusing, lastMessage: "That listing is gone.")
        guard let e = entry(s, listingID: listingID, companyID: companyID, data: data), let first = begin(&s, listingID: listingID, companyID: companyID, data: data) else { return blank }
        let k = negKey(companyID, listingID)
        var n = first
        let noTalk = e.h.noTalk
        if !n.canDiscuss {
            var m = state(s)
            var ref = m["ref"]; if ref.isNull { ref = .object([:]) }
            var list = ref[listingID].array
            if !list.contains(where: { $0.int == companyID }) { list.append(.number(Double(companyID))) }
            ref[listingID] = .array(list); m["ref"] = ref
            s.rest["mkt"] = m
            n.lastMessage = word(goneWords, "gone:\(listingID)")
            n.mood = .refusing
            write(&s, k, n, noTalk: noTalk)
            return n
        }
        let h = e.h
        var r = HashedRandom("\(s.seed):mkp:\(listingID):\(n.patienceLeft):\(Int(n.price))")
        let sellerEstimate = h.fair * (1 - 0.5 * h.wear * h.aware)
        let floor = h.kind == 1 ? e.l.askingPrice * 0.97 : sellerEstimate * 0.9
        let gap = n.price - floor
        var drop = n.price * (0.015 + 0.035 * r.next()) * (1 + 2 * h.wear * h.aware)
        if h.kind == 1 { drop *= 0.3 }
        drop = gap > 0 ? min(drop, gap * 0.6) : 0
        n.price -= drop
        n.patienceLeft -= 1
        if n.patienceLeft <= 0 {
            n.canDiscuss = false; n.mood = .refusing; n.patienceLeft = 0
            n.lastMessage = word(lastWords, "last:\(listingID)")
        } else {
            n.mood = n.patienceLeft == 1 ? .reluctant : .open
            n.lastMessage = drop >= n.price * 0.004 ? word(dropWords, "dr:\(listingID):\(n.patienceLeft)") : word(stuckWords, "st:\(listingID):\(n.patienceLeft)")
        }
        write(&s, k, n, noTalk: noTalk)
        return n
    }

    // MARK: Buying

    public enum BuyResult: Equatable, Sendable { case ok, refused(String) }

    public static func buy(_ s: inout GameState, listingID: String, companyID: Int, price: Double, data: GameData) -> BuyResult {
        guard let i = s.companyIndex(companyID), s.companies[i].status.isLive else { return .refused("That company no longer exists.") }
        guard let e = entry(s, listingID: listingID, companyID: companyID, data: data) else { return .refused("That listing is gone.") }
        let neg = read(s, negKey(companyID, listingID))
        let floor = neg?.price ?? e.l.askingPrice
        if price < floor - 0.005 { return .refused("The seller will not sell for less than the agreed price.") }
        if s.companies[i].cash < price { return .refused("The company does not have the cash.") }
        let h = e.h, co = s.companies[i]
        let mech = co.value("staff").array.contains { $0["role"].string == "mech" }
        var ok = false
        if co.type == UsedCarDealer.tradeID && h.vehicle && h.equipmentID.isEmpty {
            ok = UsedCarDealer.addStock(&s, companyIndex: i, listing: e.l, hidden: h, price: price)
        } else if let bd = data.catalog[co.type], let spec = bd.allEquipment.first(where: { $0.id == (h.vehicle ? (bd.allEquipment.first { $0.vehicleModels?.contains(h.modelID) == true }?.id ?? "") : h.equipmentID) }) {
            var slot = 0
            for u in listingID.utf16 { slot = (slot &* 31 &+ Int(u)) & 0xFFFFFF }
            let L = EquipmentMarket.UsedOffer(key: "mkt", slot: slot, brandIndex: 0, modelID: h.modelID, name: h.brand, cls: h.cls, age: h.age, year: h.year,
                                              trueCondition: 1 - h.wear, visibleCondition: 1 - h.visWear, knownToLast: false, price: price, seller: h.seller, says: e.l.blurb,
                                              reliability: h.reliability * (1 + Double(h.age) * (h.vehicle ? 0.05 : 0.04)), rating: h.rating, performance: h.performance,
                                              kilometres: h.km, risk: "", fuel: "")
            ok = EquipmentMarket.buyUsed(&s, companyID: companyID, equipmentID: spec.id, listing: L, payment: .cash, data: data) == .ok
        }
        guard ok else { return .refused("The company cannot use that item.") }
        var m = state(s)
        var sold = m["sold"]; if sold.isNull { sold = .object([:]) }
        sold[listingID] = .bool(true); m["sold"] = sold
        var neg2 = m["neg"]; if !neg2.isNull { neg2.removeKey(negKey(companyID, listingID)); m["neg"] = neg2 }
        let text = revealText(h, company: s.companies[i], mechanic: mech, state: s, data: data)
        var rev = m["rev"]; if rev.isNull { rev = .object([:]) }
        rev[negKey(companyID, listingID)] = .string(text)
        m["rev"] = rev
        s.rest["mkt"] = m
        s.addMessage(kind: "info", from: h.seller, title: "About the \(e.l.title) you bought", body: text, companyID: companyID, tone: h.kind == 2 ? "bad" : "n")
        return .ok
    }

    static func revealText(_ h: Hidden, company co: Company, mechanic: Bool, state s: GameState, data: GameData) -> String {
        let cur = World(state: s, data: data).currency(co)
        let cost = repairEstimate(h, mechanic: mechanic)
        let part = h.vehicle ? ["brakes", "clutch", "gearbox", "suspension", "engine mounts"][Int(HashedRandom.first("part:\(h.brand):\(h.year)") * 5) % 5]
                             : ["motor", "bearings", "control board", "seals", "wiring"][Int(HashedRandom.first("part:\(h.brand):\(h.year)") * 5) % 5]
        if h.wear > 0.45 { return "The seller did not mention the worn \(part): repair about \(cur.short(cost))." }
        if h.wear > 0.25 { return "It needs more work than the ad let on (the \(part) is tired): about \(cur.short(cost)) over time." }
        return "Nothing hidden: it is in the condition the ad described."
    }

    public static func reveal(_ s: GameState, listingID: String, companyID: Int) -> String? {
        let t = state(s)["rev"][negKey(companyID, listingID)]
        return t.isNull ? nil : t.string
    }

    /// Housekeeping once a week: forget talks and purchases of listings that have expired.
    public static func weekly(_ s: inout GameState) {
        guard var m = s.rest["mkt"], !m.isNull else { return }
        let cutoff = s.week - cohortWeeks - 2
        func weekOf(_ id: String) -> Int { Int(id.split(separator: "_").dropFirst().first ?? "") ?? Int.max }
        for key in ["sold", "ref"] where !m[key].isNull {
            for id in m[key].object.keys where weekOf(id) < cutoff { m[key].removeKey(id) }
        }
        if !m["neg"].isNull {
            for k in m["neg"].object.keys where m["neg"][k]["w"].int < cutoff { m["neg"].removeKey(k) }
        }
        s.rest["mkt"] = m
    }
}
