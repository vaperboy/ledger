import Foundation
import GameCore
import Countries
import Finance

/// The equipment market: brands and models in three classes, the used market, leasing, subscriptions and licences, and buying
/// one item at a time. Originals: `eqCat`, `vehCat`, `makerName` (engine/suppliers), and the buying steps of
/// features/company/realistic_buying.js. The names and numbers of the brands are data: Resources/equipment_brands.json.
///
/// It extends the existing purchase path: `CompanySetup.addEquipment` / `addVehicle` record what was bought,
/// `EquipmentUnits` keeps one record per unit, `Capacity` already reads `perf` and `cond` from the equipment record.
public enum EquipmentMarket {
    // MARK: Data

    static let book: JSONValue = {
        guard let url = Bundle.module.url(forResource: "equipment_brands", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return json
    }()

    public static var classNames: [String] { book["classNames"].array.map { $0.string } }

    /// One brand and model on offer, in one class. Original: an entry of `eqCat`.
    public struct Offer: Identifiable, Equatable, Sendable {
        public var id: Int { index }
        public var index: Int
        public var vendorID: String
        public var seller: String
        public var brand: String
        public var model: String
        public var className: String
        public var cls: Int
        /// Price factor against the standard price
        public var priceFactor: Double
        public var rating: Double
        public var reviews: Int
        /// Output: multiplies the capacity of the equipment (1 = standard)
        public var performance: Double
        /// Breakdown tendency (1 = standard, lower is better)
        public var reliability: Double
        public var comment: String
        public var name: String { brand + " " + model }
    }

    /// One vehicle make on offer for a vehicle model. Original: an entry of `vehCat`.
    public struct VehicleOffer: Identifiable, Equatable, Sendable {
        public var id: String { modelID + ":" + String(index) }
        public var modelID: String
        public var index: Int
        public var brand: String
        public var model: String
        public var modelName: String
        public var priceFactor: Double
        public var rating: Double
        public var reviews: Int
        public var reliability: Double
        public var name: String { brand + " " + model }
    }

    /// A second-hand item for sale this month. `trueCondition` is what it really is; `visibleCondition` what the seller shows.
    public struct UsedOffer: Identifiable, Equatable, Sendable {
        public var id: String { key + ":" + String(slot) }
        public var key: String
        public var slot: Int
        /// Index of the brand in the catalogue (equipment), or of the make (vehicle)
        public var brandIndex: Int
        public var modelID: String
        public var name: String
        public var cls: Int
        public var age: Int
        public var year: Int
        public var trueCondition: Double
        public var visibleCondition: Double
        public var knownToLast: Bool
        public var price: Double
        public var seller: String
        public var says: String
        public var reliability: Double
        public var rating: Double
        public var performance: Double
        public var kilometres: Int
        public var risk: String
        public var fuel: String
    }

    public enum Payment: String, Sendable { case cash, finance, lease }
    public enum Result: Equatable, Sendable { case ok, notEnoughCash, notPossible }

    /// What one bought unit carries into the books (name, class, reliability).
    public struct Brand: Equatable, Sendable {
        public var name: String
        public var cls: Int
        public var reliability: Double
        public var performance: Double
        public var rating: Double
    }

    // MARK: Words

    static func wear(_ c: Double) -> String {
        for row in book["wear"].array where c >= row[0].double { return row[1].string }
        return "Heavily worn"
    }
    public static func wearWord(_ c: Double) -> String { wear(c) }

    static func comment(_ rt: Double) -> String {
        rt >= 4.5 ? "Built to last" : rt >= 4.1 ? "Reliable, good value" : rt >= 3.7 ? "Solid choice" : rt >= 3.3 ? "Does the job" : rt >= 2.9 ? "Mixed reviews" : "Breaks often"
    }

    // MARK: Maker names

    static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Product category of an equipment name, for the maker names. Original: `eqMakerCat`.
    static func makerCategory(_ name: String) -> String {
        let n = name.lowercased()
        for r in book["makerRules"].array where matches(r[0].string, n) { return r[1].string }
        return "general"
    }
    static func vehicleMakerCategory(_ model: String) -> String {
        for r in book["vehicleMakerRules"].array where matches(r[0].string, model) { return r[1].string }
        return "general"
    }

    /// One maker name: about 55% from the buyer's own country, the rest from countries known for the product. Original: `makerName`.
    static func makerName(_ cat: String, _ cc: String, _ r: inout HashedRandom, _ used: inout Set<String>, _ countries: CountryBook) -> String {
        let M = book["makers"][cat].isNull ? book["makers"]["general"] : book["makers"][cat]
        func pick<T>(_ a: [T]) -> T { a[min(a.count - 1, Int(r.next() * Double(a.count)))] }
        var nm = "", guardN = 0
        repeat {
            let home = r.next() < 0.55
            let origins = M["origins"].array.map { $0.string }
            let oc = home ? cc : pick(origins)
            let C = countries.resolve(oc, orHome: cc)
            let roll = r.next()
            let lasts = C.lastNames.isEmpty ? ["Berg"] : C.lastNames
            let starts = C.companyNameStarts.isEmpty ? ["Nova"] : C.companyNameStarts
            let sur = pick(lasts)
            let stem = pick(M["stems"].array.map { $0.string })
            let suf = pick(M["suffixes"].array.map { $0.string })
            let a = pick(starts)
            if roll < 0.3 { nm = sur + " " + suf }
            else if roll < 0.55 { nm = a + " " + suf }
            else if roll < 0.8 { nm = sur + " " + stem }
            else { let sur2 = pick(lasts); nm = sur + " & " + sur2 + " " + (suf.split(separator: " ").first.map(String.init) ?? suf) }
            nm = nm.split(whereSeparator: { $0 == " " }).joined(separator: " ")
            guardN += 1
        } while used.contains(nm) && guardN <= 30
        used.insert(nm)
        return nm
    }

    // MARK: Suppliers

    struct Vendor { var id: String; var name: String; var quality: Double }

    /// The pool of supplier companies of a country, shared by all kinds of business. Original: `vpoolAll`.
    static func vendorPool(seed: Int, countryCode cc: String, countries: CountryBook, nouns: JSONValue) -> [(vendor: Vendor, families: [String])] {
        var r = HashedRandom("\(seed):\(cc):vpa")
        let C = countries.resolve(cc, orHome: cc)
        let fams = ["svc", "venue", "retail", "prod", "logi", "project", "rent", "fin", "energy", "club"]
        let generic = ["Group", "Trading", "Supply Group", "Holding", "Partners"]
        let starts = C.companyNameStarts.isEmpty ? ["Nova"] : C.companyNameStarts
        func pick<T>(_ a: [T]) -> T { a[min(a.count - 1, Int(r.next() * Double(a.count)))] }
        var out: [(Vendor, [String])] = []
        var used = Set<String>()
        var guardN = 0
        while out.count < 60 && guardN < 600 {
            guardN += 1
            let i = out.count
            var f = [fams[i % fams.count]]
            if r.next() < 0.4 { let x = pick(fams); if !f.contains(x) { f.append(x) } }
            if r.next() < 0.15 { let x = pick(fams); if !f.contains(x) { f.append(x) } }
            let list = f.count > 1 ? generic : (nouns[f[0]].array.isEmpty ? generic : nouns[f[0]].array.map { $0.string })
            let name = pick(starts) + " " + pick(list)
            if used.contains(name) { continue }
            used.insert(name)
            _ = pick(C.firstNames.isEmpty ? ["A"] : C.firstNames); _ = pick(C.lastNames.isEmpty ? ["B"] : C.lastNames)
            let q = jsRound((r.next() - 0.5) * 70) / 100
            out.append((Vendor(id: "V-\(cc)-\(i)", name: name, quality: q), f))
        }
        return out
    }

    /// `n` suppliers for this kind of equipment in a country. Original: `vendorsFor`.
    static func vendors(for key: String, count n: Int, family: String, seed: Int, countryCode cc: String, countries: CountryBook, nouns: JSONValue) -> [Vendor] {
        let all = vendorPool(seed: seed, countryCode: cc, countries: countries, nouns: nouns).filter { $0.families.contains(family) }.map { $0.vendor }
        var r = HashedRandom("\(seed):vf:\(cc):\(key)")
        return all.enumerated().map { (r.next(), $0.offset) }.sorted { $0.0 < $1.0 }.prefix(n).map { all[$0.1] }
    }

    /// Number of brands the buyer sees: more in a crowded market. Original: `brandN`.
    public static func brandCount(_ co: Company, state s: GameState) -> Int {
        let n = s.rest["mk"]?[co.type + "|" + co.cityID]["n"].double ?? 0
        return 3 + (n >= 6 ? 1 : 0) + (n >= 12 ? 1 : 0)
    }

    // MARK: Catalogues

    /// Brands and models for one piece of equipment: each brand in three classes. Original: `eqCat`.
    public static func offers(for e: EquipmentSpec, tradeID: String, family: String, brands nb: Int, countryCode cc: String, seed: Int, countries: CountryBook, tables: TradeTables) -> [Offer] {
        var r = HashedRandom("\(seed):\(cc):\(tradeID):\(e.id):\(nb)")
        let vs = vendors(for: tradeID + ":" + e.id, count: nb, family: family, seed: seed, countryCode: cc, countries: countries, nouns: tables.raw["FAM_NOUN"])
        let base = book["classPrice"].array.map { $0.double }
        let names = classNames
        let words = book["modelWords"].array.map { $0.string }, letters = book["modelLetters"].array.map { $0.string }
        let mcat = makerCategory(e.name)
        var used = Set<String>()
        var list: [Offer] = []
        for (b, v) in vs.enumerated() {
            let bf = 0.94 + r.next() * 0.12
            for c in 0..<3 {
                var rating = 3.0 + Double(c) * 0.65 + v.quality + (r.next() - 0.5) * 0.5
                rating = jsRound(clamp(rating, 2.5, 4.9) * 10) / 10
                let model = words[Int(r.next() * Double(words.count))] + " " + letters[Int(r.next() * 5)] + String(c + 1) + "0" + String(Int(r.next() * 9))
                let brand = makerName(mcat, cc, &r, &used, countries)
                let reviews = Int(jsRound(30 + r.next() * r.next() * 1800))
                list.append(Offer(index: b * 3 + c, vendorID: v.id, seller: v.name, brand: brand, model: model, className: names[c], cls: c,
                                  priceFactor: jsRound(base[c] * bf * 100) / 100, rating: rating, reviews: reviews,
                                  performance: jsRound((0.88 + 0.0957 * (rating - 2.6)) * 1000) / 1000,
                                  reliability: jsRound((1.4 - 0.3 * (rating - 2.6)) * 100) / 100, comment: comment(rating)))
            }
        }
        return list
    }

    /// Makes for a vehicle model: two of them. Original: `vehCat`.
    public static func vehicleOffers(model m: String, modelName: String, countryCode cc: String, seed: Int, countries: CountryBook) -> [VehicleOffer] {
        var r = HashedRandom("\(seed):veh:\(cc):\(m)")
        var used = Set<String>()
        let words = book["vehicleModelWords"].array.map { $0.string }
        var list: [VehicleOffer] = []
        for i in 0..<2 {
            let brand = makerName(vehicleMakerCategory(m), cc, &r, &used, countries)
            let rating = jsRound(clamp(3.6 + (r.next() - 0.35) * 1.5 + Double(i) * 0.1, 2.7, 4.9) * 10) / 10
            let model = words[Int(r.next() * 5)] + " " + String(Int(r.next() * 8) + 2) + "00"
            let f = jsRound((0.92 + r.next() * 0.2 + (rating - 3.6) * 0.08) * 100) / 100
            let reviews = Int(jsRound(40 + r.next() * r.next() * 1500))
            list.append(VehicleOffer(modelID: m, index: i, brand: brand, model: model, modelName: modelName, priceFactor: f, rating: rating, reviews: reviews,
                                     reliability: jsRound((1.4 - 0.3 * (rating - 2.6)) * 100) / 100))
        }
        return list
    }

    // MARK: Context for a company

    struct Ctx {
        var bd: Trade
        var co: Company
        var w: World
        var seed: Int
        var countries: CountryBook
        var tables: TradeTables
        var brands: Int
    }

    static func ctx(_ s: GameState, _ co: Company, data: GameData) -> Ctx? {
        guard let bd = data.catalog[co.type] else { return nil }
        return Ctx(bd: bd, co: co, w: World(state: s, data: data), seed: s.seed, countries: data.countries, tables: data.catalog.tables, brands: brandCount(co, state: s))
    }

    public static func offers(_ s: GameState, companyID: Int, equipmentID: String, data: GameData) -> [Offer] {
        guard let co = s.company(companyID), let c = ctx(s, co, data: data), let e = c.bd.equipment.first(where: { $0.id == equipmentID }) else { return [] }
        return offers(for: e, tradeID: c.bd.id, family: c.bd.family, brands: c.brands, countryCode: co.countryCode, seed: s.seed, countries: c.countries, tables: c.tables)
    }

    public static func vehicleOffers(_ s: GameState, companyID: Int, equipmentID: String, data: GameData) -> [VehicleOffer] {
        guard let co = s.company(companyID), let c = ctx(s, co, data: data), let e = c.bd.equipment.first(where: { $0.id == equipmentID }) else { return [] }
        return (e.vehicleModels ?? []).flatMap { m in
            c.tables.vehicles[m].map { vehicleOffers(model: m, modelName: $0.name, countryCode: co.countryCode, seed: s.seed, countries: c.countries) } ?? []
        }
    }

    // MARK: Prices

    /// Price of one item in a brand (factor 1 is the standard price). Original: `eqPrice`.
    public static func price(_ e: EquipmentSpec, company co: Company, _ w: World, factor f: Double = 1) -> Double {
        let raw = (e.cost * w.inflationIndex * f * w.country(co).costIndex).rounded()
        let fx = w.rates.rate(w.country(co))
        return Currency.nicePrice(raw / fx) * fx
    }

    public static func vehiclePrice(_ v: TradeTables.VehicleModel, factor f: Double, _ w: World) -> Double {
        roundTo(v.price * w.inflationIndex * f, step: 1000)
    }

    public static func leaseMonthly(price: Double) -> Double { price * 0.0235 }
    public static func vehicleLeaseMonthly(price: Double) -> Double { jsRound(price * 0.0215) }

    // MARK: What kind of thing is it

    public enum SoftwareMode: String, Sendable { case subscription, once, upfront }

    public static func kind(_ e: EquipmentSpec, tradeID: String, tables: TradeTables) -> String {
        e.vehicleModels != nil ? "veh" : EquipmentUnits.kind(tradeID: tradeID, equipmentID: e.id, tables: tables)
    }

    public static func kindName(_ k: String) -> String {
        ["veh": "Vehicle", "soft": "Software", "svc": "Service", "it": "IT equipment", "pos": "Payment terminal", "tool": "Tools", "furn": "Furniture and fit-out", "mach": "Machine"][k] ?? "Machine"
    }

    /// How software is sold: a subscription, a one-time licence, or a licence with yearly updates. Original: `softMode`.
    public static func softwareMode(_ e: EquipmentSpec, tradeID: String, company co: Company, _ w: World) -> SoftwareMode {
        if let o = book["subscriptionOverride"][tradeID + ":" + e.id].isNull ? nil : book["subscriptionOverride"][tradeID + ":" + e.id].bool { return o ? .subscription : .upfront }
        if matches(book["subscriptionPattern"].string, e.name.lowercased()) { return .subscription }
        return price(e, company: co, w) < w.currency(co).scaledPrice(20000) ? .once : .upfront
    }

    public static func canLease(_ e: EquipmentSpec, tradeID: String, unitPrice: Double, company co: Company, _ w: World, tables: TradeTables) -> Bool {
        if e.vehicleModels != nil { return true }
        return kind(e, tradeID: tradeID, tables: tables) == "mach" && unitPrice >= w.currency(co).scaledPrice(100000)
    }

    public static func canFinance(_ e: EquipmentSpec, tradeID: String, total: Double, company co: Company, _ w: World, tables: TradeTables) -> Bool {
        e.vehicleModels != nil || (kind(e, tradeID: tradeID, tables: tables) != "soft" && total >= w.currency(co).scaledPrice(30000))
    }

    public static func canBuyUsed(_ e: EquipmentSpec, tradeID: String, tables: TradeTables) -> Bool {
        let k = kind(e, tradeID: tradeID, tables: tables)
        if e.vehicleModels != nil { return true }
        if k == "soft" || k == "svc" { return false }
        return e.flags.contains("u") || (e.cost < 5_000_000 && e.flags.contains("c") && e.cost > 3000) || ["tool", "it", "furn"].contains(k)
    }

    // MARK: Subscriptions

    public struct Plan: Equatable, Sendable { public var index: Int; public var name: String; public var maxUsers: Int; public var monthlyFee: Double; public var performance: Double; public var recommended: Bool }

    public static func users(_ co: Company) -> Int { co.staff.count + 1 }

    public static func plans(_ e: EquipmentSpec, company co: Company, _ w: World, factor f: Double) -> [Plan] {
        let rec = users(co) <= 3 ? 0 : users(co) <= 15 ? 1 : 2
        let unit = price(e, company: co, w, factor: f)
        return book["plans"].array.enumerated().map { (i, p) in
            let fee = max(w.currency(co).scaledPrice(90), (unit / max(1, e.lifeYears) / 12 * p["fee"].double / 10).rounded() * 10)
            return Plan(index: i, name: p["name"].string, maxUsers: p["users"].int, monthlyFee: fee, performance: p["perf"].double, recommended: i == rec)
        }
    }

    @discardableResult
    public static func subscribe(_ s: inout GameState, companyID: Int, equipmentID: String, plan: Int, offer: Offer?, data: GameData) -> Result {
        guard let i = s.companyIndex(companyID), let c = ctx(s, s.companies[i], data: data), let e = c.bd.equipment.first(where: { $0.id == equipmentID }) else { return .notPossible }
        let all = offers(for: e, tradeID: c.bd.id, family: c.bd.family, brands: c.brands, countryCode: c.co.countryCode, seed: s.seed, countries: c.countries, tables: c.tables)
        guard let o = offer ?? all.first(where: { $0.cls == 1 }) ?? all.first, plan >= 0, plan < 3 else { return .notPossible }
        let p = plans(e, company: c.co, c.w, factor: o.priceFactor)[plan]
        if c.co.cash < p.monthlyFee { return .notEnoughCash }
        Payments.companyPays(&s, companyID: companyID, amount: p.monthlyFee, category: "oth", label: "Subscription: \(o.brand) \(p.name)")
        var eq = s.companies[i].value("eq")
        let old = eq[e.id]
        let had = !old.isNull && old["sub"].isNull
        eq[e.id] = .object(["n": 1, "cond": 1, "bv": had ? old["bv"] : 0, "cost": had ? old["cost"] : 0, "used": 0, "age": 0, "life": .number(e.lifeYears),
                            "sub": .object(["tier": .number(Double(plan)), "fee": .number(p.monthlyFee), "nm": .string(o.name), "w0": .number(Double(s.week)), "c": .number(Double(o.index))]),
                            "perf": .number(p.performance), "rel": 1, "mods": .array([.object(["nm": .string(o.name), "n": 1, "rt": .number(o.rating)])])])
        s.companies[i].set("eq", eq)
        var units = s.companies[i].value("units"); units = EquipmentUnits.removing(units, e.id); s.companies[i].set("units", units)
        if old.isNull { SpecialFamilies.afterBuy(&s, companyIndex: i, c.bd, equipmentID: e.id, quantity: 1) }
        return .ok
    }

    public static func cancelSubscription(_ s: inout GameState, companyID: Int, equipmentID: String) {
        guard let i = s.companyIndex(companyID) else { return }
        var eq = s.companies[i].value("eq")
        guard !eq[equipmentID]["sub"].isNull else { return }
        eq = .object(eq.object.filter { $0.key != equipmentID })
        s.companies[i].set("eq", eq)
    }

    // MARK: The used market

    static func monthIdx(_ s: GameState) -> Int { GameCalendar.monthIndex(week: s.week) }

    static func taken(_ co: Company, key: String) -> [Int] { co.value("uTaken")[key].array.map { $0.int } }

    static func usedTruth(_ r: inout HashedRandom, age: Int) -> (tc: Double, vis: Double, dressed: Bool) {
        let tc = clamp(0.95 - Double(age) * 0.07 + (r.next() - 0.6) * 0.2, 0.18, 0.95)
        let dressed = r.next() < 0.25
        let vis = dressed ? min(0.95, tc + 0.15 + r.next() * 0.15) : clamp(tc + (r.next() - 0.5) * 0.08, 0.1, 0.97)
        return (tc, vis, dressed)
    }

    /// Second-hand listings of a piece of equipment this month: each one different, and the seller does not always tell the truth.
    /// Original: `usedEqList`.
    public static func usedEquipment(_ s: GameState, companyID: Int, equipmentID: String, data: GameData) -> [UsedOffer] {
        guard let co = s.company(companyID), let c = ctx(s, co, data: data), let e = c.bd.equipment.first(where: { $0.id == equipmentID }), e.vehicleModels == nil else { return [] }
        let key = "\(s.seed):ul:\(co.id):\(e.id):\(monthIdx(s))"
        var r = HashedRandom(key)
        let cat = offers(for: e, tradeID: c.bd.id, family: c.bd.family, brands: c.brands, countryCode: co.countryCode, seed: s.seed, countries: c.countries, tables: c.tables)
        let sellers = book["sellers"].array.map { $0.string }, dressedSays = book["usedSaysDressed"].array.map { $0.string }
        let n = 3 + Int(r.next() * 3)
        var out: [UsedOffer] = []
        for i in 0..<n {
            let o = cat[Int(r.next() * Double(cat.count))]
            let age = 1 + Int(r.next() * Double(min(8, Int(e.lifeYears) + 2)))
            let t = usedTruth(&r, age: age)
            let kr = age >= 4 && r.next() < 0.25
            let p = max(100, roundTo(price(e, company: co, c.w, factor: o.priceFactor) * 0.78 * pow(0.86, Double(age)) * (0.7 + 0.45 * t.vis), step: 100))
            let seller = sellers[Int(r.next() * Double(sellers.count))]
            let says = t.dressed ? dressedSays[Int(r.next() * Double(dressedSays.count))] : t.vis > 0.8 ? "Well kept, light use" : t.vis > 0.6 ? "Normal signs of use" : "Used hard, but works"
            out.append(UsedOffer(key: key, slot: i, brandIndex: o.index, modelID: "", name: o.name, cls: o.cls, age: age, year: GameCalendar.year(week: s.week) - age,
                                 trueCondition: t.tc, visibleCondition: t.vis, knownToLast: kr, price: p, seller: seller, says: says,
                                 reliability: o.reliability * (kr ? 0.65 : 1 + Double(age) * 0.04), rating: o.rating, performance: o.performance, kilometres: 0, risk: "", fuel: ""))
        }
        let gone = taken(co, key: key)
        return out.filter { !gone.contains($0.slot) }
    }

    /// Second-hand vehicles this month. Original: `usedVehList`.
    public static func usedVehicles(_ s: GameState, companyID: Int, equipmentID: String, data: GameData) -> [UsedOffer] {
        guard let co = s.company(companyID), let c = ctx(s, co, data: data), let e = c.bd.equipment.first(where: { $0.id == equipmentID }), let models = e.vehicleModels else { return [] }
        let key = "\(s.seed):uv:\(co.id):\(e.id):\(monthIdx(s))"
        var r = HashedRandom(key)
        let sellers = book["sellers"].array.map { $0.string }, says0 = book["usedSaysDressedVehicle"].array.map { $0.string }
        let n = 4 + Int(r.next() * 3)
        var out: [UsedOffer] = []
        for i in 0..<n {
            let m = models[Int(r.next() * Double(models.count))]
            guard let vm = c.tables.vehicles[m] else { continue }
            let vc = vehicleOffers(model: m, modelName: vm.name, countryCode: co.countryCode, seed: s.seed, countries: c.countries)
            let o = vc[Int(r.next() * Double(vc.count))]
            let cl = c.tables.raw["VEH_CLASS"][m].string
            let age = 1 + Int(r.next() * (["plant", "ship", "plane"].contains(cl) ? 14 : 11))
            let kmY: Double = c.bd.id == "taxi" ? 60000 : (cl == "truck" || cl == "bus") ? 90000 : (cl == "bike" || cl == "scooter") ? 4000 : 18000
            let km = Int(roundTo(Double(age) * kmY * (0.6 + r.next() * 0.8), step: 1000))
            let tc = clamp(0.97 - Double(age) * 0.045 - Double(km) / 700000 + (r.next() - 0.6) * 0.18, 0.15, 0.96)
            let dressed = r.next() < 0.25
            let vis = dressed ? min(0.95, tc + 0.15 + r.next() * 0.15) : clamp(tc + (r.next() - 0.5) * 0.08, 0.1, 0.97)
            let kr = age >= 5 && r.next() < 0.28
            let base = roundTo(vm.price * c.w.inflationIndex * o.priceFactor, step: 1000)
            let usage = clamp(1 - (Double(km) / max(1, Double(age) * kmY) - 1) * 0.15, 0.8, 1.15)
            let p = max(1000, roundTo(base * 0.8 * pow(0.87, Double(age - 1)) * usage * (0.8 + 0.3 * vis), step: 1000))
            let risk = (1 - vis) * 1.4 + Double(age) * 0.05 + Double(km) / 500000 - (kr ? 0.3 : 0)
            let seller = sellers[Int(r.next() * Double(sellers.count))]
            let says = dressed ? says0[Int(r.next() * Double(says0.count))] : vis > 0.8 ? "Good condition" : vis > 0.6 ? "Some scratches, drives well" : "Worn, priced to sell"
            out.append(UsedOffer(key: key, slot: i, brandIndex: o.index, modelID: m, name: o.name, cls: 1, age: age, year: GameCalendar.year(week: s.week) - age,
                                 trueCondition: tc, visibleCondition: vis, knownToLast: kr, price: p, seller: seller, says: says,
                                 reliability: o.reliability * (kr ? 0.65 : 1 + Double(age) * 0.05), rating: o.rating, performance: 1, kilometres: km,
                                 risk: risk < 0.45 ? "Low" : risk < 0.8 ? "Medium" : "High", fuel: age >= 8 ? "Higher" : age >= 4 ? "Normal" : "Low"))
        }
        let gone = taken(co, key: key)
        return out.filter { !gone.contains($0.slot) }
    }

    static func markTaken(_ s: inout GameState, _ i: Int, _ o: UsedOffer) {
        var t = s.companies[i].value("uTaken")
        // listings of earlier months are forgotten
        let month = String(monthIdx(s))
        t = .object(t.object.filter { $0.key.split(separator: ":").last.map(String.init) == month })
        var list = t[o.key].array
        list.append(.number(Double(o.slot)))
        t[o.key] = .array(list)
        s.companies[i].set("uTaken", t)
    }

    // MARK: Buying

    @discardableResult
    static func openLoan(_ s: inout GameState, companyID: Int, name: String, amount: Double, months: Int, extraMargin: Double) -> Int {
        guard let i = s.companyIndex(companyID) else { return 0 }
        var loan = Loan(raw: [:])
        loan.id = s.makeID()
        loan.kind = "biz"
        loan.name = name
        loan.balance = amount
        loan.originalAmount = amount
        loan.margin = Banking.creditMargin(s.credit) + extraMargin
        loan.termMonths = months
        loan.companyID = companyID
        loan.startWeek = s.week
        loan.isGuaranteed = s.companies[i].form != .limited
        loan.monthlyPayment = Loans.annuity(principal: amount, yearlyRate: s.economy.policyRate + loan.margin, months: Double(months))
        s.loans.append(loan)
        return loan.id
    }

    /// Buy new equipment of a chosen brand: for cash, on a loan (20% down, four years) or on a lease (3 years, service included).
    /// Software and services are one licence; a licence already owned is replaced by the new version. Original: `buyEq` + the steps.
    @discardableResult
    public static func buyNew(_ s: inout GameState, companyID: Int, equipmentID: String, offer: Offer, quantity: Int, payment: Payment, data: GameData) -> Result {
        guard let i = s.companyIndex(companyID), let c = ctx(s, s.companies[i], data: data), let e = c.bd.equipment.first(where: { $0.id == equipmentID }), e.vehicleModels == nil else { return .notPossible }
        let k = kind(e, tradeID: c.bd.id, tables: c.tables)
        let one = k == "soft" || k == "svc"
        let mode = one ? softwareMode(e, tradeID: c.bd.id, company: c.co, c.w) : nil
        if mode == .subscription { return subscribe(&s, companyID: companyID, equipmentID: equipmentID, plan: 1, offer: offer, data: data) }
        let q = one ? 1 : max(1, quantity)
        let unit = price(e, company: c.co, c.w, factor: offer.priceFactor)
        let total = unit * Double(q)
        var pay = payment
        if one || (pay == .lease && !canLease(e, tradeID: c.bd.id, unitPrice: unit, company: c.co, c.w, tables: c.tables)) { pay = .cash }
        if pay == .finance && !canFinance(e, tradeID: c.bd.id, total: total, company: c.co, c.w, tables: c.tables) { pay = .cash }
        let brand = Brand(name: offer.name, cls: offer.cls, reliability: offer.reliability, performance: offer.performance, rating: offer.rating)
        if pay == .lease {
            var lease = s.companies[i].value("lease")
            lease[e.id] = .number(lease[e.id].double + Double(q))
            s.companies[i].set("lease", lease)
            var eqL = s.companies[i].value("eqL")
            eqL[e.id] = .number(eqL[e.id].double + leaseMonthly(price: total))
            s.companies[i].set("eqL", eqL)
            return .ok
        }
        // A newer version of a licence already owned
        if one, case let eq = s.companies[i].value("eq"), !eq[e.id].isNull, eq[e.id]["sub"].isNull {
            if c.co.cash < total { return .notEnoughCash }
            Payments.companyPays(&s, companyID: companyID, amount: total, category: nil, label: "New version: \(offer.name)")
            var rec = s.companies[i].value("eq")
            rec[e.id]["ver"] = .number(Double(s.week)); rec[e.id]["perf"] = .number(offer.performance)
            rec[e.id]["cost"] = .number(rec[e.id]["cost"].double + total); rec[e.id]["bv"] = .number(rec[e.id]["bv"].double + total)
            rec[e.id]["mods"] = .array([.object(["nm": .string(offer.name), "n": 1, "rt": .number(offer.rating)])])
            s.companies[i].set("eq", rec)
            return .ok
        }
        if pay == .finance {
            let down = total * 0.2
            if c.co.cash < down { return .notEnoughCash }
            Payments.companyPays(&s, companyID: companyID, amount: down, category: nil, label: "Down payment: \(e.name)")
            openLoan(&s, companyID: companyID, name: "Equipment loan: \(e.name)", amount: total - down, months: 48, extraMargin: 0.02)
        } else {
            if c.co.cash < total { return .notEnoughCash }
            Payments.companyPays(&s, companyID: companyID, amount: total, category: nil, label: "\(e.name) x\(q)")
        }
        CompanySetup.addEquipment(&s, companyIndex: i, e, tradeID: c.bd.id, quantity: Double(q), totalPrice: total, brand: brand, used: nil, data: data)
        if one {
            var eq = s.companies[i].value("eq")
            eq[e.id]["soft"] = .string(k == "svc" ? "svc" : (mode == .upfront ? "upfront" : "once"))
            eq[e.id]["ver"] = .number(Double(s.week))
            eq[e.id]["upd"] = .number(mode == .upfront ? jsRound(unit * 0.18) : 0)
            eq[e.id]["cond"] = 1
            s.companies[i].set("eq", eq)
        }
        return .ok
    }

    /// Buy a used item from this month's listings. Original: `buyUsedEq`.
    @discardableResult
    public static func buyUsed(_ s: inout GameState, companyID: Int, equipmentID: String, listing L: UsedOffer, payment: Payment, data: GameData) -> Result {
        guard let i = s.companyIndex(companyID), let c = ctx(s, s.companies[i], data: data), let e = c.bd.equipment.first(where: { $0.id == equipmentID }) else { return .notPossible }
        if e.vehicleModels != nil { return buyUsedVehicle(&s, companyIndex: i, e, L, payment: payment, data: data) }
        if payment == .finance {
            if c.co.cash < L.price * 0.2 { return .notEnoughCash }
            Payments.companyPays(&s, companyID: companyID, amount: L.price * 0.2, category: nil, label: "Down payment: used \(L.name)")
            openLoan(&s, companyID: companyID, name: "Equipment loan: \(L.name)", amount: L.price * 0.8, months: 36, extraMargin: 0.025)
        } else {
            if c.co.cash < L.price { return .notEnoughCash }
            Payments.companyPays(&s, companyID: companyID, amount: L.price, category: nil, label: "Used \(L.name) (\(L.year))")
        }
        let brand = Brand(name: L.name, cls: L.cls, reliability: L.reliability, performance: L.performance, rating: L.rating)
        CompanySetup.addEquipment(&s, companyIndex: i, e, tradeID: c.bd.id, quantity: 1, totalPrice: L.price, brand: brand, used: L, data: data)
        markTaken(&s, i, L)
        return .ok
    }

    static func buyUsedVehicle(_ s: inout GameState, companyIndex i: Int, _ e: EquipmentSpec, _ L: UsedOffer, payment: Payment, data: GameData) -> Result {
        let id = s.companies[i].id
        var loan = 0
        if payment == .finance {
            if s.companies[i].cash < L.price * 0.2 { return .notEnoughCash }
            Payments.companyPays(&s, companyID: id, amount: L.price * 0.2, category: nil, label: "Down payment: used \(L.name)")
            loan = openLoan(&s, companyID: id, name: "Vehicle loan: \(L.name)", amount: L.price * 0.8, months: 48, extraMargin: 0.02)
        } else {
            if s.companies[i].cash < L.price { return .notEnoughCash }
            Payments.companyPays(&s, companyID: id, amount: L.price, category: nil, label: "Used \(L.name) (\(L.year))")
        }
        var list = s.companies[i].value("veh").array
        list.append(.object(["id": .number(Double(s.makeID())), "eq": .string(e.id), "model": .string(L.modelID), "cost": .number(L.price), "bv": .number(L.price), "cond": .number(L.trueCondition),
                             "km": .number(Double(L.kilometres)), "mode": .string(loan != 0 ? "fin" : "own"), "loan": .number(Double(loan)), "name": .string("\(L.name) \(L.year)"),
                             "rel": .number(L.reliability), "rating": .number(L.rating), "yr": .number(Double(L.year)), "src": "used", "vis": .number(L.visibleCondition),
                             "c0": .number(L.trueCondition), "warr": 0, "down": 0, "kr": .bool(L.knownToLast)]))
        s.companies[i].set("veh", .array(list))
        markTaken(&s, i, L)
        return .ok
    }

    /// Buy a new vehicle of a chosen make. Cash, loan (20% down, five years) or lease (3 years). Original: `buyVehCore`.
    @discardableResult
    public static func buyNewVehicle(_ s: inout GameState, companyID: Int, equipmentID: String, offer: VehicleOffer, payment: Payment, data: GameData) -> Result {
        guard let i = s.companyIndex(companyID), let c = ctx(s, s.companies[i], data: data), let e = c.bd.equipment.first(where: { $0.id == equipmentID }),
              let vm = c.tables.vehicles[offer.modelID] else { return .notPossible }
        let base = vehiclePrice(vm, factor: offer.priceFactor, c.w)
        let mode = payment == .lease ? "lease" : payment == .finance ? "fin" : "own"
        if payment == .finance && c.co.cash < base * 0.2 { return .notEnoughCash }
        if payment == .cash && c.co.cash < base { return .notEnoughCash }
        return CompanySetup.addVehicle(&s, companyIndex: i, e, model: offer.modelID, modelName: vm.name, price: base, mode: mode, brand: Brand(name: offer.name, cls: 1, reliability: offer.reliability, performance: 1, rating: offer.rating), data: data) ? .ok : .notEnoughCash
    }

    // MARK: Selling

    /// Sell one unit. Used equipment sells for well under what was paid, less if it looks worn. Original: `sellUnit`.
    @discardableResult
    public static func sellUnit(_ s: inout GameState, companyID: Int, equipmentID: String, unitID: Int) -> Double {
        guard let i = s.companyIndex(companyID) else { return 0 }
        EquipmentUnits.ensureUnits(&s, companyIndex: i, equipmentID: equipmentID)
        var eq = s.companies[i].value("eq")
        var list = s.companies[i].value("units")[equipmentID].array
        guard !eq[equipmentID].isNull, let at = list.firstIndex(where: { $0["u"].int == unitID }) else { return 0 }
        let r = eq[equipmentID]
        let n = max(1, r["n"].double)
        let bvU = r["bv"].double / n, cU = r["cost"].double / n
        let u = list[at]
        let val = jsRound(bvU * 0.7 * (0.6 + 0.4 * seen(u)))
        list.remove(at: at)
        eq[equipmentID]["n"] = .number(r["n"].double - 1)
        eq[equipmentID]["bv"] = .number(r["bv"].double - bvU)
        eq[equipmentID]["cost"] = .number(r["cost"].double - cU)
        var units = s.companies[i].value("units")
        if r["n"].double - 1 <= 0 { eq = .object(eq.object.filter { $0.key != equipmentID }); units = EquipmentUnits.removing(units, equipmentID) }
        else { units[equipmentID] = .array(list) }
        s.companies[i].set("eq", eq); s.companies[i].set("units", units)
        if r["n"].double - 1 > 0 { EquipmentUnits.syncCondition(&s, companyIndex: i, equipmentID: equipmentID) }
        if val > 0 { Payments.companyReceives(&s, companyID: companyID, amount: val, category: nil, label: "Sold used \(equipmentID)") }
        return val
    }

    /// What the owner has seen of the wear: how it looked when bought, minus what has worn since.
    public static func seen(_ u: JSONValue) -> Double {
        let tc = u["tc"].isNull ? u["cond"].double : u["tc"].double
        let vis = u["vis"].isNull ? tc : u["vis"].double
        let c0 = u["c0"].isNull ? tc : u["c0"].double
        return clamp(vis - (c0 - tc), 0.05, 1)
    }

    /// Sell all of a kind of equipment for 70% of book value. Original: `sellEq`.
    @discardableResult
    public static func sellAll(_ s: inout GameState, companyID: Int, equipmentID: String) -> Double {
        guard let i = s.companyIndex(companyID) else { return 0 }
        var eq = s.companies[i].value("eq")
        guard !eq[equipmentID].isNull, equipmentID != "fit" else { return 0 }
        let v = jsRound(eq[equipmentID]["bv"].double * 0.7)
        eq = .object(eq.object.filter { $0.key != equipmentID })
        s.companies[i].set("eq", eq)
        s.companies[i].set("units", EquipmentUnits.removing(s.companies[i].value("units"), equipmentID))
        Payments.companyReceives(&s, companyID: companyID, amount: v, category: nil, label: "Sold equipment")
        return v
    }

    /// Sell a vehicle for 78% of book value (nothing for a leased one); a loan on it is settled. Original: `sellVeh`.
    @discardableResult
    public static func sellVehicle(_ s: inout GameState, companyID: Int, vehicleID: Int) -> Double {
        guard let i = s.companyIndex(companyID) else { return 0 }
        var list = s.companies[i].value("veh").array
        guard let at = list.firstIndex(where: { $0["id"].int == vehicleID }) else { return 0 }
        let v = list.remove(at: at)
        s.companies[i].set("veh", .array(list))
        let val = v["mode"].string == "lease" ? 0 : jsRound(v["bv"].double * 0.78)
        if val > 0 { Payments.companyReceives(&s, companyID: companyID, amount: val, category: nil, label: "Sold \(v["name"].string)") }
        if v["loan"].int != 0, let li = s.loans.firstIndex(where: { $0.id == v["loan"].int }) {
            Payments.companyPays(&s, companyID: companyID, amount: s.loans[li].balance, category: nil, label: "Loan settled")
            s.loans.remove(at: li)
        }
        return val
    }

    /// End a lease on equipment (the units go back). The monthly cost stops.
    public static func endLease(_ s: inout GameState, companyID: Int, equipmentID: String) {
        guard let i = s.companyIndex(companyID) else { return }
        var lease = s.companies[i].value("lease"), eqL = s.companies[i].value("eqL")
        lease = .object(lease.object.filter { $0.key != equipmentID }); eqL = .object(eqL.object.filter { $0.key != equipmentID })
        s.companies[i].set("lease", lease); s.companies[i].set("eqL", eqL)
    }

    // MARK: Reading for the screens

    /// One line of the "needed" list: what is required, what the company has and the lowest price.
    public struct Need: Identifiable, Equatable, Sendable {
        public var id: String { equipmentID }
        public var equipmentID: String
        public var name: String
        public var kind: String
        public var have: Double
        public var leased: Double
        public var need: Double
        public var required: Bool
        public var isVehicle: Bool
        public var isSoftware: Bool
        public var subscription: Bool
        public var fromPrice: Double
        public var canUsed: Bool
        public var canLease: Bool
        public var lifeYears: Double
        public var warrantyYears: Double
    }

    public static func needs(_ s: GameState, companyID: Int, data: GameData) -> [Need] {
        guard let co = s.company(companyID), let c = ctx(s, co, data: data) else { return [] }
        let std = CompanySetup.standardEquipment(c.bd, size: co.size)
        return c.bd.equipment.filter { $0.id != "fit" }.map { e in
            let k = kind(e, tradeID: c.bd.id, tables: c.tables)
            let soft = k == "soft"
            let sub = soft && softwareMode(e, tradeID: c.bd.id, company: co, c.w) == .subscription
            let lowest: Double
            if let models = e.vehicleModels {
                lowest = models.compactMap { m in c.tables.vehicles[m].map { vehiclePrice($0, factor: 0.9, c.w) } }.min() ?? 0
            } else {
                let cat = offers(for: e, tradeID: c.bd.id, family: c.bd.family, brands: c.brands, countryCode: co.countryCode, seed: s.seed, countries: c.countries, tables: c.tables)
                lowest = cat.map { price(e, company: co, c.w, factor: $0.priceFactor) }.min() ?? price(e, company: co, c.w)
            }
            let have = e.vehicleModels != nil ? Double(co.value("veh").array.filter { $0["eq"].string == e.id }.count) : co.value("eq")[e.id]["n"].double
            let years = EquipmentUnits.warrantyYears(kind: k, vehicleModel: e.vehicleModels?.first, class: 1, price: lowest, tables: c.tables, currency: c.w.currency(co))
            return Need(equipmentID: e.id, name: e.name, kind: k, have: have, leased: co.value("lease")[e.id].double,
                        need: max(0, (std[e.id] ?? (e.isRequired ? 1 : 0)) - (c.bd.id == "estate" && e.id == "car" ? Double(co.staff.filter { $0.role == "estate" && $0.num("ownCar") != 0 }.count) : 0)), required: e.isRequired, isVehicle: e.vehicleModels != nil, isSoftware: soft, subscription: sub,
                        fromPrice: lowest, canUsed: canBuyUsed(e, tradeID: c.bd.id, tables: c.tables),
                        canLease: canLease(e, tradeID: c.bd.id, unitPrice: lowest, company: co, c.w, tables: c.tables), lifeYears: e.lifeYears, warrantyYears: years)
        }
    }

    /// Equipment health as far as the owner can tell, 0 to 1 (nil if the company owns nothing that wears).
    public static func health(_ co: Company) -> Double? {
        var vals: [Double] = []
        for (_, list) in co.value("units").object { for u in list.array { vals.append(seen(u)) } }
        for v in co.value("veh").array { vals.append(seen(v)) }
        return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
    }
}
