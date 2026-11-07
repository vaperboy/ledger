import Foundation
import GameCore
import Countries
import Employees
import Finance

/// One car of a new-car dealership as the player sees it: in the showroom, on order, or on order and already reserved by a customer.
public struct CarDealerRow: Sendable, Identifiable, Equatable {
    public enum Status: String, Sendable { case inStock, onOrder, reserved }
    public var id: Int
    public var status: Status
    public var brand: String
    public var title: String
    public var body: String
    public var listPrice: Double
    public var cost: Double
    public var askingPrice: Double
    /// Weeks in the showroom (in stock) or weeks until it arrives (on order).
    public var weeks: Int
    /// Asking price minus what the car cost: what the sale would earn today, negative when it would lose money.
    public var profit: Double { askingPrice - cost }
    public var profitPercent: Double { cost > 0 ? profit / cost * 100 : 0 }
}

/// One car the dealership can order right now, at what it would cost.
public struct CarDealerOffer: Sendable, Identifiable, Equatable {
    public var id: String { brandID + ":" + modelID }
    public var brandID: String
    public var brandName: String
    public var modelID: String
    public var modelName: String
    public var body: String
    public var fuel: String
    public var listPrice: Double
    public var cost: Double
    public var leadWeeks: Int
}

/// The new-car dealership (trade `cardealer`). Like the used dealer, nothing arrives on its own: cars are ordered from a supplier, arrive
/// after a delivery time, are paid on delivery and sit on the balance sheet at cost until a customer buys them.
///
/// Supplier: the generic distributor (any brand, margin 4 percent of list, no strings) or one brand under a contract (`CarBrandContract`:
/// a dealer margin of about 5 to 10 percent incl. the yearly volume bonus, only that brand, minimum standards, yearly review, renewal).
/// A buyer (or a manager) orders for you when the showroom runs thin and haggles the distributor price down a little; without either you
/// order by hand. Shoppers pick the best value of up to three cars; a car on order can be reserved by a customer who then waits for it.
///
/// Saved on the company as `cd` (only once the dealership has ordered or signed): `cars`, `orders`, `con` (see `CarBrandContract`).
/// A car: id, b (brand), m (model), name, list, cost, ask (when the player set one), wk (week it arrived), fair (market value), rsv (reserved).
/// An order: id, b, m, name, list, cost, due (week), res (a customer reserved it).
public enum CarDealer {
    public static let tradeID = "cardealer"
    /// Square metres of showroom, lot and handover area one car needs.
    static let m2PerSpace = 60.0
    /// Weekly cost of holding stock (floor-plan interest, insurance, cleaning), share of its value.
    static let holding = 0.0012
    /// Weekly fall in a car's market value once it has stood for a quarter.
    static let depreciation = 0.003
    /// Most cars a shopper compares.
    static let looks = 3

    // MARK: Reading

    /// Cars the premises hold: showroom, lot and handover area.
    public static func spaces(_ co: Company, _ bd: Trade) -> Int {
        let m2 = co.value("prem")["m2"].double
        let base = m2 > 0 ? m2 : bd.premisesM2 * co.size
        return max(1, Int(base / m2PerSpace))
    }

    /// The list price of an average new car today (the trade's ticket, with local prices and inflation).
    public static func listTicket(_ co: Company, _ bd: Trade, _ s: GameState, _ data: GameData) -> Double {
        Pricing.ticket(co, bd, World(state: s, data: data), withItems: false)
    }

    /// Cars a dealership keeps in the showroom and on order for its demand (about six weeks of shoppers, at least three, never more than three
    /// quarters of its spaces). The buyer orders up to this, and the start-up plan counts it as the stock the owner has to pay for.
    static func wantedCars(_ co: Company, _ bd: Trade, demand D: Double) -> Int {
        max(3, min(Int(Double(spaces(co, bd)) * 0.75), Int((D * 6).rounded(.up))))
    }

    /// The money the dealership needs for its cars before it sells: the wanted cars at the distributor's price. A new dealership opens with an
    /// empty showroom (every car is ordered and paid on delivery), so this is working capital the plan must show, not stock bought at opening.
    public static func stockBudget(_ co: Company, _ bd: Trade, _ s: GameState, _ data: GameData) -> Double {
        let w = World(state: s, data: data)
        let cars = wantedCars(co, bd, demand: DemandModel.compute(co, bd, w).customers)
        return jsRound(Double(cars) * listTicket(co, bd, s, data) * (1 - CarBrands.distributorMargin))
    }

