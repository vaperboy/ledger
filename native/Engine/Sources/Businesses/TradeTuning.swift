import Foundation
import GameCore

public enum TradeTuning {
    public static var tunedTradeIDs: Set<String> {
        let t = bundled()
        return Set(t["trades"].object.keys).union(t["demandLevel"].object.keys).union(t["priceRetuned"].array.map { $0.string }).union(CityMarketTables.bundledTradeIDs)
    }

    public static func bundled() -> JSONValue {
        guard let url = Bundle.module.url(forResource: "trade_tuning", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return json
    }

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
