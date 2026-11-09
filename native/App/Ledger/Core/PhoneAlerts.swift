import SwiftUI
import UserNotifications
import GameCore
import Simulation

/// One thing on the Phone that asks for the player: the app that
/// owns it carries a red bubble. Built from the engine by `PhoneAlerts`; no game rules here.
struct PhoneAlert: Identifiable, Equatable {
    var id: String
    /// The app that owns this alert.
    var app: PhoneApp
    /// Small caps source line ("Bank").
    var source: String
    var title: String
    var detail: String
    /// A company the alert is about (0 = none).
    var companyID: Int = 0
    /// A message to open in the Inbox, for an inbox alert (0 = none).
    var messageID: Int = 0
}

/// Reads the engine into Phone alerts and per-app bubble counts.
@MainActor
enum PhoneAlerts {
    /// Alerts, most urgent first: open decisions (bad news before the rest).
    static func all(engine: GameEngine, formatter store: GameStore) -> [PhoneAlert] {
        var out: [PhoneAlert] = []
        for w in engine.bigWeatherWarnings() {
            let names: String = w.companyIDs.compactMap { engine.state.company($0)?.name }.joined(separator: ", ")
            out.append(PhoneAlert(id: "weather-\(w.countryCode)", app: .weather, source: "Weather", title: w.title, detail: "Can hit: " + names, companyID: w.companyIDs.first ?? 0))
        }
        // Standing alerts are decisions of severity 3 or more; smaller open ones wait in the Inbox, and the desks' matters show under Handled.
        let open: [Message] = engine.ownerDecisions.filter { engine.severityLevel(of: $0) >= 3 }
        let bad: [Message] = open.filter { $0.tone == "bad" }
        let rest: [Message] = open.filter { $0.tone != "bad" }
        let ordered: [Message] = bad + rest
        for m in ordered.prefix(3) {
            let title: String = engine.displayText(m.title, companyID: m.companyID)
            let detail: String = m.companyID != 0 ? (engine.state.company(m.companyID)?.name ?? "") : ""
            out.append(PhoneAlert(id: "message-\(m.id)", app: .inbox, source: "Inbox", title: title, detail: detail, companyID: m.companyID, messageID: m.id))
        }
        return out
    }
}

/// The only three local notifications (planned by the engine's `SessionHooks`). Scheduled when the app goes to the
/// background, cancelled when it comes back, never repeating. The Settings toggle `Reminders` (default on) controls all three.
@MainActor
enum Reminders {
    private static let enabledKey: String = "remindersEnabled"
    private static let askedKey: String = "remindersAsked"
    private static let ids: [String] = ["ledger.expiry", "ledger.goal", "ledger.idle"]

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if !newValue { cancelAll() }
        }
    }

    /// The system permission prompt, once, after the first week report is dismissed. No custom pre-prompt.
    static func askOnce() {
        guard enabled, !UserDefaults.standard.bool(forKey: askedKey) else { return }
        UserDefaults.standard.set(true, forKey: askedKey)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func cancelAll() {
        let center: UNUserNotificationCenter = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    static func schedule(_ plans: [SessionHooks.Reminder]) {
        cancelAll()
        guard enabled else { return }
        let center: UNUserNotificationCenter = UNUserNotificationCenter.current()
        for p in plans {
            let content: UNMutableNotificationContent = UNMutableNotificationContent()
            content.title = p.title
            content.body = p.body
            content.sound = .default
            let trigger: UNTimeIntervalNotificationTrigger = UNTimeIntervalNotificationTrigger(timeInterval: p.after, repeats: false)
            center.add(UNNotificationRequest(identifier: p.id, content: content, trigger: trigger)) { _ in }
        }
    }
}
