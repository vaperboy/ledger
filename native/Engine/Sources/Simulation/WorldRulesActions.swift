import Foundation
import GameCore
import Finance

public extension GameEngine {
    var worldRules: WorldRules { state.worldRules }

    mutating func applyWorldRules(snapshot: [String: Double]) {
        let rules = WorldRules(snapshot: snapshot)
        update { s, _, _ in s.worldRules = rules }
    }

    mutating func applyWorldRules(from source: any WorldRulesSource) {
        let rules = WorldRules(source: source)
        update { s, _, _ in s.worldRules = rules }
    }

    mutating func setGovernmentAdmins(_ admins: Set<String>) {
        update { s, _, ctx in GovernmentBridge.ensureHome(&s, admins: admins, context: ctx) }
    }
}
