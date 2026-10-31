import Foundation
import GameCore

/// What an employee's portrait needs to know: a stable key, gender, age band and region. The game's people do not store gender or
/// country, so both are derived here (never in views): gender from the first name, region from the country the person works in.
/// Only the look of the portrait depends on this; no game rule reads it. Faces are for people who work in companies (managers,
/// assistants, staff, candidates), not for the player, rivals, the rich list or companies.
public struct FaceTraits: Equatable, Hashable, Sendable {
    /// Stable per person (id and name), the seed for choosing a portrait.
    public var key: String
    /// "F" or "M".
    public var gender: Character
    /// "Y" (under 35), "M" (35 to 54), "O" (55 and over).
    public var ageBand: Character
    /// "S" South Asian, "E" East Asian, "U" European, "A" African, "L" Latino, "W" Middle Eastern; nil when the country is unknown.
    public var region: Character?

    public init(key: String, gender: Character, ageBand: Character, region: Character?) {
        self.key = key; self.gender = gender; self.ageBand = ageBand; self.region = region
    }

    /// The traits of a person who works in `countryCode` (nil: unknown region).
    public static func of(_ p: Person, countryCode: String?) -> FaceTraits {
        of(id: p.id, name: p.name, age: p.age, countryCode: countryCode)
    }

    /// The traits from the fields a read model carries (applicants, search results) when the Person record is not at hand.
    public static func of(id: Int, name: String, age: Int, countryCode: String?) -> FaceTraits {
        let region: Character? = countryCode.flatMap { Self.region(countryCode: $0) }
        return FaceTraits(key: "p\(id)-\(name)", gender: gender(firstName: firstName(name), seed: id), ageBand: ageBand(age), region: region)
    }

    /// For a post-holder known only by name (chain, regional and group people): the age is unknown, so the middle band.
    public static func named(_ name: String, countryCode: String?) -> FaceTraits {
        let seed = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 1_000_003 }
        return of(id: seed, name: name, age: 45, countryCode: countryCode)
    }

    public static func ageBand(_ age: Int) -> Character { age < 35 ? "Y" : age < 55 ? "M" : "O" }

    static func firstName(_ full: String) -> String {
        let s = full.trimmingCharacters(in: .whitespaces)
        return s.split(separator: " ").first.map(String.init) ?? s
    }

    // MARK: Gender from the first name (stand-in lookup: the person record has no gender field)

    /// Women's first names from the game's country name lists (Countries/Resources/countries.json). Two-word names are matched on the first word.
    static let femaleNames: Set<String> = [
        "Agnieszka", "Agnė", "Aino", "Aisha", "Alice", "Alma", "Amanda", "Amelia", "Ana", "Anjali", "Anke", "Anna", "Anouk", "Aoife", "Aurora",
        "Austėja", "Ava", "Beatrice", "Beatriz", "Camila", "Camilla", "Carmen", "Charlotte", "Chiara", "Chloe", "Chloé", "Ciara", "Clara",
        "Daniela", "Eevi", "Eglė", "Elena", "Elin", "Elise", "Ella", "Ellie", "Emi", "Emily", "Emma", "Eun-ji", "Eunji", "Eva", "Ewa",
        "Fatima", "Fernanda", "Fiadh", "Fiona", "Francesca", "Freja", "Frida", "Georgia", "Giedrė", "Ginevra", "Gintarė", "Giulia", "Grace",
        "Guadalupe", "Ha-eun", "Haeun", "Hanna", "Hannah", "Hanne", "Helena", "Helmi", "Hessa", "Hina", "Ida", "Ieva", "Indrė", "Ingrid",
        "Inès", "Iris", "Isabel", "Isabella", "Isabelle", "Isla", "Jennifer", "Jessica", "Joanna", "Johanna", "Josefin", "Julia", "Juliana",
        "Julie", "Jurgita", "Júlia", "Kaisa", "Karin", "Karla", "Karolina", "Katarzyna", "Katharina", "Kavya", "Kristina", "Larissa", "Laura",
        "Lauren", "Layla", "Lea", "Lena", "Lene", "Linda", "Lina", "Linn", "Linnea", "Lise", "Live", "Lotte", "Louise", "Lucy", "Lucía", "Léa",
        "Magdalena", "Maja", "Manon", "Manuela", "Maria", "Mariam", "Mariana", "Marie", "Marloes", "Marta", "Marte", "Martina", "Mary",
        "María", "Małgorzata", "Megan", "Mei", "Mette", "Mia", "Milda", "Min-seo", "Minseo", "Moa", "Monika", "Nana",
        "Nanami", "Natalia", "Niamh", "Nina", "Noor", "Noora", "Nora", "Noura", "Nur", "Nuria", "Olivia", "Ona", "Paola", "Paula",
        "Poppy", "Priya", "Rachel", "Randi", "Regina", "Riikka", "Róisín", "Rūta", "Ruby", "Sakura", "Sanna", "Sanne", "Sara", "Sarah",
        "Seo-yeon", "Seoyeon", "Shamma", "Shi", "Silje", "Siobhán", "Siti", "Sofia", "Sofie", "Sofía", "Soo-ah", "Sophia", "Sophie",
        "Soyeon", "Tess", "Thea", "Valentina", "Valeria", "Venla", "Vilde", "Weronika", "Ximena", "Xin", "Yui", "Yuna", "Zoe", "Zofia", "Élise",
    ]
    /// Names used by both sexes: decided by the person's id, so the same person always gets the same answer.
    static let unisexNames: Set<String> = [
        "Andrea", "Aoi", "Camille", "Charlie", "Chris", "Jesse", "Kai", "Max", "Nico", "Rin", "Ren", "Ola", "Kari", "Jules", "Hyun", "Joon",
        "Jiho", "Ji-woo", "Jiwoo", "Cooper", "Logan", "Ashley", "Hunter", "Mason", "Jayden", "Tyler",
    ]

    public static func gender(firstName: String, seed: Int) -> Character {
        if femaleNames.contains(firstName) { return "F" }
        if unisexNames.contains(firstName) { return abs(seed % 1000) % 2 == 0 ? "F" : "M" }
        return "M"
    }

    // MARK: Region from the country

    static let regionByCountry: [String: Character] = {
        var m: [String: Character] = [:]
        for c in "GB UK IE DE FR NO SE PL LT ES NL CH IT DK FI AT BE PT CZ US CA AU NZ".split(separator: " ") { m[String(c)] = "U" }
        for c in "IN PK BD LK NP".split(separator: " ") { m[String(c)] = "S" }
        for c in "CN JP KR VN TH PH SG MY ID TW HK".split(separator: " ") { m[String(c)] = "E" }
        for c in "NG GH KE ZA ET TZ".split(separator: " ") { m[String(c)] = "A" }
        for c in "BR MX CO AR CL PE".split(separator: " ") { m[String(c)] = "L" }
        for c in "TR EG SA AE IR IQ QA KW JO".split(separator: " ") { m[String(c)] = "W" }
        return m
    }()

    /// The portrait region of a country code; nil for an unknown country (any portrait will do).
    public static func region(countryCode: String) -> Character? { regionByCountry[countryCode.uppercased()] }
}
