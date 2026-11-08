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
/// ORDER OF A DAY (documented so every change of money and state has a reason). Every day is the same; the calendar only decides
/// which weekday a process has and which day closes a month:
///  1. the day number moves on (after day 6 the week counter turns and the week just ended is reported from what the days did)
///  2. the day's slice of the weekly processes: companies whose slot is today (`GameCalendar.slot`) run their seven-day model,
///     then the world process of today's weekday (see `runWorldProcesses`); the money and messages of the slice are held back
///  3. on the last day of a month the books close (every company, then you), on 31 December the year too
///  4. every open company trades the day (customers, sales, cash in)
///  5. payroll and bills that fall due today are paid (see `Payday`)
///  6. a seventh of every held-back batch (this slice's and the six before it) lands
public struct GameEngine {
    public private(set) var state: GameState { didSet { stateStamp = ReadMemo.nextStamp() } }
    /// Changes whenever `state` does (see `ReadMemo`).
    var stateStamp: UInt64 = ReadMemo.nextStamp()
    let readMemo = ReadMemo()
    public let data: GameData
    public let context: FinanceContext
    public let events: EventLibrary
    public let marketing: MarketingTables
    /// The TechPro Store lists every item in the game for every company: working out all those prices is the slow part of a screen, so the
    /// result is kept per company until the day, the company's cash or what it owns changes (a reference, shared by the copies of the engine).
    let needsMemo = NeedsMemo()

