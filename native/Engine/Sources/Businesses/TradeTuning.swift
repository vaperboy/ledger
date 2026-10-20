import Foundation
import GameCore

/// Balance corrections kept apart from the big data files (`Resources/trade_tuning.json`), so that a pass over the
/// economics of the trades is one small, reviewable file. Each entry says what it changes and why (real-world basis in
/// docs/BALANCE_REPORT.md).
///
/// ```
/// { "trades": { "airline": { "ticket": 250000, "eq": { "plane": { "cost": 150000000 } }, "tw": { "fuel": 0.25 } } },
///   "demandLevel": { "grocery": 1.6 } }
/// ```
/// * `trades.<id>.<key>`: the key of the trade's data entry is replaced (`eq` and `tw` are merged item by item).
/// * `demandLevel.<id>`: replaces the trade's demand level in `balance.json`.
public enum TradeTuning {
    /// Trades whose numbers deliberately differ from the original game's (parity tests skip them).
    public static var tunedTradeIDs: Set<String> {
        let t = bundled()
        return Set(t["trades"].object.keys).union(t["demandLevel"].object.keys)
    }

    public static func bundled() -> JSONValue {
        guard let url = Bundle.module.url(forResource: "trade_tuning", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return json
    }

    /// The trades' data with the tuning applied.
    static func apply(to trades: JSONValue, tuning: JSONValue) -> JSONValue {
        var out = trades
        for (id, patch) in tuning["trades"].object {
            var t = out["trades"][id]
            if t.isNull { continue }
            for (key, value) in patch.object {
                switch key {
                case "eq":
                    var list = t["eq"].array
                    for (eqID, fields) in value.object {
                        guard let i = list.firstIndex(where: { $0["id"].string == eqID }) else { continue }
                        for (f, v) in fields.object { list[i][f] = v }
                    }
                    t["eq"] = .array(list)
                case "tw":
                    var tw = t["tw"]
                    for (f, v) in value.object { tw[f] = v }
                    t["tw"] = tw
                default:
                    t[key] = value
                }
            }
            out["trades"][id] = t
        }
        return out
    }
}
