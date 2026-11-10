import Foundation
import GameCore

enum CountryEvents {
    enum Eff { case dem(Double), cost(Double, Double), cap(Double, Double) }
    struct Item { let cc: String, head: String, text: String, fx: [String: Eff]; var wage: Double = 0; var rate: Double = 0 }

    private static let file: JSONValue = {
        guard let url = Bundle.module.url(forResource: "country_events", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return json
    }()

    static let table: [Item] = file["events"].array.map { e in
        var fx: [String: Eff] = [:]
        for (k, v) in e["fx"].object {
            let a = v.array
            switch a.first?.string {
            case "dem": fx[k] = .dem(a[1].double)
            case "cost": fx[k] = .cost(a[1].double, a[2].double)
            case "cap": fx[k] = .cap(a[1].double, a[2].double)
            default: break
            }
        }
        return Item(cc: e["cc"].string, head: e["head"].string, text: e["text"].string, fx: fx, wage: e["wage"].double, rate: e["rate"].double)
    }

    static func country(ofDecision id: String) -> String { file["decisionCountry"][id].string }
}
