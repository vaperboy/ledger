import Foundation
import GameCore
import Countries
import Finance

/// Franchise brands you can join as a franchisee: who they are, how they answer an application, and the talk about
/// the terms. Original: engine/world/franchise_brands.js (`fbMake`, `fbLocalList`, `fbGlobalList`, `fbStatus`, `fbPower`,
/// `fbNegotiate`, `fbApply`, `fbWeek`, `applyBrand`). The brands are made from the game seed and the trade and country, so
/// the same game always shows the same brands (the original keeps them in `S.fb`; here they are worked out when asked).
/// What is saved: the applications (`fbApps`), the weeks a brand will not talk (`fbLock`) and how many rounds you went (`fbIrr`).
public enum FranchiseBrands {
    /// Trades a brand franchises. Original: `FB_TYPES`.
    public static let tradeIDs: [String] = ["carclean", "carrepair", "cleaning", "tutor", "handy", "barber", "drivsk", "physio", "estate", "pets", "foodtruck",
                                           "cafe", "restaurant", "gym", "hotel", "fun", "kiosk", "boutique", "grocery", "hardware", "cardealer", "bakery", "courier"]
    public static func isFranchisable(_ tradeID: String) -> Bool { tradeIDs.contains(tradeID) }

    static let globalNames = ["Everest", "Nova", "Atlas", "Orbit", "Zenith", "Vertex", "Aurora", "Meridian", "Pulse", "Horizon", "Quantum", "Apex", "Lumen", "Titan",
                              "Spark", "Cosmos", "Vanguard", "Elevate", "Unity", "Crest", "Fusion", "Stellar", "Axis", "Radiant", "Polaris"]

    /// The word a brand name uses for each trade ("Nordic Plumbing"). Original: `FB_NOUNS`.
    static let nouns: [String: String] = ["cons": "Consulting", "tutor": "Tutoring", "carclean": "Car Care", "carrepair": "Auto Service", "photo": "Photo", "handy": "Handyman",
        "cleaning": "Cleaning", "webdev": "Digital", "mktg": "Marketing", "law": "Law", "acctfirm": "Accounting", "staffing": "Staffing", "barber": "Hair", "drivsk": "Driving School",
        "physio": "Physio", "estate": "Estate", "pets": "Pet Care", "foodtruck": "Street Food", "cafe": "Café", "restaurant": "Restaurant", "nightclub": "Club", "gym": "Gym",
        "hotel": "Hotel", "casino": "Casino", "fun": "Entertainment", "kiosk": "Convenience", "boutique": "Clothing", "webshop": "Online", "grocery": "Supermarket",
        "hardware": "Building Supplies", "cardealer": "Motors", "construction": "Construction", "electrician": "Electric", "plumber": "Plumbing", "realdev": "Property",
        "event": "Events", "engcons": "Engineering", "bakery": "Bakery", "brewery": "Brewing", "furniture": "Furniture", "salmon": "Seafood", "factory": "Industries",
        "farm": "Farms", "taxi": "Taxi", "courier": "Courier", "trucking": "Haulage", "shipping": "Shipping", "airline": "Air", "resrent": "Homes", "comrent": "Properties",
        "parking": "Parking", "insco": "Insurance", "bank": "Bank", "fund": "Capital", "power": "Power", "oilgas": "Energy"]

    struct TierSpec { var name: String; var units: (Int, Int); var strength: (Double, Double); var fee: Double; var royalty: (Double, Double); var flex: (Double, Double); var who: String }
    static let tiers: [TierSpec] = [
        TierSpec(name: "", units: (0, 0), strength: (0, 0), fee: 0, royalty: (0, 0), flex: (0, 0), who: ""),
        TierSpec(name: "Local brand", units: (3, 12), strength: (25, 45), fee: 0.8, royalty: (0.04, 0.06), flex: (20, 45), who: "owner"),
        TierSpec(name: "Regional chain", units: (15, 80), strength: (45, 62), fee: 1.5, royalty: (0.05, 0.07), flex: (35, 60), who: "owner"),
        TierSpec(name: "National chain", units: (90, 400), strength: (62, 80), fee: 2.6, royalty: (0.06, 0.085), flex: (55, 78), who: "manager"),
        TierSpec(name: "Global brand", units: (500, 2500), strength: (80, 95), fee: 4.2, royalty: (0.07, 0.1), flex: (70, 92), who: "manager"),
    ]

