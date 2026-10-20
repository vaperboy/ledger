import Foundation
import GameCore
import Countries
import Finance

/// Aurum private sales: cars, watches, art, yachts, private jets, homes and estates. What you own is kept in `rest["lux"]` (like
/// the original's `S.lux`, so imported saves load) and counts in net worth (`Valuation.netWorth`). Values move every week and
/// upkeep and insurance are paid; jets and yachts can be chartered, homes let, art lent to a museum; estates earn money; a car or
/// jet can be bought through a limited company (the company pays and writes it down, you pay benefit-in-kind as salary).
/// Originals: LUX in ui/screens/mockup.js, features/player/lifestyle.js, features/player/estates.js, hiring_place_swipe_luxury.js.
/// The catalogue and all rates are data: Resources/luxury.json.
public enum Luxury {
    static let book: JSONValue = {
        guard let url = Bundle.module.url(forResource: "luxury", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return json
    }()

    // MARK: Catalogue

    public struct Item: Identifiable, Equatable, Sendable {
        public var id: String
        public var category: String
        public var name: String
        public var detail: String
        public var price: Double
        /// Upkeep, insurance and storage a year, as a share of the price
        public var upkeep: Double
        /// Yearly change in value
        public var growth: Double
        public var volatility: Double
        public var monthlyUpkeep: Double { upkeep * price / 12 }
        /// "Usually rises" ... "Loses value fast"
        public var trend: String { growth >= 0.04 ? "Usually rises" : growth > 0 ? "Holds its value" : growth > -0.06 ? "Loses some value" : "Loses value fast" }
    }

    public struct Category: Identifiable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var items: [Item]
    }

    public static let categories: [Category] = book["categories"].array.map { c in
        Category(id: c["id"].string, name: c["name"].string, items: c["items"].array.map {
            Item(id: $0["id"].string, category: c["id"].string, name: $0["name"].string, detail: $0["detail"].string, price: $0["price"].double,
                 upkeep: $0["upkeep"].double, growth: $0["growth"].double, volatility: $0["volatility"].double)
        })
    }
    public static func item(_ id: String) -> Item? { categories.lazy.flatMap { $0.items }.first { $0.id == id } }
    public static var sellFee: Double { book["sellFee"].double }

    public struct Use: Equatable, Sendable { public var id: String; public var name: String; public var detail: String }
    public static func uses(for category: String) -> [Use] {
        ["charter", "rent", "museum"].compactMap { k in
            let u = book["uses"][k]
            return u["categories"].array.contains { $0.string == category } ? Use(id: k, name: u["name"].string, detail: u["detail"].string) : nil
        }
    }

    // MARK: What the player owns

    public struct Piece: Identifiable, Equatable, Sendable {
        public var id: Int
        public var item: Item
        public var paid: Double
        public var value: Double
        public var week: Int
        public var companyID: Int
        public var bookValue: Double
        public var use: String
        public var until: Int
        /// What it earns a week in its present use or as an estate (before tax)
        public var weeklyIncome: Double
        public var gain: Double { paid > 0 ? (value - paid) / paid : 0 }
        public var isEstate: Bool { item.category == "estates" }
    }

    static func record(_ s: GameState) -> [JSONValue] { s.rest["lux"]?.array ?? [] }

    public static func pieces(_ s: GameState) -> [Piece] {
        record(s).compactMap { x in
            guard let it = item(x["k"].string) else { return nil }
            return Piece(id: x["id"].int, item: it, paid: x["price"].double, value: x["val"].double, week: x["w"].int, companyID: x["co"].int, bookValue: x["bv"].double,
                         use: x["use"].string, until: x["until"].int, weeklyIncome: weeklyIncome(x, it, s))
        }
    }

    /// What the player owns personally, at today's value. Company items sit in the company's books.
    public static func personalValue(_ s: GameState) -> Double { record(s).filter { $0["co"].int == 0 }.reduce(0) { $0 + $1["val"].double } }
    public static func upkeepPerMonth(_ s: GameState) -> Double { pieces(s).reduce(0) { $0 + $1.item.monthlyUpkeep * ($1.paid / max(1, $1.item.price)) } }