    public init(state: GameState, data: GameData, events: EventLibrary, marketing: MarketingTables) {
        var state = state
        Markets.refreshNames(&state, country: data.countries.resolve(state.homeCountryCode, orHome: state.homeCountryCode))
        MarketBook.backfillCostBases(&state)
        HeldMoney.normalise(&state)
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
    public static func newGame(countryCode: String, playerName: String, cityID: String? = nil, seed: Int? = nil, age: Int = 30, story: LifeStory = .loan, ambition: String? = nil,
                               tradeID: String? = nil, companyName: String? = nil, chooseFirstItem: Bool = false) throws -> GameEngine {
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
        let startCash = story == .loan ? loan : 0   // other stories are funded through the ledger, so no loan record is ever made and removed
        json["cash"] = .number(startCash); json["cash0"] = .number(startCash); json["flow"] = .object([:]); json["sav"] = .object(["bal": 0])
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
        if story == .loan {
            var l = Loan(raw: [:])
            l.id = state.makeID(); l.kind = "start"; l.name = "Start-up loan"; l.balance = loan; l.set("rate", 0); l.margin = 0.045
            l.termMonths = country.startLoanTermMonths; l.companyID = 0; l.startWeek = 0; l.isGuaranteed = false
            l.monthlyPayment = Loans.annuity(principal: loan, yearlyRate: state.economy.policyRate + 0.045, months: Double(country.startLoanTermMonths))
            state.loans.append(l)
        }
        state.economy.set("rate0", state.economy.policyRate)
        state.rest["gameID"] = .string("g\(seed)")   // deterministic: the same seed gives the same state; the app clears remembered details at every new game
        PlayerGoals.startLadder(&state)   // the M1 to M10 ladder and its gates
        Markets.initialize(&state, country: country)
        _ = Providers.pool(for: country.code, state: &state, countries: data.countries)
        if story == .loan {
            state.note("Welcome to Ledger. You have a start-up loan of \(currency.display(loan)). Open your first business with + on the Company tab.", tone: "good")
        } else if story == .fresh {
            let ctx = FinanceContext(countries: data.countries, trades: data.catalog)
            guard let tradeID, LifeStories.applyFresh(&state, data: data, context: ctx, tradeID: tradeID, name: companyName ?? "", chooseFirstItem: chooseFirstItem) else { throw CocoaError(.fileReadUnknown) }
            state.note("Welcome to Ledger. \(state.companies.first?.name ?? "Your business") is open. Tap Next day to begin.", tone: "good")
        } else {
            let ctx = FinanceContext(countries: data.countries, trades: data.catalog)
            guard LifeStories.applyHeir(&state, data: data, context: ctx) else { throw CocoaError(.fileReadUnknown) }
            state.note("Welcome to Ledger. The family café is yours, open and trading, with \(currency.display(state.cash)) in savings and no loan.", tone: "good")
        }
        let bank = country.pack["authorities"]["cb"].string
        state.news("\(bank): policy rate unchanged at \(Currency.percent(state.economy.policyRate, decimals: 2)). New year, new opportunities.")
        var engine = GameEngine(state: state, data: data, events: events, marketing: marketing)
        engine.openReportBaselines()
        engine.snapshot()
        engine.recordDay()
        // An ambition chosen on the start screen is stored like any other choice (perk active at once: there is nothing to switch from).
        if let ambition, Ambitions.path(ambition) != nil { engine.chooseAmbition(path: ambition) }
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
        MarketBook.recordHistory(&state, data: data)
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
            if m.actionID == PromiseReminders.action { PromiseReminders.answer(&s, message: m, option: idx, data: d); return true }
            if m.actionID == Appointments.kind { Appointments.answer(&s, message: m, option: idx); return true }
            if m.actionID == HierarchyHiring.action { HierarchyHiring.answer(&s, message: m, option: idx, data: d); return true }
            if m.actionID == "staffx" { StaffTalks.answer(&s, message: m, option: idx, data: d); return true }
            if m.actionID == FixedTerm.action { FixedTerm.answer(&s, message: m, option: idx); return true }
            if m.actionID == PersonalFinance.dueAction { return TaxSettlement.answer(&s, message: m, option: idx, data: d, context: c) }
            if ["prop", "mgrraise", "mgrpoach"].contains(m.actionID) { ManagerModel.answer(&s, message: m, option: idx, data: d); return true }
            if ManagerTargets.handlesAnswer(m.actionID) { ManagerTargets.answer(&s, message: m, option: idx, data: d); return true }
            if m.actionID == FirstYear.frozenAction { return true }
            if m.actionID == "oil24" { EnergyModel.answer(&s, message: m, option: idx); return true }
            if m.actionID == "club24" { FootballModel.answerBid(&s, message: m, option: idx); return true }
            if Franchising.handlesAnswer(m.actionID) { Franchising.answer(&s, message: m, option: idx, context: c); return true }
            if Ventures.handlesAnswer(m.actionID) { return Ventures.answer(&s, message: m, option: idx, data: d, context: c) }
            if m.actionID == UsedCarDealer.offerAction { UsedCarDealer.answerOffer(&s, message: m, option: idx); return true }
            if m.actionID == "acct" { KeyAccounts.answer(&s, message: m, option: idx); return true }
            if m.actionID == VolumeContracts.action { VolumeContracts.answer(&s, message: m, option: idx); return true }
            if m.actionID == "g27poach" { RivalGroups.answerPoach(&s, message: m, option: idx, data: d); return true }
            if m.actionID == RivalBids.action { RivalBids.answer(&s, message: m, option: idx, data: d, context: c); return true }   // rival group bids ("g27bid")
            if m.actionID == "fav31" { WorldAround.answerFavour(&s, message: m, option: idx, data: d); return true }
            if m.actionID == "sue16" { Lawsuits.answer(&s, message: m, option: idx, data: d); return true }
            if m.actionID == "cy56r" { Cyber.answerRansom(&s, message: m, option: idx, data: d); return true }
            if m.actionID == "cy56l" { Cyber.answerLeak(&s, message: m, option: idx, data: d); return true }
            if Stories.handlesAnswer(m.actionID) { Stories.answer(&s, message: m, option: idx, data: d); return true }
            if m.actionID == Press.interviewAction { Press.answerInterview(&s, questionIndex: m.value("data")["q"].int, option: idx); return true }
            if m.actionID == WeatherEvents.prepareAction { WeatherEvents.answerPrepare(&s, data: d, message: m, option: idx); return true }
            if m.actionID == "pay29s" { return true }   // a payroll-short notice: acknowledging it moves no money; back pay is automatic
            if m.actionID == "pay29" || m.actionID == "pay29all" {
                Payday.answer(&s, action: m.actionID, data: m.value("data"), option: idx, companyID: m.companyID, data: d, context: c)
                return true
            }
            // An action nobody handles must not be marked as answered: the message stays open and the problem is logged.
            s.note("Unknown inbox action \"\(m.actionID)\": the answer was not applied.", tone: "bad")
            return false
        }
        if ok { ReportCounters.add(&state, ReportCounters.Key.answered, 1) }
        return ok
    }

