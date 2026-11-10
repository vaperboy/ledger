import Foundation
import GameCore
import Countries
import Finance

public struct NewItemOption: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var isService: Bool
    public var profitChange: Double?
    public var marketChange: Double?
}

public struct NewItemOptionList: Equatable, Sendable {
    public var options: [NewItemOption]
    public var hasMarketAdvisor: Bool
}

public enum NewItemOptions {
    public static let projectID = "newitem"
    public static let advisorRole = "advisor"
    static let variantLift = 0.02
    static let optionCount = 5

    struct Entry: Equatable { var name: String; var isService: Bool; var brand: Bool }

    static let catalog: [String: [Entry]] = {
        guard let url = Bundle.module.url(forResource: "itemcatalog", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return [:] }
        var out: [String: [Entry]] = [:]
        for (k, rows) in j["trades"].object {
            out[k] = rows.array.map { Entry(name: $0["n"].string, isService: $0["svc"].bool, brand: $0["b"].bool) }
        }
        return out
    }()

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

    static func estimate(_ s: GameState, _ co: Company, _ bd: Trade, lift: Double, w: World) -> (Double, Double) {
        let rivals = Rivals.rivals(s, for: co)
        let effective = MarketPressure.addedLift(co, category: false, rivalCount: rivals.count)
        let ticket = SalesItems.marketTicket(co, bd, w)
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

    static func addRefusal(_ co: Company, _ bd: Trade, name: String) -> String? {
        let list = SalesItems.items(co, bd)
        if list.count >= SalesItems.maxItems { return "That is as many items as one company can sell." }
        if list.contains(where: { $0.name.lowercased() == name.lowercased() }) { return "There is already an item with that name." }
        return nil
    }

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
