import Foundation
import GameCore

public enum GroupStakes {
    public static func profit(_ g: JSONValue, _ s: GameState) -> Double { g["rev"].double * g["m"].double - g["debt"].double * (s.economy.policyRate + 0.025) }
    public static func value(of g: JSONValue, _ s: GameState) -> Double {
        let mult: Double = g["strat"].string == "premium" ? 11 : g["strat"].string == "cautious" ? 10 : 8
        return max(0, profit(g, s) * mult + g["cash"].double - g["debt"].double * 0.5)
    }
    public static func group(_ s: GameState, id: String) -> JSONValue? {
        guard let g = s.rest["g27"]?["g"][id], !g.isNull else { return nil }
        return g
    }
    public static func groups(_ s: GameState, country cc: String) -> [JSONValue] {
        (s.rest["g27"]?["g"].object ?? [:]).sorted { $0.key < $1.key }.map { $0.value }.filter { !$0["gone"].bool && $0["cs"].array.contains { $0.string == cc } }
    }
    public static func stakesValue(_ s: GameState) -> Double {
        (s.rest["st27"]?.array ?? []).reduce(0) { t, st in
            guard let g = group(s, id: st["g"].string), !g["gone"].bool else { return t }
            return t + value(of: g, s) * st["pct"].double
        }
    }
}
