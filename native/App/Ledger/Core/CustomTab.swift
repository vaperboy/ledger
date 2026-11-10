import SwiftUI
import GameCore
import Simulation

/// Where the player's Custom tab goes: a Phone app (Store, Market, Bank, Inbox, Reports, AirStay ...) or one company's page.
/// Kept per install in UserDefaults under "customTab" (JSON); the Inbox until the player picks another.
enum CustomTabTarget: Codable, Hashable {
    case app(PhoneApp)
    case company(Int)

    static let defaultsKey = "customTab"

    static let standard: CustomTabTarget = .app(.inbox)

    /// Every Phone app the Custom tab can show. Ventures is its own tab, so it is not offered.
    static var apps: [PhoneApp] { PhoneApp.launcher.filter { $0 != .ventures } }

    /// The stored choice; a missing, unreadable or retired value gives the standard one.
    static func stored() -> CustomTabTarget {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return standard }
        guard let t = try? JSONDecoder().decode(CustomTabTarget.self, from: data) else { return standard }
        if case .app(let app) = t, !apps.contains(app) { return standard }
        return t
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: CustomTabTarget.defaultsKey)
    }
}

extension GameStore {
    /// The title shown for a tab: fixed, except the Custom tab, which takes its destination's.
    func title(for tab: AppTab) -> String { tab == .custom ? customTitle : tab.title }
    /// The icon shown for a tab: fixed, except the Custom tab, which takes its destination's.
    func glyph(for tab: AppTab) -> String { tab == .custom ? customGlyph : tab.glyph }

    var customTitle: String {
        switch customTarget {
        case .app(let app): return app.title
        case .company(let id): return engine?.state.company(id)?.name ?? "Company"
        }
    }

    var customGlyph: String {
        switch customTarget {
        case .app(let app): return app.glyph
        case .company: return Glyph.home
        }
    }

    /// The player picked a destination: it is stored and the Custom tab starts on it. The selected tab stays (only the tab bar changes
    /// it): on the Custom tab its root shows the new destination.
    func chooseCustom(_ target: CustomTabTarget) {
        customTarget = target
        target.save()
        customPickerOpen = false
        if tab == .custom { popToRoot(.custom) }
    }
}
