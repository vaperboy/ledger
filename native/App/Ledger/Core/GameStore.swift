import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Investments
import Events
import SaveSystem
import Simulation

enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case custom, group, company, projects, phone
    var id: String { rawValue }
    var title: String { switch self { case .company: return "Home"; case .custom: return "Store"; case .group: return "Group"; case .projects: return "Ventures"; case .phone: return "Phone" } }
    var symbol: String {
        switch self { case .company: return "house"; case .custom: return "bag"; case .group: return "square.stack.3d.up"; case .projects: return "hammer"; case .phone: return "iphone" }
    }
    var glyph: String {
        switch self { case .company: return Glyph.home; case .custom: return Glyph.shopBag; case .group: return Glyph.group; case .projects: return Glyph.projects; case .phone: return Glyph.phone }
    }
    var accent: Color {
        switch self { case .company: return Theme.gold; case .custom: return Color(hex: 0xE0BC5E); case .group: return Color(hex: 0x7F9BC4); case .projects: return Color(hex: 0xE0BC5E); case .phone: return Color(hex: 0x86B890) }
    }
    static let launch: AppTab = .company
    static func from(raw: String) -> AppTab { AppTab(rawValue: raw) ?? .launch }
}

struct ReturnInfo: Equatable {
    var from: AppTab
    var dest: AppTab
    var destDepth: Int
}

enum AppRequest: Equatable {
    case message(Int)
    case bank(BankRequest)
    case market(companyID: Int)
    case marketTab(MarketUI.Tab)
    case airStay(companyID: Int)
    case techPro(companyID: Int, equipmentID: String)
    case atlas(companyID: Int)
    case ventures
    case newsPlayers
    case auctionListing(String)
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var title: String = ""
    var text: String
    var tone: String
    var style = ""
    var subtitle = ""
    var rows: [String] = []
}

struct OutcomeNote: Identifiable, Equatable {
    let id = UUID()
    var chosen: String
    var result: String
    /// The one screen an answered decision is about, shown as a link under the result.
    var link: DecisionLink? = nil
}

struct OutcomeCapture {
    var lines: [String] = []
    var refused = false
    var told = false
}

struct DayChanges: Equatable {
    var netWorth: Double = 0
    var cash: Double = 0
    var revenue: Double = 0
    var debt: Double = 0
}

struct PaymentNotice: Equatable, Identifiable {
    let id = UUID()
    var amount: Double
    var from: String
}

struct HomeEvent: Equatable, Identifiable {
    let id = UUID()
    var glyph: String
    var text: String
    var day: String
}

struct TransferChip: Equatable, Identifiable {
    let id = UUID()
    var label: String
    var amount: Double
    var origin: CGPoint? = nil
    var outgoing: Bool = false
    var text: String? = nil
}

