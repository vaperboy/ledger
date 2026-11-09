import SwiftUI
import GameCore
import Businesses
import Simulation

extension Gate {
    /// What opens the gate, as a plain goal for the player (no raw rule numbers); falls back to the engine's own line.
    var goalLine: String {
        switch self {
        case .hiring: return "Keep running your first company for a few weeks"
        case .marketing, .reviews: return "Hire your first employee"
        case .ownerMoney: return "Make your first decision"
        case .bank, .newCompany, .management, .accounting, .techpro: return "Make your first profitable month"
        case .insurance, .weather, .atlas: return "Make your first profitable month or take your first loss"
        case .suppliers, .marketplace: return "Finish your first week of sales"
        case .property, .rivals, .airstay: return "Own two companies"
        case .group: return "Own three companies"
        case .ventures, .venturesFeed: return "Run the group at a profit for two years"
        case .luxury: return "Become rich"
        case .ownerHours: return ""
        }
    }
}

extension AppTab {
    /// The gate that keeps a tab shut; Home, Phone and the Custom tab are always open.
    var gate: Gate? {
        switch self {
        case .group: return .group
        case .projects: return .ventures
        case .company, .custom, .phone: return nil
        }
    }
}

extension GameStore {
    /// True while the tab's gate is closed. A game without the ladder, and no game at all, has nothing locked.
    func isLocked(_ tab: AppTab) -> Bool {
        guard let g = tab.gate else { return false }
        return !gateOpen(g)
    }

    /// True while the Phone app's gate is closed.
    func isLocked(_ app: PhoneApp) -> Bool {
        guard let g = app.gate else { return false }
        return !gateOpen(g)
    }

    /// Progress towards a gate in words ("2 of 3 companies"), or "" when the roadmap has none.
    func gateProgress(_ g: Gate) -> String {
        guard let e = engine else { return "" }
        return e.unlockRoadmap().first { (r: UnlockRoadmapItem) -> Bool in r.id == "gate." + g.rawValue }?.detail ?? ""
    }

    /// Drops a stored Custom tab choice that points at an app the player has not unlocked (a new game on an install that remembers an
    /// older choice); the tab then asks again.
    func validateCustomTarget() {
        guard engine != nil, let target = customTarget, case .app(let app) = target, isLocked(app) else { return }
        customTarget = nil
        CustomTabTarget.clearStored()
    }
}

/// The centre popup a locked tab opens: what it waits for, as a goal.
struct TabLockPopup: View {
    @EnvironmentObject var store: GameStore
    var tab: AppTab
    var onClose: () -> Void

    var body: some View {
        let gate: Gate? = tab.gate
        let title: String = store.title(for: tab)
        let progress: String = gate.map { (g: Gate) -> String in store.gateProgress(g) } ?? ""
        GamePopup(title: "\(title) is locked", category: .compact, tone: .info, icon: "lock.fill", onClose: onClose) {
            PopupBody {
                Text("Goal: " + (gate?.goalLine ?? "")).popupText(.body)
                if !progress.isEmpty { Text(progress).popupText(.caption) }
                PopupOptionButton(title: "OK", highlighted: true, identifier: "tab-lock-ok", action: onClose)
            }
        }
        .accessibilityIdentifier("tab-lock-popup")
    }
}

/// A small lock drawn over a grayed tab or app.
struct LockBadge: View {
    var size: CGFloat = 12
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Theme.inkSoft)
            .accessibilityHidden(true)
    }
}
