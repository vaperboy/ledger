import Foundation
import GameCore
import Countries
import Employees
import Finance

public enum RentalFinance {
    public static func handles(_ bd: Trade) -> Bool { bd.family == "rent" || bd.family == "fin" }

    static func week(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData) -> CompanyWeek.WeekContext {
        bd.family == "rent" ? RentalModel.weekly(&s, i, bd, data: data) : FinanceModel.weekly(&s, i, bd, data: data)
    }

    static func checklist(_ co: Company, _ bd: Trade, _ w: World) -> [OpeningChecklist.Item] {
        if bd.family == "rent" {
            let ok = !co.properties.isEmpty
            return [OpeningChecklist.Item(id: "prop", title: "At least one property bought", isDone: ok, detail: "See the Properties section")]
        }
        guard bd.hasTrait("ins") else { return [] }
        let any = FinanceModel.products(w.catalog.tables).contains { FinanceModel.isOffered(co, $0.id) }
        let verified = FinanceModel.products(w.catalog.tables).contains {
            FinanceModel.isOffered(co, $0.id) && FinanceModel.verifiedAgents(co, product: $0.id, week: w.week, people: w.state.people, salesRoles: w.catalog.tables.salesRoles) > 0
        }
        return [OpeningChecklist.Item(id: "prod", title: "Choose at least one insurance product", isDone: any, detail: any ? "" : "See the Insurance section"),
                OpeningChecklist.Item(id: "ver", title: "At least one verified salesperson", isDone: verified, detail: "Each salesperson is verified per product")]
    }

    static func buyFirstProperty(_ s: inout GameState, companyID: Int, data: GameData, log: inout [String]) {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type], bd.family == "rent", s.companies[i].properties.isEmpty else { return }
        let w = World(state: s, data: data)
        let ls = RentalModel.listings(s.companies[i], bd, w)
        let ltv = s.economy.policyRate > 0.09 ? 0.2 : 0.55
        var r = RentalModel.BuyResult.notEnoughCash
        for k in stride(from: ls.count - 1, through: 0, by: -1) where r != .ok {
            r = RentalModel.buy(&s, companyID: companyID, listing: ls[k], loanToValue: ltv, reserve: ls[k].price * 0.06, data: data)
        }
        if r != .ok { log.append("property: \(r)") }
    }

    static func finishSetup(_ s: inout GameState, companyID: Int, data: GameData) {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type], bd.hasTrait("ins") else { return }
        FinanceModel.startInsurer(&s, companyID: companyID, data: data)
    }

    static func addEstimate(_ r: inout CompanySetup.Estimate, _ bd: Trade, size: Double, city: Country.City, currency cur: Currency, _ s: GameState, _ w: World) {
        if bd.family == "rent", let tPrice = bd.trait("price") {
            let units = max(2, jsRound((bd.trait("units") ?? 10) * 0.35))
            let price = units * tPrice * pow(city.rent == 0 ? 1 : city.rent, 0.8) * w.economy.housing
            let ltv = s.economy.policyRate > 0.09 ? 0.2 : 0.55
            r.property = (price * (1 - ltv) + price * 0.06) * 1.3
        }
        let capital: Double? = bd.id == "bank" ? cur.scaledPrice(180_000_000) : bd.id == "insco" ? cur.scaledPrice(45_000_000) : nil
        if let c = capital { r.buffer = max(r.buffer, c * size) }
    }

    static let legacyProducts = ["skade": "property", "bil": "motor", "hjem": "home", "reise": "travel", "naring": "business"]

    public static func migrateLegacy(_ root: inout [String: JSONValue]) {
        var companies = root["cos"]?.array ?? []
        for i in companies.indices where companies[i]["type"].string == "insco" {
            func rename(_ v: JSONValue) -> JSONValue {
                var o: [String: JSONValue] = [:]
                for (k, x) in v.object { o[legacyProducts[k] ?? k] = x }
                return .object(o)
            }
            if !companies[i]["fm"]["prods"].isNull { companies[i]["fm"]["prods"] = rename(companies[i]["fm"]["prods"]) }
            var staff = companies[i]["staff"].array
            for k in staff.indices where !staff[k]["ver"].isNull { staff[k]["ver"] = rename(staff[k]["ver"]) }
            if !staff.isEmpty { companies[i]["staff"] = .array(staff) }
        }
        if !companies.isEmpty { root["cos"] = .array(companies) }
    }
}
