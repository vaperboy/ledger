import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Who you are when the game starts. Original: `STORY57` (features/player/life_stories.js).
/// Only the start-up loan (the classic start, and what every older game has) and the heir are built; the student and the
/// investor's kid wait for a decision on their cash and severance. Saved in `rest["start"]` only for non-default stories,
/// so a game started the default way is unchanged and an older save without the key is a start-up loan game.
public enum LifeStory: String, CaseIterable, Sendable {
    case loan, heir
    /// The new-player start: one chosen trade, fully set up and open on day 1, cash for the first weeks, no loan.
    case fresh

    public var title: String { self == .loan ? "Start-up loan" : self == .heir ? "Heir" : "New business" }
    public var tagline: String {
        switch self {
        case .loan: return "The bank lends you a start-up loan. The classic start."
        case .heir: return "The family café is yours: open, a small team and money in its account. A little savings, no loan."
        case .fresh: return "Your chosen business, set up and open on the first day. No loan."
        }
    }
    /// Cities matter only for the heir, whose café already exists.
    public var needsCity: Bool { self == .heir }
}

/// The real numbers of a story in a country, read from a game the engine actually builds (never typed in).
public struct StoryPreview: Equatable, Sendable {
    public var story: LifeStory
    public var cash: Double
    public var debt: Double
    public var monthlyRepayment: Double
    public var credit: Double
    public var netWorth: Double
    /// The business you start with (heir): its name and what it is worth to you.
    public var companyName: String?
    public var companyValue: Double
}

public extension GameEngine {
    /// What a story gives in this country: builds a game with a fixed seed and reads the result. Nil if the story cannot start there.
    static func storyPreview(_ story: LifeStory, countryCode: String, cityID: String? = nil) -> StoryPreview? {
        guard let e = try? GameEngine.newGame(countryCode: countryCode, playerName: "Preview", cityID: cityID, seed: 1, story: story) else { return nil }
        let own = e.state.companies.first
        let value = own.map { Valuation.companyValue($0, state: e.state, trades: e.data.catalog) } ?? 0
        return StoryPreview(story: story, cash: e.state.cash, debt: e.state.loans.reduce(0) { $0 + $1.balance },
                            monthlyRepayment: e.state.loans.reduce(0) { $0 + $1.monthlyPayment }, credit: e.state.credit, netWorth: e.netWorth.total,
                            companyName: own?.name, companyValue: value)
    }

    /// The story this game started with (older saves: the start-up loan).
    var lifeStory: LifeStory { LifeStory(rawValue: state.rest["start"]?["story"].string ?? "") ?? .loan }
}

enum LifeStories {
    /// The new-player start: the chosen trade is created, set up to the cheapest option that opens it, and opened on day 1.
    /// The starting cash is the cost of all that plus `startRunwayWeeks` weeks of fixed costs and payroll, rounded up to the next 1,000. It is
    /// measured on a copy of the game (set up with plenty of money) and then paid for real, so it follows every trade and country by itself.
    static func applyFresh(_ s: inout GameState, data: GameData, context: FinanceContext, tradeID: String, name: String) -> Bool {
        guard let bd = data.catalog[tradeID], SpecialFamilies.isStartable(bd), let country = data.countries[s.homeCountryCode],
              let city = country.city(s.player.cityID) ?? country.cities.first else { return false }
        let form: LegalForm = bd.needsLimitedCompany ? .limited : .soleTrader
        let size = CompanySetup.recommendedSize(bd, city: city)
        let big = 1e9
        var probe = s
        Ledger.move(&probe, .me, big, why: "Start probe")
        guard let pid = build(&probe, data: data, context: context, tradeID: tradeID, cityID: city.id, form: form, size: size, name: name),
              let pi = probe.companyIndex(pid) else { return false }
        let spent: Double = big - probe.cash - probe.companies[pi].cash
        let weekly: Double = context.weeklyCost(probe.companies[pi], probe)
        let weeks: Double = Double(data.balance.firstYear.startRunwayWeeks)
        let cash: Double = ((spent + weekly * weeks) / 1000).rounded(.up) * 1000
        Ledger.move(&s, .me, cash, why: "Starting money")
        guard let id = build(&s, data: data, context: context, tradeID: tradeID, cityID: city.id, form: form, size: size, name: name),
              let i = s.companyIndex(id) else { return false }
        s.rest["start"] = .object(["story": .string(LifeStory.fresh.rawValue), "cash": .number(cash)])
        return s.companies[i].status == .open
    }

