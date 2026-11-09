import Foundation
import Observation
import GameCore
import Simulation

/// Which service the app talks to. A real server replaces the mock by returning its implementation here; nothing else changes.
enum OnlineBackend {
    /// The offline stand-in unless `OnlineConfig.useServer` is on, so launch makes no network calls by default.
    static func make() -> any OnlineService {
        guard OnlineConfig.useServer, let url = OnlineConfig.projectURL else { return MockOnlineService() }
        return SupabaseOnlineService(baseURL: url, apiKey: OnlineConfig.publishableKey, tokens: UnavailableIdentityTokenProvider())
    }

    /// The one instance the session, the boards and the offices share, so only one place ever refreshes the sign-in token.
    static let shared: any OnlineService = make()
}

/// The player's online state for the views: guest, signing in or signed in, with their own profile. Injected with `.environment(online)`.
/// Everything here is optional to the game: a guest or a failed call changes nothing about single-player.
@MainActor @Observable
final class OnlineSession {
    enum State: Equatable { case guest, signingIn, signedIn(SignInProvider) }

    /// Which side keeps its progress when a device's game meets an account that already has some.
    enum ProgressChoice: String { case device, account }
    struct MergePrompt: Equatable { var accountWeek: Int; var deviceWeek: Int }

    private(set) var state: State = .guest
    private(set) var profile: PlayerProfile?
    /// What the server last said about this account (nil before it answered, or for a guest).
    private(set) var status: AccountStatus?
    /// The server's answer to "is this account an administrator", remembered per account so the entry shows offline. It is only ever set
    /// from that answer, and the server checks the account again on every Admin call.
    private(set) var isAdmin = false
    private(set) var accountID: String?
    /// The link reward the server just paid, shown once.
    private(set) var linkReward: LinkRewardResult?
    /// Set when this device's game and the account's saved progress disagree and the player has not chosen yet.
    private(set) var mergePrompt: MergePrompt?
    private(set) var progressChoice: ProgressChoice?
    /// One plain line for the screen that started the last call; cleared by the next call.
    var problem: String?
    /// A calm note (not an error), such as "No profile was created".
    var notice: String?
    /// The account screen is shown once on a new install, before the start screen.
    private(set) var needsAccountScreen: Bool

    @ObservationIgnored let service: any OnlineService
    private static let seenKey = "ledger.online.accountScreenSeen"
    private static let adminKey = "ledger.online.adminAccounts"
    private static func choiceKey(_ id: String) -> String { "ledger.online.progressChoice." + id }

    init(service: any OnlineService = OnlineBackend.shared) {
        self.service = service
        needsAccountScreen = !UserDefaults.standard.bool(forKey: Self.seenKey)
    }

    var isSignedIn: Bool { if case .signedIn = state { return true }; return false }
    var provider: SignInProvider? { if case .signedIn(let p) = state { return p }; return nil }
    /// Signed in, but the profile waits for the 18+ confirmation.
    var awaitingAdultConfirmation: Bool { isSignedIn && status?.adultConfirmed == false }
    /// What linking pays, once the server has said so.
    var linkRewardGold: Int { status?.linkRewardGold ?? 0 }

    /// Restores a saved account at launch.
    func start() async {
        guard let account = await service.currentAccount() else { return }
        adopt(account)
        await refreshStatus()
        if status?.adultConfirmed == true { profile = try? await service.myProfile() }
    }

    func finishAccountScreen() {
        needsAccountScreen = false
        UserDefaults.standard.set(true, forKey: Self.seenKey)
    }

    func continueAsGuest() { finishAccountScreen() }

    private func adopt(_ account: OnlineAccount) {
        accountID = account.playerID
        state = .signedIn(account.provider)
        isAdmin = Self.rememberedAdmins().contains(account.playerID)
        progressChoice = UserDefaults.standard.string(forKey: Self.choiceKey(account.playerID)).flatMap { ProgressChoice(rawValue: $0) }
    }

