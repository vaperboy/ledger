import Foundation
import GameCore
import Countries

/// Names for the places AirStay lists: a street address and a district in the style of the country ("14 Hansen Street, Fjordvik", "Müllerstraße 9,
/// Lindenau", "Calle García 22, Costavera"), built from the country's own surnames and name endings. Deterministic per listing (the same listing
/// always has the same name and the same picture slot), different for every listing. The listing's tier name ("Back street unit") stays as it was:
/// other rules read it.
enum PlaceNames {
    /// How a country writes its streets (data: `street_styles.json`); anything not listed uses the English style.
    private static let styles: JSONValue = {
        guard let url = Bundle.module.url(forResource: "street_styles", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return json
    }()

    static func styleOf(_ countryCode: String) -> String { styles[countryCode].string }

    private static func pick(_ a: [String], _ r: inout HashedRandom) -> String {
        a.isEmpty ? "" : a[min(a.count - 1, Int(r.next() * Double(a.count)))]
    }

    /// A district: a local root plus a local ending ("Fjordvik", "Skogholm").
    static func district(_ country: Country, _ r: inout HashedRandom) -> String {
        let starts = country.companyNameStarts.isEmpty ? ["Nova"] : country.companyNameStarts
        let ends = country.pack["names"]["coinEnd"].array.map { $0.string }
        var root = pick(starts, &r).filter { $0.isLetter }
        if root.count > 6 { root = String(root.prefix(5)) }
        var tail = pick(ends.isEmpty ? ["ton", "field", "ham", "ford"] : ends, &r)
        if let l = root.last?.lowercased(), let f = tail.first?.lowercased(), l == f { tail.removeFirst() }
        return root + tail
    }

    /// A street with a house number, written the way the country writes it.
    static func street(_ style: String, last rawLast: String, number n: Int, _ r: inout HashedRandom) -> String {
        let last = rawLast.isEmpty ? "Nova" : rawLast
        let compact = last.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "de", with: "", options: .anchored)
        switch style {
        case "german": return compact + pick(["straße", "weg", "allee", "platz"], &r) + " \(n)"
        case "dutch": return compact + pick(["straat", "laan", "weg"], &r) + " \(n)"
        case "norwegian": return compact + pick(["s gate", "veien", "gata"], &r) + " \(n)"
        case "swedish": return compact + pick(["gatan", "vägen"], &r) + " \(n)"
        case "danish": return compact + pick(["s Allé", "vej", "gade"], &r) + " \(n)"
        case "finnish": return compact + pick(["nkatu", "ntie"], &r) + " \(n)"
        case "polish": return "ul. \(last) \(n)"
        case "lithuanian": return "\(last) g. \(n)"
        case "french": return "\(n) " + pick(["Rue", "Avenue", "Boulevard", "Place"], &r) + " \(last)"
        case "spanish": return pick(["Calle", "Avenida", "Paseo"], &r) + " \(last), \(n)"
        case "italian": return pick(["Via", "Corso", "Viale"], &r) + " \(last) \(n)"
        case "portuguese": return pick(["Rua", "Avenida", "Travessa"], &r) + " \(last), \(n)"
        case "japanese":
            let chome: Int = Int(r.next() * 4) + 1
            return "\(last) \(chome)-chome-\(n)"
        case "korean": return "\(last)-ro \(n)"
        case "american": return "\(n) \(last) " + pick(["Street", "Avenue", "Boulevard", "Drive"], &r)
        default: return "\(n) \(last) " + pick(["Street", "Road", "Lane", "Way", "Row"], &r)
        }
    }

    /// The name shown for a listing: street and district, or an estate on the edge of town, or the city centre.
    static func title(seed: Int, country: Country, cityID: String, cityName: String, tier: Int, group: String, week: Int, kind: String) -> String {
        var r = HashedRandom("\(seed):pname:\(country.code):\(cityID):\(group):\(week / 26):\(tier)")
        let lasts = country.pack["names"]["last"].array.map { $0.string }
        let n = Int(r.next() * 60) + 2
        let lastName: String = pick(lasts, &r)
        let st = street(styleOf(country.code), last: lastName, number: n, &r)
        let area = district(country, &r)
        let industrial = ["industrial", "workshop", "warehouse", "yard", "factory", "farm", "mill"].contains(kind)
        switch tier {
        case 0:
            let est = pick(industrial ? ["Industrial Estate", "Trading Estate", "Business Park"] : ["Business Park", "Trading Estate", "Retail Park"], &r)
            return "Unit \(Int(r.next() * 18) + 1), \(area) \(est)"
        case 1: return st + ", " + area
        case 2: return st + ", " + area
        case 3: return st + ", " + cityName + " " + pick(["Old Town", "Quarter", "Market"], &r)
        default: return st + ", " + cityName + " centre"
        }
    }

    /// Which of the three pictures of a kind of place this listing shows: fixed by the listing, varied by its index in the feed.
    static func photoSlot(seed: Int, group: String, index: Int) -> Int {
        var r = HashedRandom("\(seed):pslot:\(group)")
        return (Int(r.next() * 3) + index) % 3
    }
}
