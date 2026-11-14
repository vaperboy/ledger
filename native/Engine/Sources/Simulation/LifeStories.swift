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
        case .fresh: return "Your chosen business, open on the first day. The bank lends what the kit costs beyond your savings."
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
        // The grant only ever funds a starter trade; bigger trades are opened later with the player's own money.
        guard TradeUnlocks.isStarter(tradeID), let bd = data.catalog[tradeID], SpecialFamilies.isStartable(bd), let country = data.countries[s.homeCountryCode],
              let city = country.city(s.player.cityID) ?? country.cities.first else { return false }
        let size = CompanySetup.recommendedSize(bd, city: city)
        let fy = data.balance.firstYear
        let weeks: Double = Double(fy.startRunwayWeeks)
        let currency = context.currency(country.code, s)
        let floor: Double = country.shareCapitalMinimum + country.registrationFee
        // Every starter brings the same own savings.
        let savings: Double = max(floor, currency.tidy(currency.scaledPrice(fy.startSavings)))
        Ledger.move(&s, .me, savings, why: "Starting money")
        // Setup runs as if fully funded, so every trade buys its minimum kit and team; the money is settled right after.
        let bridge: Double = 1e9
        Ledger.moveRaw(&s, .me, bridge)
        guard let id = build(&s, data: data, context: context, tradeID: tradeID, cityID: city.id, size: size, name: name),
              let i = s.companyIndex(id) else { return false }
        Ledger.moveRaw(&s, .me, -bridge)
        // Savings pay for the opening first; the bank lends what the kit and fit-out cost beyond them, so part of the savings stays as working money.
        let keep: Double = savings * fy.startKeepShare
        let loan: Double = StartGrant.roundUp(max(0, keep - s.cash))
        let monthly: Double = OpeningLoan.open(&s, companyID: id, amount: loan)
        // The grant is a short runway of running costs, capped at a share of the savings, so no trade starts much richer than another.
        let weekly: Double = context.weeklyCost(s.companies[i], s) + monthly * 12 / 52
        let grant: Double = StartGrant.roundUp(min(savings * fy.startGrantCapShare, max(0, weekly * weeks)))
        StartGrant.pay(&s, companyID: id, amount: grant)
        s.rest["start"] = .object(["story": .string(LifeStory.fresh.rawValue), "cash": .number(savings + grant), "own": .number(savings), "grant": .number(grant),
                                   "loan": .number(loan), "weeks": .number(weeks)])
        if chooseFirstItem { SalesItems.markFirstChoicePending(&s, i) }
        return s.companies[i].status == .open
    }

    private static func build(_ s: inout GameState, data: GameData, context: FinanceContext, tradeID: String, cityID: String, size: Double, name: String) -> Int? {
        guard case .success(let id) = CompanySetup.create(&s, tradeID: tradeID, cityID: cityID, size: size, name: name.isEmpty ? nil : name, data: data, context: context) else { return nil }
        let options = CompanySetup.SetupOptions(team: .minimum, optionalEquipment: false, payrollMonthsReserve: 2)
        _ = CompanySetup.quickSetupReport(&s, companyID: id, data: data, options: options)
        guard let i = s.companyIndex(id), let bd = data.catalog[s.companies[i].type] else { return nil }
        var docs = s.companies[i].value("docs")
        for d in Documents.needed(s.companies[i], bd, World(state: s, data: data)) {
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
        for d in Documents.needed(s.companies[i], bd, w) {
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

/// The bank loan that pays for a first company's kit and fit-out beyond the owner's savings, repaid monthly over five years.
public enum OpeningLoan {
    public static let label = "Opening loan"
    static let months = 60
    static let margin = 0.035

    /// Books the loan on the company and pays the money into its account; returns the monthly instalment.
    @discardableResult
    static func open(_ s: inout GameState, companyID: Int, amount: Double) -> Double {
        guard amount > 0, let i = s.companyIndex(companyID) else { return 0 }
        var l = Loan(raw: [:])
        l.id = s.makeID(); l.kind = "biz"; l.name = label
        l.balance = amount; l.originalAmount = amount; l.margin = margin
        l.termMonths = months; l.companyID = companyID; l.startWeek = s.week; l.isGuaranteed = false
        l.monthlyPayment = Loans.annuity(principal: amount, yearlyRate: s.economy.policyRate + margin, months: Double(months))
        s.loans.append(l)
        Payments.companyReceives(&s, companyID: companyID, amount: amount, category: nil, label: label, bookInPnL: false)
        s.companies[i].addTransaction(week: s.week, amount: jsRound(amount), label: label)
        return l.monthlyPayment
    }

    public static func amount(_ s: GameState) -> Double { s.rest["start"]?["loan"].double ?? 0 }
}

/// Government start-up support: a short runway of running costs, never more than the owner's savings. It is no achievement, so goals leave it out.
public enum StartGrant {
    public static let label = "Government start-up grant"

    static func roundUp(_ v: Double) -> Double { (v / 100).rounded(.up) * 100 }

    static func pay(_ s: inout GameState, companyID: Int, amount: Double) {
        guard amount > 0, let i = s.companyIndex(companyID) else { return }
        Payments.companyReceives(&s, companyID: companyID, amount: amount, category: nil, label: label, bookInPnL: false)
        s.companies[i].addTransaction(week: s.week, amount: jsRound(amount), label: label)
    }

    public static func amount(_ s: GameState) -> Double { s.rest["start"]?["grant"].double ?? 0 }
}
