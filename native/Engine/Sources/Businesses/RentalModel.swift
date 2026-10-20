import Foundation
import GameCore
import Countries
import Employees
import Finance

/// One building (or car park, or block of flats) a rental company owns. Original: `co.props` entries.
public struct Property: JSONRecord, Identifiable {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }

    public var id: Int { get { int("id") } set { set("id", newValue) } }
    public var name: String { get { str("name") } set { set("name", newValue) } }
    /// Flats, square metres or parking/storage spaces, by `kind`.
    public var units: Double { get { num("units") } set { set("units", newValue) } }
    /// "res" (flats), "com" (m2 of commercial space) or "park" (spaces and storage units)
    public var kind: String { get { str("kind") } set { set("kind", newValue) } }
    /// What it cost to buy.
    public var cost: Double { get { num("cost") } set { set("cost", newValue) } }
    /// What it is worth now: follows the housing market and the condition.
    public var value: Double { get { num("val") } set { set("val", newValue) } }
    /// Housing index on the day it was bought.
    public var housingAtPurchase: Double { get { num("idx0", 1) } set { set("idx0", newValue) } }
    /// Mortgage loan id, 0 if none.
    public var loanID: Int { get { int("loan") } set { set("loan", newValue) } }
    /// Rent per unit per week at market level, before the company's own rent policy.
    public var rentPerUnit: Double { get { num("rentU") } set { set("rentU", newValue) } }
    public var vacancy: Double { get { num("vac") } set { set("vac", newValue) } }
    public var condition: Double { get { num("cond") } set { set("cond", newValue) } }
    public var boughtWeek: Int { get { int("w0") } set { set("w0", newValue) } }
    /// Units let on a long lease (commercial property only).
    public var leasedUnits: Double { get { num("lu") } set { set("lu", newValue) } }
    public var leases: [Lease] { get { records("leases") } set { setRecords("leases", newValue) } }
}

/// A tenant on a long lease in a commercial building. Original: `p.leases` entries.
public struct Lease: JSONRecord {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }
    public var name: String { get { str("name") } set { set("name", newValue) } }
    public var squareMetres: Double { get { num("m2") } set { set("m2", newValue) } }
    /// Rent per m2 per week.
    public var weeklyRentPerM2: Double { get { num("rw") } set { set("rw", newValue) } }
    public var untilWeek: Int { get { int("until") } set { set("until", newValue) } }
    /// One of the player's own companies is the tenant.
    public var companyID: Int { get { int("co") } set { set("co", newValue) } }
}

public extension Company {
    var properties: [Property] {
        get { records("props") }
        set { setRecords("props", newValue) }
    }
}

/// A property for sale. Original: `propListings` entries.
public struct PropertyListing: Identifiable, Equatable, Sendable {
    public var id: Int { index }
    public var index: Int
    public var name: String
    public var units: Double
    public var pricePerUnit: Double
    public var price: Double
    public var rentPerUnit: Double
    public var condition: Double
    public var grossYield: Double
}

/// A business that wants to rent space in a commercial building, or buy the building. Original: `propTenants` entries.
public struct TenantOffer: Identifiable, Equatable, Sendable {
    public var id: Int { index }
    public var index: Int
    public var name: String
    public var squareMetres: Double
    public var weeklyRentPerM2: Double
    public var years: Int
    /// Offer for the whole building as a multiple of its value.
    public var buyMultiple: Double
}

/// Residential rentals, commercial property and parking/self-storage: a portfolio of properties with tenants,
/// vacancy, maintenance, mortgages and values that follow the housing market. Original: `FAM.rent`, `propListings`,
/// `buyProp`, `sellProp`, `renovateProp` (engine/company/family_rental.js) and `propTenants`, `leaseTo`, `sellPropTo`.
public enum RentalModel {
    public enum BuyResult: Equatable { case ok, notEnoughCash, loanDeclined, unknown }

    static func kind(_ bd: Trade) -> String { bd.traitText["kind"] ?? "res" }

    // MARK: Listings

