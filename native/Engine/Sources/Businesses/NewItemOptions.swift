import Foundation
import GameCore
import Countries
import Finance

/// One choice in the "new product or service" popup.
public struct NewItemOption: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var isService: Bool
    /// True for a genuinely new category (a service for a goods trade, goods for a service trade): it is developed first.
    public var needsDevelopment: Bool
    public var developmentWeeks: Int
    public var developmentCost: Double
    /// Weekly profit change when the item is added, and the change in the company's share of the local market (0.01 = one point).
    /// Both nil unless the company has a market advisor.
    public var profitChange: Double?
    public var marketChange: Double?
}

public struct NewItemOptionList: Equatable, Sendable {
    public var options: [NewItemOption]
    /// False: `profitChange` and `marketChange` are nil because nobody advises the company on its market.
    public var hasMarketAdvisor: Bool
}

/// New products and services. A variant of what the trade already sells is added at once; a new category is developed first
/// (the Development machinery, project "newitem"; the item appears when it is done). Profit and market numbers need a market advisor
/// (role "advisor", hired or as a duty). See DECISIONS.md "New product and service options".
public enum NewItemOptions {
    public static let projectID = "newitem"
    public static let advisorRole = "advisor"
    /// Customers a variant brings in, and a new category brings in, as a share of the weekly units (before rivals dilute it).
    static let variantLift = 0.02
    static let categoryLift = 0.05
    /// Share of a year's sales a new category costs to develop.
    static let costShare = 0.02
    static let optionCount = 5

    /// One catalog entry (`Resources/itemcatalog.json`): a realistic product or service for a trade.
    struct Entry: Equatable { var name: String; var isService: Bool; var develop: Bool; var brand: Bool }

    /// Options per trade id, from the JSON resource. Empty if the resource is missing (then the family fallback below is used).
    static let catalog: [String: [Entry]] = {
        guard let url = Bundle.module.url(forResource: "itemcatalog", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return [:] }
        var out: [String: [Entry]] = [:]
        for (k, rows) in j["trades"].object {
            out[k] = rows.array.map { Entry(name: $0["n"].string, isService: $0["svc"].bool, develop: $0["dev"].bool, brand: $0["b"].bool) }
        }
        return out
    }()

    /// Last resort for a trade without an entry: generic options by kind.
    static let fallback: (goods: [String], service: [String]) = (
        ["Limited edition", "Gift box", "Family pack", "Seasonal range", "Premium range", "Starter kit"],
        ["Express service", "Care plan", "Weekend special", "Premium package", "Consultation", "Annual plan"])

    static func entries(for bd: Trade) -> [Entry] {
        if let e = catalog[bd.id], !e.isEmpty { return e }
        return fallback.goods.map { Entry(name: $0, isService: false, develop: false, brand: false) } + fallback.service.map { Entry(name: $0, isService: true, develop: false, brand: false) }
    }

    public static func hasAdvisor(_ co: Company) -> Bool { RoleEffects.filled(co, advisorRole) }

    static func slug(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }

