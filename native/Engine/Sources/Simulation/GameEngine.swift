import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses
import Investments
import Events

/// The game itself: creates a new game, moves time forward one day at a time, and answers the player's actions.
///
/// ORDER OF A DAY (documented so every change of money and state has a reason):
///  Monday..Saturday (days 1-6):  1. the day number moves on
///                                2. every open company trades the day (customers, sales, cash in)
///                                3. payroll and bills that fall due today are paid (see `Payday`)
///                                4. the week's already-worked-out money flows release a slice of themselves
///  Sunday -> Monday (week change): the whole week is worked out in this order, then released over the next 7 days:
///                                1. economy, stock markets, competitors, funds, investments
///                                2. for each company: documents, customers sold, books, costs, staff, marketing, events
///                                3. unanswered decisions expire
///                                4. month end (every company, then you), year end
///                                5. companies that cannot pay are declared bankrupt
///                                6. net worth history, bank checks, game over
public struct GameEngine {
    public private(set) var state: GameState
    public let data: GameData
    public let context: FinanceContext
    public let events: EventLibrary
    public let marketing: MarketingTables

    public init(state: GameState, data: GameData, events: EventLibrary, marketing: MarketingTables) {
        var state = state
        Markets.refreshNames(&state, country: data.countries.resolve(state.homeCountryCode, orHome: state.homeCountryCode))
        self.state = state
        self.data = data
        self.events = events
        self.marketing = marketing
        var lending = LendingModifiers()
        lending.marginAdjustment = { [data] _, _, s in -Ambitions.loanMarginCut(s, data) }   // the financier / dynasty ambition perk: cheaper loans
        self.context = FinanceContext(countries: data.countries, trades: data.catalog, lending: lending)
    }

    /// Load all bundled data. Throws if a data file is missing or broken.
    public static func loadResources() throws -> (GameData, EventLibrary, MarketingTables) {
        (try GameData.bundled(), try EventLibrary.bundled(), try MarketingTables.bundled())
    }

    // MARK: New game