    /// A brand that takes franchisees. Original: the objects made by `fbMake`.
    public struct Brand: Equatable, Identifiable, Sendable {
        public var id: String
        public var tradeID: String
        public var name: String
        public var origin: String
        /// 1 local brand ... 4 global brand
        public var tier: Int
        public var tierName: String
        public var units: Int
        /// Brand strength 0-100. Original: `str`.
        public var strength: Double
        /// "open" takes new franchisees, "exp" only proven operators, "closed" none. Original: `open`.
        public var openness: String
        public var royalty: Double
        public var marketingFund: Double
        /// 0 none, 1 covers about 40% of the fit-out, 2 about 70%. Original: `supp`.
        public var support: Int
        public var termYears: Int
        public var failPercent: Double
        public var standard: Double
        public var flex: Double
        /// Reference-country entry fee before the country's price level. Original: `fee0`.
        public var baseFee: Double
        public var contact: String
        public var fitMultiplier: Double

        public var role: String { ["", "founder", "owner", "franchise manager", "CEO"][min(4, max(1, tier))] }
        /// "Name, the founder," as in the original's `fbWho`.
        public var who: String { "\(contact), the \(role)," }
        public var tierDescription: String {
            tierName + (tier == 4 && !origin.isEmpty ? " (from \(origin))" : "")
        }
    }

    /// What was agreed in the talk. Original: `fbTermsOf` result.
    public struct Terms: Equatable, Sendable {
        public var fee: Double
        public var royalty: Double
        public var marketing: Double
        public var cover: Int
        public var rent: Int
        public var vehicles: Int
        public var building: Int
        public var brandID: String
        /// A free space in one of your own commercial buildings, where the unit will be. Original: `terms.prem`.
        public var premises: BuildingRef?

        var json: JSONValue {
            var o: [String: JSONValue] = ["fee": .number(fee), "roy": .number(royalty), "mkt": .number(marketing), "cover": .number(Double(cover)), "rent": .number(Double(rent)),
                     "veh": .number(Double(vehicles)), "bld": .number(Double(building)), "brand": .string(brandID)]
            if let p = premises { o["prem"] = .object(["co": .number(Double(p.companyID)), "pid": .number(Double(p.propertyID))]) }
            return .object(o)
        }
        init(fee: Double, royalty: Double, marketing: Double, cover: Int, rent: Int, vehicles: Int, building: Int, brandID: String, premises: BuildingRef? = nil) {
            self.fee = fee; self.royalty = royalty; self.marketing = marketing; self.cover = cover; self.rent = rent; self.vehicles = vehicles; self.building = building; self.brandID = brandID
            self.premises = premises
        }
        init?(json j: JSONValue) {
            if j.isNull { return nil }
            self.init(fee: j["fee"].double, royalty: j["roy"].double, marketing: j["mkt"].double, cover: j["cover"].int, rent: j["rent"].int,
                      vehicles: j["veh"].int, building: j["bld"].int, brandID: j["brand"].string,
                      premises: j["prem"].isNull ? nil : BuildingRef(companyID: j["prem"]["co"].int, propertyID: j["prem"]["pid"].int))
        }
    }

    /// A building of one of your commercial rental companies. Original: `{ co, pid }`.
    public struct BuildingRef: Equatable, Sendable {
        public var companyID: Int
        public var propertyID: Int
        public init(companyID: Int, propertyID: Int) { self.companyID = companyID; self.propertyID = propertyID }
    }