    public static func carsInShowroom(_ co: Company) -> Int { co.value("cd")["cars"].array.count }
    public static func carsOnOrder(_ co: Company) -> Int { co.value("cd")["orders"].array.count }
    public static func spacesFree(_ co: Company, _ bd: Trade) -> Int { max(0, spaces(co, bd) - carsInShowroom(co) - carsOnOrder(co)) }

    /// A buyer on the payroll, or a manager, orders for the dealership.
    public static func hasBuyer(_ co: Company) -> Bool {
        co.staff.contains { $0.role == "buyer" } || (co.managerID != nil && co.status == .open)
    }

    /// How much off the distributor's price a buyer gets, from the best buyer's skill (0 without one; a manager counts as skill 40).
    static func buyerEdge(_ co: Company, _ s: GameState, _ data: GameData) -> Double {
        let roles = data.catalog.tables.salesRoles
        var best = co.managerID != nil ? 40.0 : 0
        for m in co.staff where m.role == "buyer" { best = max(best, StaffModel.skill(m, person: s.people[m.id], salesRoles: roles)) }
        return best / 100 * 0.012
    }

    /// The list price of a model for this dealership.
    static func list(_ model: CarModel, _ co: Company, _ bd: Trade, _ s: GameState, _ data: GameData) -> Double {
        Currency.nicePrice(listTicket(co, bd, s, data) * model.factor)
    }

    /// Everything that can be ordered now: with a brand contract only that brand's range at the contract margin, else every brand's range
    /// from the distributor.
    public static func offers(_ co: Company, _ s: GameState, _ data: GameData) -> [CarDealerOffer] {
        guard let bd = data.catalog[tradeID] else { return [] }
        let con = CarBrandContract.active(co, s, data)
        let edge = buyerEdge(co, s, data)
        let brands = con.map { [$0.brand] } ?? CarBrands.forCountry(co.countryCode)
        let margin = con?.margin ?? (CarBrands.distributorMargin + edge)
        let lead = CarBrands.leadWeeks(brandContract: con != nil)
        return brands.flatMap { b in
            b.models.map { m -> CarDealerOffer in
                let l = list(m, co, bd, s, data)
                return CarDealerOffer(brandID: b.id, brandName: b.name, modelID: m.id, modelName: m.name, body: m.body, fuel: m.fuel, listPrice: l,
                                      cost: jsRound(l * (1 - margin)), leadWeeks: (lead.0 + lead.1 + 1) / 2)
            }
        }
    }

    /// The supplier line for the screen: the brand's name under a contract, else the distributor.
    public static func supplierName(_ co: Company) -> String {
        if let b = CarBrandContract.brandID(co), let brand = CarBrands.brand(b) { return brand.name }
        return CarBrands.distributorName
    }

    static func brandStrength(_ id: String) -> Double { CarBrands.brand(id)?.strength ?? 60 }

    /// Showroom cars and cars on order, newest orders last.
    public static func rows(_ co: Company, week: Int) -> [CarDealerRow] {
        let cd = co.value("cd")
        let cars = cd["cars"].array.map { c -> CarDealerRow in
            CarDealerRow(id: c["id"].int, status: .inStock, brand: c["b"].string, title: c["name"].string, body: bodyOf(c), listPrice: c["list"].double, cost: c["cost"].double,
                         askingPrice: c["ask"].isNull ? c["list"].double : c["ask"].double, weeks: max(0, week - c["wk"].int))
        }
        let orders = cd["orders"].array.map { o -> CarDealerRow in
            CarDealerRow(id: o["id"].int, status: o["res"].bool ? .reserved : .onOrder, brand: o["b"].string, title: o["name"].string, body: bodyOf(o), listPrice: o["list"].double,
                         cost: o["cost"].double, askingPrice: o["list"].double, weeks: max(0, o["due"].int - week))
        }
        return cars + orders
    }

    static func bodyOf(_ c: JSONValue) -> String { CarBrands.brand(c["b"].string)?.models.first { $0.id == c["m"].string }?.body ?? "" }

    // MARK: Actions