    /// Start a new game. Original: `newGame` (engine/core/state.js). The player begins with a start-up loan and an empty
    /// current account of that size, and no companies.
    public static func newGame(countryCode: String, playerName: String, cityID: String? = nil, seed: Int? = nil, age: Int = 30) throws -> GameEngine {
        let (data, events, marketing) = try loadResources()
        guard let country = data.countries[countryCode] ?? data.countries.countries.first else { throw CocoaError(.fileReadUnknown) }
        let seed = seed ?? Int(Date().timeIntervalSince1970) % 2147483647
        let fxRates = ExchangeRates()
        let currency = Currency(country: country, rates: fxRates)
        let loan = currency.tidy(country.startLoan)
        var json: [String: JSONValue] = [:]
        json["v"] = .number(Double(GameState.legacyVersion))
        json["seed"] = .number(Double(seed)); json["rs"] = .number(Double(Int32(truncatingIfNeeded: seed)))
        json["uid"] = 1000; json["week"] = 0; json["day"] = 0; json["country"] = .string(country.code)
        json["player"] = .object(["name": .string(playerName.isEmpty ? "You" : playerName), "age": .number(Double(min(110, max(1, age)))),
                                  "city": .string(cityID ?? country.cities[0].id), "skill": .object([:])])
        json["cash"] = .number(loan); json["cash0"] = .number(loan); json["flow"] = .object([:]); json["sav"] = .object(["bal": 0])
        json["loans"] = .array([]); json["credit"] = 62; json["overdraft"] = 0
        json["overdraftLimit"] = .number(currency.scaledPrice(25000))
        json["inv"] = .object(["stocks": .object([:]), "crypto": .object([:]), "funds": .object([:]), "deposits": .array([])])
        json["mk"] = .object([:]); json["rivals"] = .object([:]); json["cos"] = .array([]); json["npcs"] = .object([:])
        json["pool"] = .object(["acc": .array([])]); json["inbox"] = .array([]); json["news"] = .array([]); json["rep"] = .null
        json["hist"] = .object(["nw": .array([]), "cash": .array([])]); json["log"] = .array([])
        json["econ"] = .object(["phase": "steady", "dem": 1.0, "infl": 0.03, "fuel": 1.0, "mat": 1.0, "power": 1.0, "oil": 1.0, "housing": 1.0,
                                "rate": .number(max(0.0025, country.startingPolicyRate)), "left": 12, "freight": 1.0])
        json["tax"] = .object(["ytd": 0, "paid": 0, "enkIncome": 0, "wage": 0, "div": 0, "ytdDiv": 0, "bank": 0])
        json["office"] = .object(["tier": "home", "city": .string(cityID ?? country.cities[0].id), "since": 0, "staff": .array([]),
                                  "rep": .object(["freq": 4, "detail": "short", "only": "managed"])])
        json["group"] = .object(["ceo": .null, "regional": .array([]), "big": .number(currency.scaledPrice(5_000_000))])
        json["deals"] = .array([]); json["startups"] = .array([]); json["fundHold"] = .array([]); json["wealthPaid"] = 0
        json["stats"] = .object(["peak": 0, "bankrupt": 0, "firstWeek": 0, "years": 0, "sold": 0, "dividends": 0, "taxPaid": 0, "wagesPaid": 0])
        json["over"] = .null; json["settings"] = .object(["adv": 1, "confirm": 1]); json["flags"] = .object([:])
        json["dmode"] = 1
        var state = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(JSONValue.object(json)))
        var l = Loan(raw: [:])
        l.id = state.makeID(); l.kind = "start"; l.name = "Start-up loan"; l.balance = loan; l.set("rate", 0); l.margin = 0.045
        l.termMonths = country.startLoanTermMonths; l.companyID = 0; l.startWeek = 0; l.isGuaranteed = false
        l.monthlyPayment = Loans.annuity(principal: loan, yearlyRate: state.economy.policyRate + 0.045, months: Double(country.startLoanTermMonths))
        state.loans.append(l)
        state.economy.set("rate0", state.economy.policyRate)
        PlayerGoals.startFirstSteps(&state)
        Markets.initialize(&state, country: country)
        _ = Providers.pool(for: country.code, state: &state, countries: data.countries)
        state.note("Welcome to Ledger. You have a start-up loan of \(currency.display(loan)). Open your first business from the Phone.", tone: "good")
        let bank = country.pack["authorities"]["cb"].string
        state.news("\(bank): policy rate unchanged at \(Currency.percent(state.economy.policyRate, decimals: 2)). New year, new opportunities.")
        var engine = GameEngine(state: state, data: data, events: events, marketing: marketing)
        engine.openReportBaselines()
        engine.snapshot()
        engine.recordDay()
        return engine
    }

    // MARK: Reading

    public var netWorth: NetWorth { Valuation.netWorth(state, trades: data.catalog) }
    public var homeCurrency: Currency { context.homeCurrency(state) }
    public var homeCountry: Country { context.homeCountry(state) }
    public var date: String { GameCalendar.dateString(week: state.week, dayOffset: state.day) }

    /// Record net worth for the charts. Original: `snapshot`.
    mutating func snapshot() {
        let nw = netWorth.total
        state.netWorthHistory.append(jsRound(nw))
        if state.netWorthHistory.count > 520 { state.netWorthHistory.remove(at: 1) }
        state.stats.peakNetWorth = max(state.stats.peakNetWorth, nw)
    }

    /// Replace the state, e.g. after the player acts through a service in a view model.
    public mutating func update(_ body: (inout GameState, GameData, FinanceContext) -> Void) {
        body(&state, data, context)
    }

    // MARK: Answering the inbox

    /// The player picks one of the options of an open message (a decision, a payroll approval ...).
    @discardableResult
    public mutating func answer(messageID: Int, option: Int) -> Bool {
        let d = data, c = context, mk = marketing
        let ok = EventEngine.answer(&state, messageID: messageID, option: option, data: d, context: c) { s, m, idx in
            if m.actionID == StrategicDecisions.action { StrategicDecisions.answer(&s, message: m, option: idx, data: d, context: c); return true }
            if ManagerModel.handlesAnswer(m.actionID) { ManagerModel.answerGroup(&s, message: m, option: idx, data: d, context: c, marketing: mk); return true }
            if m.actionID == "staffx" { StaffTalks.answer(&s, message: m, option: idx, data: d); return true }
            if ["prop", "mgrraise", "mgrpoach"].contains(m.actionID) { ManagerModel.answer(&s, message: m, option: idx, data: d); return true }
            if ManagerTargets.handlesAnswer(m.actionID) { ManagerTargets.answer(&s, message: m, option: idx, data: d); return true }
            if m.actionID == "oil24" { EnergyModel.answer(&s, message: m, option: idx); return true }
            if m.actionID == "club24" { FootballModel.answerBid(&s, message: m, option: idx); return true }
            if Franchising.handlesAnswer(m.actionID) { Franchising.answer(&s, message: m, option: idx, context: c); return true }
            if Ventures.handlesAnswer(m.actionID) { return Ventures.answer(&s, message: m, option: idx, data: d, context: c) }
            if m.actionID == "acct" { KeyAccounts.answer(&s, message: m, option: idx); return true }
            if m.actionID == VolumeContracts.action { VolumeContracts.answer(&s, message: m, option: idx); return true }
            if m.actionID == "g27poach" { RivalGroups.answerPoach(&s, message: m, option: idx, data: d); return true }
            if m.actionID == RivalBids.action { RivalBids.answer(&s, message: m, option: idx, data: d, context: c); return true }
            if m.actionID == "fav31" { WorldAround.answerFavour(&s, message: m, option: idx, data: d); return true }
            if m.actionID == "sue16" { Lawsuits.answer(&s, message: m, option: idx, data: d); return true }
            if m.actionID == "cy56r" { Cyber.answerRansom(&s, message: m, option: idx, data: d); return true }
            if m.actionID == "cy56l" { Cyber.answerLeak(&s, message: m, option: idx, data: d); return true }
            if Stories.handlesAnswer(m.actionID) { Stories.answer(&s, message: m, option: idx, data: d); return true }
            if m.actionID == Press.interviewAction { Press.answerInterview(&s, questionIndex: m.value("data")["q"].int, option: idx); return true }
            if m.actionID == WeatherEvents.prepareAction { WeatherEvents.answerPrepare(&s, data: d, message: m, option: idx); return true }
            Payday.answer(&s, action: m.actionID, data: m.value("data"), option: idx, companyID: m.companyID, data: d, context: c)
            return true
        }
        if ok { ReportCounters.add(&state, ReportCounters.Key.answered, 1) }
        return ok
    }

    /// Open messages waiting for an answer, newest first.
    public var openDecisions: [Message] { state.inbox.filter { $0.status == "open" } }

    // MARK: Time

    public struct DayOutcome {
        public var newMessages: [Message]
        public var completedWeek: Bool
        public var gameOver: Bool
    }

    /// Move one day forward. Original: `dayStep`.
    @discardableResult
    public mutating func nextDay() -> DayOutcome {
        let before = Set(state.inbox.map { $0.id })
        state.dayMode = true
        var completed = false
        if state.isGameOver { return DayOutcome(newMessages: [], completedWeek: false, gameOver: true) }
        if state.day < 6 {
            state.day += 1
            tradeAndPay(day: state.day)
            releaseDay(state.day)
        } else {
            // The seventh day is over: the week's money has all been released, so the week (and a month or year that ends with it) can be reported.
            closeReportPeriods()
            state.rest["pend"] = .null
            state.day = 0
            stageWeek()
            if !state.isGameOver {
                tradeAndPay(day: 0)
                releaseDay(0)
            }
            completed = true
        }
        recordDay()
        let fresh = state.inbox.filter { !before.contains($0.id) }
        return DayOutcome(newMessages: fresh, completedWeek: completed, gameOver: state.isGameOver)
    }

    /// Go on until something needs the player: a decision, bad news, game over, or `maxDays`. Original: "Until needed".
    public mutating func advanceUntilNeeded(maxDays: Int = 26 * 7) -> (days: Int, reason: String?) {
        var n = 0
        while n < maxDays && !state.isGameOver {
            let r = nextDay()
            n += 1
            if let m = r.newMessages.first(where: { $0.status == "open" || (!$0.isRead && $0.tone == "bad") }) { return (n, m.title) }
        }
        return (n, state.isGameOver ? "Game over" : nil)
    }

    mutating func tradeAndPay(day: Int) {
        DailyTrade.runDay(&state, day: day, data: data)
        ProjectWeek.runDay(&state, day: day, data: data)
        Payday.onDay(&state, data: data, context: context)
    }

    // MARK: The week, worked out at once and released over the next seven days

    mutating func stageWeek() {
        let meBefore = state.cash
        var coBefore: [Int: Double] = [:]
        var txBefore: [Int: String] = [:]
        for c in state.companies { coBefore[c.id] = c.cash; txBefore[c.id] = c.transactions.first.map { "\($0["w"].int):\($0["a"].double):\($0["l"].string)" } }
        let inboxBefore = Set(state.inbox.map { $0.id })
        let newsBefore = (state.rest["news"]?.array ?? []).count
        state.transient.stagedPlayerLines = []
        state.rest["rep"] = .object(["ev": .array([]), "w": .number(Double(state.week)), "from": .number(Double(state.week)),
                                     "nw0": .number(netWorth.total), "cash0": .number(state.cash)])
        advanceWeek()
        let rows = state.transient.stagedPlayerLines ?? []
        state.transient.stagedPlayerLines = nil
        if state.isGameOver {
            for r in rows { Ledger.addStatementLine(&state, amount: r.amount, label: r.label, companyID: r.companyID) }
            state.rest["pend"] = .null
            return
        }
        var pend: [String: JSONValue] = [:]
        let meDelta = state.cash - meBefore
        var staged = rows.map { (amount: $0.amount, label: $0.label, companyID: $0.companyID) }
        let left = meDelta - staged.reduce(0) { $0 + $1.amount }
        if abs(left) >= 1 { staged.append((left, "Other", 0)) }
        var rm = HashedRandom("\(state.seed):me:\(state.week)")
        pend["me"] = .number(meDelta)
        pend["rows"] = .array(staged.map { .object(["a": .number($0.amount), "l": .string($0.label), "co": .number(Double($0.companyID)), "d": .number((rm.next() * 7).rounded(.down))]) })
        if meDelta != 0 { Ledger.moveRaw(&state, .me, -meDelta) }
        var coList: [JSONValue] = []
        for i in state.companies.indices {
            let id = state.companies[i].id
            guard let b = coBefore[id] else { continue }
            let d = state.companies[i].cash - b
            if d != 0 {
                var one = 0.0
                for t in state.companies[i].transactions {
                    if "\(t["w"].int):\(t["a"].double):\(t["l"].string)" == txBefore[id] { break }
                    if t["a"].double < 0 { one += t["a"].double }
                }
                coList.append(.array([.number(Double(id)), .number(d), .number(jsRound(one))]))
                Ledger.moveRaw(&state, .company(id), -d)
            }
        }
        pend["co"] = .array(coList)
        var r = HashedRandom("\(state.seed):day:\(state.week)")
        var msgs: [JSONValue] = []
        let fresh = state.inbox.filter { !inboxBefore.contains($0.id) }
        state.inbox.removeAll { !inboxBefore.contains($0.id) }
        for m in fresh { msgs.append(.object(["m": .object(m.raw), "d": .number((r.next() * 7).rounded(.down))])) }
        pend["msgs"] = .array(msgs)
        let allNews = state.rest["news"]?.array ?? []
        let addedNews = Array(allNews.prefix(max(0, allNews.count - newsBefore)))
        state.rest["news"] = .array(Array(allNews.dropFirst(max(0, allNews.count - newsBefore))))
        pend["news"] = .array(addedNews.map { .object(["n": $0, "d": .number((r.next() * 7).rounded(.down))]) })
        state.rest["pend"] = .object(pend)
    }

    /// The part of the staged week that lands today. Original: `releaseDay`.
    mutating func releaseDay(_ day: Int) {
        guard let P = state.rest["pend"], !P.isNull else { return }
        let d = Double(day)
        func part(_ total: Double) -> Double { jsRound(total * (d + 1) / 7) - jsRound(total * d / 7) }
        for row in P["rows"].array where row["d"].double == d {
            Ledger.moveRaw(&state, .me, row["a"].double)
            Ledger.addStatementLine(&state, amount: row["a"].double, label: row["l"].string, companyID: row["co"].int)
        }
        for x in P["co"].array {
            let id = x[0].int, total = x[1].double, one = x[2].double
            let oneOff = one + min(0, total - one)
            let v = part(total - oneOff) + (day == 0 ? oneOff : 0)
            if v != 0, state.companyIndex(id) != nil { Ledger.moveRaw(&state, .company(id), v) }
        }
        var got: [Message] = []
        for x in P["msgs"].array.reversed() where x["d"].double == d {
            let m = Message(raw: x["m"].object)
            state.inbox.insert(m, at: 0)
            got.append(m)
        }
        var news = state.rest["news"]?.array ?? []
        for x in P["news"].array.reversed() where x["d"].double == d { news.insert(x["n"], at: 0) }
        state.rest["news"] = .array(news)
    }

    // MARK: The weekly turn

    /// Everything that changes in the world in one week. Original: `nextWeek0`.
    mutating func advanceWeek() {
        if state.isGameOver { return }
        state.transient.simulatingWeek = true
        defer { state.transient.simulatingWeek = false }
        state.week += 1
        WorldWeek.economy(&state, data: data)
        Markets.weekly(&state)
        WorldWeek.competitors(&state, data: data)
        FootballModel.leaguesWeek(&state, data: data)
        Markets.fundsWeekly(&state)
        Brokerage.weekly(&state)
        FinanceManager.weekly(&state, context: context)   // your fund manager's returns, the office finance manager's holdings
        Luxury.weekly(&state)
        for i in state.companies.indices {
            guard state.companies[i].status.isLive else { continue }
            CompanyWeek.run(&state, companyIndex: i, data: data, marketing: marketing)
            if state.companies[i].status == .open, let bd = data.catalog[state.companies[i].type], CompanyWeek.isSupported(bd) {
                EventEngine.spawn(&state, companyIndex: i, library: events, data: data, context: context)
            }
            if state.companies[i].status == .open || state.companies[i].status == .closed {
                var trf = state.companies[i].value("trf").array
                trf.append(.number(jsRound(((state.companies[i].value("lastW")["D"].double != 0 ? state.companies[i].value("lastW")["D"].double : state.companies[i].lastWeekUnits)) * 10) / 10))
                if trf.count > 52 { trf.removeFirst() }
                state.companies[i].set("trf", .array(trf))
            }
        }
        // Customers, competition and reputation: rivals and their groups, price moves, lawsuits, cyber attacks, market shares.
        Rivals.weekly(&state, data: data)
        PriceMoves.weekly(&state, data: data)
        Lawsuits.weekly(&state, data: data)
        Cyber.weekly(&state, data: data)
        MarketMap.weekly(&state, data: data)
        SoftwareProducts.weekly(&state, data: data)
        ProjectTenders.weekly(&state, data: data, context: context)
        AutoStaff.weekly(&state, data: data)
        EventEngine.expire(&state, data: data, context: context)
        StrategicDecisions.weekly(&state, data: data, context: context)
        Ventures.weekly(&state, data: data, context: context)   // startups, private equity, the big meeting, owners of your companies
        Awards.weekly(&state, data: data, context: context)
        SpecialFamilies.weeklyAfter(&state, data: data, context: context)
        Chains.weekly(&state, data: data, context: context, marketing: marketing)   // chains, franchises, supply between your companies
        MiscWeekly.run(&state, data: data, context: context)   // staff record, ambitions, giving, weather, cyber, perks ... (MiscWeekly.swift)
        if GameCalendar.isMonthEnd(week: state.week) { MonthEnd.closeMonth(&state, data: data, context: context) }
        if GameCalendar.isYearEnd(week: state.week) { MonthEnd.closeYear(&state, data: data, context: context) }
        ManagerTargets.weekly(&state, data: data)   // monthly targets and yearly budget of managed companies (after the month is closed)
        for i in state.companies.indices {
            let c = state.companies[i]
            if (c.status == .open || c.status == .closed) && c.weeksNegative > 12 && c.cash < -context.overdraftRoom(c, state) * 2 {
                Failure.bankrupt(&state, companyIndex: i, reason: "cash", data: data, context: context)
            }
            else if (c.status == .open || c.status == .closed) && c.cash < 0 && Payday.unpaidForMonths(c, today: Payday.dayNumber(week: state.week, day: state.day)) {
                // Rent, suppliers or tax left unpaid for months while the account is empty: creditors close the company.
                Failure.bankrupt(&state, companyIndex: i, reason: "unpaid", data: data, context: context)
            }
        }
        for id in FinanceModel.insolventCompanies(&state, data: data) {
            if let i = state.companyIndex(id) { Failure.bankrupt(&state, companyIndex: i, reason: "insolvent", data: data, context: context) }
        }
        snapshot()
        Failure.checkOver(&state, data: data, context: context, liquidate: { s, need in Brokerage.liquidate(&s, need: need); FinanceManager.cashIn(&s, need: need) })
    }
}
