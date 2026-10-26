import Foundation
import GameCore
import Countries
import Employees
import Finance

/// Starting a company: choosing trade, city, legal form and size; the paperwork, premises, equipment and people it
/// needs. Original: `startCompany`, `newCompany`, `setupEstimate`, `autoSetup` (engine/core/api.js, company.js).
public enum CompanySetup {
    public struct Listing: Equatable, Identifiable {
        public var id: Int { index }
        public var index: Int
        public var name: String
        public var squareMetres: Double
        public var rentFactor: Double
        /// Footfall / location quality (1 = standard)
        public var location: Double
        public var landlord: String
    }

    public enum StartError: Error, Equatable { case banned(String), notEnoughCash, notAllowedHere, notYetAvailable }

    /// Size a new company starts at, between the trade's minimum and the city's natural size. Original: `startSize`.
    public static func recommendedSize(_ bd: Trade, city: Country.City, brandStrength: Double = 0) -> Double {
        let target = clamp(jsRound(city.demand * 20) / 20, 0.4, 2.2)
        let tgt = clamp(target, bd.minSize, bd.maxSize)
        let k = clamp(brandStrength * 1.2, 0, 1)
        return max(bd.minSize, jsRound((bd.minSize + (tgt - bd.minSize) * k) * 20) / 20)
    }

    /// Reason this trade is not allowed in a country, if any. Original: `legalStatus`.
    public static func banReason(_ tradeID: String, country: Country) -> String? {
        let b = country.pack["banned"][tradeID]
        return b.isNull ? nil : b.string
    }

    // MARK: Names

    /// A company name that sounds local. Original: `brandCoName` (framework.js; the richer `R25.nameFor` is not ported).
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

    /// A coined brand word from a local root and a local ending (`names.coinEnd` in the country's data). Original: `coinName`.
    static func coined(_ starts: [String], endings: [String], _ r: inout DeterministicRandom) -> String {
        let endings = endings.isEmpty ? ["ia", "ex", "ora", "on", "ix"] : endings
        var root = starts.isEmpty ? "Nova" : r.pick(starts).filter { $0.isLetter }
        if root.count > 6 { root = String(root.prefix(5)) }
        var tail = r.pick(endings)
        if let l = root.last?.lowercased(), let f = tail.first?.lowercased(), l == f { tail.removeFirst() }
        return root + tail
    }

    // MARK: Premises

    static let premisesWords = ["Properties", "Estates", "Commercial", "Real Estate", "Holdings", "Property Group"]

