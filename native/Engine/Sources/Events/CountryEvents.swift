import Foundation
import GameCore

/// The country-specific news items ("The pound swings") and which country each hand-written country decision belongs to, as data
/// (`Resources/country_events.json`).
///
/// ```
/// { "decisionCountry": { "UK_rent": "UK" },
///   "events": [ { "cc": "UK", "head": "...", "text": "...",
///                 "fx": { "retail": ["cost", 1.03, 26], "prod": ["dem", 1.03], "logi": ["cap", 0.8, 2] },   // trade, family or "all"
///                 "wage": 1.03, "rate": 0.015 } ] }            // optional: wage factor, loan margin added
/// ```
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

    /// The country a hand-written country decision (by its id without the "c_" prefix) is for.
    static func country(ofDecision id: String) -> String { file["decisionCountry"][id].string }
}