    /// True while an open inbox message comes from a blocking event (`blocking` in events.json): Play waits until it is answered.
    public var hasBlockingDecision: Bool { blockingMessage != nil }

    /// The first open message from a blocking event, if any.
    public var blockingMessage: Message? {
        state.inbox.first { $0.status == "open" && events[$0.str("ev")]?.blocking == true }
    }

    /// Open messages waiting for an answer, newest first.
    public var openDecisions: [Message] { state.inbox.filter { $0.status == "open" } }

    // MARK: Time

    public struct DayOutcome {
        public var newMessages: [Message]
        public var completedWeek: Bool
        public var gameOver: Bool
    }

    /// Move one day forward. Original: `dayStep`. Every simulation step runs inside a day: nothing waits for the week to end.
    @discardableResult
    public mutating func nextDay() -> DayOutcome {
        let before = Set(state.inbox.map { $0.id })
        state.dayMode = true
        var completed = false
        if state.isGameOver { return DayOutcome(newMessages: [], completedWeek: false, gameOver: true) }
        if state.day < 6 {
            state.day += 1
        } else {
            // The seventh day is over: the calendar counter turns and the week, month and year just ended are reported. The reports only
            // read what the days already did.
            closeReportPeriods()
            sweepLadder()   // M1 (first week closed) finishes in the week it closed
            openWeekReport()
            state.week += 1
            state.day = 0
            completed = true
        }
        runDaySlices()
        if !state.isGameOver {
            tradeAndPay(day: state.day)
            releaseDay(state.day)
        }
        recordDay()
        sweepLadder()
        sweepCareer()
        checkMilestones(weekClosed: completed)
        routeFreshDecisions(state.inbox.filter { !before.contains($0.id) })   // a hired rank takes what is theirs
        let fresh = state.inbox.filter { !before.contains($0.id) }
        return DayOutcome(newMessages: fresh, completedWeek: completed, gameOver: state.isGameOver)
    }

    /// Finishes ladder goals whose condition now holds (PlayerGoals.ladderSweep); cheap, so it runs every day.
    mutating func sweepLadder() {
        update { s, _, ctx in PlayerGoals.ladderSweep(&s, currency: ctx.homeCurrency(s)) }
    }

    mutating func tradeAndPay(day: Int) {
        JobAds.runDay(&state, data: data)   // applicants to job ads arrive over the weeks
        Agency.runDay(&state, data: data)
        StoreOrders.runDay(&state, data: data)   // TechPro Store orders arrive on their delivery day
        DailyTrade.runDay(&state, day: day, data: data)
        ProjectWeek.runDay(&state, day: day, data: data)
        Payday.onDay(&state, data: data, context: context)
    }

    // MARK: The day's slice of the weekly processes

    /// The part of the world that changes in one day beyond trade and pay: each company's seven-day model on its own weekday, every
    /// world process on a weekday of its own, and the month and year books on their real last day. The money a slice works out is held
    /// and released over the next seven days (`endSlice` / `releaseDay`), so cash moves a little every day.
    mutating func runDaySlices() {
        if state.isGameOver { return }
        HeldMoney.normalise(&state)
        // A save from the weekly turn already worked out the week it was saved in: the slices start with the next one.
        if let from = state.rest["sliceStart"], !from.isNull, state.week < from.int { return }
        let day = state.day
        let mark = beginSlice()
        runCompanyModels(day: day)
        runWorldProcesses(day: day)
        endSlice(mark)
        if !state.isGameOver, GameCalendar.isMonthEnd(week: state.week, day: day) { runMonthEnd() }
    }

    /// What a slice must remember to hold back the money and messages it creates.
    struct SliceMark {
        var meBefore: Double
        var coBefore: [Int: Double]
        var txBefore: [Int: String]
        var inboxBefore: Set<Int>
        var newsBefore: Int
    }

    mutating func beginSlice() -> SliceMark {
        var coBefore: [Int: Double] = [:]
        var txBefore: [Int: String] = [:]
        for c in state.companies { coBefore[c.id] = c.cash; txBefore[c.id] = c.transactions.first.map { "\($0["w"].int):\($0["a"].double):\($0["l"].string)" } }
        state.transient.stagedPlayerLines = []
        state.transient.simulatingWeek = true
        return SliceMark(meBefore: state.cash, coBefore: coBefore, txBefore: txBefore, inboxBefore: Set(state.inbox.map { $0.id }),
                         newsBefore: (state.rest["news"]?.array ?? []).count)
    }