    /// What you ask for. Fee and royalty are the share taken off (negative: you offer to pay more). Original: the `ask` object.
    public struct Ask: Equatable, Sendable {
        public var fee = 0.0, royalty = 0.0
        public var cover = 0, rent = 0, vehicles = 0, building = 0
        /// Put the unit in one of your own buildings (the franchisor likes a ready place: +16 bargaining power).
        public var premises: BuildingRef?
        public init() {}
    }

    public struct Negotiation: Equatable, Sendable {
        public enum Kind: String, Sendable { case accept, counter, push, refuse, closed }
        public var kind: Kind
        public var message: String
        public var counter: Ask?
        public var terms: Terms?
    }

    // MARK: Making the brands

    struct BrandRandom {
        var h: HashedRandom
        init(_ key: String) { h = HashedRandom(key) }
        mutating func next() -> Double { h.next() }
        mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
        mutating func int(_ a: Int, _ b: Int) -> Int { Int((Double(a) + next() * Double(b - a + 1)).rounded(.down)) }
        mutating func chance(_ p: Double) -> Bool { next() < p }
        mutating func pick<T>(_ a: [T]) -> T { a[Int((next() * Double(a.count)).rounded(.down)) % a.count] }
    }

    static func noun(_ tradeID: String, _ bd: Trade) -> String {
        if let n = nouns[tradeID] { return n }
        var first = bd.name.split(separator: " ").first.map(String.init) ?? bd.name
        if first.hasSuffix("s") { first.removeLast() }
        return first
    }

    static func bossName(_ r: inout BrandRandom, origin: String, p: Double, w: World) -> String {
        let codes = w.countries.countries.map { $0.code }
        let home = w.countries[origin]
        let useHome = home != nil && r.chance(p)
        let c = useHome ? home! : (w.countries[r.pick(codes.filter { $0 != origin })] ?? w.countries.countries[0])
        return r.pick(c.firstNames) + " " + r.pick(c.lastNames)
    }

    static func make(_ r: inout BrandRandom, bd: Trade, tier t: Int, name: String, origin: String, id: String, w: World) -> Brand {
        let T = tiers[t]
        let open = r.range(0, 1) < (t >= 3 ? 0.35 : 0.65) ? "open" : (r.range(0, 1) < 0.65 ? "exp" : "closed")
        let roy = (min(r.range(T.royalty.0, T.royalty.1), max(0.03, bd.margin * 0.4)) * 1000).rounded() / 1000
        let str = r.range(T.strength.0, T.strength.1).rounded()
        let base = (150000 + bd.openingCost * 2) * T.fee * r.range(0.9, 1.15)
        let units = r.int(T.units.0, T.units.1)
        let mkt = (min(r.range(0.02, 0.04), max(0.01, bd.margin * 0.15)) * 100).rounded() / 100
        let supp = t >= 3 ? (r.range(0, 1) < 0.3 ? 1 : 0) : r.int(0, 2)
        let term = r.int(5, 10)
        let fail = r.range(4, Double(22 - t * 2)).rounded()
        let std = Double(r.int(52, 80))
        let flex = r.range(T.flex.0, T.flex.1).rounded()
        let contact = bossName(&r, origin: origin, p: [0, 0.93, 0.9, 0.85, 0.8][t], w: w)
        return Brand(id: id, tradeID: bd.id, name: name, origin: origin, tier: t, tierName: T.name, units: units, strength: str, openness: open, royalty: roy, marketingFund: mkt,
                     support: supp, termYears: term, failPercent: fail, standard: std, flex: flex, baseFee: base, contact: contact, fitMultiplier: 1 + Double(t - 1) * 0.07)
    }

