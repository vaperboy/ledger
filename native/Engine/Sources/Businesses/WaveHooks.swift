import Foundation
import GameCore

/// The two places the item waves (`Wave2` ... `Wave11`) act on a company each week, so no wave edits the shared weekly code:
/// `weekly` (installs and refreshes real item records, writes no money) and `cogsFactor` (what the owner's item prices do to the
/// week's purchases, exactly 1 at default prices). Each wave adds one line to each function when it lands.
public enum WaveHooks {
    public static func weekly(_ s: inout GameState, _ i: Int, data: GameData) {
        Wave2.weekly(&s, i, data: data)
        let co = s.companies[i]
        if co.status == .open, ItemWaves.w3.contains(co.type) { _ = Wave3Recipes.apply(&s, companyID: co.id, data: data, trades: ItemWaves.w3) }
    }

    public static func cogsFactor(_ s: GameState, companyID: Int, data: GameData) -> Double {
        Wave2.cogsFactor(s, companyID: companyID, data: data)
    }
}
