import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// One insurance policy a company can hold (property, liability, cyber ...), with what it costs a week.
public struct InsurancePolicyRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var blurb: String
    public var isOn: Bool
    /// What it would cost (or costs) each week, with the insurer's price factor and any repricing after a lost lawsuit.
    public var weeklyPremium: Double
}

/// A provider of one of the three advisers: accountant, law firm or insurer (your own group firm included).
public struct AdviserOption: Equatable, Sendable, Identifiable {
    public var id: Int
    public var kind: Advisers.Kind
    public var name: String
    public var rating: Double
    public var reviews: Int?
    /// Accountant and law firm: a monthly fee. Insurers: 0 (they charge premiums).
    public var monthlyFee: Double
    /// Insurer: premiums as a multiple of the standard rate (below 1 is cheaper).
    public var premiumFactor: Double?
    /// Insurer: how reliably a claim is paid in full.
    public var payoutReliability: Double?
    /// Accountant: how often the books are wrong.
    public var errorRate: Double?
    public var isCurrent: Bool
    /// Set when the provider is one of your own companies.
    public var ownFirmID: Int?
}

public struct CoverageOverview: Equatable, Sendable {
    public var insurer: AdviserOption?
    public var lawFirm: AdviserOption?
    public var accountant: AdviserOption?
    public var policies: [InsurancePolicyRow]
    public var activeCount: Int { policies.filter { $0.isOn }.count }
    public var weeklyPremiums: Double { policies.filter { $0.isOn }.reduce(0) { $0 + $1.weeklyPremium } }
    public var lawMonthly: Double { lawFirm?.monthlyFee ?? 0 }
}

public extension GameEngine {
    /// Make sure the country's pool of accountants, law firms and insurers exists in the real game, so the ids a screen shows are the ids
    /// a hire uses. Safe to call again.
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

    /// Providers on offer for one kind, your own firms first, then the market by rating.
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
        let policies = marketing.insuranceProducts.sorted { $0.key < $1.key }.compactMap { (k, p) -> InsurancePolicyRow? in
            guard p.count > 3 else { return nil }
            return InsurancePolicyRow(id: k, name: p[0].string, blurb: p[2].string, isOn: on[k].bool,
                                      weeklyPremium: CompanyCosts.insurancePremium(co, product: k, rate: p[3].double, w) * repriced)
        }
        return CoverageOverview(insurer: current(.insurer), lawFirm: current(.law), accountant: current(.accountant), policies: policies)
    }
}
