import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Investments
import Events
import SaveSystem
import Simulation

/// The five tabs, left to right: Ventures (Projects), Group, Home (the middle tab, where the game opens), the player's Custom tab (any
/// destination, see `CustomTabTarget`) and Phone (the apps; Inbox is an app inside it). The raw values are the route and deep-link names
/// and never change: `.company` is displayed as "Home", `.projects` as "Ventures". The old Team tab is gone: its people pages live in
/// Group > entity > Management and in each company's Team tab.
enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case projects, group, company, custom, phone
    var id: String { rawValue }
    /// The fixed title; the Custom tab's real title is the chosen destination's (`GameStore.title(for:)`).
    var title: String { switch self { case .company: return "Home"; case .custom: return "Custom"; case .group: return "Group"; case .projects: return "Ventures"; case .phone: return "Phone" } }
    /// SF Symbol for the iPad sidebar; the floating tab bar uses `glyph`.
    var symbol: String {
        switch self { case .company: return "house"; case .custom: return "star"; case .group: return "square.stack.3d.up"; case .projects: return "hammer"; case .phone: return "iphone" }
    }
    /// The house icon (SVG path data from the new-look mockups); the Custom tab's real icon is the destination's (`GameStore.glyph(for:)`).
    var glyph: String {
        switch self { case .company: return Glyph.home; case .custom: return Glyph.bank; case .group: return Glyph.group; case .projects: return Glyph.projects; case .phone: return Glyph.phone }
    }
    /// The tab the game opens on: Home, the middle one. A stored or deep-linked name that no longer exists (the old "team") maps to it.
    static let launch: AppTab = .company
    static func from(raw: String) -> AppTab { AppTab(rawValue: raw) ?? .launch }
}

/// Where a link is going to land and how it gets back: the tab it came from, the tab it opened on, and how many screens that tab's
/// stack held before the link pushed its screen. Back from the screen the link pushed (the stack shrinking to `destDepth`) returns to `from`.
struct ReturnInfo: Equatable {
    var from: AppTab
    var dest: AppTab
    var destDepth: Int
}

/// What a link asks the app it opened to show, once the app is on screen. The one slot for it: taken (and so cleared) by the app that
/// reads it, dropped when the player moves on by hand.
enum AppRequest: Equatable {
    case message(Int)
    case bank(BankRequest)
    case report(ReportRef)
    /// Accounting on one company (its Payroll page when `payroll` is true).
    case accounting(companyID: Int, payroll: Bool)
    /// The Market app on one company (0 = all markets).
    case market(companyID: Int)
    /// The Reviews app on one company.
    case reviews(companyID: Int)
    /// AirStay on one company (0 = all), at the places it could take or the one it works in.
    case airStay(companyID: Int)
    /// TechPro Store shopping for one company, on one item's page ("" = the store front).
    case techPro(companyID: Int, equipmentID: String)
    /// Atlas Insurance for one company.
    case atlas(companyID: Int)
    /// The merged Ventures screen (the Projects tab) on its Ideas and startups segment.
    case ventures
}

/// One notice, told in the in-game popup (never a banner): a refusal, a warning or an outcome the player must see.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    var title: String = ""
    var text: String
    var tone: String
    /// "answered": the result card for an answered decision (what was chosen, where, and what changed).
    var style = ""
    var subtitle = ""
    var rows: [String] = []
}

/// What one day changed, from before/after snapshots of the engine state (no engine code): feeds the animation layer.
struct DayChanges: Equatable {
    var netWorth: Double = 0
    var cash: Double = 0
    var revenue: Double = 0
    /// Change of all loan balances (negative = repaid).
    var debt: Double = 0
}

/// A small payment notice that slides in at the top of the app shell and leaves by itself.
struct PaymentNotice: Equatable, Identifiable {
    let id = UUID()
    var amount: Double
    var from: String
}

/// One line of Home's important-events timeline (kept in memory for the session, newest first).
struct HomeEvent: Equatable, Identifiable {
    let id = UUID()
    var glyph: String
    var text: String
    var day: String
}

/// An amount chip that travels once (dividend received, transfer made).
struct TransferChip: Equatable, Identifiable {
    let id = UUID()
    var label: String
    var amount: Double
}

