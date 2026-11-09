import Foundation
import GameCore
import Finance

/// The administrators' world rules, as the app feeds them: a snapshot from the server (or a saved copy). The engine reads them for printing, the
/// limits on tax changes and price support, the price bands of the exchange, startup resale and venture stakes, and the electricity price band.
/// With nothing fed, every rule is at its default, so a game offline plays exactly as before.
public extension GameEngine {
    /// The rules in force (defaults where none were fed).
    var worldRules: WorldRules { state.worldRules }

    /// Feeds a snapshot: key to value (the server's `world_rules_snapshot`). Unknown keys are dropped and every value is held inside its hard limit.
    mutating func applyWorldRules(snapshot: [String: Double]) {
        let rules = WorldRules(snapshot: snapshot)
        update { s, _, _ in s.worldRules = rules }
    }

    /// Feeds the rules from anything that can answer for a key.
    mutating func applyWorldRules(from source: any WorldRulesSource) {
        let rules = WorldRules(source: source)
        update { s, _, _ in s.worldRules = rules }
    }

    /// The administrator accounts the server lists for the home country; creates the government if the game has none yet.
    mutating func setGovernmentAdmins(_ admins: Set<String>) {
        update { s, _, ctx in GovernmentBridge.ensureHome(&s, admins: admins, context: ctx) }
    }
}