@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var engine: GameEngine? {
        didSet {
            memoBox.removeAll(keepingCapacity: true)
            if let e = engine, !isShowcase {
                ProfileStore.record(PlayerLevel.profile(of: e.state))
                SeasonModel.shared.activate(save: Self.saveID(e.state))
            }
        }
    }
    private var memoBox: [String: Any] = [:]
    static func saveID(_ s: GameState) -> String { "seed" + String(s.seed) }
    func memo<T>(_ key: String, _ compute: (GameEngine) -> T) -> T? {
        guard let e = engine else { return nil }
        if let v = memoBox[key] as? T { return v }
        let v: T = compute(e)
        memoBox[key] = v
        return v
    }
    var netWorthNow: NetWorth? { memo("nw") { $0.netWorth } }
    var dayHistoryNow: DayHistory? { memo("hist") { $0.dayHistory } }
    func netWorthSeriesNow(days: Int) -> [Double] { memo("nws\(days)") { $0.netWorthSeries(days: days) } ?? [] }
    var suggestionsNow: [Suggestion] { memo("sugg8") { $0.suggestions(limit: 8) } ?? [] }
    var teamOverviewNow: TeamOverview? { memo("team") { $0.teamOverview() } }
    @Published private(set) var notices: [Toast] = []
    @Published private(set) var redAlerts: [Message] = []
    func dismissRedAlert() { if !redAlerts.isEmpty { redAlerts.removeFirst() } }
    var toast: Toast? { notices.first }
    @Published private(set) var outcomes: [OutcomeNote] = []
    var outcomeCapture: OutcomeCapture?
    @Published var decisionPopup: Int?
    @Published var errorText: String?

    @Published private(set) var isAdvancing = false
    @Published private(set) var reportSheet: ReportDigest?
    @Published private(set) var celebrationQueue: [Celebration] = []
    @Published var homeCliffhanger: Int = 0
    func openGoals() { openApp(.season) }
    var playStreakShown: Int {
        guard let e = engine else { return 0 }
        let n: Int = PlayStreak.current(e.state, today: GameStore.calendarDay())
        return n >= PlayStreak.showFrom ? n : 0
    }
    static func calendarDay() -> Int { TrustedClock.today() }
    func scheduleReminders() {
        guard let e = engine else { return }
        Reminders.schedule(SessionHooks.reminders(e.state))
    }
    private static let leftAtKey = "ledger.leftAt"
    private static let recapAfterAway: Double = 15 * 60
    func noteLeaving() {
        guard var e = engine else { return }
        e.markSeen()
        engine = e
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: GameStore.leftAtKey)
    }
    func showReturnRecap() {
        let left: Double = UserDefaults.standard.double(forKey: GameStore.leftAtKey)
        guard left > 0, Date().timeIntervalSince1970 - left >= GameStore.recapAfterAway else { return }
        UserDefaults.standard.removeObject(forKey: GameStore.leftAtKey)
        guard var e = engine, !isAdvancing, reportSheet == nil, notices.isEmpty, outcomes.isEmpty, let seen: Int = e.lastSeenDay else { return }
        if let recap: ReturnRecap = e.sinceYouLeft(lastSeenDay: seen) {
            var t = Toast(title: recap.title, text: recap.lines.joined(separator: "\n"), tone: "n")
            t.style = "recap"
            notices.append(t)
        }
        e.markSeen()
        engine = e
    }
    @Published var unlockQueue: [UnlockPrompt] = []
    @Published private(set) var dayChip: DayChip?
    @Published private(set) var lastDayChanges = DayChanges()
    @Published private(set) var paymentNotice: PaymentNotice?
    @Published var seenMarks: UpdateMarks = UpdateMarks.load("seen") { didSet { memoBox["badges"] = nil } }
    var pendingSeen: [String] = []
    var seenFlushScheduled = false
    var visitBaselines: [String: UpdateMarks] = [:]
    @Published var visitFresh: [String: Set<String>] = [:]
    @Published var workerPopup: WorkerPopupRef?
    @Published private(set) var homeEvents: [HomeEvent] = []
    private func logEvents(_ items: [HomeEvent]) {
        guard !items.isEmpty else { return }
        homeEvents = Array((items + homeEvents).prefix(12))
    }
    @Published private(set) var transferChip: TransferChip?
    func flyChip(_ label: String, amount: Double, from origin: CGPoint? = nil, outgoing: Bool = false, text: String? = nil) {
        transferChip = TransferChip(label: label, amount: amount, origin: origin, outgoing: outgoing, text: text)
    }
    func clearChip() { transferChip = nil }
    @Published private(set) var dailySheet: DailyDigest?

    @Published var tab: AppTab = AppTab.launch
    @Published private(set) var previousTab: AppTab?
    func returnToPreviousTab() {
        guard let p = previousTab, p != tab else { return }
        selectTab(p, resetRoot: false)
    }
    private struct LastPush { var route: NavRoute; var tab: AppTab; var at: Date }
    private var lastPush: LastPush?
    @Published private(set) var stacks: [AppTab: [NavRoute]] = [:]
    @Published private(set) var rootTokens: [AppTab: Int] = [:]
    @Published private(set) var appRequest: AppRequest?
    @Published private(set) var loadProblem: String?
    /// True from launch until the saved game has been read, so the first frame never waits for the file.
    @Published private(set) var isLoadingSave: Bool = false
    private let writer: SaveWriter?

    let saves: SaveStore?
    private let isShowcase = ProcessInfo.processInfo.arguments.contains("-showcase")
    private static var showcaseTrades: [String] {
        let a: [String] = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-showcase-trades"), i + 1 < a.count else { return [] }
        return a[i + 1].split(separator: ",").map { String($0) }
    }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ledger/Saves", isDirectory: true)
        let store: SaveStore? = try? SaveStore(directory: base)
        saves = store
        writer = store.map { SaveWriter(store: $0) }
        if isShowcase, let e = try? GameEngine.showcase(wealthy: ProcessInfo.processInfo.arguments.contains("-showcase-rich"), board: ProcessInfo.processInfo.arguments.contains("-showcase-board"),
                                                        extraTrades: Self.showcaseTrades) { engine = e }
        else if let saves, saves.hasSave() { isLoadingSave = true }
        writer?.onFailure = { [weak self] (message: String) -> Void in self?.errorText = message }
        ConfirmThreshold.delegated = { [weak self] () -> (limit: Double, rate: Double) in self?.engine?.delegatedSpendLimit() ?? (limit: 0, rate: 0) }
        StoreSession.shared.moneyPrizeHandler = { [weak self] (amount: Int, id: String) -> Void in self?.claimBoxMoney(amount, claimID: id) }
        StoreSession.shared.moneyPackHandler = { [weak self] (pack: String, id: String) -> Double? in self?.claimMoneyPack(pack, claimID: id) }
        StoreSession.shared.purse = { [weak self] () -> AuctionPurse? in
            guard let e = self?.engine else { return nil }
            let cur: Currency = e.homeCurrency
            return AuctionPurse(cash: e.auctionCash, priceLevel: e.auctionPriceLevel, format: { (n: Int) -> String in cur.display(Double(n) * cur.rate).tidyMoney })
        }
        StoreSession.shared.cashHandler = { [weak self] (amount: Int, id: String, label: String) -> Void in self?.settleAuctionCash(amount, claimID: id, label: label) }
    }

    func settleAuctionCash(_ amount: Int, claimID: String, label: String) {
        act({ $0.settleAuctionCash(amount, claimID: claimID, label: label) })
    }

    func claimBoxMoney(_ amount: Int, claimID: String) {
        guard let paid = act({ $0.claimBoxMoney(amount, claimID: claimID) }) ?? nil, paid > 0 else { return }
        if let cur = engine?.homeCurrency { tell("Prize paid", "+" + cur.display(paid) + " from your box.", tone: "good") }
    }

    var hasGame: Bool { engine != nil }
    var hasSavedGame: Bool { saves?.hasSave() ?? false }

    func money(_ v: Double) -> String { (engine?.homeCurrency.display(v) ?? String(Int(saturating: v))).tidyMoney }
    func short(_ v: Double) -> String { (engine?.homeCurrency.short(v) ?? String(Int(saturating: v))).tidyMoney }
    func money(_ v: Double, in co: Company) -> String { (engine?.currency(for: co).display(v) ?? String(Int(saturating: v))).tidyMoney }
    func short(_ v: Double, in co: Company) -> String { (engine?.currency(for: co).short(v) ?? String(Int(saturating: v))).tidyMoney }

    func loadCurrent() {
        guard let saves else { return }
        writer?.flush()
        do { try start(with: saves.load()); loadProblem = nil; resetNavigation() }
        catch { noteLoadFailure(error, saves: saves) }
    }

    /// Reads the saved game off the main thread, after the first frame is on screen.
    func loadInitialSave() async {
        guard isLoadingSave, let saves else { isLoadingSave = false; return }
        let result: Result<GameState, Error> = await Task.detached { () -> Result<GameState, Error> in
            Result { try saves.load() }
        }.value
        switch result {
        case .success(let state):
            do { try start(with: state); loadProblem = nil; resetNavigation() }
            catch { noteLoadFailure(error, saves: saves) }
        case .failure(let error):
            noteLoadFailure(error, saves: saves)
        }
        isLoadingSave = false
        syncPlayerCompanies()
    }

    private func noteLoadFailure(_ error: Error, saves: SaveStore) {
        let kept: Bool = saves.keepUnreadable()
        loadProblem = Self.describe(error) + (kept ? " A copy of your save was kept on this device." : "")
    }

    func currentSaveSummary() -> SaveSummary? {
        saves?.slots().first { $0.slot == "current" }?.summary
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case SaveError.notAGameSave: return "The file is not a Ledger save."
        case SaveError.newerThanThisApp(let v): return "It was saved by a newer version of Ledger (save format \(v)). Update the app to open it."
        case SaveError.unreadable(let why): return "The file is damaged: \(why)."
        case is DecodingError: return "The file is damaged and its contents could not be read."
        default: return error.localizedDescription
        }
    }

    private func start(with state: GameState) throws {
        let (data, events, marketing) = try GameEngine.loadResources()
        var e = GameEngine(state: state, data: data, events: events, marketing: marketing)
        if e.state.rest["dayHist"] == nil { e.recordDay() }
        if !isShowcase { ProfileStore.adopt(into: &e) }
        engine = e
    }

    /// Queues a save; the file is written in the background a moment later.
    func save(backup: Bool = false) {
        guard !isShowcase, let saves, let engine, let writer else { return }
        writer.schedule(engine.state, summary: saves.summary(of: engine.state, trades: engine.data.catalog), backup: backup)
    }

    /// Writes the save now. Used before leaving the app or touching save files.
    func saveNow() {
        save()
        writer?.flush()
    }

    func slotList() -> [(slot: String, summary: SaveSummary?)] { saves?.slots() ?? [] }

    /// Slots are separate careers: the current one is parked under its own name and the chosen one continues from its latest state.
    func switchCareer(to slot: String) {
        guard !isShowcase, let saves, slot != "current", saves.hasSave(slot: slot) else { return }
        saveNow()
        do {
            if saves.hasSave() { guard try saves.park(as: careerName) != nil else { errorText = "Your career could not be put aside."; return } }
            guard try saves.unpark(slot) else { errorText = "That career could not be opened."; return }
            try start(with: saves.load()); loadProblem = nil; resetNavigation(); save()
        } catch { errorText = "That career could not be opened. " + Self.describe(error) }
    }

    /// Puts the current career aside in its own slot and returns to the start screen for a new one.
    @discardableResult
    func parkForNewCareer() -> Bool {
        guard !isShowcase, let saves, engine != nil else { return false }
        saveNow()
        do {
            guard try saves.park(as: careerName) != nil else { return false }
            resetNavigation(); engine = nil
            return true
        } catch { errorText = "Your career could not be put aside. " + Self.describe(error); return false }
    }

    private var careerName: String {
        guard let s = engine?.state else { return "Career" }
        return SaveStore.cleanSlotName(s.companies.first?.name ?? s.player.name) ?? "Career"
    }

    func deleteSlot(_ slot: String) { try? saves?.delete(slot: slot) }

    @discardableResult
    func renameSlot(_ slot: String, to raw: String) -> Bool { (try? saves?.renameSlot(slot, to: raw)) ?? false }

    func newGame(name: String, countryCode: String, story: LifeStory = .loan, cityID: String? = nil, ambition: String? = nil, tradeID: String? = nil, companyName: String? = nil, channel: SalesChannel? = nil) {
        RememberedDetails.clearAll()
        do {
            var e = try GameEngine.newGame(countryCode: countryCode, playerName: name, cityID: cityID, story: story, ambition: ambition, tradeID: tradeID, companyName: companyName, chooseFirstItem: true, channel: channel)
            ProfileStore.adopt(into: &e)
            if let old = engine, !isShowcase { SeasonModel.shared.succeed(save: Self.saveID(old.state), with: Self.saveID(e.state)) }
            engine = e
            loadProblem = nil
            resetNavigation()
            save()
        } catch { errorText = "Could not start a game: \(error)" }
    }

    /// Restores the cloud copy only when it is newer than every copy of that career on this phone, so a backup never rolls a career back.
    func restoreBackup(text: String) -> String? {
        guard let saves else { return "Saving is not available." }
        do {
            let state: GameState = try saves.importLegacy(text: text)
            let id: String = Self.saveID(state)
            for row in saves.slots() where row.slot != "current" {
                if let parked = try? saves.load(slot: row.slot), Self.saveID(parked) == id { return "This career is in the slot \(row.slot). Open it there." }
            }
            if engine != nil { saveNow() }
            writer?.flush()
            var here: GameState? = engine?.state
            if here == nil, saves.hasSave() { here = try? saves.load() }
            if let here {
                if Self.saveID(here) == id {
                    guard (state.week, state.day) > (here.week, here.day) else { return "This phone already has this career at the same point or later." }
                } else {
                    let name: String = SaveStore.cleanSlotName(here.companies.first?.name ?? here.player.name) ?? "Career"
                    guard try saves.park(as: name) != nil else { return "Your career could not be put aside." }
                }
            }
            try start(with: state); loadProblem = nil; resetNavigation(); save()
            return nil
        } catch { return "That backup could not be restored. " + Self.describe(error) }
    }

    func backupText() -> String? {
        guard let engine, let d = try? JSONEncoder().encode(engine.state) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    func quitToMenu() { saveNow(); resetNavigation(); engine = nil }

    func nextDay() {
        guard !isAdvancing, blockingMessageID == nil, reportSheet == nil, celebrationQueue.isEmpty, unlockQueue.isEmpty, engine != nil else { return }
        isAdvancing = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self?.advanceOneDay()
            self?.isAdvancing = false
        }
    }

    var blockingMessageID: Int? {
        let id: Int = memo("blocking") { $0.blockingMessage?.id ?? Int.min } ?? Int.min
        return id == Int.min ? nil : id
    }

    private var profitMark: (week: Int, day: Int, value: Double)?

    private func advanceOneDay() {
        guard var e = engine else { return }
        seedUpdateMarks()
        let nwBefore: Double? = e.dayHistory.netWorth.last
        let cashBefore: Double? = e.dayHistory.cash.last
        let debtBefore: Double = e.state.loans.reduce(0) { $0 + $1.balance }
        let profitBefore: Double = { if let m = profitMark, m.week == e.state.week, m.day == e.state.day { return m.value }; return e.groupBooksProfit }()
        let tightBefore: Bool = e.cashIsTight
        let out = e.nextDay()
        let today: Int = GameStore.calendarDay()
        e.update { s, _, _ in PlayStreak.record(&s, today: today) }
        let celebrations: [Celebration] = e.takeCelebrations()
        if !celebrations.isEmpty { Haptics.goalDone(); SoundCues.play(.goal) }
        if !tightBefore && e.cashIsTight && !out.gameOver { Haptics.cashWarning(); SoundCues.play(.warning) }
        let digest: ReportDigest? = e.pendingReportDigest()
        engine = e
        SeasonModel.shared.observe(e.state)
        StoreSession.shared.receiveLevel(e.playerLevel.level)
        Haptics.nextDay()
        SoundCues.play(out.completedWeek ? .weekReport : .dayClose)
        report(out.newMessages)
        if out.completedWeek { save(backup: e.state.week % 4 == 0) } else { save() }
        if out.gameOver { Haptics.failure() }
        celebrationQueue.append(contentsOf: celebrations)
        queueNotices()
        if out.completedWeek { queueUnlocks() }
        reportSheet = digest
        Task { @MainActor in
            await JointVentureCoordinator.shared.sync(self)
            AssociationStore.shared.syncMembers(self)
        }
        var daily: DailyDigest = e.dailyDigest(fresh: out.newMessages)
        daily.profit = e.groupBooksProfit - profitBefore
        profitMark = (week: e.state.week, day: e.state.day, value: e.groupBooksProfit)
        if let nwBefore, let nwAfter = e.dayHistory.netWorth.last, let cashBefore, let cashAfter = e.dayHistory.cash.last {
            daily.netWorthChange = nwAfter - nwBefore
            daily.cashChange = cashAfter - cashBefore
        }
        let debtAfter: Double = e.state.loans.reduce(0) { $0 + $1.balance }
        lastDayChanges = DayChanges(netWorth: daily.netWorthChange ?? 0, cash: daily.cashChange ?? 0, revenue: daily.revenue, debt: debtAfter - debtBefore)
        var todaysPayment: PaymentNotice?
        if !out.gameOver, let p = bigPayment(e) {
            let notice = PaymentNotice(amount: p.amount, from: p.from)
            todaysPayment = notice
            paymentNotice = notice
        }
        var logged: [HomeEvent] = []
        if let n = todaysPayment { logged.append(HomeEvent(glyph: Glyph.ovCoin, text: "Payments of \(short(n.amount)) from \(n.from)", day: daily.dateLabel)) }
        if lastDayChanges.debt < -0.5 { logged.append(HomeEvent(glyph: Glyph.bank, text: "Loans repaid by \(short(-lastDayChanges.debt))", day: daily.dateLabel)) }
        for line in daily.wentWell.prefix(2) { logged.append(HomeEvent(glyph: Glyph.check, text: line.tidyMoney, day: daily.dateLabel)) }
        for c in celebrations.prefix(2) { logged.append(HomeEvent(glyph: Glyph.achievements, text: c.title, day: daily.dateLabel)) }
        logEvents(logged)
        dailySheet = (digest == nil && !out.gameOver) ? daily : nil
        if digest == nil, let nwAfter = e.dayHistory.netWorth.last, let nwBefore {
            let cashAfter: Double = e.dayHistory.cash.last ?? 0
            dayChip = DayChip(id: UUID(), day: e.state.day + 1, netWorthChange: nwAfter - nwBefore, cashChange: cashAfter - (cashBefore ?? cashAfter), profit: daily.profit)
        } else {
            dayChip = nil
        }
    }

    func chooseAmbition(_ path: String?) {
        act { e -> Bool in
            if let path { e.chooseAmbition(path: path) }
            e.markAmbitionPromptShown()
            return true
        }
        if let path, let name = engine?.ambitionPaths.first(where: { $0.id == path })?.name { show("Your ambition: \(name). Change it freely until week 4.", tone: "good") }
    }

    func refreshPending() {
        guard var e = engine, !isAdvancing else { return }
        if reportSheet == nil { reportSheet = e.pendingReportDigest() }
        let taken: [Celebration] = e.takeCelebrations()
        if !taken.isEmpty {
            engine = e
            save()
            celebrationQueue.append(contentsOf: taken)
        }
        queueNotices()
        queueUnlocks()
    }

    func dismissReportSheet() {
        guard let d = reportSheet else { return }
        act { e -> Bool in
            if let r = e.pendingReportPrompt() { e.dismissReportPrompt(r) }
            return true
        }
        reportSheet = nil
        if d.kind == .week { Reminders.askOnce() }
        if let e = engine, SessionHooks.cliffhanger(e.state) { homeCliffhanger += 1 }
    }

    func dismissDailySheet() { dailySheet = nil }

    func dismissCelebration() {
        if !celebrationQueue.isEmpty { celebrationQueue.removeFirst() }
    }

    private func report(_ fresh: [Message]) {
        if fresh.contains(where: { $0.isOwnerAddressed && ($0.status == "open" || $0.severity >= 3) }) { Haptics.warning() }
        let alerts: [Message] = fresh.filter { (m: Message) -> Bool in m.isAlert && !redAlerts.contains(where: { (a: Message) -> Bool in a.id == m.id }) }
        if !alerts.isEmpty { Haptics.failure(); redAlerts.append(contentsOf: alerts) }
    }

    @discardableResult
    func act<T>(_ body: (inout GameEngine) -> T) -> T? {
        guard var e = engine else { return nil }
        let r = body(&e)
        engine = e
        save()
        SeasonModel.shared.observe(e.state)
        StoreSession.shared.receiveLevel(e.playerLevel.level)
        queueNotices()
        return r
    }

    func dailyGoal() -> PlayerGoals.DailyGoal? {
        guard var e = engine else { return nil }
        let before: JSONValue? = e.state.rest["dy59"]
        let goal: PlayerGoals.DailyGoal? = e.dailyGoal()
        if e.state.rest["dy59"] != before {
            engine = e
            save()
        }
        return goal
    }

    var claimableGoals: [GoalClaims.Claimable] { engine?.claimableGoals(now: Date()) ?? [] }

    func claimGoal(_ kind: GoalClaims.Kind, id: String) {
        guard case .claimed(let title, let reward, let cash)? = act({ $0.claimGoal(kind: kind, id: id) }) else { return }
        Haptics.success()
        var parts: [String] = [title]
        if !reward.isEmpty { parts.append(reward) }
        if cash > 0, let cur = engine?.homeCurrency { parts.append("+" + cur.display(cash)) }
        tell("Reward claimed", parts.joined(separator: ". "), tone: "good")
    }

    func answer(_ message: Message, option: Int) {
        act { $0.answer(messageID: message.id, option: option) }
        Haptics.success()
    }

    func markRead(_ id: Int) {
        guard var e = engine else { return }
        e.update { s, _, _ in if let i = s.inbox.firstIndex(where: { $0.id == id }), !s.inbox[i].isRead { s.inbox[i].isRead = true } }
        engine = e
    }

    @discardableResult
    func settle(_ result: SettingResult?, _ done: String, same: String = "Already set.", tone: String = "n") -> Bool {
        switch result {
        case .applied?: show(done, tone: tone); return true
        case .unchanged?: show(same, tone: "n"); return true
        case .refused(let why)?: Haptics.warning(); show(why, tone: "warn"); return false
        case nil: return false
        }
    }

    func saved(_ what: String) { show("Saved: \(what)", tone: "n") }

    func show(_ text: String, tone: String = "n") {
        switch tone {
        case "bad", "warn":
            tell("", text, tone: tone)
        default:
            outcomeCapture?.lines.append(text.tidyText)
        }
    }

    func tell(_ title: String, _ text: String, tone: String = "n") {
        outcomeCapture?.refused = true
        let t = Toast(title: title, text: text.tidyText, tone: tone)
        if notices.last?.text == t.text && notices.last?.title == t.title { return }
        notices.append(t)
    }

    func tellLocked(_ app: PhoneApp, reason: String) {
        var text: String = reason
        if let g = app.gate, let item = engine?.unlockRoadmap().first(where: { (i: UnlockRoadmapItem) -> Bool in i.id == "gate." + g.rawValue }), !item.detail.isEmpty {
            text += "\n" + item.detail
        }
        var t = Toast(title: app.title + " is locked", text: text, tone: "n")
        t.style = "locked"
        notices.append(t)
    }

    func tabLockReason(_ t: AppTab) -> String? {
        guard t == .projects, let e = engine else { return nil }
        if !LevelGates.isOpen(.ventures, e.state) { return LevelGates.lockLine(.ventures) }
        guard !Gates.isOpen(.ventures, e.state, data: e.data) else { return nil }
        return Gate.ventures.lockText ?? "Not unlocked yet"
    }

    func tellTabLocked(_ t: AppTab, reason: String) {
        var text: String = reason
        if !reason.hasPrefix("Unlocks at level"), let item = engine?.unlockRoadmap().first(where: { (i: UnlockRoadmapItem) -> Bool in i.id == "gate." + Gate.ventures.rawValue }), !item.detail.isEmpty {
            text += "\n" + item.detail
        }
        var n = Toast(title: t.title + " is locked", text: text, tone: "n")
        n.style = "locked"
        notices.append(n)
    }

    func tellLuxury(name: String, price: String) {
        var t = Toast(title: name, text: "", tone: "good")
        t.style = "luxury"
        t.subtitle = "Now in your vault"
        t.rows = [price]
        notices.append(t)
    }

    func announceAnswer(label: String, effects: [String], ok: Bool, messageTitle: String = "", companyID: Int = 0) {
        guard ok else { Haptics.warning(); tell("Not applied", "That answer could not be applied: the message is no longer open.", tone: "warn"); return }
        Haptics.success()
        outcome(chosen: label, result: effects.joined(separator: "\n"))
    }

    func outcome(chosen: String, result: String, link: DecisionLink? = nil) {
        let c: String = chosen.tidyText
        let r: String = result.tidyText
        outcomeCapture?.told = true
        if r.isEmpty { Haptics.success(); return }
        outcomes.append(OutcomeNote(chosen: c, result: r.isEmpty ? "Done: " + c : r, link: link))
    }

    func runConfirmed(_ action: PendingAction) {
        let outer: OutcomeCapture? = outcomeCapture
        outcomeCapture = OutcomeCapture()
        action.run()
        let c: OutcomeCapture = outcomeCapture ?? OutcomeCapture()
        outcomeCapture = outer
        guard !c.refused, !c.told else { return }
        SoundCues.play(.paymentOut)
        outcome(chosen: action.button, result: c.lines.joined(separator: "\n"))
    }
    func dismissOutcome() { if !outcomes.isEmpty { outcomes.removeFirst() } }

    func dismissNotice() { if !notices.isEmpty { notices.removeFirst() } }

    func go(popup action: Suggestion.Action) {
        if case .openMessage(let id) = action, engine?.state.inbox.contains(where: { $0.id == id && $0.status == "open" }) == true {
            Haptics.tap(); decisionPopup = id
        } else { go(action) }
    }

    var returnInfo: ReturnInfo? { nil }
    var returnTab: AppTab? { nil }
    func returnToOrigin() {}

    func path(for tab: AppTab) -> [NavRoute] { stacks[tab] ?? [] }
    var phonePath: [NavRoute] { path(for: .phone) }
    var customPath: [NavRoute] { path(for: .custom) }
    func depth(_ tab: AppTab) -> Int { path(for: tab).count }
    func rootToken(_ tab: AppTab) -> Int { rootTokens[tab] ?? 0 }

    func setPath(_ new: [NavRoute], for tab: AppTab) {
        let old = path(for: tab)
        var next = new
        if new.count == old.count + 1, var last = new.last {
            if last == .market {
                appRequest = .market(companyID: 0)
                last = .app(.market)
            }
            next = Self.collapse(old, pushing: last)
        }
        guard next != old else { return }
        stacks[tab] = next
    }

    static func collapse(_ old: [NavRoute], pushing route: NavRoute) -> [NavRoute] {
        var base = old
        if route.companyID != nil, base.last == .newCompany { base.removeLast() }
        if let i = base.lastIndex(where: { $0.key == route.key }) { return Array(base.prefix(i)) + [route] }
        return base + [route]
    }

    func push(_ route: NavRoute, on target: AppTab? = nil) {
        let t = target ?? tab
        let now: Date = Date()
        if let last = lastPush, last.route == route, last.tab == t, now.timeIntervalSince(last.at) < 0.4 { return }
        lastPush = LastPush(route: route, tab: t, at: now)
        setPath(path(for: t) + [route], for: t)
    }

    func replaceTop(with route: NavRoute) {
        let t = tab
        var base = path(for: t)
        guard !base.isEmpty else { push(route, on: t); return }
        base.removeLast()
        if let i = base.lastIndex(where: { $0.key == route.key }) { base = Array(base.prefix(i)) }
        Haptics.choose()
        stacks[t] = base + [route]
    }

    func openCompany(_ id: Int, section: CompanySection? = nil, part: String? = nil) {
        if section == .market { openMarket(companyID: id); return }
        if section == .chain { openGroupEntity(companyID: id); return }
        let route = NavRoute.make(id, section, part)
        let target = tab
        Task { @MainActor [weak self] in self?.push(route, on: target) }
    }

    func openGroupEntity(companyID: Int, section: String = "expansion") {
        guard let e = engine else { return }
        let list: [GroupEntity] = GroupEntities.cached(self) ?? GroupEntities.build(e)
        guard let g = GroupEntities.find(list, companyID: companyID) else { openCompany(companyID); return }
        let s: GroupSection = GroupSection.from(key: section)
        Haptics.tap()
        push(.entity(g.id, s))
    }

    @available(*, deprecated, message: "Links never change tab: use push(_:)")
    func open(_ route: NavRoute, on dest: AppTab) { push(route) }

    func setPhonePath(_ new: [NavRoute]) { setPath(new, for: .phone) }
    func setCustomPath(_ new: [NavRoute]) { setPath(new, for: .custom) }

    @available(*, deprecated, message: "Links never change tab: use openApp(_:) or push(_:)")

    private func clearStack(_ tab: AppTab) { stacks[tab] = [] }

    func selectTab(_ t: AppTab, resetRoot: Bool = true) {
        if let reason = tabLockReason(t) { Haptics.warning(); tellTabLocked(t, reason: reason); return }
        if t == tab {
            popToRoot(t)
        } else {
            if resetRoot { popToRoot(t) }
            previousTab = tab
            tab = t
        }
        appRequest = nil
    }

    func popToRoot(_ t: AppTab) {
        let deep: Bool = !(stacks[t] ?? []).isEmpty
        clearStack(t)
        if deep || t != tab { rootTokens[t] = rootToken(t) + 1 }
        appRequest = nil
    }

    func openApp(_ app: PhoneApp, request: AppRequest? = nil) {
        if var e = engine, e.noteVisit(app: app.rawValue) { engine = e }
        appRequest = request
        if app == .store { selectTab(.custom); return }
        push(.app(app))
    }

    func openVentures() {
        if let reason = tabLockReason(.projects) { Haptics.warning(); tellTabLocked(.projects, reason: reason); return }
        if tab != .projects { selectTab(.projects, resetRoot: false) }
        clearStack(.projects)
        appRequest = .ventures
    }

    func noteVisit(_ key: String) {
        if var e = engine, e.noteVisit(app: key) { engine = e }
    }

    func openBank(_ account: BankAccountID, tab: BankTab = .loans, applyLoan: Double? = nil) {
        openApp(.bank, request: .bank(BankRequest(account: account, tab: tab, applyLoan: applyLoan)))
    }

    @Published var pendingLoanApply: Double?

    func openMarket(companyID: Int? = nil) {
        openApp(.market, request: .market(companyID: companyID ?? 0))
    }

    func openMarket(tab: MarketUI.Tab) {
        openApp(.market, request: .marketTab(tab))
    }

    func openMessage(_ id: Int) { openApp(.inbox, request: .message(id)) }

    func takeVenturesRequest() -> Bool {
        guard case .ventures? = appRequest else { return false }
        appRequest = nil
        return true
    }
    func takeAuctionListing() -> String? {
        guard case .auctionListing(let id)? = appRequest else { return nil }
        appRequest = nil
        return id
    }
    func takeNewsPlayersRequest() -> Bool {
        guard case .newsPlayers? = appRequest else { return false }
        appRequest = nil
        return true
    }
    func takeMessageRequest() -> Int? {
        guard case .message(let id)? = appRequest else { return nil }
        appRequest = nil
        return engine?.state.inbox.contains(where: { $0.id == id }) == true ? id : nil
    }
    func takeBankRequest() -> BankRequest? {
        guard case .bank(let r)? = appRequest else { return nil }
        appRequest = nil
        return r
    }
    func takeMarketRequest() -> Int? {
        guard case .market(let id)? = appRequest else { return nil }
        appRequest = nil
        return id
    }
    func takeMarketTabRequest() -> MarketUI.Tab? {
        guard case .marketTab(let t)? = appRequest else { return nil }
        appRequest = nil
        return t
    }
    func takeAirStayRequest() -> Int? {
        guard case .airStay(let id)? = appRequest else { return nil }
        appRequest = nil
        return id
    }
    func takeTechProRequest() -> (companyID: Int, equipmentID: String)? {
        guard case .techPro(let id, let item)? = appRequest else { return nil }
        appRequest = nil
        return (id, item)
    }
    func takeAtlasRequest() -> Int? {
        guard case .atlas(let id)? = appRequest else { return nil }
        appRequest = nil
        return id
    }
    private func resetNavigation() {
        tab = .company
        stacks = [:]; rootTokens = [:]; appRequest = nil
        reportSheet = nil; dailySheet = nil; decisionPopup = nil; workerPopup = nil; seedUpdateMarks(); outcomes = []; notices = []; redAlerts = []; celebrationQueue = []; unlockQueue = []; dayChip = nil
    }

    func go(_ action: Suggestion.Action) {
        Haptics.tap()
        switch action {
        case .openMessage(let id): openMessage(id)
        case .openCompany(let id, let key): openCompany(id, section: key.flatMap { CompanySection(key: $0) })
        case .openLoans:
            let short: Double = max(0, -(engine?.state.cash ?? 0))
            openBank(.personal, tab: .loans, applyLoan: short > 0 ? (short / 100).rounded(.up) * 100 : nil)
        case .openInvest: openMarket(tab: .invest)
        case .openTax: openBank(.personal, tab: .statements)
        case .newCompany: push(.newCompany)
        }
    }

    var unreadCount: Int { memo("unread") { $0.state.inbox.filter { !$0.isRead || $0.status == "open" }.count } ?? 0 }
    var openDecisionCount: Int { memo("openDecisions") { $0.ownerDecisions.count } ?? 0 }

    var phoneAlerts: [PhoneAlert] { engine.map { PhoneAlerts.all(engine: $0, formatter: self) } ?? [] }
}

