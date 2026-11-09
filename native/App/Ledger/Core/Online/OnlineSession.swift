import Foundation
import Observation
import GameCore
import Simulation

/// Which service the app talks to. A real server replaces the mock by returning its implementation here; nothing else changes.
enum OnlineBackend {
    /// The real server's address. Nil while only the stand-in exists; the same in debug and release builds.
    static let serverURL: URL? = nil

    static func make() -> any OnlineService { MockOnlineService() }
}

/// The player's online state for the views: guest, signing in or signed in, with their own profile. Injected with `.environment(online)`.
/// Everything here is optional to the game: a guest or a failed call changes nothing about single-player.
@MainActor @Observable
final class OnlineSession {
    enum State: Equatable { case guest, signingIn, signedIn(SignInProvider) }

    private(set) var state: State = .guest
    private(set) var profile: PlayerProfile?
    /// One plain line for the screen that started the last call; cleared by the next call.
    var problem: String?
    /// The account screen is shown once on a new install, before the start screen.
    private(set) var needsAccountScreen: Bool

    @ObservationIgnored let service: any OnlineService
    private static let seenKey = "ledger.online.accountScreenSeen"

    init(service: any OnlineService = OnlineBackend.make()) {
        self.service = service
        needsAccountScreen = !UserDefaults.standard.bool(forKey: Self.seenKey)
    }

    var isSignedIn: Bool { if case .signedIn = state { return true }; return false }
    var provider: SignInProvider? { if case .signedIn(let p) = state { return p }; return nil }

    /// Restores a saved account at launch.
    func start() async {
        guard let account = await service.currentAccount() else { return }
        state = .signedIn(account.provider)
        profile = try? await service.myProfile()
    }

    func finishAccountScreen() {
        needsAccountScreen = false
        UserDefaults.standard.set(true, forKey: Self.seenKey)
    }

    func continueAsGuest() { finishAccountScreen() }

    /// Signs in (or links, for a guest who adds an account later). Returns whether it worked.
    @discardableResult
    func signIn(with provider: SignInProvider) async -> Bool {
        problem = nil
        let before: State = state
        state = .signingIn
        do {
            let account = try await service.signIn(with: provider)
            state = .signedIn(account.provider)
            profile = try? await service.myProfile()
            finishAccountScreen()
            return true
        } catch {
            state = before
            problem = (error as? LocalizedError)?.errorDescription ?? "Could not sign in. Try again."
            return false
        }
    }

    func signOut() async {
        await service.signOut()
        state = .guest
        profile = nil
    }

    /// Deletes the account and everything online. The saved game on this device is not touched.
    func deleteAccount() async {
        problem = nil
        do {
            try await service.deleteAccount()
            state = .guest
            profile = nil
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
        guard isSignedIn else { return }
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

    /// Sends the running game's companies, level and week to the own profile (quietly; nothing to do for a guest or when it fails).
    func shareProgress(from engine: GameEngine?) async {
        guard isSignedIn, let e = engine else { return }
        let week: Int = e.state.week
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