    /// Hold back the slice's money, messages and news and spread them over the next seven days (day 0 of the spread is today).
    mutating func endSlice(_ mark: SliceMark) {
        let rows = state.transient.stagedPlayerLines ?? []
        state.transient.stagedPlayerLines = nil
        state.transient.simulatingWeek = false
        if state.isGameOver {
            for r in rows { Ledger.addStatementLine(&state, amount: r.amount, label: r.label, companyID: r.companyID) }
            state.rest["pend"] = .null
            return
        }
        let now = HeldMoney.today(state)
        var pend = state.rest["pend"] ?? .null
        if pend.isNull { pend = .object(["v": 2, "rows": .array([]), "co": .array([]), "msgs": .array([]), "news": .array([])]) }
        let meDelta = state.cash - mark.meBefore
        var staged = rows.map { (amount: $0.amount, label: $0.label, companyID: $0.companyID) }
        let left = meDelta - staged.reduce(0) { $0 + $1.amount }
        if abs(left) >= 1 { staged.append((left, "Other", 0)) }
        var rm = HashedRandom("\(state.seed):me:\(state.week):\(state.day)")
        var rowList = pend["rows"].array
        for x in staged {
            rowList.append(.object(["a": .number(x.amount), "l": .string(x.label), "co": .number(Double(x.companyID)), "d": .number(Double(now) + (rm.next() * 7).rounded(.down))]))
        }
        if meDelta != 0 { Ledger.moveRaw(&state, .me, -meDelta) }
        var coList = pend["co"].array
        for i in state.companies.indices {
            let id = state.companies[i].id
            guard let b = mark.coBefore[id] else { continue }
            guard state.companies[i].status.isLive else { continue }   // sold or bust during the slice: nothing is held back for a company that is gone
            let d = state.companies[i].cash - b
            if d != 0 {
                var one = 0.0
                for t in state.companies[i].transactions {
                    if "\(t["w"].int):\(t["a"].double):\(t["l"].string)" == mark.txBefore[id] { break }
                    if t["a"].double < 0 { one += t["a"].double }
                }
                coList.append(.array([.number(Double(id)), .number(d), .number(jsRound(one)), .number(Double(now))]))
                Ledger.moveRaw(&state, .company(id), -d)
            }
        }
        var r = HashedRandom("\(state.seed):day:\(state.week):\(state.day)")
        var msgs = pend["msgs"].array
        let fresh = state.inbox.filter { !mark.inboxBefore.contains($0.id) }
        state.inbox.removeAll { !mark.inboxBefore.contains($0.id) }
        for m in fresh { msgs.append(.object(["m": .object(m.raw), "d": .number(Double(now) + (r.next() * 7).rounded(.down))])) }
        var newsList = pend["news"].array
        let allNews = state.rest["news"]?.array ?? []
        let addedNews = Array(allNews.prefix(max(0, allNews.count - mark.newsBefore)))
        state.rest["news"] = .array(Array(allNews.dropFirst(max(0, allNews.count - mark.newsBefore))))
        for n in addedNews { newsList.append(.object(["n": n, "d": .number(Double(now) + (r.next() * 7).rounded(.down))])) }
        pend["rows"] = .array(rowList)
        pend["co"] = .array(coList)
        pend["msgs"] = .array(msgs)
        pend["news"] = .array(newsList)
        state.rest["pend"] = pend
    }