    // MARK: Buying and selling

    public enum Result: Equatable, Sendable { case ok, notEnoughCash, unknownItem, notPossible }

    static func save(_ s: inout GameState, _ list: [JSONValue]) { s.rest["lux"] = .array(list) }

    /// Buy a piece from your personal cash. `price` can be lower than the list price (a private sale). Original: `luxbuygo`.
    @discardableResult
    public static func buy(_ s: inout GameState, itemID: String, price: Double? = nil) -> Result {
        guard let it = item(itemID) else { return .unknownItem }
        let p = jsRound(price ?? it.price)
        if s.cash < p { return .notEnoughCash }
        Payments.playerPays(&s, p, label: "Bought: \(it.name)")
        var list = record(s)
        list.append(.object(["id": .number(Double(s.makeID())), "k": .string(it.id), "price": .number(p), "val": .number(max(p, it.price)), "w": .number(Double(s.week))]))
        save(&s, list)
        return .ok
    }

    /// Limited companies of the player that can buy a car or a jet (open, in the player's home country).
    public static func companiesThatCanBuy(_ s: GameState, itemID: String) -> [Company] {
        guard let it = item(itemID), (book["companyCategories"].array.map { $0.string }).contains(it.category) else { return [] }
        return s.companies.filter { $0.status == .open && $0.form == .limited && $0.type != "hold" && $0.countryCode == s.homeCountryCode }
    }

    /// A car or jet bought by one of your limited companies: it pays, writes it down and pays the upkeep. Original: `LIFE.buyVia`.
    @discardableResult
    public static func buyThroughCompany(_ s: inout GameState, itemID: String, companyID: Int) -> Result {
        guard let it = item(itemID), let i = s.companyIndex(companyID), companiesThatCanBuy(s, itemID: itemID).contains(where: { $0.id == companyID }) else { return .notPossible }
        if s.companies[i].cash < it.price { return .notEnoughCash }
        Payments.companyPays(&s, companyID: companyID, amount: it.price, category: nil, label: "Bought: \(it.name)")
        var list = record(s)
        list.append(.object(["id": .number(Double(s.makeID())), "k": .string(it.id), "price": .number(it.price), "val": .number(it.price), "w": .number(Double(s.week)),
                             "co": .number(Double(companyID)), "bv": .number(it.price)]))
        save(&s, list)
        syncBookValues(&s)
        return .ok
    }

    /// Sell a piece: the proceeds are 92% of its value. A company's piece pays the company, and the difference to its book value is
    /// a gain or loss there; a gain on a personal collectible is taxed with your other gains. Original: `luxsell`.
    @discardableResult
    public static func sell(_ s: inout GameState, pieceID: Int) -> Double {
        var list = record(s)
        guard let at = list.firstIndex(where: { $0["id"].int == pieceID }), let it = item(list[at]["k"].string) else { return 0 }
        let x = list[at]
        if x["use"].string == "museum" && x["until"].int > s.week { return 0 }
        let get = jsRound(x["val"].double * (1 - sellFee))
        list.remove(at: at)
        save(&s, list)
        if x["co"].int != 0, let i = s.companyIndex(x["co"].int) {
            let bv = jsRound(x["bv"].double)
            Payments.companyReceives(&s, companyID: x["co"].int, amount: get, category: nil, label: "Sold: \(it.name)")
            Payments.book(&s, companyID: x["co"].int, category: get > bv ? "rev" : "loss", amount: abs(get - bv))
            _ = i
            syncBookValues(&s)
        } else {
            Payments.playerReceives(&s, get, label: "Sold: \(it.name)")
            if get > x["price"].double { s.tax.gains += get - x["price"].double }
        }
        return get
    }

    public static func setUse(_ s: inout GameState, pieceID: Int, use: String?) {
        var list = record(s)
        guard let at = list.firstIndex(where: { $0["id"].int == pieceID }), let it = item(list[at]["k"].string) else { return }
        if list[at]["use"].string == "museum" && list[at]["until"].int > s.week { return }
        let allowed = uses(for: it.category).map { $0.id }
        let u = use ?? ""
        guard u.isEmpty || allowed.contains(u) else { return }
        list[at]["use"] = u.isEmpty ? .null : .string(u)
        list[at]["until"] = u == "museum" ? .number(Double(s.week + 26)) : .null
        save(&s, list)
    }