extension Int {
    var weeksText: String { "\(self) \(self == 1 ? "week" : "weeks")" }
    var peopleText: String { "\(self) \(self == 1 ? "person" : "people")" }
    func countText(_ singular: String, plural: String? = nil) -> String { "\(self) \(self == 1 ? singular : (plural ?? singular + "s"))" }
}

extension Currency {
    func tidyShort(_ v: Double) -> String { short(v).tidyMoney }
    func tidyDisplay(_ v: Double) -> String { display(v).tidyMoney }
}

extension String {
    var tidyMoney: String { TidyMoney.tidy(self) }
}

enum TidyMoney {
    private static let rules: [(regex: NSRegularExpression, template: String)] = {
        var list: [(String, String)] = [
            ("(?<=\\d)[\u{00A0}\u{202F}\u{2009}](?=\\d)", ","),
            ("(?<=[£$€¥]\\d{1,3}) (?=\\d{3}(?!\\d))", ","),
            ("(?<=[£$€¥]\\d{1,3},\\d{3}) (?=\\d{3}(?!\\d))", ","),
        ]
        for unit in ["k", "M", "bn"] { list.append(("(?<=\\d) \(unit)\\b", unit)) }
        list.append(("(?<=\\d|\\dk|\\dM|\\dbn) (?=(kr|zł|(?!CEO|CFO|COO|CTO|VAT|PAYE)[A-Z]{3})(?![A-Za-z]))", "\u{00A0}"))
        return list.compactMap { (p: (String, String)) -> (regex: NSRegularExpression, template: String)? in
            guard let r = try? NSRegularExpression(pattern: p.0) else { return nil }
            return (r, p.1)
        }
    }()
    private static let lock = NSLock()
    private static var cache: [String: String] = [:]
    private static let digits = CharacterSet.decimalDigits