    /// Brands of one country: local, regional and national chains named from that country. Original: `fbLocalList`.
    public static func localBrands(_ tradeID: String, country cc: String, _ w: World) -> [Brand] {
        guard isFranchisable(tradeID), let bd = w.catalog[tradeID], let C = w.countries[cc] else { return [] }
        var r = BrandRandom("fb:\(w.state.seed):\(tradeID):\(cc)")
        let nb = r.int(2, 3)
        var tierList = [1, 2, 3]
        for k in stride(from: tierList.count - 1, to: 0, by: -1) { tierList.swapAt(k, r.int(0, k)) }
        let chosen = Array(tierList.prefix(nb)).sorted()
        var used: [String] = []
        var out: [Brand] = []
        let starts = C.companyNameStarts.isEmpty ? ["Nordic"] : C.companyNameStarts
        for t in chosen {
            var a = r.pick(starts)
            var guardCount = 0
            while used.contains(a) && guardCount < 40 { a = r.pick(starts); guardCount += 1 }
            used.append(a)
            out.append(make(&r, bd: bd, tier: t, name: a + " " + noun(tradeID, bd), origin: cc, id: "\(tradeID):\(cc):\(a)", w: w))
        }
        return out
    }

    /// Worldwide brands: the same in every country, with a home country of their own. Original: `fbGlobalList`.
    public static func globalBrands(_ tradeID: String, _ w: World) -> [Brand] {
        guard isFranchisable(tradeID), let bd = w.catalog[tradeID] else { return [] }
        var r = BrandRandom("fb:\(w.state.seed):\(tradeID):GL")
        guard r.chance(0.7) else { return [] }
        let a = r.pick(globalNames)
        let origin = r.pick(CountryTraits.globalBrandOrigins)
        return [make(&r, bd: bd, tier: 4, name: a + " " + noun(tradeID, bd), origin: origin, id: "\(tradeID):GL:\(a)", w: w)]
    }

    public static func brands(_ tradeID: String, country cc: String, _ w: World) -> [Brand] {
        localBrands(tradeID, country: cc, w) + globalBrands(tradeID, w)
    }

    public static func brand(_ id: String, _ w: World) -> Brand? {
        let p = id.split(separator: ":").map(String.init)
        guard p.count == 3 else { return nil }
        let list = p[1] == "GL" ? globalBrands(p[0], w) : localBrands(p[0], country: p[1], w)
        return list.first { $0.id == id }
    }

    /// Every brand that is open to the player in a country, plus the ones they have already applied to.
    public static func available(country cc: String, _ w: World) -> [Brand] {
        var out: [Brand] = []
        for id in w.catalog.order where isFranchisable(id) {
            for b in brands(id, country: cc, w) {
                let a = application(w.state, b.id)
                let live = ["pending", "invited", "agreed"].contains(a["st"].string)
                if status(b, w.state, w).ok || live { out.append(b) }
            }
        }
        return out
    }

    // MARK: Facts

    public static func fee(_ b: Brand, country: Country) -> Double {
        Currency(country: country, rates: ExchangeRates()).scaledPrice(b.baseFee)
    }
    static func fee(_ b: Brand, _ w: World, country cc: String) -> Double {
        Currency(country: w.countries.resolve(cc, orHome: w.state.homeCountryCode), rates: w.rates).scaledPrice(b.baseFee)
    }

    /// What a typical unit earns: revenue a week and margin after fees. Original: `fbUnitStats`.
    public static func unitStats(_ b: Brand, _ w: World) -> (revenue: Double, margin: Double) {
        guard let bd = w.catalog[b.tradeID] else { return (0, 0) }
        let rev = bd.normalDemand * bd.ticket * 0.55 * (0.35 + b.strength / 100 * 0.6)
        return (rev, bd.margin + b.strength / 100 * 0.04 - b.royalty - b.marketingFund)
    }

    public static func brandWord(_ v: Double) -> String {
        v >= 85 ? "A household name" : v >= 70 ? "Very well known" : v >= 55 ? "Well regarded" : v >= 40 ? "Known locally" : v >= 25 ? "Still building a name" : "Little known"
    }