    static func syncBookValues(_ s: inout GameState) {
        let list = record(s)
        for i in s.companies.indices {
            let id = s.companies[i].id
            let bv = jsRound(list.filter { $0["co"].int == id }.reduce(0) { $0 + $1["bv"].double })
            if bv != 0 || s.companies[i].value("luxBV").double != 0 { s.companies[i].set("luxBV", .number(bv)) }
        }
    }

    // MARK: Income, estates

    static func month(_ s: GameState) -> Int {
        let m = GameCalendar.monthIndex(week: s.week) % 12
        return ["AU", "BR"].contains(s.homeCountryCode) ? (m + 6) % 12 : m
    }

    static func inSeason(_ s: GameState) -> Bool {
        let m = GameCalendar.monthIndex(week: s.week) % 12
        return ["AU", "BR"].contains(s.homeCountryCode) ? (m >= 10 || m <= 2) : (m >= 4 && m <= 8)
    }

    /// What a piece earns this week: chartered jets and yachts, rented homes, and estates by season. Originals: `weekIncome` (both files).
    static func weeklyIncome(_ x: JSONValue, _ it: Item, _ s: GameState) -> Double {
        if it.category == "estates", let d = Optional(book["estates"][it.id]), !d.isNull {
            if it.id == "e5" && x["mode"].string == "private" { return 0 }
            let vint = it.id == "e1" ? (x["vint"].isNull ? 1 : x["vint"].double) : 1
            let w = d["weights"].array.map { $0.double }, total = max(0.0001, w.reduce(0, +))
            return jsRound(x["val"].double * d["yearly"].double * vint * (w[month(s)] * 12 / total) / 52)
        }
        let u = book["uses"][x["use"].string]
        guard !u.isNull, u["yearly"][it.category].double > 0 else { return 0 }
        let season: Double = it.category == "yachts" ? (inSeason(s) ? 2.4 : 0) : 1
        return jsRound(x["val"].double * u["yearly"][it.category].double * (1 - u["fee"].double) * season / 52)
    }

    public static func estateInfo(_ id: String) -> (what: String, does: String, yearly: Double)? {
        let d = book["estates"][id]
        return d.isNull ? nil : (d["what"].string, d["does"].string, d["yearly"].double)
    }

    /// Benefit-in-kind on a company piece, a year, as a share of the price. Original: `bikOf`.
    static func benefitRate(_ x: JSONValue, _ it: Item, _ s: GameState) -> Double {
        if it.category == "jets" { return 0.08 }
        let b = book["benefitInKind"]
        let r = b[s.homeCountryCode].isNull ? b["default"].double : b[s.homeCountryCode].double
        return r * (book["electric"].array.contains { $0.string == x["k"].string } ? 0.6 : 1)
    }
    public static func benefitPerYear(_ p: Piece, _ s: GameState) -> Double {
        p.companyID == 0 ? 0 : jsRound(p.paid * benefitRate(.object(["k": .string(p.item.id)]), p.item, s))
    }

    // MARK: Lending against what you own

    /// Value the bank will lend against: art, watches, homes, boats, jets at 30-60%, estates at half. Original: 'collateral' steps.
    public static func collateral(_ s: GameState) -> Double {
        let ltv: [String: Double] = ["art": 0.4, "watches": 0.5, "homes": 0.6, "yachts": 0.3, "jets": 0.3, "estates": book["estateLoanShare"].double]
        return record(s).filter { $0["co"].int == 0 }.reduce(0) { t, x in t + x["val"].double * (item(x["k"].string).flatMap { ltv[$0.category] } ?? 0) }
    }

    // MARK: Every week

