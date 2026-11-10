import Foundation
import GameCore
import Countries
import Employees
import Finance

public enum CompanySetup {
    public struct Listing: Equatable, Identifiable, Sendable {
        public var id: Int { index }
        public var index: Int
        public var name: String
        public var squareMetres: Double
        public var rentFactor: Double
        public var location: Double
        public var landlord: String
        public init(index: Int, name: String, squareMetres: Double, rentFactor: Double, location: Double, landlord: String) {
            self.index = index; self.name = name; self.squareMetres = squareMetres; self.rentFactor = rentFactor; self.location = location; self.landlord = landlord
        }
    }

    public enum StartError: Error, Equatable { case banned(String), notEnoughCash, notAllowedHere, notYetAvailable }

    public static func recommendedSize(_ bd: Trade, city: Country.City, brandStrength: Double = 0) -> Double {
        let target = clamp(jsRound(city.demand * 20) / 20, 0.4, 2.2)
        let tgt = clamp(target, bd.minSize, bd.maxSize)
        let k = clamp(brandStrength * 1.2, 0, 1)
        return max(bd.minSize, jsRound((bd.minSize + (tgt - bd.minSize) * k) * 20) / 20)
    }

    public static func banReason(_ tradeID: String, country: Country) -> String? {
        let b = country.pack["banned"][tradeID]
        return b.isNull ? nil : b.string
    }

    static func generateName(country: Country, family: String, _ r: inout DeterministicRandom) -> String {
        let endings = country.pack["names"]["companyEnd"]
        let list: [String]
        if endings.object.isEmpty { list = endings.array.map { $0.string } }
        else { list = (endings[family].isNull ? endings["svc"] : endings[family]).array.map { $0.string } }
        let end = list.isEmpty ? "Group" : r.pick(list)
        let roll = r.range(0, 1)
        let lasts = country.lastNames
        if roll < 0.3 && !lasts.isEmpty { return r.pick(lasts) + " " + end }
        if roll < 0.42 && (family == "svc" || family == "fin") && lasts.count > 1 {
            let a = r.pick(lasts)
            let b = r.pick(lasts.filter { $0 != a })
            return "\(a) & \(b) \(end)"
        }
        let starts = country.companyNameStarts
        if roll < 0.82 { return coined(starts, endings: country.pack["names"]["coinEnd"].array.map { $0.string }, &r) + " " + end }
        return (starts.isEmpty ? "Nova" : r.pick(starts)) + " " + end
    }

    static func coined(_ starts: [String], endings: [String], _ r: inout DeterministicRandom) -> String {
        let endings = endings.isEmpty ? ["ia", "ex", "ora", "on", "ix"] : endings
        var root = starts.isEmpty ? "Nova" : r.pick(starts).filter { $0.isLetter }
        if root.count > 6 { root = String(root.prefix(5)) }
        var tail = r.pick(endings)
        if let l = root.last?.lowercased(), let f = tail.first?.lowercased(), l == f { tail.removeFirst() }
        return root + tail
    }

    static let premisesWords = ["Properties", "Estates", "Commercial", "Real Estate", "Holdings", "Property Group"]

    public static func listings(for co: Company, _ bd: Trade, _ w: World) -> [Listing] {
        if PremisesExtras.isHomeTrade(bd) { return PremisesExtras.listings(co, bd, w) }
        guard let kind = bd.premisesKind, kind != "none", kind != "home" else { return [] }
        var r = HashedRandom("\(w.state.seed):pl:\(co.type):\(co.cityID):\(w.week / 26)")
        let country = w.country(co)
        let rec = max(10, jsRound(bd.premisesM2 * co.size))
        let tiers = w.catalog.tables.raw["PL_TIERS"].array
        let tiersB = w.catalog.tables.raw["PL_TIERS_B"].array
        let foot = Competition.isFootTraffic(co.value("prem")["kind"].isNull ? kind : co.value("prem")["kind"].string)
        return tiers.enumerated().map { (i, t) in
            let m2 = max(10, jsRound(rec * t[1].double * (0.92 + r.next() * 0.16) / 5) * 5)
            let rentF = t[2].double * (0.94 + r.next() * 0.12)
            let landlord = country.companyNameStarts.isEmpty ? "Nova" : country.companyNameStarts[Int(saturating: (r.next() * Double(country.companyNameStarts.count)).rounded(.down))]
            let word = premisesWords[Int(saturating: (r.next() * Double(premisesWords.count)).rounded(.down))]
            return Listing(index: i, name: foot ? t[0].string : tiersB[i].string, squareMetres: m2, rentFactor: rentF, location: t[3].double, landlord: landlord + " " + word)
        }
    }

    public enum PremisesResult: Equatable { case ok, notEnoughCash, bad }

