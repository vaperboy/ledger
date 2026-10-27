import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Investments
import Events
import SaveSystem
import Simulation

/// Five destinations: daily company operations (with today's summary), everyone who works for you, the group (ownership, structure, money),
/// time-bound projects and investments, and decisions. The old Phone pages sit behind a toolbar button on Company and Group.
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

/// The sections of the Money tab.
enum MoneySection: String, CaseIterable, Hashable { case overview = "Overview", bank = "Bank", invest = "Invest", taxes = "Taxes", costs = "Costs", reports = "Reports" }

/// "Push this onto the stack of this tab": the one shape of a deep link to a company.
struct RouteRequest: Equatable {
    let id = UUID()
    var tab: AppTab
    var route: CompanyRoute
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

    // Navigation requests from anywhere (e.g. a suggestion card)
    @Published var tab: AppTab = .company { didSet { if tab != oldValue && !jumping { returnTab = nil } } }
    /// Set while the player is on a tab they were sent to by a link; that tab shows "Back to <returnTab>".
    @Published private(set) var returnTab: AppTab?
    /// A company or record to push onto the navigation stack of `tab` (the tab it was requested from). Taken by `routeRequests`.
    @Published var routeRequest: RouteRequest?
    private var jumping = false
    /// An app of the Phone tab to open (set by `openApp`, taken by `PhoneHome`).
    @Published var phoneAppRequest: PhoneApp?
    /// Kept only so an old link to a money section still compiles (`GroupView` forwards it to the Bank app).
    @Published var moneySection: MoneySection?
    /// An account (and tab) of the Bank app to open (set by `openBank`, taken by `BankApp`).
    @Published var bankRequest: BankRequest?
    /// Open the Reports section on this report (set by the Home prompt).
    @Published var reportRequest: ReportRef?
    @Published var showNewCompany = false
    @Published var openMessageID: Int?
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

    /// The one way to open a company (or one of its sections) from anywhere: it is pushed onto the navigation stack of the tab the
    /// player is on (Home, Team, Group, Projects or Phone), so Back returns to the screen they came from. The request is consumed by
    /// that tab (`routeRequests`), so it cannot leak.
    func openCompany(_ id: Int, section: CompanySection? = nil) {
        let route: CompanyRoute
        if let section { route = .companyAt(id, section) } else { route = .company(id) }
        routeRequest = RouteRequest(tab: tab, route: route)
    }

    /// Switches to another tab for a link that cannot be pushed (a message in the Inbox, a Money section, New company) and remembers
    /// where the player came from; the destination shows "Back to <tab>". Switching tabs by hand clears it.
    func jump(to destination: AppTab) {
        guard destination != tab else { return }
        let from = tab
        jumping = true; tab = destination; jumping = false
        returnTab = from
    }

    /// Back to the tab a link came from.
    func returnToOrigin() {
        guard let back = returnTab else { return }
        jumping = true; tab = back; jumping = false
        returnTab = nil
    }

    /// Opens an app of the Phone tab (Inbox, Bank, News ...), switching to the Phone tab first when needed.
    func openApp(_ app: PhoneApp) {
        phoneAppRequest = app
        jump(to: .phone)
    }

    /// Opens one account of the Bank app (and optionally one of its tabs) from anywhere: a company's "Open in Bank", a loan or tax prompt.
    func openBank(_ account: BankAccountID, tab: BankTab = .account) {
        bankRequest = BankRequest(account: account, tab: tab)
        openApp(.bank)
    }

    /// Opens one message in the Inbox app. `InboxView` takes the request on appear and on change, so it works whether or not
    /// the Inbox was built before.
    func openMessage(_ id: Int) {
        openMessageID = id
        openApp(.inbox)
    }

    /// Drops every pending navigation request, so nothing from one game (or one visit) opens in the next.
    private func resetNavigation() {
        jumping = true; tab = .company; jumping = false; returnTab = nil
        routeRequest = nil; moneySection = nil; bankRequest = nil; reportRequest = nil
        openMessageID = nil; phoneAppRequest = nil; showNewCompany = false
    }

    func go(_ action: Suggestion.Action) {
        Haptics.tap()
        switch action {
        case .openMessage(let id): openMessage(id)
        case .openCompany(let id): openCompany(id)
        case .openLoans: openBank(.personal, tab: .loans)
        case .openInvest: openBank(.investments, tab: .deposits)
        case .openTax: openBank(.personal, tab: .bills)
        case .newCompany: showNewCompany = true; jump(to: .company)
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