    /// Values move, upkeep and insurance are paid, uses earn, estates earn, risks happen. Original: the three 'week.after' steps.
    public static func weekly(_ s: inout GameState) {
        var list = record(s)
        if list.isEmpty { return }
        // 1. values move; upkeep
        var personalCost = 0.0
        for n in list.indices {
            guard let it = item(list[n]["k"].string) else { continue }
            var r = HashedRandom("\(s.seed):lux:\(list[n]["id"].int):\(s.week)")
            let z = (r.next() - 0.5) * 3.4
            list[n]["val"] = .number(max(it.price * 0.05, jsRound(list[n]["val"].double * (1 + it.growth / 52 + z * it.volatility / 52.0.squareRoot()))))
            let cost = it.upkeep * list[n]["price"].double / 52
            if list[n]["co"].int != 0, s.companyIndex(list[n]["co"].int) != nil {
                Payments.companyPays(&s, companyID: list[n]["co"].int, amount: jsRound(cost), category: "oth", label: "Upkeep: \(it.name)")
            } else { personalCost += cost }
        }
        personalCost = jsRound(personalCost)
        if personalCost > 0 { Payments.playerPays(&s, personalCost, label: "Upkeep: private collection") }
        // 2. what you own: uses, wear, company items, risks
        var gone: [Int] = [], income = 0.0, estateIncome = 0.0
        for n in list.indices {
            guard let it = item(list[n]["k"].string) else { continue }
            var x = list[n]
            let companyID = x["co"].int
            if companyID != 0, s.company(companyID).map({ !$0.status.isLive }) ?? true { x["co"] = .null; x["bv"] = .null }
            let owner = x["co"].int
            let u = book["uses"][x["use"].string]
            if !u.isNull {
                if u["wear"].double != 0 { x["val"] = .number(max(it.price * 0.05, jsRound(x["val"].double * (1 - u["wear"].double / 52)))) }
                let w = weeklyIncome(x, it, s)
                if w > 0 {
                    if owner != 0 { Payments.companyReceives(&s, companyID: owner, amount: w, category: "rev", label: (x["use"].string == "rent" ? "Rent: " : "Charter: ") + it.name) } else { income += w }
                }
                if x["use"].string == "museum", x["until"].int != 0, s.week >= x["until"].int {
                    x["use"] = .null; x["until"] = .null
                    s.addMessage(kind: "info", from: "The museum", title: "\(it.name) is back", body: "The exhibition has closed and the work is back with you. It is better known now.", tone: "good")
                }
            }
            if it.category == "estates" { estateIncome += weeklyIncome(x, it, s) }
            if owner != 0 {
                let dep = book["depreciation"][it.category].isNull ? book["depreciation"]["default"].double : book["depreciation"][it.category].double
                let d = jsRound(x["bv"].double * dep / 52)
                if d > 0 { Payments.book(&s, companyID: owner, category: "dep", amount: d); x["bv"] = .number(x["bv"].double - d) }
                s.tax.salary += jsRound(x["price"].double * benefitRate(x, it, s) / 52)
            }
            let risk = book["risks"][it.category]
            if !risk.isNull {
                let mult = x["use"].string == "charter" ? 1.8 : x["use"].string == "rent" ? 1.5 : 1
                if s.random.chance(risk[0].double * mult / 52) {
                    let excess = max(1000, jsRound(x["val"].double * 0.02))
                    if risk[1].string == "theft" {
                        let pay = jsRound(x["val"].double - excess)
                        gone.append(x["id"].int)
                        if owner != 0 { Payments.companyReceives(&s, companyID: owner, amount: pay, category: nil, label: "Insurance: \(it.name)") } else { Payments.playerReceives(&s, pay, label: "Insurance: \(it.name) stolen") }
                        s.addMessage(kind: "info", from: "Your insurer", title: "\(it.name) was stolen", body: "The police have not found it. The insurer pays the value less the excess.", tone: "bad")
                    } else {
                        if owner != 0 { Payments.companyPays(&s, companyID: owner, amount: excess, category: "oth", label: "Insurance excess: \(it.name)") } else { Payments.playerPays(&s, excess, label: "Insurance excess: \(it.name)") }
                        s.addMessage(kind: "info", from: "Your insurer", title: "Damage to \(it.name)", body: "Repaired; you paid the excess.", tone: "bad")
                    }
                }
            }
            list[n] = x
        }
        if !gone.isEmpty { list = list.filter { !gone.contains($0["id"].int) } }
        save(&s, list)
        if !gone.isEmpty || list.contains(where: { $0["co"].int != 0 }) { syncBookValues(&s) }
        if income > 0 { Payments.playerReceives(&s, income, label: "Charter and rent"); s.tax.interest += income }
        if estateIncome > 0 { Payments.playerReceives(&s, estateIncome, label: "Estates"); s.tax.interest += estateIncome }
        // 3. the vintage is set at harvest
        let harvest = month(s) == 9
        if harvest {
            var changed = false
            for n in list.indices where list[n]["k"].string == "e1" && list[n]["co"].int == 0 && list[n]["vy"].int != GameCalendar.year(week: s.week) {
                list[n]["vy"] = .number(Double(GameCalendar.year(week: s.week)))
                let q = jsRound(clamp(1 + s.random.gauss() * 0.28, 0.3, 1.5) * 100) / 100
                list[n]["vint"] = .number(q)
                s.addMessage(kind: "info", from: "Your vineyard", title: "Harvest: " + vintageWord(q), body: "This year's wine will sell for about \(Int(q * 100))% of a normal year.", tone: q >= 0.85 ? "good" : "bad")
                changed = true
            }
            if changed { save(&s, list) }
        }
    }