    /// Companies of this trade that prove you can run one: 26 weeks open, reputation 52+. Original: `fbExp`.
    public static func experience(_ s: GameState, _ tradeID: String) -> Int {
        s.companies.filter { $0.type == tradeID && $0.status.isLive && s.week - ($0.openedWeek ?? s.week) >= 26 && $0.reputation >= 52 }.count
    }

    public static func lockedUntil(_ s: GameState, _ b: Brand) -> Int? {
        guard let v = s.rest["fbLock"]?[b.id], !v.isNull, s.week < v.int else { return nil }
        return v.int
    }

    public struct Status: Equatable, Sendable { public var ok: Bool; public var why: String }
    /// Can anyone apply to this brand now? Original: `fbStatus`.
    public static func status(_ b: Brand, _ s: GameState, _ w: World) -> Status {
        if let until = lockedUntil(s, b) { return Status(ok: false, why: until - s.week > 5000 ? "They will not do business with you again." : "They will not talk to you again for \(until - s.week) weeks.") }
        if b.openness == "closed" { return Status(ok: false, why: "This brand does not take new franchisees.") }
        if b.openness == "exp" && experience(s, b.tradeID) == 0 {
            return Status(ok: false, why: "They only franchise to operators with a proven record: run a company of this kind for 6 months with reputation 52+.")
        }
        return Status(ok: true, why: "")
    }

    /// Your bargaining power. Original: `fbPower`.
    static func power(_ b: Brand, _ ask: Ask?, _ s: GameState, _ w: World, country cc: String) -> Double {
        let exp = Double(experience(s, b.tradeID))
        var p = 34 + exp * 14 + (s.credit - 50) * 0.2 + (s.cash > fee(b, w, country: cc) * 4 ? 8 : 0)
        if let a = ask, a.building == 2 || a.premises != nil { p += 16 }
        return clamp(p, 0, 100)
    }

    /// Each brand boss has a taste: some want money up front, some a lasting royalty, some a unit that looks right. Original: `fbTaste`.
    static func taste(_ b: Brand) -> (fee: Double, roy: Double, cover: Double) {
        var h = 7
        for u in b.id.utf16 { h = (h * 31 + Int(u)) % 9973 }
        func u(_ k: Int) -> Double { Double((h * (k + 3) * 7919) % 1000) / 1000 }
        return (0.55 + u(1) * 1.1, 0.55 + u(2) * 1.1, 0.8 + u(3) * 0.5)
    }

    static func terms(_ b: Brand, _ ask: Ask, _ w: World, country cc: String) -> Terms {
        Terms(fee: (fee(b, w, country: cc) * (1 - ask.fee)).rounded(), royalty: max(0, ((b.royalty - ask.royalty) * 1000).rounded() / 1000),
              marketing: b.marketingFund, cover: max(max(ask.cover, 0), b.support), rent: ask.rent, vehicles: ask.vehicles, building: ask.building, brandID: b.id, premises: ask.premises)
    }

