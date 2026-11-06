import Foundation
import GameCore
import Countries
import Businesses

/// One accountant on offer in a country: what the choice screens show before and after a company exists.
public struct AccountantOffer: Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    /// Fee a month.
    public var monthlyFee: Double
    /// 1 to 5.
    public var rating: Double
    /// How often the books are wrong (0 to 1).
    public var errorRate: Double
    /// The one a company gets when none is chosen.
    public var isDefault: Bool
}

/// Choosing the accountant of a company, and reading the country's accountants before the company exists.
public extension GameEngine {
    /// Make sure the country's accountants exist in the save, so the ids a screen shows are the ids a company is given. Safe to call again.
    mutating func prepareAccountants(countryCode: String) {
        update { s, d, _ in _ = Providers.pool(for: countryCode, state: &s, countries: d.countries) }
    }

    /// The accountants of a country, in the order of the pool; empty until `prepareAccountants` has run for it.
    func accountantOffers(countryCode: String) -> [AccountantOffer] {
        let list: [JSONValue] = (state.rest["poolc"] ?? .null)[countryCode]["acc"].array
        let defaultIndex: Int = list.count > 1 ? 1 : 0
        return list.enumerated().map { (n: Int, j: JSONValue) -> AccountantOffer in
            AccountantOffer(id: j["id"].int, name: j["name"].string, monthlyFee: j["fee"].double, rating: j["rating"].double,
                            errorRate: j["err"].double, isDefault: n == defaultIndex)
        }
    }

    /// Appoint one of the country's accountants for a company (the monthly fee changes with it; who runs payroll follows from it).
    @discardableResult
    mutating func setAccountant(companyID: Int, accountantID: Int) -> SettingResult {
        guard let co = state.company(companyID) else { return .refused("That company no longer exists.") }
        prepareAccountants(countryCode: co.countryCode)
        guard accountantOffers(countryCode: co.countryCode).contains(where: { (o: AccountantOffer) -> Bool in o.id == accountantID }) else {
            return .refused("That accountant is not on offer here.")
        }
        let acc: JSONValue = co.value("acc")
        if !acc.isNull, acc["own"].isNull, acc["id"].int == accountantID { return .unchanged }
        update { s, d, _ in CompanySetup.chooseAccountant(&s, companyID: companyID, accountantID: accountantID, data: d) }
        return .applied
    }
}
