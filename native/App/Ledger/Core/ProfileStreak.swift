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

    func openToday() -> LoginReward? {
        let out = LoginStreakRules.open(streak, today: GameStore.calendarDay())
        guard let reward = out.reward else { return nil }
        streak = out.streak
        if let d = try? JSONEncoder().encode(out.streak) { UserDefaults.standard.set(d, forKey: Self.key) }
        StoreSession.shared.receiveDaily(boxes: reward.boxes, gold: reward.gold)
        return reward
    }
}
