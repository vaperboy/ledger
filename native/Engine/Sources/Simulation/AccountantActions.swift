import Foundation
import GameCore
import Countries
import Businesses

public struct AccountantOffer: Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var monthlyFee: Double
    public var rating: Double
    public var errorRate: Double
    public var isDefault: Bool
}

public extension GameEngine {
    mutating func prepareAccountants(countryCode: String) {
        update { s, d, _ in _ = Providers.pool(for: countryCode, state: &s, countries: d.countries) }
    }

    func accountantOffers(countryCode: String) -> [AccountantOffer] {
        let list: [JSONValue] = (state.rest["poolc"] ?? .null)[countryCode]["acc"].array
        let defaultIndex: Int = list.count > 1 ? 1 : 0
        return list.enumerated().map { (n: Int, j: JSONValue) -> AccountantOffer in
            AccountantOffer(id: j["id"].int, name: j["name"].string, monthlyFee: j["fee"].double, rating: j["rating"].double,
                            errorRate: j["err"].double, isDefault: n == defaultIndex)
        }
    }

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

public extension GameEngine {
    @discardableResult
    mutating func bookOnlineSettlements(_ items: [OnlineSettlement]) -> [String] {
        var done: [String] = []
        update { s, d, _ in done = OnlineSettlements.book(&s, items, data: d) }
        return done
    }
}