    /// Order one car. Returns why not, or nil when it is ordered (paid on delivery). Needs a free space and a supplier that sells it.
    public static func order(_ s: inout GameState, companyID: Int, brandID: String, modelID: String, data: GameData) -> String? {
        guard let i = s.companyIndex(companyID), s.companies[i].type == tradeID, let bd = data.catalog[tradeID] else { return "Only a vehicle dealership orders cars." }
        let co = s.companies[i]
        guard co.status == .open else { return "The dealership is not open." }
        guard spacesFree(co, bd) > 0 else { return "No free space: the showroom and lot are full (\(spaces(co, bd)) spaces, cars on order count)." }
        if let b = CarBrandContract.brandID(co), b != brandID { return "Your brand contract with \(CarBrands.brand(b)?.name ?? b) means cars can only be ordered from the brand." }
        guard let offer = offers(co, s, data).first(where: { $0.brandID == brandID && $0.modelID == modelID }) else { return "That car is not on offer." }
        placeOrder(&s, i, offer)
        return nil
    }

    static func placeOrder(_ s: inout GameState, _ i: Int, _ offer: CarDealerOffer) {
        let id = s.makeID()
        var r = HashedRandom("cdlead:\(s.seed):\(s.companies[i].id):\(id)")
        let lead = CarBrands.leadWeeks(brandContract: CarBrandContract.isActive(s.companies[i]))
        let weeks = lead.0 + Int(r.next() * Double(lead.1 - lead.0 + 1))
        var cd = s.companies[i].value("cd")
        var orders = cd["orders"].array
        orders.append(.object(["id": .number(Double(id)), "b": .string(offer.brandID), "m": .string(offer.modelID), "name": .string(offer.brandName + " " + offer.modelName),
                               "list": .number(offer.listPrice), "cost": .number(offer.cost), "due": .number(Double(s.week + min(lead.1, weeks)))]))
        cd["orders"] = .array(orders)
        s.companies[i].set("cd", cd)
    }

    /// Set the asking price of a car in the showroom (any positive price).
    public static func setAsk(_ s: inout GameState, companyID: Int, carID: Int, price: Double) -> Bool {
        guard let i = s.companyIndex(companyID), s.companies[i].type == tradeID, price.isFinite, price > 0 else { return false }
        var cd = s.companies[i].value("cd")
        var cars = cd["cars"].array
        guard let k = cars.firstIndex(where: { $0["id"].int == carID }) else { return false }
        cars[k]["ask"] = .number(price)
        cd["cars"] = .array(cars)
        s.companies[i].set("cd", cd)
        return true
    }

    // MARK: Week

    /// How likely a shopper is to buy at this ratio of asking price to the car's worth to them.
    static func accept(_ ratio: Double) -> Double { 1 / (1 + exp((ratio - 1.03) / 0.05)) }