    public struct PremisesTerms: Equatable {
        public var rentPerM2Year: Double
        public var monthlyRent: Double
        public var deposit: Double
        public var fitOut: Double
        public var purchasePrice: Double
        public var downPayment: Double
        public var squareMetres: Double
    }

    public static func premisesTerms(_ co: Company, _ listing: Listing, data: GameData, world w: World) -> PremisesTerms? { premisesTerms(co, listing, catalog: data.catalog, world: w) }

    public static func premisesTerms(_ co: Company, _ listing: Listing, catalog: TradeCatalog, world w: World) -> PremisesTerms? {
        guard let bd = catalog[co.type], let kind0 = bd.premisesKind, case let kind = PremisesExtras.isHomeTrade(bd) ? PremisesExtras.placeKind(bd) : kind0,
              let P = catalog.tables.premises[kind], let city = w.city(co) else { return nil }
        let m2 = listing.squareMetres
        let rent0 = P.rentPerM2Year * listing.rentFactor * city.rent * w.inflationIndex
        let rent = m2 > 0 ? w.currency(co).tidy(rent0 * m2 / 12) * 12 / m2 : w.currency(co).tidy(rent0)
        let fit = (catalog.tables.fitOut[kind] ?? 0) * m2
        let price = jsRound(P.pricePerM2 * listing.rentFactor * pow(city.rent, 0.9) * m2 * w.economy.housing)
        return PremisesTerms(rentPerM2Year: rent, monthlyRent: rent * m2 / 12, deposit: rent * m2 / 12 * 3, fitOut: fit, purchasePrice: price, downPayment: price * 0.35, squareMetres: m2)
    }