    /// The talk about the terms. Original: `fbNegotiate`. Each unfinished round counts against your patience.
    public static func negotiate(_ s: inout GameState, brand b: Brand, ask: Ask, data: GameData, country cc: String? = nil) -> Negotiation {
        let w = World(state: s, data: data)
        let code = cc ?? s.homeCountryCode
        let st = status(b, s, w)
        if !st.ok { return Negotiation(kind: .closed, message: st.why, counter: nil, terms: nil) }
        let pow = power(b, ask, s, w, country: code)
        let cover = max(ask.cover, 0)
        let extra = Double(max(0, cover - b.support))
        let who = b.who
        let ta = taste(b)
        let pFee = ask.fee * 100 * 0.55 * ta.fee
        let pRoy = ask.royalty * 100 * 9 * ta.roy
        let pCover = extra * 13 * ta.cover
        let pRent = Double(ask.rent) * 7
        let pVeh = ask.vehicles != 0 ? 10.0 : 0
        let pBld = ask.building != 0 ? 16.0 : 0
        let cost = pFee + pRoy + pCover + pRent + pVeh + pBld
        let t = terms(b, ask, w, country: code)
        let gives = ask.fee < 0 || ask.royalty < 0
        if cost <= 0 && !(ask.fee > 0 || ask.royalty > 0 || extra > 0 || ask.rent != 0 || ask.vehicles != 0 || ask.building != 0) {
            return Negotiation(kind: .accept, message: "\(who) says: \"\(gives ? "That works for us. Thank you." : "Standard terms. We would be glad to have you.")\"", counter: ask, terms: t)
        }
        let slack = pow - b.flex - cost
        if slack >= 0 {
            let line = gives && cost < 0 ? "That suits us well. Let us do it." : b.tier <= 2 ? "You seem serious. I can live with that." : "Head office approved this exception for you."
            return Negotiation(kind: .accept, message: "\(who) agrees: \"\(line)\"", counter: ask, terms: t)
        }
        var irr = s.rest["fbIrr"] ?? .object([:])
        let rounds = irr[b.id].int + 1
        irr[b.id] = .number(Double(rounds))
        s.rest["fbIrr"] = irr
        if slack >= -34 {
            let pos = max(0, pFee) + max(0, pRoy) + pCover + pRent + pVeh + pBld
            let credit = max(0, -pFee) + max(0, -pRoy)
            let f = clamp((pow - b.flex + credit) / max(pos, 0.01), 0.15, 0.95)
            func q(_ v: Double, _ step: Double) -> Double { (v / step).rounded() * step }
            var c = ask
            c.fee = ask.fee > 0 ? q(ask.fee * f, 0.05) : ask.fee
            c.royalty = ask.royalty > 0 ? q(ask.royalty * f, 0.005) : ask.royalty
            c.cover = max(b.support, min(cover, b.support + Int((extra * f).rounded())))
            c.rent = Int((Double(ask.rent) * f).rounded(.down))
            c.vehicles = f > 0.5 ? ask.vehicles : 0
            c.building = f > 0.6 ? ask.building : 0
            let lines = ["I cannot give you all of that, but I can go part of the way.", "Let us find a middle ground. This is what I can do.", "That is a bit much, but I like your plan. How about this?"]
            let likes = gives ? " I do like that you give something back." : ""
            return Negotiation(kind: .counter, message: "\(who) says: \"\(lines[(rounds + b.tier) % 3])\(likes)\"", counter: c, terms: terms(b, c, w, country: code))
        }
        if slack < -60 && rounds >= 4 && s.random.chance(0.2) {
            var lock = s.rest["fbLock"] ?? .object([:])
            lock[b.id] = .number(Double(s.week + 12))
            s.rest["fbLock"] = lock
            if !application(s, b.id).isNull { s.rest["fbApps", default: .object([:])][b.id]["st"] = "refused" }
            return Negotiation(kind: .refuse, message: "\(who) says: \"We keep going in circles. Come back in a few months, when you have more to show.\"", counter: nil, terms: nil)
        }
        let line = slack < -50 ? "That is far more than a new partner gets. Start smaller and we can talk." : "That is more than I can offer right now. Ask for a little less, or give something back."
        return Negotiation(kind: .push, message: "\(who) says: \"\(line)\"", counter: nil, terms: nil)
    }

    // MARK: Applying

    public static func application(_ s: GameState, _ brandID: String) -> JSONValue { s.rest["fbApps"]?[brandID] ?? .null }

    public enum ApplyResult: Equatable, Sendable { case ok, closed(String), already }

    /// Send an application; the brand answers after a week or three. Original: `fbApply`.
    public static func apply(_ s: inout GameState, brand b: Brand, country: String, city: String, data: GameData) -> ApplyResult {
        let w = World(state: s, data: data)
        let st = status(b, s, w)
        if !st.ok { return .closed(st.why) }
        let a = application(s, b.id)
        if ["pending", "invited", "agreed"].contains(a["st"].string) { return .already }
        let delay = Int(clamp((Double(b.tier) * 0.7 + s.random.range(0, 1.2)).rounded(), 1, 3))
        s.rest["fbApps", default: .object([:])][b.id] = .object(["st": "pending", "w0": .number(Double(s.week)), "due": .number(Double(s.week + delay)),
                                                                  "country": .string(country), "city": .string(city)])
        return .ok
    }