    static func tidy(_ s: String) -> String {
        guard mayChange(s) else { return s }
        lock.lock()
        let hit: String? = cache[s]
        lock.unlock()
        if let hit { return hit }
        var t: String = s
        for rule in rules {
            let range = NSRange(t.startIndex..<t.endIndex, in: t)
            t = rule.regex.stringByReplacingMatches(in: t, options: [], range: range, withTemplate: rule.template)
        }
        lock.lock()
        if cache.count > 4000 { cache.removeAll(keepingCapacity: true) }
        cache[s] = t
        lock.unlock()
        return t
    }

    static func mayChange(_ s: String) -> Bool {
        var p1: Unicode.Scalar = " ", p2: Unicode.Scalar = " ", p3: Unicode.Scalar = " "
        for c in s.unicodeScalars {
            if c == " " || c == "\u{00A0}" || c == "\u{202F}" || c == "\u{2009}" {
                if digits.contains(p1) { return true }
                if (p1 == "k" || p1 == "M") && digits.contains(p2) { return true }
                if p1 == "n" && p2 == "b" && digits.contains(p3) { return true }
            }
            p3 = p2; p2 = p1; p1 = c
        }
        return false
    }
}

@MainActor
enum ProfileStore {
    private static let key = "ledger.profile.progress"
    private static var cache: ProfileProgress = stored()

    private static func stored() -> ProfileProgress {
        guard let d = UserDefaults.standard.data(forKey: key), let p = try? JSONDecoder().decode(ProfileProgress.self, from: d) else { return ProfileProgress() }
        return p
    }

    static func record(_ p: ProfileProgress) {
        let merged: ProfileProgress = cache.merged(with: p)
        guard merged != cache else { return }
        cache = merged
        if let d = try? JSONEncoder().encode(merged) { UserDefaults.standard.set(d, forKey: key) }
    }

    static func adopt(into e: inout GameEngine) {
        let known: ProfileProgress = cache
        e.update { s, _, _ in _ = PlayerLevel.adopt(&s, profile: known) }
        record(PlayerLevel.profile(of: e.state))
    }
}
