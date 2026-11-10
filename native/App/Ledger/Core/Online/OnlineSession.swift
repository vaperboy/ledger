import Foundation
import Observation
import UIKit
import GameCore
import Events
import Simulation
import Businesses

enum OnlineBackend {
    private static var standInOnly: Bool {
        ProcessInfo.processInfo.arguments.contains("-showcase") || NSClassFromString("XCTestCase") != nil
    }

    static func make() -> any OnlineService {
        guard OnlineConfig.useServer, !standInOnly, let url = OnlineConfig.projectURL else { return standIn }
        let tokens = SupabaseIdentityProvider(baseURL: url, apiKey: OnlineConfig.publishableKey)
        return SupabaseOnlineService(baseURL: url, apiKey: OnlineConfig.publishableKey, tokens: tokens)
    }

    static let standIn: MockOnlineService = MockOnlineService()

    static let shared: any OnlineService = make()
}

enum InviteLink {
    static let scheme = "ledger"
    static let host = "friend"

    static func normalised(_ raw: String) -> String? {
        let chars: [Character] = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard chars.count == 7 else { return nil }
        return String(chars[0..<3]) + "-" + String(chars[3..<7])
    }

    static func webURL(code: String) -> URL? {
        guard OnlineConfig.useServer, let base = OnlineConfig.projectURL, let c = normalised(code) else { return nil }
        var comps = URLComponents(url: base.appendingPathComponent("functions/v1/invite"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "c", value: c)]
        return comps?.url
    }

    static func message(code: String) -> String {
        let shown: String = normalised(code) ?? code
        if let link = webURL(code: shown) { return "Come and play Ledger with me. Open \(link.absoluteString) or add my friend code \(shown) in the app." }
        return "Come and play Ledger with me. Add my friend code \(shown) in the app."
    }

    static func code(from url: URL) -> String? {
        if url.scheme == scheme, url.host == host { return normalised(url.lastPathComponent) }
        if url.path.hasSuffix("/functions/v1/invite"), let c = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "c" })?.value {
            return normalised(c)
        }
        return nil
    }
}

enum AccountantHireIntent {
    struct Pick: Codable, Equatable {
        var officeID: String
        var offerID: Int
        var currency: String
        var known: [Int]
        var at: Date
    }

    private static let key = "ledger.online.accountantIntent"
    private static let lifetime: TimeInterval = 3 * 86_400

    static func choose(officeID: String, offerID: Int, currency: String, knownCompanies: [Int]) {
        let pick = Pick(officeID: officeID, offerID: offerID, currency: currency, known: knownCompanies, at: Date())
        if let data = try? JSONEncoder().encode(pick) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    static var current: Pick? {
        guard let data = UserDefaults.standard.data(forKey: key), let pick = try? JSONDecoder().decode(Pick.self, from: data) else { return nil }
        if Date().timeIntervalSince(pick.at) > lifetime { clear(); return nil }
        return pick
    }
}

@MainActor enum DeviceIdentity {
    private static let key = "ledger.online.deviceID"

    static var current: String {
        if let id = UIDevice.current.identifierForVendor?.uuidString { return id }
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let made: String = UUID().uuidString
        UserDefaults.standard.set(made, forKey: key)
        return made
    }
}

@MainActor @Observable
final class OnlineSession {
    enum State: Equatable { case guest, signedIn(SignInProvider?) }

    private(set) var state: State = .guest
    private(set) var offline = false
    private(set) var isLinking = false
    private(set) var pausedByPlayer = false
    private(set) var profile: PlayerProfile?
    private(set) var status: AccountStatus?
    private(set) var isAdmin = false
    private(set) var accountID: String?
    private(set) var linkReward: LinkRewardResult?
    private(set) var pulse: WorldPulse?
    private(set) var friendActivity: FriendActivity = .empty
    private(set) var pendingInvite: String?
    var problem: String?
    var notice: String?

    @ObservationIgnored let service: any OnlineService
    @ObservationIgnored private var deviceRegistered = false
    @ObservationIgnored private var sharedWeek: Int?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    private static let boards: any LeaderboardService = LeaderboardBackend.make()
    private static let adminKey = "ledger.online.adminAccounts"
    private static let inviteKey = "ledger.online.pendingInvite"

    init(service: any OnlineService = OnlineBackend.shared) {
        self.service = service
        pendingInvite = UserDefaults.standard.string(forKey: Self.inviteKey)
    }

    var isSignedIn: Bool { if case .signedIn = state { return true }; return false }
    var provider: SignInProvider? { if case .signedIn(let p) = state { return p }; return nil }
    var isLinked: Bool { provider != nil }
    var linkProviders: [SignInProvider] { OnlineConfig.linkProviders }
    var canLink: Bool { !isLinking && (isSignedIn ? !isLinked : !service.createsAccountsItself) }
    var awaitingAdultConfirmation: Bool { isSignedIn && status?.adultConfirmed == false }
    var linkRewardGold: Int { status?.linkRewardGold ?? 0 }

