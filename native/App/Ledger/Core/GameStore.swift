import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Investments
import Events
import SaveSystem
import Simulation

/// The five destinations: Home (portfolio and companies), Team (everyone who works for you), Group (ownership and structure), Projects
/// (time-bound work and investments) and Phone (the apps: Inbox, Bank, Reports, News ...).
/// The five tabs. The raw values are the route and deep-link names and never change: `.company` is displayed as "Home", and `.phone`
/// (the Phone tab, home of the apps; Inbox is an app inside it) replaced the old Inbox tab.
enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case company, team, group, projects, phone
    var id: String { rawValue }
    var title: String { switch self { case .company: return "Home"; case .team: return "Team"; case .group: return "Group"; case .projects: return "Projects"; case .phone: return "Phone" } }
    /// SF Symbol for the iPad sidebar; the floating tab bar uses `glyph`.
    var symbol: String {
        switch self { case .company: return "house"; case .team: return "person.3"; case .group: return "square.stack.3d.up"; case .projects: return "hammer"; case .phone: return "iphone" }
    }
    /// The house icon (SVG path data from the new-look mockups).
    var glyph: String {
        switch self { case .company: return Glyph.home; case .team: return Glyph.team; case .group: return Glyph.group; case .projects: return Glyph.projects; case .phone: return Glyph.phone }
    }
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
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var tone: String
}

/// Owns the running game and the save files. Views read `engine` and call the methods here; no game rules live in views.
@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var engine: GameEngine?
    @Published var toast: Toast?
    @Published var errorText: String?

    // MARK: Navigation state (the one owner; the methods are under "Navigation" below)

    /// The selected tab. Selecting one by hand (`selectTab`) forgets where a link came from.
    @Published var tab: AppTab = .company { didSet { if tab != oldValue && !jumping { returnInfo = nil } } }
    private var jumping = false
    /// The navigation stack of Home, Team, Group and Projects. The tab roots bind to these; nothing else holds a stack.
    @Published private(set) var routePaths: [AppTab: [CompanyRoute]] = [:]
    /// The Phone tab's stack: apps, and the companies a link opened from inside an app.
    @Published private(set) var phonePath: [PhoneHome.Page] = []
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
        if isShowcase, let e = try? GameEngine.showcase(wealthy: ProcessInfo.processInfo.arguments.contains("-showcase-rich")) { engine = e }
        else if let saves, saves.hasSave() { loadCurrent() }
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

    func newGame(name: String, countryCode: String, story: LifeStory = .loan, cityID: String? = nil) {
        do { engine = try GameEngine.newGame(countryCode: countryCode, playerName: name, cityID: cityID, story: story); loadProblem = nil; resetNavigation(); save() } catch { errorText = "Could not start a game: \(error)" }
    }

    /// Import a save from the HTML game. The original text is kept in `Imports/` untouched.
    func importLegacy(text: String) {
        guard let saves else { return }
        do { try start(with: saves.importLegacy(text: text)); loadProblem = nil; resetNavigation(); save(); show("Save imported. The original file is kept untouched.", tone: "good") }
        catch { errorText = "That save could not be imported. " + Self.describe(error) }
    }

    func exportText() -> String? {
        guard let engine, let d = try? JSONEncoder().encode(engine.state) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    func quitToMenu() { save(); resetNavigation(); engine = nil }

    // MARK: Time

    func nextDay() {
        guard var e = engine else { return }
        let out = e.nextDay()
        engine = e
        if out.completedWeek { Haptics.weekDone() } else { Haptics.advanceDay() }
        report(out.newMessages)
        if out.completedWeek { save(backup: e.state.week % 4 == 0) } else { save() }
        if out.gameOver { Haptics.failure() }
    }

    private func report(_ fresh: [Message]) {
        if let m = fresh.first(where: { $0.status == "open" }) { Haptics.warning(); show(m.title, tone: "warn") }
        else if let m = fresh.first(where: { $0.tone == "bad" }) { Haptics.warning(); show(m.title, tone: "bad") }
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

    func show(_ text: String, tone: String = "n") {
        let t = Toast(text: text.tidyText, tone: tone)
        toast = t
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if self?.toast?.id == t.id { self?.toast = nil }
        }
    }

    // MARK: Navigation

    /// The tab the player came from while a link has them on another tab (the gold "Back to <tab>" line at a tab root).
    var returnTab: AppTab? { returnInfo?.from }

    func path(for tab: AppTab) -> [CompanyRoute] { routePaths[tab] ?? [] }
    /// How many screens are pushed on a tab (0 = its root).
    func depth(_ tab: AppTab) -> Int { tab == .phone ? phonePath.count : path(for: tab).count }
    func rootToken(_ tab: AppTab) -> Int { rootTokens[tab] ?? 0 }

    /// The tab roots set their stack through here (a push, a pop by Back or by swipe). A record that is already on the stack is not
    /// stacked twice: a link to it goes back to it. When a link's screen is popped the player returns to where the link came from.
    func setPath(_ new: [CompanyRoute], for tab: AppTab) {
        let old = path(for: tab)
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
        let t = target ?? tab
        if t == .phone { setPhonePath(phonePath + [.company(route)]) } else { setPath(path(for: t) + [route], for: t) }
    }

    /// The one way to open a company (or one of its screens) from anywhere: pushed onto the stack of the tab the player is on, so Back
    /// returns to the screen they came from. A link to a company screen that is already on the stack goes back to it.
    func openCompany(_ id: Int, section: CompanySection? = nil, part: String? = nil) {
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
        } else if path(for: tab).count > depth {
            routePaths[tab] = Array(path(for: tab).prefix(depth))
        }
    }

    private func clearStack(_ tab: AppTab) {
        if tab == .phone { phonePath = [] } else { routePaths[tab] = [] }
    }

    /// A tab chosen by hand (the tab bar or the sidebar). Choosing the tab that is already open returns it to its root.
    func selectTab(_ t: AppTab) {
        if t == tab {
            popToRoot(t)
        } else {
            // Leaving a tab a link opened, by hand: the screens the link pushed there go with it, as with "Back".
            if let r = returnInfo, r.dest == tab { cutStack(r.dest, to: r.destDepth) }
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
        appRequest = request
        if tab == .phone {
            setPhonePath(phonePath + [.app(app)])
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

    /// Opens one message in the Inbox app.
    func openMessage(_ id: Int) { openApp(.inbox, request: .message(id)) }

    /// Opens the Reports app on one report.
    func openReport(_ ref: ReportRef) { openApp(.reports, request: .report(ref)) }

    /// The apps take their request when they appear and when it changes. A request whose target is gone (a message that was removed) is dropped.
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
    func takeReportRequest() -> ReportRef? {
        guard case .report(let r)? = appRequest else { return nil }
        appRequest = nil
        return r
    }

    /// Drops every stack and pending request, so nothing from one game (or one visit) opens in the next.
    private func resetNavigation() {
        jumping = true; tab = .company; jumping = false
        routePaths = [:]; phonePath = []; rootTokens = [:]; returnInfo = nil; appRequest = nil
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
    /// The red bubble count of each app: Inbox = open decisions, Bank = payroll alerts.
    var phoneBadges: [PhoneApp: Int] { engine.map { PhoneAlerts.badges(engine: $0) } ?? [:] }
    /// The number on the Phone tab: every bubble added up (open decisions + payroll alerts).
    var waitingCount: Int { phoneBadges.values.reduce(0, +) }
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