    static func week(_ s: inout GameState, _ i: Int, _ bd: Trade, _ data: GameData) -> CompanyWeek.WeekContext {
        let w = World(state: s, data: data)
        var co = s.companies[i]
        let id = co.id
        let D = DemandModel.compute(co, bd, w).customers
        let cap = CapacityModel.compute(co, bd, w).capacity
        var rnd = HashedRandom("cdeal:\(s.seed):\(s.week):\(id)")
        CarBrandContract.week(&s, i, bd, data)
        if co.status == .open, hasBuyer(s.companies[i]) { autoOrder(&s, i, bd, data, demand: D, random: &rnd) }
        deliver(&s, i)
        co = s.companies[i]
        var dd = co.value("cd")
        var list = dd["cars"].array
        // Shoppers.
        var shoppers = Int(D)
        if rnd.next() < D - Double(Int(D)) { shoppers += 1 }
        var units = 0.0, rev = 0.0, cogs = 0.0
        let room = Int(cap.rounded(.down)) + (rnd.next() < cap - cap.rounded(.down) ? 1 : 0)
        func ask(_ c: JSONValue) -> Double { c["ask"].isNull ? c["list"].double : c["ask"].double }
        func ratio(_ c: JSONValue) -> Double {
            let fair = c["fair"].isNull ? c["list"].double : c["fair"].double
            return ask(c) / max(1, fair * (0.92 + brandStrength(c["b"].string) / 100 * 0.16))
        }
        /// The add-ons (warranty, loan, insurance) are decided per sale; a bank that declines can lose the sale (the car stays in the showroom).
        @discardableResult
        func sell(_ k: Int) -> Bool {
            let c = list[k]
            let price = ask(c)
            s.companies[i] = co
            let r = DealerAddons.apply(&s, companyID: id, sale: DealerSale(key: "cd:\(c["id"].int)", price: price, car: .new(title: c["name"].string)), data: data)
            co = s.companies[i]
            guard r.saleCompleted else { return false }
            list.remove(at: k)
            rev += price; cogs += c["cost"].double; units += 1
            CarBrandContract.recordSale(&co, brand: c["b"].string, list: c["list"].double)
            return true
        }
        // A car that arrived already reserved goes to its customer first, if the price still suits them.
        for k in list.indices.reversed() where list[k]["rsv"].bool && Int(units) < room {
            if rnd.next() < accept(ratio(list[k])) { if !sell(k) { list[k] = JSONValue.object(list[k].object.filter { $0.key != "rsv" }) } } else { list[k] = JSONValue.object(list[k].object.filter { $0.key != "rsv" }) }
        }
        var orders = dd["orders"].array
        for _ in 0..<shoppers where Int(units) < room {
            let open = orders.indices.filter { !orders[$0]["res"].bool }
            let pool = list.count + open.count
            guard pool > 0 else { break }
            var best = -1, bestRatio = Double.infinity
            for _ in 0..<min(looks, pool) {
                let n = min(pool - 1, Int(rnd.next() * Double(pool)))
                let c = n < list.count ? list[n] : orders[open[n - list.count]]
                let r = ratio(c)
                if r < bestRatio { bestRatio = r; best = n }
            }
            guard best >= 0, rnd.next() < accept(bestRatio) * (best < list.count ? 1 : 0.8) else { continue }
            if best < list.count { _ = sell(best) } else { orders[open[best - list.count]]["res"] = .bool(true) }
        }
        // Market value of the cars standing in the showroom slips once they are a quarter old.
        for k in list.indices where s.week - list[k]["wk"].int > 13 { list[k]["fair"] = .number(list[k]["fair"].double * (1 - depreciation)) }
        co.inventory = max(0, co.inventory - cogs)
        dd["cars"] = .array(list)
        dd["orders"] = .array(orders)
        co.set("cd", dd)
        // Holding cost, paid with the monthly bills like other stock costs.
        let hold = co.inventory * holding
        var books = co.books
        books.add("cogs", hold)
        co.books = books
        co.addPayable("other", hold)
        s.companies[i] = co
        DealerAddons.weekly(&s, companyIndex: i, data: data)
        let util = cap > 0 ? units / cap : 0
        var ctx = CompanyWeek.WeekContext(units: units, rev: rev, cogs: cogs, D: D, cap: cap, util: util, price: units > 0 ? rev / units : 0, paidDuringWeek: 0)
        ctx.cogsIsAccounting = true
        return ctx
    }

    /// Orders that are due arrive and are paid for. A dealership without the cash leaves them with the supplier until next week.
    static func deliver(_ s: inout GameState, _ i: Int) {
        let id = s.companies[i].id
        var cd = s.companies[i].value("cd")
        var orders = cd["orders"].array
        var cars = cd["cars"].array
        var k = 0
        while k < orders.count {
            let o = orders[k]
            if o["due"].int <= s.week, s.companies[i].cash >= o["cost"].double {
                AccountingLedger.note(category: "cogs", label: "New car delivered: \(o["name"].string)")
                Ledger.moveRaw(&s, .company(id), -o["cost"].double)
                s.companies[i].inventory += o["cost"].double
                var car: [String: JSONValue] = ["id": o["id"], "b": o["b"], "m": o["m"], "name": o["name"], "list": o["list"], "cost": o["cost"], "wk": .number(Double(s.week)), "fair": o["list"]]
                if o["res"].bool { car["rsv"] = .bool(true) }
                cars.append(.object(car))
                orders.remove(at: k)
            } else { k += 1 }
        }
        cd["orders"] = .array(orders)
        cd["cars"] = .array(cars)
        s.companies[i].set("cd", cd)
    }

    /// A buyer or manager orders when the showroom and orders are thin: up to two cars a week, a mix of the models on offer.
    static func autoOrder(_ s: inout GameState, _ i: Int, _ bd: Trade, _ data: GameData, demand D: Double, random rnd: inout HashedRandom) {
        let co = s.companies[i]
        let want = wantedCars(co, bd, demand: D)
        let have = carsInShowroom(co) + carsOnOrder(co)
        guard have < want else { return }
        let menu = offers(co, s, data)
        guard !menu.isEmpty else { return }
        for _ in 0..<min(2, want - have) {
            let cur = s.companies[i]
            guard spacesFree(cur, bd) > 0 else { return }
            let pick = menu[min(menu.count - 1, Int(rnd.next() * Double(menu.count)))]
            guard cur.cash > pick.cost * 2 else { return }
            placeOrder(&s, i, pick)
        }
    }
}