    public static func list(_ s: GameState, companyID: Int, isService svc: Bool, data: GameData) -> NewItemOptionList {
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return NewItemOptionList(options: [], hasMarketAdvisor: false) }
        let advisor = hasAdvisor(co)
        let own = SalesItems.isService(bd)
        let pool = entries(for: bd).filter { $0.isService == svc }
        let existing = Set(SalesItems.items(co, bd).map { $0.name.lowercased() })
        let short = SalesItems.shortName(co)
        var h = HashedRandom("\(s.seed):newitems:\(co.id):\(svc)")
        let start = pool.isEmpty ? 0 : Int(h.next() * Double(pool.count))
        let w = World(state: s, data: data)
        let cur = w.currency(co)
        let devWeeks = RoleEffects.developmentWeeks(developmentWeeksBase(co), co)
        let devCost = developmentCost(co, currency: cur)
        var out: [NewItemOption] = []
        for k in pool.indices where out.count < optionCount {
            let e = pool[(start + k) % pool.count]
            let name = e.brand ? "\(short) \(e.name.prefix(1).lowercased() + e.name.dropFirst())" : e.name
            if existing.contains(name.lowercased()) { continue }
            let category = svc != own          // a different kind of offer is always developed first
            let develop = category || e.develop
            let est = advisor ? estimate(s, co, bd, lift: category ? categoryLift : variantLift, w: w) : nil
            out.append(NewItemOption(id: "\(svc ? "svc" : "gds"):\(slug(name))", name: name, isService: svc, needsDevelopment: develop, developmentWeeks: develop ? devWeeks : 0,
                                     developmentCost: develop ? devCost : 0, profitChange: est?.0, marketChange: est?.1))
        }
        return NewItemOptionList(options: out, hasMarketAdvisor: advisor)
    }

    /// Larger companies take longer: 6 weeks plus 2 per square root of size, at most 20.
    static func developmentWeeksBase(_ co: Company) -> Int { min(20, 6 + Int((2 * max(1, co.size).squareRoot()).rounded())) }

    static func developmentCost(_ co: Company, currency cur: Currency) -> Double {
        Development.cost(Development.Project(id: projectID, name: "A new product or service", text: "", kind: "dem", size: 0, weeks: 0, share: costShare), for: co, currency: cur)
    }

    /// Weekly profit and market-share change, by the unit-share model of `SalesItems.forecast`: the new customers buy at the going ticket and
    /// leave the cost of sales; rivals dilute the lift (a quarter each); share is own size over own plus rivals'.
    static func estimate(_ s: GameState, _ co: Company, _ bd: Trade, lift: Double, w: World) -> (Double, Double) {
        let rivals = Rivals.rivals(s, for: co)
        let effective = MarketPressure.addedLift(co, category: lift == categoryLift, rivalCount: rivals.count)   // the very figure the real add uses
        let ticket = SalesItems.marketTicket(co, bd, w)
        // The extra customers are what the demand model itself gives with the lift in full force, up to what the company can serve:
        // the same calculation the weekly simulation runs, so the estimate and the game cannot drift apart.
        var with = co
        with.set(MarketPressure.liftKey, .array(co.value(MarketPressure.liftKey).array + [.object(["w0": .number(Double(s.week - MarketPressure.rampWeeks)), "f": .number(effective)])]))
        let capacity = CapacityModel.compute(co, bd, w).capacity
        let units = max(0, min(DemandModel.compute(with, bd, w).customers, capacity) - min(DemandModel.compute(co, bd, w).customers, capacity))
        let profit = units * ticket * (1 - bd.costOfSales)
        let others = rivals.reduce(0.0) { $0 + $1.size }
        let own = max(co.size, 0.01)
        let share = own / (own + others)
        let after = own * (1 + effective) / (own * (1 + effective) + others)
        return (profit, after - share)
    }

    // MARK: Development of a new category

    static func addRefusal(_ co: Company, _ bd: Trade, name: String) -> String? {
        let list = SalesItems.items(co, bd)
        if list.count >= SalesItems.maxItems { return "That is as many items as one company can sell." }
        if list.contains(where: { $0.name.lowercased() == name.lowercased() }) { return "There is already an item with that name." }
        return nil
    }

    public static func startRefusal(_ s: GameState, companyID: Int, option o: NewItemOption, data: GameData) -> String? {
        if let why = SalesItems.refusal(s, companyID: companyID, itemID: nil, data: data) { return why }
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return nil }
        if let why = addRefusal(co, bd, name: o.name) { return why }
        if !co.value("rd56")["run"].isNull { return "Another development project is already running." }
        if co.cash < o.developmentCost { return "The company does not have the cash for it yet." }
        return nil
    }

    public static func start(_ s: inout GameState, companyID: Int, option o: NewItemOption) {
        guard let i = s.companyIndex(companyID) else { return }
        _ = Payments.companyPays(&s, companyID: companyID, amount: o.developmentCost, category: "oth", label: "Development: \(o.name)")
        var r = s.companies[i].value("rd56")
        if r.isNull { r = .object(["run": .null, "done": .array([])]) }
        r["run"] = .object(["k": .string(projectID), "w0": .number(Double(s.week)), "wEnd": .number(Double(s.week + o.developmentWeeks)), "cost": .number(o.developmentCost),
                            "item": .string(o.name), "svc": .bool(o.isService)])
        s.companies[i].set("rd56", r)
        Development.refreshFactors(&s, i)
        s.note("\(s.companies[i].name) started developing \(o.name).", tone: "n", companyID: companyID)
    }

    /// The project is done: the item joins the list (or, if the list changed meanwhile, the money is spent and a message says so).
    static func finish(_ s: inout GameState, _ i: Int, name: String, isService: Bool, data: GameData) {
        let co = s.companies[i]
        guard let bd = data.catalog[co.type] else { return }
        if let why = addRefusal(co, bd, name: name) {
            s.addMessage(kind: "info", from: co.name, title: "\(name) could not be added", body: why, companyID: co.id, tone: "bad")
            return
        }
        SalesItems.add(&s, companyID: co.id, name: name, isService: isService, data: data)
        s.addMessage(kind: "info", from: co.managerID.flatMap { s.people[$0]?.name } ?? co.name, title: "\(name) is ready",
                     body: "Development is finished. \(name) is now on sale.", companyID: co.id, tone: "good")
    }
}