    /// Four properties for sale in the company's city, a new list every four weeks. Original: `propListings`.
    public static func listings(_ co: Company, _ bd: Trade, _ w: World) -> [PropertyListing] {
        guard let city = w.city(co) else { return [] }
        let k = kind(bd)
        let seedKey = (w.week >> 2) * 131 + co.id
        var r = DeterministicRandom(state: Int32(truncatingIfNeeded: seedKey &* 2654435761))
        let tUnits = bd.trait("units") ?? 10, tPrice = bd.trait("price") ?? 1_000_000
        let home = homeCurrency(w)
        var out: [PropertyListing] = []
        for (i, f) in [0.35, 0.6, 1, 1.7].enumerated() {
            let units = max(2, jsRound(tUnits * f * r.range(0.85, 1.2)))
            let per = home.roundedStep(tPrice * pow(city.rent, 0.8) * w.economy.housing * r.range(0.9, 1.12), about: 1000)
            let rentU = jsRound((k == "com" ? 1.8 : 1.3) * bd.ticket * pow(city.rent, 0.8) * r.range(0.9, 1.1) * pow(1 + w.economy.inflation, Double(w.week) / 52))
            let label: String
            switch k {
            case "res": label = "Block of \(Int(units)) flats"
            case "com": label = "\(Int(units)) m2 " + r.pick(["office floor", "retail parade", "logistics hall", "mixed building"])
            default: label = "\(Int(units)) " + r.pick(["parking spaces", "storage units", "spaces in a car park"])
            }
            let cond = r.range(0.55, 0.95)
            out.append(PropertyListing(index: i, name: label + ", " + city.name, units: units, pricePerUnit: per, price: per * units,
                                       rentPerUnit: rentU, condition: cond, grossYield: rentU * 52 / per))
        }
        return out
    }

    static func homeCurrency(_ w: World) -> Currency {
        Currency(country: w.countries.resolve(w.state.homeCountryCode, orHome: w.state.homeCountryCode), rates: w.rates)
    }

    // MARK: Buying, selling, renovating