/// Owns the running game and the save files. Views read `engine` and call the methods here; no game rules live in views.
@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var engine: GameEngine?
    /// Notices waiting to be read, oldest first. The first one is on screen as a popup; reading it shows the next.
    @Published private(set) var notices: [Toast] = []
    /// Red alerts (a company about to be force-sold): a see-through red popup, shown before anything else, closed only by its button.
    @Published private(set) var redAlerts: [Message] = []
    func dismissRedAlert() { if !redAlerts.isEmpty { redAlerts.removeFirst() } }
    var toast: Toast? { notices.first }
    /// The iOS-style notification banners (see `NotificationBannerLayer`).
    let banners = BannerQueue()
    /// The open decision (an Inbox message id) being answered in a popup on the main screen, or nil.
    @Published var decisionPopup: Int?
    @Published var errorText: String?

    // MARK: Day state (Next day, the report sheet, rewards)

    /// True while a day is running: the Next day button shows progress and ignores taps.
    @Published private(set) var isAdvancing = false
    /// The week, month or year report the player must read before the next day runs (nil = none waiting).
    @Published private(set) var reportSheet: ReportDigest?
    /// Rewards earned and not yet shown, oldest first. The Home screen shows the first, one at a time.
    @Published private(set) var celebrationQueue: [Celebration] = []
    /// Brief 7.2: rises by one when a closed week report is continued while a decision expires within 2 weeks. Home watches it (scroll to Needs you, pulse the pill once).
    @Published var homeCliffhanger: Int = 0
    /// Brief 7.3: consecutive calendar days played; Home shows it from 3 up, else 0 is returned.
    var playStreakShown: Int {
        guard let e = engine else { return 0 }
        let n: Int = PlayStreak.current(e.state, today: GameStore.calendarDay())
        return n >= PlayStreak.showFrom ? n : 0
    }
    /// Local calendar day number (days since the era start), the unit of the play streak.
    static func calendarDay() -> Int { Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0 }
    /// The app went to the background: plan the reminders for the state the player left.
    func scheduleReminders() {
        guard let e = engine else { return }
        Reminders.schedule(SessionHooks.reminders(e.state))
    }
    /// Newly opened features waiting for their announcement popup, oldest first (UnlockKit.swift). One shows at a time, after the day's popups.
    @Published var unlockQueue: [UnlockPrompt] = []
    /// What the last ordinary day did to net worth and cash (real figures); cleared when a report sheet takes its place.
    @Published private(set) var dayChip: DayChip?
    /// What the last day changed (net worth, cash, revenue, debt), for the animation layer.
    @Published private(set) var lastDayChanges = DayChanges()
    /// The one payment notice of the day (a big customer payment), shown as a self-dismissing banner.
    @Published private(set) var paymentNotice: PaymentNotice?
    /// What each Phone app has shown the player so far (badges count what is newer), and what was already announced in a banner.
    @Published var seenMarks = UpdateMarks.load("seen")
    var announcedMarks = UpdateMarks.load("announced")
    /// Per Phone app (by raw value): the marks when the app was opened, and the item ids that were new then (ItemMarks.swift).
    var visitBaselines: [String: UpdateMarks] = [:]
    @Published var visitFresh: [String: Set<String>] = [:]
    /// A worker's profile opened from a Recognition banner.
    @Published var workerPopup: WorkerPopupRef?
    /// The last important events (big payments, loan repayments, good news, milestones), newest first, at most 12.
    @Published private(set) var homeEvents: [HomeEvent] = []
    private func logEvents(_ items: [HomeEvent]) {
        guard !items.isEmpty else { return }
        homeEvents = Array((items + homeEvents).prefix(12))
    }
    /// A chip that flies from a company to the personal account (a view calls `flyChip` after a dividend is paid out).
    @Published private(set) var transferChip: TransferChip?
    func flyChip(_ label: String, amount: Double) { transferChip = TransferChip(label: label, amount: amount) }
    func clearChip() { transferChip = nil }
    /// The short popup after an ordinary day (real sales and today's messages); nil when there is nothing to say or it has been read.
    @Published private(set) var dailySheet: DailyDigest?
    /// True while the start-of-game ambition prompt is waiting to be answered (before the first day).
    @Published private(set) var ambitionPrompt = false

    // MARK: Navigation state (the one owner; the methods are under "Navigation" below)

    /// The selected tab. Selecting one by hand (`selectTab`) forgets where a link came from.
    @Published var tab: AppTab = AppTab.launch { didSet { if tab != oldValue && !jumping { returnInfo = nil } } }
    private var jumping = false
    private struct LastPush { var route: CompanyRoute; var tab: AppTab; var at: Date }
    private var lastPush: LastPush?
    /// The navigation stack of Home, Group and Ventures. The tab roots bind to these; nothing else holds a stack.
    @Published private(set) var routePaths: [AppTab: [CompanyRoute]] = [:]
    /// The Phone tab's stack: apps, and the companies a link opened from inside an app.
    @Published private(set) var phonePath: [PhoneHome.Page] = []
    /// The Custom tab's stack (its root is the chosen destination), and the destination itself, kept in UserDefaults ("customTab").
    @Published private(set) var customPath: [PhoneHome.Page] = []
    @Published var customTarget: CustomTabTarget? = CustomTabTarget.stored()
    /// The "Change the Custom tab" popup.
    @Published var customPickerOpen = false
    /// Set by a banner for the Market app: it shows its News segment when it takes the request.
    var marketNewsPending = false
    /// Bumped each time a tab is re-selected: the tab root resets its own sub-tab and scrolls to the top.
    @Published private(set) var rootTokens: [AppTab: Int] = [:]
    /// Set while the player is on a tab they were sent to by a link; see `ReturnInfo`.
    @Published private(set) var returnInfo: ReturnInfo?
    /// The one pending request for the app a link opened (an Inbox message, a Bank account, a report).
    @Published private(set) var appRequest: AppRequest?
    /// Set when the save on disk exists but could not be opened; the start screen explains it instead of a passing alert.
    @Published private(set) var loadProblem: String?

    let saves: SaveStore?
    /// Launched with `-showcase` (screenshots, UI tests): a prepared game, and nothing is written to disk.
    private let isShowcase = ProcessInfo.processInfo.arguments.contains("-showcase")

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ledger/Saves", isDirectory: true)
        saves = try? SaveStore(directory: base)
        if isShowcase, let e = try? GameEngine.showcase(wealthy: ProcessInfo.processInfo.arguments.contains("-showcase-rich"), board: ProcessInfo.processInfo.arguments.contains("-showcase-board")) { engine = e }
        else if let saves, saves.hasSave() { loadCurrent() }
        ConfirmThreshold.delegated = { [weak self] () -> (limit: Double, rate: Double) in self?.engine?.delegatedSpendLimit() ?? (limit: 0, rate: 0) }
    }

    var hasGame: Bool { engine != nil }
    var hasSavedGame: Bool { saves?.hasSave() ?? false }

    // MARK: Formatting (home currency)

    func money(_ v: Double) -> String { (engine?.homeCurrency.display(v) ?? String(Int(v))).tidyMoney }
    func short(_ v: Double) -> String { (engine?.homeCurrency.short(v) ?? String(Int(v))).tidyMoney }
    func money(_ v: Double, in co: Company) -> String { (engine?.currency(for: co).display(v) ?? String(Int(v))).tidyMoney }
    func short(_ v: Double, in co: Company) -> String { (engine?.currency(for: co).short(v) ?? String(Int(v))).tidyMoney }

    // MARK: Saving and loading

    func loadCurrent() {
        guard let saves else { return }
        do { try start(with: saves.load()); loadProblem = nil; resetNavigation() }
        catch { loadProblem = Self.describe(error) }
    }

    /// The summary written with the current save (player, country, week, companies, when it was saved), or nil when there is none or it is unreadable.
    func currentSaveSummary() -> SaveSummary? {
        saves?.slots().first { $0.slot == "current" }?.summary
    }

    /// A save error in words a player can act on.
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
        engine = e
    }

    func save(backup: Bool = false) {
        guard !isShowcase, let saves, let engine else { return }
        do {
            let summary = saves.summary(of: engine.state, trades: engine.data.catalog)
            try saves.save(engine.state, summary: summary)
            if backup { try saves.backup(engine.state, summary: summary) }
        } catch { errorText = "Saving failed: \(error)" }
    }

    // MARK: Save slots (Settings > Saves > Save slots; `current` is the game being played)

    func slotList() -> [(slot: String, summary: SaveSummary?)] { saves?.slots() ?? [] }

    /// Copies the game being played into a named slot. Returns false when there is no game, the name is unusable or taken.
    @discardableResult
    func saveToSlot(_ raw: String) -> Bool {
        guard !isShowcase, let saves, let engine, let name = SaveStore.cleanSlotName(raw), name != "current", !saves.hasSave(slot: name) else { return false }
        do { try saves.save(engine.state, slot: name, summary: saves.summary(of: engine.state, trades: engine.data.catalog)); return true }
        catch { errorText = "Saving failed: \(error)"; return false }
    }

    /// Makes a slot the game being played. The game it replaces is kept as a backup file first.
    func loadSlot(_ slot: String) {
        guard !isShowcase, let saves else { return }
        save(backup: true)
        do { try start(with: saves.load(slot: slot)); loadProblem = nil; resetNavigation(); save() }
        catch { errorText = "That slot could not be opened. " + Self.describe(error) }
    }

    func deleteSlot(_ slot: String) { try? saves?.delete(slot: slot) }

    @discardableResult
    func renameSlot(_ slot: String, to raw: String) -> Bool { (try? saves?.renameSlot(slot, to: raw)) ?? false }

    /// `story: .fresh` is the new-player start: `tradeID` and `companyName` are the player's two choices after the country.
    func newGame(name: String, countryCode: String, story: LifeStory = .loan, cityID: String? = nil, ambition: String? = nil, tradeID: String? = nil, companyName: String? = nil) {
        RememberedDetails.clearAll()
        do { engine = try GameEngine.newGame(countryCode: countryCode, playerName: name, cityID: cityID, story: story, ambition: ambition, tradeID: tradeID, companyName: companyName); loadProblem = nil; resetNavigation(); save() } catch { errorText = "Could not start a game: \(error)" }
    }

    /// Import a save from the HTML game. The original text is kept in `Imports/` untouched.
    func importLegacy(text: String) {
        guard let saves else { return }
        do { try start(with: saves.importLegacy(text: text)); loadProblem = nil; resetNavigation(); save(); tell("Save imported", "The original file is kept untouched.", tone: "good") }
        catch { errorText = "That save could not be imported. " + Self.describe(error) }
    }

    /// Set at Milestone M8: the classic loan start and the family café become selectable under Settings > Saves > New game.
    static let classicStartKey = "ledger.classicStartUnlocked"
    var classicStartUnlocked: Bool { UserDefaults.standard.bool(forKey: Self.classicStartKey) }

    func exportText() -> String? {
        guard let engine, let d = try? JSONEncoder().encode(engine.state) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    func quitToMenu() { save(); resetNavigation(); engine = nil }

    // MARK: Time

    /// Runs one day. Taps while a day is running, or while a report sheet is waiting to be read, are ignored: a day is never
    /// advanced twice by one press, and a week/month/year report is always read before the next day runs. The pause before the
    /// engine runs is only long enough for the button to show its progress state (the engine itself runs at once).
    func nextDay() {
        guard !isAdvancing, blockingMessageID == nil, reportSheet == nil, celebrationQueue.isEmpty, unlockQueue.isEmpty, !ambitionPrompt, engine != nil else { return }
        isAdvancing = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self?.advanceOneDay()
            self?.isAdvancing = false
        }
    }

    /// The open Inbox item that blocks Play (brief 2.2 and 4.4), if any. 
    var blockingMessageID: Int? { engine?.blockingMessage?.id }

    /// "Play to end of week" is offered from week 2 (the engine's week counter is 0-based).
    var canPlayWeek: Bool {
        guard let e = engine else { return false }
        return e.state.week >= 1 && !e.state.isGameOver
    }

    /// Runs the days left in this week one by one, 0.4 s apart, then leaves the week report. Stops early when a report, a reward or a
    /// popup is waiting, or the game ends. The per-day sheets of the days in between are dropped; the last day's report stays.
    func playToEndOfWeek() {
        guard canPlayWeek, !isAdvancing, blockingMessageID == nil, reportSheet == nil, celebrationQueue.isEmpty, unlockQueue.isEmpty, !ambitionPrompt else { return }
        isAdvancing = true
        let startWeek: Int = engine?.state.week ?? 0
        Task { @MainActor [weak self] in
            while let self, let e = self.engine, e.state.week == startWeek, !e.state.isGameOver {
                try? await Task.sleep(nanoseconds: 400_000_000)
                self.advanceOneDay()
                if self.reportSheet != nil || !self.celebrationQueue.isEmpty || !self.unlockQueue.isEmpty || self.engine?.state.day == 0 { break }
                self.dailySheet = nil
            }
            self?.isAdvancing = false
        }
    }

    /// Group books profit at the end of the last day played (week, day, value); used as the start of the next day's "Profit today".
    private var profitMark: (week: Int, day: Int, value: Double)?

    private func advanceOneDay() {
        guard var e = engine else { return }
        seedUpdateMarks()
        let nwBefore: Double? = e.dayHistory.netWorth.last
        let cashBefore: Double? = e.dayHistory.cash.last
        let debtBefore: Double = e.state.loans.reduce(0) { $0 + $1.balance }
        // Profit today starts where the last day ended, so what the owner did in between (opening a new store in a chain, setting up) counts.
        let profitBefore: Double = { if let m = profitMark, m.week == e.state.week, m.day == e.state.day { return m.value }; return e.groupBooksProfit }()
        let tightBefore: Bool = e.cashIsTight
        let out = e.nextDay()
        let today: Int = GameStore.calendarDay()
        e.update { s, _, _ in PlayStreak.record(&s, today: today) }   // Brief 7.3
        // Brief 7.4: only a finished ladder goal celebrates; trophies, milestones and daily missions are taken and dropped.
        let celebrations: [Celebration] = e.takeCelebrations().filter { $0.kind == "goal" }
        if !celebrations.isEmpty { Haptics.goalDone() }
        if !tightBefore && e.cashIsTight && !out.gameOver { Haptics.cashWarning() }
        let digest: ReportDigest? = e.pendingReportDigest()
        engine = e
        if PlayerGoals.ladderFlag(e.state, "classic") { UserDefaults.standard.set(true, forKey: GameStore.classicStartKey) }   // Milestone M8 (brief 1.2)
        Haptics.nextDay()
        report(out.newMessages)
        if out.completedWeek { save(backup: e.state.week % 4 == 0) } else { save() }
        if out.gameOver { Haptics.failure() }
        celebrationQueue.append(contentsOf: celebrations)
        if out.completedWeek { queueUnlocks() }
        reportSheet = digest
        var daily: DailyDigest = e.dailyDigest(fresh: out.newMessages)
        daily.profit = e.groupBooksProfit - profitBefore
        profitMark = (week: e.state.week, day: e.state.day, value: e.groupBooksProfit)
        if let nwBefore, let nwAfter = e.dayHistory.netWorth.last, let cashBefore, let cashAfter = e.dayHistory.cash.last {
            daily.netWorthChange = nwAfter - nwBefore
            daily.cashChange = cashAfter - cashBefore
        }
        let debtAfter: Double = e.state.loans.reduce(0) { $0 + $1.balance }
        lastDayChanges = DayChanges(netWorth: daily.netWorthChange ?? 0, cash: daily.cashChange ?? 0, revenue: daily.revenue, debt: debtAfter - debtBefore)
        // A major payment (the day's takings above 1.5 percent of net worth) is logged for Home only; it never raises a banner.
        var todaysPayment: PaymentNotice?
        if !out.gameOver, let p = bigPayment(e) {
            let notice = PaymentNotice(amount: p.amount, from: p.from)
            todaysPayment = notice
            paymentNotice = notice
        }
        if !out.gameOver { postUpdateBanners(e) }
        var logged: [HomeEvent] = []
        if let n = todaysPayment { logged.append(HomeEvent(glyph: Glyph.ovCoin, text: "Payments of \(short(n.amount)) from \(n.from)", day: daily.dateLabel)) }
        if lastDayChanges.debt < -0.5 { logged.append(HomeEvent(glyph: Glyph.bank, text: "Loans repaid by \(short(-lastDayChanges.debt))", day: daily.dateLabel)) }
        for line in daily.wentWell.prefix(2) { logged.append(HomeEvent(glyph: Glyph.check, text: line.tidyMoney, day: daily.dateLabel)) }
        for c in celebrations.prefix(2) { logged.append(HomeEvent(glyph: Glyph.achievements, text: c.title, day: daily.dateLabel)) }
        logEvents(logged)
        // Every ordinary day has a report, quiet or busy; only Continue closes it.
        dailySheet = (digest == nil && !out.gameOver) ? daily : nil
        if digest == nil, let nwAfter = e.dayHistory.netWorth.last, let nwBefore {
            let cashAfter: Double = e.dayHistory.cash.last ?? 0
            dayChip = DayChip(id: UUID(), day: e.state.day + 1, netWorthChange: nwAfter - nwBefore, cashChange: cashAfter - (cashBefore ?? cashAfter))
        } else {
            dayChip = nil
        }
    }

    /// The player answers the start-of-game ambition prompt: a path, or nil for "decide later". Either way it is not asked again.
    func chooseAmbition(_ path: String?) {
        act { e -> Bool in
            if let path { e.chooseAmbition(path: path) }
            e.markAmbitionPromptShown()
            return true
        }
        ambitionPrompt = false
        if let path, let name = engine?.ambitionPaths.first(where: { $0.id == path })?.name { show("Your ambition: \(name). Change it freely until week 4.", tone: "good") }
    }

    /// Picks up what was earned or closed while the app was away (a saved game with an unread report or an unshown celebration).
    func refreshPending() {
        guard var e = engine, !isAdvancing else { return }
        ambitionPrompt = e.ambitionPromptPending
        if reportSheet == nil { reportSheet = e.pendingReportDigest() }
        let taken: [Celebration] = e.takeCelebrations()
        let waiting: [Celebration] = taken.filter { $0.kind == "goal" }
        if !taken.isEmpty {
            engine = e
            save()
            celebrationQueue.append(contentsOf: waiting)
        }
        queueUnlocks()
    }

    /// The player has read the report sheet: the report (and the shorter ones that closed with it) are marked seen.
    func dismissReportSheet(openReports: Bool = false) {
        guard let d = reportSheet else { return }
        act { e -> Bool in
            if let r = e.pendingReportPrompt() { e.dismissReportPrompt(r) }
            return true
        }
        reportSheet = nil
        if d.kind == .week { Reminders.askOnce() }   // Brief 7: the system prompt, once, after the first week report
        if let e = engine, SessionHooks.cliffhanger(e.state) { homeCliffhanger += 1 }   // Brief 7.2: Home scrolls to Needs you and the expiry pill pulses once
        if openReports { openReport(ReportRef(kind: d.kind, id: d.reportID)) }
    }

    func dismissDailySheet() { dailySheet = nil }

    /// The popup on screen has been seen: the next one (if any) shows.
    func dismissCelebration() {
        if !celebrationQueue.isEmpty { celebrationQueue.removeFirst() }
    }

    // MARK: Home shortcuts

    /// The four boxes on Home (the saved choice, else the default four).
    var homeShortcuts: [HomeShortcut] { HomeShortcut.resolve(engine?.homeShortcutIDs) }

    func setHomeShortcuts(_ shortcuts: [HomeShortcut]) {
        act { e -> Bool in
            e.setHomeShortcutIDs(shortcuts.map { $0.rawValue })
            return true
        }
    }

    /// A buzz when something needs the player; the words are in the daily popup (and the Inbox), not in a banner.
    private func report(_ fresh: [Message]) {
        if fresh.contains(where: { $0.status == "open" || $0.tone == "bad" }) { Haptics.warning() }
        let alerts: [Message] = fresh.filter { (m: Message) -> Bool in m.isAlert && !redAlerts.contains(where: { (a: Message) -> Bool in a.id == m.id }) }
        if !alerts.isEmpty { Haptics.failure(); redAlerts.append(contentsOf: alerts) }
    }

    // MARK: Acting

    /// Run an action on the engine, publish the result and save.
    @discardableResult
    func act<T>(_ body: (inout GameEngine) -> T) -> T? {
        guard var e = engine else { return nil }
        let r = body(&e)
        engine = e
        save()
        return r
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

    /// Tells the player what a setting-style engine action did: `done` when it changed something, `same` when it was already so (or the
    /// thing has gone), and the engine's reason when it refused. Returns true when the setting now holds.
    @discardableResult
    func settle(_ result: SettingResult?, _ done: String, same: String = "Already set.", tone: String = "n") -> Bool {
        switch result {
        case .applied?: show(done, tone: tone); return true
        case .unchanged?: show(same, tone: "n"); return true
        case .refused(let why)?: Haptics.warning(); show(why, tone: "warn"); return false
        case nil: return false
        }
    }

    /// For a setting the engine applies without a result of its own (a limit, a duty, a slider): a short "Saved" with what it is now.
    func saved(_ what: String) { show("Saved: \(what)", tone: "n") }

    /// A result line from an action. There is no banner: a refusal or a warning (tone "warn" or "bad") is told in a popup because the
    /// player must see why nothing happened; a plain confirmation ("Saved", "Hired") is already visible on the screen, so it just goes.
    func show(_ text: String, tone: String = "n") {
        guard tone == "warn" || tone == "bad" else { banner(text); return }
        tell("", text, tone: tone)
    }

    /// Important information, always told in the popup (an answer with an immediate effect, a result the player waits for).
    func tell(_ title: String, _ text: String, tone: String = "n") {
        let t = Toast(title: title, text: text.tidyText, tone: tone)
        if notices.last?.text == t.text && notices.last?.title == t.title { return }
        notices.append(t)
    }

    /// A luxury purchase is confirmed on a gold-edged reveal card (see `GoldReveal`).
    func tellLuxury(name: String, price: String) {
        var t = Toast(title: name, text: "", tone: "good")
        t.style = "luxury"
        t.subtitle = "Now in your vault"
        t.rows = [price]
        notices.append(t)
    }

    /// An answer to an open decision has an effect at once, so it is told at once, in a popup (what was chosen and what it does).
    func announceAnswer(label: String, effects: [String], ok: Bool, messageTitle: String = "", companyID: Int = 0) {
        guard ok else { Haptics.warning(); tell("Not applied", "That answer could not be applied: the message is no longer open.", tone: "warn"); return }
        Haptics.success()
        var rows: [String] = effects
        var who = ""
        if companyID != 0, let e = engine, let co = e.state.company(companyID) {
            who = co.name
            rows.append("\(co.name) now has \(short(co.cash, in: co)) in its account")
        }
        let t = Toast(title: label, text: effects.joined(separator: "\n"), tone: "good", style: "answered", subtitle: ([messageTitle, who].filter { !$0.isEmpty }).joined(separator: " \u{00B7} "), rows: rows)
        if notices.last?.title == t.title && notices.last?.subtitle == t.subtitle { return }
        notices.append(t)
    }

    /// The popup on screen has been read: the next notice (if any) shows.
    func dismissNotice() { if !notices.isEmpty { notices.removeFirst() } }

    /// A top-priority row: a decision opens in a popup right here, anything else goes to its screen.
    func go(popup action: Suggestion.Action) {
        if case .openMessage(let id) = action, engine?.state.inbox.contains(where: { $0.id == id && $0.status == "open" }) == true {
            Haptics.tap(); decisionPopup = id
        } else { go(action) }
    }

    // MARK: Navigation

    /// The tab the player came from while a link has them on another tab (the gold "Back to <tab>" line at a tab root).
    var returnTab: AppTab? { returnInfo?.from }

    func path(for tab: AppTab) -> [CompanyRoute] { routePaths[tab] ?? [] }
    /// How many screens are pushed on a tab (0 = its root).
    func depth(_ tab: AppTab) -> Int { tab == .phone ? phonePath.count : (tab == .custom ? customPath.count : path(for: tab).count) }
    func rootToken(_ tab: AppTab) -> Int { rootTokens[tab] ?? 0 }

    /// The tab roots set their stack through here (a push, a pop by Back or by swipe). A record that is already on the stack is not
    /// stacked twice: a link to it goes back to it. When a link's screen is popped the player returns to where the link came from.
    func setPath(_ new: [CompanyRoute], for tab: AppTab) {
        let old = path(for: tab)
        // A link to the Market route (a deep link, a stored route) opens the Market app of the Phone instead of a page on this stack.
        if new.count == old.count + 1, new.last == .market {
            openMarket()
            return
        }
        var next = new
        if new.count == old.count + 1, let last = new.last {
            next = Self.collapse(old, pushing: last)
        }
        guard next != old else { return }
        routePaths[tab] = next
        afterPathChange(tab, depth: next.count, grew: next.count > old.count)
    }

    func setPhonePath(_ new: [PhoneHome.Page]) {
        let old = phonePath
        var next = new
        if new.count == old.count + 1, let last = new.last {
            if let i = old.lastIndex(where: { $0.key == last.key }) { next = Array(old.prefix(i)) + [last] }
        }
        guard next != old else { return }
        phonePath = next
        afterPathChange(.phone, depth: next.count, grew: next.count > old.count)
    }

    func setCustomPath(_ new: [PhoneHome.Page]) {
        let old = customPath
        var next = new
        if new.count == old.count + 1, let last = new.last {
            if let i = old.lastIndex(where: { $0.key == last.key }) { next = Array(old.prefix(i)) + [last] }
        }
        guard next != old else { return }
        customPath = next
        afterPathChange(.custom, depth: next.count, grew: next.count > old.count)
    }

    /// `old` with `route` pushed, unless the same record is already on it: then the stack is cut back to that record, which takes the
    /// new route (so a link to another section of it shows that section). A finished "new company" form is not kept behind a push.
    static func collapse(_ old: [CompanyRoute], pushing route: CompanyRoute) -> [CompanyRoute] {
        var base = old
        if route != .newCompany, base.last == .newCompany { base.removeLast() }
        if let i = base.lastIndex(where: { $0.key == route.key }) { return Array(base.prefix(i)) + [route] }
        return base + [route]
    }

    /// The stack of `tab` shrank back to where a link found it: the player goes back to the tab the link came from.
    private func afterPathChange(_ tab: AppTab, depth: Int, grew: Bool) {
        guard let r = returnInfo, r.dest == tab, !grew, depth <= r.destDepth else { return }
        returnToOrigin()
    }

    /// Pushes `route` on the stack of a tab: the one the player is on by default (a company opened from Team stays on Team, so Back
    /// returns to Team).
    func push(_ route: CompanyRoute, on target: AppTab? = nil) {
        if route == .market { openMarket(); return }
        let t = target ?? tab
        // A double tap must not push the same screen twice: the same route on the same tab within 0.4 s is ignored.
        let now: Date = Date()
        if let last = lastPush, last.route == route, last.tab == t, now.timeIntervalSince(last.at) < 0.4 { return }
        lastPush = LastPush(route: route, tab: t, at: now)
        if t == .phone { setPhonePath(phonePath + [.company(route)]) }
        else if t == .custom { setCustomPath(customPath + [.company(route)]) }
        else { setPath(path(for: t) + [route], for: t) }
    }

    /// The one way to open a company (or one of its screens) from anywhere: pushed onto the stack of the tab the player is on, so Back
    /// returns to the screen they came from. A link to a company screen that is already on the stack goes back to it.
    func openCompany(_ id: Int, section: CompanySection? = nil, part: String? = nil) {
        // The Market is a Phone app: a link to a company's market opens it with that company chosen.
        if section == .market { openMarket(companyID: id); return }
        // Chain and franchise live on the company's entity page in the Group tab.
        if section == .chain { openGroupEntity(companyID: id); return }
        let route = CompanyRoute.make(id, section, part)
        let target = tab
        // One turn later: a screen that opens a company and then closes itself (a finished form) must pop before the push lands.
        Task { @MainActor [weak self] in self?.push(route, on: target) }
    }

    /// A link that lands on another tab: the screen is pushed on that tab's stack and the player is taken there. Back from it returns
    /// to the tab they came from, and the other tab keeps no screen from the link.
    func open(_ route: CompanyRoute, on dest: AppTab) {
        guard dest != tab else { push(route, on: dest); return }
        let before = depth(dest)
        let from = tab
        push(route, on: dest)
        arrive(on: dest, from: from, depth: before)
    }

    /// A link that lands on the root of another tab (the stack there is cleared, so the root is what shows).
    func jump(to destination: AppTab) {
        guard destination != tab else { return }
        let from = tab
        clearStack(destination)
        arrive(on: destination, from: from, depth: 0)
    }

    private func arrive(on dest: AppTab, from: AppTab, depth: Int) {
        jumping = true; tab = dest; jumping = false
        returnInfo = ReturnInfo(from: from, dest: dest, destDepth: depth)
    }

    /// Back to the tab a link came from; the tab the link opened is cut back to where it was before the link.
    func returnToOrigin() {
        guard let r = returnInfo else { return }
        returnInfo = nil
        cutStack(r.dest, to: r.destDepth)
        appRequest = nil
        jumping = true; tab = r.from; jumping = false
    }

    /// Pops a tab's stack back to `depth` screens (what it held before a link pushed onto it).
    private func cutStack(_ tab: AppTab, to depth: Int) {
        if tab == .phone {
            if phonePath.count > depth { phonePath = Array(phonePath.prefix(depth)) }
        } else if tab == .custom {
            if customPath.count > depth { customPath = Array(customPath.prefix(depth)) }
        } else if path(for: tab).count > depth {
            routePaths[tab] = Array(path(for: tab).prefix(depth))
        }
    }

    private func clearStack(_ tab: AppTab) {
        if tab == .phone { phonePath = [] } else if tab == .custom { customPath = [] } else { routePaths[tab] = [] }
    }

    /// A tab chosen by hand. A tap on the tab bar or the sidebar (`resetRoot` true) always shows that tab's ROOT: the screens it had are
    /// dropped. A swipe between tabs (`resetRoot` false) keeps the place it had. Choosing the tab that is already open returns it to its root.
    /// A link (`open`, `jump`, `openApp`) sets the destination's stack itself and never comes through here.
    func selectTab(_ t: AppTab, resetRoot: Bool = true) {
        if t == tab {
            popToRoot(t)
        } else {
            // Leaving a tab a link opened, by hand: the screens the link pushed there go with it, as with "Back".
            if let r = returnInfo, r.dest == tab { cutStack(r.dest, to: r.destDepth) }
            if resetRoot { popToRoot(t) }
            tab = t
        }
        appRequest = nil
    }

    /// Pops a tab to its root: no pushed screens, and the root shows its first page scrolled to the top.
    func popToRoot(_ t: AppTab) {
        clearStack(t)
        rootTokens[t] = rootToken(t) + 1
        if returnInfo?.dest == t { returnInfo = nil }
        appRequest = nil
    }

    /// Opens an app of the Phone tab (Inbox, Bank, News ...). From another tab the Phone stack is replaced by the app and Back returns
    /// to where the link was; on the Phone it is pushed (or, when already on the stack, gone back to).
    func openApp(_ app: PhoneApp, request: AppRequest? = nil) {
        // Ventures lives in the Projects tab now: any link to the old Phone app lands on its Ideas and startups segment.
        if app == .ventures {
            appRequest = .ventures
            if tab != .projects { let from = tab; arrive(on: .projects, from: from, depth: path(for: .projects).count) }
            return
        }
        appRequest = request
        if tab == .phone {
            setPhonePath(phonePath + [.app(app)])
        } else if tab == .custom {
            setCustomPath(customPath + [.app(app)])
        } else {
            let from = tab
            phonePath = [.app(app)]
            arrive(on: .phone, from: from, depth: 0)
        }
    }

    /// Opens one account of the Bank app (and optionally one of its tabs) from anywhere: a company's "Open in Bank", a loan or tax prompt.
    func openBank(_ account: BankAccountID, tab: BankTab = .account) {
        openApp(.bank, request: .bank(BankRequest(account: account, tab: tab)))
    }

    /// Opens the Accounting app on one company, on its Payroll page when `payroll` is true: the link Team and the Bank use instead of a payroll run of their own.
    func openAccounting(companyID: Int, payroll: Bool = false) {
        openApp(.accounting, request: .accounting(companyID: companyID, payroll: payroll))
    }

    /// Opens the Market app (the Phone), on one company when `companyID` is given, else on all markets.
    func openMarket(companyID: Int? = nil) {
        openApp(.market, request: .market(companyID: companyID ?? 0))
    }

    /// Opens the Reviews app on one company.
    func openReviews(companyID: Int) {
        openApp(.reviews, request: .reviews(companyID: companyID))
    }

    /// Opens AirStay (places to rent) for one company.
    func openAirStay(companyID: Int = 0) { openApp(.airStay, request: .airStay(companyID: companyID)) }

    /// Opens TechPro Store for one company, on one item's page when `equipmentID` is given.
    func openTechPro(companyID: Int, equipmentID: String = "") { openApp(.techPro, request: .techPro(companyID: companyID, equipmentID: equipmentID)) }

    /// Opens Atlas Insurance for one company.
    func openAtlas(companyID: Int) { openApp(.atlas, request: .atlas(companyID: companyID)) }

    /// Opens one message in the Inbox app.
    func openMessage(_ id: Int) { openApp(.inbox, request: .message(id)) }

    /// Opens the Reports app on one report.
    func openReport(_ ref: ReportRef) { openApp(.reports, request: .report(ref)) }

    /// The apps take their request when they appear and when it changes. A request whose target is gone (a message that was removed) is dropped.
    func takeVenturesRequest() -> Bool {
        guard case .ventures? = appRequest else { return false }
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
    func takeAccountingRequest() -> (companyID: Int, payroll: Bool)? {
        guard case .accounting(let id, let payroll)? = appRequest else { return nil }
        appRequest = nil
        return (id, payroll)
    }
    func takeMarketRequest() -> Int? {
        guard case .market(let id)? = appRequest else { return nil }
        appRequest = nil
        return id
    }
    func takeReviewsRequest() -> Int? {
        guard case .reviews(let id)? = appRequest else { return nil }
        appRequest = nil
        return id
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
    func takeReportRequest() -> ReportRef? {
        guard case .report(let r)? = appRequest else { return nil }
        appRequest = nil
        return r
    }

    /// Drops every stack and pending request, so nothing from one game (or one visit) opens in the next.
    private func resetNavigation() {
        jumping = true; tab = .company; jumping = false
        routePaths = [:]; phonePath = []; customPath = []; rootTokens = [:]; returnInfo = nil; appRequest = nil
        reportSheet = nil; dailySheet = nil; decisionPopup = nil; workerPopup = nil; seedUpdateMarks(); banners.reset(); notices = []; redAlerts = []; celebrationQueue = []; unlockQueue = []; dayChip = nil; ambitionPrompt = false
    }

    func go(_ action: Suggestion.Action) {
        Haptics.tap()
        switch action {
        case .openMessage(let id): openMessage(id)
        case .openCompany(let id): openCompany(id)
        case .openLoans: openBank(.personal, tab: .loans)
        case .openInvest: openBank(.investments, tab: .deposits)
        case .openTax: openBank(.personal, tab: .bills)
        case .newCompany: open(.newCompany, on: .company)
        }
    }

    var unreadCount: Int { engine?.state.inbox.filter { !$0.isRead || $0.status == "open" }.count ?? 0 }
    /// Decisions waiting for an answer: the number behind the Inbox app bubble and the Decisions tab badge.
    var openDecisionCount: Int { engine?.state.inbox.filter { $0.status == "open" }.count ?? 0 }

    // MARK: Phone alerts and bubbles

    /// Everything on the Phone that asks for the player, most urgent first (see `PhoneAlert`).
    var phoneAlerts: [PhoneAlert] { engine.map { PhoneAlerts.all(engine: $0, formatter: self) } ?? [] }
    // The red bubbles (`appBadge`, `phoneBadges`, `waitingCount`) are in UpdateBadges.swift.
}

extension Int {
    /// "1 week", "3 weeks".
    var weeksText: String { "\(self) \(self == 1 ? "week" : "weeks")" }
    /// "1 person", "12 people": the one way to count employees on screen.
    var peopleText: String { "\(self) \(self == 1 ? "person" : "people")" }
    /// "1 decision", "3 decisions": a count with a regular plural ("s", or `plural` for the others, like "companies").
    func countText(_ singular: String, plural: String? = nil) -> String { "\(self) \(self == 1 ? singular : (plural ?? singular + "s"))" }
}

extension Currency {
    /// `short` as the player should read it ("£220k", "£2,751"), the same as `GameStore.short`. Views that hold a currency use this,
    /// so the same amount never shows as "£2 751" on one screen and "£2,751" on the next.
    func tidyShort(_ v: Double) -> String { short(v).tidyMoney }
    /// `display` as the player should read it: the one app-side formatter for full amounts ("£8,026", "1,234\u{00A0}kr").
    func tidyDisplay(_ v: Double) -> String { display(v).tidyMoney }
}

extension String {
    /// Money text as the player should read it: "£220 k" becomes "£220k", thousands use a comma ("£8,026", never "£8 026"), and a
    /// symbol that follows the number (kr, zł, three-letter codes) keeps a non-breaking space ("1,234\u{00A0}kr"). Safe to run on
    /// engine-written news, notes and insights, so every amount on screen looks the same.
    var tidyMoney: String {
        var t = self
        // A non-breaking space between digits is a thousands separator.
        t = t.replacingOccurrences(of: "(?<=\\d)[\u{00A0}\u{202F}\u{2009}](?=\\d)", with: ",", options: .regularExpression)
        // Engine sentences turn that separator into a plain space ("£7 745"): a currency symbol, then 1-3 digits, a space, 3 digits.
        t = t.replacingOccurrences(of: "(?<=[£$€¥]\\d{1,3}) (?=\\d{3}(?!\\d))", with: ",", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?<=[£$€¥]\\d{1,3},\\d{3}) (?=\\d{3}(?!\\d))", with: ",", options: .regularExpression)
        for unit in ["k", "M", "bn"] {
            t = t.replacingOccurrences(of: "(?<=\\d) \(unit)\\b", with: unit, options: .regularExpression)
        }
        t = t.replacingOccurrences(of: "(?<=\\d|\\dk|\\dM|\\dbn) (?=(kr|zł|(?!CEO|CFO|COO|CTO|VAT|PAYE)[A-Z]{3})(?![A-Za-z]))", with: "\u{00A0}", options: .regularExpression)
        return t
    }
}