    /// Asks the server about this account and keeps its answer, the administrator answer included.
    func refreshStatus() async {
        guard isSignedIn, let s = try? await service.accountStatus() else { return }
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

    /// Signs in (or links, for a guest who adds an account later). Returns whether it worked. A new account has no profile yet: the
    /// 18+ confirmation comes first (`awaitingAdultConfirmation`); a returning one gets its profile back and, if never paid, the reward.
    @discardableResult
    func signIn(with provider: SignInProvider) async -> Bool {
        problem = nil
        notice = nil
        let before: State = state
        state = .signingIn
        do {
            let account = try await service.signIn(with: provider)
            adopt(account)
            finishAccountScreen()
            await refreshStatus()
            if status?.adultConfirmed == true {
                profile = try? await service.myProfile()
                await collectLinkReward()
            }
            return true
        } catch {
            state = before
            problem = (error as? LocalizedError)?.errorDescription ?? "Could not sign in. Try again."
            return false
        }
    }

    /// The player confirmed they are 18 or older: the server creates the profile and the reward follows.
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

    /// The player is under 18, or does not want a profile: the empty account is removed again and they carry on as a guest.
    func declineProfile() async {
        problem = nil
        do {
            try await service.deleteAccount()
            clearAccount()
            notice = "No profile was created. You can keep playing as a guest."
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "Could not remove the account. Try again."
        }
    }

    private func collectLinkReward() async {
        guard let s = status, !s.linkRewardClaimed else { return }
        guard let r = try? await service.claimLinkReward() else { return }
        if r.granted { linkReward = r }
        await refreshStatus()
        await StoreSession.shared.load()
    }

    func dismissLinkReward() { linkReward = nil }

    func signOut() async {
        await service.signOut()
        clearAccount()
    }

    private func clearAccount() {
        state = .guest
        profile = nil
        status = nil
        isAdmin = false
        accountID = nil
        linkReward = nil
        mergePrompt = nil
        progressChoice = nil
    }

    /// Spends an administrator code. The server decides; on success the account's status is read again.
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

    /// Deletes the account and everything online. The saved game on this device is not touched.
    func deleteAccount() async {
        problem = nil
        do {
            try await service.deleteAccount()
            clearAccount()
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "Could not delete the account. Try again."
        }
    }

    /// The player's data as a JSON file in the temporary folder, ready to share; nil on failure.
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

    /// Saves a change to the own profile. Returns nil on success, otherwise the reason in one line.
    func update(_ change: ProfileUpdate) async -> String? {
        do {
            profile = try await service.updateMyProfile(change)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "Could not save. Try again."
        }
    }

    /// The player's answer when the account already holds more progress than this device's game.
    func resolveMerge(_ choice: ProgressChoice, engine: GameEngine?) async {
        progressChoice = choice
        mergePrompt = nil
        if let id = accountID { UserDefaults.standard.set(choice.rawValue, forKey: Self.choiceKey(id)) }
        if choice == .device { await shareProgress(from: engine) }
    }

    /// Sends the running game's companies, level and week to the own profile (quietly; nothing to do for a guest, before the profile exists,
    /// or when it fails). When the account already holds clearly more progress, nothing is sent until the player has chosen which side stays.
    func shareProgress(from engine: GameEngine?) async {
        guard isSignedIn, status?.adultConfirmed == true, let e = engine else { return }
        let week: Int = e.state.week
        if let held = profile?.gameWeek, held > week + 4, progressChoice != .device {
            if progressChoice == nil { mergePrompt = MergePrompt(accountWeek: held, deviceWeek: week) }
            return
        }
        let companies: [OnlineCompany] = e.state.companies.filter { $0.status == .open && $0.type != "hold" }.prefix(12).map { (co) -> OnlineCompany in
            let health: OnlineCompanyHealth
            if co.weeksNegative >= 4 { health = .struggling }
            else if let opened = co.openedWeek, week - opened < 8 { health = .new }
            else if co.reputation >= 70 { health = .thriving }
            else if co.reputation >= 55 { health = .growing }
            else { health = .steady }
            return OnlineCompany(id: "own.\(co.id)", name: co.name, trade: e.tradeName(co), city: e.cityName(co), countryCode: co.countryCode, health: health)
        }
        _ = await update(ProfileUpdate(companies: companies, level: 1 + week / 14, gameWeek: week))
    }
}