    /// Lands today's part of everything held back: a seventh of each company's money (its one-off bills at once), the player's lines
    /// and the messages and news whose day has come. Original: `releaseDay`.
    mutating func releaseDay(_ day: Int) {
        HeldMoney.normalise(&state)
        guard var P = state.rest["pend"], !P.isNull else { return }
        let now = state.week * 7 + day
        func part(_ total: Double, _ offset: Int) -> Double { jsRound(total * Double(offset + 1) / 7) - jsRound(total * Double(offset) / 7) }
        var keepRows: [JSONValue] = []
        for row in P["rows"].array {
            if row["d"].int > now { keepRows.append(row); continue }
            Ledger.moveRaw(&state, .me, row["a"].double)
            Ledger.addStatementLine(&state, amount: row["a"].double, label: row["l"].string, companyID: row["co"].int)
        }
        var keepCo: [JSONValue] = []
        for x in P["co"].array {
            let id = x[0].int, total = x[1].double, one = x[2].double
            let offset = now - x[3].int
            if offset < 0 { keepCo.append(x); continue }
            if offset > 6 { continue }
            let oneOff = one + min(0, total - one)
            let v = part(total - oneOff, offset) + (offset == 0 ? oneOff : 0)
            if v != 0, state.companyIndex(id) != nil { Ledger.moveRaw(&state, .company(id), v) }
            if offset < 6 { keepCo.append(x) }
        }
        var dueMsgs: [JSONValue] = [], keepMsgs: [JSONValue] = []
        for x in P["msgs"].array { if x["d"].int <= now { dueMsgs.append(x) } else { keepMsgs.append(x) } }
        for x in dueMsgs.reversed() { state.inbox.insert(Message(raw: x["m"].object), at: 0) }
        var news = state.rest["news"]?.array ?? []
        var keepNews: [JSONValue] = []
        for x in P["news"].array.reversed() { if x["d"].int <= now { news.insert(x["n"], at: 0) } else { keepNews.insert(x, at: 0) } }
        state.rest["news"] = .array(news)
        P["rows"] = .array(keepRows)
        P["co"] = .array(keepCo)
        P["msgs"] = .array(keepMsgs)
        P["news"] = .array(keepNews)
        state.rest["pend"] = P
    }

    /// Start the week report's baseline (net worth, cash) on the day the calendar turns. Called before the week counter moves.
    mutating func openWeekReport() {
        state.rest["rep"] = .object(["ev": .array([]), "w": .number(Double(state.week)), "from": .number(Double(state.week)),
                                     "nw0": .number(netWorth.total), "cash0": .number(state.cash)])
    }

    // MARK: The weekly models, one day each

    /// Each company's seven-day model runs on its own weekday: documents, customers sold, books, costs, staff, marketing, events.
    mutating func runCompanyModels(day: Int) {
        for i in state.companies.indices {
            guard state.companies[i].status.isLive, GameCalendar.slot(ofCompany: state.companies[i].id) == day else { continue }
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
            state.companies[i].set("slotRun", .number(Double(HeldMoney.today(state))))
        }
    }

    /// The processes of the world, each once in seven days on its own weekday (0 = the first day of a game week):
    ///  0 economy, stock markets, luxury, market facts          1 competitors, leagues, rivals, price moves, market shares
    ///  2 funds, brokerage, finance manager, software, tenders, research   3 lawsuits, cyber, staffing plan, follow-ups, expiry, unlocks
    ///  4 decisions, ventures, awards, special families, chains  5 staff record, ambitions, giving, weather, perks, manager targets
    ///  6 failure checks, bankruptcy, portraits, the net worth point, game over
    mutating func runWorldProcesses(day: Int) {
        switch day {
        case 0:
            WorldWeek.economy(&state, data: data)
            Markets.weekly(&state)
            Luxury.weekly(&state)
            MarketEvents.weekly(&state, data: data)   // log of market facts for the app (no inbox messages)
            Marketplace.weekly(&state)   // forget talks and purchases of expired listings
        case 1:
            WorldWeek.competitors(&state, data: data)
            FootballModel.leaguesWeek(&state, data: data)
            Rivals.weekly(&state, data: data)
            PriceMoves.weekly(&state, data: data)
            MarketMap.weekly(&state, data: data)
        case 2:
            Markets.fundsWeekly(&state)
            Brokerage.weekly(&state)
            FinanceManager.weekly(&state, context: context)   // your fund manager's returns, the office finance manager's holdings
            SoftwareProducts.weekly(&state, data: data)
            ProjectTenders.weekly(&state, data: data, context: context)
            MarketResearch.weekly(&state, data: data)   // ordered research reports arrive (inbox message)
        case 3:
            Lawsuits.weekly(&state, data: data)
            Cyber.weekly(&state, data: data)
            StaffingPlan.weekly(&state, data: data)   // vacancies, replacements, growth and seasonal crews (Businesses/StaffingPlan.swift)
            Aftermath.weekly(&state, data: data, context: context)   // follow-ups of earlier lawsuits, breakdowns, resignations ... (Events/Aftermath.swift)
            EventEngine.expire(&state, data: data, context: context)
            Unlocks.weekly(&state, context: context)   // newly satisfied unlocks are recorded once per company (Businesses/Unlocks.swift)
        case 4:
            StrategicDecisions.weekly(&state, data: data, context: context)
            Ventures.weekly(&state, data: data, context: context)   // startups, private equity, the big meeting, owners of your companies
            Awards.weekly(&state, data: data, context: context)
            SpecialFamilies.weeklyAfter(&state, data: data, context: context)
            Chains.weekly(&state, data: data, context: context, marketing: marketing)   // chains, franchises, supply between your companies
            ChainBranches.weekly(&state, data: data)   // a chain is one company: a branch short of cash is covered by the chain first
        case 5:
            MiscWeekly.run(&state, data: data, context: context)   // staff record, ambitions, giving, weather, cyber, perks ... (MiscWeekly.swift)
            // In the week that holds a month end the targets are set by the month's own close (`runMonthEnd`), after the books are in.
            if !GameCalendar.isMonthEnd(week: state.week) { ManagerTargets.weekly(&state, data: data) }
        default:
            runFailureChecks()
        }
    }