    /// The player signs the terms that were offered. Original: `ACT.negsign`.
    public static func sign(_ s: inout GameState, brand b: Brand, terms: Terms) {
        guard !application(s, b.id).isNull else { return }
        s.rest["fbApps", default: .object([:])][b.id]["st"] = "agreed"
        s.rest["fbApps", default: .object([:])][b.id]["terms"] = terms.json
        s.rest["fbApps", default: .object([:])][b.id]["exp"] = .number(Double(s.week + 16))
    }

    public static func agreedTerms(_ s: GameState, _ brandID: String) -> Terms? {
        let a = application(s, brandID)
        guard a["st"].string == "agreed" else { return nil }
        return Terms(json: a["terms"])
    }

    /// Weekly: applications are answered or expire. Original: `fbWeek`.
    static func weekly(_ s: inout GameState, data: GameData) {
        guard let apps = s.rest["fbApps"]?.object, !apps.isEmpty else { return }
        let w = World(state: s, data: data)
        for id in apps.keys.sorted() {
            let a = apps[id]!
            guard let b = brand(id, w) else { continue }
            let st = a["st"].string
            if st == "pending" && s.week >= a["due"].int {
                let p = power(b, nil, s, w, country: a["country"].string.isEmpty ? s.homeCountryCode : a["country"].string)
                if p < b.flex - 28 && s.random.chance(0.55) {
                    s.rest["fbApps", default: .object([:])][id]["st"] = "refused"
                    var lock = s.rest["fbLock"] ?? .object([:]); lock[id] = .number(Double(s.week + 26)); s.rest["fbLock"] = lock
                    s.addMessage(kind: "info", from: b.name, title: "\(b.name) declines your application",
                                 body: "They are not looking for a partner with your background right now. Build a record and try again later.", tone: "bad")
                } else {
                    s.rest["fbApps", default: .object([:])][id]["st"] = "invited"
                    s.rest["fbApps", default: .object([:])][id]["exp"] = .number(Double(s.week + 8))
                    s.addMessage(kind: "info", from: b.name, title: "\(b.name) wants to talk",
                                 body: "\(String(b.who.dropLast())) invites you to discuss terms. The invitation stands for eight weeks.", tone: "good")
                }
            } else if (st == "invited" || st == "agreed") && s.week > a["exp"].int {
                var m = s.rest["fbApps"]?.object ?? [:]
                m[id] = nil
                s.rest["fbApps"] = .object(m)
            }
        }
    }

    // MARK: Starting as a franchisee

    /// What the franchisor pays towards the set-up: part of the fit-out, rent months, half the vehicles. Original: `fbSetupGrant`.
    static func setupGrant(_ s: GameState, companyIndex i: Int, terms t: Terms, data: GameData) -> Double {
        let co = s.companies[i]
        let w = World(state: s, data: data)
        guard let bd = data.catalog[co.type] else { return 0 }
        var eq = 0.0
        for e in bd.equipment where e.standardCount > 0 && e.vehicleModels == nil { eq += e.cost * max(1, (e.standardCount * 0.7).rounded()) }
        let tables = data.catalog.tables
        var fit = 0.0, rentMonth = 0.0
        if let kind = bd.premisesKind, bd.premisesM2 > 0 {
            fit = (tables.fitOut[kind] ?? 0) * bd.premisesM2 * co.size
            if let P = tables.premises[kind], let city = w.city(co) { rentMonth = P.rentPerM2Year * city.rent * bd.premisesM2 * co.size / 12 }
        }
        let share = [0.0, 0.4, 0.7][min(2, max(0, t.cover))]
        var g = (eq + fit) * share
        if t.rent > 0 { g += rentMonth * [0.0, 6, 12][min(2, t.rent)] }
        if t.vehicles != 0 {
            for e in bd.equipment where e.standardCount > 0 { if let m = e.vehicleModels?.first, let v = tables.vehicles[m] { g += v.price * e.standardCount * 0.5 } }
        }
        return w.currency(co).scaledPrice(g)
    }