    /// Five places to rent (the original's `PL_TIERS`), from a back street unit to a central location; a new list every half year. Original: `premListings`.
    public static func listings(for co: Company, _ bd: Trade, _ w: World) -> [Listing] {
        if PremisesExtras.isHomeTrade(bd) { return PremisesExtras.listings(co, bd, w) }   // a trade that started at home looks for a workshop or office
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
            let landlord = country.companyNameStarts.isEmpty ? "Nova" : country.companyNameStarts[Int((r.next() * Double(country.companyNameStarts.count)).rounded(.down))]
            let word = premisesWords[Int((r.next() * Double(premisesWords.count)).rounded(.down))]
            return Listing(index: i, name: foot ? t[0].string : tiersB[i].string, squareMetres: m2, rentFactor: rentF, location: t[3].double, landlord: landlord + " " + word)
        }
    }

    public enum PremisesResult: Equatable { case ok, notEnoughCash, bad }

    /// What a listing costs: rent a year per m², monthly rent, the 3-month deposit, fit-out, and (if bought) the price and the down payment.
    public struct PremisesTerms: Equatable {
        public var rentPerM2Year: Double
        public var monthlyRent: Double
        public var deposit: Double
        public var fitOut: Double
        public var purchasePrice: Double
        public var downPayment: Double
        public var squareMetres: Double
    }

    /// Terms of renting or buying a listing. Rent is per m² per year, adjusted for the city, the listing and inflation since the start.
    public static func premisesTerms(_ co: Company, _ listing: Listing, data: GameData, world w: World) -> PremisesTerms? {
        guard let bd = data.catalog[co.type], let kind0 = bd.premisesKind, case let kind = PremisesExtras.isHomeTrade(bd) ? PremisesExtras.placeKind(bd) : kind0,
              let P = data.catalog.tables.premises[kind], let city = w.city(co) else { return nil }
        let m2 = listing.squareMetres
        let rent0 = P.rentPerM2Year * listing.rentFactor * city.rent * w.inflationIndex
        let rent = m2 > 0 ? w.currency(co).tidy(rent0 * m2 / 12) * 12 / m2 : w.currency(co).tidy(rent0)
        let fit = (data.catalog.tables.fitOut[kind] ?? 0) * m2
        let price = jsRound(P.pricePerM2 * listing.rentFactor * pow(city.rent, 0.9) * m2 * w.economy.housing)
        return PremisesTerms(rentPerM2Year: rent, monthlyRent: rent * m2 / 12, deposit: rent * m2 / 12 * 3, fitOut: fit, purchasePrice: price, downPayment: price * 0.35, squareMetres: m2)
    }

    /// Rent (or buy, with a commercial mortgage: 35% down, 15 years) premises. A deposit on the place being left is returned.
    /// Original: `setPrem`.
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
        // The deposit of the place being left comes back first.
        let old = s.companies[i].value("prem")
        let refund = old["dep"].double > 0 && !old["owned"].bool ? old["dep"].double : 0
        let co = s.companies[i]
        // A franchise unit with the franchisor's building: 15 % off the rent and no deposit. Original: `setPrem` (`franchise.bld`).
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
            if let li = s.loans.firstIndex(where: { $0.id == loanID }) { s.loans[li].isGuaranteed = co.form != .limited }
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

    // MARK: Equipment and vehicles

    /// Price of one piece of equipment today. Original: `eqPrice` (standard class, no brand discount).
    public static func equipmentPrice(_ e: EquipmentSpec, company co: Company, _ w: World) -> Double {
        let raw = (e.cost * w.inflationIndex * w.country(co).costIndex).rounded()
        let fx = w.rates.rate(w.country(co))
        return Currency.nicePrice(raw / fx) * fx
    }

    /// How many of each piece a company of this size needs. Original: `stdEq`.
    public static func standardEquipment(_ bd: Trade, size: Double) -> [String: Double] {
        var out: [String: Double] = [:]
        for e in bd.equipment where e.standardCount > 0 { out[e.id] = max(1, jsRound(e.standardCount * size)) }
        return out
    }

    /// People a company of this size normally employs. Original: `stdStaff` (+ small-firm step).
    public static func standardStaff(_ bd: Trade, size: Double) -> [(role: String, count: Int)] {
        var base: [(role: String, count: Int)] = bd.standardStaff.map { (role: $0.role, count: Int(max(1, jsRound($0.count * size)))) }
        if size <= 0.6 {
            base = bd.standardStaff.enumerated().map { (i, s) in (role: s.role, count: i == 0 ? Int(max(1, jsRound(s.count * size))) : Int(max(0, jsRound(s.count * size)))) }
        }
        return base
    }

    @discardableResult
    public static func buyEquipment(_ s: inout GameState, companyID: Int, equipmentID: String, quantity q: Double, data: GameData, preferFinancing: Bool = false) -> Bool {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type], let e = bd.equipment.first(where: { $0.id == equipmentID }) else { return false }
        let w = World(state: s, data: data)
        let co = s.companies[i]
        if let model = e.vehicleModels?.first, let v = data.catalog.tables.vehicles[model] {
            for _ in 0..<Int(q) {
                let price = jsRound(roundTo(v.price * w.inflationIndex, step: 1000))
                // Like a real firm (and the original's autoSetup): buy outright when the cash is there, otherwise finance with
                // 20% down and a five-year loan secured on the vehicle, otherwise lease. Original: `buyVehCore`.
                let cash = s.companies[i].cash
                let mode = cash >= price && !(preferFinancing && cash < price * 3) ? "own" : cash >= price * 0.2 ? "fin" : "lease"
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

    /// Put bought equipment into the company's books: the record, its units, the brand's output and reliability. The money has
    /// been paid already. Used by the standard purchase and by the equipment market. Original: `setupEqRec`.
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

    /// Add one vehicle: paid for in full (`own`), on a loan with 20% down (`fin`) or leased (`lease`). The first payment is made here.
    /// Returns false when the money for it is not there. Original: `buyVehCore`.
    static func addVehicle(_ s: inout GameState, companyIndex i: Int, _ e: EquipmentSpec, model: String, modelName: String, price: Double, mode: String,
                           brand: EquipmentMarket.Brand?, data: GameData) -> Bool {
        let companyID = s.companies[i].id
        var loanID = 0, lease = 0.0, bookValue = price
        let name = brand?.name ?? modelName
        switch mode {
        case "own":
            if s.companies[i].cash < price { return false }
            Payments.companyPays(&s, companyID: companyID, amount: price, category: nil, label: name)
        case "fin":
            if s.companies[i].cash < price * 0.2 { return false }
            Payments.companyPays(&s, companyID: companyID, amount: price * 0.2, category: nil, label: "Down payment: \(name)")
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

    // MARK: Creating a company

    /// Create a company in the setup state. The legal form decides liability and tax: a limited company needs share
    /// capital and a registration fee and an accountant; a sole trader needs none but is personally liable.
    public static func create(_ s: inout GameState, tradeID: String, cityID: String, form: LegalForm, size: Double? = nil, name: String? = nil,
                              countryCode: String? = nil, accountantID: Int? = nil, data: GameData, context: FinanceContext) -> Result<Int, StartError> {
        guard let bd = data.catalog[tradeID] else { return .failure(.notAllowedHere) }
        let code = countryCode ?? s.homeCountryCode
        guard let country = data.countries[code], let city = country.city(cityID) ?? country.cities.first else { return .failure(.notAllowedHere) }
        if let reason = banReason(tradeID, country: country) { return .failure(.banned(reason)) }
        let currency = context.currency(code, s)
        let abroad = code != s.homeCountryCode
        let abroadFee = abroad ? Luxury.abroadFee(Ambitions.abroadFee(context.currency(code, s).scaledPrice(220000 + bd.openingCost * 1.5), s, data), s) : 0
        if abroad && s.cash < abroadFee + currency.scaledPrice(50000) { return .failure(.notEnoughCash) }
        if form == .limited && s.cash < country.shareCapitalMinimum + country.registrationFee + abroadFee { return .failure(.notEnoughCash) }
        let chosenSize = size ?? recommendedSize(bd, city: city)
        var co = Company(raw: [:])
        co.id = s.makeID()
        co.type = tradeID; co.countryCode = code
        co.name = name ?? generateName(country: country, family: bd.family, &s.random)
        co.cityID = city.id; co.form = form; co.size = chosenSize; co.status = .setup
        co.foundedWeek = s.week; co.openedWeek = nil; co.cash = 0; co.ownership = 100
        co.set("holders", .array([])); co.set("docs", .object([:])); co.set("eq", .object([:])); co.set("veh", .array([])); co.set("lease", .object([:]))
        co.set("staff", .array([])); co.set("mgrWage", 0); co.set("mgrBonus", 0)
        co.set("auth", .object(["lvl": 0, "buy": .number(currency.scaledPrice(25000)), "hire": .number(currency.scaledPrice(8000)), "ad": .number(currency.scaledPrice(3000))]))
        co.set("region", 0); co.set("mkt", .object([:])); co.awareness = 25
        var knob: [String: JSONValue] = [:]
        for k in bd.knobs { knob[k.id] = .number(Double(k.defaultIndex)) }
        co.set("knob", .object(knob))
        co.priceLevel = 0; co.ownerHours = 40; co.reputation = 45; co.quality = 45; co.ownerSkill = 40; co.maintenance = 1
        co.set("stockPol", 1); co.set("bid", 1); co.set("prem", .null); co.set("recv", .array([]))
        co.set("pay", .object(["wages": 0, "other": 0, "tax": 0, "rent": 0])); co.vatBalance = 0; co.inventory = 0
        co.books = Books(); co.set("hist", .array([])); co.set("mods", .array([])); co.set("tx", .array([]))
        co.set("ins", .object([:])); co.set("flags", .object([:])); co.set("fm", .object([:]))
        co.set("lossCarry", 0); co.set("dist", 0); co.set("capital", 0); co.set("inj", 0); co.set("ownerSalary", 0)
        co.set("unitsW", 0); co.set("mgrQ", 0); co.set("eqc", 1); co.set("books", 0.5); co.set("group", 0)
        // What the owner's own work would cost to replace: a buyer has to pay someone to do it. Used to value the company.
        if let role = bd.standardStaff.first?.role, let base = data.catalog.tables.roles[role]?.baseMonthlyWage, bd.ownerFTE > 0 {
            co.set("ownWage", .number(jsRound(Wages.market(baseMonthlyWage: base, country: country, city: city, economy: s.economy, rates: World(state: s, data: data).rates))))
        }
        // A brand-new name is known only to friends and family.
        co.awareness = min(co.awareness, 10)
        s.companies.append(co)
        let i = s.companies.count - 1
        let id = co.id
        if form == .limited {
            Payments.playerPays(&s, country.registrationFee, label: "Registration of \(co.name)", companyID: id)
            Payments.playerPays(&s, country.shareCapitalMinimum, label: "Share capital", companyID: id)
            Ledger.moveRaw(&s, .company(id), country.shareCapitalMinimum)
            s.companies[i].ownerNetFlow += country.shareCapitalMinimum
            s.companies[i].shareCapital = country.shareCapitalMinimum
            s.companies[i].injectedCapital += country.shareCapitalMinimum
            s.companies[i].addTransaction(week: s.week, amount: country.shareCapitalMinimum, label: "Share capital paid in")
            chooseAccountant(&s, companyID: id, accountantID: accountantID, data: data)
        }
        if abroad { Payments.playerPays(&s, abroadFee, label: "Local representative, travel and legal counsel abroad", companyID: id) }
        // The owner works there within the hours they have left.
        let used = CapacityModel.ownerHoursCommitted(s, except: id)
        let hours = max(0, (min(s.companies[i].ownerHours, 80 - used, max(10, 55 - used)) / 5).rounded(.down) * 5)
        s.companies[i].ownerHours = hours
        return .success(id)
    }

    /// Give up rented or owned premises and work from home again: an owned place is sold at its value and the mortgage paid off,
    /// a rented one returns the deposit. Original: `ACT.home37`.
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

    static func chooseAccountant(_ s: inout GameState, companyID: Int, accountantID: Int?, data: GameData) {
        guard let i = s.companyIndex(companyID) else { return }
        let pool = Providers.pool(for: s.companies[i].countryCode, state: &s, countries: data.countries).accountants
        guard let a = pool.first(where: { $0["id"].int == accountantID }) ?? (pool.count > 1 ? pool[1] : pool.first) else { return }
        s.companies[i].set("acc", .object(["id": a["id"], "name": a["name"], "tier": a["tier"], "fee": a["fee"], "q": a["q"], "err": a["err"], "rating": a["rating"], "w0": .number(Double(s.week))]))
        var docs = s.companies[i].value("docs")
        docs["accountant_agreement"] = .object(["st": "ok", "done": .number(Double(s.week)), "ok": .number(Double(s.week))])
        s.companies[i].set("docs", docs)
    }

    // MARK: Cost estimate

    public struct Estimate: Equatable {
        public var documents = 0.0, equipment = 0.0, vehicles = 0.0, premises = 0.0, stock = 0.0, firstPayroll = 0.0, buffer = 0.0
        /// Down payment and fees on a first property (rental businesses).
        public var property = 0.0
        public var registration = 0.0, shareCapital = 0.0, abroad = 0.0
        /// Wages and rent paid while a long licence is awaited (original: `r.wait` in `setupEstimate`)
        public var wait = 0.0
        public var total: Double { documents + equipment + vehicles + premises + stock + firstPayroll + buffer + property + registration + abroad + wait }
        /// Money that must be in the player's account first (registration, capital) plus money to put in the company
        public var personalOutlay: Double { registration + shareCapital + abroad }
    }

    /// What it takes to start this business, on the new-company screen. Original: `setupEstimate`.
    public static func estimate(tradeID: String, cityID: String, form: LegalForm, size: Double, countryCode: String? = nil, state s: GameState, data: GameData) -> Estimate? {
        guard let bd = data.catalog[tradeID] else { return nil }
        let code = countryCode ?? s.homeCountryCode
        guard let country = data.countries[code], let city = country.city(cityID) ?? country.cities.first else { return nil }
        var tmp = s
        let cx = FinanceContext(countries: data.countries, trades: data.catalog)
        let result = create(&tmp, tradeID: tradeID, cityID: city.id, form: form, size: size, name: "tmp", countryCode: code, data: data, context: cx)
        guard case .success(let id) = result, let i = tmp.companyIndex(id) else { return nil }
        let co = tmp.companies[i]
        let w = World(state: tmp, data: data)
        var r = Estimate()
        var vehicleFull = 0.0, monthlyRent = 0.0
        for d in Documents.needed(co, bd, w) where d != "vat_not_applicable" && d != "accountant_agreement" { r.documents += Documents.cost(d, company: co, bd, w) }
        let need = standardEquipment(bd, size: size)
        for e in bd.equipment {
            let q = need[e.id] ?? (e.isRequired ? 1 : 0)
            if q <= 0 { continue }
            if let model = e.vehicleModels?.first {
                let price = data.catalog.tables.vehicles[model]?.price ?? 300000
                r.vehicles += price * q * w.inflationIndex * 0.2
                vehicleFull += price * q
            } else { r.equipment += equipmentPrice(e, company: co, w) * q }
        }
        if let kind = bd.premisesKind, let P = data.catalog.tables.premises[kind], bd.premisesM2 > 0 {
            let m2 = jsRound(bd.premisesM2 * size)
            let rent = P.rentPerM2Year * city.rent * w.inflationIndex
            r.premises = rent * m2 / 12 * 3 + (data.catalog.tables.fitOut[kind] ?? 0) * m2
            monthlyRent = rent * m2 / 12
        }
        r.stock = OpeningChecklist.initialStockCost(co, bd, w)
        for (i, st) in bd.standardStaff.enumerated() {
            let n = (i == 0 && bd.ownerFTE >= 1) ? max(0, st.count - 1) : st.count
            let base = data.catalog.tables.roles[st.role]?.baseMonthlyWage ?? 40000
            r.firstPayroll += n * Wages.market(baseMonthlyWage: base, country: country, city: city, economy: s.economy, rates: w.rates) * country.employerCostFactor
        }
        r.buffer = bd.weeklyFixedCosts * 6 * pow(size, 0.9) * city.rent * 0.5 + SpecialFamilies.extraStartupBuffer(bd, size: size, country: country)
        RentalFinance.addEstimate(&r, bd, size: size, city: city, currency: w.currency(co), tmp, w)
        // Contractors wait weeks for the first jobs and the first payments: a bigger cash buffer. Original: `setupEstimate` step.
        if bd.family == "project" && !bd.hasTrait("dev") { r.buffer *= 3.5 }
        // Months spent waiting for a licence cost wages and rent too (a wait of more than 8 weeks). Original: `r.wait`.
        let longest = Documents.needed(co, bd, w).compactMap { Documents.definition($0, country: country, tables: data.catalog.tables)?.weeks }.max() ?? 0
        if longest > 8 { r.wait = (r.firstPayroll + monthlyRent + vehicleFull * 0.012) * Double(longest - 4) / 4.33 * 1.15 }
        let cur = Currency(country: country, rates: w.rates)
        func round(_ v: Double) -> Double { v == 0 ? 0 : Currency.nicePrice(v / cur.rate) * cur.rate }
        r.documents = round(r.documents); r.equipment = round(r.equipment); r.vehicles = round(r.vehicles); r.premises = round(r.premises)
        r.stock = round(r.stock); r.firstPayroll = round(r.firstPayroll); r.buffer = round(r.buffer); r.property = round(r.property); r.wait = round(r.wait)
        if form == .limited { r.registration = country.registrationFee; r.shareCapital = country.shareCapitalMinimum }
        if code != s.homeCountryCode { r.abroad = Luxury.abroadFee(Ambitions.abroadFee(cur.scaledPrice(220000 + bd.openingCost * 1.5), s, data), s) }
        return r
    }

    // MARK: Quick setup

    /// Do everything a company needs to open with sensible standard choices: apply for all documents, rent a
    /// standard place, buy the standard equipment, hire the standard team. It then opens by itself once the
    /// paperwork is approved. Returns what could not be done (usually: not enough cash). Original: `autoSetup`.
    /// The original makes one offer to the median-priced candidate per job and does not retry a refusal; the app retries and picks the
    /// best value. `faithfulHiring` switches to the original's way (used only by the statistical comparison tests).
    public static func quickSetup(_ s: inout GameState, companyID: Int, data: GameData, faithfulHiring: Bool = false) -> [String] {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type] else { return ["unknown company"] }
        var log: [String] = []
        let w = World(state: s, data: data)
        for d in Documents.needed(s.companies[i], bd, w) where d != "vat_not_applicable" {
            let st = s.companies[i].value("docs")[d]["st"].string
            if st == "ok" || st == "applied" { continue }
            let r = Documents.apply(d, companyID: companyID, state: &s, data: data)
            if r != .ok && r != .alreadyHeld { log.append("document \(d): \(r)") }
        }
        if let kind = bd.premisesKind, kind != "none", kind != "home", s.companies[i].value("prem").isNull {
            let ls = listings(for: s.companies[i], bd, World(state: s, data: data))
            if ls.count > 2 {
                let r = setPremises(&s, companyID: companyID, listing: ls[2], data: data)
                if r != .ok { log.append("premises: \(r)") }
            }
        }
        let need = standardEquipment(bd, size: s.companies[i].size)
        // Fixed equipment first, vehicles last: vehicles can be financed or leased, a counter cannot.
        for e in bd.equipment.filter({ $0.vehicleModels == nil }) + bd.equipment.filter({ $0.vehicleModels != nil }) {
            let q = need[e.id] ?? (e.isRequired ? 1 : 0)
            if q <= 0 { continue }
            var qq = q
            var ok = buyEquipment(&s, companyID: companyID, equipmentID: e.id, quantity: qq, data: data, preferFinancing: true)
            while !ok && qq > 1 { qq = max(1, (qq / 2).rounded(.down)); ok = buyEquipment(&s, companyID: companyID, equipmentID: e.id, quantity: qq, data: data, preferFinancing: true) }
            if !ok { log.append("equipment \(e.id): not enough cash") }
        }
        RentalFinance.buyFirstProperty(&s, companyID: companyID, data: data, log: &log)
        if !bd.hasTrait("noStaff") && bd.family != "rent" {
            for (idx, st) in standardStaff(bd, size: s.companies[i].size).enumerated() {
                let have = s.companies[i].staff.filter { $0.role == st.role }.count
                var n = st.count - have
                if idx == 0 && bd.ownerFTE >= 1 && s.companies[i].managerID == nil && s.companies[i].ownerHours >= 20 { n = max(0, n - 1) }
                var attempts = 0; let allowed = faithfulHiring ? max(0, n) : 6
                // faithfulHiring (balance comparison with the original only): one offer to the median-priced candidate, no retry.
                while n > 0 && attempts < allowed {
                    attempts += 1
                    let found = Hiring.search(role: st.role, company: s.companies[i], mode: .network, state: &s, data: data)
                    guard !found.isEmpty else { break }
                    if faithfulHiring {
                        let cands = found.sorted { $0.askingMonthlyWage < $1.askingMonthlyWage }
                        let pick = cands[cands.count / 2]
                        let offer = w.currency(s.companies[i]).roundedStep(pick.askingMonthlyWage * 1.02, about: 100)
                        if Hiring.hire(pick.id, into: companyID, monthlyWage: offer, state: &s, data: data) == .ok { n -= 1 }
                    } else if AutoHire.hireWorker(role: st.role, companyID: companyID, candidates: found, state: &s, data: data) != nil { n -= 1 }
                }
                if n > 0 { log.append("hire \(st.role): \(n) missing") }
            }
        }
        RentalFinance.finishSetup(&s, companyID: companyID, data: data)
        return log
    }
}