    /// Companies that cannot pay are warned, frozen in their first year, or declared bankrupt; then the net worth point and game over.
    mutating func runFailureChecks() {
        Failure.warn(&state, context: context)   // a company close to a forced sale says so first (red alert)
        FirstYear.freezeSweep(&state, balance: data.balance)   // before week 27 a company in the red is frozen, not bankrupt (Businesses/FirstYear.swift)
        let bankruptcyOn = data.balance.firstYear.bankruptcyActive(week: state.week)
        for i in state.companies.indices where bankruptcyOn {
            let c = state.companies[i]
            if state.isBranch(c) { continue }   // a branch is not a legal entity: only its whole chain can fail (Failure.chainChecks)
            if (c.status == .open || c.status == .closed) && c.weeksNegative > 12 && c.cash < -context.overdraftRoom(c, state) * 2 {
                Failure.bankrupt(&state, companyIndex: i, reason: "cash", data: data, context: context)
            }
            else if (c.status == .open || c.status == .closed) && c.int("loanCall") > 0 && state.week >= c.int("loanCall") {
                // The bank called the loan after three missed instalments and the company did not catch up in time.
                Failure.bankrupt(&state, companyIndex: i, reason: "loan", data: data, context: context)
            }
            else if (c.status == .open || c.status == .closed) && c.cash < 0 && Payday.unpaidForMonths(c, today: Payday.dayNumber(week: state.week, day: state.day)) {
                // Rent, suppliers or tax left unpaid for months while the account is empty: creditors close the company.
                Failure.bankrupt(&state, companyIndex: i, reason: "unpaid", data: data, context: context)
            }
        }
        let insolvent = FinanceModel.insolventCompanies(&state, data: data)
        for id in insolvent where bankruptcyOn {
            if let i = state.companyIndex(id), !state.isBranch(state.companies[i]) { Failure.bankrupt(&state, companyIndex: i, reason: "insolvent", data: data, context: context) }
        }
        if bankruptcyOn { Failure.chainChecks(&state, data: data, context: context, insolvent: Set(insolvent)) }
        FaceBook.sweep(&state, data: data)   // portraits: hired people keep theirs for good, stale candidates give theirs back
        snapshot()
        let ctx = context
        Failure.checkOver(&state, data: data, context: ctx, liquidate: { s, need in Brokerage.liquidate(&s, need: need, currency: ctx.homeCurrency(s)); FinanceManager.cashIn(&s, need: need) })
    }

    // MARK: Calendar steps

    /// The books of the month (and of the year, on 31 December) close on the real last day, with the money moving that day.
    mutating func runMonthEnd() {
        state.transient.simulatingWeek = true
        defer { state.transient.simulatingWeek = false }
        MiscWeekly.monthly(&state, data: data, context: context)
        MonthEnd.closeMonth(&state, data: data, context: context)
        if GameCalendar.isYearEnd(week: state.week, day: state.day) { MonthEnd.closeYear(&state, data: data, context: context) }
        ManagerTargets.weekly(&state, data: data)   // monthly targets and yearly budget of managed companies (after the month is closed)
    }
}