    /// Creates the company, puts all the player's money into it, buys what the trade cannot open without (premises, required equipment, papers,
    /// the minimum team), puts the owner to work in it and opens it. Returns its id.
    private static func build(_ s: inout GameState, data: GameData, context: FinanceContext, tradeID: String, cityID: String, form: LegalForm, size: Double, name: String) -> Int? {
        guard case .success(let id) = CompanySetup.create(&s, tradeID: tradeID, cityID: cityID, form: form, size: size, name: name.isEmpty ? nil : name, data: data, context: context) else { return nil }
        _ = Payments.injectCash(&s, companyID: id, amount: s.cash)
        // The minimum team, and all the equipment the trade needs to serve customers (some of it, such as a café's furniture, is not on the opening
        // checklist but capacity is zero without it).
        let options = CompanySetup.SetupOptions(team: .minimum, optionalEquipment: true, payrollMonthsReserve: 2)
        _ = CompanySetup.quickSetupReport(&s, companyID: id, data: data, options: options)
        guard let i = s.companyIndex(id), let bd = data.catalog[s.companies[i].type] else { return nil }
        // The papers are applied for (fees paid) and are in order on day 1.
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

    /// The heir: a running café, money in its account, savings in yours, no loan. Money arrives and leaves only through the ledger.
    static func applyHeir(_ s: inout GameState, data: GameData, context: FinanceContext) -> Bool {
        guard let bd = data.catalog["cafe"], let country = data.countries[s.homeCountryCode],
              let city = country.city(s.player.cityID) ?? country.cities.first else { return false }
        let currency = context.currency(country.code, s)
        let savings = currency.scaledPrice(50000)
        let size = CompanySetup.recommendedSize(bd, city: city)
        // The estimate needs the owner to hold the share capital; price it on a copy that does.
        var probe = s; probe.cash += Double(Int32.max)
        guard let est = CompanySetup.estimate(tradeID: "cafe", cityID: city.id, form: .limited, size: size, state: probe, data: data) else { return false }
        let put = currency.tidy(est.total * 1.3)
        Ledger.move(&s, .me, put + savings + est.personalOutlay, why: "Inheritance: the family café and savings")
        let last = country.lastNames.isEmpty ? "Family" : s.random.pick(country.lastNames)
        guard case .success(let id) = CompanySetup.create(&s, tradeID: "cafe", cityID: city.id, form: .limited, size: size, name: "\(last) Café", data: data, context: context),
              Payments.injectCash(&s, companyID: id, amount: put) else { return false }
        _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        guard let i = s.companyIndex(id) else { return false }
        // The family has run it for years: the papers are in order and the people know the job.
        let w = World(state: s, data: data)
        var docs = s.companies[i].value("docs")
        for d in Documents.needed(s.companies[i], bd, w) where d != "vat_not_applicable" {
            docs[d] = .object(["st": "ok", "done": .number(Double(s.week)), "ok": .number(Double(s.week)), "w0": .number(Double(s.week))])
        }
        s.companies[i].set("docs", docs)
        var staff = s.companies[i].staff
        for k in staff.indices { for it in StaffExtras.items(role: staff[k].role) { StaffExtras.tick(&staff[k], key: it.key) } }
        s.companies[i].staff = staff
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