    /// Buy a listing with a mortgage of `ltv` of the price, keeping `reserve` in cash. Original: `buyProp`.
    @discardableResult
    public static func buy(_ s: inout GameState, companyID: Int, listing L: PropertyListing, loanToValue ltv: Double, reserve: Double = 0, data: GameData) -> BuyResult {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type], bd.family == "rent" else { return .unknown }
        let price = L.price, fee = price * 0.025
        let loan = homeCurrency(World(state: s, data: data)).roundedStep(price * ltv, about: 1000)
        let down = price - loan + fee
        if s.companies[i].cash < down + reserve { return .notEnoughCash }
        var loanID = 0
        if loan > 0 {
            // A mortgage up to 60% of the price is always granted; more only within the bank's business-loan limit.
            if loan > price * 0.6 + 1 {
                let nw = Valuation.netWorth(s, trades: data.catalog).total
                let ctx = FinanceContext(countries: data.countries, trades: data.catalog)
                let off = Banking.offer(kind: "biz", amount: loan, company: s.companies[i], state: s, netWorth: nw, context: ctx)
                if loan > max(off.maximum, 0) { return .loanDeclined }
            }
            var l = Loan(raw: [:])
            l.id = s.makeID()
            l.kind = "biz"
            l.name = "Property mortgage"
            l.balance = loan
            l.margin = max(0.012, Banking.creditMargin(s.credit) * 0.45) + 0.003
            l.termMonths = 240
            l.companyID = companyID
            l.startWeek = s.week
            l.isGuaranteed = true
            l.monthlyPayment = Loans.annuity(principal: loan, yearlyRate: s.economy.policyRate + l.margin, months: 240)
            s.loans.append(l)
            Ledger.moveRaw(&s, .company(companyID), loan)
            loanID = l.id
        }
        Payments.companyPays(&s, companyID: companyID, amount: price, category: nil, label: "Property purchase")
        Payments.companyPays(&s, companyID: companyID, amount: fee, category: "oth", label: "Stamp duty and fees")
        var p = Property(raw: [:])
        p.id = s.makeID()
        p.name = L.name; p.units = L.units; p.kind = kind(bd); p.cost = price; p.value = price
        p.housingAtPurchase = s.economy.housing
        p.loanID = loanID; p.rentPerUnit = L.rentPerUnit; p.vacancy = 0.18; p.condition = L.condition
        p.set("city", s.companies[i].cityID); p.boughtWeek = s.week
        var list = s.companies[i].properties
        list.append(p)
        s.companies[i].properties = list
        return .ok
    }

    /// Sell a property on the market (2.5% costs) and repay its mortgage. Returns what the sale brought in. Original: `sellProp`.
    @discardableResult
    public static func sell(_ s: inout GameState, companyID: Int, propertyID: Int) -> Double {
        guard let i = s.companyIndex(companyID), let k = s.companies[i].properties.firstIndex(where: { $0.id == propertyID }) else { return 0 }
        var list = s.companies[i].properties
        let p = list.remove(at: k)
        s.companies[i].properties = list
        let net = jsRound(p.value * 0.975)
        settle(&s, companyID: companyID, property: p, net: net, label: "Property sold", gainBase: p.value)
        return net
    }

    /// Cash in, mortgage out, gain or loss booked. Shared by `sell` and `sell(to:)`.
    static func settle(_ s: inout GameState, companyID: Int, property p: Property, net: Double, label: String, gainBase: Double) {
        Payments.companyReceives(&s, companyID: companyID, amount: net, category: nil, label: label)
        if p.loanID != 0, let l = s.loans.first(where: { $0.id == p.loanID }) {
            let r = l.balance
            Ledger.moveRaw(&s, .company(companyID), -r)
            Banking.close(loanID: l.id, repaid: r, state: &s)
        }
        let gain = net - gainBase
        Payments.book(&s, companyID: companyID, category: gain > 0 ? "rev" : "loss", amount: gain > 0 ? gain : -gain)
    }

    /// Renovate: costs two percent of the reference price per unit, restores condition and adds 1.5% to the value. Original: `renovateProp`.
    @discardableResult
    public static func renovate(_ s: inout GameState, companyID: Int, propertyID: Int, data: GameData) -> BuyResult {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type],
              let k = s.companies[i].properties.firstIndex(where: { $0.id == propertyID }) else { return .unknown }
        var list = s.companies[i].properties
        let cost = jsRound(list[k].units * ((bd.trait("price") ?? 0) * 0.02))
        if s.companies[i].cash < cost { return .notEnoughCash }
        Payments.companyPays(&s, companyID: companyID, amount: cost, category: "oth", label: "Renovation")
        list[k].condition = min(1, list[k].condition + 0.25)
        s.companies[i].add("reval", list[k].value * 0.015)
        list[k].value *= 1.015
        s.companies[i].properties = list
        return .ok
    }

    // MARK: Commercial tenants and buyers

    /// Businesses that want space in this building, or want to buy it; new offers every four weeks. Original: `propTenants`
    /// (the original also offers its franchise brands as tenants; those are not ported, so tenants are local businesses).
    public static func tenants(_ co: Company, property p: Property, _ w: World) -> [TenantOffer] {
        let seed = (w.week >> 2) * 977 + p.id
        var r = DeterministicRandom(state: Int32(truncatingIfNeeded: seed &* 2654435761))
        let free = p.units - p.leasedUnits
        if free < 20 { return [] }
        let trades = w.catalog.all.filter { $0.premisesKind != nil && $0.premisesKind != "none" && $0.premisesKind != "home" && $0.family != "rent" && $0.family != "fin" && $0.family != "energy" }
            .sorted { $0.id < $1.id }
        guard !trades.isEmpty else { return [] }
        let lasts = w.country(co).lastNames
        var out: [TenantOffer] = []
        for i in 0..<3 {
            let bd = r.pick(trades)
            let surname = lasts.isEmpty ? "Nova" : r.pick(lasts)
            let m2 = min(free, jsRound(bd.premisesM2 * r.range(0.7, 1.4) / 10) * 10)
            out.append(TenantOffer(index: i, name: surname + " " + (bd.name.split(separator: " ").first.map(String.init) ?? bd.name),
                                   squareMetres: m2 == 0 ? 20 : m2, weeklyRentPerM2: p.rentPerUnit * r.range(1.0, 1.12),
                                   years: r.int(3, 8), buyMultiple: r.range(1.02, 1.12)))
        }
        return out
    }

    /// Let space in a commercial building on a long lease. Original: `leaseTo`.
    @discardableResult
    public static func lease(_ s: inout GameState, companyID: Int, propertyID: Int, offer o: TenantOffer) -> Bool {
        guard let i = s.companyIndex(companyID), let k = s.companies[i].properties.firstIndex(where: { $0.id == propertyID }) else { return false }
        var list = s.companies[i].properties
        if list[k].units - list[k].leasedUnits < o.squareMetres { return false }
        list[k].leasedUnits += o.squareMetres
        var ls = list[k].leases
        var l = Lease(raw: [:])
        l.name = o.name; l.squareMetres = o.squareMetres; l.weeklyRentPerM2 = o.weeklyRentPerM2; l.untilWeek = s.week + o.years * 52
        ls.append(l)
        list[k].leases = ls
        s.companies[i].properties = list
        return true
    }

    /// Sell the whole building to a buyer who pays more than its value. Original: `sellPropTo`.
    @discardableResult
    public static func sell(_ s: inout GameState, companyID: Int, propertyID: Int, to o: TenantOffer) -> Double {
        guard let i = s.companyIndex(companyID), let k = s.companies[i].properties.firstIndex(where: { $0.id == propertyID }) else { return 0 }
        if s.companies[i].properties[k].leases.contains(where: { $0.companyID != 0 }) { return -1 }
        var list = s.companies[i].properties
        let p = list.remove(at: k)
        s.companies[i].properties = list
        let net = jsRound(p.value * o.buyMultiple)
        settle(&s, companyID: companyID, property: p, net: net, label: "Property sold to \(o.name)", gainBase: p.cost)
        return net
    }

    /// Leases that have run out end, with a note. Original: `leaseClean` (company tenants are part of the franchise feature, not ported).
    static func expireLeases(_ s: inout GameState, _ i: Int) {
        var changed = false
        var list = s.companies[i].properties
        for k in list.indices where !list[k].leases.isEmpty {
            var keep: [Lease] = []
            for l in list[k].leases {
                if l.companyID == 0, s.week >= l.untilWeek {
                    list[k].leasedUnits = max(0, list[k].leasedUnits - l.squareMetres)
                    s.note("A tenant (\(l.name)) left \(list[k].name).", tone: "n", companyID: s.companies[i].id)
                    changed = true
                } else { keep.append(l) }
            }
            if keep.count != list[k].leases.count { list[k].leases = keep }
        }
        if changed { s.companies[i].properties = list }
    }

    // MARK: The week

    /// Rent in, upkeep and property tax out; vacancy, condition and value move. Original: `FAM.rent.custom`.
    static func weekly(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData) -> CompanyWeek.WeekContext {
        expireLeases(&s, i)
        var co = s.companies[i]
        let w = World(state: s, data: data)
        let k = kind(bd)
        let maint = bd.trait("maint") ?? 0.008, ptaxRate = bd.trait("ptax") ?? 0.0025
        var props = co.properties
        let tables = w.catalog.tables
        let people = s.people
        func fte(_ role: String) -> Double {
            StaffModel.fullTimeEquivalents(role: role, staff: co.staff, people: people, week: w.week, salesRoles: tables.salesRoles)
        }
        let totalUnits = props.reduce(0) { $0 + $1.units }
        let need = k == "res" ? totalUnits / 60 : k == "com" ? totalUnits / 4000 : totalUnits / 450
        let staffFTE = fte("caretaker") + fte("propm") * 0.6 + (co.managerID != nil ? 0.3 : co.ownerHours / 40 * 0.5)
        let cover = need > 0 ? clamp(staffFTE / need, 0, 1.4) : 1
        let pr = (1 + 0.08 * co.priceLevel) * Knobs.effect(co, bd, "t", w)
        let dm = DemandModel.modifier(co, "dem")
        let dKnob = Knobs.effect(co, bd, "d", w)
        let mgrQ = co.managerID != nil ? ManagerModel.quality(co, bd, people: people) : 0
        let seasonal = (bd.seasonKey == "study" && k == "res") ? (1 - (tables.seasons["study"]?[GameCalendar.month(week: w.week)] ?? 1)) * 0.012 : 0
        let rivals = w.market(for: co).map { min(0.02, $0["n"].double * 0.0005) } ?? 0
        let housing = w.economy.housing
        let maintIdx = min(2, max(0, co.maintenance))
        var rent = 0.0, units = 0.0, occU = 0.0, upkeep = 0.0, ptax = 0.0
        for n in props.indices {
            var p = props[n]
            let target = clamp(0.03 + 0.28 * (pr - 1) * bd.elasticity + (1 - p.condition) * 0.16 + (1 - w.economy.demand) * 0.6
                               - (co.awareness / 100) * 0.03 - (co.reputation - 50) / 100 * 0.05 + (1 - dm) * 0.8 + (1 - dKnob) * 0.18
                               + (cover < 1 ? (1 - cover) * 0.06 : 0) + seasonal + rivals, 0.01, 0.8)
            p.vacancy += (target - p.vacancy) * 0.12
            let occ = 1 - p.vacancy
            let lu = min(p.leasedUnits, p.units), fu = p.units - lu
            units += p.units
            occU += lu + fu * occ
            rent += p.leases.reduce(0) { $0 + ($1.weeklyRentPerM2 != 0 ? $1.squareMetres * $1.weeklyRentPerM2 : 0) }
            let idx0 = p.housingAtPurchase == 0 ? housing : p.housingAtPurchase
            rent += fu * occ * p.rentPerUnit * pr * (0.93 + 0.07 * p.condition) * pow(housing / idx0, 0.6) * (1 + (co.reputation - 50) / 700)
            upkeep += p.value * maint / 52 * (1.7 - p.condition) * (1.1 - mgrQ * 0.2 * (co.managerID != nil ? 1 : 0))
            ptax += p.value * ptaxRate / 52
            p.condition = clamp(p.condition - 0.0006 * (cover < 1 ? 2 : 1) * [1.5, 1, 0.7][maintIdx], 0.1, 1)
            if maintIdx == 2 { p.condition = clamp(p.condition + 0.0005, 0, 1) }
            let nv = p.cost * (housing / p.housingAtPurchase) * (0.88 + 0.12 * p.condition) * (k == "com" ? (0.92 + 0.08 * (1 - p.vacancy) / 0.9) : 1)
            co.add("reval", nv - p.value)
            p.value = nv
            props[n] = p
        }
        let outsourced = cover < 0.8 && need > 0 ? rent * 0.07 : 0
        co.properties = props
        var fm = co.value("fm")
        fm["assets"] = 0
        fm["cover"] = .number(cover)
        co.set("fm", fm)
        s.companies[i] = co
        let util = units > 0 ? occU / units : 0
        return CompanyWeek.WeekContext(units: occU, rev: rent, cogs: upkeep + ptax + outsourced, D: units, cap: units, util: util, price: bd.ticket, paidDuringWeek: 0)
    }

    // MARK: Events

    /// Effects of events that only a property company understands. Original: `FAM.rent.fx`.
    public static func applyEffects(_ s: inout GameState, _ i: Int, fx: JSONValue, data: GameData) {
        var list = s.companies[i].properties
        if list.isEmpty { return }
        if fx["vacAdd"].double != 0 { for n in list.indices { list[n].vacancy = clamp(list[n].vacancy + fx["vacAdd"].double * 0.02, 0, 0.9) } }
        if fx["vac"].double != 0 { for n in list.indices { list[n].vacancy = clamp(list[n].vacancy + 0.08, 0, 0.9) } }
        s.companies[i].properties = list
        let tenant = fx["tenant"].string
        if !tenant.isEmpty {
            let id = s.companies[i].id
            if tenant == "evict" {
                let cost = Currency(country: data.countries.resolve(s.companies[i].countryCode, orHome: s.homeCountryCode), rates: ExchangeRates(drift: s.exchangeRates.values)).scaledPrice(12000)
                Payments.companyPays(&s, companyID: id, amount: cost, category: "oth", label: "Eviction costs")
                var mods = s.companies[i].value("mods").array
                mods.append(.object(["k": "dem", "m": 0.97, "w": 6]))
                s.companies[i].set("mods", .array(mods))
            } else if tenant == "plan" {
                Payments.book(&s, companyID: id, category: "loss", amount: 4000)
            } else {
                Payments.book(&s, companyID: id, category: "loss", amount: 9000)
            }
        }
    }
}
