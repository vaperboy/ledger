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

    public var title: String { self == .loan ? "Start-up loan" : "Heir" }
    public var tagline: String {
        self == .loan ? "The bank lends you a start-up loan. The classic start."
                      : "The family café is yours: open, a small team and money in its account. A little savings, no loan."
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