    public static func vintageWord(_ q: Double) -> String {
        q >= 1.25 ? "an exceptional vintage" : q >= 1.05 ? "a good vintage" : q >= 0.85 ? "an ordinary year" : q >= 0.6 ? "a poor year: rain at harvest" : "a disaster: hail in August"
    }

    // MARK: The island, the castle

    public enum EstateResult: Equatable, Sendable { case ok, none, wait, notEnoughCash }

    public static func setCastleMode(_ s: inout GameState, pieceID: Int, open: Bool) {
        var list = record(s)
        guard let at = list.firstIndex(where: { $0["id"].int == pieceID && $0["k"].string == "e5" }) else { return }
        list[at]["mode"] = .string(open ? "open" : "private")
        save(&s, list)
    }

    /// A retreat on the island, once a quarter. Your managers are in a better mood afterwards. Original: `EST.retreat`.
    @discardableResult
    public static func hostRetreat(_ s: inout GameState, currency: Currency) -> EstateResult {
        guard record(s).contains(where: { $0["k"].string == "e2" && $0["co"].int == 0 }) else { return .none }
        if let last = s.rest["ret56"], !last.isNull, s.week - last.int < 13 { return .wait }
        let cost = currency.scaledPrice(120000)
        if s.cash < cost { return .notEnoughCash }
        Payments.playerPays(&s, cost, label: "Retreat on the island")
        s.rest["ret56"] = .number(Double(s.week))
        for i in s.companies.indices where s.companies[i].managerID != nil && s.companies[i].status == .open {
            s.companies[i].set("mood", .number(min(100, (s.companies[i].value("mood").isNull ? 60 : s.companies[i].value("mood").double) + 3)))
        }
        s.addMessage(kind: "info", from: "The island", title: "A retreat on the island", body: "Your managers came. Three days of talk, sailing and long dinners. People remember who invites them to a place like this.", tone: "good")
        return .ok
    }

    /// A week off on the island: you are not working next week and come back rested. Original: `EST.weekOff`.
    @discardableResult
    public static func takeWeekOff(_ s: inout GameState) -> EstateResult {
        guard record(s).contains(where: { $0["k"].string == "e2" && $0["co"].int == 0 }) else { return .none }
        if let off = s.rest["offW56"], !off.isNull, s.week < off.int { return .wait }
        s.rest["offW56"] = .number(Double(s.week + 1))
        s.rest["sickW"] = .number(Double(s.week + 1))
        s.addMessage(kind: "info", from: "The island", title: "A week off", body: "You are away next week. Companies you run yourself manage without you; you come back rested.", tone: "good")
        return .ok
    }
}
