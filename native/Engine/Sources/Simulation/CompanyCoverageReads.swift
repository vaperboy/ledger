import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Events

public struct InsurancePolicyRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var blurb: String
    public var isOn: Bool
    public var weeklyPremium: Double
}

public struct AdviserOption: Equatable, Sendable, Identifiable {
    public var id: Int
    public var kind: Advisers.Kind
    public var name: String
    public var rating: Double
    public var reviews: Int?
    public var monthlyFee: Double
    public var premiumFactor: Double?
    public var payoutReliability: Double?
    public var errorRate: Double?
    public var isCurrent: Bool
    public var ownFirmID: Int?
}

public struct CoverageOverview: Equatable, Sendable {
    public var insurer: AdviserOption?
    public var lawFirm: AdviserOption?
    public var policies: [InsurancePolicyRow]
    public var activeCount: Int { policies.filter { $0.isOn }.count }
    public var weeklyPremiums: Double { policies.filter { $0.isOn }.reduce(0) { $0 + $1.weeklyPremium } }
    public var lawMonthly: Double { lawFirm?.monthlyFee ?? 0 }
}

public extension GameEngine {
    mutating func prepareAdvisers(companyID: Int) {
        update { s, d, _ in
            guard let co = s.company(companyID) else { return }
            _ = Providers.pool(for: co.countryCode, state: &s, countries: d.countries)
        }
    }

    private func adviserOption(_ j: JSONValue, kind: Advisers.Kind, current: JSONValue) -> AdviserOption {
        let own = j["own"].isNull ? nil : j["own"].int
        let isCurrent = own != nil ? current["own"].int == own : (!current.isNull && current["own"].isNull && current["id"].int == j["id"].int)
        return AdviserOption(id: own ?? j["id"].int, kind: kind, name: j["name"].string, rating: j["rating"].double,
                             reviews: j["reviews"].isNull ? nil : j["reviews"].int, monthlyFee: j["fee"].double,
                             premiumFactor: j["premM"].isNull ? nil : j["premM"].double, payoutReliability: j["payM"].isNull ? nil : j["payM"].double,
                             errorRate: j["err"].isNull ? nil : j["err"].double, isCurrent: isCurrent, ownFirmID: own)
    }

    func adviserChoices(companyID: Int, kind: Advisers.Kind) -> [AdviserOption] {
        guard let co = state.company(companyID) else { return [] }
        let current = Advisers.current(co, kind)
        let own = Advisers.ownFirms(state, for: companyID, kind: kind).map { adviserOption(Advisers.ownProvider(state, kind: kind, firm: $0, data: data), kind: kind, current: current) }
        return own + adviserOffers(companyID: companyID, kind: kind).map { adviserOption($0, kind: kind, current: current) }
    }

    func coverageOverview(companyID: Int) -> CoverageOverview? {
        guard let co = state.company(companyID) else { return nil }
        let w = World(state: state, data: data)
        func current(_ kind: Advisers.Kind) -> AdviserOption? {
            let j = Advisers.current(co, kind)
            return j.isNull ? nil : adviserOption(j, kind: kind, current: j)
        }
        let on = co.value("ins")
        let repriced = co.value("flags")["premUntil"].double > Double(state.week) ? 1 + co.value("flags")["premUp"].double : 1
        var policies = marketing.insuranceProducts.sorted { $0.key < $1.key }.compactMap { (k, p) -> InsurancePolicyRow? in
            guard p.count > 3 else { return nil }
            return InsurancePolicyRow(id: k, name: p[0].string, blurb: p[2].string, isOn: on[k].bool,
                                      weeklyPremium: CompanyCosts.insurancePremium(co, product: k, rate: p[3].double, w) * repriced)
        }
        let holdsStock: Bool = data.catalog[co.type].map { $0.hasTrait("stock") } ?? false
        if holdsStock || co.inventory > 0 || StockInsurance.isInsured(co) {
            let premium: Double = StockInsurance.isInsured(co) ? StockInsurance.weeklyPremium(co) : StockInsurance.estimatedWeeklyPremium(co)
            policies.append(InsurancePolicyRow(id: StockInsurance.product, name: "Stock", blurb: "Pays for stock lost to fire, water damage, theft or damage in transit, less an excess. About 1.2% of the stock held a year.",
                                               isOn: StockInsurance.isInsured(co), weeklyPremium: premium))
        }
        return CoverageOverview(insurer: current(.insurer), lawFirm: current(.law), policies: policies)
    }
}
