import SwiftUI
import GameCore
import Simulation

enum CustomTabTarget: Codable, Hashable {
    case app(PhoneApp)
    case company(Int)

    static let defaultsKey = "customTab"

    static let standard: CustomTabTarget = .app(.inbox)

    static var apps: [PhoneApp] { PhoneApp.launcher.filter { $0 != .season && $0 != .profile } }

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
    func title(for tab: AppTab) -> String { tab == .custom ? customTitle : tab.title }
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

    func chooseCustom(_ target: CustomTabTarget) {
        customTarget = target
        target.save()
        customPickerOpen = false
        if tab == .custom { popToRoot(.custom) }
    }
}
