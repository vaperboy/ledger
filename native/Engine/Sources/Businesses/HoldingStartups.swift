import Foundation
import GameCore

public enum HoldingStartups {
    public static func records(_ s: GameState, holdingID: Int) -> [JSONValue] {
        guard holdingID != 0 else { return [] }
        return (s.rest["startups"]?.array ?? []).filter { $0["hid"].int == holdingID }
    }
    public static func value(_ s: GameState, holdingID: Int) -> Double {
        records(s, holdingID: holdingID).filter { $0["st"].string == "live" }.reduce(0) { $0 + $1["val"].double * $1["pct"].double / 100 }
    }
}
