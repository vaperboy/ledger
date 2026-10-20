import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Investments
import Events
import SaveSystem
import Simulation

/// Five flat destinations: today, the companies (with the group's totals), money (finance, bank, investments), decisions, and the rest.
enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case home, companies, money, inbox, phone
    var id: String { rawValue }
    var title: String { switch self { case .home: return "Home"; case .companies: return "Group"; case .money: return "Money"; case .phone: return "Phone"; case .inbox: return "Inbox" } }
    var symbol: String {
        switch self { case .home: return "house"; case .companies: return "building.2"; case .money: return "banknote"; case .phone: return "iphone.gen3"; case .inbox: return "tray" }
    }
}

enum PhoneDestination: Hashable { case news, stats, activity, luxury, settings, achievements, richList, ranking, worldAround }

/// The sections of the Money tab.
enum MoneySection: String, CaseIterable, Hashable { case overview = "Overview", bank = "Bank", invest = "Invest", taxes = "Taxes", costs = "Costs", reports = "Reports" }

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
    @Published private(set) var isAdvancing = false

    // Navigation requests from anywhere (e.g. a suggestion card)
    @Published var tab: AppTab = .home
    @Published var openCompanyID: Int?
    @Published var phoneDestination: PhoneDestination?
    @Published var moneySection: MoneySection?
    /// Open the Reports section on this report (set by the Home prompt).
    @Published var reportRequest: ReportRef?
    @Published var showNewCompany = false
    @Published var openMessageID: Int?

    let saves: SaveStore?
    private var cancelAdvance = false
    /// Launched with `-showcase` (screenshots, UI tests): a prepared game, and nothing is written to disk.
    private let isShowcase = ProcessInfo.processInfo.arguments.contains("-showcase")

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ledger/Saves", isDirectory: true)
        saves = try? SaveStore(directory: base)
        if isShowcase, let e = try? GameEngine.showcase() { engine = e }
        else if let saves, saves.hasSave() { loadCurrent() }
    }

    var hasGame: Bool { engine != nil }
    var hasSavedGame: Bool { saves?.hasSave() ?? false }

    // MARK: Formatting (home currency)

    func money(_ v: Double) -> String { engine?.homeCurrency.display(v) ?? String(Int(v)) }
    func short(_ v: Double) -> String { (engine?.homeCurrency.short(v) ?? String(Int(v))).tidyMoney }
    func money(_ v: Double, in co: Company) -> String { engine?.currency(for: co).display(v) ?? String(Int(v)) }
    func short(_ v: Double, in co: Company) -> String { (engine?.currency(for: co).short(v) ?? String(Int(v))).tidyMoney }

    // MARK: Saving and loading

    func loadCurrent() {
        guard let saves else { return }
        do { try start(with: saves.load()) } catch { errorText = "The save could not be read: \(error)" }
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

    func newGame(name: String, countryCode: String) {
        do { engine = try GameEngine.newGame(countryCode: countryCode, playerName: name); tab = .home; save() } catch { errorText = "Could not start a game: \(error)" }
    }

    /// Import a save from the HTML game. The original text is kept in `Imports/` untouched.
    func importLegacy(text: String) {
        guard let saves else { return }
        do { try start(with: saves.importLegacy(text: text)); tab = .home; save(); show("Save imported. The original file is kept untouched.", tone: "good") }
        catch { errorText = "That save could not be imported: \(error)" }
    }

    func exportText() -> String? {
        guard let engine, let d = try? JSONEncoder().encode(engine.state) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    func quitToMenu() { save(); engine = nil }

    // MARK: Time

    func nextDay() {
        guard var e = engine, !isAdvancing else { return }
        let out = e.nextDay()
        engine = e
        if out.completedWeek { Haptics.weekDone() } else { Haptics.advanceDay() }
        report(out.newMessages)
        if out.completedWeek { save(backup: e.state.week % 4 == 0) } else { save() }
        if out.gameOver { Haptics.failure() }
    }

    /// Keep going until something needs a decision, in small steps so the screen stays alive.
    func untilNeeded(maxDays: Int = 26 * 7) {
        guard !isAdvancing, engine != nil else { return }
        isAdvancing = true; cancelAdvance = false
        Task { [weak self] in
            guard let self else { return }
            var reason: String?
            var n = 0
            while n < maxDays, !self.cancelAdvance, var e = self.engine, !e.state.isGameOver {
                let out = e.nextDay()
                self.engine = e
                n += 1
                if let m = out.newMessages.first(where: { $0.status == "open" || (!$0.isRead && $0.tone == "bad") }) { reason = m.title; break }
                if n % 3 == 0 { await Task.yield() }
            }
            self.isAdvancing = false
            self.save(backup: true)
            if let reason { Haptics.warning(); self.show("Stopped: \(reason)", tone: "warn") }
            else if self.engine?.state.isGameOver == true { Haptics.failure() }
            else if !self.cancelAdvance { Haptics.success() }
        }
    }

    func stopAdvancing() { cancelAdvance = true }

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

    func show(_ text: String, tone: String = "n") {
        let t = Toast(text: text, tone: tone)
        toast = t
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if self?.toast?.id == t.id { self?.toast = nil }
        }
    }

    // MARK: Navigation

    func go(_ action: Suggestion.Action) {
        Haptics.tap()
        switch action {
        case .openMessage(let id): openMessageID = id; tab = .inbox
        case .openCompany(let id): openCompanyID = id; tab = .companies
        case .openLoans: moneySection = .bank; tab = .money
        case .openInvest: moneySection = .invest; tab = .money
        case .openTax: moneySection = .taxes; tab = .money
        case .newCompany: showNewCompany = true; tab = .companies
        }
    }

    var unreadCount: Int { engine?.state.inbox.filter { !$0.isRead || $0.status == "open" }.count ?? 0 }
}

extension String {
    /// "£220 k" and "2\u{00A0}751" as the player should read them: "£220k", "2,751".
    var tidyMoney: String {
        var t = replacingOccurrences(of: "\u{00A0}", with: ",")
        for unit in ["k", "M", "bn"] { t = t.replacingOccurrences(of: " \(unit)", with: unit) }
        return t
    }
}
