import SwiftUI
import GameCore
import Simulation

/// Where the player's Custom tab goes: a Phone app (Bank, Market, Inbox, Stats, Goals, Reports, AirStay ...) or one company's page.
/// Kept per install in UserDefaults under "customTab" (JSON); nil until the player picks one (the tab then reads "Pick tab").
enum CustomTabTarget: Codable, Hashable {
    case app(PhoneApp)
    case company(Int)

    static let defaultsKey = "customTab"

    /// Every Phone app the Custom tab can show. Ventures is its own tab, so it is not offered.
    static var apps: [PhoneApp] { PhoneApp.allCases.filter { $0 != .ventures } }

    /// The stored choice; a missing, unreadable or retired value gives nil (not picked yet).
    static func stored() -> CustomTabTarget? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        guard let t = try? JSONDecoder().decode(CustomTabTarget.self, from: data) else { return nil }
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
        guard let target = customTarget else { return "Pick tab" }
        switch target {
        case .app(let app): return app.title
        case .company(let id): return engine?.state.company(id)?.name ?? "Company"
        }
    }

    var customGlyph: String {
        guard let target = customTarget else { return Glyph.hire }
        switch target {
        case .app(let app): return app.glyph
        case .company: return Glyph.home
        }
    }

    /// The player picked a destination: it is stored and the Custom tab starts on it. The selected tab stays (only the tab bar changes
    /// it): on the Custom tab its root shows the new destination, elsewhere a toast says where it went.
    func chooseCustom(_ target: CustomTabTarget) {
        customTarget = target
        target.save()
        customPickerOpen = false
        if tab == .custom { popToRoot(.custom) } else { show("\(title(for: .custom)) is now on your Custom tab", tone: "good") }
    }
}