    public static func setPremises(_ s: inout GameState, companyID: Int, listing lst: Listing?, buy: Bool = false, data: GameData) -> PremisesResult {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type], let kind0 = bd.premisesKind,
              case let kind = (PremisesExtras.isHomeTrade(bd) && lst != nil) ? PremisesExtras.placeKind(bd) : kind0,
              data.catalog.tables.premises[kind] != nil else { return .bad }
        if kind == "home" || kind == "none" {
            s.companies[i].set("prem", .object(["kind": .string(kind), "m2": 0, "rent": 0, "owned": false, "val": 0, "loan": 0]))
            return .ok
        }
        let w = World(state: s, data: data)
        guard let lst = lst, let t0 = premisesTerms(s.companies[i], lst, data: data, world: w) else { return .bad }
        let old = s.companies[i].value("prem")
        let refund = old["dep"].double > 0 && !old["owned"].bool ? old["dep"].double : 0
        let co = s.companies[i]
        let franchiseBuilding = !buy && co.value("franchise")["bld"].bool
        var t = t0
        if franchiseBuilding { t.rentPerM2Year *= 0.85; t.monthlyRent *= 0.85; t.deposit = 0 }
        if co.cash + refund < (buy ? t.downPayment : t.deposit) + t.fitOut { return .notEnoughCash }
        if refund > 0 { Payments.companyReceives(&s, companyID: companyID, amount: refund, category: nil, label: "Lease deposit returned") }
        let m2 = lst.squareMetres
        if buy {
            Payments.companyPays(&s, companyID: companyID, amount: t.downPayment, category: nil, label: "Premises purchase (equity)")
            let loanID = EquipmentMarket.openLoan(&s, companyID: companyID, name: "Commercial mortgage", amount: t.purchasePrice - t.downPayment, months: 180,
                                                  extraMargin: max(0.012, Banking.creditMargin(s.credit) * 0.45) + 0.004 - Banking.creditMargin(s.credit))
            if let li = s.loans.firstIndex(where: { $0.id == loanID }) { s.loans[li].isGuaranteed = false }
            s.companies[i].set("prem", .object(["kind": .string(kind), "m2": .number(m2), "rent": 0, "owned": true, "val": .number(t.purchasePrice), "loan": .number(Double(loanID)), "cost": .number(t.purchasePrice),
                                                "loc": .number(lst.location), "lname": .string(lst.name), "landlord": .string(lst.landlord)]))
        } else {
            if t.deposit > 0 { Payments.companyPays(&s, companyID: companyID, amount: t.deposit, category: nil, label: "Lease deposit (3 months)") }
            s.companies[i].set("prem", .object(["kind": .string(kind), "m2": .number(m2), "rent": .number(t.rentPerM2Year), "owned": false, "val": 0, "loan": 0, "dep": .number(t.deposit),
                                                "loc": .number(lst.location), "lname": .string(lst.name), "landlord": .string(lst.landlord)]))
            var docs = s.companies[i].value("docs")
            docs["lease_agreement"] = .object(["st": "ok", "done": .number(Double(s.week)), "ok": .number(Double(s.week))])
            s.companies[i].set("docs", docs)
        }
        if t.fitOut > 0 {
            Payments.companyPays(&s, companyID: companyID, amount: t.fitOut, category: nil, label: "Fit-out of premises")
            var eq = s.companies[i].value("eq")
            eq["fit"] = .object(["n": 1, "cond": 1, "bv": .number(t.fitOut), "cost": .number(t.fitOut), "used": 0, "age": 0, "life": 10])
            s.companies[i].set("eq", eq)
        }
        return .ok
    }

    public static func equipmentPrice(_ e: EquipmentSpec, company co: Company, _ w: World) -> Double {
        let raw = (e.cost * w.inflationIndex * w.country(co).costIndex).rounded()
        let fx = w.rates.rate(w.country(co))
        return Currency.nicePrice(raw / fx) * fx
    }

    static func opensTheTrade(_ e: EquipmentSpec, _ bd: Trade, tables: TradeTables) -> Bool {
        e.opensTheTrade || PersonalEquipment.rule(bd, e, tables: tables) != nil
    }

    public static func standardEquipment(_ bd: Trade, size: Double) -> [String: Double] {
        var out: [String: Double] = [:]
        for e in bd.equipment where e.standardCount > 0 { out[e.id] = max(1, jsRound(e.standardCount * size)) }
        return out
    }

    public static func standardStaff(_ bd: Trade, size: Double) -> [(role: String, count: Int)] {
        var base: [(role: String, count: Int)] = bd.standardStaff.map { (role: $0.role, count: Int(max(1, jsRound($0.count * size)))) }
        if size <= 0.6 {
            base = bd.standardStaff.enumerated().map { (i, s) in (role: s.role, count: i == 0 ? Int(max(1, jsRound(s.count * size))) : Int(max(0, jsRound(s.count * size)))) }
        }
        return base
    }

    @discardableResult
    public static func buyEquipment(_ s: inout GameState, companyID: Int, equipmentID: String, quantity q: Double, data: GameData, preferFinancing: Bool = false, forceFinancing: Bool = false) -> Bool {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type], let e = bd.equipment.first(where: { $0.id == equipmentID }) else { return false }
        let w = World(state: s, data: data)
        let co = s.companies[i]
        if let model = e.vehicleModels?.first, let v = data.catalog.tables.vehicles[model] {
            for _ in 0..<Int(q) {
                let price = jsRound(roundTo(v.price * w.inflationIndex, step: 1000))
                let cash = s.companies[i].cash
                let mode = cash >= price && !forceFinancing && !(preferFinancing && cash < price * 3) ? "own" : cash >= price * 0.2 ? "fin" : "lease"
                _ = addVehicle(&s, companyIndex: i, e, model: model, modelName: v.name, price: price, mode: mode, brand: nil, data: data)
            }
            return true
        }
        let unit = equipmentPrice(e, company: co, w)
        let price = unit * q
        if co.cash < price { return false }
        Payments.companyPays(&s, companyID: companyID, amount: price, category: nil, label: "\(e.name) x\(Int(q))")
        addEquipment(&s, companyIndex: i, e, tradeID: bd.id, quantity: q, totalPrice: price, brand: nil, used: nil, data: data)
        return true
    }

    static func addEquipment(_ s: inout GameState, companyIndex i: Int, _ e: EquipmentSpec, tradeID: String, quantity q: Double, totalPrice price: Double,
                             brand: EquipmentMarket.Brand?, used: EquipmentMarket.UsedOffer?, data: GameData) {
        var eq = s.companies[i].value("eq")
        var rec = eq[e.id].isNull ? JSONValue.object(["n": 0, "cond": 1, "bv": 0, "cost": 0, "used": 0, "age": 0]) : eq[e.id]
        let before = rec["n"].double
        let total = before + q
        rec["cond"] = .number((rec["cond"].double * before + (used?.trueCondition ?? 1) * q) / max(1, total))
        rec["n"] = .number(total)
        rec["bv"] = .number(rec["bv"].double + price)
        rec["cost"] = .number(rec["cost"].double + price)
        if used != nil { rec["used"] = 1 }
        rec["life"] = .number(e.lifeYears)
        if let b = brand {
            rec["perf"] = .number(((rec["perf"].isNull ? 1 : rec["perf"].double) * before + b.performance * q) / max(1, total))
            rec["rel"] = .number(((rec["rel"].isNull ? 1 : rec["rel"].double) * before + b.reliability * q) / max(1, total))
            var mods = rec["mods"].array
            if let at = mods.firstIndex(where: { $0["nm"].string == b.name }) { mods[at]["n"] = .number(mods[at]["n"].double + q) }
            else { mods.append(.object(["nm": .string(b.name), "n": .number(q), "rt": .number(b.rating)])) }
            rec["mods"] = .array(mods)
        }
        eq[e.id] = rec
        s.companies[i].set("eq", eq)
        EquipmentUnits.recordPurchase(&s, companyIndex: i, e, tradeID: tradeID, quantity: Int(q), unitPrice: price / max(1, q), brand: brand, used: used, data: data)
        if let bd = data.catalog[tradeID] { SpecialFamilies.afterBuy(&s, companyIndex: i, bd, equipmentID: e.id, quantity: q) }
    }

    static func addVehicle(_ s: inout GameState, companyIndex i: Int, _ e: EquipmentSpec, model: String, modelName: String, price: Double, mode: String,
                           brand: EquipmentMarket.Brand?, prepaid: Bool = false, data: GameData) -> Bool {
        let companyID = s.companies[i].id
        var loanID = 0, lease = 0.0, bookValue = price
        let name = brand?.name ?? modelName
        switch mode {
        case "own":
            if !prepaid && s.companies[i].cash < price { return false }
            if !prepaid { Payments.companyPays(&s, companyID: companyID, amount: price, category: nil, label: name) }
        case "fin":
            if !prepaid && s.companies[i].cash < price * 0.2 { return false }
            if !prepaid { Payments.companyPays(&s, companyID: companyID, amount: price * 0.2, category: nil, label: "Down payment: \(name)") }
            loanID = EquipmentMarket.openLoan(&s, companyID: companyID, name: "Vehicle loan: \(name)", amount: price * 0.8, months: 60, extraMargin: 0.015)
        default:
            lease = jsRound(price * 0.0215); bookValue = 0
        }
        let year = GameCalendar.year(week: s.week)
        let warranty = EquipmentUnits.warrantyYears(kind: "veh", vehicleModel: model, class: 1, price: price, tables: data.catalog.tables, currency: World(state: s, data: data).currency(s.companies[i]))
        var rec: JSONValue = .object(["id": .number(Double(s.makeID())), "eq": .string(e.id), "model": .string(model), "cost": .number(price), "bv": .number(bookValue), "cond": 1, "km": 0,
                                      "mode": .string(mode), "loan": .number(Double(loanID)), "name": .string(brand == nil ? modelName : "\(name) \(year)"), "rel": .number(brand?.reliability ?? 1),
                                      "yr": .number(Double(year)), "src": .string(mode == "lease" ? "lease" : "new"), "vis": 1, "c0": 1, "down": 0,
                                      "warr": .number(Double(s.week) + (mode == "lease" ? 156 : warranty * 52))])
        if let b = brand { rec["rating"] = .number(b.rating) }
        if mode == "lease" { rec["lease"] = .number(lease) }
        var list = s.companies[i].value("veh").array
        list.append(rec)
        s.companies[i].set("veh", .array(list))
        return true
    }

    public static func create(_ s: inout GameState, tradeID: String, cityID: String, size: Double? = nil, name: String? = nil,
                              countryCode: String? = nil, data: GameData, context: FinanceContext) -> Result<Int, StartError> {
        guard let bd = data.catalog[tradeID] else { return .failure(.notAllowedHere) }
        let code = countryCode ?? s.homeCountryCode
        guard let country = data.countries[code], let city = country.city(cityID) ?? country.cities.first else { return .failure(.notAllowedHere) }
        if let reason = banReason(tradeID, country: country) { return .failure(.banned(reason)) }
        let currency = context.currency(code, s)
        let abroad = code != s.homeCountryCode
        let abroadFee = abroad ? Luxury.abroadFee(Ambitions.abroadFee(context.currency(code, s).scaledPrice(220000 + bd.openingCost * 1.5), s, data), s) : 0
        if abroad && s.cash < abroadFee + currency.scaledPrice(50000) { return .failure(.notEnoughCash) }
        if s.cash < country.shareCapitalMinimum + country.registrationFee + abroadFee { return .failure(.notEnoughCash) }
        let chosenSize = size ?? recommendedSize(bd, city: city)
        var co = Company(raw: [:])
        co.id = s.makeID()
        co.type = tradeID; co.countryCode = code
        co.name = name ?? generateName(country: country, family: bd.family, &s.random)
        co.cityID = city.id; co.size = chosenSize; co.status = .setup
        co.foundedWeek = s.week; co.openedWeek = nil; co.ownership = 100
        co.set("holders", .array([])); co.set("docs", .object([:])); co.set("eq", .object([:])); co.set("veh", .array([])); co.set("lease", .object([:]))
        co.set("staff", .array([])); co.set("mgrWage", 0); co.set("mgrBonus", 0)
        co.set("auth", Budget.initialAuth)
        co.set("region", 0); co.set("mkt", .object([:])); co.awareness = 25
        var knob: [String: JSONValue] = [:]
        for k in bd.knobs { knob[k.id] = .number(Double(k.defaultIndex)) }
        co.set("knob", .object(knob))
        co.priceLevel = 0; co.ownerHours = 40; co.reputation = 45; co.quality = 45; co.ownerSkill = 40; co.maintenance = 1
        co.set("stockPol", 1); co.set("bid", 1); co.set("prem", .null); co.set("recv", .array([]))
        co.set("pay", .object(["wages": 0, "other": 0, "tax": 0, "rent": 0])); co.vatBalance = 0; co.inventory = 0
        co.books = Books(); co.set("hist", .array([])); co.set("mods", .array([])); co.set("tx", .array([]))
        co.set("ins", .object([:])); co.set("flags", .object([:])); co.set("fm", .object([:]))
        co.set("lossCarry", 0); co.set("capital", 0); co.set("inj", 0)
        co.set("unitsW", 0); co.set("mgrQ", 0); co.set("eqc", 1); co.set("books", 0.5); co.set("group", 0)
        if let role = bd.standardStaff.first?.role, let base = data.catalog.tables.roles[role]?.baseMonthlyWage, bd.ownerFTE > 0 {
            co.set("ownWage", .number(jsRound(Wages.market(baseMonthlyWage: base, country: country, city: city, economy: s.economy, rates: World(state: s, data: data).rates))))
        }
        co.awareness = min(co.awareness, 10)
        s.companies.append(co)
        s.mirrorCash()
        let i = s.companies.count - 1
        let id = co.id
        Payments.playerPays(&s, country.registrationFee, label: "Registration of \(co.name)", companyID: id)
        Payments.recordInvestment(&s, companyID: id, amount: country.shareCapitalMinimum)
        s.companies[i].shareCapital = country.shareCapitalMinimum
        s.companies[i].addTransaction(week: s.week, amount: country.shareCapitalMinimum, label: "Share capital paid in")
        if abroad { Payments.playerPays(&s, abroadFee, label: "Local representative, travel and legal counsel abroad", companyID: id) }
        let used = CapacityModel.ownerHoursCommitted(s, except: id)
        let hours = max(0, (min(s.companies[i].ownerHours, 80 - used, max(10, 55 - used)) / 5).rounded(.down) * 5)
        s.companies[i].ownerHours = hours
        return .success(id)
    }

    public static func giveUpPremises(_ s: inout GameState, companyID: Int, data: GameData) -> Bool {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type], bd.premisesKind == "home" else { return false }
        let prem = s.companies[i].value("prem")
        guard !prem.isNull, prem["m2"].double > 0 else { return false }
        if prem["owned"].bool {
            let loanID = prem["loan"].int
            let debt = s.loans.first { $0.id == loanID }?.balance ?? 0
            s.loans.removeAll { $0.id == loanID }
            let value = prem["val"].double
            Payments.companyReceives(&s, companyID: companyID, amount: max(0, value - debt), category: nil, label: "Office sold")
            if debt > value { Payments.companyPays(&s, companyID: companyID, amount: debt - value, category: nil, label: "Mortgage shortfall") }
        } else if prem["dep"].double > 0 {
            Payments.companyReceives(&s, companyID: companyID, amount: prem["dep"].double, category: nil, label: "Lease deposit returned")
        }
        s.companies[i].set("prem", .object(["kind": "home", "m2": 0, "rent": 0, "owned": false, "val": 0, "loan": 0]))
        return true
    }

    public struct Estimate: Equatable {
        public var documents = 0.0, equipment = 0.0, vehicles = 0.0, premises = 0.0, stock = 0.0, firstPayroll = 0.0, buffer = 0.0
        public var requiredEquipment = 0.0, requiredVehicles = 0.0
        public var requiredEquipmentUpfront = 0.0
        public var premisesLeast = 0.0
        public var minimumPayroll = 0.0
        public var premisesFitOut = 0.0
        public var monthlyRent = 0.0
        public var property = 0.0
        public var registration = 0.0, shareCapital = 0.0, abroad = 0.0
        public var wait = 0.0
        public var minimumToOpen: Double { documents + premisesLeast + property + wait + registration + shareCapital + abroad + requiredEquipmentUpfront + requiredVehicles }
        public var total: Double { documents + equipment + vehicles + premises + stock + firstPayroll + buffer + property + registration + abroad + wait }
        public var personalOutlay: Double { registration + shareCapital + abroad }
    }

    public static func estimate(tradeID: String, cityID: String, size: Double, countryCode: String? = nil, state s: GameState, data: GameData) -> Estimate? {
        guard let bd = data.catalog[tradeID] else { return nil }
        let code = countryCode ?? s.homeCountryCode
        guard let country = data.countries[code], let city = country.city(cityID) ?? country.cities.first else { return nil }
        var tmp = s
        tmp.cash = max(tmp.cash, 1e12)
        let cx = FinanceContext(countries: data.countries, trades: data.catalog)
        let result = create(&tmp, tradeID: tradeID, cityID: city.id, size: size, name: "tmp", countryCode: code, data: data, context: cx)
        guard case .success(let id) = result, let i = tmp.companyIndex(id) else { return nil }
        let co = tmp.companies[i]
        let w = World(state: tmp, data: data)
        var r = Estimate()
        var vehicleFull = 0.0, monthlyRent = 0.0
        for d in Documents.needed(co, bd, w) where d != "vat_not_applicable" { r.documents += Documents.cost(d, company: co, bd, w) }
        let need = standardEquipment(bd, size: size)
        for e in bd.equipment {
            let q = need[e.id] ?? (e.isRequired ? 1 : 0)
            if q <= 0 { continue }
            if let model = e.vehicleModels?.first {
                let price = data.catalog.tables.vehicles[model]?.price ?? 300000
                r.vehicles += price * q * w.inflationIndex * 0.2
                if opensTheTrade(e, bd, tables: data.catalog.tables) { r.requiredVehicles += price * q * w.inflationIndex * 0.2 }
                vehicleFull += price * q
            } else {
                r.equipment += equipmentPrice(e, company: co, w) * q
                if opensTheTrade(e, bd, tables: data.catalog.tables) {
                    let unit = equipmentPrice(e, company: co, w)
                    r.requiredEquipment += unit * q
                    r.requiredEquipmentUpfront += EquipmentMarket.canFinance(e, tradeID: bd.id, total: unit * q, company: co, w, tables: data.catalog.tables) ? unit * q * 0.2 : unit * q
                }
            }
        }
        if let kind = bd.premisesKind, let P = data.catalog.tables.premises[kind], bd.premisesM2 > 0 {
            let m2 = jsRound(bd.premisesM2 * size)
            let rent = P.rentPerM2Year * city.rent * w.inflationIndex
            r.premises = rent * m2 / 12 * 3 + (data.catalog.tables.fitOut[kind] ?? 0) * m2
            r.premisesFitOut = (data.catalog.tables.fitOut[kind] ?? 0) * m2
            monthlyRent = rent * m2 / 12
            let least = listings(for: co, bd, w).compactMap { l in premisesTerms(co, l, catalog: data.catalog, world: w).map { $0.deposit + $0.fitOut } }.min()
            r.premisesLeast = min(r.premises, least ?? r.premises)
        }
        r.stock = bd.id == CarDealer.tradeID ? CarDealer.stockBudget(co, bd, tmp, data) : OpeningChecklist.initialStockCost(co, bd, w)
        for (i, st) in bd.standardStaff.enumerated() {
            let n = (i == 0 && bd.ownerFTE >= 1) ? max(0, st.count - 1) : st.count
            let base = data.catalog.tables.roles[st.role]?.baseMonthlyWage ?? 40000
            let cost = n * Wages.market(baseMonthlyWage: base, country: country, city: city, economy: s.economy, rates: w.rates) * country.employerCostFactor
            r.firstPayroll += cost
            if i == 0 { r.minimumPayroll += cost }
        }
        r.buffer = bd.weeklyFixedCosts * 6 * pow(size, 0.9) * city.rent * 0.5 + SpecialFamilies.extraStartupBuffer(bd, size: size, country: country)
        RentalFinance.addEstimate(&r, bd, size: size, city: city, currency: w.currency(co), tmp, w)
        if bd.family == "project" && !bd.hasTrait("dev") { r.buffer *= 3.5 }
        let longest = Documents.needed(co, bd, w).compactMap { Documents.definition($0, country: country, tables: data.catalog.tables)?.weeks }.max() ?? 0
        if longest > 8 { r.wait = (r.firstPayroll + monthlyRent + vehicleFull * 0.012) * Double(longest - 4) / 4.33 * 1.15 }
        let cur = Currency(country: country, rates: w.rates)
        func round(_ v: Double) -> Double { v == 0 ? 0 : Currency.nicePrice(v / cur.rate) * cur.rate }
        r.documents = round(r.documents); r.equipment = round(r.equipment); r.vehicles = round(r.vehicles); r.premises = round(r.premises)
        r.premisesFitOut = min(r.premises, round(r.premisesFitOut)); r.monthlyRent = round(monthlyRent); r.premisesLeast = min(r.premises, round(r.premisesLeast))
        r.requiredEquipment = round(r.requiredEquipment); r.requiredEquipmentUpfront = round(r.requiredEquipmentUpfront); r.requiredVehicles = round(r.requiredVehicles); r.minimumPayroll = round(r.minimumPayroll)
        r.stock = round(r.stock); r.firstPayroll = round(r.firstPayroll); r.buffer = round(r.buffer); r.property = round(r.property); r.wait = round(r.wait)
        r.registration = country.registrationFee; r.shareCapital = country.shareCapitalMinimum
        if code != s.homeCountryCode { r.abroad = Luxury.abroadFee(Ambitions.abroadFee(cur.scaledPrice(220000 + bd.openingCost * 1.5), s, data), s) }
        return r
    }

    public struct SetupOptions: Equatable, Sendable {
        public enum Team: String, Equatable, Sendable { case minimum, standard }
        public var team: Team = .standard
        public var optionalEquipment = false
        public var payrollMonthsReserve: Double? = nil
        public var equipmentInPlace = false
        public var teamInPlace = false
        public var applyDocuments = true
        public var autoPremises = true
        public var buyProperty = true
        public init(team: Team = .standard, optionalEquipment: Bool = false, payrollMonthsReserve: Double? = nil, equipmentInPlace: Bool = false, teamInPlace: Bool = false) {
            self.team = team; self.optionalEquipment = optionalEquipment; self.payrollMonthsReserve = payrollMonthsReserve
            self.equipmentInPlace = equipmentInPlace; self.teamInPlace = teamInPlace
        }
        public static let careful = SetupOptions(team: .minimum, optionalEquipment: false, payrollMonthsReserve: 2)
    }

    public struct SetupSkipped: Equatable, Sendable, Identifiable {
        public enum Kind: String, Equatable, Sendable { case staff, equipment, vehicle }
        public var id: String
        public var kind: Kind
        public var title: String
        public var count: Int
        public var cost: Double
        public var reason: String
    }

    public struct SetupReport: Equatable, Sendable {
        public var log: [String] = []
        public var skipped: [SetupSkipped] = []
        public init(log: [String] = [], skipped: [SetupSkipped] = []) { self.log = log; self.skipped = skipped }
    }

    public static func quickSetup(_ s: inout GameState, companyID: Int, data: GameData, faithfulHiring: Bool = false) -> [String] {
        quickSetupReport(&s, companyID: companyID, data: data, faithfulHiring: faithfulHiring, options: SetupOptions()).log
    }

    public static func quickSetupReport(_ s: inout GameState, companyID: Int, data: GameData, faithfulHiring: Bool = false, options: SetupOptions) -> SetupReport {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type] else { return SetupReport(log: ["unknown company"]) }
        var rep = SetupReport()
        let w = World(state: s, data: data)
        for d in Documents.needed(s.companies[i], bd, w) where d != "vat_not_applicable" && options.applyDocuments {
            let st = s.companies[i].value("docs")[d]["st"].string
            if st == "ok" || st == "applied" { continue }
            let r = Documents.apply(d, companyID: companyID, state: &s, data: data)
            if r != .ok && r != .alreadyHeld { rep.log.append("document \(d): \(r)") }
        }
        if options.autoPremises, let kind = bd.premisesKind, kind != "none", kind != "home", s.companies[i].value("prem").isNull {
            let ls = listings(for: s.companies[i], bd, World(state: s, data: data))
            if ls.count > 2 {
                let r = setPremises(&s, companyID: companyID, listing: ls[2], data: data)
                if r != .ok { rep.log.append("premises: \(r)") }
            }
        }
        let need = standardEquipment(bd, size: s.companies[i].size)
        for e in bd.equipment.filter({ $0.vehicleModels == nil }) + bd.equipment.filter({ $0.vehicleModels != nil }) {
            let q = need[e.id] ?? (e.isRequired ? 1 : 0)
            if q <= 0 || options.equipmentInPlace { continue }
            if !options.optionalEquipment && !opensTheTrade(e, bd, tables: data.catalog.tables) {
                let each: Double
                if let model = e.vehicleModels?.first {
                    each = (data.catalog.tables.vehicles[model]?.price ?? 300000) * w.inflationIndex * 0.2
                } else { each = equipmentPrice(e, company: s.companies[i], w) }
                rep.skipped.append(SetupSkipped(id: "eq:\(e.id)", kind: e.vehicleModels == nil ? .equipment : .vehicle, title: e.name, count: Int(q), cost: each * q,
                                                reason: "Not needed to open; buy it when the business can carry it."))
                continue
            }
            var qq = q
            var ok = buyEquipment(&s, companyID: companyID, equipmentID: e.id, quantity: qq, data: data, preferFinancing: true)
            while !ok && qq > 1 { qq = max(1, (qq / 2).rounded(.down)); ok = buyEquipment(&s, companyID: companyID, equipmentID: e.id, quantity: qq, data: data, preferFinancing: true) }
            if !ok { rep.log.append("equipment \(e.id): not enough cash") }
        }
        if options.buyProperty { RentalFinance.buyFirstProperty(&s, companyID: companyID, data: data, log: &rep.log) }
        if !bd.hasTrait("noStaff") && bd.family != "rent" && !options.teamInPlace {
            hireStandardTeam(&s, companyID: companyID, bd: bd, data: data, faithfulHiring: faithfulHiring, options: options, report: &rep)
        }
        RentalFinance.finishSetup(&s, companyID: companyID, data: data)
        return rep
    }

    @discardableResult
    public static func transferEquipment(_ s: inout GameState, companyID: Int, data: GameData) -> Int {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type] else { return 0 }
        let w = World(state: s, data: data)
        let need = standardEquipment(bd, size: s.companies[i].size)
        var moved = 0
        for e in bd.equipment where e.vehicleModels == nil {
            let q = need[e.id] ?? (e.isRequired ? 1 : 0)
            if q <= 0 { continue }
            addEquipment(&s, companyIndex: i, e, tradeID: bd.id, quantity: q, totalPrice: equipmentPrice(e, company: s.companies[i], w) * q * 0.6, brand: nil, used: nil, data: data)
            moved += Int(q)
        }
        return moved
    }

    public static func transferStaff(_ s: inout GameState, companyID: Int, data: GameData) -> (people: Int, retention: Double) {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type] else { return (0, 0) }
        var rep = SetupReport()
        hireStandardTeam(&s, companyID: companyID, bd: bd, data: data, faithfulHiring: false, options: SetupOptions(), report: &rep)
        let staff = s.companies[i].staff
        return (staff.count, staff.reduce(0) { $0 + $1.monthlyWage })
    }

    private static func carries(_ co: Company, extraMonthly extra: Double, months: Double, loans: [Loan]) -> Bool {
        let payroll = co.staff.reduce(0.0) { $0 + $1.monthlyWage * $1.partTimeShare }
        let rent = co.value("prem")["rent"].double
        let instalments = loans.filter { $0.companyID == co.id }.reduce(0.0) { $0 + $1.monthlyPayment }
        return co.cash >= (payroll * 1.12 + extra + rent) * months + rent + instalments
    }

    private static func hireStandardTeam(_ s: inout GameState, companyID: Int, bd: Trade, data: GameData, faithfulHiring: Bool, options: SetupOptions, report rep: inout SetupReport) {
        guard let i = s.companyIndex(companyID) else { return }
        let w = World(state: s, data: data)
        let factor = w.country(s.companies[i]).employerCostFactor
        for (idx, st) in standardStaff(bd, size: s.companies[i].size).enumerated() {
            let have = s.companies[i].staff.filter { $0.role == st.role }.count
            var n = st.count - have
            if idx == 0 && bd.ownerFTE >= 1 && s.companies[i].managerID == nil && s.companies[i].ownerHours >= 20 { n = max(0, n - 1) }
            let roleName = data.catalog.tables.roles[st.role]?.name ?? st.role
            let wage = Hiring.marketWage(role: st.role, company: s.companies[i], state: s, data: data) * factor
            if options.team == .minimum && idx > 0 {
                if n > 0 { rep.skipped.append(SetupSkipped(id: "staff:\(st.role)", kind: .staff, title: roleName, count: n, cost: wage * Double(n), reason: "Not needed to open; hire when the money is coming in.")) }
                continue
            }
            var attempts = 0; let allowed = faithfulHiring ? max(0, n) : 6
            while n > 0 && attempts < allowed {
                if let months = options.payrollMonthsReserve, !carries(s.companies[i], extraMonthly: wage, months: months, loans: s.loans) {
                    rep.skipped.append(SetupSkipped(id: "staff:\(st.role)", kind: .staff, title: roleName, count: n, cost: wage * Double(n),
                                                    reason: "Your account does not yet cover \(Int(months)) months of this wage."))
                    n = 0
                    break
                }
                attempts += 1
                let found = Hiring.search(role: st.role, company: s.companies[i], mode: .network, faces: false, state: &s, data: data)
                guard !found.isEmpty else { break }
                if faithfulHiring {
                    let cands = found.sorted { $0.askingMonthlyWage < $1.askingMonthlyWage }
                    let pick = cands[cands.count / 2]
                    let offer = w.currency(s.companies[i]).roundedStep(Hiring.askInThisTalk(pick, company: s.companies[i], state: s, data: data) * 1.02, about: 100)
                    if Hiring.hire(pick.id, into: companyID, monthlyWage: offer, state: &s, data: data) == .ok { n -= 1 }
                } else if AutoHire.hireWorker(role: st.role, companyID: companyID, candidates: found, state: &s, data: data) != nil { n -= 1 }
                else if let pick = found.min(by: { $0.askingMonthlyWage < $1.askingMonthlyWage }) {
                    let offer = w.currency(s.companies[i]).roundedStep(Hiring.askInThisTalk(pick, company: s.companies[i], state: s, data: data) * 1.02, about: 100)
                    if Hiring.hire(pick.id, into: companyID, monthlyWage: offer, state: &s, data: data) == .ok { n -= 1 }
                }
            }
            if n > 0 { rep.log.append("hire \(st.role): \(n) missing") }
        }
    }
}
