import SwiftUI
import UserNotifications
import GameCore
import Simulation

struct PhoneAlert: Identifiable, Equatable {
    var id: String
    var app: PhoneApp
    var source: String
    var title: String
    var detail: String
    var companyID: Int = 0
    var messageID: Int = 0
}

@MainActor
enum PhoneAlerts {
    static func all(engine: GameEngine, formatter store: GameStore) -> [PhoneAlert] {
        var out: [PhoneAlert] = []
        for w in engine.bigWeatherWarnings() {
            let names: String = w.companyIDs.compactMap { engine.state.company($0)?.name }.joined(separator: ", ")
            out.append(PhoneAlert(id: "weather-\(w.countryCode)", app: .news, source: "Weather", title: w.title, detail: "Can hit: " + names, companyID: w.companyIDs.first ?? 0))
        }
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

@MainActor
enum Reminders {
    private static let enabledKey: String = "remindersEnabled"
    private static let askedKey: String = "remindersAsked"
    private static let ids: [String] = ["ledger.expiry", "ledger.goal", "ledger.idle", "ledger.jv.urgent", "ledger.jv.planned"]

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if !newValue { cancelAll() }
        }
    }

    static func askOnce() {
        guard enabled, !UserDefaults.standard.bool(forKey: askedKey) else { return }
        UserDefaults.standard.set(true, forKey: askedKey)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted { DispatchQueue.main.async { PushAlerts.registerIfAllowed() } }
        }
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
