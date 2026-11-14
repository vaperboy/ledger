import SwiftUI
import Simulation

@MainActor
final class StreakModel: ObservableObject {
    static let shared = StreakModel()
    private static let key = "ledger.profile.loginStreak"

    @Published private(set) var streak: LoginStreak

    private init() {
        if let d = UserDefaults.standard.data(forKey: Self.key), let s = try? JSONDecoder().decode(LoginStreak.self, from: d) { streak = s } else { streak = LoginStreak() }
    }

    var openedToday: Bool { LoginStreakRules.openedToday(streak, today: GameStore.calendarDay()) }

    var line: String {
        guard streak.count > 0 else { return "" }
        let days: Int = LoginStreakRules.daysToBox(streak)
        return "Streak: day \(streak.count). Season box in \(days) \(days == 1 ? "day" : "days")."
    }

    func openToday() async -> LoginReward? {
        if StoreSession.shared.isServerBacked { return await openOnServer() }
        let out = LoginStreakRules.open(streak, today: GameStore.calendarDay())
        guard let reward = out.reward else { return nil }
        save(out.streak)
        StoreSession.shared.receiveDaily(boxes: reward.boxes, gold: reward.gold)
        return reward
    }

    /// The server counts the streak on its own days and pays the gold and box; the phone only shows it.
    private func openOnServer() async -> LoginReward? {
        guard let out = await StoreSession.shared.claimLoginDay() else { return nil }
        save(LoginStreak(count: out.count, best: out.best, lastDay: GameStore.calendarDay()))
        return out.opened ? LoginStreakRules.reward(day: out.count) : nil
    }

    private func save(_ s: LoginStreak) {
        streak = s
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: Self.key) }
    }
}
