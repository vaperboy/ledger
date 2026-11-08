import Foundation
import GameCore

/// Shares a holding company owns in other founders' startups. They are `rest["startups"]` records with `hid` = the holding's id, so the startup
/// rounds, bridges and exits run on them like on the player's own; money goes to and from the holding's cash. The player's net worth counts them
/// inside the holding (`HoldingModel.refreshAssets`), never a second time as personal startup shares (`Valuation.netWorth`).
public enum HoldingStartups {
    public static func records(_ s: GameState, holdingID: Int) -> [JSONValue] {
        guard holdingID != 0 else { return [] }
        return (s.rest["startups"]?.array ?? []).filter { $0["hid"].int == holdingID }
    }
    /// What the holding's live startup shares are worth, by the startups' latest valuation.
    public static func value(_ s: GameState, holdingID: Int) -> Double {
        records(s, holdingID: holdingID).filter { $0["st"].string == "live" }.reduce(0) { $0 + $1["val"].double * $1["pct"].double / 100 }
    }
}