    func start() async {
        guard service.createsAccountsItself else { await connect(); return }
        scheduleReconnect(after: 0)
    }

    private func connect() async {
        guard !isSignedIn, !pausedByPlayer, Terms.accepted || !service.createsAccountsItself else { return }
        do {
            let account = try await service.startSession(createIfMissing: true)
            offline = false
            adopt(account)
            await finishSignIn()
        } catch OnlineError.offline {
            offline = true
        } catch {}
    }

    private func finishSignIn() async {
        await refreshStatus()
        if status?.adultConfirmed == true {
            profile = try? await service.myProfile()
            await collectLinkReward()
        } else if status?.adultConfirmed == false, !(await confirmAdult()) {
            problem = nil
        }
    }

    private func scheduleReconnect(after delay: UInt64 = 3) {
        guard reconnectTask == nil, service.createsAccountsItself, !isSignedIn else { return }
        reconnectTask = Task { [weak self] in
            var wait: UInt64 = delay
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
                guard let self, !self.isSignedIn, !self.pausedByPlayer else { break }
                await self.connect()
                if self.isSignedIn { break }
                wait = self.offline ? min(max(wait, 3) * 2, 120) : 3
            }
            self?.reconnectTask = nil
        }
    }

    private func adopt(_ account: OnlineAccount) {
        accountID = account.playerID
        state = .signedIn(account.provider)
        isAdmin = Self.rememberedAdmins().contains(account.playerID)
    }

    func resume() {
        pausedByPlayer = false
        scheduleReconnect(after: 0)
    }

    func refreshStatus() async {
        guard isSignedIn else { return }
        let s: AccountStatus
        do { s = try await service.accountStatus() } catch {
            if error as? OnlineError == .offline { offline = true }
            return
        }
        status = s
        setAdmin(s.isAdmin)
        await WorldRulesSync.refresh()
    }

