import Foundation
import GameCore
import Countries
import Employees
import Finance

/// The glue between the company engine and the property and finance families: which trades they cover, how they open,
/// what they need to start. Models: `RentalModel`, `FinanceModel`.
public enum RentalFinance {
    /// Residential, commercial and parking/storage property (`rent`) and insurance company, bank and fund (`fin`).
    public static func handles(_ bd: Trade) -> Bool { bd.family == "rent" || bd.family == "fin" }

    /// The week's customers, revenue and costs of a rental or finance company (the part that is its own model).
    static func week(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData) -> CompanyWeek.WeekContext {
        bd.family == "rent" ? RentalModel.weekly(&s, i, bd, data: data) : FinanceModel.weekly(&s, i, bd, data: data)
    }

    // MARK: Opening

    /// What a rental or finance company needs before it opens, besides paperwork. Original: `FAM.rent.checklist`, `FAM.fin.checklist`.
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

    /// Before staff are hired: a rental company buys its first property (the largest it can afford, as the original's `autoSetup`).
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

    /// After staff are hired: an insurer switches on its first products and verifies its salespeople.
    static func finishSetup(_ s: inout GameState, companyID: Int, data: GameData) {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type], bd.hasTrait("ins") else { return }
        FinanceModel.startInsurer(&s, companyID: companyID, data: data)
    }

    /// What the first property costs (down payment and fees on the smallest listing) and the regulator's capital. Original: `setupEstimate` additions.
    static func addEstimate(_ r: inout CompanySetup.Estimate, _ bd: Trade, size: Double, city: Country.City, currency cur: Currency, _ s: GameState, _ w: World) {
        if bd.family == "rent", let tPrice = bd.trait("price") {
            let units = max(2, jsRound((bd.trait("units") ?? 10) * 0.35))
            let price = units * tPrice * pow(city.rent == 0 ? 1 : city.rent, 0.8) * w.economy.housing
            let ltv = s.economy.policyRate > 0.09 ? 0.2 : 0.55
            // Listings vary up to about 30% around the typical price.
            r.property = (price * (1 - ltv) + price * 0.06) * 1.3
        }
        let capital: Double? = bd.id == "bank" ? cur.scaledPrice(180_000_000) : bd.id == "insco" ? cur.scaledPrice(45_000_000) : nil
        if let c = capital { r.buffer = max(r.buffer, c * size) }
    }

    // MARK: Old saves

    /// Insurance products had Norwegian ids in the HTML game (`skade`, `bil` ...): rename them in an imported save.
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
