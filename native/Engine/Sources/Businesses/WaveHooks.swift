import Foundation

/// The two places the item waves (`Wave2` ... `Wave11`) act on a company each week, so no wave edits the shared weekly code:
/// `weekly` (installs and refreshes real item records, writes no money) and `cogsFactor` (what the owner's item prices do to the
/// week's purchases, exactly 1 at default prices). Each wave adds one line to each function when it lands.
public enum WaveHooks {
    public static func weekly(_ s: inout GameState, _ i: Int, data: GameData) {
        Wave2.weekly(&s, i, data: data)
    }

    public static func cogsFactor(_ s: GameState, companyID: Int, data: GameData) -> Double {
        Wave2.cogsFactor(s, companyID: companyID, data: data)
    }
}