    private static func rememberedAdmins() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: adminKey) ?? []) }

    private func setAdmin(_ on: Bool) {
        isAdmin = on
        guard let id = accountID else { return }
        var all: Set<String> = Self.rememberedAdmins()
        if on { all.insert(id) } else { all.remove(id) }
        UserDefaults.standard.set(Array(all), forKey: Self.adminKey)
    }

    @discardableResult
    func signIn(with provider: SignInProvider) async -> Bool {
        problem = nil
        notice = nil
        isLinking = true
        defer { isLinking = false }
        do {
            let account = try await service.signIn(with: provider)
            adopt(account)
            offline = false
            await finishSignIn()
            return true
        } catch OnlineError.cancelled {
            return false
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "Could not sign in. Try again."
            return false
        }
    }

    @discardableResult
    func confirmAdult() async -> Bool {
        problem = nil
        do {
            profile = try await service.createProfile(adultConfirmed: true)
            await refreshStatus()
            await collectLinkReward()
            return true
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "Could not create the profile. Try again."
            return false
        }
    }

    private func collectLinkReward() async {
        guard isLinked, let s = status, !s.linkRewardClaimed else { return }
        guard let r = try? await service.claimLinkReward() else { return }
        if r.granted { linkReward = r }
        await refreshStatus()
        await StoreSession.shared.load()
    }

    func dismissLinkReward() { linkReward = nil }

    func signOut() async {
        await service.signOut()
        pausedByPlayer = service.createsAccountsItself
        clearAccount()
    }

    private func clearAccount() {
        state = .guest
        profile = nil
        status = nil
        isAdmin = false
        accountID = nil
        linkReward = nil
        pulse = nil
        friendActivity = .empty
        deviceRegistered = false
        sharedWeek = nil
    }

    func redeemAdminCode(_ code: String) async -> AdminCodeResult? {
        problem = nil
        do {
            let r = try await service.redeemAdminCode(code)
            await refreshStatus()
            return r
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "Could not check the code. Try again."
            return nil
        }
    }

    func deleteAccount() async {
        problem = nil
        do {
            try await service.deleteAccount()
            pausedByPlayer = service.createsAccountsItself
            clearAccount()
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "Could not delete the account. Try again."
        }
    }

    func exportData() async -> URL? {
        problem = nil
        do {
            let data = try await service.exportMyData()
            let url: URL = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-my-data.json")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "Could not export your data."
            return nil
        }
    }

    func refreshProfile() async {
        guard isSignedIn, status?.adultConfirmed != false else { return }
        if let p = try? await service.myProfile() { profile = p }
    }

    func update(_ change: ProfileUpdate) async -> String? {
        do {
            profile = try await service.updateMyProfile(change)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "Could not save. Try again."
        }
    }

    func shareProgress(from engine: GameEngine?) async {
        guard isSignedIn, status?.adultConfirmed == true, let e = engine else { return }
        if profile == nil { await refreshProfile() }
        let week: Int = e.state.week
        let behind: Bool = week < (profile?.gameWeek ?? 0)
        var change = ProfileUpdate(badges: Self.badges(e))
        if !behind {
            change.companies = Self.companies(e)
            change.level = e.playerLevel.level
            change.gameWeek = week
        }
        _ = await update(change)
        guard let id = accountID else { return }
        await Self.boards.publish(e.leaderboardSubmission(playerID: id))
    }

    private static func badges(_ e: GameEngine) -> [String] {
        let names: [String] = TrophyList.unlocked(e).map { (t: Trophies.Entry) -> String in String(t.name.prefix(40)) }.filter { (n: String) -> Bool in !n.isEmpty }
        return Array(((e.inHallOfFame ? [HallOfFameBadge.name] : []) + names).prefix(64))
    }

    private static func companies(_ e: GameEngine) -> [OnlineCompany] {
        let week: Int = e.state.week
        return e.state.companies.filter { $0.status == .open }.prefix(12).map { (co: Company) -> OnlineCompany in
            let health: OnlineCompanyHealth
            if co.weeksNegative >= 4 { health = .struggling }
            else if let opened = co.openedWeek, week - opened < 8 { health = .new }
            else if co.reputation >= 70 { health = .thriving }
            else if co.reputation >= 55 { health = .growing }
            else { health = .steady }
            return OnlineCompany(id: "own.\(co.id)", name: co.name, trade: e.tradeName(co), city: e.cityName(co), countryCode: co.countryCode, health: health)
        }
    }

    func runPresence(store: GameStore) async {
        while !Task.isCancelled {
            await syncWorld(store: store)
            try? await Task.sleep(nanoseconds: 120 * 1_000_000_000)
        }
    }

    func syncWorld(store: GameStore) async {
        guard isSignedIn else { return }
        if status?.adultConfirmed != true { await finishSignIn() }
        guard status?.adultConfirmed == true else { return }
        if !deviceRegistered { deviceRegistered = (try? await service.registerDevice(DeviceIdentity.current)) != nil }
        do {
            pulse = try await service.heartbeat()
            offline = false
        } catch OnlineError.offline {
            offline = true
            return
        } catch OnlineError.notSignedIn {
            clearAccount()
            scheduleReconnect()
            return
        } catch {}
        await bookSettlements(store: store)
        await reconcileHire(store: store)
        if let e = store.engine, sharedWeek != e.state.week {
            sharedWeek = e.state.week
            await shareProgress(from: e)
        }
        if let a = try? await service.friendActivity() { friendActivity = a }
    }

    private func bookSettlements(store: GameStore) async {
        guard !store.isAdvancing, store.engine != nil, let rows = try? await service.pendingSettlements(), !rows.isEmpty else { return }
        let items: [OnlineSettlement] = rows.map { (r: OnlineSettlementRow) -> OnlineSettlement in
            OnlineSettlement(id: r.id, amount: r.amount, currency: r.currency, kind: r.kind, label: r.label, companyKey: r.meta?.companyKey,
                             units: r.meta?.units, unitPrice: r.meta?.unitPrice)
        }
        guard let done = store.act({ (e: inout GameEngine) -> [String] in e.bookOnlineSettlements(items) }) else { return }
        try? await service.acknowledgeSettlements(done)
    }

    private func reconcileHire(store: GameStore) async {
        guard let pick = AccountantHireIntent.current, let e = store.engine else { return }
        let fresh: [Company] = e.state.companies.filter { (c: Company) -> Bool in
            !pick.known.contains(c.id) && c.status.isLive && c.value("acc")["id"].int == pick.offerID
        }
        guard let company = fresh.min(by: { (a: Company, b: Company) -> Bool in a.id < b.id }) else { return }
        do {
            try await AccountantOfficeBackend.make().hire(officeID: pick.officeID, companyKey: "own.\(company.id)", currency: pick.currency)
            AccountantHireIntent.clear()
        } catch OnlineError.offline {
            return
        } catch {
            AccountantHireIntent.clear()
        }
    }

    @discardableResult
    func receive(url: URL) -> Bool {
        guard let code = InviteLink.code(from: url) else { return false }
        pendingInvite = code
        UserDefaults.standard.set(code, forKey: Self.inviteKey)
        return true
    }

    func dismissInvite() {
        pendingInvite = nil
        UserDefaults.standard.removeObject(forKey: Self.inviteKey)
    }
}
