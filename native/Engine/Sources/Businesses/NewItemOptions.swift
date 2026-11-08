import Foundation
import GameCore
import Countries
import Finance

/// One choice in the "new product or service" popup.
public struct NewItemOption: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var isService: Bool
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

/// New products and services of the trade's own kind, added at once. Everything the company does not sell yet is on offer, the starters it
/// did not choose first included. Profit and market numbers need a market advisor (role "advisor", hired or as a duty).
public enum NewItemOptions {
    public static let projectID = "newitem"
    public static let advisorRole = "advisor"
    /// Customers an added item brings in, as a share of the weekly units (before rivals dilute it).
    static let variantLift = 0.02
    static let optionCount = 5

    /// One catalog entry (`Resources/itemcatalog.json`): a realistic product or service for a trade.
    struct Entry: Equatable { var name: String; var isService: Bool; var brand: Bool }

    /// Options per trade id, from the JSON resource. Empty if the resource is missing (then the family fallback below is used).
    static let catalog: [String: [Entry]] = {
        guard let url = Bundle.module.url(forResource: "itemcatalog", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return [:] }
        var out: [String: [Entry]] = [:]
        for (k, rows) in j["trades"].object {
            out[k] = rows.array.map { Entry(name: $0["n"].string, isService: $0["svc"].bool, brand: $0["b"].bool) }
        }
        return out
    }()

    /// Last resort for a trade without an entry: generic options by kind.
    static let fallback: (goods: [String], service: [String]) = (
        ["Limited edition", "Gift box", "Family pack", "Seasonal range", "Premium range", "Starter kit"],
        ["Express service", "Care plan", "Weekend special", "Premium package", "Consultation", "Annual plan"])

    static func entries(for bd: Trade) -> [Entry] {
        if let e = catalog[bd.id], !e.isEmpty { return e }
        return fallback.goods.map { Entry(name: $0, isService: false, brand: false) } + fallback.service.map { Entry(name: $0, isService: true, brand: false) }
    }

    public static func hasAdvisor(_ co: Company) -> Bool { RoleEffects.filled(co, advisorRole) }

    static func slug(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }

    public static func list(_ s: GameState, companyID: Int, isService svc: Bool, data: GameData) -> NewItemOptionList {
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return NewItemOptionList(options: [], hasMarketAdvisor: false) }
        let advisor = hasAdvisor(co)
        // Only the trade's own kind of offer: a service for a goods trade (or the reverse) is not a variant and is not offered.
        guard svc == SalesItems.isService(bd) else { return NewItemOptionList(options: [], hasMarketAdvisor: advisor) }
        let pool = entries(for: bd).filter { $0.isService == svc }
        let existing = SalesItems.onSaleNames(co, bd)
        let short = SalesItems.shortName(co)
        var h = HashedRandom("\(s.seed):newitems:\(co.id):\(svc)")
        let start = pool.isEmpty ? 0 : Int(h.next() * Double(pool.count))
        let w = World(state: s, data: data)
        var out: [NewItemOption] = []
        func option(_ name: String) -> NewItemOption {
            let est = advisor ? estimate(s, co, bd, lift: variantLift, w: w) : nil
            return NewItemOption(id: "\(svc ? "svc" : "gds"):\(slug(name))", name: name, isService: svc, profitChange: est?.0, marketChange: est?.1)
        }
        // Items the company holds but does not sell (the starters it did not choose) come first, all of them.
        let hidden = SalesItems.hiddenIDs(co)
        for it in SalesItems.items(co, bd) where hidden.contains(it.id) && it.isService == svc && !existing.contains(it.name.lowercased()) {
            if !out.contains(where: { $0.name.lowercased() == it.name.lowercased() }) { out.append(option(it.name)) }
        }
        let held = out.count
        for k in pool.indices where out.count < held + optionCount {
            let e = pool[(start + k) % pool.count]
            let name = e.brand ? "\(short) \(e.name.prefix(1).lowercased() + e.name.dropFirst())" : e.name
            if existing.contains(name.lowercased()) { continue }
            if out.contains(where: { $0.name.lowercased() == name.lowercased() }) { continue }
            out.append(option(name))
        }
        return NewItemOptionList(options: out, hasMarketAdvisor: advisor)
    }

    /// Weekly profit and market-share change, by the unit-share model of `SalesItems.forecast`: the new customers buy at the going ticket and
    /// leave the cost of sales; rivals dilute the lift (a quarter each); share is own size over own plus rivals'.
    static func estimate(_ s: GameState, _ co: Company, _ bd: Trade, lift: Double, w: World) -> (Double, Double) {
        let rivals = Rivals.rivals(s, for: co)
        let effective = MarketPressure.addedLift(co, category: false, rivalCount: rivals.count)   // the very figure the real add uses
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

    // MARK: Projects started before development was removed

    static func addRefusal(_ co: Company, _ bd: Trade, name: String) -> String? {
        let list = SalesItems.items(co, bd)
        if list.count >= SalesItems.maxItems { return "That is as many items as one company can sell." }
        if list.contains(where: { $0.name.lowercased() == name.lowercased() }) { return "There is already an item with that name." }
        return nil
    }

    /// An older save's running project is done: the item joins the list (or, if the list changed meanwhile, a message says so).
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
