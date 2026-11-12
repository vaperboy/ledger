import SwiftUI
import UIKit
import UserNotifications

enum PushCategory: String, CaseIterable, Identifiable {
    case auction, supplier, gift, race, daily, board

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auction: return "Auctions"
        case .supplier: return "Supplier requests"
        case .gift: return "Friend gifts"
        case .race: return "Weekly race result"
        case .daily: return "Daily reward ready"
        case .board: return "Board votes and offers"
        }
    }

    var detail: String {
        switch self {
        case .auction: return "When you are outbid or win"
        case .supplier: return "When a buyer signs up for your supply"
        case .gift: return "When a friend sends you a piece"
        case .race: return "When the friend race week closes"
        case .daily: return "When your daily reward is waiting"
        case .board: return "When a co-owner calls an emergency vote or makes you an offer"
        }
    }
}

protocol PushService: Sendable {
    func registerPushToken(_ payload: PushTokenPayload) async throws
}

extension PushService {
    func registerPushToken(_ payload: PushTokenPayload) async throws {}
}

struct PushTokenPayload: Equatable, Sendable {
    var token: String
    var environment: String
    var categories: [String]

    init(deviceToken: Data, environment: String, categories: [PushCategory]) {
        self.token = deviceToken.map { (b: UInt8) -> String in String(format: "%02x", b) }.joined()
        self.environment = environment
        self.categories = categories.map { (c: PushCategory) -> String in c.rawValue }
    }

    init(token: String, environment: String, categories: [PushCategory]) {
        self.token = token
        self.environment = environment
        self.categories = categories.map { (c: PushCategory) -> String in c.rawValue }
    }

    var rpcParams: [String: Any] {
        ["p_token": token, "p_environment": environment, "p_categories": categories]
    }
}

@MainActor
enum PushAlerts {
    static let tokenArrived: Notification.Name = Notification.Name("ledger.pushTokenArrived")
    private static let tokenKey: String = "pushToken"

    static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    static func enabled(_ c: PushCategory) -> Bool { UserDefaults.standard.object(forKey: "push." + c.rawValue) as? Bool ?? true }

    static func setEnabled(_ c: PushCategory, _ on: Bool) { UserDefaults.standard.set(on, forKey: "push." + c.rawValue) }

    static var enabledCategories: [PushCategory] { PushCategory.allCases.filter { (c: PushCategory) -> Bool in enabled(c) } }

    static func registerIfAllowed() {
        UNUserNotificationCenter.current().getNotificationSettings { (s: UNNotificationSettings) in
            guard s.authorizationStatus == .authorized || s.authorizationStatus == .provisional else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    static func received(_ deviceToken: Data) {
        let hex: String = PushTokenPayload(deviceToken: deviceToken, environment: environment, categories: []).token
        UserDefaults.standard.set(hex, forKey: tokenKey)
        NotificationCenter.default.post(name: tokenArrived, object: nil)
    }

    static func payload() -> PushTokenPayload? {
        guard let t = UserDefaults.standard.string(forKey: tokenKey), !t.isEmpty else { return nil }
        return PushTokenPayload(token: t, environment: environment, categories: enabledCategories)
    }

    static func sync(service: any PushService, signedIn: Bool) async {
        guard signedIn, let p = payload() else { return }
        try? await service.registerPushToken(p)
    }
}

final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushAlerts.received(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}
}

extension SupabaseOnlineService {
    func registerPushToken(_ payload: PushTokenPayload) async throws {
        _ = try await rpcData("register_push_token", payload.rpcParams)
    }
}