    /// The supplier standards brands of this trade and tier require (`Resources/franchise_standards.json`): input ids.
    public static func requiredSupplierInputs(tradeID: String, tier: Int) -> [String] {
        guard let url = Bundle.module.url(forResource: "franchise_standards", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return [] }
        return j["supplierStandards"].array.filter { $0["standard"].string == "approved" && $0["trades"].array.contains { $0.string == tradeID } && tier >= $0["minTier"].int }.map { $0["input"].string }
    }

    /// Write the brand's required suppliers into the franchise record (`supStd`, only when the brand requires any) and put the store on them.
    /// The approved supplier is picked the same way every time from the suppliers that serve the store, by the brand.
    static func applySupplierStandards(_ s: inout GameState, companyIndex i: Int, brand b: Brand, data: GameData) {
        for input in requiredSupplierInputs(tradeID: b.tradeID, tier: b.tier) where input == "goods" {
            let list = Suppliers.candidates(s, company: s.companies[i], scope: "goods", data: data).sorted { $0.id < $1.id }
            guard !list.isEmpty else { continue }
            var h = HashedRandom("\(s.seed):supstd:\(b.id):\(input)")
            let v = list[min(list.count - 1, Int(h.next() * Double(list.count)))]
            var f = s.companies[i].value("franchise")
            var std = f["supStd"].isNull ? JSONValue.object([:]) : f["supStd"]
            std[input] = SupplyDeals.encode(.goodsVendor(v.id))
            f["supStd"] = std
            s.companies[i].set("franchise", f)
            Suppliers.chooseGoodsVendor(&s, companyID: s.companies[i].id, vendorID: v.id)
        }
    }

    /// Put the brand's terms on a company that was just started: the franchise record, reputation and awareness of the brand,
    /// the franchisor's set-up support. Original: `applyBrand`.
    public static func applyToCompany(_ s: inout GameState, companyIndex i: Int, brand b: Brand, terms t: Terms, data: GameData) {
        let id = s.companies[i].id
        s.companies[i].set("franchise", .object([
            "fran": 1, "brandId": .string(b.id), "brandName": .string(b.name), "fee": .number(t.fee), "roy": .number(t.royalty), "mkt": .number(t.marketing),
            "brand": .number(b.strength), "std": .number(b.standard), "cover": .number(Double(t.cover)), "bld": .number(Double(t.building)),
            "term": .number(Double(b.termYears)), "w0": .number(Double(s.week)),
        ]))
        applySupplierStandards(&s, companyIndex: i, brand: b, data: data)
        if let p = t.premises { s.companies[i].set("landlord", .object(["co": .number(Double(p.companyID)), "pid": .number(Double(p.propertyID))])) }
        s.companies[i].reputation = max(s.companies[i].reputation, 38 + Double(b.tier) * 6)
        s.companies[i].awareness = max(s.companies[i].awareness, 25 + b.strength * 0.55)
        var docs = s.companies[i].value("docs")
        docs["fran_op"] = .object(["st": "ok", "done": .number(Double(s.week)), "ok": .number(Double(s.week))])
        s.companies[i].set("docs", docs)
        let g = setupGrant(s, companyIndex: i, terms: t, data: data)
        if g > 0 {
            Ledger.moveRaw(&s, .company(id), g)
            s.companies[i].injectedCapital += g
            s.companies[i].addTransaction(week: s.week, amount: g, label: "Franchisor setup support: \(b.name)")
            var f = s.companies[i].value("flags"); f["fbGrant"] = .number(g); s.companies[i].set("flags", f)
        }
    }
}
