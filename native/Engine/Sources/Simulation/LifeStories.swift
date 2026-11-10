import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum LifeStory: String, CaseIterable, Sendable {
    case loan, heir
    case fresh

    public var title: String { self == .loan ? "Start-up loan" : self == .heir ? "Heir" : "New business" }
    public var tagline: String {
        switch self {
        case .loan: return "The bank lends you a start-up loan. The classic start."
        case .heir: return "The family café is yours: open, a small team and money in its account. A little money in yours, no loan."
        case .fresh: return "Your chosen business, set up and open on the first day. No loan."
        }
    }
    public var needsCity: Bool { self == .heir }
}

public struct StoryPreview: Equatable, Sendable {
    public var story: LifeStory
    public var cash: Double
    public var debt: Double
    public var monthlyRepayment: Double
    public var credit: Double
    public var netWorth: Double
    public var companyName: String?
    public var companyValue: Double
}

public extension GameEngine {
    static func storyPreview(_ story: LifeStory, countryCode: String, cityID: String? = nil) -> StoryPreview? {
        guard let e = try? GameEngine.newGame(countryCode: countryCode, playerName: "Preview", cityID: cityID, seed: 1, story: story) else { return nil }
        let own = e.state.companies.first
        let value = own.map { Valuation.companyValue($0, state: e.state, trades: e.data.catalog) } ?? 0
        return StoryPreview(story: story, cash: e.state.cash, debt: e.state.loans.reduce(0) { $0 + $1.balance },
                            monthlyRepayment: e.state.loans.reduce(0) { $0 + $1.monthlyPayment }, credit: e.state.credit, netWorth: e.netWorth.total,
                            companyName: own?.name, companyValue: value)
    }

    var lifeStory: LifeStory { LifeStory(rawValue: state.rest["start"]?["story"].string ?? "") ?? .loan }
}

enum LifeStories {
    static func applyFresh(_ s: inout GameState, data: GameData, context: FinanceContext, tradeID: String, name: String, chooseFirstItem: Bool = false) -> Bool {
        guard let bd = data.catalog[tradeID], SpecialFamilies.isStartable(bd), let country = data.countries[s.homeCountryCode],
              let city = country.city(s.player.cityID) ?? country.cities.first else { return false }
        let size = CompanySetup.recommendedSize(bd, city: city)
        let big = 1e9
        var probe = s
        Ledger.move(&probe, .me, big, why: "Start probe")
        guard let pid = build(&probe, data: data, context: context, tradeID: tradeID, cityID: city.id, size: size, name: name),
              let pi = probe.companyIndex(pid) else { return false }
        let spent: Double = big - probe.cash
        let weekly: Double = context.weeklyCost(probe.companies[pi], probe)
        let weeks: Double = Double(data.balance.firstYear.startRunwayWeeks)
        let cash: Double = ((spent + weekly * weeks) / 1000).rounded(.up) * 1000
        Ledger.move(&s, .me, cash, why: "Starting money")
        guard let id = build(&s, data: data, context: context, tradeID: tradeID, cityID: city.id, size: size, name: name),
              let i = s.companyIndex(id) else { return false }
        s.rest["start"] = .object(["story": .string(LifeStory.fresh.rawValue), "cash": .number(cash)])
        if chooseFirstItem { SalesItems.markFirstChoicePending(&s, i) }
        return s.companies[i].status == .open
    }

    private static func build(_ s: inout GameState, data: GameData, context: FinanceContext, tradeID: String, cityID: String, size: Double, name: String) -> Int? {
        guard case .success(let id) = CompanySetup.create(&s, tradeID: tradeID, cityID: cityID, size: size, name: name.isEmpty ? nil : name, data: data, context: context) else { return nil }
        let options = CompanySetup.SetupOptions(team: .minimum, optionalEquipment: false, payrollMonthsReserve: 2)
        _ = CompanySetup.quickSetupReport(&s, companyID: id, data: data, options: options)
        guard let i = s.companyIndex(id), let bd = data.catalog[s.companies[i].type] else { return nil }
        var docs = s.companies[i].value("docs")
        for d in Documents.needed(s.companies[i], bd, World(state: s, data: data)) where d != "vat_not_applicable" {
            var entry = docs[d]
            entry["st"] = .string("ok")
            for k in ["done", "ok", "w0"] where entry[k].isNull { entry[k] = .number(Double(s.week)) }
            docs[d] = entry
        }
        s.companies[i].set("docs", docs)
        s.companies[i].raw["ownOut"] = nil
        s.companies[i].ownerHours = 40
        _ = OpeningChecklist.open(&s, companyIndex: i, data: data)
        return id
    }

    static func applyHeir(_ s: inout GameState, data: GameData, context: FinanceContext) -> Bool {
        guard let bd = data.catalog["cafe"], let country = data.countries[s.homeCountryCode],
              let city = country.city(s.player.cityID) ?? country.cities.first else { return false }
        let currency = context.currency(country.code, s)
        let savings = currency.scaledPrice(50000)
        let size = CompanySetup.recommendedSize(bd, city: city)
        var probe = s; probe.cash += Double(Int32.max)
        guard let est = CompanySetup.estimate(tradeID: "cafe", cityID: city.id, size: size, state: probe, data: data) else { return false }
        let put = currency.tidy(est.total * 1.3)
        Ledger.move(&s, .me, put + savings + est.personalOutlay, why: "Inheritance: the family café and cash")
        let last = country.lastNames.isEmpty ? "Family" : s.random.pick(country.lastNames)
        guard case .success(let id) = CompanySetup.create(&s, tradeID: "cafe", cityID: city.id, size: size, name: "\(last) Café", data: data, context: context) else { return false }
        _ = CompanySetup.quickSetupReport(&s, companyID: id, data: data, options: CompanySetup.SetupOptions(optionalEquipment: true))
        guard let i = s.companyIndex(id) else { return false }
        let w = World(state: s, data: data)
        var docs = s.companies[i].value("docs")
        for d in Documents.needed(s.companies[i], bd, w) where d != "vat_not_applicable" {
            docs[d] = .object(["st": "ok", "done": .number(Double(s.week)), "ok": .number(Double(s.week)), "w0": .number(Double(s.week))])
        }
        s.companies[i].set("docs", docs)
        _ = OpeningChecklist.open(&s, companyIndex: i, data: data)
        s.companies[i].awareness = max(s.companies[i].awareness, 45)
        s.companies[i].reputation = max(s.companies[i].reputation, 60)
        s.companies[i].ownerHours = 25
        s.companies[i].set("inherited", 1)
        let left = s.cash - savings
        if left > 0 { Payments.playerPays(&s, left, label: "Inheritance tax and lawyer") }
        s.rest["start"] = .object(["story": .string(LifeStory.heir.rawValue)])
        return s.companies[i].status == .open
    }
}
